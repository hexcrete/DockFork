#!/usr/bin/env ruby
# Compile the production key-press gate and Space matcher without posting events.
require 'tmpdir'

def block(source, signature)
  start = source.index(signature) or abort "Missing #{signature}"
  opening = source.index(/\{\n/, start)
  depth = 0
  (opening...source.length).each do |i|
    depth += 1 if source[i] == '{'
    depth -= 1 if source[i] == '}'
    return source[start..i] if depth.zero?
  end
  abort "Unclosed #{signature}"
end

root = File.expand_path('../..', __dir__)
keybinds = File.read("#{root}/DockDoor/Utilities/KeybindHelper.swift")
constants = File.read("#{root}/DockDoor/consts.swift")
handler = block(keybinds, '    private func handleEvent(')
gate_start = handler.index('        // Keep consumed action keys suppressed') or abort 'Missing early physical-key gate'
gate_end = handler.index('        if previewCoordinator.tapSnapshot.isPresentationSuspended') or abort 'Missing modal guard'
abort 'Key-up and repeat handling must precede modal/UI guards' unless gate_start < gate_end
early_gate = handler[gate_start...gate_end]
abort 'Key-up must clear only its own action key' unless early_gate.include?('if type == .keyUp') && early_gate.include?('actionKeyPressState.release(keyCode:')

routes = {
  'context menu' => block(handler, '            if let routing = previewCoordinator.contextMenuShortcutRoutingSnapshot(),'),
  'numbered Spaces' => block(handler, '            if let spaceNumber = numberedSpaceShortcut(event: event),'),
  'Cmd+Tab app/preview' => block(handler, '                            if hasSelection || action == .selectAllWindows || canTileCheckedWindows ||'),
  'regular preview' => block(keybinds, '                if let action = getActionForPreviewShortcut(keyCode: keyCode),')
}
routes.each do |label, route|
  abort "#{label} does not consume recognized repeats" unless route.include?('guard actionKeyPressState.begin(keyCode: keyCode, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0')
  dispatch = [route.index('Task {'), route.index('preventSwitcherHideOnRelease ='), route.index('cmdTabActionPerformed =')].compact.min
  abort "#{label} starts work before repeat admission" unless dispatch && route.index('actionKeyPressState.begin(') < dispatch
end
abort 'Navigation/search must not claim action keys' unless keybinds.scan('actionKeyPressState.begin(').size == routes.size
abort 'Tap teardown must clear key state' unless block(keybinds, '    private func removeEventTap(').include?('actionKeyPressState.reset()')
abort 'Tap recovery must clear key state' unless handler[0...gate_start].include?('actionKeyPressState.reset()')
matcher = block(keybinds, '    private func numberedSpaceShortcut(')
abort 'Space matching must recognize repeats before execution rejects them' if matcher.include?('keyboardEventAutorepeat')

source = "import AppKit\nimport Carbon\n"
source += block(keybinds, 'private final class PreviewActionKeyPressState {') + "\n"
source += "enum WindowSwitcherShortcutResolver {\n"
source += block(constants, '    static func spaceNumber(forPhysicalKeyCode') + "\n"
source += block(constants, '    static func normalizedModifiers(') + "\n}\n"
source += <<~'SWIFT'
enum Key { case enableSpacesShortcuts }
enum Defaults { static var enabled = true; static subscript(_ key: Key) -> Bool { enabled } }
struct UserKeyBind { var modifierFlags = Int(CGEventFlags.maskAlternate.rawValue) }
final class Coordinator {
 var keybind = UserKeyBind()
 func effectivePreviewShortcutKeybind(forSpaces: Bool) -> UserKeyBind { keybind }
}
private final class Harness {
 let actionKeyPressState = PreviewActionKeyPressState()
 let previewCoordinator = Coordinator()
 var acceptsSide = true
 func modifierSideMatches(_ keybind: UserKeyBind) -> Bool { acceptsSide }
 func match(_ event: CGEvent) -> Int? { numberedSpaceShortcut(event: event) }
 func forward(_ event: CGEvent) -> CGEvent? {
  let type = event.type
SWIFT
source += early_gate + "_ = releasedActionPress\nreturn event\n}\n" + matcher + "\n}\n"
source += <<~'SWIFT'
func event(_ code: Int, repeat repeated: Bool = false, up: Bool = false, flags: CGEventFlags = .maskAlternate) -> CGEvent {
 let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: !up)!
 event.flags = flags
 event.setIntegerValueField(.keyboardEventAutorepeat, value: repeated ? 1 : 0)
 return event
}
@main struct Checks {
 static func main() {
  let h = Harness(), state = h.actionKeyPressState
  for code in [kVK_ANSI_M, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_Q, kVK_ANSI_1] {
   precondition(h.forward(event(code)) != nil)
   precondition(state.begin(keyCode: Int64(code), isRepeat: false))
   for flags: CGEventFlags in [.maskAlternate, .maskCommand, []] {
    for _ in 0..<30 { precondition(h.forward(event(code, repeat: true, flags: flags)) == nil) }
   }
   precondition(h.forward(event(code, up: true, flags: [])) != nil)
   precondition(h.forward(event(code, repeat: true)) != nil)
   precondition(!state.begin(keyCode: Int64(code), isRepeat: true))
   precondition(h.forward(event(code, repeat: true)) == nil)
   precondition(h.forward(event(code)) != nil, "Fresh physical down must clear a missed release")
  }
  for code in [kVK_Tab, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_ANSI_H, kVK_ANSI_A, kVK_Space] {
   precondition(h.forward(event(code)) != nil)
   for _ in 0..<30 { precondition(h.forward(event(code, repeat: true)) != nil) }
  }
  precondition(state.begin(keyCode: Int64(kVK_ANSI_M), isRepeat: false))
  precondition(state.begin(keyCode: Int64(kVK_ANSI_W), isRepeat: false))
  _ = h.forward(event(kVK_ANSI_W, up: true))
  precondition(h.forward(event(kVK_ANSI_M, repeat: true)) == nil, "Another key release cleared the held action")
  state.reset()
  precondition(h.forward(event(kVK_ANSI_M, repeat: true)) != nil)
  precondition(state.begin(keyCode: 14, isRepeat: false, timestamp: 100))
  precondition(state.isHeld(keyCode: 14, timestamp: 100))
  precondition(state.release(keyCode: 14) == 100)
  precondition(state.begin(keyCode: 14, isRepeat: false, timestamp: 200))
  precondition(!state.isHeld(keyCode: 14, timestamp: 100) && state.isHeld(keyCode: 14, timestamp: 200))
  state.reset()
  let numbers = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]
  for (index, code) in numbers.enumerated() {
   for repeated in [false, true] { precondition(h.match(event(code, repeat: repeated)) == index + 1) }
   precondition(h.match(event(code, flags: .maskCommand)) == nil)
   precondition(h.match(event(code, flags: [.maskAlternate, .maskAlphaShift])) == index + 1)
  }
  Defaults.enabled = false
  precondition(h.match(event(kVK_ANSI_1, repeat: true)) == nil)
  Defaults.enabled = true
  h.acceptsSide = false
  precondition(h.match(event(kVK_ANSI_1)) == nil)
  h.acceptsSide = true
  h.previewCoordinator.keybind.modifierFlags = 0
  precondition(h.match(event(kVK_ANSI_1, flags: [])) == nil)
  precondition(h.match(event(kVK_ANSI_A)) == nil)
  DispatchQueue.concurrentPerform(iterations: 64) { index in
   let key = Int64(1000 + index)
   precondition(state.begin(keyCode: key, isRepeat: false))
   precondition(state.consumeRepeat(keyCode: key, isRepeat: true))
   state.release(keyCode: key)
   precondition(!state.consumeRepeat(keyCode: key, isRepeat: true))
  }
  state.reset()
  print("PASS production physical-key gate: repeat suppression through dismissal/modifier changes, fresh presses, missed releases, independent keys, reset and concurrent cleanup; navigation/typing remain unclaimed")
  print("PASS production Space matching: all ten numbers, repeat recognition without execution, modifiers, physical-side refusal and disabled behavior; four action routes gated before dispatch")
 }
}
SWIFT
Dir.mktmpdir('dockfork-preview-keyboard-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Preview keyboard fixture compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Preview keyboard checks failed' unless system("#{dir}/checks")
end

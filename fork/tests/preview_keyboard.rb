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

conflicts = <<~'SWIFT'
import AppKit
import Carbon
enum ModifierKeySide { case either, left, right }
struct UserKeyBind {
 var keyCode: UInt16
 var modifierFlags: Int
 var modifierSide: ModifierKeySide = .either
}
enum AlternateSwitcherShortcutConflict { case spacesShortcut, duplicate, previewAction }
struct GlobalShortcut { let keyCode: UInt16; let modifierFlags: Int; let doubleTapKey: Int? = nil }
enum Defaults {
 struct Key<T> { let read:()->T }
 static subscript<T>(_ key:Key<T>)->T {key.read()}
 static var forward:UInt16 = .max, backward:UInt16 = .max
 static var previews:[UserKeyBind]=[], alternates:[UserKeyBind]=[], persistent:[GlobalShortcut]=[], last:[GlobalShortcut]=[]
}
extension Defaults.Key where T == UInt16 {
 static var spacesBarCycleKey:Self{Self(read:{Defaults.forward})}
 static var spacesBarBackwardCycleKey:Self{Self(read:{Defaults.backward})}
 static var switcherBackwardKeyCode:Self{Self(read:{56})}
 static var windowSwitcherSelectionKeyCode:Self{Self(read:{36})}
}
extension Defaults.Key where T == [UserKeyBind] {
 static var cmdShortcuts:Self{Self(read:{Defaults.previews})}
 static var alternateSwitcherShortcuts:Self{Self(read:{Defaults.alternates})}
}
extension Defaults.Key where T == [GlobalShortcut] {
 static var persistentSwitcherShortcuts:Self{Self(read:{Defaults.persistent})}
 static var lastFocusedWindowShortcuts:Self{Self(read:{Defaults.last})}
}
struct ResolvedAlternate {let keybind:UserKeyBind}
enum WindowSwitcherShortcutResolver {
 static var spacesReserved = false
 static func conflictsWithSpacesShortcut(keyCode:UInt16,modifierFlags:Int,modifierSide:ModifierKeySide,mainKeybind:UserKeyBind)->Bool {spacesReserved && keyCode==18 && modifierFlags==mainKeybind.modifierFlags}
 static func heldShortcutOverlaps(_ candidate:UserKeyBind,initializer:UserKeyBind)->Bool {combinationsMatch(candidate,initializer)}
 static func resolvedPreviewShortcuts(_ shortcuts:[UserKeyBind],previewKeybind:UserKeyBind,mainKeybind:UserKeyBind)->[UserKeyBind]{shortcuts}
 static func resolvedAlternateShortcuts(_ shortcuts:[UserKeyBind],mainKeybind:UserKeyBind,previewShortcuts:[UserKeyBind])->[ResolvedAlternate]{shortcuts.map{ResolvedAlternate(keybind:$0)}}
 static func resolvedPersistentShortcuts(_ shortcuts:[GlobalShortcut],mainKeybind:UserKeyBind,alternateShortcuts:[UserKeyBind],previewShortcuts:[UserKeyBind])->[GlobalShortcut]{shortcuts}
 static func resolvedLastFocusedShortcuts(_ shortcuts:[GlobalShortcut],mainKeybind:UserKeyBind,alternateShortcuts:[UserKeyBind],persistentShortcuts:[GlobalShortcut],previewShortcuts:[UserKeyBind])->[GlobalShortcut]{shortcuts}
SWIFT
%w[spaceCycleConflict combinationsMatch sidesOverlap normalizedModifiers].each do |name|
  signature = name == 'combinationsMatch' || name == 'sidesOverlap' ? "    private static func #{name}(" : "    static func #{name}("
  conflicts += block(constants, signature) + "\n"
end
conflicts += <<~'SWIFT'
}
@main struct ConflictChecks {
 static func main() {
 let main=UserKeyBind(keyCode:48,modifierFlags:Int(CGEventFlags.maskAlternate.rawValue))
 func check(_ code:UInt16,_ expected:AlternateSwitcherShortcutConflict?,backward:Bool=false,keybind:UserKeyBind?=nil) {
  if backward {Defaults.backward=code} else {Defaults.forward=code}
  precondition(WindowSwitcherShortcutResolver.spaceCycleConflict(backward:backward,previewKeybind:keybind ?? main,mainKeybind:main)==expected)
 }
 check(.max,nil)
 check(48,.duplicate)
 check(36,.duplicate)
 WindowSwitcherShortcutResolver.spacesReserved=true
 check(18,.spacesShortcut)
 WindowSwitcherShortcutResolver.spacesReserved=false
 Defaults.previews=[UserKeyBind(keyCode:0,modifierFlags:main.modifierFlags)]
 check(0,.previewAction)
 Defaults.alternates=[UserKeyBind(keyCode:1,modifierFlags:main.modifierFlags,modifierSide:.left)]
 check(1,.duplicate)
 check(1,nil,keybind:UserKeyBind(keyCode:48,modifierFlags:main.modifierFlags,modifierSide:.right))
 Defaults.persistent=[GlobalShortcut(keyCode:2,modifierFlags:main.modifierFlags)]
 check(2,.duplicate)
 Defaults.last=[GlobalShortcut(keyCode:3,modifierFlags:main.modifierFlags)]
 check(3,.duplicate)
 check(4,nil)
 check(4,.duplicate,backward:true)
 check(2,nil,keybind:UserKeyBind(keyCode:48,modifierFlags:Int(CGEventFlags.maskCommand.rawValue)))
 print("PASS production Space-cycle conflict policy: unassigned, reserved/navigation, numbered Spaces, preview actions, alternate/persistent/last-focused bindings, duplicates and modifier sides/session modifiers")
 }
}
SWIFT
Dir.mktmpdir('dockfork-cycle-conflicts-') do |dir|
 File.write("#{dir}/checks.swift",conflicts)
 abort 'Space-cycle conflict compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Space-cycle conflicts failed' unless system("#{dir}/checks")
end

# Exercise the production script adapter and early-release branch without mutating windows.
require 'rexml/document'
scripts = File.read("#{root}/DockDoor/Utilities/ScriptCommands.swift")
dictionary = REXML::Document.new(File.read("#{root}/DockDoor/DockDoor.sdef"))
show = REXML::XPath.first(dictionary, '//command[@name="show switcher"]')
abort 'Show Switcher command code changed' unless show.attributes['code'] == 'DKDRshsw'
parameter = show.elements['parameter[@name="spaces focused"]']
abort 'Missing optional Spaces focus parameter' unless parameter && %w[code type optional].map { |key| parameter.attributes[key] } == ['spfc', 'boolean', 'yes']
release = block(keybinds, '    private func selectOnSwitcherRelease()')
abort 'Pending Space release must precede window activation' unless release.index('activatePendingSpaceNavigation()') < release.index('selectAndBringToFrontCurrentWindow()')
abort 'Space entry must be tied to native presentation' unless File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift").include?('navigateSpaces(pending.request)')
launch = <<~'SWIFT'
import Foundation
class NSScriptCommand {
 var evaluatedArguments: [String:Any]?
 func performDefaultImplementation() -> Any? { nil }
}
enum Key { case enableWindowSwitcher, enableSpacesBar }
enum Defaults {
 static var switcher = true, bar = true
 static subscript(_ key:Key) -> Bool { key == .enableWindowSwitcher ? switcher : bar }
}
enum DockDoorCommands {
 static var requests: [Bool] = []
 static func showSwitcherAsync(spacesFocused:Bool = false) { requests.append(spacesFocused) }
}
SWIFT
launch += block(scripts, 'class ShowSwitcherCommand:') + "\n"
launch += <<~'SWIFT'
enum PreviewStateCoordinator { enum SpaceNavigationRequest: Equatable { case current, cycle(backward:Bool) } }
@MainActor final class SharedPreviewWindowCoordinator {
 final class Coordinator {
  var windowSwitcherActive = false
  var pendingSpaceNavigation: (request:PreviewStateCoordinator.SpaceNavigationRequest,screen:Int)?
 }
 let windowSwitcherCoordinator = Coordinator()
 var isVisible = false
 var presented: [PreviewStateCoordinator.SpaceNavigationRequest] = []
 func navigateSpaces(_ request:PreviewStateCoordinator.SpaceNavigationRequest) { presented.append(request) }
}
@MainActor final class NavigationLaunchProbe {
 func getTargetScreenForSwitcher() -> Int { 42 }
SWIFT
launch += block(keybinds, '    func navigateSpaces(previewCoordinator:') + "\n}\n"
launch += <<~'SWIFT'
@MainActor final class Preview {
 struct Coordinator { var selectionSuppressesRelease = false; var windowSwitcherActive = true }
 var windowSwitcherCoordinator = Coordinator()
 var isVisible = false, pending = false
 var result: String?
 var didFinish: (() -> Void)?
 func activatePendingSpaceNavigation() -> Bool {
  guard pending else { return false }; pending = false; finish("space"); return true
 }
 func selectAndBringToFrontCurrentWindow() { finish("visible-window") }
 func hideWindow() { finish("hidden-window") }
 func finish(_ value:String) { result = value; didFinish?(); didFinish = nil }
}
struct Window { func bringToFront() {}; func warpMouseToCenterIfNeeded() {} }
@MainActor final class Switching {
 var currentSessionId = 1
 func cancelPendingRender() { currentSessionId += 1 }
 func selectCurrentWindow(previewCoordinator:Preview) -> Window? { Window() }
 func cancelSwitching(previewCoordinator:Preview) {}
}
@MainActor final class ReleaseProbe {
 let previewCoordinator = Preview()
 let windowSwitchingCoordinator = Switching()
 func run() { selectOnSwitcherRelease() }
SWIFT
launch += release + "\n}\n"
launch += <<~'SWIFT'
@main struct LaunchChecks {
 @MainActor static func main() async {
  let navigation = NavigationLaunchProbe(), preview = SharedPreviewWindowCoordinator()
  navigation.navigateSpaces(previewCoordinator:preview,request:.cycle(backward:true))
  precondition(preview.windowSwitcherCoordinator.pendingSpaceNavigation?.screen == 42 && preview.presented.isEmpty)
  navigation.navigateSpaces(previewCoordinator:preview,request:.current)
  precondition(preview.windowSwitcherCoordinator.pendingSpaceNavigation?.request == .current, "Repeated requests before presentation replace the pending intent")
  preview.isVisible = true; preview.windowSwitcherCoordinator.windowSwitcherActive = true
  navigation.navigateSpaces(previewCoordinator:preview,request:.current)
  precondition(preview.presented == [.current] && preview.windowSwitcherCoordinator.pendingSpaceNavigation == nil, "Visible sessions must focus directly and consume pending intent without a delay or reopening")
  let script = ShowSwitcherCommand()
  precondition(script.performDefaultImplementation() as? String == "ok" && DockDoorCommands.requests == [false])
  script.evaluatedArguments = ["spacesFocused":true]
  precondition(script.performDefaultImplementation() as? String == "ok" && DockDoorCommands.requests == [false,true])
  for disabled in [Key.enableWindowSwitcher,.enableSpacesBar] {
   Defaults.switcher = disabled != .enableWindowSwitcher; Defaults.bar = disabled != .enableSpacesBar
   precondition((script.performDefaultImplementation() as? String)?.hasPrefix("error:") == true)
   precondition(DockDoorCommands.requests == [false,true], "Refused requests cannot launch")
  }
  for (pending,visible,expected) in [(true,false,"space"),(true,true,"space"),(false,true,"visible-window"),(false,false,"hidden-window")] {
   let probe = ReleaseProbe()
   probe.previewCoordinator.pending = pending; probe.previewCoordinator.isVisible = visible
   await withCheckedContinuation { continuation in
    probe.previewCoordinator.didFinish = { continuation.resume() }; probe.run()
   }
   precondition(probe.previewCoordinator.result == expected, "Quick Space release must never activate a window")
  }
  let protected = ReleaseProbe()
  protected.previewCoordinator.windowSwitcherCoordinator.selectionSuppressesRelease = true
  protected.run()
  precondition(protected.windowSwitchingCoordinator.currentSessionId == 1, "Selection release policy remains unchanged")
  print("PASS production Spaces launch: optional script argument, disabled refusal, quick-release destination priority, normal window fallbacks and selection-release ownership")
 }
}
SWIFT
Dir.mktmpdir('dockfork-spaces-launch-') do |dir|
 File.write("#{dir}/checks.swift",launch)
 abort 'Spaces launch compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Spaces launch checks failed' unless system("#{dir}/checks")
end

state = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift")
panel = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
navigation = "import Foundation\ntypealias CGSSpaceID = UInt64\nenum PreviewStateCoordinator {\n" + block(state, '    enum SpaceNavigationRequest:') + "\n}\n"
navigation += <<~'SWIFT'
enum Input { case programmatic, keyboard }
enum Target: Equatable { case windows, space(UInt64) }
enum Defaults { enum Key { case spacesBarStartOnNext }; static var startNext = true; static subscript(_ key:Key) -> Bool {startNext} }
enum NSEvent { static let mouseLocation = CGPoint(x:10,y:20) }
enum NSSound { static var beeps = 0; static func beep() {beeps += 1} }
enum WindowSpaces { static func screen(forDisplayIdentifier id:String) -> Int? {Int(id)} }
struct Entry { let id:UInt64; let isCurrent:Bool }
struct Display { let id:String; let spaces:[Entry] }
final class Coordinator {
 var windowSwitcherActive = true, hasMovedSinceOpen = true
 var index = 0
 var initialHoverLocation:CGPoint?
 var spaceNavigationInputSource = Input.programmatic
 var navigationTarget = Target.windows
 func setIndex(to index:Int, shouldScroll:Bool, source:Input) {self.index = index}
 func endSelectionRange() {}
}
@MainActor final class NavigationProbe {
 let windowSwitcherCoordinator = Coordinator()
 var spacesBarWindow:Int? = 1
 var panelAnchor:(screen:Int,unused:Bool)? = (2,false)
 let screen:Int? = 1
 var spacesBarSections = [Display(id:"1",spaces:[Entry(id:10,isCurrent:true),Entry(id:20,isCurrent:false)]),Display(id:"2",spaces:[Entry(id:30,isCurrent:true),Entry(id:40,isCurrent:false)])]
 var highlightedSpaceID:UInt64? {if case let .space(id) = windowSwitcherCoordinator.navigationTarget {return id};return nil}
 var searchFocused = true
 func unfocusSearchWindow() {searchFocused = false}
SWIFT
navigation += block(panel, '    func navigateSpaces(_ request:') + "\n}\n"
navigation += <<~'SWIFT'
@main struct NavigationChecks {
 @MainActor static func main() {
  let probe = NavigationProbe(), coordinator = probe.windowSwitcherCoordinator
  probe.navigateSpaces(.current)
  precondition(probe.highlightedSpaceID == 30 && coordinator.index == -1 && !probe.searchFocused, "Current entry must use invocation display without leaving a stale window target")
  probe.navigateSpaces(.cycle(backward:false)); precondition(probe.highlightedSpaceID == 40)
  probe.navigateSpaces(.cycle(backward:false)); precondition(probe.highlightedSpaceID == 10)
  probe.navigateSpaces(.cycle(backward:true)); precondition(probe.highlightedSpaceID == 40)
  coordinator.windowSwitcherActive = false; coordinator.index = 5
  probe.navigateSpaces(.current); precondition(coordinator.index == 5)
  coordinator.windowSwitcherActive = true; coordinator.navigationTarget = .windows; probe.spacesBarWindow = nil
  probe.navigateSpaces(.current)
  precondition(coordinator.index == -1 && NSSound.beeps == 1, "Unavailable/hidden bar must not leave a window selected for initializer release")
  print("PASS production Space navigation: invocation-display current entry, wrap/direction, search/window focus separation, session guard and unavailable-bar refusal")
 }
}
SWIFT
Dir.mktmpdir('dockfork-spaces-navigation-') do |dir|
 File.write("#{dir}/checks.swift",navigation)
 abort 'Space navigation compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Space navigation checks failed' unless system("#{dir}/checks")
end

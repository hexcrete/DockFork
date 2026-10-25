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
startup = block(keybinds, '    private func initializeWindowSwitching(')
abort 'Fresh switcher startup must cancel pending Dock presentation before replacing its windows' unless startup.index('previewCoordinator.cancelPendingShow()') < startup.index('let windows = buildSwitcherWindows(')
abort 'Fresh switcher startup must dismiss a visible non-switcher through shared cleanup before initializing rows' unless startup.include?('if previewCoordinator.isVisible, !previewCoordinator.windowSwitcherCoordinator.windowSwitcherActive {') && startup.index('previewCoordinator.hideWindow()') < startup.index('coordinator.initializeForWindowSwitcher(')
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
 static var search:UInt16 = 44
 static var bar = false, vim = false
 static var previews:[UserKeyBind]=[], alternates:[UserKeyBind]=[], persistent:[GlobalShortcut]=[], last:[GlobalShortcut]=[]
}
extension Defaults.Key where T == UInt16 {
 static var spacesBarCycleKey:Self{Self(read:{Defaults.forward})}
 static var spacesBarBackwardCycleKey:Self{Self(read:{Defaults.backward})}
 static var searchTriggerKey:Self{Self(read:{Defaults.search})}
 static var switcherBackwardKeyCode:Self{Self(read:{56})}
 static var windowSwitcherSelectionKeyCode:Self{Self(read:{36})}
}
extension Defaults.Key where T == Bool {
 static var enableSpacesBar:Self{Self(read:{Defaults.bar})}
 static var enableVimMotions:Self{Self(read:{Defaults.vim})}
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
%w[spaceCycleConflict searchTriggerConflict dependentKeyConflict combinationsMatch sidesOverlap normalizedModifiers].each do |name|
  signature = %w[dependentKeyConflict combinationsMatch sidesOverlap].include?(name) ? "    private static func #{name}(" : "    static func #{name}("
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
 Defaults.previews=[];Defaults.alternates=[];Defaults.persistent=[];Defaults.last=[]
 func search(_ code:UInt16,_ expected:AlternateSwitcherShortcutConflict?,side:ModifierKeySide = .either) {
  Defaults.search=code
  let keybind=UserKeyBind(keyCode:48,modifierFlags:main.modifierFlags,modifierSide:side)
  precondition(WindowSwitcherShortcutResolver.searchTriggerConflict(previewKeybind:keybind,mainKeybind:main)==expected)
 }
 search(44,nil);search(48,.duplicate);search(UInt16(kVK_LeftArrow),.duplicate)
 WindowSwitcherShortcutResolver.spacesReserved=true;search(18,.spacesShortcut);WindowSwitcherShortcutResolver.spacesReserved=false
 Defaults.previews=[UserKeyBind(keyCode:0,modifierFlags:main.modifierFlags)];search(0,.previewAction);Defaults.previews=[]
 Defaults.alternates=[UserKeyBind(keyCode:1,modifierFlags:main.modifierFlags,modifierSide:.left)]
 search(1,.duplicate,side:.left);search(1,nil,side:.right);search(1,.duplicate,side:.either);Defaults.alternates=[]
 Defaults.persistent=[GlobalShortcut(keyCode:2,modifierFlags:main.modifierFlags)];search(2,.duplicate);Defaults.persistent=[]
 Defaults.last=[GlobalShortcut(keyCode:3,modifierFlags:main.modifierFlags)];search(3,.duplicate);Defaults.last=[]
 Defaults.forward=4;Defaults.backward=5;Defaults.bar=true;search(4,.duplicate);search(5,.duplicate)
 Defaults.bar=false;search(4,nil)
 Defaults.vim=true;search(UInt16(kVK_ANSI_H),.duplicate);Defaults.vim=false;search(UInt16(kVK_ANSI_H),nil)
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

swipe = File.read("#{root}/DockDoor/Utilities/TrackpadSwipeTrigger.swift")
swipe_source = "import Foundation\n" + block(swipe, 'struct SwipeTouch {') + "\n" + block(swipe, 'enum TrackpadSwipeEvent:') + "\n" + block(swipe, 'struct TrackpadSwipeDetector {') + "\n"
swipe_source += block(File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift"), '    enum SpaceNavigationRequest:').gsub('CGSSpaceID','UInt64') + "\n"
route = block(keybinds, '    private func handleTrackpadSwipe(')
intent = route[route.index('                var openingBackward:')...route.index('                guard !spaces ||')]
swipe_source += "func swipeIntent(_ event:TrackpadSwipeEvent)->(opens:Bool,spaces:Bool,backward:Bool) {\n" + intent + "return (opens,spaces,backward)\n}\n"
swipe_source += <<~'SWIFT'
func touches(_ x: CGFloat, _ y: CGFloat, _ count: Int = 3) -> [SwipeTouch] {
 (0..<count).map { SwipeTouch(id:$0,position:CGPoint(x:0.3+x+CGFloat($0)*0.02,y:0.3+y)) }
}
@main struct SwipeChecks {
 static func main() {
  for horizontal in [false,true] {
   for fingers in [3,4] {
    for enabled in [false,true] {
     for opposite in [false,true] {
      let axis = opposite ? !horizontal : horizontal
      var detector = TrackpadSwipeDetector()
      precondition(detector.handle(touches(0,0,fingers),fingers:fingers,horizontal:horizontal,spacesEnabled:enabled)==nil)
      let opened = detector.handle(touches(axis ? 0.04:0,axis ? 0:-0.04,fingers),fingers:fingers,horizontal:horizontal,spacesEnabled:enabled)
      if opposite && !enabled { precondition(opened==nil);continue }
      precondition(opened == (opposite ? .openSpaces(backward:false):.open))
      let cycle = detector.handle(touches(axis ? 0.20:0,axis ? 0:-0.20,fingers),fingers:fingers,horizontal:horizontal,spacesEnabled:enabled)
      precondition(cycle == (opposite ? .cycleSpaceForward:.cycleForward),"Right/down must preserve existing forward convention")
      let back = detector.handle(touches(axis ? 0.14:0,axis ? 0:-0.14,fingers),fingers:fingers,horizontal:horizontal,spacesEnabled:enabled)
      precondition(back == (opposite ? .cycleSpaceBackward:.cycleBackward))
      precondition(detector.handle([],fingers:fingers,horizontal:horizontal,spacesEnabled:enabled)==.release)
      precondition(!detector.isSwitching)
     }
    }
   }
  }
  var detector=TrackpadSwipeDetector()
  _=detector.handle(touches(0,0),fingers:3,horizontal:true,spacesEnabled:true)
  precondition(detector.handle(touches(0.04,0.035),fingers:3,horizontal:true,spacesEnabled:true)==nil,"Ambiguous diagonal must not choose a target")
  precondition(detector.handle(touches(0.01,-0.06),fingers:3,horizontal:true,spacesEnabled:true)==.openSpaces(backward:false))
  precondition(detector.handle(touches(0.3,-0.07),fingers:3,horizontal:true,spacesEnabled:true)==nil,"A latched vertical gesture must ignore later dominant horizontal travel")
  precondition(detector.handle(touches(0.3,-0.23),fingers:3,horizontal:false,spacesEnabled:false)==.cycleSpaceForward,"Axis/target remain latched through settings changes")
  precondition(detector.handle([],fingers:3,horizontal:true,spacesEnabled:true)==.release)
  _=detector.handle(touches(0,0),fingers:3,horizontal:true,spacesEnabled:true)
  precondition(detector.handle(touches(0.04,0),fingers:3,horizontal:true,spacesEnabled:true)==.open,"New gesture can choose a different axis")
  for sensitivity:CGFloat in [0.5,1,2] {
   var d=TrackpadSwipeDetector()
   _=d.handle(touches(0,0),fingers:3,horizontal:false,sensitivity:sensitivity,spacesEnabled:true)
   precondition(d.handle(touches(0.031/sensitivity,0),fingers:3,horizontal:false,sensitivity:sensitivity,spacesEnabled:true)==.openSpaces(backward:false))
  }
  for (forward,backward) in [(TrackpadSwipeEvent.cycleForward,TrackpadSwipeEvent.cycleBackward),(.cycleSpaceForward,.cycleSpaceBackward)] {
   precondition(forward.reversingSelection(if:true)==backward && backward.reversingSelection(if:true)==forward)
   precondition(forward.reversingSelection(if:false)==forward)
  }
  for event in [TrackpadSwipeEvent.open,.release,.cancel] {precondition(event.reversingSelection(if:true)==event)}
for configuredHorizontal in [false,true] {
 for fingers in [3,4] {
  for positive in [false,true] {
   let gestureHorizontal = !configuredHorizontal
   let delta:CGFloat = positive ? 0.04:-0.04
   var d=TrackpadSwipeDetector()
   _=d.handle(touches(0,0,fingers),fingers:fingers,horizontal:configuredHorizontal,spacesEnabled:true)
   let opening=d.handle(touches(gestureHorizontal ? delta:0,gestureHorizontal ? 0:delta,fingers),fingers:fingers,horizontal:configuredHorizontal,spacesEnabled:true)!
   let rawBackward=gestureHorizontal ? !positive:positive
   precondition(opening == .openSpaces(backward:rawBackward),"Left/up must open backwards; right/down forwards")
   for reverse in [false,true] {
    let intent=swipeIntent(opening.reversingSelection(if:reverse))
    precondition(intent.opens && intent.spaces && intent.backward == (reverse ? !rawBackward:rawBackward))
    let request=SpaceNavigationRequest.cycle(backward:intent.backward)
    precondition(request.targetIndex(ids:[10,20,30],current:20,highlighted:nil,startNext:false)==1,"Start-next Off must remain on the current Space")
    precondition(request.targetIndex(ids:[10,20,30],current:20,highlighted:nil,startNext:true)==(intent.backward ? 0:2),"Start-next must follow the opening direction, including reversal")
   }
  }
 }
}
  precondition(TrackpadSwipeEvent.openSpaces(backward:false).reversingSelection(if:true) == .openSpaces(backward:true))
  precondition(TrackpadSwipeEvent.openSpaces(backward:true).reversingSelection(if:true) == .openSpaces(backward:false))
  print("PASS production two-axis swipe detector: opt-in, both configured axes, three/four fingers, direction/reversal, dominant-axis recognition/latching, sensitivity, release and next-gesture reset; no input events posted")
 }
}
SWIFT
# Keep Swift's whitespace-sensitive operator lexer unambiguous.
swipe_source = swipe_source.gsub(')==.', ') == .')
Dir.mktmpdir('dockfork-spaces-swipe-') do |dir|
 File.write("#{dir}/checks.swift",swipe_source)
 abort 'Swipe detector compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Swipe detector checks failed' unless system("#{dir}/checks")
end

swipe_settings = File.read("#{root}/DockDoor/Views/Settings/Gestures/TrackpadSwitcherSwipeSection.swift")
catalog = File.read("#{root}/DockDoor/Views/Settings/Search/SettingsSearchCatalog.swift")
reset = File.read("#{root}/DockDoor/Views/Settings/MainSettingsView.swift")
abort 'Opposite-axis swipe setting wiring/default is missing' unless constants.include?('Key<Bool>("trackpadSwitcherSwipeSpaces", default: false)') && swipe_settings.include?('if enableSpacesBar {') && swipe_settings.include?('.settingsSearchTarget("gestures.trackpadSwitcherSwipeSpaces")') && catalog.include?('id: "gestures.trackpadSwitcherSwipeSpaces"') && reset.include?('Defaults[.trackpadSwitcherSwipeSpaces] = Defaults.Keys.trackpadSwitcherSwipeSpaces.defaultValue')
abort 'Axis label must follow configured direction' unless swipe_settings.include?('Text(trackpadSwitcherSwipeDirection.spacesBarNavigationTitle)') && constants.include?('case .horizontal: String(localized: "Use up/down for Spaces Bar")') && constants.include?('case .vertical: String(localized: "Use left/right for Spaces Bar")')
abort 'Keep a single gated trackpad detector/tap' unless swipe.scan('CGEvent.tapCreate(').size==1 && swipe.include?('Defaults[.enableSpacesBar] && Defaults[.trackpadSwitcherSwipeSpaces]')
routing = block(keybinds, '    private func handleTrackpadSwipe(')
abort 'Spaces swipe must share session ownership, pending launch and modifier rules' unless routing.include?('spaceNavigation: spaces ? .cycle(backward: backward) : nil') && routing.include?('initializerHeld: isSwitcherModifierKeyPressed') && routing.include?('TrackpadSwipeReleasePolicy.shouldSelect(') && routing.include?('selectOnSwitcherRelease()')
puts 'PASS Spaces swipe integration: default-off/search/reset, dynamic opposite-axis label, existing event tap, shared session ownership, held-initializer precedence and common pending/release selection'

ownership_source = <<~'SWIFT'
import Foundation
enum Key {case selectWindowOnPersistentSwitcherSwipe, useClassicWindowOrdering, persistentSwitcherStartsUnfocused, instantWindowSwitcher, focusSearchOnWindowSwitcherOpen}
enum Defaults {static var takeover = true;static subscript(_ key:Key)->Bool {key == .selectWindowOnPersistentSwitcherSwipe ? takeover:false}}
enum SwitcherInvocationMode {case allWindows}
final class PreviewStateCoordinator {
 enum SpaceNavigationRequest: Equatable {case current, cycle(backward:Bool)}
 var isKeybindSessionActive = true, hasMovedSinceOpen = true
 var initialHoverLocation: CGPoint? = CGPoint(x:0,y:0)
 var clears = 0, forward = 0, backward = 0
 func clearCheckedWindows(resetOwnership:Bool) {clears += 1}
 func cycleForward() {forward += 1}
 func cycleBackward() {backward += 1}
}
final class SharedPreviewWindowCoordinator {
 let windowSwitcherCoordinator = PreviewStateCoordinator()
 var searchUnfocused = 0
 func unfocusSearchWindow() {searchUnfocused += 1}
}
SWIFT
ownership_source += block(keybinds,'enum WindowSwitcherLaunchSource:')+"\n"+block(keybinds,'enum TrackpadSwipeReleasePolicy {')+"\n"
ownership_source += <<~'SWIFT'
@MainActor final class SwitchingProbe {
 var isProcessingSwitcher = false, currentSessionId = UUID(), activeLaunchSource: WindowSwitcherLaunchSource? = .keyboard
 var trackpadSessionId: UUID?, trackpadTookOverKeepOpenSession = false
 var spaceRequests: [PreviewStateCoordinator.SpaceNavigationRequest] = [], initializations = 0
 func takeKeyboardOwnership() {activeLaunchSource = .keyboard; trackpadSessionId = nil}
 func navigateSpaces(previewCoordinator:SharedPreviewWindowCoordinator,request:PreviewStateCoordinator.SpaceNavigationRequest) {spaceRequests.append(request)}
 func initializeWindowSwitching(previewCoordinator:SharedPreviewWindowCoordinator,mode:SwitcherInvocationMode,launchSource:WindowSwitcherLaunchSource,spaceNavigation:PreviewStateCoordinator.SpaceNavigationRequest?) async -> Bool {
  initializations += 1; activeLaunchSource = launchSource
  trackpadSessionId = launchSource == .trackpad ? currentSessionId:nil
  if let spaceNavigation {spaceRequests.append(spaceNavigation)}
  return true
 }
SWIFT
ownership_source += block(keybinds,'    func handleWindowSwitching(')+"\n}\n"
ownership_source += <<~'SWIFT'
@main struct OwnershipChecks {
 @MainActor static func main() async {
  let panel = SharedPreviewWindowCoordinator(), state = SwitchingProbe()
  _ = await state.handleWindowSwitching(previewCoordinator:panel,isModifierPressed:true,isBackwardPressed:false,launchSource:.trackpad,initializerHeld:true,spaceNavigation:.cycle(backward:false))
  precondition(state.activeLaunchSource == .keyboard && state.trackpadSessionId == nil && panel.windowSwitcherCoordinator.clears == 0 && state.spaceRequests.count == 1,"Held initializer retains ownership while navigating Spaces")
  state.activeLaunchSource = .persistent
  _ = await state.handleWindowSwitching(previewCoordinator:panel,isModifierPressed:true,isBackwardPressed:false,launchSource:.trackpad,spaceNavigation:.current)
  precondition(state.activeLaunchSource == .trackpad && state.trackpadSessionId == state.currentSessionId && state.trackpadTookOverKeepOpenSession && panel.searchUnfocused == 1)
  _ = await state.handleWindowSwitching(previewCoordinator:panel,isModifierPressed:false,isBackwardPressed:true,launchSource:.trackpad,spaceNavigation:.cycle(backward:true))
  precondition(state.spaceRequests.last == .cycle(backward:true) && panel.windowSwitcherCoordinator.forward == 0 && panel.windowSwitcherCoordinator.backward == 0)
  _ = await state.handleWindowSwitching(previewCoordinator:panel,isModifierPressed:false,isBackwardPressed:false,launchSource:.keyboard)
  precondition(state.activeLaunchSource == .keyboard && state.trackpadSessionId == nil,"Keyboard navigation revokes swipe-release ownership")
  state.activeLaunchSource = .persistent; Defaults.takeover = false
  _ = await state.handleWindowSwitching(previewCoordinator:panel,isModifierPressed:true,isBackwardPressed:false,launchSource:.trackpad,spaceNavigation:.current)
  precondition(state.activeLaunchSource == .persistent && state.trackpadSessionId == nil)
  panel.windowSwitcherCoordinator.isKeybindSessionActive = false
  _ = await state.handleWindowSwitching(previewCoordinator:panel,isModifierPressed:true,isBackwardPressed:false,launchSource:.trackpad,spaceNavigation:.current)
  precondition(state.initializations == 1 && state.spaceRequests.last == .current)
  for searchFocused in [false,true] {
   precondition(TrackpadSwipeReleasePolicy.shouldSelect(tookOverKeepOpenSession:true,keepOpen:true,focusesSearchOnOpen:true,searchEnabled:true,searchFocused:searchFocused) == !searchFocused)
  }
  print("PASS production swipe ownership: held initializer, persistent takeover/preference, search unfocus, Space-only navigation, keyboard takeover, pending initialization and unchanged release policy")
 }
}
SWIFT
Dir.mktmpdir('dockfork-spaces-swipe-ownership-') do |dir|
 File.write("#{dir}/checks.swift",ownership_source)
 abort 'Swipe ownership compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Swipe ownership checks failed' unless system("#{dir}/checks")
end

search_section = File.read("#{root}/DockDoor/Views/Settings/Gestures/WindowSwitcherKeybindSection.swift")
abort 'Search settings must share dependent modifier-side resolution and conflict warnings' unless search_section.include?('ignoreModifierSide: ignoreMainModifierSideForDependentShortcuts') && search_section.include?('Text(modifierConverter.toSymbol(searchShortcutKeybind))') && search_section.include?('if let conflict = searchShortcutConflict')
search_route = keybinds[keybinds.index('keyCode == Int64(Defaults[.searchTriggerKey])')...keybinds.index('self.previewCoordinator.focusSearchWindow()', keybinds.index('keyCode == Int64(Defaults[.searchTriggerKey])'))]
abort 'Search trigger must share runtime conflict policy and allow bare typing or the effective side-aware modifier' unless search_route.include?('WindowSwitcherShortcutResolver.searchTriggerConflict(previewKeybind: effectivePreviewShortcutKeybind()') && search_route.include?('normalizedModifiers(Int(flags.rawValue)) == 0 || modifierFlagsMatch(effectivePreviewShortcutKeybind(), flags: flags)')

# Exercise the production terminal-hide prefix and session cancellation without native panels.
panel_source = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
terminal_hide = block(panel_source, '    func hideWindow(')
abort 'Terminal hiding must end the active session before clearing UI state' unless terminal_hide.index('onSwitcherSessionDismissal?()') < terminal_hide.index('windowSwitcherCoordinator.pendingSpaceNavigation = nil')
abort 'Panel dismissal must not cancel accepted mutations' if terminal_hide.include?('cancelPreviewBatchAction(') || terminal_hide.include?('previewActionTasks')
abort 'Session cancellation callback must be weak and installed by the session owner' unless keybinds.include?('previewCoordinator.onSwitcherSessionDismissal = { [weak self] in')
abort 'Remove the obsolete Space-only cancellation entry point' if keybinds.include?('dismissPreviewsForSpaceChange')
%w[scheduleWindowClosureDismissConfirmation scheduleCloseAllDismissConfirmation scheduleNewWindowDismissConfirmation].each do |name|
 watcher = block(panel_source, "    private func #{name}(")
 abort "#{name} must recheck cancellation after discovery returns" unless watcher.include?("await WindowUtil.updateNewWindowsForApp(app)\n                guard shouldRunDeferredWatchers else { return }")
end
hide_prefix = terminal_hide.split('        windowSwitcherCoordinator.pendingSpaceNavigation = nil', 2).first + "        isVisible = false\n    }\n"
lifecycle_source = <<~'SWIFT'
import Foundation
@MainActor final class State {
 var isKeybindSessionActive = true
 var windowSwitcherActive = true
 var fullWindowPreviewActive = false
 func deactivateKeybindSession() { isKeybindSessionActive = false }
}
@MainActor final class Pending { var cancelled = false; func cancel() { cancelled = true } }
@MainActor final class Panel {
 let windowSwitcherCoordinator = State()
 var onSwitcherSessionDismissal: (@MainActor () -> Void)?
 var isVisible = true
SWIFT
lifecycle_source += hide_prefix + block(panel_source, '    private var shouldRunDeferredWatchers: Bool').sub('private var', 'var') + "\n}\n"
lifecycle_source += <<~'SWIFT'
@MainActor final class Switcher {
 var currentSessionId = UUID()
 var shouldSelectImmediately = true
 var windowRefreshTask: Pending? = Pending()
 var uiRenderingTask: Pending? = Pending()
 var activeLaunchSource: Int? = 1
 func relinquishTrackpadSession() {}
SWIFT
lifecycle_source += block(keybinds, '    func cancelSwitching(').gsub('SharedPreviewWindowCoordinator', 'Panel') + "\n}\n"
lifecycle_source += <<~'SWIFT'
@MainActor final class Helper {
 let previewCoordinator: Panel
 let windowSwitchingCoordinator = Switcher()
 var switcherSessionActive = true
 var preventSwitcherHideOnRelease = true
 var hasProcessedModifierRelease = false
 var repeatCancelled = false
 init(_ panel: Panel) { previewCoordinator = panel }
 func cancelHeldKeyRepeatTask() { repeatCancelled = true }
SWIFT
lifecycle_source += block(keybinds, '    private func cancelWindowSwitcherSession(').sub('private func', 'func') + "\n}\n"
lifecycle_source += <<~'SWIFT'
@main struct SessionDismissalChecks {
 @MainActor static func main() async {
  let panel = Panel(), helper = Helper(Panel())
  // Install on the helper's panel, as production initialization does.
  let owned = helper.previewCoordinator
  owned.onSwitcherSessionDismissal = { [weak helper] in helper?.cancelWindowSwitcherSession() }
  let original = helper.windowSwitchingCoordinator.currentSessionId
  owned.hideWindow()
  precondition(!owned.isVisible && !owned.windowSwitcherCoordinator.isKeybindSessionActive)
  precondition(!helper.switcherSessionActive && helper.repeatCancelled && helper.hasProcessedModifierRelease)
  precondition(helper.windowSwitchingCoordinator.currentSessionId != original)
  precondition(helper.windowSwitchingCoordinator.windowRefreshTask!.cancelled && helper.windowSwitchingCoordinator.uiRenderingTask!.cancelled)
  let ended = helper.windowSwitchingCoordinator.currentSessionId
  owned.hideWindow()
  precondition(helper.windowSwitchingCoordinator.currentSessionId == ended, "Already-ended sessions must not be cancelled twice")
  owned.isVisible = true; owned.windowSwitcherCoordinator.isKeybindSessionActive = true
  owned.hideWindow()
  precondition(!owned.windowSwitcherCoordinator.isKeybindSessionActive, "A reopened session must dismiss normally")
  panel.hideWindow()
  precondition(!panel.windowSwitcherCoordinator.isKeybindSessionActive, "Missing owners must still clear the session flag")
  owned.isVisible = true
  precondition(owned.shouldRunDeferredWatchers)
  await Task { @MainActor in
   withUnsafeCurrentTask { $0?.cancel() }
   precondition(!owned.shouldRunDeferredWatchers, "Cancelled watchers cannot act on a reopened visible panel")
  }.value
  print("PASS production dismissal: session flags, queued rendering, idempotence, reopen, fallback and cancelled watchers")
 }
}
SWIFT
Dir.mktmpdir('dockfork-session-dismissal-') do |dir|
 File.write("#{dir}/checks.swift", lifecycle_source)
 abort 'Session dismissal compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Session dismissal checks failed' unless system("#{dir}/checks")
end

#!/usr/bin/env ruby
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
util = File.read("#{root}/DockDoor/Utilities/Window Management/WindowUtil.swift")
source = <<~'SWIFT'
import Foundation
import CoreGraphics
final class NSScreen {
 let cgFrame:CGRect
 init(_ frame:CGRect){cgFrame=frame}
 static var screens:[NSScreen]=[]
}
struct WindowInfo {let id:Int;let frame:CGRect}
final class NSRunningApplication {
 enum Policy {case regular,accessory,prohibited}
 let bundleIdentifier:String?
 let processIdentifier:pid_t
 var isTerminated=false
 static var apps:[pid_t:NSRunningApplication]=[:]
 var activationPolicy=Policy.regular
 init(_ id:String?,pid:pid_t=1){bundleIdentifier=id;processIdentifier=pid;Self.apps[pid]=self}
 init?(processIdentifier:pid_t){guard let app=Self.apps[processIdentifier] else{return nil};self.processIdentifier=processIdentifier;bundleIdentifier=app.bundleIdentifier;isTerminated=app.isTerminated;activationPolicy=app.activationPolicy}
}
enum QuitOnWindowCloseScope { case allExceptSelected, onlySelected }
enum Defaults {
 struct Key<T> {let value:T}
 static var excluded:[String]=[]
 static var included:[String]=[]
 static var quitScope=QuitOnWindowCloseScope.allExceptSelected
 static var quitEnabled=true
 static subscript<T>(_ key:Key<T>)->T{key.value}
}
extension Defaults.Key where T==[String] {
 static var quitAppOnWindowCloseExcludedApps:Self{Self(value:Defaults.excluded)}
 static var quitAppOnWindowCloseIncludedApps:Self{Self(value:Defaults.included)}
}
extension Defaults.Key where T==QuitOnWindowCloseScope {static var quitAppOnWindowCloseScope:Self{Self(value:Defaults.quitScope)}}
extension Defaults.Key where T==Bool {static var quitAppOnWindowClose:Self{Self(value:Defaults.quitEnabled)}}
let finderAppIdentifier="com.apple.finder"
enum Session {static var locked=false}
func testSessionDictionary()->[String:Any]?{["CGSSessionScreenIsLocked":Session.locked]}
let kCGWindowLayer="layer",kCGWindowNumber="number"
enum Ordered {static var ids:Set<UInt32>=[];static var reads=0}
func SLSWindowIsOrderedIn(_ id:UInt32)->Bool?{Ordered.reads+=1;return Ordered.ids.contains(id)}
enum WindowUtil {
 static var candidates:[[String:Any]]=[],valid:Set<UInt32>=[]
 static var cache:[pid_t:[WindowInfo]]=[:]
 static func readCachedWindows(for pid:pid_t)->[WindowInfo]{cache[pid] ?? []}
 static func getCGWindowCandidates(for pid:pid_t)->[[String:Any]]{candidates}
 static func isValidCGWindowCandidate(_ id:UInt32,in values:[[String:Any]])->Bool{valid.contains(id)}
SWIFT
%w[sortWindowsByScreenPosition orderedScreens screenPositionKey quitBlockReason hasOrderedInWindow].each do |name|
  source += block(util, "    private static func #{name}(").sub('private static func', 'static func') + "\n"
end
source += block(util, '    static func shouldQuitAppOnWindowClose(') + "\n"
source += block(util, '    static var isScreenLocked:').sub('CGSessionCopyCurrentDictionary()', 'testSessionDictionary()') + "\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 static func main(){
  NSScreen.screens=[NSScreen(CGRect(x:1000,y:-200,width:1000,height:1000)),NSScreen(CGRect(x:0,y:0,width:1000,height:1000))]
  let a=WindowInfo(id:1,frame:CGRect(x:20,y:30,width:400,height:400))
  let b=WindowInfo(id:2,frame:CGRect(x:50,y:20,width:400,height:400))
  let c=WindowInfo(id:3,frame:CGRect(x:20,y:10,width:400,height:400))
  let d=WindowInfo(id:4,frame:CGRect(x:1100,y:-100,width:400,height:400))
  let unknown=WindowInfo(id:5,frame:.zero),offscreen=WindowInfo(id:6,frame:CGRect(x:-2000,y:0,width:100,height:100))
  let tie=WindowInfo(id:7,frame:a.frame)
  precondition(WindowUtil.sortWindowsByScreenPosition([d,unknown,b,a,offscreen,c,tie]).map(\.id)==[3,1,7,2,4,5,6])
  precondition(WindowUtil.screenPositionKey(for:CGRect(x:900,y:0,width:500,height:500),screens:WindowUtil.orderedScreens())?.screen==1,"Use greatest display overlap")
  NSScreen.screens=[]
  precondition(WindowUtil.sortWindowsByScreenPosition([b,a]).map(\.id)==[2,1],"Unknown geometry keeps input order")
  let app=NSRunningApplication("test.app")
  precondition(WindowUtil.quitBlockReason(for:app)==nil)
  Session.locked=true;precondition(WindowUtil.quitBlockReason(for:app)=="screen locked");Session.locked=false
  app.activationPolicy = .accessory;precondition(WindowUtil.quitBlockReason(for:app)=="not a regular app")
  app.activationPolicy = .prohibited;precondition(WindowUtil.quitBlockReason(for:app)=="not a regular app")
  app.activationPolicy = .regular;Defaults.excluded=["test.app"];precondition(WindowUtil.quitBlockReason(for:app)=="excluded")
  Defaults.excluded=[];precondition(WindowUtil.quitBlockReason(for:NSRunningApplication(nil))==nil)
  let regular=NSRunningApplication("test.close",pid:10)
  WindowUtil.cache[10]=[a]
  precondition(WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10))
  Defaults.excluded=["test.close"];precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10),"DockFork Close must respect the same exclusion as native Close")
  Defaults.quitScope = .onlySelected
  precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10),"An empty allowlist must not quit apps")
  Defaults.included=["test.close"]
  precondition(WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10),"Allowlist ignores the stored exclusion list")
  precondition(WindowUtil.quitBlockReason(for:NSRunningApplication(nil))=="not selected")
  Defaults.quitScope = .allExceptSelected
  Defaults.excluded=[];Session.locked=true;precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10));Session.locked=false
  regular.activationPolicy = .accessory;precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10));regular.activationPolicy = .regular
  regular.isTerminated=true;precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10));regular.isTerminated=false
  WindowUtil.cache[10]=[a,b];precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10))
  WindowUtil.cache[10]=[];precondition(WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10))
  Defaults.quitEnabled=false;precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10));Defaults.quitEnabled=true
  _=NSRunningApplication(finderAppIdentifier,pid:11);precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:11))
  precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:99),"Missing app must not become a Quit fallback")
  print("PASS shared Close-to-Quit policy: excluded, locked, accessory, terminated, Finder, disabled, missing and multi-window cases refuse; eligible last/windowless entries retain behavior")
  WindowUtil.candidates=[[kCGWindowLayer:1,kCGWindowNumber:1],[kCGWindowLayer:0,kCGWindowNumber:2],[kCGWindowLayer:0,kCGWindowNumber:3]]
  WindowUtil.valid=[3];Ordered.ids=[3];precondition(WindowUtil.hasOrderedInWindow(pid:1) && Ordered.reads==1)
  Ordered.ids=[];precondition(!WindowUtil.hasOrderedInWindow(pid:1))
  print("PASS upstream integration: cached screen sorting/overlap/stable fallback and lock/policy/exclusion/ordered-window quit guards; inert data only")
 }
}
SWIFT
Dir.mktmpdir('dockfork-upstream-integration-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Integration compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Integration checks failed' unless system("#{dir}/checks")
end
verify = block(util, '    private static func verifyNoWindowsRemain(')
abort 'Quit must retain both upstream guards and shared ownership' unless verify.include?('hasOrderedInWindow(pid: pid)') && verify.index('quitBlockReason(for: app)') < verify.index('.quit(force: false)') && !verify.include?('app.terminate()')
buttons = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/Traffic Light Buttons.swift")
abort 'Native accessible traffic lights must retain shared dimensions' unless buttons.include?('return Button {') && buttons.include?('.accessibilityLabel(action.localizedName)') && buttons.include?('Self.buttonFrameSize * buttonScale')
puts 'PASS integration source contracts: shared Quit ownership and native accessible/sized traffic lights'

# Merge boundaries: preserve fork routing and use the incoming resource fixes.
settings_root = "#{root}/DockDoor/Views/Settings"
settings = Dir.glob("#{settings_root}/**/*.swift").map { |path| File.read(path) }.join("\n")
keys = File.read("#{root}/DockDoor/consts.swift")
reset = File.read("#{settings_root}/MainSettingsView.swift")
search = File.read("#{settings_root}/Search/SettingsSearchCatalog.swift")
abort 'Description preference needs default, reset and exact search/control wiring' unless keys.include?('Key<Bool>("showSettingsDescriptions", default: true)') && reset.include?('Defaults.reset(.showSettingsDescriptions)') && reset.include?('.settingsSearchTarget("general.showSettingDescriptions")') && search.include?('id: "general.showSettingDescriptions"')
abort 'Retired Settings shell must not survive the merge' if settings.include?('BaseSettingsView {') || settings.include?('SettingsGroup(')
abort 'Fork shortcut storage must remain authoritative' unless keys.include?('alternateSwitcherShortcuts') && !keys.include?('additionalAlternateKeybinds') && settings.include?('ModifierKeyToggles(modifierFlags: $keybindModel.modifierKey)')
%w[DockPreviewsSettingsView CmdTabSettingsView WindowSwitcherBehaviorSettingsView].each do |name|
  pane = File.read("#{settings_root}/#{name}.swift")
  abort "#{name} needs the shared pinned preview header" unless pane.include?('} pinnedHeader: {') && pane.include?('SettingsMockPreview(context:')
end
abort 'Dock locking search must route to its new pane' unless File.read("#{settings_root}/AdvancedSettingsView.swift").include?('.settingsSearchTarget("dockLocking.enable")') && !search.include?('tab: "DockLocking"')
mock = File.read("#{settings_root}/Shared Components/SettingsMockPreview.swift")
container = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreviewHoverContainer.swift")
abort 'Mock cache cleanup/shared appearance parity must survive' unless mock.include?('static func releaseCaches()') && !mock.include?('appearanceOverride:') && mock.include?('PreviewStateCoordinator(isMockPreview: true)') && mock.include?('.modifier(ScaledToFit(maxHeight: maxHeight))')
abort 'Settings mocks must not affect real capture lifetime' unless container.scan('if !mockPreviewActive, Defaults[.enableLivePreview], Defaults[.livePreviewStreamKeepAlive] != 0 {').length == 2
observers = File.read("#{root}/DockDoor/Utilities/Window Management/WindowManipulationObservers.swift")
removal = block(observers, '    func removeObserver(for pid:')
abort 'Unschedule the AX source before releasing its observer off-main' unless removal.index('CFRunLoopRemoveSource(CFRunLoopGetMain()') < removal.index('DispatchQueue.global')
permissions = File.read("#{root}/DockDoor/Components/PermissionsView/PermissionsChecker.swift")
abort 'Preserve permission transition publication and granted-timer teardown' unless permissions.include?('guard self[keyPath: keyPath] != value else { return }') && permissions.include?('if accessibilityPermission, screenRecordingPermission {') && permissions.include?('timer = nil')
activation = File.read("#{root}/DockDoor/Utilities/Window Management/WindowInfo.swift")
raise_action = activation.index('try window.axElement.performAction(kAXRaiseAction)')
main_write = activation.index('try window.axElement.setAttribute(kAXMainAttribute, true)', raise_action)
reactivation = activation.index('if wasOwnerActive {', main_write)
abort 'Already-active reactivation must follow raise/Main and retain cancellation ownership' unless reactivation && activation[reactivation, 650].include?('guard isActive(), !window.ownerApp.isTerminated') && activation[reactivation, 650].include?('request.finish(true)')
puts 'PASS 1.42.2 merge contracts: fork shortcut/settings preservation, pinned/cached mocks, permission timers, AX observer teardown and guarded post-raise reactivation'

cmd_tab = File.read("#{root}/DockDoor/Utilities/DockObserver+CmdTab.swift")
subscription = block(cmd_tab, '    private func subscribeToProcessSwitcher(')
abort 'Confirmed Cmd+Tab ownership must release an existing Dock reveal tap' unless subscription.include?("DockObserver.isCmdTabSwitcherActive = true\n            previewCoordinator.releaseDockReveal()")
panel = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
reveal = block(panel, '    private func keepDockRevealed(')
abort 'A late Dock preview must not acquire a reveal tap during Cmd+Tab' unless reveal.index('!DockObserver.isCmdTabSwitcherActive,') && reveal.index('!DockObserver.isCmdTabSwitcherActive,') < reveal.index('DockUtils.dockRevealTarget()')
puts 'PASS Dock reveal handoff: confirmed Cmd+Tab releases the old tap and gates late Dock reveal'

dock_release = <<~'SWIFT'
import Foundation
import CoreGraphics
typealias CFMachPort = Int
final class NSRunningApplication {
 let processIdentifier: pid_t = 42
 var isTerminated = false
}
enum DockObserver {
 static var mouseLocation = CGPoint.zero
 static func getMousePosition() -> CGPoint { mouseLocation }
}
enum DockUtils {
 static let mouseExitedEventType = 9
 static var posts: [CGPoint] = []
 static func postMouseEvent(_ type: Int, at point: CGPoint, toDock pid: pid_t) {
  precondition(type == mouseExitedEventType && pid == 42)
  posts.append(point)
 }
}
final class EventTapThread {
 static let shared = EventTapThread()
 var cleanup: (() -> Void)?
 var removals = 0
 func remove(_ tap: Int, source: Int, then cleanup: @escaping () -> Void) {
  precondition(tap == 1 && source == 2 && self.cleanup == nil)
  removals += 1
  self.cleanup = cleanup
 }
 func finish() {
  let callback = cleanup
  cleanup = nil
  callback?()
 }
}
SWIFT
dock_release += block(panel, 'private final class DockRevealTapContext') + "\n"
dock_release += <<~'SWIFT'
final class Panel {
 private var dockRevealTap: (tap: Int, source: Int, context: Unmanaged<DockRevealTapContext>)?
 private weak var context: DockRevealTapContext?
 var ownsTap: Bool { dockRevealTap != nil }
 var retainsContext: Bool { context != nil }
 init(app: NSRunningApplication) {
  let context = DockRevealTapContext(app: app, revealPoint: .zero, dockRegion: CGRect(x: 0, y: 0, width: 20, height: 20))
  self.context = context
  dockRevealTap = (1, 2, .passRetained(context))
 }
SWIFT
dock_release += block(panel, '    func releaseDockReveal(') + "\n}\n"
dock_release += <<~'SWIFT'
for (inside, terminateDuringCleanup) in [(true, false), (false, false), (false, true)] {
 let app = NSRunningApplication()
 let panel = Panel(app: app)
 let worker = EventTapThread.shared
 let start = worker.removals
 let point = CGPoint(x: inside ? 10 : 30, y: 10)
 DockObserver.mouseLocation = point
 DockUtils.posts = []
 panel.releaseDockReveal()
 panel.releaseDockReveal()
 precondition(!panel.ownsTap && panel.retainsContext && worker.removals == start + 1 && DockUtils.posts.isEmpty)
 app.isTerminated = terminateDuringCleanup
 worker.finish()
 precondition(!panel.retainsContext)
 precondition(DockUtils.posts == (inside || terminateDuringCleanup ? [] : [point]))
}
print("PASS Dock reveal teardown: cached bounds, no Dock lookup, exactly-once cleanup, safe exit event")
SWIFT
Dir.mktmpdir('dockfork-dock-reveal-') do |dir|
  File.write("#{dir}/checks.swift", dock_release)
  abort 'Dock reveal compilation failed' unless system('swiftc', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Dock reveal checks failed' unless system("#{dir}/checks")
end

# Keep the fork's per-call timing when merging upstream's batch-duration fix.
registration = block(observers, '    private func createObserverForApp(')
abort 'Observer registration must time each AX call and retain guarded cleanup' unless registration.include?('for notification in observedAXNotifications') && registration.include?('timedOut = timedOut || AXResponsiveness.shouldBackOff(after: result, elapsed: CFAbsoluteTimeGetCurrent() - start)') && registration.include?('guard registration.failed else { return }') && registration.include?('if registration.timedOut') && registration.include?('self.observers[pid] === observer')
ax = File.read("#{root}/DockDoor/Extensions/AXUIElement.swift")
policy = "import Foundation\nenum AXError {case success,cannotComplete}\nenum AXResponsiveness {\n"
policy += ax.lines.find { |line| line.include?('static let hangThreshold:') }
policy += block(ax, '    static func shouldBackOff(') + "\n}\n"
policy += <<~'SWIFT'
for error in [AXError.success,.cannotComplete] {
 for duration in [0.0,0.01,0.499,0.5,0.501,5.0] {
  precondition(AXResponsiveness.shouldBackOff(after:error,elapsed:duration) == (error == .cannotComplete && duration >= 0.5))
 }
}
precondition(!(0..<100).contains { _ in AXResponsiveness.shouldBackOff(after:.cannotComplete,elapsed:0.01) },"Many fast failures must not quarantine an app")
print("PASS observer readiness: fast registration failures do not quarantine, slow cannotComplete does; per-call timing and stale-owner cleanup retained")
SWIFT
Dir.mktmpdir('dockfork-observer-readiness-') do |dir|
 File.write("#{dir}/checks.swift", policy)
 abort 'Observer policy compilation failed' unless system('swiftc', "#{dir}/checks.swift", '-o', "#{dir}/checks")
 abort 'Observer policy checks failed' unless system("#{dir}/checks")
end

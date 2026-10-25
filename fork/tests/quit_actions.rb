#!/usr/bin/env ruby
# Exercise production Quit dispatch with inert apps; never terminate a real process.
require 'tmpdir'
require_relative 'support/action_ownership'
ROOT = File.expand_path('../..', __dir__)
def block(source, signature)
  start = source.index(signature) or abort "Missing #{signature}"
  first = source.index(/\{\n/, start)
  depth = 0
  (first...source.length).each do |i|
    depth += 1 if source[i] == '{'
    depth -= 1 if source[i] == '}'
    return source[start..i] if depth.zero?
  end
  abort "Unclosed #{signature}"
end
util = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowUtil.swift")
info = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowInfo.swift")
catalog = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowActionCatalog.swift")
perform = block(util, "    func perform(\n")
abort 'Preview Quit/Close still inspects held modifiers' if perform.include?('modifierFlags')
abort 'Quit label still inspects held modifiers' if block(catalog, '    func menuTitle(').include?('modifierFlags')
dock = File.read("#{ROOT}/DockDoor/Utilities/DockObserver.swift")
gesture = block(dock, '    private func handleCmdRightClickQuit(')
abort 'Documented Dock Quick Quit changed' unless gesture.include?('event.flags.contains(.maskAlternate)') && gesture.include?('? .forceQuit : .quit') && gesture.include?('WindowUtil.performPreviewBatchAction')
builder = File.read("#{ROOT}/DockDoor/Views/Hover Window/WindowPreviewInteractionModifier.swift")
abort 'Both Quit actions need shared destructive styling' unless builder.include?('if action.isQuitAction {')
abort 'Collapsed Quit needs an explicit Force Quit alternative' unless builder.include?('.flatMap { $0 == .quit ? [.quit, .forceQuit] : [$0] }')
abort 'Force Quit missing from shared menus' unless catalog.include?('[.close, .quit, .forceQuit]')
abort 'Force Quit missing from assignments' unless util[util.index('    static let assignablePreviewActions:')...util.index('    func postActionCategory(')].include?('.forceQuit')
coordinator = File.read("#{ROOT}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
highlighted = block(coordinator, '    func performActionOnCmdTabHighlightedApps(')
abort 'Cmd+Tab app requests must report refusal' unless highlighted.include?('if case .noChange = result {')
defaults = File.read("#{ROOT}/DockDoor/consts.swift")
abort 'Force Quit must not gain a default assignment' if defaults.include?('.forceQuit')
%w[quit forceQuit].each do |action|
  abort "Stored action #{action} missing" unless util.match?(/^    case #{action}$/)
end

source = <<~'SWIFT'
import Foundation
typealias pid_t = Int32
struct Key<T> { let value: T }
enum Defaults { static var autoFill=false, limited=false, foreground=false, rows=2, columns=3; static subscript<T>(_ key: Key<T>) -> T { key.value } }
extension Key where T == Bool {
 static var enableMultiWindowSelection: Self { Self(value: true) }
 static var enableWindowlessAppSelection: Self { Self(value: true) }
 static var fillActionsAutoTileSelection: Self { Self(value: Defaults.autoFill) }
 static var moveResizeBringToForeground: Self { Self(value: Defaults.foreground) }
 static var tileOnlyWhatFits: Self { Self(value: Defaults.limited) }
}
extension Key where T == Int {
 static var maximumTilingRows: Self { Self(value: Defaults.rows) }
 static var maximumTilingColumns: Self { Self(value: Defaults.columns) }
}
final class App {
 let processIdentifier: pid_t
 var isHidden = false, isTerminated = false, accepts = true
 var normal = 0, forced = 0
 init(_ pid: pid_t) { processIdentifier = pid }
 func terminate() -> Bool { normal += 1; return accepts }
 func forceTerminate() -> Bool { forced += 1; return accepts }
}
struct AX { func isFullscreen() throws -> Bool { false } }
struct PreviewWindowIdentity: Hashable {
 let pid: pid_t, windowID: Int
 init(_ window: WindowInfo) { pid = window.app.processIdentifier; windowID = window.id }
}
struct WindowInfo {
 let id: Int, app: App
 var isWindowlessApp = false, isFullscreen: Bool? = false, isWineWindow = false
 var isMinimized = false
 var closeButton: Int? = 1
 var hasLimitedWindowControls = false
 var isEffectivelyHiddenForUI: Bool { isHidden && isFullscreen != true }
 var isHidden: Bool { app.isHidden }
 var axElement: AX { AX() }
 func close() -> Bool { true }
 func readFullscreenState() async -> Bool? {false}
 func positionWindow(_ rect:Int) async -> Bool {await WindowUtil.position(id)}
 func bringToFrontConfirmed() async -> Bool {await WindowUtil.focus(id)}
SWIFT
source += block(info, '    func quit(force:') + "\n}\n"
case_start = util.index('    // Existing actions')
cases = util[case_start...util.index('    var localizedName:', case_start)].scan(/^    case (\w+)$/).flatten
source += "enum WindowAction { case #{cases.join(', ')}\n var positionRect:Int? {[.center,.maximize,.fillLeftHalf,.fillRightHalf,.fillTopHalf,.fillBottomHalf,.fillTopLeftQuarter,.fillTopRightQuarter,.fillBottomLeftQuarter,.fillBottomRightQuarter].contains(self) ? 0 : nil}\n"
%w[localizedName iconName].each { |name| source += block(util[case_start..], "    var #{name}:") + "\n" }
source += block(catalog, '    enum TargetScope:') + "\n" + block(catalog, '    var targetScope:') + "\n" + block(catalog, '    func selectedPreviewTargets(') + "\n"
source += catalog[catalog.index('    var isQuitAction:')...catalog.index('    var isAppWidePreviewAction:')]
%w[isAppWidePreviewAction].each { |name| source += block(catalog, "    var #{name}:") + "\n" }
%w[isSupported appliesToSelectedWindow previewTargets batchTargets].each { |name| source += block(catalog, "    func #{name}(") + "\n" }
source += <<~'SWIFT'
 var tilingDirection: Int? { self == .fillLeftHalf || self == .autoTileSelectedWindows ? 0 : nil }
 /* Auto Tile policy */

 /* Action availability */
SWIFT
source.sub!('/* Action availability */', block(catalog, '    func isAvailable(for window: WindowInfo) -> Bool') + "\n" + block(catalog, '    func isAvailable(for window: WindowInfo, batchTargets:'))
source.sub!('/* Auto Tile policy */', block(catalog, '    func autoTilingDirection(').sub('PreviewTilingLayout.Direction?', 'Int?'))
source += block(catalog, '    func batchTargetState(') + "\n"
source += block(catalog, '    func menuTitle(') + "\n" + block(catalog, '    func feedbackTitle(') + "\n"
source += block(catalog, '    static func spaceMoveMenuTitle(') + "\n"
source += <<~'SWIFT'
 enum ActionResult { case noChange, dismissed }
 func perform(on window: WindowInfo, keepPreviewOnQuit: Bool = false, preferredWindows: [WindowInfo]? = nil, feedback: ActionFeedbackHandle? = nil) -> ActionResult {
  defer { feedback?.finishRemaining(.requested) }
  func accepted(_ success: Bool) -> Bool { if !success { feedback?.finishRemaining(.failed) }; return success }
  switch self {
SWIFT
source += perform[perform.index('        case .quit, .forceQuit:')...perform.index('        case .minimize, .toggleFullScreen, .hide:')]
source += "default: return .noChange\n}\n}\n}\n"
source += <<~'SWIFT'
enum Outcome { case requested, completed, failed, cancelled }
final class ActionFeedbackHandle {
 var states: [PreviewWindowIdentity: Outcome] = [:]
 var confirmedProgress: ((WindowInfo, Bool) -> Void)? { nil }
 func finishRemaining(_ outcome: Outcome) {}
 func finish(_ id: PreviewWindowIdentity, _ outcome: Outcome) { if states[id] == nil { states[id] = outcome } }
 var result: WindowUtil.PreviewBatchResult?
 func finish(_ result: WindowUtil.PreviewBatchResult, requested: Bool = false) { self.result = result }
}
@MainActor final class PendingAX {
 var started=false
 private var completion:CheckedContinuation<Void,Never>?
 func wait() async {started=true;await withCheckedContinuation {completion=$0}}
 func release() {completion?.resume();completion=nil}
}
enum WindowUtil {
 @MainActor static var pendingPosition:[Int:PendingAX]=[:],pendingFocus:[Int:PendingAX]=[:]
 @MainActor static var positionCalls:[Int]=[],focusCalls:[Int]=[],positionFailures=Set<Int>(),focusFailures=Set<Int>(),offSpace=Set<Int>()
 @MainActor static func position(_ id:Int) async -> Bool {
  positionCalls.append(id);if let gate=pendingPosition.removeValue(forKey:id) {await gate.wait()}
  return !Task.isCancelled && !positionFailures.contains(id)
 }
 @MainActor static func focus(_ id:Int) async -> Bool {
  focusCalls.append(id);if let gate=pendingFocus.removeValue(forKey:id) {await gate.wait()}
  return !Task.isCancelled && !focusFailures.contains(id)
 }
 @MainActor static var pendingMinimize:PendingAX?
 static var hiddenRequests: [(pid_t, Bool)] = [], minimizedRequests: [Bool] = []
 static var quitOnClose = false
 static var spaceCalls:[Int]=[]
 static var cached: [pid_t: [WindowInfo]] = [:]
 static func readCachedWindows(for pid: pid_t) -> [WindowInfo] { cached[pid] ?? [] }
 static func shouldQuitAppOnWindowClose(processIdentifier pid: pid_t) -> Bool { quitOnClose }
 static func closeAllWindows(for app: App, preferredWindows: [WindowInfo]? = nil, feedback: ActionFeedbackHandle? = nil) -> Int { 0 }
 static func hasOnlyFullscreenWindows(for app: App) -> Bool { false }
 static func openNewWindow(app: App) -> Bool { true }
 static func moveWindowToCurrentManagedSpace(_ window:WindowInfo)->Bool {spaceCalls.append(window.id);return true}
 @MainActor static func canBringWindowToFrontWithoutSpaceSwitch(_ window: WindowInfo) -> Bool { !offSpace.contains(window.id) }
 static func setHiddenStateConfirmed(for app: App, isHidden: Bool, fullscreenCandidates: [AX] = [], beforeChange: (@MainActor (Bool) -> Bool)? = nil) async -> Bool { hiddenRequests.append((app.processIdentifier, isHidden)); return true }
 static func revealWindowConfirmed(_ window: WindowInfo) async -> Bool { true }
 static func changeFullscreenConfirmed(_ window: WindowInfo, toggle: Bool, beforeChange: (@MainActor (Bool) -> Bool)? = nil) async -> Bool { true }
 static func setMinimizedWindowsConfirmed(_ windows: [WindowInfo], isMinimized: Bool, isTargetActive: @escaping @Sendable (PreviewWindowIdentity) -> Bool = { _ in true }, progress: ((WindowInfo, Bool) -> Void)?) async -> [WindowInfo] { minimizedRequests.append(isMinimized); if let pending=await pendingMinimize { await MainActor.run {pendingMinimize=nil}; await pending.wait() }; return Task.isCancelled ? [] : windows }
 static var tileCalls:[[Int]]=[]
 static func tilePreviewWindows(_ windows: [WindowInfo], direction: Int, feedback: ActionFeedbackHandle?) async -> PreviewBatchResult { tileCalls.append(windows.map(\.id)); return PreviewBatchResult(succeeded:windows) }
 static func closeWindows(_ windows: [WindowInfo], feedback: ActionFeedbackHandle?) async -> PreviewBatchResult { PreviewBatchResult(succeeded: windows) }
SWIFT
source += block(util, '    static func beginPreviewActionRequest(') + "\n"
source += block(util, '    static func autoTileTargets(') + "\n"
source += block(util, '    struct PreviewBatchResult') + "\n"
source = block(catalog, 'enum PreviewBatchTogglePolicy {') + "\n" + catalog[catalog.index('final class WindowActionRequest:')...catalog.index('enum PreviewBatchTogglePolicy {')] + "\n" + source
source += "@MainActor\n" + block(util, '    static func performPreviewBatchAction(') + "\n@MainActor\n" + block(util, '    private static func executePreviewAction(') + "\n}\n"
source += block(File.read("#{ROOT}/DockDoor/Views/Hover Window/WindowPreview.swift"), 'func resolvedTrafficLightButtons(') + "\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async {
  let wineApp = App(77), nativeApp = App(78)
  let wine = WindowInfo(id: 77, app: wineApp, isWineWindow: true)
  var native = WindowInfo(id: 78, app: nativeApp); native.isMinimized = true
  let normal = WindowInfo(id: 81, app: nativeApp)
  let full = WindowInfo(id: 82, app: nativeApp, isFullscreen: true)
  let fullscreenUnsupported: [WindowAction] = [.minimize, .minimizeAllWindows, .maximize, .center, .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf, .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter, .autoTileSelectedWindows, .bringToCurrentSpace]
  WindowUtil.cached[78] = [normal, full]
  for action in fullscreenUnsupported {
   precondition(!action.isSupported(for: full) && !action.isAvailable(for: full), "Fullscreen-only menus must omit unsupported actions")
   precondition(action.previewTargets(from: [full, normal]).map(\.id) == [normal.id], "Mixed groups must exclude fullscreen targets before execution and feedback")
   precondition(action.isAvailable(for: full, batchTargets: [full, normal]), "A fullscreen initiator must not hide actions supported by selected peers")
  }
  precondition(WindowAction.toggleFullScreen.isSupported(for: full) && WindowAction.toggleFullScreen.isAvailable(for: full))
  WindowUtil.cached[78] = [full]
  precondition(!WindowAction.hide.isAvailable(for: full), "A visible fullscreen-only app cannot be hidden")
  nativeApp.isHidden = true
  precondition(WindowAction.hide.isAvailable(for: full), "Unhide must remain available")
  nativeApp.isHidden = false
  WindowUtil.cached[78] = [normal, full]
  precondition(WindowAction.hide.isAvailable(for: full), "App-wide Hide remains available when other app windows support it")
  WindowUtil.cached = [:]
  precondition(WindowAction.openAppWindow.targetScope == .initiator)
  precondition(WindowAction.openAppWindow.selectedPreviewTargets(for: native, from: [native, wine]) == nil)
  precondition(WindowAction.autoTileSelectedWindows.selectedPreviewTargets(for: normal, from: [native, wine]) == nil, "Unchecked initiators must not tile an unrelated selection")
  precondition(WindowAction.close.selectedPreviewTargets(for: native, from: [wine, native])?.map(\.id) == [wine.id, native.id], "Selection order must survive scope resolution")
  precondition(WindowAction.toggleFullScreen.selectedPreviewTargets(for: normal, from: [normal, wine]) == nil, "Fullscreen entry stays initiating-window-only")
  var wineFull = wine; wineFull.isFullscreen = true
  precondition(WindowAction.toggleFullScreen.selectedPreviewTargets(for: normal, from: [normal, wineFull]) == nil, "Unsupported fullscreen sources must not block initiating-window entry")
  let emptySource = WindowInfo(id: 0, app: nativeApp, isWindowlessApp: true)
  precondition(WindowAction.toggleFullScreen.selectedPreviewTargets(for: emptySource, from: [emptySource, normal])?.isEmpty == true, "Windowless sources must not enter fullscreen for another selection")
  precondition(WindowAction.toggleFullScreen.selectedPreviewTargets(for: normal, from: [normal, full])?.map(\.id) == [normal.id, full.id])
  precondition(WindowAction.toggleFullScreen.previewTargets(from: [normal, full], allowFullscreenEntry: false).map(\.id) == [full.id])
  precondition(WindowAction.minimize.isAvailable(for: wine, batchTargets: [wine, native]), "A supported selected peer must make the group action available")
  precondition(!WindowAction.minimize.isAvailable(for: wine, batchTargets: [wine]))
  precondition(WindowAction.toggleFullScreen.isAvailable(for: wine, batchTargets: [wine, full]))
  precondition(WindowAction.openNewWindow.targetScope == .selectedApps && WindowAction.closeAllWindows.targetScope == .allWindowsOfSelectedApps)
  precondition(WindowAction.openNewWindow.batchTargets(from: [normal, full]).map(\.id) == [normal.id], "New Window must remain one request per app")
  precondition(WindowAction.openAppWindow.localizedName == "Open Window")
  precondition(WindowAction.openAppWindow.menuTitle(for: normal) == "Open Window")
  precondition(WindowAction.openAppWindow.menuTitle(for: normal, batchTargets: [normal, full]) == "Open Window (This Window)")
  precondition(WindowAction.openAppWindow.menuTitle(for: emptySource, batchTargets: [emptySource, normal]) == "Activate App")
  precondition(WindowAction.close.menuTitle(for: normal, batchTargets: [normal, full]) == "Close Selected Windows")
  precondition(WindowAction.quit.menuTitle(for: normal, batchTargets: [normal, full]) == "Quit Selected App")
  precondition(WindowAction.quit.menuTitle(for: normal, batchTargets: [normal, wine]) == "Quit Selected Apps")
  precondition(WindowAction.forceQuit.menuTitle(for: normal, batchTargets: [normal, full]) == "Force Quit Selected App")
  precondition(WindowAction.openNewWindow.menuTitle(for: normal, batchTargets: [normal, full]) == "Open New Window for Selected App")
  precondition(WindowAction.closeAllWindows.menuTitle(for: normal, batchTargets: [normal, full]) == "Close All Windows of Selected App")
  precondition(WindowAction.toggleFullScreen.menuTitle(for: normal, batchTargets: [normal, wine]) == "Enter Full Screen (This Window)")
  precondition(WindowAction.toggleFullScreen.menuTitle(for: normal, batchTargets: [normal, full]) == "Exit Full Screen for Selected Window")
  precondition(WindowAction.spaceMoveMenuTitle(for: normal, batchTargets: [normal, full]) == "Move Selected Windows to Space")
  precondition(WindowAction.spaceMoveMenuTitle(for: normal, batchTargets: nil) == "Move to Space")
  precondition(WindowAction.quit.feedbackTitle(for: normal, batchTargets: [normal, wine]) == "Quit App")
  precondition(WindowAction.close.feedbackTitle(for: normal, batchTargets: [normal, full]) == "Close")
  precondition(WindowAction.fillLeftHalf.menuTitle(for: normal, batchTargets: [normal, wine]) == "Fill Left Half for Selected Windows")
  Defaults.autoFill = true
  precondition(WindowAction.fillLeftHalf.menuTitle(for: normal, batchTargets: [normal, wine]) == "Auto Tile Selected Windows (Fill Left Half)")
  Defaults.autoFill = false
  let unsupportedWineActions: [WindowAction] = [.close, .closeAllWindows, .minimize, .minimizeAllWindows, .toggleFullScreen, .openNewWindow]
  for action in unsupportedWineActions {
   precondition(!action.isSupported(for: wine) && action.isSupported(for: native))
   precondition(!action.isAvailable(for: wine))
   let feedback = ActionFeedbackHandle()
   let result = await WindowUtil.performPreviewBatchAction(action, on: [wine], allowFullscreenEntry: true, feedback: feedback)
   precondition(result.succeeded.isEmpty && result.failed == [PreviewWindowIdentity(wine)], "Invalid Wine action did not fail: \(action), \(result)")
   precondition(feedback.result?.failed == [PreviewWindowIdentity(wine)], "Invalid Wine feedback: \(action)")
   precondition(action.previewTargets(from: [wine, wine]).isEmpty)
   let ignored = await WindowUtil.performPreviewBatchAction(action, on: [wine, wine])
   precondition(ignored.failed.isEmpty && ignored.succeeded.isEmpty)
  }
  for action: WindowAction in [.quit, .forceQuit, .hide, .bringToCurrentSpace, .openAppWindow, .maximize, .center, .fillLeftHalf, .autoTileSelectedWindows, .toggleWindowSelection, .selectAllWindows] {
   precondition(action.isSupported(for: wine))
  }
  for action: WindowAction in [.minimize, .close] {
   precondition(action.previewTargets(from: [wine, native]).map(\.id) == [native.id])
  }
  WindowUtil.cached[77] = [wine]; WindowUtil.cached[78] = [native]
  precondition(WindowAction.minimizeAllWindows.previewTargets(from: [wine, native]).map(\.id) == [native.id])
  precondition(WindowAction.closeAllWindows.previewTargets(from: [wine, native]).map(\.id) == [native.id])
  precondition(WindowAction.minimize.batchTargetState(for: [wine, native]) == false)
  let configured = Set([WindowAction.quit, .close, .hide, .minimize, .toggleFullScreen, .maximize, .bringToCurrentSpace])
  for hidden in [false, true] {
   wineApp.isHidden = hidden
   for action in unsupportedWineActions { precondition(!action.isAvailable(for: wine)) }
   precondition(resolvedTrafficLightButtons(for: wine, configuredButtons: configured, showWindowlessQuitButton: true) == configured.filter { $0.isSupported(for: wine) })
  }
  wineApp.isHidden = false; WindowUtil.cached = [:]
  print("PASS Wine action policy: supported operations, invalid single failures, ignored batch targets, frozen minimize intent, hidden/visible controls")
  for force in [false, true] {
   let app = App(1), other = App(2)
   let action = force ? WindowAction.forceQuit : .quit
   let one = WindowInfo(id: 1, app: app), two = WindowInfo(id: 2, app: app)
   let empty = WindowInfo(id: 0, app: other, isWindowlessApp: true)
   precondition(action.menuTitle(for: one) == (force ? "Force Quit App" : "Quit App"))
   precondition(action.feedbackTitle(for: one) == action.menuTitle(for: one))
   precondition(action.iconName == (force ? "exclamationmark.octagon.fill" : "xmark.circle.fill"))
   precondition(action.isAppWidePreviewAction && action.appliesToSelectedWindow(empty))
   let feedback = ActionFeedbackHandle()
   let result = await WindowUtil.performPreviewBatchAction(action, on: [one, two, empty, one], feedback: feedback)
   precondition(result.succeeded.count == 2 && result.failed.isEmpty)
   precondition(app.normal == (force ? 0 : 1) && app.forced == (force ? 1 : 0))
   precondition(other.normal == app.normal && other.forced == app.forced)
   precondition(feedback.states.count == 3 && feedback.states.values.allSatisfy { $0 == .requested })
   app.accepts = false
   let failed = await WindowUtil.performPreviewBatchAction(action, on: [one, two])
   precondition(failed.failed == [PreviewWindowIdentity(one)] && failed.succeeded.isEmpty)
   let stopped = App(3); stopped.isTerminated = true
   let unavailable = await WindowUtil.performPreviewBatchAction(action, on: [WindowInfo(id: 3, app: stopped)])
   precondition(unavailable.succeeded.isEmpty && stopped.normal == 0 && stopped.forced == 0)
   let scalar = App(4)
   if case .dismissed = action.perform(on: WindowInfo(id: 4, app: scalar)) {} else { preconditionFailure() }
   precondition(scalar.normal == (force ? 0 : 1) && scalar.forced == (force ? 1 : 0))
   scalar.accepts = false
   if case .noChange = action.perform(on: WindowInfo(id: 4, app: scalar)) {} else { preconditionFailure() }
  }
  WindowUtil.quitOnClose = true
  for windowless in [false, true] {
   let app = App(5), window = WindowInfo(id: 5, app: app, isWindowlessApp: windowless)
   _ = WindowAction.close.perform(on: window)
   precondition(app.normal == 1 && app.forced == 0)
  }
  let app = App(6)
  let windows = [WindowInfo(id: 6, app: app), WindowInfo(id: 7, app: app)]
  _ = await WindowUtil.performPreviewBatchAction(.close, on: windows)
  precondition(app.normal == 1 && app.forced == 0)
  let cancelled = App(7)
  let task = Task { @MainActor in
   withUnsafeCurrentTask { $0?.cancel() }
   return await WindowUtil.performPreviewBatchAction(.forceQuit, on: [WindowInfo(id: 8, app: cancelled)])
  }
  _ = await task.value
  precondition(cancelled.normal == 0 && cancelled.forced == 0)
let visibleApp=App(10),hiddenApp=App(11);hiddenApp.isHidden=true
let visible=WindowInfo(id:100,app:visibleApp),hidden=WindowInfo(id:101,app:hiddenApp)
let protected=WindowActionOwnership.shared.begin([PreviewWindowIdentity(visible)],protect:true)
let mixedHide=await WindowUtil.performPreviewBatchAction(.hide,on:[visible,hidden])
precondition(mixedHide.failed == [PreviewWindowIdentity(visible)] && mixedHide.succeeded.map(\.id)==[101])
precondition(WindowUtil.hiddenRequests.last!.0==11 && WindowUtil.hiddenRequests.last!.1,"Busy filtering reversed app toggle intent")
let allBusy=await WindowUtil.performPreviewBatchAction(.quit,on:[visible,WindowInfo(id:102,app:visibleApp)])
precondition(allBusy.failed.count==2 && visibleApp.normal==0,"App-wide claim was not atomic")
let minimized=WindowInfo(id:103,app:hiddenApp,isMinimized:true)
let mixedMinimize=await WindowUtil.performPreviewBatchAction(.minimize,on:[visible,minimized])
precondition(mixedMinimize.failed == [PreviewWindowIdentity(visible)] && mixedMinimize.succeeded.map(\.id)==[103])
precondition(WindowUtil.minimizedRequests.last==true,"Busy filtering reversed window toggle intent")
protected.finish()
let afterRelease=await WindowUtil.performPreviewBatchAction(.quit,on:[visible])
precondition(afterRelease.failed.isEmpty && visibleApp.normal==1,"Completed request left targets busy")
let pending=PendingAX();WindowUtil.pendingMinimize=pending
let earlier=Task {await WindowUtil.performPreviewBatchAction(.minimize,on:[visible])}
for _ in 0..<1000 where !pending.started {await Task.yield()}
precondition(pending.started,"Standalone worker did not start")
let newerTask=Task {await WindowUtil.performPreviewBatchAction(.minimize,on:[visible])}
try? await Task.sleep(nanoseconds:10_000_000)
pending.release();let superseded=await earlier.value;let newer=await newerTask.value
precondition(newer.succeeded.map(\.id)==[100])
precondition(superseded.succeeded.isEmpty,"Standalone superseded worker did not receive cancellation")
let clean=WindowActionOwnership.shared.begin([PreviewWindowIdentity(visible)])
precondition(clean.admitted.count==1);clean.finish()
let unsupported=WindowInfo(id:200,app:visibleApp,isFullscreen:true)
let appMinimize=App(40)
let restoredMember=WindowInfo(id:400,app:appMinimize), minimizedMember=WindowInfo(id:401,app:appMinimize,isMinimized:true)
let fullMember=WindowInfo(id:402,app:appMinimize,isFullscreen:true), windowlessMember=WindowInfo(id:0,app:appMinimize,isWindowlessApp:true)
WindowUtil.cached[40]=[restoredMember,minimizedMember,fullMember,windowlessMember]
let appGroup=await WindowUtil.performPreviewBatchAction(.minimizeAllWindows,on:[restoredMember])
precondition(appGroup.succeeded.map(\.id)==[400,401] && appGroup.failed.isEmpty && WindowUtil.minimizedRequests.last==true)
var nowMinimized=restoredMember;nowMinimized.isMinimized=true
WindowUtil.cached[40]=[nowMinimized,minimizedMember,fullMember,windowlessMember]
let restoreAppGroup=await WindowUtil.performPreviewBatchAction(.minimizeAllWindows,on:[nowMinimized])
precondition(restoreAppGroup.succeeded.map(\.id)==[400,401] && restoreAppGroup.failed.isEmpty && WindowUtil.minimizedRequests.last==false)
WindowUtil.cached.removeAll()
print("PASS shared app-level Minimize toggle: cached app expansion, mixed-state minimize, all-minimized restore and fullscreen/windowless exclusions")
let invalid=await WindowUtil.performPreviewBatchAction(.minimize,on:[unsupported])
precondition(invalid.failed == [PreviewWindowIdentity(unsupported)],"Unsupported explicit attempt falsely succeeded")
Defaults.autoFill=true;Defaults.limited=true;Defaults.rows=1;Defaults.columns=1
let capOne=WindowInfo(id:201,app:visibleApp),capTwo=WindowInfo(id:202,app:visibleApp)
let capped=await WindowUtil.performPreviewBatchAction(.fillLeftHalf,on:[capOne,capTwo])
precondition(WindowUtil.tileCalls.last == [201] && capped.succeeded.map(\.id)==[201] && capped.failed.isEmpty,"Tiling exclusion changed original group intent")
let mixed=await WindowUtil.performPreviewBatchAction(.fillLeftHalf,on:[unsupported,capTwo])
precondition(WindowUtil.tileCalls.last == [202] && mixed.succeeded.map(\.id)==[202] && mixed.failed.isEmpty,"Fullscreen exclusion must precede capacity without changing Fill-to-Auto-Tile intent")
let beforeEmpty=WindowUtil.tileCalls.count
let allFullscreen=await WindowUtil.performPreviewBatchAction(.autoTileSelectedWindows,on:[unsupported])
precondition(allFullscreen.failed.isEmpty && allFullscreen.succeeded.isEmpty && WindowUtil.tileCalls.count==beforeEmpty)
let available=WindowActionOwnership.shared.begin([PreviewWindowIdentity(unsupported)])
precondition(available.admitted.count==1);available.finish()
let protectedTile=WindowActionOwnership.shared.begin([PreviewWindowIdentity(capOne)],protect:true)
let tileRefusal=ActionFeedbackHandle()
let busyTile=await WindowUtil.performPreviewBatchAction(.autoTileSelectedWindows,on:[unsupported,capOne,capTwo],feedback:tileRefusal)
precondition(busyTile.succeeded.isEmpty && busyTile.failed==[PreviewWindowIdentity(capOne)],"Busy eligible targets must fail without refilling intentional capacity exclusions")
protectedTile.finish()
Defaults.autoFill=false;Defaults.limited=false;Defaults.rows=2;Defaults.columns=3
precondition(WindowAction.fillLeftHalf.previewTargets(from:[unsupported,capOne]).map(\.id)==[200,201],"Independent Fill eligibility changed")
let geometry=[WindowInfo(id:300,app:visibleApp),WindowInfo(id:301,app:visibleApp)]
func started(_ gate:PendingAX) async {
 for _ in 0..<2000 {if gate.started {return};try? await Task.sleep(nanoseconds:1_000_000)}
 preconditionFailure("Geometry worker did not reach gate")
}
let placementGate=PendingAX(),placingFeedback=ActionFeedbackHandle()
WindowUtil.pendingPosition[301]=placementGate
let placing=Task {await WindowUtil.performPreviewBatchAction(.center,on:geometry,feedback:placingFeedback)}
await started(placementGate)
precondition(placingFeedback.states[PreviewWindowIdentity(geometry[0])] == .completed && placingFeedback.states[PreviewWindowIdentity(geometry[1])] == nil,"Completed geometry waited for the entire group")
precondition(WindowUtil.positionCalls==[300,301] && WindowUtil.focusCalls.isEmpty)
let stillOwned=WindowUtil.beginPreviewActionRequest(.center,windows:[geometry[0]])
precondition(stillOwned.admitted.isEmpty,"Feedback completion released active batch ownership")
stillOwned.finish()
Defaults.foreground=true
placementGate.release();let placed=await placing.value
precondition(placed.succeeded.map(\.id)==[300,301] && placed.failed.isEmpty && WindowUtil.focusCalls.isEmpty,"Preference changes altered in-flight geometry intent")
Defaults.foreground=true;WindowUtil.positionCalls=[]
let focusGate=PendingAX(),focusingFeedback=ActionFeedbackHandle()
WindowUtil.pendingFocus[300]=focusGate;WindowUtil.focusFailures=[301]
let focusing=Task {await WindowUtil.performPreviewBatchAction(.center,on:geometry,feedback:focusingFeedback)}
await started(focusGate)
precondition(focusingFeedback.states[PreviewWindowIdentity(geometry[1])] == .failed && focusingFeedback.states[PreviewWindowIdentity(geometry[0])] == nil,"Geometry settled before required foregrounding or lost a failure")
precondition(WindowUtil.positionCalls==[300,301] && WindowUtil.focusCalls==[301,300],"Progress reordered or duplicated geometry/focus work")
focusGate.release();let focused=await focusing.value
precondition(focused.failed==[PreviewWindowIdentity(geometry[1])] && focusingFeedback.states[PreviewWindowIdentity(geometry[0])] == .completed)
WindowUtil.offSpace=[300,301];WindowUtil.focusCalls=[];WindowUtil.focusFailures=[]
let offFeedback=ActionFeedbackHandle()
_ = await WindowUtil.performPreviewBatchAction(.center,on:geometry,feedback:offFeedback)
precondition(WindowUtil.focusCalls.isEmpty && offFeedback.states.values.allSatisfy {$0 == .completed} && offFeedback.states.count==2,"Off-Space geometry was activated or left unsettled")
Defaults.foreground=false;WindowUtil.offSpace=[]
let acceptedSpace=ActionFeedbackHandle()
_ = await WindowUtil.performPreviewBatchAction(.bringToCurrentSpace,on:geometry,feedback:acceptedSpace)
precondition(WindowUtil.spaceCalls==[300,301] && acceptedSpace.states.count==2 && acceptedSpace.states.values.allSatisfy {$0 == .requested},"Legacy Space request acceptance was reported as verified completion")
print("PASS geometry progress: per-target settlement, confirmed reverse foreground order, failures, off-Space preservation and no added operation calls")
print("PASS shared target accounting: explicit invalid failure and frozen group Fill with 1x1 capacity")
print("PASS shared executor admission: atomic app rejection, partial failures, frozen Hide/Minimize intent and cleanup")
  print("PASS normal/force dispatch, PID deduplication, windowless targets, acknowledgements, refusal, terminated targets, Close-to-Quit and cancellation")
 }
}
SWIFT
Dir.mktmpdir('dockfork-quit-actions-') do |dir|
  path = "#{dir}/checks.swift"; File.write(path, with_action_ownership(source))
  abort 'Swift compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', '-suppress-warnings', path, '-o', "#{dir}/checks")
  abort 'Quit checks failed' unless system("#{dir}/checks")
end
puts 'PASS catalog/menu/default wiring and unchanged Dock Quick Quit; all termination calls used inert apps'

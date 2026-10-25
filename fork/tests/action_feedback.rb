#!/usr/bin/env ruby
# Execute the production feedback state machine with inert panels/monitors; no live preferences or windows.
require 'tmpdir'
require_relative 'support/action_ownership'
require 'open3'
ROOT = File.expand_path('../..', __dir__)
source = File.read("#{ROOT}/DockDoor/Utilities/Window Gestures/WindowGestureHUD.swift")
keys = File.read("#{ROOT}/DockDoor/consts.swift")
view = File.read("#{ROOT}/DockDoor/Views/Settings/KeybindsSettingsView.swift")
behavior_view = File.read("#{ROOT}/DockDoor/Views/Settings/WindowSwitcherBehaviorSettingsView.swift")
catalog = File.read("#{ROOT}/DockDoor/Views/Settings/Search/SettingsSearchCatalog.swift")
%w[enableActionFeedback actionFeedbackPosition showMouseFollowsFocusFeedback].each do |key|
  target_view, prefix = key == 'showMouseFollowsFocusFeedback' ? [behavior_view, 'windowSwitcher'] : [view, 'gestures']
  abort "Missing reset: #{key}" unless File.read("#{ROOT}/DockDoor/Views/Settings/MainSettingsView.swift").include?(".#{key}")
  abort "Missing search target: #{key}" unless target_view.include?("settingsSearchTarget(\"#{prefix}.#{key}\")")
  abort "Missing/duplicate search entry: #{key}" unless catalog.scan("id: \"#{prefix}.#{key}\"").size == 1
end
abort 'Cursor hint must live below Mouse follows focus, not in Action Feedback' unless behavior_view.index('windowSwitcher.mouseFollowsFocus') < behavior_view.index('windowSwitcher.showMouseFollowsFocusFeedback') && !view.include?('showMouseFollowsFocusFeedback') && !catalog.include?('gestures.showMouseFollowsFocusFeedback')
abort 'Cursor hint must hide when unavailable, not disable' unless behavior_view.include?('Toggle("Show feedback popup",') && behavior_view.include?('if mouseFollowsFocusMode != .never, enableActionFeedback {') && !behavior_view.include?('.disabled(mouseFollowsFocusMode == .never || !enableActionFeedback)')
helper = "Show a popup at the cursor's new location. Requires action feedback to be enabled."
abort 'Cursor hint search text must match its control' unless behavior_view.include?("Text(\"#{helper}\")") && catalog.include?("description: String(localized: \"#{helper}\")")
abort 'Removed consolidation setting remains wired' if [source, keys, view, catalog, File.read("#{ROOT}/DockDoor/Views/Settings/MainSettingsView.swift")].any? { |text| text.include?('animateActionFeedbackConsolidation') }
abort 'Consolidation must only fade' if source.include?('towards destination:')
abort 'Feedback default must remain off' unless keys.include?('Key<Bool>("enableActionFeedback", default: false)')
abort 'Mouse follows focus feedback must default off' unless keys.include?('Key<Bool>("showMouseFollowsFocusFeedback", default: false)')
abort 'Space-transition timing workaround must stay removed' if %w[prepareForSpaceTransition deferResultDismissal spaceTransitionTask spaceTransitionPending workspaceObservation activeSpaceDidChangeNotification].any? { |name| source.include?(name) }
%w[Utilities/Window\ Gestures/WindowGestureExecutor.swift Utilities/Window\ Management/WindowUtil.swift Views/Hover\ Window/Shared\ Components/SharedPreviewWindowCoordinator.swift].each do |path|
  abort "Leftover feedback transition hook in #{path}" if File.read("#{ROOT}/DockDoor/#{path}").include?('prepareForSpaceTransition')
end
abort 'Native all-Spaces popup behavior must remain' unless source.include?('.canJoinAllSpaces, .fullScreenAuxiliary')
abort 'Unexpected timing change' unless source.include?('initiated: TimeInterval = 0.7') && source.include?('result: TimeInterval = 0.35')
abort 'Cursor motion must not measure popup contents' if source[source.index('    func followCursor()')...source.index('    private func targetFrame')].include?('fittingSize')
abort 'Popup must not slide or animate its frame' unless source.include?('animationBehavior = .none') && !source[source.index('final class ActionPopupPanel:')...source.index('final class ActionFeedbackController')].include?('animator().setFrame')
abort 'Popup content updates must not restart fade-in' unless source.include?('let needsFadeIn = !isVisible || isFadingOut') && source.include?('if needsFadeIn {')
abort 'Scripts must stay feedback-free' if File.read("#{ROOT}/DockDoor/Utilities/ScriptCommands.swift").include?('ActionFeedbackController')

abort 'Success symbol policy must not suppress accessibility completion or change gesture defaults' unless source.include?('var showsSuccessSymbol = true') && source.include?('else if content.isSuccess, content.showsSuccessSymbol {') && source.include?('result.isSuccess = outcome == .completed')

abort 'Shared popup must retain gesture-overlay exclusion' unless source.include?('WindowGestureOverlays.register(windowNumber)') && source.include?('WindowGestureOverlays.unregister(windowNumber)')

stubs = <<~'SWIFT'
import AppKit
struct Key<T> { let value: T; var name: String = "" }
enum Defaults {
 protocol Serializable {}
 static var enabled = false, position = ActionFeedbackPosition.trigger, mouseFeedback = false, limitedTiling = false
 static var callbacks: [UUID: (Change) -> Void] = [:]
 static var gestures = true, observationKeys: [UUID: String] = [:]
 struct Change { let newValue: Bool }
 final class Observation { let id: UUID; init(_ id: UUID) { self.id = id }; func invalidate() { Defaults.callbacks[id] = nil; Defaults.observationKeys[id] = nil } }
 static subscript<T>(_ key: Key<T>) -> T { key.value }
 static func observe(_ key: Key<Bool>, options: [Int], handler: @escaping (Change) -> Void) -> Observation {
  let id = UUID(); callbacks[id] = handler; observationKeys[id] = key.name; return Observation(id)
 }
 static func disable() { enabled = false; for (id, f) in callbacks where observationKeys[id] != "gestures" { f(Change(newValue: false)) } }
 static func disableGestures() { gestures = false; for (id, f) in callbacks where observationKeys[id] == "gestures" { f(Change(newValue: false)) } }
}
extension Key where T == Bool {
 static var enableActionFeedback: Self { Self(value: Defaults.enabled) }
 static var enableWindowGestures: Self { Self(value: Defaults.gestures, name: "gestures") }
 static var showMouseFollowsFocusFeedback: Self { Self(value: Defaults.mouseFeedback) }
 static var tileOnlyWhatFits: Self { Self(value: Defaults.limitedTiling) }
 static var fillActionsAutoTileSelection: Self { Self(value: false) }
}
extension Key where T == Int {
 static var maximumTilingRows: Self { Self(value: 2) }
 static var maximumTilingColumns: Self { Self(value: 3) }
}
extension Key where T == ActionFeedbackPosition { static var actionFeedbackPosition: Self { Self(value: Defaults.position) } }
struct PreviewWindowIdentity: Hashable { let pid: Int32; let windowID: UInt32; init(pid: Int32, windowID: UInt32) { self.pid = pid; self.windowID = windowID }; init(_ w: WindowInfo) { self.init(pid: w.app.processIdentifier, windowID: w.id) } }
struct TestApp { let processIdentifier: Int32; let isHidden: Bool }
struct WindowInfo { enum WindowPositionRect: Equatable { case test }; let id: UInt32; var pid: Int32 = 1; var isFullscreen: Bool? = false; var isMinimized = false; var isHidden = false; var isWindowlessApp = false; var isWineWindow = false; var app: TestApp { TestApp(processIdentifier: pid, isHidden: isHidden) } }
enum WindowAction { case bringToCurrentSpace, maximize, center, fillLeftHalf, fillRightHalf, fillTopHalf, fillBottomHalf, fillTopLeftQuarter, fillTopRightQuarter, fillBottomLeftQuarter, fillBottomRightQuarter, openNewWindow, quit, forceQuit, none, toggleWindowSelection, selectAllWindows, openAppWindow, close, closeAllWindows, minimize, minimizeAllWindows, hide, toggleFullScreen, autoTileSelectedWindows
 /* Action names */
 /* Shared target eligibility */
 var positionRect: WindowInfo.WindowPositionRect? { [.center,.maximize,.fillLeftHalf,.fillRightHalf,.fillTopHalf,.fillBottomHalf,.fillTopLeftQuarter,.fillTopRightQuarter,.fillBottomLeftQuarter,.fillBottomRightQuarter].contains(self) ? .test : nil }
 func autoTilingDirection(windowCount: Int, fillActionsAutoTile: Bool) -> Int? { self == .autoTileSelectedWindows ? 0 : nil }
 func menuTitle(for w: WindowInfo, batchTargets: [WindowInfo]?) -> String {
  switch self { case .close: "Close Window"; case .closeAllWindows: "Close All Windows"; case .minimizeAllWindows: "Minimize All Windows"; default: "Other Action" }
 }
 /* Shared batch targets */
 /* Batch target state */
 /* Feedback title */
 var iconName: String { self == .minimizeAllWindows ? "minus.circle.fill" : "xmark" }
 /* Menu icon */
}
enum WindowUtil {
 /* Auto Tile eligibility */
 static var cachedWindows: [WindowInfo] = []
 static func readCachedWindows(for pid: Int32) -> [WindowInfo] { cachedWindows.filter { $0.app.processIdentifier == pid } }
 struct PreviewBatchResult { var succeeded: [WindowInfo] = []; var failed: [PreviewWindowIdentity] = [] }
}
final class PreviewStateCoordinator {
 enum SelectionInputSource { case mouse, keyboard, programmatic }
 var selectionInputSource = SelectionInputSource.programmatic
 var actionFeedbackGrid: Grid? = Grid()
}
final class Grid {
 var missing = Set<PreviewWindowIdentity>()
 func feedbackFrame(for id: PreviewWindowIdentity) -> CGRect? { missing.contains(id) ? nil : CGRect(x: 100, y: 100, width: 200, height: 150) }
}
final class SharedPreviewWindowCoordinator: NSObject {
 static var activeInstance: SharedPreviewWindowCoordinator? = SharedPreviewWindowCoordinator()
 var isVisible = true
 let windowSwitcherCoordinator = PreviewStateCoordinator()
}
enum WindowGestureHUD {
 /* Popup content */
}
@MainActor final class ActionPopupPanel {
 static var fades = true, motion = true, creates = 0, live = 0, cursorUpdates = 0
 var frame = CGRect(x: 10, y: 10, width: 100, height: 40)
 var value: WindowGestureHUD.Content?
 private var closed = false
 init() { Self.creates += 1; Self.live += 1 }
 var cursor: CGPoint?
 func present(_ content: WindowGestureHUD.Content, center: CGPoint? = nil, cursor: CGPoint? = nil) { value = content; self.cursor = cursor }
 func followCursor() { Self.cursorUpdates += 1 }
 func hide(closeAfter: Bool = false, completion: (() -> Void)? = nil) {
 Task { @MainActor in
  if Self.fades { try? await Task.sleep(nanoseconds: UInt64(ActionPopupTiming.fadeOut * 1_000_000_000)) }
  if closeAfter { close() }; completion?()
 }
}
 func close() { if !closed { closed = true; Self.live -= 1 } }
}
enum TestEvent {
 typealias EventTypeMask = NSEvent.EventTypeMask
 static let mouseLocation = CGPoint(x: 200, y: 200)
 static var monitors: Set<UUID> = []
 static var localHandler: ((NSEvent) -> NSEvent?)?
 static func addLocalMonitorForEvents(matching: EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? { let id = UUID(); monitors.insert(id); localHandler = handler; return id }
 static func addGlobalMonitorForEvents(matching: EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? { let id = UUID(); monitors.insert(id); return id }
 static func removeMonitor(_ monitor: Any) { monitors.remove(monitor as! UUID); if monitors.isEmpty { localHandler = nil } }
}
SWIFT
stubs.sub!('/* Popup content */', source[source.index('    struct Content: Equatable {')...source.index('    private var tooltipPanel:')])
actions = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowActionCatalog.swift")
util_source = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowUtil.swift")
stubs.sub!('/* Auto Tile eligibility */', util_source[util_source.index('    static func autoTileTargets(')...util_source.index("    @MainActor\n    static func tilePreviewWindows(")])
stubs.sub!('/* Action names */', block(util_source[util_source.index('    // Existing actions')..], '    var localizedName:'))
stubs.sub!('/* Shared target eligibility */', block(actions, '    enum TargetScope:') + "\n" + block(actions, '    var targetScope:') + "\n" + block(actions, '    func selectedPreviewTargets(') + "\n" + actions[actions.index('    func isSupported(')...actions.index('    func usesConfirmedSingleWindowAction(')] + actions[actions.index('    func appliesToSelectedWindow(')...actions.index('    func batchTargets(')])
stubs.sub!('/* Shared batch targets */', actions[actions.index('    func batchTargets(')...actions.index('    func batchTargetState(')] + actions[actions.index('    var isAppWidePreviewAction:')...actions.index('    enum Group:')])
stubs << actions[actions.index('enum PreviewBatchTogglePolicy {')...actions.index('struct WindowActionGroup:')]
stubs.sub!('/* Batch target state */', actions[actions.index('    func batchTargetState(')...actions.index('    var isAppWidePreviewAction:')])
stubs.sub!('/* Feedback title */', actions[actions.index('    func feedbackTitle(')...actions.index('    func menuTitle(')])
stubs.sub!('/* Menu icon */', actions[actions.index('    func menuIcon(')...actions.rindex("\n}")])
position = source[source.index('enum ActionFeedbackPosition:')...source.index('enum ActionFeedbackOutcome:')]
handle = source[source.index('enum ActionFeedbackOutcome:')...source.index('@MainActor\nfinal class ActionPopupPanel'.gsub('\\n', "\n"))]
controller = source[source.index('@MainActor\nfinal class ActionFeedbackController'.gsub('\\n', "\n"))..].gsub('NSEvent.', 'TestEvent.')
timing = source[source.index('enum ActionPopupTiming {')...source.index('enum ActionFeedbackPosition:')]
# Faster presentation-only clock in the fixture. The production numeric constants are checked above.
timing = timing.gsub('= 0.7', '= 0.07').gsub('= 0.35', '= 0.035').gsub('= 0.16', '= 0.016').gsub('= 0.14', '= 0.014')
checks = <<~'SWIFT'
extension ActionFeedbackController {
 var snapshot: (Bool, Bool, Int, Int, WindowGestureHUD.Content?) { (cursorMode, handingOff, entries.values.filter { $0.outcome != nil }.count, order.count, aggregate?.value) }
 var busyCount: Int { entries.values.filter { $0.panel?.value?.isBusy == true }.count }
 var previewContents: [WindowGestureHUD.Content] { entries.values.compactMap { $0.panel?.value } }
 var hasResultDeadline: Bool { aggregateTask != nil || !resultTasks.isEmpty }
 var cursorAnchor: CGPoint? { aggregate?.cursor }
}
@main struct Checks {
 @MainActor static func pause(_ milliseconds: UInt64) async { try? await Task.sleep(nanoseconds: milliseconds * 1_000_000) }
 @MainActor static func waitUntil(_ condition: () -> Bool) async {
  for _ in 0..<200 {
   if condition() { return }
   await pause(5)
  }
  preconditionFailure("Feedback condition did not settle within one second")
 }
 @MainActor static func waitForCleanup() async {
  await waitUntil { ActionFeedbackController.existing == nil && ActionPopupPanel.live == 0 }
 }
 @MainActor static func main() async {
  let windows = [WindowInfo(id: 1), WindowInfo(id: 2)]
  let first = PreviewWindowIdentity(windows[0]), second = PreviewWindowIdentity(windows[1])
  precondition(WindowAction.minimize.feedbackTitle(for: windows[0], batchTargets: windows) == "Minimize")
  var minimized = windows; minimized[0].isMinimized = true; minimized[1].isMinimized = true
  precondition(WindowAction.minimize.feedbackTitle(for: minimized[0], batchTargets: minimized) == "Un-minimize")
  precondition(WindowAction.minimize.feedbackTitle(for: minimized[0], batchTargets: [minimized[0], windows[1]]) == "Minimize")
  var hidden = windows; hidden[0].isHidden = true; hidden[1].isHidden = true
  precondition(WindowAction.hide.feedbackTitle(for: hidden[0], batchTargets: hidden) == "Unhide App")
  var otherApp = windows[1]; otherApp.pid = 2
  precondition(WindowAction.hide.feedbackTitle(for: hidden[0], batchTargets: [hidden[0], otherApp]) == "Hide App")
  var fullscreen = windows; fullscreen[0].isFullscreen = true
  precondition(WindowAction.toggleFullScreen.feedbackTitle(for: fullscreen[0], batchTargets: fullscreen) == "Exit Full Screen")
  precondition(WindowAction.autoTileSelectedWindows.feedbackTitle(for: windows[0], batchTargets: windows) == "Auto Tile")
  precondition(WindowAction.close.feedbackTitle(for: windows[0], batchTargets: windows) == "Close")
  for action in [WindowAction.close, .closeAllWindows] {
   precondition(action.feedbackTitle(for: windows[0]) == "Close")
   precondition(action.feedbackTitle(for: windows[0], batchTargets: windows) == "Close")
  }
  WindowUtil.cachedWindows = minimized
  precondition(WindowAction.minimizeAllWindows.feedbackTitle(for: minimized[0]) == "Un-minimize")
  precondition(WindowAction.minimizeAllWindows.feedbackTitle(for: minimized[0], batchTargets: minimized) == "Un-minimize")
  precondition(WindowAction.minimizeAllWindows.menuIcon(for: minimized[0]) == "arrow.up.left.and.arrow.down.right.square")
  WindowUtil.cachedWindows = [minimized[0], windows[1]]
  precondition(WindowAction.minimizeAllWindows.feedbackTitle(for: minimized[0]) == "Minimize")
  precondition(WindowAction.minimizeAllWindows.menuIcon(for: minimized[0]) == "minus.circle.fill")
  precondition(WindowAction.minimize.feedbackTitle(for: minimized[0]) == "Un-minimize")
  WindowUtil.cachedWindows = [minimized[0], fullscreen[0]]
  precondition(WindowAction.minimizeAllWindows.feedbackTitle(for: minimized[0]) == "Un-minimize")
  precondition(WindowAction.minimizeAllWindows.menuTitle(for: minimized[0], batchTargets: nil) == "Minimize All Windows")
  WindowUtil.cachedWindows = []
  precondition(ActionPopupTiming.resultDuration(failed: true) == ActionPopupTiming.result * 2)
  precondition(ActionPopupTiming.resultDuration(failed: false) == ActionPopupTiming.result)
  for keyboard in [false, true] {
   precondition(!ActionFeedbackPosition.cursor.usesPreviews(keyboardTrigger: keyboard, focus: .keyboard))
   precondition(ActionFeedbackPosition.preview.usesPreviews(keyboardTrigger: keyboard, focus: .mouse))
   precondition(ActionFeedbackPosition.trigger.usesPreviews(keyboardTrigger: keyboard, focus: .mouse) == keyboard)
   precondition(ActionFeedbackPosition.focus.usesPreviews(keyboardTrigger: keyboard, focus: .programmatic) == keyboard)
   precondition(!ActionFeedbackPosition.focus.usesPreviews(keyboardTrigger: keyboard, focus: .mouse))
   precondition(ActionFeedbackPosition.focus.usesPreviews(keyboardTrigger: keyboard, focus: .keyboard))
  }
  precondition(ActionFeedbackController.begin(.close, windows: windows) == nil)
  Defaults.mouseFeedback = true
  ActionFeedbackController.mouseFollowedFocus()
  precondition(ActionPopupPanel.creates == 0 && TestEvent.monitors.isEmpty && Defaults.callbacks.isEmpty)
  Defaults.mouseFeedback = false
  Defaults.enabled = true
  WindowUtil.cachedWindows = minimized
  let headerRestore = ActionFeedbackController.begin(.minimizeAllWindows, windows: minimized, usePreviews: false)!
  precondition(ActionFeedbackController.existing!.snapshot.4!.title == "Un-minimize")
  precondition(ActionFeedbackController.existing!.snapshot.4!.symbolName == "arrow.up.left.and.arrow.down.right.square")
  headerRestore.finish(first, .completed)
  precondition(ActionFeedbackController.existing!.snapshot.2 == 1 && ActionFeedbackController.existing!.snapshot.3 == 2)
  headerRestore.finish(second, .completed)
  await waitForCleanup()
  let headerClose = ActionFeedbackController.begin(.closeAllWindows, windows: windows, usePreviews: false)!
  precondition(ActionFeedbackController.existing!.snapshot.4!.title == "Close")
  headerClose.finish(first, .requested); headerClose.finish(second, .requested)
  await waitForCleanup()
  WindowUtil.cachedWindows = []
let thirdWindow = WindowInfo(id: 3)
let thirdID = PreviewWindowIdentity(thirdWindow)
let counting = ActionFeedbackController.begin(.minimize, windows: windows + [thirdWindow], usePreviews: false)!
let confirmed = counting.confirmedProgress
DispatchQueue.global().sync {
 confirmed(first, true); confirmed(first, true); confirmed(second, false)
}
// The main queue has not drained the background notification yet.
counting.finish(first, .completed)
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "2/3")
counting.finish(WindowUtil.PreviewBatchResult(succeeded: [windows[0]], failed: [second, thirdID]))
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "1/3" && ActionFeedbackController.existing!.snapshot.4!.isWarning)
counting.finishRemaining(.cancelled)
await waitForCleanup()
print("PASS confirmed progress survives final-result delivery before main-queue drain; stable identities settle once")
for action in [WindowAction.close, .closeAllWindows, .minimize, .autoTileSelectedWindows] {
 let shared = ActionFeedbackController.begin(action,windows:windows,usePreviews:false)!
 DispatchQueue.global().sync {shared.finish(first,.failed);shared.finish(second,.requested)}
 shared.finishRemaining(.requested)
 precondition(ActionFeedbackController.existing!.entries[first]?.outcome == .failed,"Final summary overtook a background failure")
 precondition(ActionFeedbackController.existing!.entries[second]?.outcome == .requested)
 await waitForCleanup()
}
print("PASS all action outcomes share delivery buffering; final summaries cannot overwrite background failures/acknowledgements")

let appWindows = windows + [thirdWindow]
let hiddenApp = ActionFeedbackController.begin(.hide, windows: appWindows, usePreviews: false)!
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == nil)
hiddenApp.finish(first, .completed)
precondition(ActionFeedbackController.existing!.snapshot.2 == 3 && ActionFeedbackController.existing!.snapshot.4!.counter == nil)
await waitForCleanup()
var sameIDOtherApp = windows[0]; sameIDOtherApp.pid = 2
let otherID = PreviewWindowIdentity(sameIDOtherApp)
let multipleApps = ActionFeedbackController.begin(.hide, windows: windows + [sameIDOtherApp], usePreviews: false)!
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "0/2")
multipleApps.finish(first, .completed)
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "1/2" && ActionFeedbackController.existing!.snapshot.2 == 2)
multipleApps.finish(otherID, .failed)
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "1/2" && ActionFeedbackController.existing!.snapshot.4!.isWarning)
await waitForCleanup()
print("PASS Hide counts apps once, fans results to same-app previews, and keeps equal window IDs in different apps distinct")
Defaults.position = .preview
let previewHide = ActionFeedbackController.begin(.hide, windows: windows + [sameIDOtherApp])!
previewHide.finish(first,.completed)
precondition(ActionFeedbackController.existing!.previewContents.filter(\.isSuccess).count == 2)
SharedPreviewWindowCoordinator.activeInstance!.isVisible = false
ActionFeedbackController.existing!.refreshAnchors()
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "1/2")
previewHide.finish(otherID,.failed)
await waitForCleanup()
SharedPreviewWindowCoordinator.activeInstance!.isVisible = true
Defaults.position = .cursor
let distinctWindows = ActionFeedbackController.begin(.minimize,windows:[windows[0],sameIDOtherApp],usePreviews:false)!
let distinctCallback = distinctWindows.confirmedProgress
DispatchQueue.global().sync {distinctCallback(first,true);distinctCallback(otherID,true)}
distinctWindows.finishRemaining(.failed)
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "2/2")
await waitForCleanup()
let superseded = ActionFeedbackController.begin(.minimize,windows:windows,usePreviews:false)!
let staleCallback = superseded.confirmedProgress
let current = ActionFeedbackController.begin(.minimize,windows:windows,usePreviews:false)!
DispatchQueue.global().sync {staleCallback(first,true)}
current.finish(second,.completed)
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "1/2")
current.finish(first,.completed)
await waitForCleanup()
print("PASS per-preview Hide fanout/consolidation, equal IDs across apps, and stale progress rejection")


WindowUtil.cachedWindows = windows + [thirdWindow]
let expanded = ActionFeedbackController.begin(.minimizeAllWindows, windows: [windows[0]], usePreviews: false)!
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "0/3")
let callback = expanded.confirmedProgress
DispatchQueue.global().sync {
 expanded.setTargets([windows[0],thirdWindow,thirdWindow]);callback(first,true);callback(thirdID,true)
}
expanded.finishRemaining(.failed)
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "2/2" && ActionFeedbackController.existing!.snapshot.4!.isSuccess)
await waitForCleanup()
WindowUtil.cachedWindows = []
var windowless = thirdWindow;windowless.isWindowlessApp = true
var full = thirdWindow;full.isFullscreen = true
precondition(WindowAction.minimize.previewTargets(from: windows + [windowless,full,windows[0]]).map(\.id) == [1,2])
WindowUtil.cachedWindows = [full]
precondition(WindowAction.hide.previewTargets(from: [full]).isEmpty)
WindowUtil.cachedWindows = []
Defaults.limitedTiling = true
let many = (1...8).map {WindowInfo(id: UInt32($0))}
precondition(WindowAction.autoTileSelectedWindows.previewTargets(from: many).count == 6)
var tiledFull=WindowInfo(id:99);tiledFull.isFullscreen=true
precondition(WindowAction.autoTileSelectedWindows.previewTargets(from: [tiledFull,windowless] + many).map(\.id) == Array(1...6).map(UInt32.init))
precondition(WindowAction.autoTileSelectedWindows.previewTargets(from: [full]).isEmpty)
let tileFeedback = ActionFeedbackController.begin(.autoTileSelectedWindows,windows:[full] + windows,usePreviews:false)!
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "0/2")
tileFeedback.finishRemaining(.completed)
await waitForCleanup()
Defaults.limitedTiling = false
print("PASS shared eligibility: Minimize All expansion, actual-snapshot reconciliation, duplicates, windowless/fullscreen exclusions and tiling limits")

// Success decoration depends on the popup's own presented spinner, not group size or elapsed time.
for position in [ActionFeedbackPosition.cursor, .preview] {
 Defaults.position = position
 for targets in [[windows[0]], windows] {
  let fast = ActionFeedbackController.begin(.minimize, windows: targets)!
  fast.finishRemaining(.completed)
  let contents = position == .cursor ? [ActionFeedbackController.existing!.snapshot.4!] : ActionFeedbackController.existing!.previewContents
  precondition(contents.allSatisfy { !$0.isBusy && $0.isSuccess && !$0.showsSuccessSymbol && $0.symbolName == "xmark" && $0.accessibilityTitle == "Minimize completed" })
  await waitForCleanup()
  for outcome in [ActionFeedbackOutcome.completed, .requested, .failed, .cancelled] {
   let slow = ActionFeedbackController.begin(.minimize, windows: targets)!
   await waitUntil {
    position == .cursor ? ActionFeedbackController.existing?.snapshot.4?.isBusy == true : ActionFeedbackController.existing?.busyCount == targets.count
   }
   slow.finishRemaining(outcome)
   let results = position == .cursor ? [ActionFeedbackController.existing!.snapshot.4!] : ActionFeedbackController.existing!.previewContents
   precondition(results.allSatisfy { !$0.isBusy && $0.showsSuccessSymbol && $0.isSuccess == (outcome == .completed) && $0.isWarning == (outcome == .failed) && $0.isCancelled == (outcome == .cancelled) })
   await waitForCleanup()
  }
 }
}
Defaults.position = .preview
let mixedSpeed = ActionFeedbackController.begin(.minimize, windows: windows)!
mixedSpeed.finish(first, .completed)
await waitUntil { ActionFeedbackController.existing?.busyCount == 1 }
precondition(ActionFeedbackController.existing!.entries[first]!.expired)
precondition(ActionFeedbackController.existing!.entries[first]!.panel!.value!.showsSuccessSymbol == false)
mixedSpeed.finish(second, .completed)
precondition(ActionFeedbackController.existing!.entries[second]!.panel!.value!.showsSuccessSymbol && ActionFeedbackController.existing!.entries[second]!.panel!.value!.isSuccess)
await waitForCleanup()
// Carry a visible spinner through disappearance, including completion during the fade handoff.
let consolidating = ActionFeedbackController.begin(.minimize, windows: windows)!
await waitUntil { ActionFeedbackController.existing?.busyCount == 2 }
ActionFeedbackController.existing!.previewWillDisappear(SharedPreviewWindowCoordinator.activeInstance!)
consolidating.finishRemaining(.completed)
precondition(ActionFeedbackController.existing!.snapshot.4!.isSuccess && ActionFeedbackController.existing!.snapshot.4!.showsSuccessSymbol)
await waitForCleanup()
let completedPreview = ActionFeedbackController.begin(.minimize, windows: [windows[0]])!
await waitUntil { ActionFeedbackController.existing?.busyCount == 1 }
completedPreview.finishRemaining(.completed)
ActionFeedbackController.existing!.previewWillDisappear(SharedPreviewWindowCoordinator.activeInstance!)
precondition(ActionFeedbackController.existing!.snapshot.4!.isSuccess && ActionFeedbackController.existing!.snapshot.4!.showsSuccessSymbol)
await waitForCleanup()
// A replacement starts fresh, even when it immediately consolidates.
let oldSpinner = ActionFeedbackController.begin(.minimize, windows: windows)!
await waitUntil { ActionFeedbackController.existing?.busyCount == 2 }
let fastReplacement = ActionFeedbackController.begin(.minimize, windows: windows)!
oldSpinner.finishRemaining(.completed)
fastReplacement.finishRemaining(.completed)
ActionFeedbackController.existing!.previewWillDisappear(SharedPreviewWindowCoordinator.activeInstance!)
precondition(ActionFeedbackController.existing!.snapshot.4!.isSuccess && !ActionFeedbackController.existing!.snapshot.4!.showsSuccessSymbol)
await waitForCleanup()
print("PASS spinner-only success for single/group and cursor/preview, independent results, consolidation and replacement")

// Explicit single-window attempts may fail visibly; batch exclusions remain silent and out of totals.
for position in [ActionFeedbackPosition.cursor, .preview] {
 Defaults.position = position
 for action in [WindowAction.minimize, .minimizeAllWindows, .hide] {
  WindowUtil.cachedWindows = [full]
  let invalid = ActionFeedbackController.begin(action, windows: [full])!
  let contents = position == .cursor ? [ActionFeedbackController.existing!.snapshot.4!] : ActionFeedbackController.existing!.previewContents
  precondition(contents.allSatisfy { $0.isWarning && !$0.isSuccess && !$0.isBusy && $0.counter == nil })
  invalid.finishRemaining(.completed)
  precondition(ActionFeedbackController.existing!.entries[PreviewWindowIdentity(full)]!.outcome == .failed)
  await waitForCleanup()
 }
 WindowUtil.cachedWindows = []
 precondition(ActionFeedbackController.begin(.minimize, windows: [windowless]) == nil)
 precondition(ActionFeedbackController.begin(.autoTileSelectedWindows, windows: [full]) == nil)
 let eligibleBatch = ActionFeedbackController.begin(.minimize, windows: [full] + windows)!
 precondition(ActionFeedbackController.existing!.order == [first, second])
 eligibleBatch.finishRemaining(.completed)
 await waitForCleanup()
}
Defaults.enabled = false
let createsBeforeInvalid = ActionPopupPanel.creates
precondition(ActionFeedbackController.begin(.minimize, windows: [full]) == nil)
precondition(ActionPopupPanel.creates == createsBeforeInvalid && TestEvent.monitors.isEmpty && Defaults.callbacks.isEmpty)
Defaults.enabled = true
print("PASS invalid single-attempt failures without enabling controls, fullscreen/windowless batch exclusions and disabled zero resources")

// Fullscreen and Space feedback use ordinary result timing, not transition guesses.
for position in [ActionFeedbackPosition.cursor, .preview] {
 Defaults.position = position
 for window in [windows[0], full] {
  let fullscreenFeedback = ActionFeedbackController.begin(.toggleFullScreen, windows: [window])!
  fullscreenFeedback.finishRemaining(.completed)
  precondition(ActionFeedbackController.existing!.hasResultDeadline, "Fullscreen result waits on a guessed transition")
  await waitForCleanup()
 }
}
Defaults.position = .cursor
let navigation = ActionFeedbackController.space(2, keyboard: true)!
await waitUntil { ActionFeedbackController.existing?.snapshot.4?.isBusy == true }
navigation.finishRemaining(.completed)
precondition(ActionFeedbackController.existing!.hasResultDeadline && ActionFeedbackController.existing!.snapshot.4!.showsSuccessSymbol)
await waitForCleanup()
// Actual preview removal still consolidates pending feedback without changing operation lifetime.
Defaults.position = .preview
let disappearing = ActionFeedbackController.begin(.toggleFullScreen, windows: [windows[0]])!
ActionFeedbackController.existing!.previewWillDisappear(SharedPreviewWindowCoordinator.activeInstance!)
precondition(ActionFeedbackController.existing!.snapshot.0)
disappearing.finishRemaining(.completed)
await waitForCleanup()
let abandoned = ActionFeedbackController.begin(.toggleFullScreen, windows: [windows[0]])!
let newAction = ActionFeedbackController.begin(.minimize, windows: [windows[0]])!
abandoned.finishRemaining(.completed)
precondition(ActionFeedbackController.existing!.entries[first]!.outcome == nil)
newAction.finishRemaining(.completed)
await waitForCleanup()
let disabling = ActionFeedbackController.begin(.toggleFullScreen, windows: [windows[0]])!
Defaults.disable(); await pause(10)
disabling.finishRemaining(.completed)
precondition(ActionFeedbackController.existing == nil)
Defaults.enabled = true
print("PASS ordinary fullscreen/Space result deadlines, pending spinner, actual preview-removal consolidation, replacement and disabled cleanup without transition resources")

// Committed native gestures use the shared presenter, independently of general action feedback.
Defaults.enabled = false
let gesturePoint = CGPoint(x: 120, y: 180)
var gestureContent = WindowGestureHUD.Content(title: "Fill Left", symbolName: "rectangle.lefthalf.filled")
gestureContent.region = .test
let gestureFeedback = ActionFeedbackController.gesture(gestureContent, identities: [first], cursor: gesturePoint)!
precondition(TestEvent.monitors.isEmpty && ActionFeedbackController.existing!.snapshot.4!.region == .test)
precondition(ActionFeedbackController.existing!.cursorAnchor == gesturePoint)
Defaults.disable(); await pause(10)
precondition(ActionFeedbackController.existing != nil, "General feedback toggle disabled the gesture HUD")
await waitUntil { ActionFeedbackController.existing?.snapshot.4?.isBusy == true }
gestureFeedback.setTargets(windows)
gestureFeedback.finish(first, .completed)
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "1/2")
gestureFeedback.finish(second, .failed)
precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "1/2" && ActionFeedbackController.existing!.snapshot.4!.isWarning)
await waitForCleanup()
let cancelledGesture = ActionFeedbackController.gesture(gestureContent, identities: [first], cursor: gesturePoint)!
Defaults.disableGestures(); await pause(10)
cancelledGesture.finishRemaining(.completed)
precondition(ActionFeedbackController.existing == nil && TestEvent.monitors.isEmpty)
precondition(ActionFeedbackController.gesture(gestureContent, identities: [first], cursor: gesturePoint) == nil)
Defaults.gestures = true
let oldGesture = ActionFeedbackController.gesture(gestureContent, identities: [first], cursor: gesturePoint)!
ActionFeedbackController.stopGestureFeedback()
oldGesture.finishRemaining(.completed)
precondition(ActionFeedbackController.existing == nil)
Defaults.enabled = true
let ordinary = ActionFeedbackController.begin(.minimize, windows: [windows[0]])!
ActionFeedbackController.stopGestureFeedback()
precondition(ActionFeedbackController.existing != nil, "A gesture candidate stopped unrelated action feedback")
ordinary.finishRemaining(.completed)
await waitForCleanup()
print("PASS independent gesture enablement, fixed placement, candidate/app-flash handoff, shared group counters/results and cleanup")

  ActionFeedbackController.mouseFollowedFocus()
  precondition(ActionFeedbackController.existing == nil)
  Defaults.mouseFeedback = true
  Defaults.position = .preview
  ActionFeedbackController.mouseFollowedFocus()
  let mousePopup = ActionFeedbackController.existing!.snapshot
  precondition(mousePopup.0 && mousePopup.2 == 1 && mousePopup.3 == 1)
  precondition(mousePopup.4!.title == "Mouse Followed Focus" && mousePopup.4!.symbolName == "pointer.arrow.motionlines")
  precondition(!mousePopup.4!.isSuccess && !mousePopup.4!.isBusy && mousePopup.4!.counter == nil)
  await waitForCleanup()
  precondition(TestEvent.monitors.isEmpty && Defaults.callbacks.isEmpty)
  Defaults.mouseFeedback = false
  Defaults.position = .trigger
  for action in [WindowAction.none, .toggleWindowSelection, .selectAllWindows, .openAppWindow] { precondition(ActionFeedbackController.begin(action, windows: windows) == nil) }
ActionFeedbackController.withoutFeedback {
 precondition(ActionFeedbackController.begin(.minimize, windows: windows) == nil)
 precondition(ActionFeedbackController.space(2, window: windows[0], keyboard: true) == nil)
}
Defaults.position = .trigger
ActionFeedbackController.performKeyboardMenuAction {
 _ = ActionFeedbackController.begin(.close, windows: windows)
 precondition(ActionFeedbackController.existing!.snapshot.0 == false)
}
ActionFeedbackController.existing?.stop()
_ = ActionFeedbackController.begin(.close, windows: windows)
precondition(ActionFeedbackController.existing!.snapshot.0 == true) // scoped keyboard source restored
ActionFeedbackController.existing?.stop()
Defaults.position = .cursor
let cursor = ActionFeedbackController.begin(.close, windows: windows)!
  precondition(TestEvent.monitors.count == 2 && ActionPopupPanel.live == 1)
  precondition(!ActionFeedbackController.existing!.snapshot.4!.centersContents)
  let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
  let before = ActionPopupPanel.cursorUpdates
  for _ in 0..<50 { precondition(TestEvent.localHandler!(event) === event) }
  precondition(ActionPopupPanel.cursorUpdates == before + 50)
  cursor.finish(first, .requested); cursor.finish(first, .failed)
  cursor.finish(PreviewWindowIdentity(pid: 4, windowID: 99), .failed)
  precondition(ActionFeedbackController.existing!.snapshot.2 == 1)
  await waitUntil { ActionFeedbackController.existing?.snapshot.4?.isBusy == true }
  precondition(ActionFeedbackController.existing!.snapshot.4!.isBusy)
  cursor.finish(second, .failed)
  precondition(ActionFeedbackController.existing!.snapshot.4!.isWarning)
  precondition(!ActionFeedbackController.existing!.snapshot.4!.isSuccess)
  precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "1/2")
  precondition(ActionFeedbackController.existing!.snapshot.4!.title == "Close")
  precondition(ActionFeedbackController.existing != nil)
  await waitForCleanup()
  precondition(ActionFeedbackController.existing == nil && ActionPopupPanel.live == 0 && TestEvent.monitors.isEmpty && Defaults.callbacks.isEmpty)
  print("PASS disabled gate, placement policy, spinner delay, deduplicated settlement, partial failures, terminal cleanup")

  let four = (1...4).map { WindowInfo(id: UInt32($0)) }
  let outcomes: [([ActionFeedbackOutcome], String, Bool, Bool, Bool)] = [
   ([.completed, .completed, .completed, .failed], "3/4", true, false, false),
   ([.failed, .failed, .failed, .failed], "0/4", true, false, false),
   ([.completed, .completed, .completed, .cancelled], "3/4", false, true, false),
   ([.completed, .completed, .requested, .cancelled], "3/4", false, true, false),
   ([.completed, .completed, .cancelled, .failed], "2/4", true, false, false),
   ([.cancelled, .cancelled, .cancelled, .cancelled], "0/4", false, true, false),
   ([.completed, .completed, .completed, .completed], "4/4", false, false, true),
   ([.requested, .requested, .requested, .requested], "4/4", false, false, false)
  ]
  for (states, count, warning, cancelled, success) in outcomes {
   let batch = ActionFeedbackController.begin(.close, windows: four)!
   for (window, state) in zip(four, states) { batch.finish(PreviewWindowIdentity(window), state) }
   let value = ActionFeedbackController.existing!.snapshot.4!
   precondition(value.title == "Close" && value.counter == count)
   precondition(value.isWarning == warning && value.isCancelled == cancelled && value.isSuccess == success)
   precondition(value.accessibilityTitle == (warning ? "Close failed" : cancelled ? "Close cancelled" : success ? "Close completed" : "Close"))
   ActionFeedbackController.existing!.stop()
  }
  let progress = ActionFeedbackController.begin(.close, windows: four)!
  progress.finish(PreviewWindowIdentity(four[0]), .failed)
  precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "1/4") // settled during progress; successful only in final results
  ActionFeedbackController.existing!.stop()
  print("PASS action-only labels, distinct outcomes, accessible status and successful/total final batch counters")

  let stack = ActionFeedbackController.begin(.close, windows: [windows[0]])!
  let tabProgress = stack.closeProgress(for: first)
  tabProgress(0, 7); tabProgress(3, 7)
  precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "3/7")
  tabProgress(2, 7); tabProgress(4, 8); tabProgress(9, 7)
  precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "3/7")
  stack.finishRemaining(.requested)
  tabProgress(7, 7)
  precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "3/7")
  ActionFeedbackController.existing!.stop()

  Defaults.position = .preview
  let tabPreviews = ActionFeedbackController.begin(.close, windows: windows)!
  tabPreviews.closeProgress(for: first)(2, 5)
  tabPreviews.closeProgress(for: second)(3, 7)
  precondition(Set(ActionFeedbackController.existing!.previewContents.compactMap(\.counter)) == ["2/5", "3/7"])
  ActionFeedbackController.existing!.previewWillDisappear(SharedPreviewWindowCoordinator.activeInstance!)
  precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "0/2") // batches continue counting windows, not tabs
  tabPreviews.finish(first, .requested)
  precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "1/2")
  ActionFeedbackController.existing!.stop()
  let soloPreview = ActionFeedbackController.begin(.close, windows: [windows[0]])!
  soloPreview.closeProgress(for: first)(2, 5)
  ActionFeedbackController.existing!.previewWillDisappear(SharedPreviewWindowCoordinator.activeInstance!)
  precondition(ActionFeedbackController.existing!.snapshot.4!.counter == "2/5")
  let replacement = ActionFeedbackController.begin(.close, windows: [windows[0]])!
  soloPreview.closeProgress(for: first)(4, 5)
  precondition(ActionFeedbackController.existing!.previewContents.allSatisfy { $0.counter == nil })
  replacement.finishRemaining(.requested)
  ActionFeedbackController.existing!.stop()
  print("PASS native-tab progress, stale/invalid updates, preview counters and consolidation without changing batch window totals")

  Defaults.position = .preview
  let cancelled = ActionFeedbackController.begin(.close, windows: [windows[0]])!
  cancelled.finishRemaining(.cancelled)
  let cancelledContent = ActionFeedbackController.existing!.previewContents[0]
  precondition(cancelledContent.title == "Close" && cancelledContent.isCancelled && !cancelledContent.isWarning && !cancelledContent.isSuccess)
  ActionFeedbackController.existing!.stop()
  let warning = ActionFeedbackController.begin(.close, windows: [windows[0]])!
  warning.finishRemaining(.failed)
  precondition(ActionFeedbackController.existing != nil && ActionPopupPanel.live == 1)
  await waitForCleanup()
  precondition(ActionFeedbackController.existing == nil && ActionPopupPanel.live == 0)
  print("PASS doubled warning duration for preview results")
  let previews = ActionFeedbackController.begin(.close, windows: windows)!
  precondition(ActionPopupPanel.live == 2 && TestEvent.monitors.isEmpty)
  precondition(ActionFeedbackController.existing!.previewContents.allSatisfy { $0.centersContents })
  previews.finish(first, .requested)
  precondition(ActionFeedbackController.existing!.previewContents.allSatisfy { $0.title == "Close" })
  precondition(ActionFeedbackController.existing!.previewContents.allSatisfy { !$0.isSuccess })
  precondition(ActionFeedbackController.existing!.busyCount == 0)
  await waitUntil { ActionFeedbackController.existing?.busyCount == 1 }
  precondition(ActionFeedbackController.existing!.busyCount == 1)
  SharedPreviewWindowCoordinator.activeInstance!.windowSwitcherCoordinator.actionFeedbackGrid!.missing.insert(second)
  ActionFeedbackController.existing!.refreshAnchors()
  precondition(ActionFeedbackController.existing!.snapshot.0)
  previews.finish(second, .completed)
  precondition(ActionFeedbackController.existing != nil) // full result duration starts after handoff
  await waitForCleanup()
  precondition(ActionFeedbackController.existing == nil && TestEvent.monitors.isEmpty && ActionPopupPanel.live == 0)
  print("PASS independent results, expired result exclusion, disappearance consolidation, full post-handoff result period")

  SharedPreviewWindowCoordinator.activeInstance!.windowSwitcherCoordinator.actionFeedbackGrid!.missing = []
  let old = ActionFeedbackController.begin(.close, windows: windows)!
  ActionFeedbackController.existing!.previewWillDisappear(SharedPreviewWindowCoordinator.activeInstance!)
  let newer = ActionFeedbackController.begin(.close, windows: [windows[0]])!
  old.finishRemaining(.failed)
  precondition(ActionFeedbackController.existing!.snapshot.2 == 0)
  newer.finishRemaining(.completed)
  precondition(ActionFeedbackController.existing!.previewContents.allSatisfy { $0.title == "Close" && $0.isSuccess && !$0.isWarning })
  await waitForCleanup()
  precondition(ActionFeedbackController.existing == nil && ActionPopupPanel.live == 0)
  let pending = ActionFeedbackController.begin(.close, windows: windows)!
  Defaults.disable(); await pause(10)
  pending.finishRemaining(.completed)
  precondition(ActionFeedbackController.existing == nil && ActionPopupPanel.live == 0 && TestEvent.monitors.isEmpty && Defaults.callbacks.isEmpty)
  print("PASS supersession, stale callbacks, handoff interruption, disable-without-cancelling-operations")
Defaults.enabled = true; Defaults.position = .cursor
let boundary = ActionFeedbackController.begin(.close, windows: [windows[0]])!
await pause(30)
boundary.finishRemaining(.requested)
await pause(40) // spinner threshold intersects the result's outgoing fade
ActionFeedbackController.existing?.refreshAnchors()
await waitForCleanup()
precondition(ActionFeedbackController.existing == nil && ActionPopupPanel.live == 0 && TestEvent.monitors.isEmpty)
print("PASS spinner/expiry boundary and layout refresh cannot resurrect cursor results")

 }
}
SWIFT
Dir.mktmpdir('action-feedback-') do |dir|
  path = "#{dir}/checks.swift"
  File.write(path, with_action_ownership(stubs + timing + position + handle + controller + checks))
  out, status = Open3.capture2e('xcrun', 'swiftc', '-parse-as-library', path, '-o', "#{dir}/checks")
  abort out unless status.success?
  out, status = Open3.capture2e("#{dir}/checks")
  puts out
  abort 'Action feedback state-machine tests failed' unless status.success?
end
puts 'PASS settings/reset/search wiring and AppleScript exclusion'

# Run the production confirmation worker against AX transitions that settle asynchronously.
util = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowUtil.swift")
confirmation = util[util.index('    static func setMinimizedWindowsConfirmed(')...util.index('    // Publish app visibility only after AX reports the requested value.')]
coordinator = File.read("#{ROOT}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
container = File.read("#{ROOT}/DockDoor/Views/Hover Window/WindowPreviewHoverContainer.swift")
menu = File.read("#{ROOT}/DockDoor/Utilities/WindowActionsMenuController.swift")
abort 'Single preview minimize/Close must use async batch operation' unless coordinator.include?('performSingleWindowAction(action, on: window, preservePreviews: preservePreviews, keyboard: true)') && container.include?('coordinator.performSingleWindowAction(action, on: window)')
abort 'Menu actions must use async batch operation' unless menu.include?('action.usesConfirmedSingleWindowAction(on: window)') && menu.include?('await WindowUtil.performPreviewBatchAction(action, on: targets, allowFullscreenEntry: action == .toggleFullScreen, feedback: feedback, request: request, targetState: targetState, resolvedTargets: resolvedTargets)')
abort 'Minimize All must not settle on queueing' unless util.include?('if self != .autoTileSelectedWindows, self != .minimizeAllWindows { feedback?.finishRemaining(.requested) }')
abort 'Minimize All action must forward feedback' unless util.include?('WindowUtil.minimizeAllWindows(for: window.app, preferredWindows: preferredWindows, feedback: feedback)')
abort 'Container must wait for Minimize All confirmation' unless container.include?('if !awaitingMinimizeConfirmation { feedback?.finishRemaining(.requested) }') && container.include?('WindowUtil.minimizeAllWindows(for: app, preferredWindows: preferredWindows, feedback: feedback)')
minimize_fixture = <<~'SWIFT'
import Foundation
enum WindowAction { case minimize; func isSupported(for window: WindowInfo) -> Bool { true } }
let kAXMinimizedAttribute = "minimized"
struct App { let bundleIdentifier: String? = "test"; var processIdentifier: Int32 = 1 }
final class AX: @unchecked Sendable {
 let lock = NSLock()
 var desired = false, fullscreen = false, refuses = false
 var changeAt: Date?, fullscreenGate: Gate?, writeGate: Gate?, readGate: Gate?
 var settleDelay: TimeInterval = 0.07
 private var writes: [Bool] = []
 private var reads = 0
 var readCount: Int {lock.withLock {reads}}
 var writeValues: [Bool] { lock.withLock { writes } }
 func isFullscreen() throws -> Bool {
  precondition(!Thread.isMainThread)
  let pending=lock.withLock {let value=fullscreenGate;fullscreenGate=nil;return value}
  if let pending {pending.entered.signal();pending.release.wait()}
  return lock.withLock {fullscreen}
 }
 func isMinimized() throws -> Bool {
  precondition(!Thread.isMainThread)
  let pending=lock.withLock {let value=readGate;readGate=nil;return value}
  if let pending {pending.entered.signal();pending.release.wait()}
  lock.lock(); defer { lock.unlock() }
  reads += 1
  return changeAt.map { Date() >= $0 && !refuses ? desired : !desired } ?? false
 }
 func setAttribute(_ key: String, _ value: Bool) throws {
  precondition(!Thread.isMainThread)
  let pending=lock.withLock {
   writes.append(value);desired=value
   if changeAt == nil {changeAt=Date().addingTimeInterval(settleDelay)}
   let pending=writeGate;writeGate=nil;return pending
  }
  if let pending {pending.entered.signal();pending.release.wait()}
 }
}
struct WindowInfo: @unchecked Sendable {
 let id: UInt32
 var axElement = AX()
 var app = App()
 var ownerApp: App { app }
 var isWindowlessApp = false
 var isFullscreen: Bool? = false
}
struct PreviewWindowIdentity: Hashable { let id: UInt32, pid: Int32; init(_ w: WindowInfo) { id = w.id; pid = w.app.processIdentifier } }
enum WindowUtil {
 static var cached = Set<UInt32>(), reconciled = Set<UInt32>()
 static var cachedStates: [UInt32: Bool] = [:]
 static var quitOnClose = false
 static func shouldQuitAppOnWindowClose(processIdentifier pid: Int32) -> Bool { quitOnClose }
 static func scheduleCachedWindowMetadataReconciliation(pid: Int32, windowID: UInt32) {reconciled.insert(windowID)}
 static func updateCachedWindowStates(for pid: Int32, matchingWindowIDs: Set<UInt32>, insertingMissing: [WindowInfo], isMinimized: Bool) { cached.formUnion(matchingWindowIDs);for id in matchingWindowIDs {cachedStates[id]=isMinimized} }
SWIFT
info_source = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowInfo.swift")
transactions = info_source[info_source.index('enum WindowFrameTransactions {')...info_source.index('struct WindowFrameContext {')]
catalog = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowActionCatalog.swift")
request_model = catalog[catalog.index('final class WindowActionRequest:')...catalog.index('enum PreviewBatchTogglePolicy {')]
minimize_fixture.sub!("import Foundation\n", "import Foundation\n" + transactions + request_model + "\nfinal class Gate: @unchecked Sendable {let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)}\n")
minimize_fixture += "}\nextension WindowUtil {\n"
abort 'Preview tasks must retain their own execution lifetime' unless coordinator.include?('previewActionTasks[token] = (request, task)')
abort 'Request cleanup missing' unless coordinator.include?('request.finish()') && coordinator.include?('self?.previewActionTasks.removeValue(forKey: token)')
abort 'New feedback must not let old actions dismiss previews' unless coordinator.include?('guard !Task.isCancelled, let self, previewBatchToken == token else { return }')
abort 'Single replacement must cancel cooperative workers' unless coordinator.include?('request.onSuperseded { task.cancel() }')
abort 'Minimize-specific admission must be removed' if coordinator.include?('PreviewMinimizeRequest') || util.include?('isMinimizeTargetActive')
minimize_fixture += confirmation + "\n}\n"
minimize_fixture += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async {
  let delayed = WindowInfo(id: 1)
  let refusal = WindowInfo(id: 2); refusal.axElement.refuses = true
  let fullscreen = WindowInfo(id: 3); fullscreen.axElement.fullscreen = true
  let progress = ProgressLog()
  let result = await WindowUtil.setMinimizedWindowsConfirmed([delayed, refusal, fullscreen], isMinimized: true, progress: { progress.record($0, $1) })
  precondition(result.map(\.id) == [1])
  precondition(progress.values == [1: true, 2: false])
  precondition(progress.calls == 2)
  precondition(WindowUtil.cached == [1])
  precondition(fullscreen.axElement.changeAt == nil)
  precondition(refusal.axElement.writeValues.count == 2 && refusal.axElement.readCount == 3, "Confirmation retry bound changed")
  let pending = WindowInfo(id: 4); pending.axElement.refuses = true
  let task = Task { await WindowUtil.setMinimizedWindowsConfirmed([pending], isMinimized: true) }
  try? await Task.sleep(nanoseconds: 20_000_000)
  task.cancel()
  let cancelled = await task.value
  precondition(cancelled.isEmpty && WindowUtil.cached == [1])
func entered(_ gate:Gate) async {
 for _ in 0..<2000 {if gate.entered.wait(timeout:.now()) == .success {return};try? await Task.sleep(nanoseconds:1_000_000)}
 preconditionFailure("Worker did not reach gate")
}
func fast(_ id:UInt32, pid:Int32=1)->WindowInfo {
 var result=WindowInfo(id:id);result.app.processIdentifier=pid;result.axElement.settleDelay=0;return result
}
for minimize in [true,false] {
 for hasProgress in [true,false] {
  let first=fast(70),second=fast(71)
  if !minimize {for window in [first,second] {window.axElement.desired=true;window.axElement.changeAt = .distantPast}}
  let writing=Gate(),reading=Gate(),progress=ProgressLog()
  second.axElement.writeGate=writing;second.axElement.readGate=reading
  let callback:(@Sendable (PreviewWindowIdentity,Bool)->Void)?
  if hasProgress {callback = {identity,success in progress.record(identity,success)}} else {callback=nil}
  let pending=Task {await WindowUtil.setMinimizedWindowsConfirmed([first,second],isMinimized:minimize,progress:callback)}
  await entered(writing)
  precondition(first.axElement.readCount==0 && second.axElement.readCount==0 && progress.snapshot.isEmpty,"Feedback interleaved confirmation with initial writes")
  writing.release.signal()
  await entered(reading)
  precondition(first.axElement.readCount==1 && progress.snapshot == (hasProgress ? [70:true] : [:]),"Existing confirmation did not publish before a later read finished")
  reading.release.signal();let result=await pending.value
  precondition(result.map(\.id)==[70,71] && progress.calls == (hasProgress ? 2 : 0))
  for window in [first,second] {
   precondition(window.axElement.writeValues==[minimize] && window.axElement.readCount==1,"Fast path added AX work")
  }
 }
}
print("PASS Minimize/Restore with/without progress: identical write-all-before-confirm scheduling, per-read outcomes before later confirmation completes, one fast-path write/read")
let slowFirst=WindowInfo(id:72),fastLast=fast(73)
let outOfOrder=await WindowUtil.setMinimizedWindowsConfirmed([slowFirst,fastLast],isMinimized:true)
precondition(outOfOrder.map(\.id)==[72,73],"Progress timing changed the returned window order")
let slowRead=fast(74,pid:11),independentRead=fast(75,pid:12)
let readGate=Gate();slowRead.axElement.readGate=readGate
let readProgress=ProgressLog()
let readTask=Task {await WindowUtil.setMinimizedWindowsConfirmed([slowRead],isMinimized:true,progress:{readProgress.record($0,$1)})}
await entered(readGate)
let independentReadResult=await WindowUtil.setMinimizedWindowsConfirmed([independentRead],isMinimized:true)
precondition(independentReadResult.map(\.id)==[75] && readProgress.snapshot.isEmpty,"Slow confirmation blocked the main actor or independent app")
readGate.release.signal();let readResult=await readTask.value
precondition(readResult.map(\.id)==[74] && readProgress.snapshot==[74:true])
let supersededRead=fast(76,pid:13),supersededGate=Gate(),supersededProgress=ProgressLog()
supersededRead.axElement.readGate=supersededGate
let oldRead=Task {await WindowUtil.setMinimizedWindowsConfirmed([supersededRead],isMinimized:true,progress:{supersededProgress.record($0,$1)})}
await entered(supersededGate)
let newRead=Task {await WindowUtil.setMinimizedWindowsConfirmed([supersededRead],isMinimized:false)}
try? await Task.sleep(nanoseconds:20_000_000)
precondition(supersededRead.axElement.writeValues==[true],"Replacement overtook an in-flight confirmation")
supersededGate.release.signal();let staleRead=await oldRead.value;let finalRead=await newRead.value
precondition(staleRead.isEmpty && supersededProgress.snapshot.isEmpty && finalRead.map(\.id)==[76])
precondition(WindowUtil.cachedStates[76]==false && supersededRead.axElement.writeValues==[true,false])
print("PASS held confirmation: responsive main actor/independent app, no stale progress/cache on replacement, ordered successor writes")
let owner=WindowActionOwnership()
let a=fast(10),b=fast(11),c=fast(12)
let independent=owner.begin([a,b].map(PreviewWindowIdentity.init))
a.axElement.fullscreenGate=Gate();let held=a.axElement.fullscreenGate!
let batch=Task {await WindowUtil.setMinimizedWindowsConfirmed([a,b],isMinimized:true,isTargetActive:{independent.contains($0)})}
await entered(held)
let rejected=owner.begin([PreviewWindowIdentity(a)])
precondition(rejected.admitted.isEmpty && rejected.rejected == [PreviewWindowIdentity(a)])
let separate=owner.begin([PreviewWindowIdentity(c)])
let separateResult=await WindowUtil.setMinimizedWindowsConfirmed([c],isMinimized:true,isTargetActive:{separate.contains($0)})
precondition(separateResult.map(\.id)==[12] && WindowUtil.cached.contains(12));separate.finish()
held.release.signal();let independentResult=await batch.value
precondition(independentResult.map(\.id)==[10,11] && a.axElement.writeValues==[true] && b.axElement.writeValues==[true])
let partial=owner.begin([a,c].map(PreviewWindowIdentity.init))
precondition(partial.admitted == [PreviewWindowIdentity(c)] && partial.rejected == [PreviewWindowIdentity(a)])
let partialBlocked=owner.begin([PreviewWindowIdentity(c)])
precondition(partialBlocked.admitted.isEmpty,"Partially admitted batch lost protection")
partial.finish();independent.finish(PreviewWindowIdentity(a))
let released=owner.begin([PreviewWindowIdentity(a)])
precondition(released.admitted.count==1 && independent.contains(PreviewWindowIdentity(b)))
released.finish();independent.finish()
let f=fast(30),g=fast(31)
let inflight=owner.begin([PreviewWindowIdentity(g)])
g.axElement.writeGate=Gate();let writing=g.axElement.writeGate!
let older=Task {await WindowUtil.setMinimizedWindowsConfirmed([g],isMinimized:true,isTargetActive:{inflight.contains($0)})}
inflight.onSuperseded {older.cancel()}
await entered(writing)
let replacement=owner.begin([PreviewWindowIdentity(g)])
let newer=Task {await WindowUtil.setMinimizedWindowsConfirmed([g],isMinimized:false,isTargetActive:{replacement.contains($0)})}
try? await Task.sleep(nanoseconds:20_000_000)
precondition(g.axElement.writeValues==[true], "New write overtook in-flight AX")
writing.release.signal();let oldResult=await older.value;let newResult=await newer.value
precondition(oldResult.isEmpty && newResult.map(\.id)==[31] && g.axElement.writeValues==[true,false])
precondition(WindowUtil.cachedStates[31]==false && WindowUtil.reconciled.contains(31))
inflight.finish();precondition(replacement.contains(PreviewWindowIdentity(g)),"Stale cleanup released newer owner");replacement.finish()
let first=fast(40),last=fast(41);first.axElement.writeGate=Gate();let cancelGate=first.axElement.writeGate!
let interrupted=Task {await WindowUtil.setMinimizedWindowsConfirmed([first,last],isMinimized:true)}
await entered(cancelGate);interrupted.cancel();cancelGate.release.signal();let interruptedResult=await interrupted.value
precondition(interruptedResult.isEmpty && first.axElement.writeValues==[true] && last.axElement.writeValues.isEmpty)
precondition(WindowUtil.reconciled.contains(40) && WindowUtil.cachedStates[40]==nil)
let otherApp=fast(10,pid:2)
let protected=owner.begin([PreviewWindowIdentity(a)],protect:true)
let appClaim=owner.begin([a,b,otherApp].map(PreviewWindowIdentity.init),apps:[1,2])
precondition(Set(appClaim.rejected)==Set([a,b].map(PreviewWindowIdentity.init)) && appClaim.admitted == [PreviewWindowIdentity(otherApp)])
let sibling=fast(100,pid:2)
precondition(owner.begin([PreviewWindowIdentity(sibling)]).admitted.isEmpty,"App scope failed to protect sibling")
appClaim.finish();protected.finish()
let oldSingle=owner.begin([PreviewWindowIdentity(a)])
let newBatch=owner.begin([a,b].map(PreviewWindowIdentity.init))
precondition(!oldSingle.contains(PreviewWindowIdentity(a)) && newBatch.admitted.count==2)
oldSingle.finish();newBatch.finish()
var temporary:WindowActionRequest?=owner.begin([PreviewWindowIdentity(a)],protect:true)
precondition(temporary!.contains(PreviewWindowIdentity(a)));temporary=nil
let available=owner.begin([PreviewWindowIdentity(a)])
precondition(available.admitted.count==1)
let late=owner.begin([PreviewWindowIdentity(a)])
available.onSuperseded {let nested=owner.begin([PreviewWindowIdentity(f)]);nested.finish()}
precondition(late.contains(PreviewWindowIdentity(a)));late.finish();available.finish()
let appSingle=owner.begin([PreviewWindowIdentity(a)])
let appReplace=owner.begin([PreviewWindowIdentity(b)],apps:[1])
precondition(!appSingle.contains(PreviewWindowIdentity(a)) && appReplace.admitted.count==1);appReplace.finish();appSingle.finish()
let appParent=owner.begin([PreviewWindowIdentity(a)]),appSibling=owner.begin([PreviewWindowIdentity(b)],protect:true)
precondition(!appParent.reserveApp(1),"Nested app mutation ignored protected sibling")
appSibling.finish();precondition(appParent.reserveApp(1))
precondition(owner.begin([PreviewWindowIdentity(b)]).admitted.isEmpty,"Nested app claim did not reserve siblings")
appParent.finish()
print("PASS shared ownership: protected batch/terminal/app scopes, disjoint targets, partial admission, per-target release, single replacement, in-flight write ordering, app atomicity, stale cleanup, deinit and reentrant cancellation")
  print("PASS delayed minimize confirmation, real refusal, fullscreen exclusion, confirmed-only cache and cancellation")
 }
}
SWIFT
minimize_fixture.sub!('@main struct Checks {', <<~'SWIFT')
final class ProgressLog: @unchecked Sendable {
 let lock = NSLock()
 var values: [UInt32: Bool] = [:]
 var calls = 0
 var snapshot: [UInt32:Bool] {lock.withLock {values}}
 func record(_ identity: PreviewWindowIdentity, _ success: Bool) {
  lock.lock(); defer { lock.unlock() }
  calls += 1; values[identity.id] = success
 }
}
@main struct Checks {
SWIFT
Dir.mktmpdir('feedback-minimize-') do |dir|
  File.write("#{dir}/checks.swift", with_action_ownership(minimize_fixture))
  out, status = Open3.capture2e('xcrun', 'swiftc', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort out unless status.success?
  out, status = Open3.capture2e("#{dir}/checks")
  puts out
  abort 'Minimize confirmation tests failed' unless status.success?
end

# The production queueing wrapper must leave results to its existing asynchronous worker.
wrapper = util[util.index('    @discardableResult\n    static func minimizeAllWindows(for'.gsub('\\n', "\n"))...util.index('    enum MinimizeAllWindowsOutcome:')]
wrapper_fixture = <<~'SWIFT'
import Foundation
enum WindowAction { case minimize; func isSupported(for window: WindowInfo) -> Bool { true } }
struct NSRunningApplication { let processIdentifier: Int32 = 1 }
struct WindowInfo { let id:UInt32=1;let app = NSRunningApplication(); var isWindowlessApp = false; var isFullscreen: Bool? = false }
struct PreviewWindowIdentity:Hashable {let pid:Int32,windowID:UInt32;init(_ w:WindowInfo){pid=w.app.processIdentifier;windowID=w.id}}
enum WrapperOutcome {case failed}
final class ActionFeedbackHandle: @unchecked Sendable {
 func finishRemaining(_ outcome:WrapperOutcome) {completed=true}
 private let lock = NSLock()
 private var value = false
 var completed: Bool {
  get { lock.lock(); defer { lock.unlock() }; return value }
  set { lock.lock(); defer { lock.unlock() }; value = newValue }
 }
}
enum WindowUtil {
 static func readCachedWindows(for pid: Int32) -> [WindowInfo] { [] }
 static func toggleAllMinimizableWindows(for app: NSRunningApplication, preferredWindows: [WindowInfo]?, feedback: ActionFeedbackHandle?) async -> Int {
  await Task.yield()
  feedback?.completed = true
  return 1
 }
SWIFT
wrapper_fixture += wrapper + "\n}\n"
wrapper_fixture += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async {
  let feedback = ActionFeedbackHandle()
  precondition(WindowUtil.minimizeAllWindows(for: NSRunningApplication(), preferredWindows: [WindowInfo()], feedback: feedback) == 1)
  precondition(!feedback.completed)
  for _ in 0..<100 where !feedback.completed { try? await Task.sleep(nanoseconds: 1_000_000) }
  precondition(feedback.completed)
  let empty = ActionFeedbackHandle()
  precondition(WindowUtil.minimizeAllWindows(for: NSRunningApplication(), feedback: empty) == 0)
  await Task.yield()
  precondition(!empty.completed)
  print("PASS Minimize All wrapper forwards feedback without prematurely finishing or scheduling empty work")
 }
}
SWIFT
Dir.mktmpdir('feedback-minimize-wrapper-') do |dir|
  File.write("#{dir}/checks.swift", with_action_ownership(wrapper_fixture))
  out, status = Open3.capture2e('xcrun', 'swiftc', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort out unless status.success?
  out, status = Open3.capture2e("#{dir}/checks")
  puts out
  abort 'Minimize feedback queueing tests failed' unless status.success?
end

# Exercise the real AppKit presenter and SwiftUI symbol layout with inert registration and pill chrome.
content = source[source.index('    struct Content: Equatable {')...source.index('    private var tooltipPanel:')]
tooltip = source[source.index('private struct WindowGestureTooltip:')...source.index('private final class WindowGesturePreviewView:')]
panel = source[source.index('@MainActor\nfinal class ActionPopupPanel:'.gsub('\\n', "\n"))...source.index('@MainActor\nfinal class ActionFeedbackController'.gsub('\\n', "\n"))]
native_fixture = <<~'SWIFT'
import AppKit
import SwiftUI
struct WindowInfo { enum WindowPositionRect: Equatable { case test; func frame(in rect: CGRect) -> CGRect { rect } } }
struct BackgroundAppearance { static func resolve() -> Self { Self() } }
extension View { func materialPill(backgroundAppearance: BackgroundAppearance) -> some View { padding(8).background(.regularMaterial) } }
struct Key<T> { let value: T }
enum Defaults { static var animations = false; static subscript<T>(_ key: Key<T>) -> T { key.value } }
extension Key where T == Bool { static var showAnimations: Self { Self(value: Defaults.animations) } }
enum WindowUtil {
 static var internalWindows = Set<UInt32>()
 static func registerInternalWindow(_ id: UInt32) { internalWindows.insert(id) }
 static func unregisterInternalWindow(_ id: UInt32) { internalWindows.remove(id) }
}
enum WindowGestureOverlays {
 static var windows = Set<Int>()
 static func register(_ id: Int) { windows.insert(id) }
 static func unregister(_ id: Int) { windows.remove(id) }
}
extension CGPoint { func screen() -> NSScreen? { NSScreen.screens.first { $0.frame.contains(self) } } }
enum WindowGestureHUD {
SWIFT
native_fixture += content + "\n}\n" + source[source.index('enum ActionPopupTiming {')...source.index('enum ActionFeedbackPosition:')] + tooltip + panel
native_fixture += <<~'SWIFT'
@main struct Checks {
 @MainActor static func pump(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
 @MainActor static func main() {
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  guard let screen = NSScreen.screens.first else { print("SKIP native popup presenter: no WindowServer display access"); return }
  precondition(NSImage(systemSymbolName: "pointer.arrow.motionlines", accessibilityDescription: nil) != nil)
  let panel = ActionPopupPanel()
  defer { panel.close() }
  precondition(panel.animationBehavior == .none && panel.ignoresMouseEvents && panel.sharingType == .none)
  let anchor = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
  var value = WindowGestureHUD.Content(title: "Un-minimize", symbolName: "arrow.up.left.and.arrow.down.right.square")
  panel.present(value, center: anchor)
  let originalSize = panel.frame.size
  for state in 0..<7 {
   value.isBusy = state == 0; value.isWarning = state == 1; value.isCancelled = state == 2; value.isSuccess = state == 3
   value.appIcon = state == 4 ? NSImage(size: NSSize(width: 18, height: 18)) : nil
   value.region = state == 5 ? .test : nil
   panel.present(value, center: anchor)
   precondition(abs(panel.frame.width - originalSize.width) < 0.1 && abs(panel.frame.height - originalSize.height) < 0.1, "Status changed the pill size")
   precondition(abs(panel.frame.midX - anchor.x) <= 0.5 && abs(panel.frame.midY - anchor.y) <= 0.5, "Popup center differs from its anchor: \(panel.frame) / \(anchor)")
  }
  value.title = "A longer action label"
  panel.present(value, center: anchor)
  precondition(panel.frame.width > originalSize.width && abs(panel.frame.midX - anchor.x) <= 0.5, "Content resize did not retain its anchor")
  panel.hide()
  pump(0.02)
  Defaults.animations = true
  value.title = "Un-minimize"
  panel.present(value, center: anchor)
  for _ in 0..<12 { pump(0.005); value.isBusy.toggle(); panel.present(value, center: anchor) }
  pump(0.2)
  precondition(panel.isVisible && panel.alphaValue > 0.99, "Repeated status updates stranded the fade-in")
  var staleCompletion = false
  panel.hide { staleCompletion = true }
  pump(0.025)
  panel.present(value, center: anchor)
  pump(0.25)
  precondition(panel.isVisible && panel.alphaValue > 0.99 && !staleCompletion, "Stale hide interrupted a new presentation")
  panel.followCursor()
  let cursorFrame = panel.frame
  pump(0.05)
  precondition(panel.frame == cursorFrame, "A frame animation moved the popup after cursor following")
  var hidden = false
  panel.hide(closeAfter: true) { hidden = true }
  pump(0.25)
  precondition(hidden && !panel.isVisible)
  precondition(WindowUtil.internalWindows.isEmpty && WindowGestureOverlays.windows.isEmpty)
  print("PASS native popup equal status/spinner geometry, anchor-preserving immediate resizing, fade-only repeated updates and interrupted-hide cleanup")
 }
}
SWIFT
Dir.mktmpdir('feedback-native-panel-') do |dir|
  File.write("#{dir}/checks.swift", with_action_ownership(native_fixture))
  out, status = Open3.capture2e('xcrun', 'swiftc', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort out unless status.success?
  out, status = Open3.capture2e("#{dir}/checks")
  puts out
  abort 'Native popup presenter tests failed' unless status.success?
end

# Run the production warp hook with fake cursor operations; never move the user's pointer.
info = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowInfo.swift")
warp = info[info.index('    func warpMouseToCenterIfNeeded()')...info.index('    @discardableResult\n    func close('.gsub('\\n', "\n"))]
warp = warp.gsub('CGWarpMouseCursorPosition', 'testWarpMouseCursorPosition').gsub('CGAssociateMouseAndMouseCursorPosition', 'testAssociateMouseAndMouseCursorPosition').gsub('CGEvent(source:', 'TestCursorEvent(source:')
warp_fixture = <<~'SWIFT'
import Foundation
import CoreGraphics
struct Key<T> { let value: T }
enum Mode { case never, always, differentDisplayOnly }
enum Defaults { static var mode = Mode.always, enabled = false, hint = false; static subscript<T>(_ key: Key<T>) -> T { key.value } }
extension Key where T == Bool {
 static var enableActionFeedback: Self { Self(value: Defaults.enabled) }
 static var showMouseFollowsFocusFeedback: Self { Self(value: Defaults.hint) }
}
extension Key where T == Mode { static var mouseFollowsFocusMode: Self { Self(value: Defaults.mode) } }
enum Cursor { static var point = CGPoint.zero, succeeds = true, available = true, warps = 0, reads = 0 }
struct TestCursorEvent {
 init?(source: Int?) { Cursor.reads += 1; if !Cursor.available { return nil } }
 var location: CGPoint { Cursor.point }
}
enum Result { case success, failure }
func testWarpMouseCursorPosition(_ point: CGPoint) -> Result { Cursor.warps += 1; if Cursor.succeeds { Cursor.point = point }; return Cursor.succeeds ? .success : .failure }
func testAssociateMouseAndMouseCursorPosition(_ value: Int) {}
enum NSScreen { static func screenFromQuartzPoint(_ point: CGPoint) -> Bool { point.x >= 1000 } }
struct AX { func position() throws -> CGPoint { CGPoint(x: 100, y: 100) }; func size() throws -> CGSize { CGSize(width: 200, height: 200) } }
@MainActor enum ActionFeedbackController { static var count = 0; static func mouseFollowedFocus() { count += 1 } }
struct WindowInfo { let axElement = AX()
SWIFT
warp_fixture += warp + "\n}\n"
warp_fixture += <<~'SWIFT'
@main struct Checks {
 @MainActor static func settle() async { try? await Task.sleep(nanoseconds: 10_000_000) }
 @MainActor static func main() async {
  let window = WindowInfo()
  window.warpMouseToCenterIfNeeded(); await settle()
  precondition(Cursor.warps == 1 && Cursor.reads == 0 && ActionFeedbackController.count == 0)
  Defaults.enabled = true; Defaults.hint = true; Cursor.point = .zero
  window.warpMouseToCenterIfNeeded(); await settle()
  precondition(Cursor.point == CGPoint(x: 200, y: 200) && ActionFeedbackController.count == 1)
  window.warpMouseToCenterIfNeeded(); await settle()
  precondition(ActionFeedbackController.count == 1, "No popup when cursor is already centered")
  Cursor.point = .zero; Cursor.succeeds = false
  window.warpMouseToCenterIfNeeded(); await settle()
  precondition(ActionFeedbackController.count == 1, "No popup on failed warp")
  Cursor.succeeds = true; Defaults.mode = .differentDisplayOnly
  let before = Cursor.warps
  window.warpMouseToCenterIfNeeded(); await settle()
  precondition(Cursor.warps == before && ActionFeedbackController.count == 1)
  Cursor.point = CGPoint(x: 1500, y: 200)
  window.warpMouseToCenterIfNeeded(); await settle()
  precondition(ActionFeedbackController.count == 2)
  Cursor.available = false; Cursor.point = .zero; Defaults.mode = .always
  window.warpMouseToCenterIfNeeded(); await settle()
  precondition(Cursor.point == CGPoint(x: 200, y: 200) && ActionFeedbackController.count == 2)
  Defaults.mode = .never
  let reads = Cursor.reads, warps = Cursor.warps
  window.warpMouseToCenterIfNeeded(); await settle()
  precondition(Cursor.reads == reads && Cursor.warps == warps)
  print("PASS Mouse Follows Focus hook: disabled cost, successful/no-op/failed warps, display policy and unavailable cursor reads")
 }
}
SWIFT
Dir.mktmpdir('feedback-mouse-warp-') do |dir|
  File.write("#{dir}/checks.swift", with_action_ownership(warp_fixture))
  out, status = Open3.capture2e('xcrun', 'swiftc', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort out unless status.success?
  out, status = Open3.capture2e("#{dir}/checks")
  puts out
  abort 'Mouse Follows Focus feedback hook tests failed' unless status.success?
end

# Execute the production gesture adapter with inert OS operations and real action ownership.
gesture_controller = File.read("#{ROOT}/DockDoor/Utilities/Window Gestures/WindowGestureController.swift")
gesture_executor = File.read("#{ROOT}/DockDoor/Utilities/Window Gestures/WindowGestureExecutor.swift")
finished_gesture = gesture_controller[gesture_controller.index('    private func finished(')...gesture_controller.index('    private func context(')]
abort 'Committed gestures still finish the HUD at dispatch' if gesture_controller.include?('hud.finish(content, cursor: point)') || finished_gesture.include?('hud.finish(content,')
abort 'Immediate gesture flash changed' unless gesture_controller.include?('hud.flash(content, cursor: current.cursor)')
abort 'Committed gestures must start feedback before dispatch' unless gesture_controller.index('ActionFeedbackController.gesture(') < gesture_controller.index('executor.perform(command, zone: zone, cursor: cursor, feedback: feedback)')
abort 'Gesture Close must use the confirmed shared route' unless gesture_executor.include?('allowFullscreenEntry: action == .toggleFullScreen, feedback: feedback)')
gesture_fixture = <<~'SWIFT'
import AppKit
import ApplicationServices
import Carbon.HIToolbox.Events
final class TestApp {
 let processIdentifier: Int32
 var isHidden=false,isTerminated=false
 var activationPolicy: NSApplication.ActivationPolicy = .regular
 let localizedName: String? = "Test"
 init(_ pid: Int32) {processIdentifier=pid}
}
final class Gate: @unchecked Sendable {
 var open=false,entered=false
 func wait() async {entered=true;while !open && !Task.isCancelled {try? await Task.sleep(nanoseconds:1_000_000)}}
}
enum State: Equatable {case completed,requested,failed,cancelled}
final class ActionFeedbackHandle: @unchecked Sendable {
 let lock=NSLock();var targets:[PreviewWindowIdentity]=[];var states:[PreviewWindowIdentity:State]=[:]
 var snapshot:[PreviewWindowIdentity:State] {lock.withLock {states}}
 func setTargets(_ windows:[WindowInfo]) {lock.withLock {targets=windows.map(PreviewWindowIdentity.init)}}
 var confirmedProgress: @Sendable (PreviewWindowIdentity,Bool)->Void {{id,success in self.finish(id,success ? .completed : .failed)}}
 func finish(_ id:PreviewWindowIdentity,_ state:State) {lock.withLock {if states[id]==nil {states[id]=state}}}
 func finishRemaining(_ state:State) {lock.withLock {for id in targets where states[id]==nil {states[id]=state}}}
 func finish(_ result:WindowUtil.PreviewBatchResult) {let failed=Set(result.failed);for w in result.succeeded {finish(PreviewWindowIdentity(w),failed.contains(PreviewWindowIdentity(w)) ? .failed:.completed)};for id in failed {finish(id,.failed)}}
}
struct PreviewWindowIdentity: Hashable {let pid:Int32,windowID:Int;init(_ w:WindowInfo){pid=w.app.processIdentifier;windowID=w.id}}
struct WindowInfo {
 let id:Int,app:TestApp
 var isMinimized=false,isHidden=false,isWindowlessApp=false,isFullscreen:Bool?=false
 var screenIdentifier="screen",lastAccessedTime=Date()
 var ownerApp:TestApp {app}
 var axElement:FakeAX {FakeAX.shared};var appAxElement:FakeAX {FakeAX.shared}
 static func windowlessEntry(for app:TestApp)->Self {Self(id:0,app:app,isWindowlessApp:true)}
 @MainActor func readWindowFrame() async -> CGRect? {CGRect(x:0,y:0,width:100,height:100)}
 @MainActor func positionWindow(_ rect:Int,size:CGSize?=nil) async->Bool {Test.calls.append("place\(id)");if let gate=Test.placeGate {await gate.wait()};return !Task.isCancelled && !Test.failures.contains(id)}
 @MainActor func bringToFrontConfirmed() async->Bool {Test.calls.append("focus\(id)");if let gate=Test.focusGate {await gate.wait()};return !Task.isCancelled && !Test.focusFailures.contains(id)}
 func bringToFront() {Test.calls.append("dispatchFocus\(id)")}
}
final class FakeAX {
 static let shared=FakeAX();var refuses=false,hasCloseControl=false
 func focusedWindow()throws->FakeAX? {self}
 func attribute<T>(_ key:String,_ type:T.Type)throws->T? {nil}
 func performAction(_ action:String)throws {if refuses {throw NSError(domain:"AX",code:1)}}
 func children()throws->[FakeAX] {hasCloseControl ? [self]:[]}
 func role()throws->String {"AXButton"}
 func subrole()throws->String {"AXCloseButton"}
}
func FakeAXCreateApplication(_ pid:Int32)->FakeAX {FakeAX.shared}
final class TestScreen {static let shared=TestScreen();static func screenFromQuartzPoint(_ p:CGPoint)->TestScreen {shared};func uniqueIdentifier()->String {"screen"}}
enum TestWorkspace {static let shared=TestWorkspaceValue()}
final class TestWorkspaceValue {var runningApplications:[TestApp]=[];var frontmostApplication:TestApp?}
enum DockObserver {static let activeInstance:DockObserverValue?=nil}
struct DockObserverValue {func runningApplicationsInDockOrder()->[TestApp] {[]}}
enum DebugLogger {static func log(_ category:String,details:String){}}
struct Record {var restoreFrame=CGRect(x:1,y:2,width:80,height:90)}
final class WindowSnapRegistry {
 static let shared=WindowSnapRegistry()
 func liveRecord(for window:WindowInfo) async->Record? {Record()}
 func remove(_ id:PreviewWindowIdentity) {Test.calls.append("remove\(id.windowID)")}
 func snapped(_ w:WindowInfo,restoreFrame:CGRect) async {Test.calls.append("enroll\(w.id)")}
}
extension Int {static let center=0}
enum WindowAction {case minimize,hide,toggleFullScreen,openAppWindow,close,quit,center,fillLeftHalf
 func isSupported(for window: WindowInfo) -> Bool { true }
 var isAppWidePreviewAction:Bool {self == .hide || self == .quit}
 var isQuitAction:Bool {self == .quit}
 var positionRect:Int? {self == .center ? 0 : self == .fillLeftHalf ? 1 : nil}
 func usesConfirmedSingleWindowAction(on window:WindowInfo)->Bool {positionRect==nil}
 func perform(on window:WindowInfo,feedback:ActionFeedbackHandle?)->Bool {false}
}
enum Test {static var windows:[WindowInfo]=[],failures=Set<Int>(),focusFailures=Set<Int>(),calls:[String]=[];static var placeGate:Gate?,focusGate:Gate?,minimizeGate:Gate?}
enum WindowUtil {
 struct PreviewBatchResult {var succeeded:[WindowInfo]=[];var failed:[PreviewWindowIdentity]=[]}
 static func windowInfo(for element:FakeAX,app:TestApp)->WindowInfo? {Test.windows.first {$0.app.processIdentifier==app.processIdentifier}}
 static func readCachedWindows(for pid:Int32)->[WindowInfo] {Test.windows.filter {$0.app.processIdentifier==pid}}
 static func getAllWindowsIgnoringSwitcherFilters()->[WindowInfo] {Test.windows}
 static func filterWindowsByCurrentSpace(_ windows:[WindowInfo])->[WindowInfo] {windows}
 static func postCommandShortcut(_ code:CGKeyCode,to pid:Int32) {}
 static func setHiddenStateConfirmed(for app:TestApp,isHidden:Bool) async->Bool {true}
 static func minimizeWindowExitingFullscreen(_ window:WindowInfo) async->Bool {
  if WindowActionRequest.current==nil {return await WindowActionRequest.run([PreviewWindowIdentity(window)]) {_ in await minimizeWindowExitingFullscreen(window)} ?? false}
  if let gate=Test.minimizeGate {await gate.wait()};return !Task.isCancelled && !Test.failures.contains(window.id)
 }
 static func setMinimizedWindowsConfirmed(_ windows:[WindowInfo],isMinimized:Bool,progress:(@Sendable (PreviewWindowIdentity,Bool)->Void)?) async->[WindowInfo] {
  var changed:[WindowInfo]=[]
  for window in windows {
   if let gate=Test.minimizeGate {await gate.wait()}
   guard !Task.isCancelled else {return changed}
   guard WindowActionRequest.current?.contains(PreviewWindowIdentity(window))==true else {continue}
   let success = !Test.failures.contains(window.id);Test.calls.append("minimize\(window.id)");progress?(PreviewWindowIdentity(window),success)
   if success {changed.append(window)}
  };return changed
 }
 static func restoreWindowsConfirmed(_ windows:[WindowInfo],progress:(@Sendable (PreviewWindowIdentity,Bool)->Void)?) async->[WindowInfo] {await setMinimizedWindowsConfirmed(windows,isMinimized:false,progress:progress)}
 static func performPreviewBatchAction(_ action:WindowAction,on windows:[WindowInfo],allowFullscreenEntry:Bool=false,feedback:ActionFeedbackHandle?) async->PreviewBatchResult {
  if WindowActionRequest.current==nil {return await WindowActionRequest.run(windows.map(PreviewWindowIdentity.init),apps:action.isAppWidePreviewAction ? Set(windows.map(\.app.processIdentifier)):[],protect:action == .close || action.isQuitAction) {_ in await performPreviewBatchAction(action,on:windows,allowFullscreenEntry:allowFullscreenEntry,feedback:feedback)} ?? PreviewBatchResult(failed:windows.map(PreviewWindowIdentity.init))}
  var result=PreviewBatchResult()
  for w in windows {guard WindowActionRequest.current?.contains(PreviewWindowIdentity(w))==true else {result.failed.append(PreviewWindowIdentity(w));continue};Test.calls.append("batch\(w.id)");if Test.failures.contains(w.id) {result.failed.append(PreviewWindowIdentity(w));feedback?.finish(PreviewWindowIdentity(w),.failed)} else {result.succeeded.append(w);feedback?.finish(PreviewWindowIdentity(w),action == .close || action.isQuitAction ? .requested:.completed)}}
  return result
 }
}
SWIFT
zone = File.read("#{ROOT}/DockDoor/Utilities/Window Gestures/WindowGestureZone.swift")
zone = zone[zone.index('enum WindowGestureZone {')...zone.index('enum WindowGestureZoneResolver {')]
# Remove kind, which belongs to the recognizer and is not used by the executor.
zone.sub!(/    var kind: WindowGestureZoneKind \{.*?\n    \}\n/m, '')
resolver = File.read("#{ROOT}/DockDoor/Utilities/Window Gestures/WindowGestureResolver.swift")
command = resolver[resolver.index('enum WindowGestureCommand:')...resolver.index('struct WindowGestureResolution:')]
command.sub!(/    func title\(.*?\n    \}\n/m, '')
command.sub!(/    var symbolName:.*?\n    \}\n/m, '')
executor = gesture_executor[gesture_executor.index('final class WindowGestureExecutor')..].gsub('private ', '')
gesture_fixture += zone + command + executor
{ 'NSRunningApplication'=>'TestApp','NSWorkspace'=>'TestWorkspace','NSScreen'=>'TestScreen','AXUIElement'=>'FakeAX' }.each {|from,to| gesture_fixture.gsub!(from,to)}
gesture_fixture += <<~'SWIFT'
@main struct Checks {
 @MainActor static func waitUntil(_ check:()->Bool) async {for _ in 0..<500 {if check(){return};try? await Task.sleep(nanoseconds:1_000_000)};preconditionFailure("Gesture fixture timed out")}
 @MainActor static func main() async {
  let app=TestApp(100),otherApp=TestApp(200)
  let a=WindowInfo(id:1,app:app),b=WindowInfo(id:2,app:app),other=WindowInfo(id:3,app:otherApp)
  let executor=WindowGestureExecutor()
  let feedback=ActionFeedbackHandle();feedback.setTargets([a]);let gate=Gate();Test.focusGate=gate
  let placing=Task {await executor.run(.window(.fillLeftHalf),zone:.window(a,isFullscreen:false),cursor:.zero,feedback:feedback)}
  await waitUntil {gate.entered}
  precondition(feedback.snapshot.isEmpty && Test.calls.contains("place1"),"Gesture result finished before foreground confirmation")
  gate.open=true;await placing.value
  precondition(feedback.snapshot[PreviewWindowIdentity(a)] == .completed && Test.calls.last == "enroll1")
  Test.focusGate=nil;Test.focusFailures=[1]
  let refusedFocus=ActionFeedbackHandle();refusedFocus.setTargets([a])
  await executor.run(.window(.center),zone:.window(a,isFullscreen:false),cursor:.zero,feedback:refusedFocus)
  precondition(refusedFocus.snapshot[PreviewWindowIdentity(a)] == .failed)
  Test.focusFailures=[]
  var full=a;full=WindowInfo(id:99,app:app,isFullscreen:true);Test.windows=[a,b,full];Test.failures=[2];Test.calls=[]
  let group=ActionFeedbackHandle();group.setTargets([a,b]);let held=Gate();Test.minimizeGate=held
  let batch=Task {await executor.run(.minimizeAllOnDisplay,zone:.menuBar,cursor:.zero,feedback:group)}
  await waitUntil {held.entered}
  let busy=ActionFeedbackHandle();busy.setTargets([a]);await executor.run(.window(.close),zone:.window(a,isFullscreen:false),cursor:.zero,feedback:busy)
  precondition(busy.snapshot[PreviewWindowIdentity(a)] == .failed && !Test.calls.contains("batch1"))
  let refusedQuit=ActionFeedbackHandle();refusedQuit.setTargets([WindowInfo.windowlessEntry(for:app)]);await executor.run(.quitApp,zone:.app(app),cursor:.zero,feedback:refusedQuit);precondition(refusedQuit.snapshot.values.allSatisfy {$0 == .failed} && !Test.calls.contains("batch0"))
  let independent=ActionFeedbackHandle();independent.setTargets([other]);await executor.run(.window(.close),zone:.window(other,isFullscreen:false),cursor:.zero,feedback:independent)
  precondition(independent.snapshot[PreviewWindowIdentity(other)] == .requested)
  held.open=true;await batch.value;Test.minimizeGate=nil
  precondition(group.snapshot[PreviewWindowIdentity(a)] == .completed && group.snapshot[PreviewWindowIdentity(b)] == .failed && group.targets.count==2)
  Test.failures=[];Test.calls=[];var restoredA=a;restoredA.isMinimized=true;var restoredB=b;restoredB.isMinimized=true;restoredB.lastAccessedTime=restoredA.lastAccessedTime.addingTimeInterval(1)
  Test.windows=[restoredA,restoredB];let restoreFeedback=ActionFeedbackHandle();restoreFeedback.setTargets(Test.windows)
  let focus=Gate();Test.focusGate=focus
  let restore=Task {await executor.run(.restoreAllOnDisplay,zone:.menuBar,cursor:.zero,feedback:restoreFeedback)}
  await waitUntil {focus.entered}
  precondition(restoreFeedback.snapshot.isEmpty,"Restore success preceded required activation")
  let stillOwned=WindowActionOwnership.shared.begin([PreviewWindowIdentity(a)]);precondition(stillOwned.admitted.isEmpty);stillOwned.finish()
  focus.open=true;await restore.value;Test.focusGate=nil
  precondition(restoreFeedback.snapshot.count==2 && restoreFeedback.snapshot.values.allSatisfy {$0 == .completed} && Test.calls.last == "focus2")
  Test.calls=[];let placement=Gate();Test.placeGate=placement
let olderFeedback=ActionFeedbackHandle();olderFeedback.setTargets([a])
let older=Task {await executor.run(.window(.fillLeftHalf),zone:.window(a,isFullscreen:false),cursor:.zero,feedback:olderFeedback)}
await waitUntil {placement.entered}
let newest=ActionFeedbackHandle();newest.setTargets([other]);await executor.run(.window(.close),zone:.window(other,isFullscreen:false),cursor:.zero,feedback:newest)
placement.open=true;await older.value;Test.placeGate=nil
precondition(olderFeedback.snapshot[PreviewWindowIdentity(a)] == .completed && !Test.calls.contains("focus1"),"Unrelated newer action caused false foreground failure")

  Test.calls=[];let slow=Gate();Test.placeGate=slow
  let cancelled=ActionFeedbackHandle();cancelled.setTargets([a]);let old=Task {await executor.run(.window(.center),zone:.window(a,isFullscreen:false),cursor:.zero,feedback:cancelled)}
  await waitUntil {slow.entered}
  let newer=WindowActionOwnership.shared.begin([PreviewWindowIdentity(a)])
  slow.open=true;await old.value;newer.finish();Test.placeGate=nil
  precondition(cancelled.snapshot[PreviewWindowIdentity(a)] == .cancelled && !Test.calls.contains("focus1"))
  FakeAX.shared.hasCloseControl=true
  for refused in [false,true] {FakeAX.shared.refuses=refused;let close=ActionFeedbackHandle();close.setTargets([a]);await executor.run(.closeTab,zone:.tab(a,tab:FakeAX.shared,isFullscreen:false,scrollable:false),cursor:.zero,feedback:close);precondition(close.snapshot[PreviewWindowIdentity(a)] == (refused ? .failed:.requested))}
  let nowFree=WindowActionOwnership.shared.begin([PreviewWindowIdentity(a),PreviewWindowIdentity(b)]);precondition(nowFree.admitted.count==2);nowFree.finish()
  print("PASS production gesture executor: settlement after placement/focus/enrollment, failures, request-only Close, protected display batches, unrelated work, restore lifetime and cancellation cleanup")
 }
}
SWIFT
Dir.mktmpdir('gesture-results-') do |dir|
  File.write("#{dir}/checks.swift", with_action_ownership(gesture_fixture))
  out,status=Open3.capture2e('xcrun','swiftc','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
  abort out unless status.success?
  out,status=Open3.capture2e("#{dir}/checks");puts out
  abort 'Gesture executor integration failed' unless status.success?
end

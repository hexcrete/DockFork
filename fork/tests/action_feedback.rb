#!/usr/bin/env ruby
# Execute the production feedback state machine with inert panels/monitors; no live preferences or windows.
require 'tmpdir'
require 'open3'
ROOT = File.expand_path('../..', __dir__)
source = File.read("#{ROOT}/DockDoor/Utilities/Window Gestures/WindowGestureHUD.swift")
keys = File.read("#{ROOT}/DockDoor/consts.swift")
view = File.read("#{ROOT}/DockDoor/Views/Settings/KeybindsSettingsView.swift")
catalog = File.read("#{ROOT}/DockDoor/Views/Settings/Search/SettingsSearchCatalog.swift")
%w[enableActionFeedback actionFeedbackPosition showMouseFollowsFocusFeedback].each do |key|
  abort "Missing reset: #{key}" unless File.read("#{ROOT}/DockDoor/Views/Settings/MainSettingsView.swift").include?(".#{key}")
  abort "Missing search target: #{key}" unless view.include?("settingsSearchTarget(\"gestures.#{key}\")")
  abort "Missing/duplicate search entry: #{key}" unless catalog.scan("id: \"gestures.#{key}\"").size == 1
end
abort 'Removed consolidation setting remains wired' if [source, keys, view, catalog, File.read("#{ROOT}/DockDoor/Views/Settings/MainSettingsView.swift")].any? { |text| text.include?('animateActionFeedbackConsolidation') }
abort 'Consolidation must only fade' if source.include?('towards destination:')
abort 'Feedback default must remain off' unless keys.include?('Key<Bool>("enableActionFeedback", default: false)')
abort 'Mouse follows focus feedback must default off' unless keys.include?('Key<Bool>("showMouseFollowsFocusFeedback", default: false)')
abort 'Unexpected timing change' unless source.include?('initiated: TimeInterval = 0.7') && source.include?('result: TimeInterval = 0.35')
abort 'Cursor motion must not measure popup contents' if source[source.index('    func followCursor()')...source.index('    private func targetFrame')].include?('fittingSize')
abort 'Popup must not slide or animate its frame' unless source.include?('animationBehavior = .none') && !source[source.index('final class ActionPopupPanel:')...source.index('final class ActionFeedbackController')].include?('animator().setFrame')
abort 'Popup content updates must not restart fade-in' unless source.include?('let needsFadeIn = !isVisible || isFadingOut') && source.include?('if needsFadeIn {')
abort 'Scripts must stay feedback-free' if File.read("#{ROOT}/DockDoor/Utilities/ScriptCommands.swift").include?('ActionFeedbackController')

abort 'Shared popup must retain gesture-overlay exclusion' unless source.include?('WindowGestureOverlays.register(windowNumber)') && source.include?('WindowGestureOverlays.unregister(windowNumber)')

stubs = <<~'SWIFT'
import AppKit
struct Key<T> { let value: T }
enum Defaults {
 protocol Serializable {}
 static var enabled = false, position = ActionFeedbackPosition.trigger, mouseFeedback = false
 static var callbacks: [UUID: (Change) -> Void] = [:]
 struct Change { let newValue: Bool }
 final class Observation { let id: UUID; init(_ id: UUID) { self.id = id }; func invalidate() { Defaults.callbacks[id] = nil } }
 static subscript<T>(_ key: Key<T>) -> T { key.value }
 static func observe(_ key: Key<Bool>, options: [Int], handler: @escaping (Change) -> Void) -> Observation {
  let id = UUID(); callbacks[id] = handler; return Observation(id)
 }
 static func disable() { enabled = false; for f in callbacks.values { f(Change(newValue: false)) } }
}
extension Key where T == Bool {
 static var enableActionFeedback: Self { Self(value: Defaults.enabled) }
 static var showMouseFollowsFocusFeedback: Self { Self(value: Defaults.mouseFeedback) }
 static var tileOnlyWhatFits: Self { Self(value: false) }
 static var fillActionsAutoTileSelection: Self { Self(value: false) }
}
extension Key where T == Int {
 static var maximumTilingRows: Self { Self(value: 2) }
 static var maximumTilingColumns: Self { Self(value: 3) }
}
extension Key where T == ActionFeedbackPosition { static var actionFeedbackPosition: Self { Self(value: Defaults.position) } }
struct PreviewWindowIdentity: Hashable { let pid: Int32; let windowID: UInt32; init(pid: Int32, windowID: UInt32) { self.pid = pid; self.windowID = windowID }; init(_ w: WindowInfo) { self.init(pid: 1, windowID: w.id) } }
struct TestApp { let processIdentifier: Int32 = 1; let isHidden: Bool }
struct WindowInfo { enum WindowPositionRect: Equatable { case test }; let id: UInt32; var isFullscreen: Bool? = false; var isMinimized = false; var isHidden = false; var isWindowlessApp = false; var app: TestApp { TestApp(isHidden: isHidden) } }
enum WindowAction { case quit, forceQuit, none, toggleWindowSelection, selectAllWindows, openAppWindow, close, closeAllWindows, minimize, minimizeAllWindows, hide, toggleFullScreen, autoTileSelectedWindows
 func appliesToSelectedWindow(_ w: WindowInfo) -> Bool { true }
 func autoTilingDirection(windowCount: Int, fillActionsAutoTile: Bool) -> Int? { self == .autoTileSelectedWindows ? 0 : nil }
 func menuTitle(for w: WindowInfo, batchTargets: [WindowInfo]?) -> String {
  switch self { case .close: "Close Window"; case .closeAllWindows: "Close All Windows"; case .minimizeAllWindows: "Minimize All Windows"; default: "Other Action" }
 }
 func batchTargets(from windows: [WindowInfo]) -> [WindowInfo] { windows }
 /* Batch target state */
 /* Feedback title */
 var iconName: String { self == .minimizeAllWindows ? "minus.circle.fill" : "xmark" }
 /* Menu icon */
}
enum WindowUtil {
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
 func present(_ content: WindowGestureHUD.Content, center: CGPoint? = nil) { value = content }
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
  precondition(WindowAction.hide.feedbackTitle(for: hidden[0], batchTargets: [hidden[0], windows[1]]) == "Hide App")
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
  File.write(path, stubs + timing + position + handle + controller + checks)
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
abort 'Menu actions must use async batch operation' unless menu.include?('action.usesConfirmedSingleWindowAction(on: window)') && menu.include?('await WindowUtil.performPreviewBatchAction(action, on: targets, allowFullscreenEntry: action == .toggleFullScreen, feedback: feedback)')
abort 'Minimize All must not settle on queueing' unless util.include?('if self != .autoTileSelectedWindows, self != .minimizeAllWindows { feedback?.finishRemaining(.requested) }')
abort 'Minimize All action must forward feedback' unless util.include?('WindowUtil.minimizeAllWindows(for: window.app, preferredWindows: preferredWindows, feedback: feedback)')
abort 'Container must wait for Minimize All confirmation' unless container.include?('if !awaitingMinimizeConfirmation { feedback?.finishRemaining(.requested) }') && container.include?('WindowUtil.minimizeAllWindows(for: app, preferredWindows: preferredWindows, feedback: feedback)')
minimize_fixture = <<~'SWIFT'
import Foundation
let kAXMinimizedAttribute = "minimized"
struct App { let bundleIdentifier: String? = "test"; var processIdentifier: Int32 = 1 }
final class AX: @unchecked Sendable {
 let lock = NSLock()
 var desired = false, fullscreen = false, refuses = false
 var changeAt: Date?, fullscreenGate: Gate?, writeGate: Gate?
 var settleDelay: TimeInterval = 0.07
 private var writes: [Bool] = []
 var writeValues: [Bool] { lock.withLock { writes } }
 func isFullscreen() throws -> Bool {
  precondition(!Thread.isMainThread)
  let pending=lock.withLock {let value=fullscreenGate;fullscreenGate=nil;return value}
  if let pending {pending.entered.signal();pending.release.wait()}
  return lock.withLock {fullscreen}
 }
 func isMinimized() throws -> Bool {
  lock.lock(); defer { lock.unlock() }
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
precondition(late.contains(PreviewWindowIdentity(a)));late.finish()
let appSingle=owner.begin([PreviewWindowIdentity(a)])
let appReplace=owner.begin([PreviewWindowIdentity(b)],apps:[1])
precondition(!appSingle.contains(PreviewWindowIdentity(a)) && appReplace.admitted.count==1);appReplace.finish()
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
 func record(_ identity: PreviewWindowIdentity, _ success: Bool) {
  lock.lock(); defer { lock.unlock() }
  calls += 1; values[identity.id] = success
 }
}
@main struct Checks {
SWIFT
Dir.mktmpdir('feedback-minimize-') do |dir|
  File.write("#{dir}/checks.swift", minimize_fixture)
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
struct NSRunningApplication { let processIdentifier: Int32 = 1 }
struct WindowInfo { let app = NSRunningApplication(); var isWindowlessApp = false; var isFullscreen: Bool? = false }
final class ActionFeedbackHandle: @unchecked Sendable {
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
  File.write("#{dir}/checks.swift", wrapper_fixture)
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
  File.write("#{dir}/checks.swift", native_fixture)
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
  File.write("#{dir}/checks.swift", warp_fixture)
  out, status = Open3.capture2e('xcrun', 'swiftc', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort out unless status.success?
  out, status = Open3.capture2e("#{dir}/checks")
  puts out
  abort 'Mouse Follows Focus feedback hook tests failed' unless status.success?
end

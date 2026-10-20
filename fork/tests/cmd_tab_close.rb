#!/usr/bin/env ruby
# Exercise the production Cmd+Tab app dispatcher and Close executor with inert targets.
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
coordinator = File.read("#{ROOT}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
keybinds = File.read("#{ROOT}/DockDoor/Utilities/KeybindHelper.swift")
abort 'Cmd+Tab Minimize must retain Command routing and focused-preview priority' unless keybinds.include?('let supportsHighlightedAppAction = action == .close || action == .minimize || action.isQuitAction') && keybinds.include?('let highlightedApps = hasSelection ? [] :') && keybinds.include?('if flags.contains(.maskCommand),')
dispatch = block(coordinator, '    private func closeCmdTabHighlightedApps(')
abort 'Cmd+Tab Close bypasses async executor' unless dispatch.include?('await WindowUtil.closeWindows(') && !dispatch.include?('action.perform(')
abort 'Close must snapshot targets and start feedback before dispatch' unless dispatch.index('let requests =') < dispatch.index('let task = WindowActionRequest.$current.withValue') && dispatch.index('ActionFeedbackController.begin') < dispatch.index('let task = WindowActionRequest.$current.withValue')
hide = block(coordinator, '    func hideWindow(')
abort 'Preview dismissal must not cancel accepted Close work' if hide.include?('previewBatchTask') || hide.include?('cancelPreviewBatchAction')
source = <<~'SWIFT'
import Foundation
typealias pid_t = Int32
enum Key { case quitAppOnWindowClose }
enum Defaults {
 static var quitOnClose = false, keepOpen = false
 static subscript(_ key: Key) -> Bool { quitOnClose }
}
final class Gate: @unchecked Sendable {
 let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
}
final class CloseTarget: @unchecked Sendable {
 let lock = NSLock()
 var gate: Gate?, accepts = true
 private var count = 0
 var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
 func close(progress: (@Sendable (Int, Int) -> Void)?) -> Bool {
  precondition(!Thread.isMainThread, "Close AX work ran on main thread")
  lock.lock(); count += 1; let pending = gate, accepted = accepts; lock.unlock()
  progress?(0, 2)
  if let pending { pending.entered.signal(); pending.release.wait() }
  if accepted { progress?(2, 2) }
  return accepted
 }
}
final class NSRunningApplication: @unchecked Sendable {
 let processIdentifier: pid_t
 var isTerminated = false, acceptsQuit = true
 var normalQuits = 0, forceQuits = 0
 static var finder: NSRunningApplication?
 init(_ pid: pid_t) { processIdentifier = pid }
 static func runningApplications(withBundleIdentifier: String) -> [NSRunningApplication] { finder.map { [$0] } ?? [] }
}
struct PreviewWindowIdentity: Hashable, Sendable {
 let pid: pid_t, windowID: Int
 init(_ window: WindowInfo) { pid = window.app.processIdentifier; windowID = window.id }
}
struct WindowInfo: Sendable {
 let app: NSRunningApplication, id: Int
 var isWindowlessApp = false
 let target: CloseTarget
 static func windowlessEntry(for app: NSRunningApplication) -> WindowInfo { WindowInfo(app: app, id: 0, isWindowlessApp: true, target: CloseTarget()) }
 func close(progress: (@Sendable (Int, Int) -> Void)?) -> Bool { target.close(progress: progress) }
 func quit(force: Bool) -> Bool {
  precondition(Thread.isMainThread, "AppKit Quit must stay on main")
  guard !app.isTerminated else { return false }
  if force { app.forceQuits += 1 } else { app.normalQuits += 1 }
  return app.acceptsQuit
 }
}
enum ActionFeedbackOutcome { case requested, failed, cancelled }
final class ActionFeedbackHandle: @unchecked Sendable {
 let identities: [PreviewWindowIdentity]
 let lock = NSLock()
 private var outcomes: [PreviewWindowIdentity: ActionFeedbackOutcome] = [:]
 private var progressCounts: [PreviewWindowIdentity: Int] = [:]
 init(_ windows: [WindowInfo]) { identities = windows.map(PreviewWindowIdentity.init) }
 func finish(_ identity: PreviewWindowIdentity, _ result: ActionFeedbackOutcome) {
  lock.lock(); defer { lock.unlock() }; if outcomes[identity] == nil { outcomes[identity] = result }
 }
 func state(_ window: WindowInfo) -> ActionFeedbackOutcome? { lock.lock(); defer { lock.unlock() }; return outcomes[PreviewWindowIdentity(window)] }
 func progress(_ window: WindowInfo) -> Int { lock.lock(); defer { lock.unlock() }; return progressCounts[PreviewWindowIdentity(window), default: 0] }
 func finishRemaining(_ outcome: ActionFeedbackOutcome) { for id in identities { finish(id, outcome) } }
 func closeProgress(for identity: PreviewWindowIdentity) -> @Sendable (Int, Int) -> Void {
  { _, _ in self.lock.lock(); self.progressCounts[identity, default: 0] += 1; self.lock.unlock() }
 }
}
@MainActor enum ActionFeedbackController {
 static var handles: [ActionFeedbackHandle] = [], enabled = true
 static func begin(_ action: WindowAction, windows: [WindowInfo], keyboard: Bool, usePreviews: Bool, resolvedTargets: [WindowInfo]? = nil) -> ActionFeedbackHandle? {
  if let resolvedTargets {precondition(resolvedTargets.map(PreviewWindowIdentity.init) == windows.map(PreviewWindowIdentity.init))}
  guard enabled else { return nil }
  let targets = windows.filter { !$0.isWindowlessApp || action.isQuitAction }
  guard !targets.isEmpty else { return nil }
  precondition(keyboard && !usePreviews)
  let handle = ActionFeedbackHandle(targets); handles.append(handle); return handle
 }
}
enum WindowAction {
 case close, closeAllWindows, minimize, minimizeAllWindows, quit, forceQuit, none
 func isSupported(for window: WindowInfo) -> Bool { true }
 var isQuitAction: Bool { self == .quit || self == .forceQuit }
 var shouldScheduleAppRefresh: Bool { true }
 enum PostActionCategory {
  case closing
  var keepPreviewsOpen: Bool { Defaults.keepOpen }
 }
 enum ActionResult { case noChange, dismissed }
 func perform(on window: WindowInfo, keepPreviewOnQuit: Bool) -> ActionResult {
  precondition(isQuitAction, "Close ran through synchronous action executor")
  return window.quit(force: self == .forceQuit) ? .dismissed : .noChange
 }
}
enum WindowUtil {
 static var cache: [pid_t: [WindowInfo]] = [:]
 struct PreviewBatchResult { var succeeded: [WindowInfo] = []; var failed: [PreviewWindowIdentity] = [] }
 static func readCachedWindows(for pid: pid_t) -> [WindowInfo] { cache[pid] ?? [] }
SWIFT
source += block(util, '    static func shouldQuitAppOnWindowClose(') + "\n"
source += block(util, '    private actor CloseExecutor') + "\n"
source += util.lines.find { |line| line.include?('private static let closeExecutor =') }
source += block(util, '    static func closeWindows(') + "\n"
source += block(util, '    private static func requestWindowClosures(') + "\n}\n"
source += <<~'SWIFT'
@MainActor final class PreviewState {
 var windows: [WindowInfo] = [], pointerInteractionSessionID: UInt = 1, focusRefreshes = 0
 func scheduleActiveFocusedWindowRefresh() { focusRefreshes += 1 }
}
@MainActor final class Coordinator {
 let windowSwitcherCoordinator = PreviewState()
 var previewBatchTask: Task<Void, Never>?, previewBatchToken: UUID?
 var previewActionTasks: [UUID:(request:WindowActionRequest, task:Task<Void,Never>)] = [:]
 var pendingAction:Task<Void,Never>? {previewBatchToken.flatMap {previewActionTasks[$0]?.task}}
 var isVisible = true, hides = 0, refreshes: [pid_t] = []
 var minimizeTargets: [WindowInfo] = [], minimizePreserves: Bool?
 func performPreviewBatchAction(_ action: WindowAction, on targets: [WindowInfo], initiator: WindowInfo, preservePreviews: Bool, keyboard: Bool, usePreviews: Bool) -> Bool {
  precondition(action == .minimizeAllWindows && keyboard && !usePreviews && targets.first?.id == initiator.id)
  minimizeTargets = targets; minimizePreserves = preservePreviews
  return false
 }
 func hideWindow() { hides += 1; isVisible = false; windowSwitcherCoordinator.windows = [] }
 func scheduleInPlaceActionRefresh(for app: NSRunningApplication) { refreshes.append(app.processIdentifier) }
 func scheduleFailedClosingFocusNotification(action: WindowAction, window: WindowInfo, willQuitOnClose: Bool) {}
SWIFT
source += block(coordinator, '    func performActionOnCmdTabHighlightedApps(') + "\n"
source += block(coordinator, '    private func cmdTabActionWindows(').sub('private func', 'func') + "\n"
source += dispatch.sub('private func', 'func') + "\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async throws {
  func window(_ app: NSRunningApplication, _ id: Int, accepts: Bool = true) -> WindowInfo {
   let target = CloseTarget(); target.accepts = accepts; return WindowInfo(app: app, id: id, target: target)
  }
  func entered(_ gate: Gate) async throws {
   for _ in 0..<2000 {
    if gate.entered.wait(timeout: .now()) == .success { return }
    try await Task.sleep(nanoseconds: 1_000_000)
   }
   preconditionFailure("Close worker never entered")
  }
  let a = NSRunningApplication(1), b = NSRunningApplication(2), terminated = NSRunningApplication(3)
  terminated.isTerminated = true
  let a1 = window(a, 1), a2 = window(a, 2), hiddenByFilter = window(a, 3), b1 = window(b, 4)
  WindowUtil.cache = [1: [a1, a2, hiddenByFilter], 2: [b1]]
  for preserve in [false, true] {
   let owner = Coordinator(); owner.windowSwitcherCoordinator.windows = [a1, a2, .windowlessEntry(for: b)]
   let handled = owner.performActionOnCmdTabHighlightedApps(action: .minimize, apps: [a, a, b, terminated], preservePreviews: preserve)
   precondition(!handled && owner.minimizeTargets.map(PreviewWindowIdentity.init) == [a1, a2, b1].map(PreviewWindowIdentity.init))
   precondition(owner.minimizePreserves == preserve && owner.isVisible && owner.hides == 0 && a.normalQuits == 0)
  }
  let windowlessApp = NSRunningApplication(99), windowless = Coordinator()
  windowless.windowSwitcherCoordinator.windows = [.windowlessEntry(for: windowlessApp)]
  precondition(!windowless.performActionOnCmdTabHighlightedApps(action: .minimize, apps: [windowlessApp]))
  precondition(windowless.minimizePreserves == nil && windowless.minimizeTargets.isEmpty)
  print("PASS Cmd+Tab Minimize routes to shared app-header toggle: Command/focused-preview priority, real target snapshot/cache fallback, PID deduplication, terminated/windowless exclusions and preserved presentation")
  let baseline = Coordinator(); baseline.windowSwitcherCoordinator.windows = [a1, a2, .windowlessEntry(for: b)]
  let dismissed = baseline.performActionOnCmdTabHighlightedApps(action: .close, apps: [a, a, b, terminated])
  precondition(!dismissed && baseline.isVisible)
  let feedback = ActionFeedbackController.handles.last!
  precondition(feedback.identities == [a1, a2, b1].map(PreviewWindowIdentity.init))
  await baseline.pendingAction?.value
  precondition([a1, a2, b1].allSatisfy { $0.target.calls == 1 && feedback.state($0) == .requested && feedback.progress($0) == 2 })
  precondition(hiddenByFilter.target.calls == 0 && a.normalQuits == 0 && baseline.hides == 1)
  precondition(baseline.pendingAction == nil && baseline.previewBatchToken == nil && baseline.refreshes == [1, 2])
  for (setting, preserve) in [(true, false), (false, true)] {
   Defaults.keepOpen = setting
   let owner = Coordinator(); owner.windowSwitcherCoordinator.windows = [a1]
   owner.performActionOnCmdTabHighlightedApps(action: .close, apps: [a], preservePreviews: preserve)
   await owner.pendingAction?.value
   precondition(owner.isVisible && owner.hides == 0)
  }
  Defaults.keepOpen = false
  for reopen in [false, true] {
   let app = NSRunningApplication(reopen ? 5 : 4), gate = Gate()
   let first = window(app, 10), second = window(app, 11)
   first.target.gate = gate
   let owner = Coordinator(); owner.windowSwitcherCoordinator.windows = [first, second]
   owner.performActionOnCmdTabHighlightedApps(action: .close, apps: [app], preservePreviews: true)
   let task = owner.pendingAction!, feedback = ActionFeedbackController.handles.last!
   try await entered(gate)
   // This main-actor work runs while the Close AX call remains blocked.
   precondition(feedback.state(first) == nil && feedback.progress(first) == 1)
   owner.hideWindow()
   if reopen { owner.isVisible = true; owner.windowSwitcherCoordinator.pointerInteractionSessionID += 1; owner.windowSwitcherCoordinator.windows = [b1] }
   gate.release.signal(); await task.value
   precondition(first.target.calls == 1 && second.target.calls == 1)
   precondition(feedback.state(first) == .requested && feedback.state(second) == .requested)
   precondition(owner.hides == 1 && owner.refreshes.isEmpty && owner.windowSwitcherCoordinator.focusRefreshes == 0)
  }
  Defaults.quitOnClose = true
  for (eligible, accepted, finder) in [(true, true, false), (false, true, false), (true, false, false), (true, true, true)] {
   let app = NSRunningApplication(6), refused = window(app, 20, accepts: false)
   app.acceptsQuit = accepted; Defaults.quitOnClose = eligible
   NSRunningApplication.finder = finder ? app : nil
   WindowUtil.cache[6] = [refused]
   let owner = Coordinator(); owner.windowSwitcherCoordinator.windows = [refused]
   owner.performActionOnCmdTabHighlightedApps(action: .close, apps: [app], preservePreviews: true)
   let feedback = ActionFeedbackController.handles.last!
   await owner.pendingAction?.value
   let attempts = eligible && !finder ? 1 : 0
   precondition(app.normalQuits == attempts && app.forceQuits == 0)
   precondition(feedback.state(refused) == (attempts == 1 && accepted ? .requested : .failed))
  }
  NSRunningApplication.finder = nil; Defaults.quitOnClose = true
  let mixedApp = NSRunningApplication(7), accepted = window(mixedApp, 30), refused = window(mixedApp, 31, accepts: false)
  WindowUtil.cache[7] = [accepted]
  let mixed = Coordinator(); mixed.windowSwitcherCoordinator.windows = [accepted, refused]
  mixed.performActionOnCmdTabHighlightedApps(action: .close, apps: [mixedApp], preservePreviews: true)
  let mixedFeedback = ActionFeedbackController.handles.last!
  await mixed.pendingAction?.value
  precondition(mixedApp.normalQuits == 0 && mixedFeedback.state(accepted) == .requested && mixedFeedback.state(refused) == .failed)
  let app = NSRunningApplication(8), gate = Gate(), refusal = window(NSRunningApplication(9), 40, accepts: false)
  let held = window(app, 41, accepts: false); held.target.gate = gate
  WindowUtil.cache[8] = [held]
  let changed = Coordinator(); changed.windowSwitcherCoordinator.windows = [held]
  changed.performActionOnCmdTabHighlightedApps(action: .close, apps: [app], preservePreviews: true)
  let changedTask = changed.pendingAction!
  try await entered(gate)
  WindowUtil.cache[8] = [held, window(app, 42)]
  gate.release.signal(); await changedTask.value
  precondition(app.normalQuits == 0)
  let emptyApp = NSRunningApplication(10), empty = Coordinator()
  empty.performActionOnCmdTabHighlightedApps(action: .close, apps: [emptyApp], preservePreviews: true)
  await empty.pendingAction?.value
  precondition(emptyApp.normalQuits == 1 && emptyApp.forceQuits == 0)
  Defaults.quitOnClose = false
  let directRefusal = window(NSRunningApplication(13), 49, accepts: false)
  let directFeedback = ActionFeedbackHandle([directRefusal])
  let directResult = await WindowUtil.closeWindows([directRefusal], feedback: directFeedback)
  precondition(directResult.failed.count == 1 && directFeedback.state(directRefusal) == .failed)
  let staleApp = NSRunningApplication(11), staleGate = Gate(), staleFirst = window(staleApp, 50), staleSecond = window(staleApp, 51)
  staleFirst.target.gate = staleGate
  let latest = Coordinator(); latest.windowSwitcherCoordinator.windows = [staleFirst, staleSecond]
  latest.performActionOnCmdTabHighlightedApps(action: .close, apps: [staleApp], preservePreviews: true)
  let oldTask = latest.pendingAction!
  try await entered(staleGate)
  latest.windowSwitcherCoordinator.windows = [b1]
  latest.performActionOnCmdTabHighlightedApps(action: .close, apps: [b], preservePreviews: true)
  let newTask = latest.pendingAction!, newFeedback = ActionFeedbackController.handles.last!
  staleGate.release.signal(); await oldTask.value; await newTask.value
  precondition(staleFirst.target.calls == 1 && staleSecond.target.calls == 1 && newFeedback.state(b1) == .requested)
  precondition(latest.refreshes == [2] && latest.pendingAction == nil && latest.previewBatchToken == nil)
  for action in [WindowAction.quit, .forceQuit] {
   let app = NSRunningApplication(12), owner = Coordinator()
   owner.performActionOnCmdTabHighlightedApps(action: action, apps: [app, app], preservePreviews: true)
   precondition(owner.pendingAction == nil && app.normalQuits == (action == .quit ? 1 : 0) && app.forceQuits == (action == .forceQuit ? 1 : 0))
  }
  let cancelled = Coordinator(); cancelled.windowSwitcherCoordinator.windows = [refusal]
  cancelled.performActionOnCmdTabHighlightedApps(action: .close, apps: [refusal.app])
  let cancelledTask = cancelled.pendingAction!; cancelledTask.cancel(); await cancelledTask.value
  precondition(refusal.target.calls == 0 && cancelled.hides == 0 && cancelled.previewBatchToken == nil)
  ActionFeedbackController.enabled = false
  let count = ActionFeedbackController.handles.count, disabled = Coordinator()
  disabled.windowSwitcherCoordinator.windows = [b1]
  disabled.performActionOnCmdTabHighlightedApps(action: .close, apps: [b], preservePreviews: true)
  await disabled.pendingAction?.value
  precondition(ActionFeedbackController.handles.count == count)
  print("PASS Cmd+Tab Close: off-main AX/main-actor progress, target snapshots/PID deduplication, real feedback/progress, keep-open policy, dismissal/reopening, fallback/refusal/Finder/partial success, live fallback validation, supersession, queued cancellation, cleanup, disabled feedback and synchronous Quit/Force Quit")
 }
}
SWIFT
Dir.mktmpdir('dockfork-cmd-tab-close-') do |dir|
  File.write("#{dir}/checks.swift", with_action_ownership(source))
  abort 'Swift compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', '-suppress-warnings', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Cmd+Tab Close checks failed' unless system("#{dir}/checks")
end

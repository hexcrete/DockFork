#!/usr/bin/env ruby
# Compile the production visibility workers against inert AX targets. Never manipulate real apps.
require 'tmpdir'
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
catalog = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowActionCatalog.swift")
coordinator = File.read("#{ROOT}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
container = File.read("#{ROOT}/DockDoor/Views/Hover Window/WindowPreviewHoverContainer.swift")
menu = File.read("#{ROOT}/DockDoor/Utilities/WindowActionsMenuController.swift")
gesture = File.read("#{ROOT}/DockDoor/Utilities/Window Gestures/WindowGestureExecutor.swift")
[coordinator, container, menu, gesture].each do |source|
  abort 'Interactive caller bypasses confirmed action routing' unless source.include?('action.usesConfirmedSingleWindowAction(on: window)')
end
restore = block(File.read("#{ROOT}/DockDoor/Utilities/KeybindHelper.swift"), '    private func switchToLastFocusedWindow(')
abort 'Last-focused restoration must confirm before activation' unless restore.index('await WindowUtil.revealWindowConfirmed') < restore.index('await targetWindow.bringToFrontConfirmed')
abort 'Last-focused restoration still uses synchronous toggles' if restore.match?(/toggleHidden|toggleMinimize|isEffectivelyHiddenForUI/)
batch = block(util, '    static func performPreviewBatchAction(')
abort 'Hide retains main-actor fullscreen scan' if batch.include?('hasOnlyFullscreenWindows')
info = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowInfo.swift")
abort 'Bypassed synchronous visibility toggles remain' if info.match?(/func toggleHidden\(|func toggleFullScreen\(/)
dispatch = block(coordinator, '    private func performPreviewBatchAction(')
abort 'Feedback must precede worker dispatch' unless dispatch.index('ActionFeedbackController.begin') < dispatch.index('await WindowUtil.performPreviewBatchAction')
abort 'Single Hide/restore must retain ordinary filtered-row refresh' unless dispatch.include?('targets.count == 1 && (action == .hide || action == .openAppWindow)')
abort 'Fullscreen single-window permission missing' unless block(coordinator, '    func performSingleWindowAction(').include?('allowFullscreenEntry: action == .toggleFullScreen')
abort 'Checked fullscreen must remain exit-only' if block(coordinator, '    func performCheckedWindowAction(').include?('allowFullscreenEntry: true')
tap = block(File.read("#{ROOT}/DockDoor/Views/Hover Window/WindowPreviewInteractionModifier.swift"), '    private func handleWindowTap(')
abort 'Activation must not reuse toggle actions or their keep-preview policy' if tap.match?(/handleWindowAction\(\.(minimize|hide)\)|isEffectivelyHiddenForUI/)
task_start = tap.index('            activationTask = Task')
opening = tap.index('{', task_start)
depth = 0
task_end = (opening...tap.length).find do |i|
  depth += 1 if tap[i] == '{'
  depth -= 1 if tap[i] == '}'
  depth.zero?
end
activation = tap[task_start..task_end]

source = <<~'SWIFT'
import Foundation
typealias AXUIElement = FakeAX
let kAXFullscreenAttribute = "fullscreen", kAXHiddenAttribute = "hidden"
enum AXFailure: Error { case refused }
final class Gate: @unchecked Sendable {
 let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
}
final class FakeAX: @unchecked Sendable {
 let lock = NSLock()
 var values = ["fullscreen": false, "hidden": false]
 var events: [String] = []
 var gate: Gate?, blockedEvent: String?, refuse = false, throwAfterWrite = false
 func record(_ event: String) -> Bool {
  precondition(!Thread.isMainThread, "AX call on UI thread: \(event)")
  lock.lock(); events.append(event)
  let pending = blockedEvent == event ? gate : nil
  if pending != nil { blockedEvent = nil }
  let refuses = refuse; lock.unlock()
  if let pending { pending.entered.signal(); pending.release.wait() }
  return refuses
 }
 func isFullscreen() throws -> Bool {
  _ = record("read fullscreen"); return value("fullscreen")
 }
 func focusedWindow() throws -> FakeAX { _ = record("focused"); return self }
 func cgWindowId() throws -> Int { _ = record("id"); return 1 }
 func attribute(_ name: String, _ type: Bool.Type) throws -> Bool {
  _ = record("read \(name)"); return value(name)
 }
 func setAttribute(_ name: String, _ value: Bool) throws {
  let refused = record("write \(name)")
  lock.lock(); if !refused { values[name] = value }; let shouldThrow = throwAfterWrite; lock.unlock()
  if shouldThrow { throw AXFailure.refused }
 }
 func value(_ name: String) -> Bool { lock.lock(); defer { lock.unlock() }; return values[name] ?? false }
 func set(_ name: String, _ value: Bool) { lock.lock(); values[name] = value; lock.unlock() }
 func history() -> [String] { lock.lock(); defer { lock.unlock() }; return events }
}
final class NSRunningApplication: @unchecked Sendable {
 let processIdentifier: Int32
 let element = FakeAX()
 var isTerminated = false
 var isHidden: Bool { element.value("hidden") }
 init(_ pid: Int32) { processIdentifier = pid }
}
enum NSWorkspace { static let shared = Workspace() }
final class Workspace { var frontmostApplication: NSRunningApplication? }
struct WindowInfo: Sendable {
 let axElement: FakeAX, app: NSRunningApplication
 let id = 1
 var appAxElement: FakeAX { app.element }
 var isWindowlessApp = false, isMinimized = false, isHidden = false
 @MainActor func bringToFrontConfirmed() async -> Bool {
  precondition(!app.isHidden); ActivationEvents.record("focus"); return true
 }
 @MainActor func warpMouseToCenterIfNeeded() { ActivationEvents.warps += 1 }
}
enum ActivationEvents {
 static let lock = NSLock()
 private static var stored: [String] = []
 static var sequence: [String] {
  get { lock.lock(); defer { lock.unlock() }; return stored }
  set { lock.lock(); stored = newValue; lock.unlock() }
 }
 static func record(_ event: String) { lock.lock(); stored.append(event); lock.unlock() }
 static var warps = 0
}
var apps: [Int32: NSRunningApplication] = [:]
func AXUIElementCreateApplication(_ pid: Int32) -> FakeAX { apps[pid]!.element }
enum WindowAction { case minimize, hide, toggleFullScreen, openAppWindow, close, closeAllWindows, quit
 var positionRect:Int? {nil}
 static let fullscreenConfirmationDelay: UInt64 = 180_000_000
SWIFT
source += block(catalog, '    func usesConfirmedSingleWindowAction(') + "\n}\n"
source += <<~'SWIFT'
enum WindowUtil {
 static var states: [Bool] = [], hiddenStates: [Bool] = [], reconciled: [UInt64] = [], minimized = 0
 static let fullscreenExitMetadataReconciliationDelayNanos: UInt64 = 450_000_000
 static func updateCachedWindowState(_ window: WindowInfo, isFullscreen: Bool) { states.append(isFullscreen) }
 static func updateCachedWindowStates(for pid: Int32, isHidden: Bool) { hiddenStates.append(isHidden); if !isHidden { ActivationEvents.record("unhide") } }
 static func scheduleCachedWindowMetadataReconciliation(pid: Int32, windowID: Int, delayNanos: UInt64) { reconciled.append(delayNanos) }
 static func setMinimizedStateConfirmed(_ windows: [WindowInfo], isMinimized: Bool) async -> Int { minimized += 1; ActivationEvents.record("unminimize"); return windows.count }
}
extension WindowUtil {
SWIFT
%w[changeFullscreenConfirmed setHiddenStateConfirmed revealWindowConfirmed exitFullScreenWithoutActivation].each do |name|
  signature = name == 'changeFullscreenConfirmed' ? "    private static func #{name}(" : "    static func #{name}("
  source += block(util, signature).sub('private static', 'static') + "\n"
end
source += "}\n"
source += <<~'SWIFT'
@MainActor final class PreviewState { var pointerInteractionSessionID = UUID() }
@MainActor final class PreviewCoordinator {
 let windowSwitcherCoordinator = PreviewState()
 var isVisible = true
}
@MainActor final class TapHarness {
 let windowInfo: WindowInfo
 var activationTask: Task<Void, Never>?
 var windowSwitcherActive = false
 var onTap: (() -> Void)? = { ActivationEvents.record("dismiss") }
 init(_ window: WindowInfo) { windowInfo = window }
 func activate(_ coordinator: PreviewCoordinator) {
  let sessionID = coordinator.windowSwitcherCoordinator.pointerInteractionSessionID
SWIFT
# SwiftUI's value-type self is implicit; the class harness needs an explicit capture.
source += activation.sub('[weak coordinator]', '[self, weak coordinator]') + "\n}\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async throws {
  func window(_ pid: Int32) -> WindowInfo {
   let app = NSRunningApplication(pid); apps[pid] = app
   return WindowInfo(axElement: FakeAX(), app: app)
  }
  func entered(_ gate: Gate) async throws {
   for _ in 0..<2000 {
    if gate.entered.wait(timeout: .now()) == .success { return }
    try await Task.sleep(nanoseconds: 1_000_000)
   }
   preconditionFailure("Worker never entered")
  }
  let fast = window(1)
  let enteredFull = await WindowUtil.changeFullscreenConfirmed(fast, toggle: true)
  precondition(enteredFull && WindowUtil.states == [true])
  precondition(fast.axElement.history() == ["read fullscreen", "write fullscreen", "read fullscreen"])
  let exited = await WindowUtil.changeFullscreenConfirmed(fast)
  precondition(exited && WindowUtil.states == [true, false])
  let noOp = window(2)
  let unchanged = await WindowUtil.changeFullscreenConfirmed(noOp)
  precondition(unchanged)
  precondition(noOp.axElement.history() == ["read fullscreen", "read fullscreen"])
  let slow = window(3), gate = Gate()
  slow.axElement.gate = gate; slow.axElement.blockedEvent = "read fullscreen"
  var settled = 0, feedbackVisible = true
  let action = Task { let result = await WindowUtil.changeFullscreenConfirmed(slow, toggle: true); settled += 1; return result }
  try await entered(gate)
  // The AX call is still blocked; a main-actor feedback update must run before release.
  await Task.yield(); feedbackVisible = false
  precondition(!feedbackVisible && settled == 0)
  action.cancel(); gate.release.signal()
  let cancelled = await action.value
  precondition(!cancelled && settled == 1 && slow.axElement.history() == ["read fullscreen"])
  let afterWrite = window(4), writeGate = Gate()
  afterWrite.axElement.gate = writeGate; afterWrite.axElement.blockedEvent = "write fullscreen"
  let stateCount = WindowUtil.states.count
  let writing = Task { await WindowUtil.changeFullscreenConfirmed(afterWrite, toggle: true) }
  try await entered(writeGate); writing.cancel(); writeGate.release.signal()
  let stale = await writing.value
  precondition(!stale && WindowUtil.states.count == stateCount && afterWrite.axElement.history() == ["read fullscreen", "write fullscreen"])
  let queued = window(5), start = Gate()
  let cancelledBeforeStart = Task {
   while start.release.wait(timeout: .now()) != .success { await Task.yield() }
   return await WindowUtil.changeFullscreenConfirmed(queued, toggle: true)
  }
  cancelledBeforeStart.cancel(); start.release.signal()
  let noDispatch = await cancelledBeforeStart.value
  precondition(!noDispatch && queued.axElement.history().isEmpty)
  let replaced = window(6)
  let refusedHandoff = await WindowUtil.changeFullscreenConfirmed(replaced, toggle: true, beforeChange: { _ in false })
  precondition(!refusedHandoff && replaced.axElement.history() == ["read fullscreen"])
  var beforeWrite = false
  let handoff = await WindowUtil.changeFullscreenConfirmed(replaced, toggle: true, beforeChange: { transitions in
   beforeWrite = transitions && replaced.axElement.history() == ["read fullscreen", "read fullscreen"]; return true
  })
  precondition(handoff && beforeWrite)
  let fullscreenRefusal = window(7); fullscreenRefusal.axElement.refuse = true
  let refused = await WindowUtil.changeFullscreenConfirmed(fullscreenRefusal, toggle: true)
  precondition(!refused && fullscreenRefusal.axElement.history().filter { $0 == "write fullscreen" }.count == 1)
  precondition(fullscreenRefusal.axElement.history().filter { $0 == "read fullscreen" }.count == 5)
  let partial = window(19); partial.axElement.throwAfterWrite = true
  let published = WindowUtil.states.count, reconciled = WindowUtil.reconciled.count
  let partialFailure = await WindowUtil.changeFullscreenConfirmed(partial, toggle: true)
  precondition(!partialFailure && partial.axElement.value("fullscreen"))
  precondition(WindowUtil.states.count == published && WindowUtil.reconciled.count == reconciled + 1)
  let hidden = window(8)
  let didHide = await WindowUtil.setHiddenStateConfirmed(for: hidden.app, isHidden: true)
  precondition(didHide && hidden.app.element.history() == ["write hidden", "read hidden"])
  let guardedHide = window(16)
  var hideHandoff = false
  let preparedHide = await WindowUtil.setHiddenStateConfirmed(for: guardedHide.app, isHidden: true, beforeChange: { _ in
   hideHandoff = guardedHide.app.element.history().isEmpty; return true
  })
  precondition(preparedHide && hideHandoff)
  let staleHide = window(17)
  let rejectedHide = await WindowUtil.setHiddenStateConfirmed(for: staleHide.app, isHidden: true, beforeChange: { _ in false })
  precondition(!rejectedHide && staleHide.app.element.history().isEmpty)
  let hideWriteGate = Gate(), cancelledWrite = window(18)
  cancelledWrite.app.element.gate = hideWriteGate; cancelledWrite.app.element.blockedEvent = "write hidden"
  let hiddenCount = WindowUtil.hiddenStates.count
  let hiddenWrite = Task { await WindowUtil.setHiddenStateConfirmed(for: cancelledWrite.app, isHidden: true) }
  try await entered(hideWriteGate); hiddenWrite.cancel(); hideWriteGate.release.signal()
  let hiddenStale = await hiddenWrite.value
  precondition(!hiddenStale && WindowUtil.hiddenStates.count == hiddenCount)
  let fullOnly = window(9); fullOnly.axElement.set("fullscreen", true)
  let blockedHide = await WindowUtil.setHiddenStateConfirmed(for: fullOnly.app, isHidden: true, fullscreenCandidates: [fullOnly.axElement])
  precondition(!blockedHide && fullOnly.app.element.history().isEmpty)
  let hideGate = Gate(), slowHide = window(10)
  slowHide.axElement.gate = hideGate; slowHide.axElement.blockedEvent = "read fullscreen"
  let hiding = Task { await WindowUtil.setHiddenStateConfirmed(for: slowHide.app, isHidden: true, fullscreenCandidates: [slowHide.axElement]) }
  try await entered(hideGate)
  let other = window(11)
  let independent = await WindowUtil.setHiddenStateConfirmed(for: other.app, isHidden: true)
  precondition(independent && slowHide.app.element.history().isEmpty)
  hiding.cancel(); hideGate.release.signal()
  let cancelledHide = await hiding.value
  precondition(!cancelledHide && slowHide.app.element.history().isEmpty)
  let refuseHide = window(12); refuseHide.app.element.refuse = true
  let hideFailed = await WindowUtil.setHiddenStateConfirmed(for: refuseHide.app, isHidden: true)
  precondition(!hideFailed && refuseHide.app.element.history() == ["write hidden", "read hidden", "read hidden", "read hidden"])
  var restore = window(13)
  let normal = await WindowUtil.revealWindowConfirmed(restore)
  precondition(normal && restore.app.element.history().isEmpty && WindowUtil.minimized == 0)
  restore.isMinimized = true; restore.app.element.set("hidden", true)
  let revealed = await WindowUtil.revealWindowConfirmed(restore)
  precondition(revealed && WindowUtil.minimized == 1 && restore.app.element.history() == ["write hidden", "read hidden"])
  let exit = window(14); exit.axElement.set("fullscreen", true)
  let exitConfirmed = await WindowUtil.exitFullScreenWithoutActivation(exit)
  precondition(exitConfirmed && WindowUtil.reconciled.last == 450_000_000)
  exit.axElement.set("fullscreen", true)
  NSWorkspace.shared.frontmostApplication = exit.app
  var activeExitTransition = false
  let activeExit = await WindowUtil.changeFullscreenConfirmed(exit, toggle: true, beforeChange: { transitions in
   activeExitTransition = transitions; return true
  })
  precondition(activeExit && activeExitTransition && exit.app.element.history() == ["focused", "id"])
  NSWorkspace.shared.frontmostApplication = nil
  var placeholder = window(15); placeholder.isWindowlessApp = true
  precondition(WindowAction.hide.usesConfirmedSingleWindowAction(on: placeholder))
  precondition(!WindowAction.openAppWindow.usesConfirmedSingleWindowAction(on: placeholder))
  precondition(WindowAction.openAppWindow.usesConfirmedSingleWindowAction(on: fast))
  for (minimized, hidden) in [(false, false), (true, false), (false, true), (true, true)] {
   var target = window(20); target.isMinimized = minimized; target.isHidden = hidden
   target.app.element.set("hidden", hidden)
   let coordinator = PreviewCoordinator(), tap = TapHarness(target)
   ActivationEvents.sequence = []; ActivationEvents.warps = 0
   tap.activate(coordinator); await tap.activationTask?.value
   let expected = (hidden ? ["unhide"] : []) + (minimized ? ["unminimize"] : []) + ["focus", "dismiss"]
   precondition(ActivationEvents.sequence == expected && ActivationEvents.warps == 0)
  }
  let staleActivation = window(21), activationGate = Gate()
  staleActivation.app.element.set("hidden", true)
  staleActivation.app.element.gate = activationGate; staleActivation.app.element.blockedEvent = "write hidden"
  let coordinator = PreviewCoordinator(), tap = TapHarness(staleActivation)
  ActivationEvents.sequence = []
  tap.activate(coordinator); try await entered(activationGate)
  coordinator.windowSwitcherCoordinator.pointerInteractionSessionID = UUID()
  activationGate.release.signal(); await tap.activationTask?.value
  precondition(ActivationEvents.sequence == ["unhide"])
  print("PASS ordinary preview activation: visible/minimized/hidden/both restore then focus/dismiss, without toggle actions; superseded sessions do not focus or dismiss")
  print("PASS visibility worker fast-path call counts, unchanged retry limits, off-main AX, main-actor progress, independent apps, cancellation before/between calls, stale publication, transition handoff, restore and routing")
 }
}
SWIFT
Dir.mktmpdir('dockfork-responsiveness-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Swift compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', '-suppress-warnings', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Responsiveness checks failed' unless system("#{dir}/checks")
end

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
batch = block(util, '    static func performPreviewBatchAction(') + block(util, '    private static func executePreviewAction(')
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
 func readMinimizedState() async -> Bool? { isMinimized }
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

# Space menus use snapshots; only accepted execution paths perform live AX validation.
spaces = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowDiscoveryShared.swift")
abort 'UI hidden-state helper performs live AX' if block(info, '    var isEffectivelyHiddenForUI:').include?('axElement')
abort 'Synchronous minimize toggle remains' if info.include?('func toggleMinimize(')
abort 'Post-action category performs live AX' if block(util, '    func postActionCategory(').include?('axElement')
abort 'Drag setup performs live AX' if block(container, '    private func beginPreviewDrag(').include?('axElement')
abort 'Space picker performs live AX' if block(spaces, '    static func validateMoveSource(').include?('axElement')
abort 'Group placement bypasses live validation' unless block(util, '    private static func performWindowGroupPlacement(').include?('await WindowSpaces.validateMoveSourceConfirmed')
[container,coordinator].each do |caller|
 watcher=block(caller,'    private func scheduleVisibilityDismissConfirmation(')
 guard=watcher.index('guard !Task.isCancelled, shouldRunDeferredWatchers')
 abort 'State read can dismiss a newer preview session' unless guard && guard>watcher.index('await window.readMinimizedState()') && guard<watcher.index('if confirmed {')
end
abort 'Spring loading bypasses confirmed restoration' unless block(util, '    static func springLoadWindow(').include?('await revealWindowConfirmed')
fallback = batch[batch.index('let fullscreen = await window.readFullscreenState()')..]
abort 'Cancelled preflight can execute a stale action' unless fallback.index('guard !Task.isCancelled') < fallback.index('action.perform(on:')
script = File.read("#{ROOT}/DockDoor/Utilities/ScriptCommands.swift")
move_command = script.split('class MoveWindowCommand:', 2).last.split('@objc(', 2).first
abort 'Script duplicates asynchronous Space validation outside request ownership' if move_command.include?('await WindowSpaces.validateMoveConfirmed')
source = <<~'SWIFT'
import Foundation
typealias pid_t = Int32
typealias CGSSpaceID = UInt64
final class Gate: @unchecked Sendable {let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)}
final class AX: @unchecked Sendable {
 var full=false,reads=0;var gate:Gate?
 func isFullscreen()throws->Bool {
  precondition(!Thread.isMainThread);reads+=1
  if let gate {self.gate=nil;gate.entered.signal();gate.release.wait()}
  return full
 }
}
final class App {let processIdentifier:Int32=1;var isTerminated=false}
struct WindowInfo {
 var id=1;let app=App();var axElement=AX();var isFullscreen:Bool?=false;var isWindowlessApp=false;var spaces:Set<UInt64>=[1]
 var ownerApp:App {app}
 @MainActor func bringToFrontConfirmed() async -> Bool {WindowUtil.events.append("focus");return true}
SWIFT
source += block(info, '    func readFullscreenState(') + "\n}\n"
source += block(info, 'enum WindowFrameTransactions {') + "\n"
source += <<~'SWIFT'
struct PreviewWindowIdentity:Hashable {let id:Int;init(_ window:WindowInfo){id=window.id}}
enum Kind {case desktop,fullscreen}
struct ManagedSpaceDescriptor {let id:UInt64;var kind:Kind? = .desktop}
struct ManagedDisplayDescriptor {let identifier:String;var spaces:[ManagedSpaceDescriptor]}
struct ManagedSpaceDestination {let display:ManagedDisplayDescriptor;let space:ManagedSpaceDescriptor}
SWIFT
source += block(spaces, 'enum ManagedSpaceMoveValidationError:') + "\n"
source += <<~'SWIFT'
enum WindowSpaces {
 static let topology=[ManagedDisplayDescriptor(identifier:"display",spaces:[ManagedSpaceDescriptor(id:1),ManagedSpaceDescriptor(id:2),ManagedSpaceDescriptor(id:3)])]
 static func managedDisplays()->[ManagedDisplayDescriptor] {topology}
 static func sourceSpaceIDs(for window:WindowInfo)->Set<UInt64> {window.spaces}
SWIFT
%w[validateMoveSource validateMove validateMoveSourceConfirmed validateMoveConfirmed].each do |name|
 source += block(spaces, "    static func #{name}(") + "\n"
end
source += "}\n"
source += <<~'SWIFT'
enum Outcome {case completed,failed,cancelled}
@MainActor final class ActionFeedbackHandle {
 var outcomes:[Outcome]=[]
 func finish(_ id:PreviewWindowIdentity,_ outcome:Outcome) {outcomes.append(outcome)}
}
enum Key {case switchToDestinationSpaceAfterMoving}
enum Defaults {static subscript(_ key:Key)->Bool {false}}
@MainActor enum WindowUtil {
 struct PendingWindowRefresh {let token:UUID;let task:Task<Void,Never>}
 static var pendingManagedSpaceFollows:[String:PendingWindowRefresh]=[:]
 static var events:[String]=[]
 static var moveGate:Gate?
 static var refuseMove=false
 static var currentSpaces:Set<UInt64>=[2]
 static func revealWindowConfirmed(_ window:WindowInfo) async -> Bool {events.append("reveal");return true}
 static func moveWindowConfirmed(_ window:WindowInfo,toManagedSpace destination:UInt64,feedback:ActionFeedbackHandle?,completion:@escaping @MainActor (Bool)->Void)->Task<Void,Never>? {
  events.append("move")
  if refuseMove {Task {@MainActor in completion(false)};return nil}
  return Task {@MainActor in
   if let gate=moveGate {moveGate=nil;gate.entered.signal();while gate.release.wait(timeout:.now()) != .success {await Task.yield()}}
   guard !Task.isCancelled else {return}
   completion(true)
  }
 }
SWIFT
# The fake source membership remains the destination after its native move acknowledgement.
spaceRequest=block(util,'    static func performConfirmedSpaceMove(')
spaceRequest=spaceRequest.gsub('WindowSpaces.sourceSpaceIDs(for: movedWindow)','currentSpaces')
source += spaceRequest + "\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async throws {
  func entered(_ gate:Gate) async throws {
   for _ in 0..<2000 {if gate.entered.wait(timeout:.now()) == .success {return};try await Task.sleep(nanoseconds:1_000_000)}
   preconditionFailure("Worker never entered")
  }
  func settle(_ predicate:()->Bool) async throws {
   for _ in 0..<2000 {if predicate() {return};try await Task.sleep(nanoseconds:1_000_000)}
   preconditionFailure("Action never settled")
  }
  let topology=WindowSpaces.managedDisplays(),dest=ManagedSpaceDestination(display:WindowSpaces.topology[0],space:ManagedSpaceDescriptor(id:2))
  var window=WindowInfo()
  precondition(WindowSpaces.validateMoveSource(window,in:topology)==nil && window.axElement.reads==0)
  window.axElement.full=true
  let liveError=await WindowSpaces.validateMoveConfirmed(window,to:dest,in:topology)
  precondition(liveError == .fullscreen && window.axElement.reads==1)
  window.isWindowlessApp=true
  let windowless=await WindowSpaces.validateMoveSourceConfirmed(window,in:topology)
  precondition(windowless == .windowless && window.axElement.reads==1)
  window.isWindowlessApp=false;window.axElement.full=false;window.spaces=[1,3]
  let multiple=await WindowSpaces.validateMoveConfirmed(window,to:dest,in:topology)
  precondition(multiple == .multipleDesktopSpaces && window.axElement.reads==1)
  window.spaces=[2]
  let current=await WindowSpaces.validateMoveConfirmed(window,to:dest,in:topology)
  precondition(current == .alreadyOnDestination && window.axElement.reads==1)
  window.spaces=[1];window.axElement.gate=Gate();let slow=window.axElement.gate!
  let feedback=ActionFeedbackHandle();var replies=0
  let cancel=WindowUtil.performConfirmedSpaceMove(window,to:dest,dismissPreviews:nil,feedback:feedback){_ in replies+=1}
  try await entered(slow);precondition(WindowUtil.events.isEmpty && replies==0)
  cancel?();slow.release.signal()
  try await settle {WindowUtil.pendingManagedSpaceFollows.isEmpty}
  try await Task.sleep(nanoseconds:10_000_000)
  precondition(WindowUtil.events.isEmpty && replies==0)
  let normal=WindowInfo();let move=Gate();WindowUtil.moveGate=move
  let cancelOld=WindowUtil.performConfirmedSpaceMove(normal,to:dest,dismissPreviews:nil){_ in replies+=1}
  try await entered(move)
  let pendingToken=WindowUtil.pendingManagedSpaceFollows.values.first!.token
  let inactive=WindowUtil.performConfirmedSpaceMove(normal,to:dest,dismissPreviews:nil,isRequestActive:{false}){_ in preconditionFailure("Inactive callback")}
  precondition(inactive == nil && WindowUtil.pendingManagedSpaceFollows.values.first?.token == pendingToken)
  _ = WindowUtil.performConfirmedSpaceMove(normal,to:dest,dismissPreviews:nil,switchToDestination:true){_ in replies+=1}
  try await settle {replies==1}
  move.release.signal();try await Task.sleep(nanoseconds:10_000_000)
  precondition(replies==1 && WindowUtil.events==["move","move","reveal","focus"] && WindowUtil.pendingManagedSpaceFollows.isEmpty)
  cancelOld?();precondition(WindowUtil.pendingManagedSpaceFollows.isEmpty)
  var active=false
  _ = WindowUtil.performConfirmedSpaceMove(normal,to:dest,dismissPreviews:nil,isRequestActive:{active}){_ in preconditionFailure("Inactive callback")}
  try await settle {WindowUtil.pendingManagedSpaceFollows.isEmpty}
  precondition(WindowUtil.events.count==4)
  WindowUtil.refuseMove=true
  let refusedFeedback=ActionFeedbackHandle();var refusedReplies:[Bool]=[]
  _ = WindowUtil.performConfirmedSpaceMove(normal,to:dest,dismissPreviews:nil,feedback:refusedFeedback){refusedReplies.append($0)}
  try await settle {refusedReplies.count==1}
  try await Task.sleep(nanoseconds:10_000_000)
  precondition(refusedReplies == [false] && refusedFeedback.outcomes == [.failed] && WindowUtil.pendingManagedSpaceFollows.isEmpty)
  WindowUtil.refuseMove=false
  let cancelled=WindowInfo();cancelled.axElement.gate=Gate();let timedOut=cancelled.axElement.gate!
  var activeRequest=true
  _ = WindowUtil.performConfirmedSpaceMove(cancelled,to:dest,dismissPreviews:nil,isRequestActive:{activeRequest}){_ in preconditionFailure("Timed-out callback")}
  try await entered(timedOut);activeRequest=false;timedOut.release.signal()
  try await settle {WindowUtil.pendingManagedSpaceFollows.isEmpty}
  precondition(WindowUtil.events.count==5)
  print("PASS Space preflight: snapshot menus, background live fullscreen, invalid/current/multi-Space gates, held AX/main-actor progress, cancellation, inactive-request isolation, latest-wins callbacks, immediate native refusal, confirmed reveal/focus order and task cleanup")
 }
}
SWIFT
Dir.mktmpdir('dockfork-space-preflight-') do |dir|
 File.write("#{dir}/checks.swift",source)
 abort 'Space preflight compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library','-suppress-warnings',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Space preflight checks failed' unless system("#{dir}/checks")
end

observers = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowManipulationObservers.swift")
interaction = File.read("#{ROOT}/DockDoor/Views/Hover Window/WindowPreviewInteractionModifier.swift")
policy = block(observers, '    static func shouldDismissPreviewOnAppActivation(')
activation = block(observers, '    @objc private func appDidActivate(')
abort 'App activation must consult native drag targeting' unless activation.include?('hasExternalDragTarget: previewCoordinator.hasExternalDragTarget')
abort 'Activation bookkeeping must continue after the dismissal decision' unless activation.index('Self.ensureObserver(for: app)') > activation.index('previewCoordinator.hideWindow()')
hide = block(coordinator, '    func hideWindow(')
abort 'Explicit hide must clear native drag targeting before visibility checks' unless hide.index('externalDragTargetToken = nil') < hide.index('guard isVisible')
begin_hover = block(interaction, '    private func beginSpringLoading(')
abort 'Disabled/windowless spring loading must not acquire a drag target' unless begin_hover.index('guard Defaults[.enableSpringLoading], !windowInfo.isWindowlessApp') < begin_hover.index('beginExternalDragTarget()')
cancel_hover = block(interaction, '    private func cancelSpringLoading(')
abort 'Native leave/drop/disappearance must release its token' unless cancel_hover.include?('endExternalDragTarget(externalDragTargetToken)') && cancel_hover.include?('externalDragTargetToken = nil')
abort 'Drop must cancel hover ownership before fallback' unless interaction.index('cancelSpringLoading()', interaction.index('.onDrop')) < interaction.index('performReleaseFallback()', interaction.index('.onDrop'))
%w[isTargeted windowIdentity].each do |property|
 handler = interaction.split("            .onChange(of: #{property})", 2).last&.split(/            \.(onChange|onDisappear)/, 2)&.first
 abort "Missing cleanup on #{property}" unless handler&.include?('cancelSpringLoading()')
end
abort 'Disappearance must cancel hover ownership' unless block(interaction, '            .onDisappear').include?('cancelSpringLoading()')
source = "import Foundation\nenum PreviewHoverAction { case tap, none }\n"
source += "enum Policy {\n#{policy}\n}\n"
source += "@MainActor final class Target {\nvar isVisible = true\nprivate var externalDragTargetToken: UUID?\n"
source += coordinator.lines.find { |line| line.include?('var hasExternalDragTarget: Bool') } || abort('Missing target property')
source += block(coordinator, '    func beginExternalDragTarget(') + "\n"
source += block(coordinator, '    func endExternalDragTarget(') + "\n"
source += "func hide() {externalDragTargetToken = nil; isVisible = false}\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() {
  for keybind in [false,true] {for keep in [false,true] {for tap in [false,true] {for inside in [false,true] {for checked in [false,true] {
   let expected = !keybind && !checked && !(keep && tap && inside)
   let actual = Policy.shouldDismissPreviewOnAppActivation(isKeybindSessionActive:keybind,keepPreviewOnHoverActivation:keep,previewHoverAction:tap ? .tap : .none,mouseIsWithinPreviewWindow:inside,hasCheckedWindows:checked)
   precondition(actual == expected, "Normal activation policy changed")
   precondition(!Policy.shouldDismissPreviewOnAppActivation(isKeybindSessionActive:keybind,keepPreviewOnHoverActivation:keep,previewHoverAction:tap ? .tap : .none,mouseIsWithinPreviewWindow:inside,hasCheckedWindows:checked,hasExternalDragTarget:true))
  }}}}}
  let target = Target()
  func dismisses() -> Bool {
   Policy.shouldDismissPreviewOnAppActivation(isKeybindSessionActive:false,keepPreviewOnHoverActivation:false,previewHoverAction:.none,mouseIsWithinPreviewWindow:true,hasExternalDragTarget:target.hasExternalDragTarget)
  }
  precondition(dismisses())
  let first = target.beginExternalDragTarget()!
  precondition(!dismisses())
  let second = target.beginExternalDragTarget()!
  target.endExternalDragTarget(first); target.endExternalDragTarget(nil)
  precondition(!dismisses(), "Stale target cleared current native drag")
  target.endExternalDragTarget(second)
  precondition(dismisses(), "Native leave/drop retained activation protection")
  _ = target.beginExternalDragTarget()
  target.hide()
  precondition(!target.hasExternalDragTarget && target.beginExternalDragTarget() == nil)
  target.endExternalDragTarget(first)
  precondition(!target.hasExternalDragTarget)
  print("PASS spring-loading activation: unchanged normal policy, targeted-drag protection, stale/nil cleanup, native exit, explicit hide and hidden-panel acquisition")
 }
}
SWIFT
Dir.mktmpdir('dockfork-spring-activation-') do |dir|
 File.write("#{dir}/checks.swift",source)
 abort 'Spring activation compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Spring activation checks failed' unless system("#{dir}/checks")
end

state_coordinator = File.read("#{ROOT}/DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift")
abort 'Immediate hidden-state publication performs AX reads' if block(state_coordinator, '    func updateHiddenStateForApp(').include?('axElement')
schedule = block(state_coordinator, '    func scheduleVisibilityStateSync(')
abort 'Visibility sync timing changed' unless schedule.include?('[80_000_000, 220_000_000]')
abort 'Superseded sync can clear the newer task' unless schedule.include?("await syncVisibilityState(processIdentifier: pid)\n                guard !Task.isCancelled")
source = <<~'SWIFT'
import Foundation
let kAXHiddenAttribute = "hidden"
final class Gate: @unchecked Sendable {let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)}
final class AX: @unchecked Sendable {
 var calls:[String]=[],gate:Gate?,refuse=false
 func read(_ key:String)throws->Bool {
  precondition(!Thread.isMainThread);calls.append(key)
  if let gate {self.gate=nil;gate.entered.signal();gate.release.wait()}
  if refuse {throw NSError(domain:"AX",code:1)}
  return true
 }
 func isMinimized()throws->Bool {try read("minimized")}
 func isFullscreen()throws->Bool {try read("fullscreen")}
 func attribute(_ key:String,_ type:Bool.Type)throws->Bool {try read(key)}
}
struct App {let processIdentifier:Int32=1;var isHidden=false}
struct Snapshot:Equatable {let minimized:Bool,hidden:Bool,fullscreen:Bool?}
struct WindowInfo {
 var id:Int;var app=App();let axElement:AX
 var appAxElement:AX {axElement};var ownerApp:App {app}
 var isWindowlessApp=false,isMinimized=false,isHidden=false;var isFullscreen:Bool?=false
 var title="retained"
 var viewSnapshot:Snapshot {Snapshot(minimized:isMinimized,hidden:isHidden,fullscreen:isFullscreen)}
SWIFT
source += block(info, '    func readVisibilityState(') + "\n}\n"
source += block(info, 'enum WindowFrameTransactions {') + "\n"
source += <<~'SWIFT'
struct PreviewWindowIdentity:Hashable {let id:Int;init(_ window:WindowInfo){id=window.id}}
@MainActor enum WindowUtil {
 static var updates:[Int]=[]
 static func updateCachedWindowState(_ window:WindowInfo,isMinimized:Bool,isHidden:Bool,isFullscreen:Bool?) {updates.append(window.id)}
}
@MainActor final class Coordinator {
 var windows:[WindowInfo]=[] {didSet {publications+=1}}
 var publications=0;var pointerInteractionSessionID=UUID()
SWIFT
source += block(state_coordinator, '    private func syncVisibilityState(').sub('private func','func') + "\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async throws {
  func entered(_ gate:Gate)async throws {
   for _ in 0..<2000 {if gate.entered.wait(timeout:.now()) == .success {return};try await Task.sleep(nanoseconds:1_000_000)}
   preconditionFailure("AX worker did not start")
  }
  let c=Coordinator(),one=AX(),two=AX(),windowless=AX()
  c.windows=[WindowInfo(id:1,axElement:one),WindowInfo(id:2,axElement:two),WindowInfo(id:3,axElement:windowless,isWindowlessApp:true)]
  one.gate=Gate();let slow=one.gate!
  let task=Task {@MainActor in await c.syncVisibilityState(processIdentifier:1)}
  try await entered(slow)
  c.windows.swapAt(0,1);c.windows[1].title="new title";c.publications=0
  precondition(WindowUtil.updates.isEmpty)
  slow.release.signal();await task.value
  precondition(c.windows.map(\.id)==[2,1,3] && c.windows[1].title=="new title")
  precondition(c.windows[0].isMinimized && c.windows[1].isHidden && c.windows[1].isFullscreen==true && c.publications==1)
  precondition(one.calls==["minimized","hidden","fullscreen"] && two.calls==one.calls && windowless.calls.isEmpty)
  precondition(WindowUtil.updates==[2,1])
  c.publications=0;await c.syncVisibilityState(processIdentifier:1)
  precondition(c.publications==0, "Unchanged sample republished rows")
  WindowUtil.updates=[];one.calls=[];one.gate=Gate();let cancelled=one.gate!
  c.windows=[WindowInfo(id:1,axElement:one)]
  let old=Task {@MainActor in await c.syncVisibilityState(processIdentifier:1)}
  try await entered(cancelled);old.cancel();cancelled.release.signal();await old.value
  precondition(WindowUtil.updates.isEmpty && !c.windows[0].isMinimized && one.calls==["minimized"])
  one.gate=Gate();let replaced=one.gate!
  let session=Task {@MainActor in await c.syncVisibilityState(processIdentifier:1)}
  try await entered(replaced);c.pointerInteractionSessionID=UUID();replaced.release.signal();await session.value
  precondition(WindowUtil.updates.isEmpty && !c.windows[0].isHidden)
  one.gate=Gate();let removed=one.gate!
  let gone=Task {@MainActor in await c.syncVisibilityState(processIdentifier:1)}
  try await entered(removed);c.windows=[];removed.release.signal();await gone.value
  precondition(c.windows.isEmpty && WindowUtil.updates.isEmpty)
  one.refuse=true;c.windows=[WindowInfo(id:1,axElement:one,isMinimized:true)]
  await c.syncVisibilityState(processIdentifier:1)
  precondition(c.windows[0].isMinimized && !c.windows[0].isHidden && c.windows[0].isFullscreen==nil)
  print("PASS post-action visibility: off-main AX and unchanged three-read fast path, main-actor progress, reordered/removed rows, retained metadata, one publication, unchanged suppression, cancellation between reads, stale session and AX failure fallbacks")
 }
}
SWIFT
Dir.mktmpdir('dockfork-visibility-sync-') do |dir|
 File.write("#{dir}/checks.swift",source)
 abort 'Visibility sync compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Visibility sync checks failed' unless system("#{dir}/checks")
end

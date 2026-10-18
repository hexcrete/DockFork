#!/usr/bin/env ruby
# Runs production tiling/registry code against simulated window APIs, never live windows.
require 'tmpdir'
require 'open3'

ROOT = File.expand_path('../..', __dir__)
def block(source, signature)
  start = source.index(signature) or abort "Missing source declaration: #{signature}"
  first = source.index(/\{\n/, start)
  depth = 0
  (first...source.length).each do |index|
    depth += 1 if source[index] == '{'
    depth -= 1 if source[index] == '}'
    return source[start..index] if depth.zero?
  end
  abort "Unclosed declaration: #{signature}"
end

stubs = <<~'SWIFT'
import AppKit
import ApplicationServices

typealias CGSSpaceID = UInt64
struct Key<T> { let value: T }
enum Defaults {
 static var links = true, gestures = true, rows = 2, columns = 3, onlyFits = false, foreground = true
 static var selection = true, windowlessSelection = true
 static subscript<T>(_ key: Key<T>) -> T { key.value }
}
extension Key where T == Bool {
 static var debugMode: Self { Self(value: false) }
 static var tileOnlyWhatFits: Self { Self(value: Defaults.onlyFits) }
 static var enableWindowGestures: Self { Self(value: Defaults.gestures) }
 static var linkTiledWindowsWhenResizing: Self { Self(value: Defaults.links) }
 static var moveResizeBringToForeground: Self { Self(value: Defaults.foreground) }
 static var enableMultiWindowSelection: Self { Self(value: Defaults.selection) }
 static var enableWindowlessAppSelection: Self { Self(value: Defaults.windowlessSelection) }
}
extension Key where T == Int {
 static var maximumTilingRows: Self { Self(value: Defaults.rows) }
 static var maximumTilingColumns: Self { Self(value: Defaults.columns) }
}
struct PreviewWindowIdentity: Hashable {
 let pid: pid_t; let windowID: CGWindowID
 init(_ window: WindowInfo) { pid = window.app.processIdentifier; windowID = window.id }
}
final class App {
 static var instances: [pid_t: App] = [:]
 let processIdentifier: pid_t; var isTerminated = false, isHidden = false
 init(_ pid: pid_t) { processIdentifier = pid; Self.instances[pid] = self }
}
final class FakeAX {
 let pid: pid_t; let id: CGWindowID
 var spaces: Set<UInt64> = [1], frame: CGRect
 var minimized = false, full = false, refuses = false, focusFails = false
 var writes = 0, reads = 0, stateReads = 0
 var minimumWidth: CGFloat = 0
 var readDelay: TimeInterval = 0
 var frameReadHook: (() -> Void)?
 init(_ pid: pid_t, _ id: CGWindowID, _ frame: CGRect) { self.pid = pid; self.id = id; self.frame = frame }
 func cgWindowId() throws -> CGWindowID { id }
 func isMinimized() throws -> Bool { stateReads += 1; return minimized }
 func isFullscreen() throws -> Bool { stateReads += 1; return full }
}
typealias AXUIElement = FakeAX
func AXUIElementGetPid(_ element: FakeAX, _ pid: UnsafeMutablePointer<pid_t>) -> AXError { pid.pointee = element.pid; return .success }
struct NSScreen {
 static func screen(containing frame: CGRect) -> Self? { frame.minX >= 5000 ? nil : Self() }
 func uniqueIdentifier() -> String { "display" }
 var snappingFrame: CGRect { CGRect(x: 0, y: 0, width: 1800, height: 1200) }
}
extension CGPoint { func screen() -> NSScreen? { NSScreen() } }
enum NSEvent { static var mouseLocation = CGPoint.zero }
enum CGEventSource {
 static var pressed = true
 static func buttonState(_ state: CGEventSourceStateID, button: CGMouseButton) -> Bool { pressed }
}
struct WindowInfo {
 let id: CGWindowID; let app: App; let axElement: FakeAX
 var payload: AnyObject? = nil
 var ownerApp: App { App.instances[axElement.pid] ?? app }
 var isWindowlessApp = false
 var isMinimized: Bool { get { axElement.minimized } set { axElement.minimized = newValue } }
 var isHidden: Bool { app.isHidden }
 var isFullscreen: Bool? { axElement.full }
 var spaceID: Int? { axElement.spaces.first.map(Int.init) }
 var screenIdentifier: String? { "display" }
 func currentWindowFrame() -> CGRect? {
  axElement.frameReadHook?()
  axElement.reads += 1
  if axElement.readDelay > 0 { Thread.sleep(forTimeInterval: axElement.readDelay) }
  return axElement.frame
 }
 func applyFrame(_ frame: CGRect) -> Bool {
  axElement.writes += 1
  guard !axElement.refuses else { return false }
  axElement.frame = frame; axElement.frame.size.width = max(frame.width, axElement.minimumWidth); return true
 }
 @MainActor func setWindowFrameResult(_ frame: CGRect, on screen: NSScreen, isRequestActive: @escaping @MainActor () -> Bool) async -> WindowFramePlacementResult {
  await Task.yield()
  guard !Task.isCancelled, isRequestActive() else { return .failed }
  WindowSnapRegistry.existing?.remove(PreviewWindowIdentity(self))
  let ok = applyFrame(frame)
  Model.placements += 1
  Model.afterPlacement?(Model.placements)
  return !ok ? .failed : axElement.frame == frame ? .confirmed : .unconfirmed
 }
 @MainActor func bringToFrontConfirmed() async -> Bool { Model.focus.append(id); return !axElement.focusFails }
}
enum WindowSpaces {
 struct Space { let id: UInt64; enum Kind { case desktop }; var kind: Kind = .desktop }
 struct Destination { var space: Space }
 static func sourceSpaceIDs(for window: WindowInfo) -> Set<UInt64> { window.axElement.spaces }
 static func destination(forSpaceID: UInt64) -> Destination? { Destination(space: Space(id: forSpaceID)) }
 static func destination(forSpaceID: UInt64, in topology: [Int]) -> Destination? { destination(forSpaceID: forSpaceID) }
 static func managedDisplays() -> [Int] { [] }
 static func currentManagedSpaceID(mouseLocation: CGPoint) -> UInt64? { 1 }
 static func screen(forDisplayIdentifier: String) -> NSScreen? { NSScreen() }
 static func validateMoveSource(_ window: WindowInfo, in topology: [Int]) -> String? {
  window.isWindowlessApp || window.axElement.full || window.axElement.spaces.count != 1 ? "invalid" : nil
 }
}
extension WindowSpaces.Destination { var display: Display { Display() }; struct Display { let identifier = "display" } }
typealias ManagedSpaceDestination = WindowSpaces.Destination
enum LauncherShortcutResolver { static func application(forProcessIdentifier pid: pid_t) -> App? { App.instances[pid] } }
enum DockObserver { static func getMousePosition() -> CGPoint { CGPoint(x: 400, y: 400) } }
enum DebugLogger { static func log(_ label: String, details: String) {} }
@MainActor enum Model {
 static var placements = 0, moves = 0
 static var focus: [CGWindowID] = []
 static var afterPlacement: ((Int) -> Void)?
 static var active = true
 static func reset() { placements = 0; moves = 0; focus = []; afterPlacement = nil; active = true }
}
enum ActionFeedbackOutcome { case completed, requested, failed, cancelled }
struct ActionFeedbackHandle {
 func finish(_ identity: PreviewWindowIdentity, _ outcome: ActionFeedbackOutcome) {}
 func finishRemaining(_ outcome: ActionFeedbackOutcome) {}
}
enum WindowUtil {
 static var cachedWindows: [WindowInfo] = []
 static func readCachedWindows(for pid: pid_t) -> [WindowInfo] { cachedWindows.filter { $0.app.processIdentifier == pid } }
 static var activeSpaces: Set<Int> = [1]
 static func currentActiveSpaceIDs() -> Set<Int> { activeSpaces }
 static func windowBelongsToActiveSpace(_ window: WindowInfo, activeSpaceIDs: Set<Int>) -> Bool {
  !Set(window.axElement.spaces.map(Int.init)).isDisjoint(with: activeSpaceIDs)
 }
 static func windowInfo(for element: FakeAX, app: App, windowID: CGWindowID) -> WindowInfo? { WindowInfo(id: windowID, app: app, axElement: element) }
 @MainActor static func performConfirmedSpaceMove(_ window: WindowInfo, to destination: ManagedSpaceDestination,
    dismissPreviews: (() -> Void)?, switchToDestination: Bool,
    isRequestActive: @escaping @MainActor () -> Bool, completion: @escaping (Bool) -> Void) -> (@MainActor () -> Void)? {
  Model.moves += 1
  window.axElement.spaces = [destination.space.id]; completion(true); return {}
 }
 @MainActor static func setHiddenStateConfirmed(for app: App, isHidden: Bool) async -> Bool { app.isHidden = isHidden; return true }
 @MainActor static func setMinimizedWindowsConfirmed(_ windows: [WindowInfo], isMinimized: Bool) async -> [WindowInfo] {
  for window in windows { window.axElement.minimized = isMinimized }; return windows
 }
SWIFT

util = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowUtil.swift")
info = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowInfo.swift")
registry = File.read("#{ROOT}/DockDoor/Utilities/Window Gestures/WindowSnapRegistry.swift").gsub(/^import .*\n/, '')
source = stubs + block(util, '    struct PreviewBatchResult') + "\n" + block(util, '    @MainActor\n    static func tilePreviewWindows('.gsub('\\n', "\n")) + "\n" + block(util, '    @MainActor\n    private static func performWindowGroupPlacement('.gsub('\\n', "\n")) + "\n}\n" + registry + "\n" + block(info, 'enum PreviewTilingLayout {') + "\n" + block(info, 'enum WindowFramePlacementResult {')
drag = File.read("#{ROOT}/DockDoor/Views/Hover Window/Shared Components/DragPreviewCoordinator.swift")
abort 'A new drag must cancel the prior released drop' unless block(drag, '    func startDragging(').include?('cancelPendingDrop()')
abort 'Ghost cleanup must not cancel a released drop' if block(drag, '    func endDragging(').include?('cancelPendingDrop()')
source += "\n@MainActor final class DragPreviewCoordinator {\nprivate var dropToken: UUID?\nprivate var dropTask: Task<Void, Never>?\n"
%w[isCompletingDrop completeDrop].each { |name| source += block(drag, "    func #{name}(") + "\n" }
source += block(drag, '    private func cancelPendingDrop(') + "\n}\n"
catalog = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowActionCatalog.swift")
source += "\nenum WindowAction: CaseIterable { case autoTileSelectedWindows, fillLeftHalf, fillRightHalf, fillTopHalf, fillBottomHalf, fillTopLeftQuarter, fillTopRightQuarter, fillBottomLeftQuarter, fillBottomRightQuarter, minimize, quit, forceQuit, openNewWindow, hide, close, closeAllWindows, minimizeAllWindows, toggleFullScreen, toggleWindowSelection, selectAllWindows, maximize, center, bringToCurrentSpace, none\n"
source += catalog[catalog.index('    var isQuitAction:')...catalog.index('    var isAppWidePreviewAction:')]
%w[tilingDirection isAppWidePreviewAction].each { |name| source += block(catalog, "    var #{name}:") + "\n" }
%w[autoTilingDirection appliesToSelectedWindow batchTargets].each { |name| source += block(catalog, "    func #{name}(") + "\n" }
source += "}\n"
coordinator = File.read("#{ROOT}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
dispatch = block(coordinator, '    private func performPreviewBatchAction(')
consume = dispatch.index('windowSwitcherCoordinator.consumeWindowlessSelection(in: targets)')
abort 'Consume windowless checks at dispatch, not in a late completion' unless consume && consume < dispatch.index('previewBatchTask = Task')
action_guard = block(coordinator, '    func performCheckedWindowAction(').split('        if action == .bringToCurrentSpace').first
space_guard = block(coordinator, '    func performCheckedSpaceMove(').split('        let feedback =').first
source += "@MainActor final class ActionHarness { let windowSwitcherCoordinator: SelectionHarness; init(_ selection: SelectionHarness) { windowSwitcherCoordinator = selection }\n"
source += action_guard + "return true\n}\n" + space_guard + "return true\n}\n}\n"
selection = File.read("#{ROOT}/DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift")
replacement = block(selection, '    func addWindows(')
consume_replacement = replacement.index('consumeWindowlessSelection(in: [windows[placeholderIndex]])')
abort 'Replacing a placeholder must consume its old selection' unless consume_replacement && consume_replacement < replacement.index('windows[placeholderIndex] = newWin')
termination = block(File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowManipulationObservers.swift"), '    private func handleAppTermination(pid:')
cleanup = termination.index('coordinator.removeCheckedWindows(forProcessIdentifier: pid)')
abort 'Termination must uncheck apps before mode-specific row dismissal' unless cleanup && cleanup < termination.index('if coordinator.isKeybindSessionActive')
source += block(selection, 'struct OrderedPreviewSelection:') + "\n"
source += "struct SelectionState { var checkedWindows = OrderedPreviewSelection() }\n"
source += "@MainActor final class SelectionHarness { var selection = SelectionState(); var windows: [WindowInfo] = []; var windowSwitcherActive = true; var checkedWindowCount = 0; var visibleIndices: [Int]?\nfunc filteredWindowIndices() -> [Int] { visibleIndices ?? Array(windows.indices) }\nfunc publishCheckedSelection() { checkedWindowCount = selection.checkedWindows.identities.count }\n"
%w[canSelectWindow toggleCheckedWindow selectAllDisplayedWindows consumeWindowlessSelection removeCheckedWindows reconcileCheckedWindows checkedActionTargets].each do |name|
  source += block(selection, "    func #{name}(") + "\n"
end
source += "}\n"
source += "\nextension WindowUtil {\n" + block(util, '    static func canBringWindowToFrontWithoutSpaceSwitch(')
source += "\n@MainActor static func finishIndependentFill(_ action: WindowAction, windows: [WindowInfo]) async -> PreviewBatchResult {\nvar result = PreviewBatchResult(succeeded: windows)\n"
source += block(util, '        if action.tilingDirection != nil || action == .maximize') + "\nreturn result\n}\n}\n"

checks = <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async {
  setbuf(stdout, nil)
  precondition(WindowSnapRegistry.existing == nil)
  Defaults.links = false
  let disabledApp = App(-10)
  let initial = WindowInfo(id: 99999, app: disabledApp, axElement: FakeAX(-10, 99999, CGRect(x: 30, y: 40, width: 420, height: 320)))
  _ = await WindowUtil.tilePreviewWindows([initial], direction: .neutral)
  precondition(WindowSnapRegistry.existing == nil && initial.axElement.reads == 0)
  Defaults.links = true
  let registry = WindowSnapRegistry.shared
  var nextID: UInt32 = 0
  func windows(_ count: Int) -> [WindowInfo] {
   (0..<count).map { _ in
    nextID += 1
    let app = App(Int32(nextID))
    return WindowInfo(id: nextID, app: app, axElement: FakeAX(app.processIdentifier, nextID, CGRect(x: 30, y: 40, width: 420, height: 320)))
   }
  }
  func clear(_ windows: [WindowInfo]) { for window in windows { registry.remove(PreviewWindowIdentity(window)) } }
  let bounds = NSScreen().snappingFrame
  var cases = 0
  let start = Date()
  for rows in 1...6 { for columns in 1...6 { for count in 1...36 { for direction in PreviewTilingLayout.Direction.allCases {
   let frames = PreviewTilingLayout.frames(count: count, in: bounds, direction: direction, maximumRows: rows, maximumColumns: columns)
   precondition(frames.count == count)
   for frame in frames.compactMap({ $0 }) {
    precondition(frame.width > 0 && frame.height > 0 && frame.minX >= bounds.minX - 0.001 && frame.minY >= bounds.minY - 0.001 && frame.maxX <= bounds.maxX + 0.001 && frame.maxY <= bounds.maxY + 0.001)
   }
   let capacity = rows * columns
   if capacity > 1 {
    let cells = Array(frames.prefix(min(count, capacity)))
    for index in frames.indices { precondition(frames[index] == cells[index % cells.count]) }
    for offset in stride(from: 0, to: count, by: capacity) {
     let group = Array(frames[offset..<min(count, offset + capacity)].compactMap { $0 })
     for i in group.indices { for j in group.indices where i < j {
      let overlap = group[i].intersection(group[j]); precondition(overlap.isNull || overlap.width < 0.001 || overlap.height < 0.001)
     } }
    }
   } else { precondition(frames.allSatisfy { $0 == nil }) }
   cases += 1
  } } } }
  print("PASS geometry: \(cases) layouts, 1...36 windows, all limits/directions in \(Date().timeIntervalSince(start))s")
  for action in WindowAction.allCases {
   precondition(action.autoTilingDirection(windowCount: 1, fillActionsAutoTile: false) == (action == .autoTileSelectedWindows ? .neutral : nil))
   precondition(action.autoTilingDirection(windowCount: 1, fillActionsAutoTile: true) == (action == .autoTileSelectedWindows ? .neutral : nil))
   precondition(action.autoTilingDirection(windowCount: 4, fillActionsAutoTile: true) == action.tilingDirection)
   precondition(action.autoTilingDirection(windowCount: 4, fillActionsAutoTile: false) == (action == .autoTileSelectedWindows ? .neutral : nil))
  }
  print("PASS action routing: each Fill direction opts into group Auto Tile; explicit Auto Tile and single-window actions remain independent")
  let selectionModel = SelectionHarness()
  let selectedReal = windows(1)[0]
  let emptyApp = App(50000)
  let empty = WindowInfo(id: 0, app: emptyApp, axElement: FakeAX(50000, 0, .zero), isWindowlessApp: true)
  selectionModel.windows = [selectedReal, empty]
  WindowUtil.cachedWindows = [selectedReal]
  Defaults.selection = false
  selectionModel.selectAllDisplayedWindows()
  precondition(selectionModel.checkedWindowCount == 0)
  Defaults.selection = true; Defaults.windowlessSelection = false
  selectionModel.selectAllDisplayedWindows()
  precondition(selectionModel.checkedWindowCount == 1 && !selectionModel.canSelectWindow(empty))
  Defaults.windowlessSelection = true
  selectionModel.selectAllDisplayedWindows()
  precondition(selectionModel.checkedWindowCount == 2)
  precondition(selectionModel.checkedActionTargets()?.map(\.id) == [selectedReal.id])
  precondition(selectionModel.checkedActionTargets(includingWindowlessApps: true)?.map(\.id) == [selectedReal.id, 0])
  selectionModel.visibleIndices = [0]
  selectionModel.reconcileCheckedWindows()
  precondition(selectionModel.checkedWindowCount == 2)
  let mixedSelection = selectionModel.checkedActionTargets(includingWindowlessApps: true)!
  for action in WindowAction.allCases {
   let eligible = action.batchTargets(from: mixedSelection)
   precondition(eligible.contains { $0.isWindowlessApp } == (action.isQuitAction || action == .openNewWindow))
   let realOnly = mixedSelection.filter { action.appliesToSelectedWindow($0) }
   if action == .fillLeftHalf { precondition(action.autoTilingDirection(windowCount: realOnly.count, fillActionsAutoTile: true) == nil) }
  }
  let actionModel = ActionHarness(selectionModel)
  precondition(actionModel.performCheckedWindowAction(.fillLeftHalf, on: empty) == true)
  precondition(actionModel.performCheckedSpaceMove(selectedReal, to: WindowSpaces.destination(forSpaceID: 1)!, dismissPreviews: nil))
  precondition(actionModel.performCheckedSpaceMove(empty, to: WindowSpaces.destination(forSpaceID: 1)!, dismissPreviews: nil))
  Defaults.windowlessSelection = false; selectionModel.reconcileCheckedWindows()
  precondition(selectionModel.checkedWindowCount == 1)
  precondition(!actionModel.performCheckedSpaceMove(selectedReal, to: WindowSpaces.destination(forSpaceID: 1)!, dismissPreviews: nil))
  Defaults.windowlessSelection = true; selectionModel.windowSwitcherActive = false
  precondition(!selectionModel.canSelectWindow(empty))
  selectionModel.windowSwitcherActive = true; selectionModel.toggleCheckedWindow(empty)
  selectionModel.windows = [empty]; WindowUtil.cachedWindows = []
  selectionModel.reconcileCheckedWindows()
  precondition(selectionModel.checkedActionTargets()?.isEmpty == true && selectionModel.checkedWindowCount == 1)
  for action in WindowAction.allCases where !action.isQuitAction && action != .openNewWindow && action != .toggleWindowSelection && action != .selectAllWindows && action != .none {
   precondition(actionModel.performCheckedWindowAction(action, on: empty) == false)
  }
  precondition(actionModel.performCheckedWindowAction(.quit, on: empty) == true)
  precondition(actionModel.performCheckedWindowAction(.forceQuit, on: empty) == true)
  precondition(actionModel.performCheckedWindowAction(.openNewWindow, on: empty) == true)
  precondition(actionModel.performCheckedSpaceMove(empty, to: WindowSpaces.destination(forSpaceID: 1)!, dismissPreviews: nil))
  Model.reset()
  _ = await WindowUtil.tilePreviewWindows([empty], direction: .neutral)
  precondition(Model.moves == 0 && Model.placements == 0 && Model.focus.isEmpty)
  emptyApp.isTerminated = true; selectionModel.reconcileCheckedWindows()
  precondition(selectionModel.checkedWindowCount == 0)
  print("PASS windowless selection: option/mode gates, filtered Select All, cache reconciliation, termination, Quit/Force Quit/New-only targets, real-only tiling/counts and empty no-op")
  let terminationModel = SelectionHarness()
  let quitApp = App(60000), survivor = App(60001)
  let quitRows = [WindowInfo(id: 101, app: quitApp, axElement: FakeAX(60000, 101, .zero)), WindowInfo(id: 102, app: quitApp, axElement: FakeAX(60000, 102, .zero)), WindowInfo(id: 0, app: quitApp, axElement: FakeAX(60000, 0, .zero), isWindowlessApp: true)]
  let survivingRow = WindowInfo(id: 103, app: survivor, axElement: FakeAX(60001, 103, .zero))
  terminationModel.windows = quitRows + [survivingRow]
  terminationModel.selectAllDisplayedWindows()
  precondition(terminationModel.checkedWindowCount == 4)
  terminationModel.removeCheckedWindows(forProcessIdentifier: 99999)
  precondition(terminationModel.checkedWindowCount == 4)
  // Termination notification can precede cache eviction or the final app-state readback.
  WindowUtil.cachedWindows = quitRows + [survivingRow]
  terminationModel.windows = [survivingRow]
  terminationModel.removeCheckedWindows(forProcessIdentifier: quitApp.processIdentifier)
  precondition(terminationModel.checkedWindowCount == 1 && terminationModel.selection.checkedWindows.identities == [PreviewWindowIdentity(survivingRow)])
  terminationModel.removeCheckedWindows(forProcessIdentifier: quitApp.processIdentifier)
  precondition(terminationModel.checkedWindowCount == 1)
  terminationModel.removeCheckedWindows(forProcessIdentifier: survivor.processIdentifier)
  precondition(terminationModel.checkedWindowCount == 0)
  WindowUtil.cachedWindows = []
  print("PASS termination selection cleanup: all real/placeholder identities, stale caches, off-list rows, unrelated apps and duplicate notifications")
  let oneShot = SelectionHarness()
  oneShot.windows = quitRows + [survivingRow]
  oneShot.selectAllDisplayedWindows()
  oneShot.consumeWindowlessSelection(in: [quitRows[0], survivingRow])
  precondition(oneShot.checkedWindowCount == 4)
  oneShot.consumeWindowlessSelection(in: quitRows)
  precondition(oneShot.selection.checkedWindows.identities == [quitRows[0], quitRows[1], survivingRow].map(PreviewWindowIdentity.init))
  oneShot.consumeWindowlessSelection(in: quitRows)
  precondition(oneShot.checkedWindowCount == 3)
  oneShot.toggleCheckedWindow(quitRows[2])
  precondition(oneShot.checkedWindowCount == 4)
  oneShot.consumeWindowlessSelection(in: WindowAction.hide.batchTargets(from: oneShot.windows))
  precondition(oneShot.checkedWindowCount == 4)
  oneShot.consumeWindowlessSelection(in: WindowAction.openNewWindow.batchTargets(from: [quitRows[2], survivingRow]))
  precondition(oneShot.checkedWindowCount == 3)
  print("PASS one-shot app selection: dispatch-time placeholder removal, same-app real windows retained, repeated calls safe, explicit reselection preserved and ignored actions do not consume checks")
  let mixedSpaces = windows(3)
  mixedSpaces[1].axElement.spaces = [2]
  for active: Set<Int> in [[1], [1, 2], []] {
   Model.reset(); WindowUtil.activeSpaces = active
   let result = await WindowUtil.finishIndependentFill(.fillLeftHalf, windows: mixedSpaces)
   let eligible = mixedSpaces.reversed().filter { !Set($0.axElement.spaces.map(Int.init)).isDisjoint(with: active) }
   precondition(result.succeeded.count == 3 && result.failed.isEmpty && Model.focus == eligible.map(\.id) && Model.moves == 0)
   precondition(mixedSpaces[1].axElement.spaces == [2])
  }
  for action in [WindowAction.maximize, .center, .bringToCurrentSpace] {
   WindowUtil.activeSpaces = [1]; Model.reset()
   _ = await WindowUtil.finishIndependentFill(action, windows: mixedSpaces)
   precondition(Model.focus == [mixedSpaces[2].id, mixedSpaces[0].id])
   Defaults.foreground = false; Model.reset()
   _ = await WindowUtil.finishIndependentFill(action, windows: mixedSpaces)
   precondition(Model.focus.isEmpty)
   Defaults.foreground = true
  }
  WindowUtil.activeSpaces = [1]; Defaults.foreground = false; Model.reset()
  _ = await WindowUtil.finishIndependentFill(.fillLeftHalf, windows: mixedSpaces)
  precondition(Model.focus.isEmpty)
  Defaults.foreground = true
  _ = await WindowUtil.finishIndependentFill(.minimize, windows: mixedSpaces)
  precondition(Model.focus.isEmpty)
  print("PASS independent Fill foregrounding: off-Space windows are not activated; all displays' active Spaces, unknown topology and foreground Off are respected")
  var boundaryCases = 0
  for count in 2...36 {
   let frames = PreviewTilingLayout.frames(count: count, in: bounds, maximumRows: 6, maximumColumns: 6).map { $0! }
   for index in frames.indices {
    let ordered = [frames[index]] + frames.enumerated().filter { $0.offset != index }.map(\.element)
    let original = ordered[0]
    let candidates = [CGRect(x: original.minX + 20, y: original.minY, width: original.width - 20, height: original.height),
                      CGRect(x: original.minX, y: original.minY, width: original.width - 20, height: original.height),
                      CGRect(x: original.minX, y: original.minY + 20, width: original.width, height: original.height - 20),
                      CGRect(x: original.minX, y: original.minY, width: original.width, height: original.height - 20)]
    let interior = [original.minX > bounds.minX + 1, original.maxX < bounds.maxX - 1,
                    original.minY > bounds.minY + 1, original.maxY < bounds.maxY - 1]
    for (edge, candidate) in candidates.enumerated() {
     let changed = WindowSnapRegistry.linkedFrames(ordered, movingFirstTo: candidate)
     let actual = ordered.enumerated().map { changed[$0.offset] ?? $0.element }
     for i in actual.indices { for j in actual.indices where i < j {
      let overlap = actual[i].intersection(actual[j])
      precondition(overlap.isNull || overlap.width < 0.001 || overlap.height < 0.001)
     } }
     precondition(actual.allSatisfy { $0.width >= 100 && $0.height >= 100 })
     if interior[edge] {
      let area = actual.reduce(CGFloat.zero) { $0 + $1.width * $1.height }
      precondition(abs(area - bounds.width * bounds.height) < 0.001, "Internal resize must not leave a gap")
     }
     boundaryCases += 1
    }
   }
  }
  print("PASS connected boundaries: \(boundaryCases) edge resizes across 2...36-window grids without overlaps or interior gaps")
  for count in 1...36 {
   Model.reset(); let group = windows(count); let originals = group.map { $0.axElement.frame }
   let result = await WindowUtil.tilePreviewWindows(group, direction: .neutral)
   precondition(result.succeeded.count == count && result.failed.isEmpty)
   precondition(Model.focus == group.reversed().map(\.id))
   for (i, window) in group.enumerated() {
    let record = registry.record(for: window)!
    precondition(record.restoreFrame == originals[i])
    for j in group.indices {
     precondition((record.origin == registry.record(for: group[j])!.origin) == (i / 6 == j / 6))
    }
   }
   Model.reset(); _ = await WindowUtil.tilePreviewWindows(group, direction: .right, bringToFront: false)
   precondition(Model.focus.isEmpty)
   for (i, window) in group.enumerated() { precondition(registry.record(for: window)?.restoreFrame == originals[i]) }
   clear(group)
  }
  print("PASS integration: 36 complete tiling/retiling requests, original restore sizes, overflow isolation and foreground preference")
  for limit in [(2, 2), (1, 1)] {
   Model.reset(); Defaults.rows = limit.0; Defaults.columns = limit.1; Defaults.onlyFits = true
   let limited = windows(7), capacity = limit.0 * limit.1
   let omitted = Array(limited.dropFirst(capacity))
   let originals = omitted.map { $0.axElement.frame }
   for window in omitted { window.axElement.spaces = [2]; window.axElement.minimized = true; window.app.isHidden = true }
   let result = await WindowUtil.tilePreviewWindows(limited, direction: .neutral)
   precondition(result.succeeded.count == capacity && result.failed.isEmpty && Model.moves == 0)
   precondition(Model.focus == limited.prefix(capacity).reversed().map(\.id))
   for (index, window) in omitted.enumerated() {
    precondition(window.axElement.writes == 0 && window.axElement.reads == 0 && window.axElement.frame == originals[index])
    precondition(window.axElement.spaces == [2] && window.axElement.minimized && window.app.isHidden && registry.record(for: window) == nil)
   }
   clear(limited)
  }
  Defaults.rows = 2; Defaults.columns = 3; Defaults.onlyFits = false
  print("PASS capacity limits: overflow receives no frame reads/writes, Space moves, reveals, focus or linked records, including 1x1 move-only")
  Model.reset(); let constrained = windows(2); constrained[0].axElement.minimumWidth = 1000
  let constrainedResult = await WindowUtil.tilePreviewWindows(constrained, direction: .neutral)
  precondition(constrainedResult.failed == [PreviewWindowIdentity(constrained[0])])
  precondition(Model.focus == constrained.reversed().map(\.id), "An accepted but constrained placement must still honor foregrounding")
  precondition(registry.record(for: constrained[0]) == nil)
  clear(constrained)
  Model.reset(); constrained[0].axElement.focusFails = true
  let constrainedFocusFailure = await WindowUtil.tilePreviewWindows(constrained, direction: .neutral)
  precondition(constrainedFocusFailure.failed.filter { $0 == PreviewWindowIdentity(constrained[0]) }.count == 1)
  clear(constrained)
  Model.reset(); _ = await WindowUtil.tilePreviewWindows(constrained, direction: .neutral, bringToFront: false)
  precondition(Model.focus.isEmpty)
  clear(constrained)
  print("PASS constrained placement: foreground preference honored, no linked enrollment or false success, failures unique")
  Model.reset(); let failed = windows(4); failed[1].axElement.refuses = true
  let partial = await WindowUtil.tilePreviewWindows(failed, direction: .neutral)
  precondition(partial.succeeded.count == 3 && partial.failed.count == 1 && registry.record(for: failed[1]) == nil)
  precondition(!Model.focus.contains(failed[1].id))
  clear(failed)
  Model.reset(); let cancelled = windows(4); Model.afterPlacement = { _ in Model.active = false }
  _ = await WindowUtil.tilePreviewWindows(cancelled, direction: .neutral, isRequestActive: { Model.active })
  precondition(Model.placements == 1 && cancelled.allSatisfy { registry.record(for: $0) == nil } && Model.focus.isEmpty)
  Model.reset(); let switchedOff = windows(3); Model.afterPlacement = { _ in Defaults.links = false }
  _ = await WindowUtil.tilePreviewWindows(switchedOff, direction: .neutral)
  precondition(switchedOff.allSatisfy { registry.record(for: $0) == nil })
  Defaults.links = true
  Model.reset(); let reveal = windows(2); reveal[0].app.isHidden = true; reveal[1].axElement.minimized = true
  for window in reveal { window.axElement.spaces = [2] }
  _ = await WindowUtil.tilePreviewWindows(reveal, direction: .neutral)
  precondition(Model.moves == 2 && !reveal[0].app.isHidden && !reveal[1].isMinimized && reveal.allSatisfy { registry.record(for: $0) != nil })
  clear(reveal)
  Model.reset(); Defaults.links = false; let disabled = windows(36)
  _ = await WindowUtil.tilePreviewWindows(disabled, direction: .neutral)
  precondition(disabled.allSatisfy { $0.axElement.reads == 0 && $0.axElement.stateReads == 1 && registry.record(for: $0) == nil })
  Defaults.links = true
  Model.reset(); Defaults.rows = 1; Defaults.columns = 1; let noop = windows(2)
  _ = await WindowUtil.tilePreviewWindows(noop, direction: .neutral)
  precondition(Model.placements == 0 && noop.allSatisfy { $0.axElement.reads == 0 && registry.record(for: $0) == nil })
  Defaults.rows = 2; Defaults.columns = 3
  Model.reset(); let stale = windows(6); Model.active = false
  _ = await WindowUtil.tilePreviewWindows(stale, direction: .neutral, isRequestActive: { Model.active })
  precondition(Model.placements == 0 && stale.allSatisfy { $0.axElement.reads == 0 && registry.record(for: $0) == nil })
  Model.reset(); let taskCancelled = windows(6)
  let cancelledTask = Task { @MainActor in
   withUnsafeCurrentTask { $0?.cancel() }
   return await WindowUtil.tilePreviewWindows(taskCancelled, direction: .neutral)
  }
  _ = await cancelledTask.value
  precondition(Model.placements == 0 && taskCancelled.allSatisfy { $0.axElement.reads == 0 })
  print("PASS failures/cancellation: partial results, stale request, toggle-off mid-request, cross-Space reveal and 1x1 no-resize")
  Model.reset(); let measured = windows(6)
  // Simulated 2ms frame reads isolate synchronous bookkeeping, not real app latency.
  for window in measured { window.axElement.readDelay = 0.002 }
  let before = Date(); _ = await WindowUtil.tilePreviewWindows(measured, direction: .neutral)
  let reads = measured.reduce(0) { $0 + $1.axElement.reads }
  print("MEASURE linked bookkeeping: first tile \(reads) frame reads, \(Date().timeIntervalSince(before))s with simulated 2ms reads")
  let readCounts = measured.map { $0.axElement.reads }
  let again = Date(); _ = await WindowUtil.tilePreviewWindows(measured, direction: .neutral)
  print("MEASURE linked bookkeeping: retile \(measured.enumerated().reduce(0) { $0 + $1.element.axElement.reads - readCounts[$1.offset] }) frame reads, \(Date().timeIntervalSince(again))s with simulated 2ms reads")
  clear(measured)
  Model.reset(); let busy = windows(1), race = windows(2)
  _ = await WindowUtil.tilePreviewWindows(busy, direction: .neutral)
  _ = await WindowUtil.tilePreviewWindows(race, direction: .neutral)
  let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
  busy[0].axElement.frameReadHook = { entered.signal(); release.wait() }
  registry.windowFrameChanged(busy[0].axElement, mouseIsDown: CGEventSource.pressed)
  precondition(entered.wait(timeout: .now() + 2) == .success)
  // Queue an old generation behind the blocked worker, then replace it before it runs.
  registry.windowFrameChanged(race[0].axElement, mouseIsDown: CGEventSource.pressed)
  let origin = registry.record(for: race[1])!.origin
  registry.snapped(race[0], restoreFrame: race[0].axElement.frame, origin: origin)
  race[0].axElement.frame.size.width += 100
  registry.windowFrameChanged(race[0].axElement, mouseIsDown: CGEventSource.pressed)
  release.signal()
  for _ in 0..<200 {
   if registry.record(for: race[1])?.snappedFrame.minX == 1000 { break }
   try? await Task.sleep(nanoseconds: 5_000_000)
  }
  busy[0].axElement.frameReadHook = nil
  precondition(race[1].axElement.frame.minX == 1000, "An old notification must not suppress a replacement record's resize")
  clear(busy + race)
  print("PASS lifecycle: replacement record notifications survive queued stale generations")
  Model.reset(); let delayed = windows(2), blocker = windows(1)
  _ = await WindowUtil.tilePreviewWindows(delayed, direction: .neutral)
  _ = await WindowUtil.tilePreviewWindows(blocker, direction: .neutral)
  let blocked = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0)
  blocker[0].axElement.frameReadHook = { blocked.signal(); resume.wait() }
  registry.windowFrameChanged(blocker[0].axElement, mouseIsDown: CGEventSource.pressed)
  precondition(blocked.wait(timeout: .now() + 2) == .success)
  registry.windowFrameChanged(delayed[0].axElement, mouseIsDown: false)
  delayed[0].axElement.frame.size.width += 100
  registry.windowFrameChanged(delayed[0].axElement, mouseIsDown: CGEventSource.pressed)
  CGEventSource.pressed = false
  registry.windowFrameChanged(delayed[0].axElement, mouseIsDown: false)
  resume.signal()
  for _ in 0..<200 {
   if registry.record(for: delayed[1])?.snappedFrame.minX == 1000 { break }
   try? await Task.sleep(nanoseconds: 5_000_000)
  }
  blocker[0].axElement.frameReadHook = nil
  precondition(delayed[1].axElement.frame.minX == 1000, "Releasing the mouse after notification must not discard the final linked resize")
  clear(delayed + blocker); CGEventSource.pressed = true
  Model.reset(); let unrelated = windows(2)
  _ = await WindowUtil.tilePreviewWindows(unrelated, direction: .neutral)
  unrelated[0].axElement.frame.size.width += 100
  registry.windowFrameChanged(unrelated[0].axElement, mouseIsDown: false)
  for _ in 0..<200 {
   if registry.record(for: unrelated[0]) == nil { break }
   try? await Task.sleep(nanoseconds: 5_000_000)
  }
  precondition(registry.record(for: unrelated[0]) == nil && unrelated[1].axElement.frame.minX == 900)
  clear(unrelated)
  print("PASS quick resize: coalesced pointer changes survive release; unrelated non-pointer changes detach")
  let lifecycle = windows(3)
  _ = await WindowUtil.tilePreviewWindows(lifecycle, direction: .neutral)
  lifecycle[0].app.isHidden = true; lifecycle[1].axElement.minimized = true; lifecycle[2].axElement.full = true
  registry.reconcileCachedWindows(lifecycle)
  for _ in 0..<200 {
   if lifecycle.allSatisfy({ registry.record(for: $0) == nil }) { break }
   try? await Task.sleep(nanoseconds: 5_000_000)
  }
  precondition(lifecycle.allSatisfy { registry.record(for: $0) == nil })
  var imageWindow = windows(1)[0]
  weak var image: NSObject?
  autoreleasepool {
   let payload = NSObject(); image = payload; imageWindow.payload = payload
   registry.snapped(imageWindow, restoreFrame: imageWindow.axElement.frame)
   imageWindow.payload = nil
  }
  precondition(image == nil)
  registry.removeAll(for: imageWindow.app.processIdentifier)
  precondition(!registry.hasRecords)
  print("PASS cleanup: hidden/minimized/fullscreen metadata, no screenshot retention and termination removal")
  Model.reset(); Defaults.links = false
  let dropped = windows(4), drops = DragPreviewCoordinator(), dropToken = UUID()
  var previewVisible = true, completed = false
  Model.afterPlacement = { _ in previewVisible = false }
  drops.completeDrop(token: dropToken, operation: {
   await WindowUtil.tilePreviewWindows(dropped, direction: .neutral, bringToFront: true,
                                      isRequestActive: { drops.isCompletingDrop(token: dropToken) })
  }, completion: { result in
   precondition(result.succeeded.count == 4 && result.failed.isEmpty)
   precondition(!drops.isCompletingDrop(token: dropToken))
   completed = true
  })
  for _ in 0..<200 where !completed { try? await Task.sleep(nanoseconds: 5_000_000) }
  precondition(completed && !previewVisible && Model.focus == dropped.reversed().map(\.id))
  var resumeOld: CheckedContinuation<Void, Never>?, oldReplied = false, newReplied = false
  let oldToken = UUID(), newToken = UUID()
  drops.completeDrop(token: oldToken, operation: {
   await withCheckedContinuation { resumeOld = $0 }
   return WindowUtil.PreviewBatchResult()
  }, completion: { _ in oldReplied = true })
  for _ in 0..<200 where resumeOld == nil { try? await Task.sleep(nanoseconds: 5_000_000) }
  precondition(resumeOld != nil)
  drops.completeDrop(token: newToken, operation: { WindowUtil.PreviewBatchResult() }, completion: { _ in newReplied = true })
  resumeOld?.resume()
  for _ in 0..<200 where !newReplied { try? await Task.sleep(nanoseconds: 5_000_000) }
  precondition(newReplied && !oldReplied && !drops.isCompletingDrop(token: newToken))
  var staleStarted = false, finalReplied = false
  drops.completeDrop(token: UUID(), operation: { staleStarted = true; return WindowUtil.PreviewBatchResult() }, completion: { _ in preconditionFailure("Superseded drop replied") })
  drops.completeDrop(token: UUID(), operation: { WindowUtil.PreviewBatchResult() }, completion: { _ in finalReplied = true })
  for _ in 0..<200 where !finalReplied { try? await Task.sleep(nanoseconds: 5_000_000) }
  precondition(finalReplied && !staleStarted)
  print("PASS released drops: preview closure does not interrupt four-window foregrounding; newer requests cancel stale work and replies; completed task/token cleared")
  print("PASS all production-flow checks; OS calls are simulated, native interaction remains a separate test")
 }
}
SWIFT

Dir.mktmpdir('dockfork-linked-tiling-') do |dir|
  path = "#{dir}/Checks.swift"
  File.write(path, source + "\n" + checks)
  command = ['swiftc', '-swift-version', '5', '-parse-as-library', '-suppress-warnings', path, '-o', "#{dir}/checks"]
  abort 'Swift compilation failed' unless system(*command)
  output, errors, status = Open3.capture3("#{dir}/checks")
  puts output
  unless status.success?
    warn errors
    if (line = errors[/Checks.swift:(\d+):/, 1])
      warn "Failing check: #{(source + "\n" + checks).lines[line.to_i - 1]}"
    end
    abort 'Linked tiling checks failed'
  end
end

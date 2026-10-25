#!/usr/bin/env ruby
# Exercise production range selection/navigation with inert windows and grid coordinates.
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
state = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift")
navigation = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview Supporting/Window Image Sizing Calculations.swift")
grid = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview Supporting/CardGridScrollView.swift")
container = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreviewHoverContainer.swift")
keybinds = File.read("#{root}/DockDoor/Utilities/KeybindHelper.swift")
interaction = block(container, '    private func selectionInteraction(for window:')
abort 'Pointer sweep must replace, not retain, an old hover-scroll request' unless interaction.match?(/if !previewStateCoordinator.isPointerSelecting \{\s+cancelDockHighlightAction\(\)\s+edgeScrollRequest = nil/)
abort 'Selection scrolling must reuse the live grid offset' unless block(grid, '        private func offsetChanged(').include?('updatePointerSelectionRange()') && block(grid, '        func windowForDrop(').include?('container.contentPoint(')
abort 'Selection must not require drag-to-tile' unless grid.include?('representable.layout.appearance.enableMultiWindowSelection') && grid.include?('previewCoordinator?.selectionGrid = self')
abort 'Grid teardown must stop selection' unless block(grid, '        func detach(').include?('endSelectionRange()')
source = <<~'SWIFT'
import AppKit
typealias CGSSpaceID = UInt64
final class App { let processIdentifier: pid_t; var isTerminated = false; init(_ pid: pid_t) { processIdentifier = pid } }
struct WindowInfo { let id: CGWindowID; var app: App; var isWindowlessApp = false }
enum DockPosition { case bottom }
final class NSScreen {}
enum WindowUtil { static var cached: [WindowInfo] = []; static func readCachedWindows(for pid: pid_t) -> [WindowInfo] { cached.filter {$0.app.processIdentifier == pid} } }
enum Key { case enableMultiWindowSelection, enableWindowlessAppSelection, keepWindowSwitcherOpenWhenSelected }
enum Defaults {
 static var enabled = true, windowless = true, pin = false
 static subscript(_ key: Key) -> Bool { switch key { case .enableMultiWindowSelection: enabled; case .enableWindowlessAppSelection: windowless; case .keepWindowSwitcherOpenWhenSelected: pin } }
}
SWIFT
%w[PreviewWindowIdentity OrderedPreviewSelection PreviewSelectionKeyPress PreviewSelectionRange].each do |name|
  source += block(state, "struct #{name}") + "\n"
end
source += <<~'SWIFT'
final class Selection { var checkedWindows = OrderedPreviewSelection() }
@MainActor final class Grid {
 var windows: [WindowInfo] = [], offset = 0
 var stops = 0
 func stopSelectionScroll() { stops += 1 }
 func updateSelectionScroll(at: CGPoint) { }
 func windowForDrop(at point: CGPoint) -> WindowInfo? {
  let index = Int(point.x) + offset
  return point.x >= 0 && windows.indices.contains(index) ? windows[index] : nil
 }
}
@MainActor final class PreviewStateCoordinator {
 enum SelectionInputSource { case programmatic, keyboard, mouse }
 enum NavigationTarget { case windows }
 var activeSpaceFilterID: CGSSpaceID?
 var activeSpaceMembers: Set<PreviewWindowIdentity>?
 var onSpaceFilterChanged: (() -> Void)?
 var retainedWindowlessSelectionRows: [WindowInfo] = []
 var navigationTarget = NavigationTarget.windows
 let selection = Selection()
 var windows: [WindowInfo] = [] { didSet { filterGeneration &+= 1 } }
 var visibleIndices: [Int]? { didSet { filterGeneration &+= 1 } }
 var windowSwitcherActive = true, currIndex = 0, checkedWindowCount = 0, selectionPinned = false
 var selectionInputSource = SelectionInputSource.programmatic, shouldScrollToIndex = true
 var tapStateDidChange: (() -> Void)?, onSelectionPinned: (() -> Void)?
 var selectionGrid: Grid?
 var selectionAnchor: PreviewWindowIdentity?, selectionRange: PreviewSelectionRange?
 private var selectionRangeInput: SelectionRangeInput?
 var selectionRangeGeneration: UInt = 0, filterGeneration: UInt = 0
 var selectionAllowsWindowless = false
 var selectionPointerLocation: CGPoint?, pointerSelectionOrigin: PreviewWindowIdentity?
 var lastKnownBestGuessMonitor: NSScreen?, onFrameRefreshNeeded: (() -> Void)?
 var hasRealWindows: Bool { windows.contains { !$0.isWindowlessApp } }
 var hasSelectionRange: Bool { selectionRange != nil }
 var isPointerSelecting: Bool { pointerSelectionOrigin != nil }
 func filteredWindowIndices() -> [Int] { visibleIndices ?? Array(windows.indices) }
 func refreshSelectionLayout() { }
 func refreshFocusedWindowID(from: [WindowInfo]) { }
 func refreshDesktopNumbers() { }
 func scheduleActiveFocusedWindowRefresh() { }
 func recomputeAndPublishDimensions(dockPosition: DockPosition, bestGuessMonitor: NSScreen, isMockPreviewActive: Bool) { }
 func getCurrentWindow() -> WindowInfo? { windows.indices.contains(currIndex) ? windows[currIndex] : nil }
SWIFT
source += block(state, '    private enum SelectionRangeInput:') + "\n"
source += block(state, '    var keyboardSelectionPress:') + "\n"
%w[setSpaceFilter displayedSelectionIdentities endSelectionRange endKeyboardSelectionRange endPointerSelectionRange reconcileSelectionRange beginSelectionRange extendSelectionRange toggleSelectionCheckbox canSelectWindow toggleCheckedWindow selectAllDisplayedWindows selectWindows pinCheckedSelectionIfNeeded clearCheckedWindows publishCheckedSelection consumeWindowlessSelection removeCheckedWindows reconcileCheckedWindows updateSelectionIndex setIndex].each do |name|
  signature = state.include?("    private func #{name}(") ? "    private func #{name}(" : "    func #{name}("
  source += "@MainActor\n" + block(state, signature) + "\n"
end
source += "@MainActor\n" + block(state, '    func updatePointerSelectionRange(from') + "\n"
source += "@MainActor\n" + block(state, '    func updatePointerSelectionRange()') + "\n"
source += "@MainActor\n" + block(state, '    func setWindows(') + "\n}\n"
source += "@MainActor final class RefreshHarness {\n"
source += block(keybinds, '    private func applyRefreshedSwitcherWindows(').sub('private func ', 'func ') + "\n"
source += block(keybinds, '    private func isSameSwitcherWindow(') + "\n}\n"
source += "enum ArrowDirection { case left, right, up, down }\nenum Nav {\n"
source += block(navigation, '    static func chunkArray<T>(') + "\n"
source += block(navigation, '    static func navigateInGrid(') + "\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() {
  let app = App(1), other = App(2)
  let windows = (1...7).map { WindowInfo(id: UInt32($0), app: app) }
  WindowUtil.cached = windows
  do {
 do {
 let filtered = PreviewStateCoordinator(), monitor = NSScreen()
 var placeholder = WindowInfo(id: 0, app: other); placeholder.isWindowlessApp = true
 let original = windows + [placeholder]
 filtered.windows = original
 filtered.toggleCheckedWindow(windows[0]); filtered.toggleCheckedWindow(placeholder)
 var updates = 0
 filtered.onSpaceFilterChanged = {
  updates += 1
  let rows = filtered.activeSpaceMembers == nil ? original : [windows[1]]
  filtered.setWindows(rows, dockPosition: .bottom, bestGuessMonitor: monitor)
 }
 let members: Set<PreviewWindowIdentity> = [PreviewWindowIdentity(windows[1])]
 filtered.setSpaceFilter(2, members: members)
 precondition(filtered.checkedWindowCount == 2 && filtered.windows.count == 1, "Filtering must retain outside-view real and windowless selection")
 filtered.setSpaceFilter(2, members: members)
 precondition(updates == 1, "Unchanged membership must not rebuild rows")
 filtered.setSpaceFilter(nil)
 precondition(filtered.windows.count == original.count && filtered.checkedWindowCount == 2 && filtered.retainedWindowlessSelectionRows.isEmpty)
 filtered.setSpaceFilter(2, members: members)
 WindowUtil.cached = windows + [WindowInfo(id: 99, app: other)]
 filtered.reconcileCheckedWindows()
 precondition(filtered.checkedWindowCount == 1 && filtered.selection.checkedWindows.identities == [PreviewWindowIdentity(windows[0])], "Retained placeholder must be pruned when its app acquires a real cached window")
 WindowUtil.cached = windows
}
  let c = PreviewStateCoordinator(), grid = Grid(), refresh = RefreshHarness(), monitor = NSScreen()
   c.windows = windows; grid.windows = windows; c.selectionGrid = grid
   for keyboard in [false, true] {
    c.clearCheckedWindows()
    if keyboard {
     c.toggleCheckedWindow(windows[0], keyboardPress: PreviewSelectionKeyPress(keyCode: 14, timestamp: 100))
     c.setIndex(to: 2, source: .keyboard, extendingSelection: true)
    } else { c.updatePointerSelectionRange(from: windows[0], at: CGPoint(x: 2,y: 0)) }
    for _ in 0..<3 {
     refresh.applyRefreshedSwitcherWindows(windows, coordinator: c, dockPosition: .bottom, bestGuessMonitor: monitor)
     precondition(c.hasSelectionRange, "Background refresh must not cancel an unchanged active range")
    }
    if keyboard { c.setIndex(to: 4, source: .keyboard, extendingSelection: true) }
    else { c.updatePointerSelectionRange(from: windows[0], at: CGPoint(x: 4,y: 0)) }
    precondition(c.selection.checkedWindows.identities.map(\.windowID) == [1,2,3,4,5], "Selection must continue after refresh")
    let source = c.selectionInputSource
    refresh.applyRefreshedSwitcherWindows(Array(windows.reversed()), coordinator: c, dockPosition: .bottom, bestGuessMonitor: monitor)
    precondition(!c.hasSelectionRange && c.getCurrentWindow()?.id == 5 && c.selectionInputSource == source, "Reorder must end the range but preserve highlight identity and input source")
    c.endPointerSelectionRange(); c.windows = windows
   }
  }
  let c = PreviewStateCoordinator(), grid = Grid()
  c.windows = windows; grid.windows = windows; c.selectionGrid = grid
  func ids() -> [CGWindowID] { c.selection.checkedWindows.identities.map(\.windowID) }
  c.toggleCheckedWindow(windows[1]); c.toggleCheckedWindow(windows[4])
  c.toggleSelectionCheckbox(windows[2], extending: true)
  precondition(ids() == [2,5,3,4])
  c.toggleSelectionCheckbox(windows[0], extending: true)
  precondition(ids() == [2,5,3,4,1], "Shift-click must preserve anchor and existing order")
  c.clearCheckedWindows()
  let press = PreviewSelectionKeyPress(keyCode: 14, timestamp: 100)
  c.toggleCheckedWindow(windows[1], keyboardPress: press)
  c.setIndex(to: 4, source: .keyboard, extendingSelection: true)
  precondition(ids() == [2,3,4,5] && c.keyboardSelectionPress == press)
  c.setIndex(to: 2, source: .keyboard, extendingSelection: true)
  precondition(ids() == [2,3])
  c.endKeyboardSelectionRange(keyCode: 15, releasedBefore: 200)
  c.endKeyboardSelectionRange(keyCode: 14, releasedBefore: 99)
  precondition(c.hasSelectionRange)
  c.endKeyboardSelectionRange(keyCode: 14, releasedBefore: 100)
  precondition(!c.hasSelectionRange && ids() == [2,3])
  c.selectAllDisplayedWindows()
  c.toggleCheckedWindow(windows[1], keyboardPress: press)
  c.setIndex(to: 4, source: .keyboard, extendingSelection: true)
  precondition(ids() == [1,6,7])
  c.setIndex(to: 2, source: .keyboard, extendingSelection: true)
  precondition(ids() == [1,4,5,6,7], "Reversal must restore previous selection order")
  c.setIndex(to: 3, source: .mouse)
  precondition(!c.hasSelectionRange)
  c.clearCheckedWindows()
  var publications = 0; c.tapStateDidChange = { publications += 1 }
  c.updatePointerSelectionRange(from: windows[0], at: CGPoint(x: 2,y: 0))
  precondition(ids() == [1,2,3] && c.isPointerSelecting)
  let previous = publications
  for _ in 0..<50 { c.updatePointerSelectionRange(from: windows[0], at: CGPoint(x: 2,y: 0)) }
  precondition(publications == previous, "Stationary endpoints must not republish selection")
  c.updatePointerSelectionRange(from: windows[0], at: CGPoint(x: -1,y: 0))
  precondition(ids() == [1,2,3], "Gaps must retain endpoint")
  grid.offset = 2; c.updatePointerSelectionRange()
  precondition(ids() == [1,2,3], "Pointer in gap must remain inert during scrolling")
  c.updatePointerSelectionRange(from: windows[0], at: CGPoint(x: 2,y: 0))
  precondition(ids() == [1,2,3,4,5], "Live offset must extend under a stationary pointer")
  c.updatePointerSelectionRange(from: windows[0], at: .zero)
  precondition(ids() == [1,2,3])
  c.visibleIndices = [0,2,4]; c.reconcileSelectionRange()
  precondition(!c.hasSelectionRange && c.isPointerSelecting)
  c.updatePointerSelectionRange(from: windows[0], at: .zero)
  precondition(!c.hasSelectionRange, "Cancelled sweep must not restart before release")
  c.endPointerSelectionRange()
  precondition(!c.isPointerSelecting)
  c.clearCheckedWindows(); c.visibleIndices = [0,2,4]; grid.offset = 0
  c.toggleCheckedWindow(windows[0], keyboardPress: press)
  c.setIndex(to: 4, source: .keyboard, extendingSelection: true)
  precondition(ids() == [1,3,5])
  c.windows = windows; c.reconcileSelectionRange()
  precondition(c.hasSelectionRange, "Metadata-only refresh must retain range")
  c.windows = Array(windows.reversed()); c.reconcileSelectionRange()
  precondition(!c.hasSelectionRange)
  c.clearCheckedWindows(); c.visibleIndices = nil
  let placeholder = WindowInfo(id: 0,app:other,isWindowlessApp:true)
  c.windows = [windows[0],placeholder,windows[1]]
  Defaults.windowless = false
  c.toggleCheckedWindow(windows[0],keyboardPress:press); c.setIndex(to:2,source:.keyboard,extendingSelection:true)
  precondition(ids() == [1,2])
  c.clearCheckedWindows(); Defaults.windowless = true
  c.toggleCheckedWindow(windows[0],keyboardPress:press); c.setIndex(to:2,source:.keyboard,extendingSelection:true)
  precondition(ids() == [1,0,2])
  c.clearCheckedWindows(); Defaults.enabled = false
  c.toggleCheckedWindow(windows[0],keyboardPress:press)
  precondition(!c.hasSelectionRange && ids().isEmpty)
  Defaults.enabled = true
  c.windows = [windows[0],windows[1],WindowInfo(id:8,app:other)]
  c.visibleIndices = [0,1]
  c.toggleCheckedWindow(c.windows[2]);c.toggleCheckedWindow(windows[0],keyboardPress:press)
  c.removeCheckedWindows(forProcessIdentifier:2)
  precondition(!c.hasSelectionRange && ids() == [1], "Termination must not resurrect a filtered-out base selection")
  c.toggleCheckedWindow(windows[1],keyboardPress:press)
  WindowUtil.cached = [windows[1]];c.reconcileCheckedWindows()
  precondition(!c.hasSelectionRange && ids() == [2], "External pruning must invalidate a range snapshot")
  for horizontal in [false,true] { for reverse in [false,true] { for count in 1...20 {
   let chunks = Nav.chunkArray(items:Array(0..<count),isHorizontal:horizontal,maxColumns:3,maxRows:3,reverse:reverse)
   for (lineIndex,line) in chunks.enumerated() { for (position,index) in line.enumerated() { for direction in [ArrowDirection.left,.right,.up,.down] {
    let bounded = Nav.navigateInGrid(from:index,direction:direction,totalItems:count,isHorizontal:horizontal,maxColumns:3,maxRows:3,reverse:reverse,wraps:false)
    let legacy = Nav.navigateInGrid(from:index,direction:direction,totalItems:count,isHorizontal:horizontal,maxColumns:3,maxRows:3,reverse:reverse)
    let backward = horizontal ? direction == .left : direction == .up
    let forward = horizontal ? direction == .right : direction == .down
    let before = horizontal ? direction == .up : direction == .left
    let after = horizontal ? direction == .down : direction == .right
    let edge = (backward && lineIndex == 0 && position == 0) || (forward && lineIndex == chunks.count-1 && position == line.count-1) || (before && lineIndex == 0) || (after && lineIndex == chunks.count-1)
    precondition(bounded == (edge ? index : legacy))
   } } }
  } } }
  print("PASS production Shift additive ranges, keyboard/pointer select/deselect reversal, original ordering, filters, windowless eligibility, stable IDs, stale release, cancellation, metadata refresh, gaps/scroll offsets and no repeated endpoint publications")
  print("PASS production bounded grid navigation in both flows, reversed Dock order and 1-20 items; default navigation retains wrap")
 }
}
SWIFT
Dir.mktmpdir('dockfork-selection-ranges-') do |dir|
  File.write("#{dir}/checks.swift",source)
  abort 'Range selection compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
  abort 'Range selection checks failed' unless system("#{dir}/checks")
end

keyboard = "import AppKit\n"
keyboard += block(keybinds, 'private final class PreviewActionKeyPressState {') + "\n"
keyboard += block(state, 'struct PreviewSelectionKeyPress:') + "\n"
keyboard += <<~'SWIFT'
enum WindowAction { case toggleWindowSelection, other }
enum ArrowDirection { case right }
@MainActor final class SelectionCoordinator {
 enum NavigationTarget { case windows }
 var navigationTarget = NavigationTarget.windows
 var keyboardSelectionPress: PreviewSelectionKeyPress?, window: Int? = 1
 var toggles = 0
 func getCurrentWindow() -> Int? { window }
 func toggleCheckedWindow(_ window: Int, keyboardPress: PreviewSelectionKeyPress?) {
  toggles += 1; keyboardSelectionPress = keyboardPress
 }
 func endSelectionRange() { keyboardSelectionPress = nil }
 func endKeyboardSelectionRange() { endSelectionRange() }
}
@MainActor final class PreviewCoordinator {
 struct Snapshot { var isSearchFocused = false }
 let windowSwitcherCoordinator = SelectionCoordinator()
 var tapSnapshot = Snapshot(), arrowExtensions: [Bool] = [], forwarded = 0
 func performActionOnCurrentWindow(action: WindowAction, preservePreviews: Bool) -> Bool { forwarded += 1; return false }
 func navigateWithArrowKey(direction: ArrowDirection, extendingSelection: Bool) { arrowExtensions.append(extendingSelection) }
}
@MainActor private final class KeyboardHarness {
 let previewCoordinator = PreviewCoordinator(), actionKeyPressState = PreviewActionKeyPressState()
SWIFT
%w[performPreviewShortcut navigatePreviewSelectionArrow].each do |name|
 keyboard += block(keybinds, "    private func #{name}(").sub('private func ', 'func ') + "\n"
end
keyboard += <<~'SWIFT'
}
@main struct KeyboardChecks {
 @MainActor static func main() {
  for focused in [false, true] {
   let h = KeyboardHarness(), code: Int64 = 14, timestamp: UInt64 = 100
   let c = h.previewCoordinator.windowSwitcherCoordinator
   h.previewCoordinator.tapSnapshot.isSearchFocused = focused
   precondition(h.actionKeyPressState.begin(keyCode: code, isRepeat: false, timestamp: timestamp))
   _ = h.performPreviewShortcut(.toggleWindowSelection, keyCode: code, timestamp: timestamp)
   precondition(c.toggles == 1 && c.keyboardSelectionPress == PreviewSelectionKeyPress(keyCode: code, timestamp: timestamp))
   h.navigatePreviewSelectionArrow(.right)
   precondition(h.previewCoordinator.arrowExtensions == [true])
   precondition(h.previewCoordinator.tapSnapshot.isSearchFocused == focused, "Selection must not change text focus")
   h.actionKeyPressState.release(keyCode: code)
   h.navigatePreviewSelectionArrow(.right)
   precondition(c.keyboardSelectionPress == nil && h.previewCoordinator.arrowExtensions == [true,false])
   _ = h.performPreviewShortcut(.toggleWindowSelection, keyCode: code, timestamp: timestamp)
   precondition(c.toggles == 2 && c.keyboardSelectionPress == nil, "Released keys must not arm extension")
   precondition(h.actionKeyPressState.begin(keyCode: code, isRepeat: false, timestamp: timestamp + 1))
   _ = h.performPreviewShortcut(.toggleWindowSelection, keyCode: code, timestamp: timestamp)
   precondition(c.keyboardSelectionPress == nil, "Stale dispatch must not arm extension")
   _ = h.performPreviewShortcut(.other, keyCode: code, timestamp: timestamp + 1)
   precondition(h.previewCoordinator.forwarded == 1 && c.keyboardSelectionPress == nil)
  }
  print("PASS production keyboard selection dispatch: held ranges with/without search focus, unchanged text focus, release, stale presses and ordinary action forwarding")
 }
}
SWIFT
Dir.mktmpdir('dockfork-selection-keyboard-') do |dir|
 File.write("#{dir}/checks.swift",keyboard)
 abort 'Keyboard range compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Keyboard range checks failed' unless system("#{dir}/checks")
end

checkbox_source = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview.swift")
native = <<~'SWIFT'
import AppKit
import SwiftUI
struct BackgroundAppearance {}
enum MaterialPillStyle { static let horizontalPadding: CGFloat = 4, verticalPadding: CGFloat = 4 }
extension View {
 func materialPill(backgroundAppearance: BackgroundAppearance) -> some View { self }
 func previewControlVisibilityAnimation(isVisible: Bool, duration: Double, animationsEnabled: Bool) -> some View { self }
}
SWIFT
native += block(checkbox_source,'struct PreviewSelectionInteraction {') + "\n"
native += block(checkbox_source,'struct PreviewSelectionCheckbox:') + "\n"
native += <<~'SWIFT'
@MainActor final class Counts: ObservableObject {
 @Published var checked = false
 var active = false, toggles = 0, starts = 0, ends = 0, bodyDrags = 0, rowActivations = 0
 func end() { if active { active = false; ends += 1 } }
}
struct Row: View {
 @ObservedObject var counts: Counts
 var body: some View {
  HStack {
   Color.blue.frame(width:32,height:32).allowsHitTesting(false)
    .overlay {
     PreviewSelectionCheckbox(isChecked:counts.checked,isVisible:true,color:.blue,
      interaction:PreviewSelectionInteraction(isDragOrigin:counts.active,
       toggle:{counts.toggles += 1;counts.checked.toggle()},
       drag:AnyGesture(DragGesture(minimumDistance:3,coordinateSpace:.global)
        .onChanged { _ in if !counts.active {counts.active = true;counts.starts += 1;counts.checked.toggle()} }
        .onEnded { _ in counts.end() }),end:{counts.end()}),toggle:{preconditionFailure("Fallback click bypassed interaction")})
    }
   Text("Window title").allowsHitTesting(false)
   Spacer()
  }.frame(width:400,height:80)
   .background {
    Color.clear.contentShape(Rectangle())
     .gesture(DragGesture(minimumDistance:3).onEnded {_ in counts.bodyDrags += 1})
     .padding(.horizontal,-8)
   }
   .background(.regularMaterial)
   .padding(.horizontal,8)
   .onTapGesture {counts.rowActivations += 1}
 }
}
@main struct NativeChecks {
 @MainActor static func pump(_ time: Double) { RunLoop.current.run(until:Date().addingTimeInterval(time)) }
 @MainActor static func main() {
  let app = NSApplication.shared;app.setActivationPolicy(.prohibited);app.finishLaunching()
  guard NSScreen.screens.first != nil else {print("SKIP native checkbox range test: no display");return}
  let counts = Counts()
  let window = NSPanel(contentRect:CGRect(x:100,y:100,width:416,height:80),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  window.isReleasedWhenClosed = false;defer {window.close()}
  window.contentView = NSHostingView(rootView:Row(counts:counts));window.orderFrontRegardless();window.contentView?.layoutSubtreeIfNeeded();pump(0.15)
  func send(_ points: [CGPoint]) {
   let time = ProcessInfo.processInfo.systemUptime
   for (index,point) in points.enumerated() {
    let type:NSEvent.EventType = index == 0 ? .leftMouseDown : (index == points.count-1 ? .leftMouseUp : .leftMouseDragged)
    app.postEvent(NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:time+Double(index)*0.05,windowNumber:window.windowNumber,context:nil,eventNumber:index,clickCount:1,pressure:type == .leftMouseUp ? 0 : 1)!,atStart:false)
   }
   while let event = app.nextEvent(matching:.any,until:Date().addingTimeInterval(0.05),inMode:.default,dequeue:true) {app.sendEvent(event)}
   pump(0.1)
  }
  let start = CGPoint(x:24,y:40), away = CGPoint(x:250,y:40)
  send([start,start]);precondition(counts.toggles == 1 && counts.checked && counts.starts == 0)
  send([start,away,away]);precondition(counts.toggles == 1 && !counts.checked && counts.starts == 1 && counts.ends == 1 && counts.bodyDrags == 0)
  send([start,away,start,start]);precondition(counts.toggles == 1 && counts.checked && counts.starts == 2 && counts.ends == 2 && counts.bodyDrags == 0)
  send([away,CGPoint(x:300,y:40),CGPoint(x:300,y:40)]);precondition(counts.bodyDrags == 1 && counts.starts == 2)
  send([start,CGPoint(x:25,y:40),CGPoint(x:25,y:40)]);precondition(counts.toggles == 2 && !counts.checked && counts.starts == 2)
  precondition(counts.rowActivations == 0, "Checkbox clicks/drags must not activate the preview")
  print("PASS production native checkbox: normal/subthreshold clicks, drag-return/release without double toggle, single settlement and body-drag separation; own nonactivating panel only")
 }
}
SWIFT
Dir.mktmpdir('dockfork-selection-checkbox-') do |dir|
 File.write("#{dir}/checks.swift",native)
 abort 'Native checkbox compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Native checkbox checks failed' unless system("#{dir}/checks")
end

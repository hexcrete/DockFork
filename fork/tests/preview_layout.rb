#!/usr/bin/env ruby
# Compile production row updates and frame scheduling against inert presentation state.
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
panel = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
view = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreviewHoverContainer.swift")
header_visibility = block(view, '    private var effectiveShouldShowHeader: Bool')
abort 'Header must use mode-resolved full-size placeholder preference' unless header_visibility.include?('resolvedAppearance.showFullSizeWindowlessPreviews')
appearance = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview.swift")
compact = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreviewCompact.swift")
abort 'Whole-card gestures can start drags from controls' if view.include?('.gesture(previewDragGesture(for:')
abort 'Both card layouts must receive only real, non-mock drag gestures' unless view.scan('previewBodyDrag: mockPreviewActive || windowInfo.isWindowlessApp ? nil : previewDragGesture(for: windowInfo)').size == 2
drag = block(view, '    private func previewDragGesture(')
abort 'Body dragging must retain the shared threshold and lifecycle' unless drag.include?('DragGesture(minimumDistance: 3, coordinateSpace: .global)') && drag.include?('updatePreviewDrag(') && drag.include?('finishPreviewDrag(')
abort 'Regular card dragging must stay on the image/body' unless block(appearance, '    private func windowContent(').include?('.gesture(skeletonMode ? nil : previewBodyDrag)')
abort 'Regular control overlays must not inherit a card drag' if block(appearance, '    private var previewCoreContent: some View').include?('.gesture(')
compact_row = block(compact, '    private func compactRow(')
compact_body = block(compact, '    var body: some View')
compact_background = block(compact_body, '            .background {')
abort 'Compact drag surface must precede decorative chrome' unless compact_body.index(compact_background) < compact_body.index('.previewCardChrome(')
abort 'Compact drag surface must share chrome edge expansion' unless compact_background.include?('.padding(.horizontal, -CardRadius.innerPadding)')
abort 'Compact drag must be a single background gesture' unless compact_body.scan('.gesture(').size == 1 && compact_background.include?('.gesture(previewBodyDrag)') && compact_background.include?('.contentShape(Rectangle())')
abort 'Compact content/controls must not inherit body dragging' if compact_row.include?('.gesture(')
abort 'Compact passive content must pass hits through without disabling icon overlays' unless compact_row.scan('.allowsHitTesting(false)').size == 3 && compact_row.match?(/\.allowsHitTesting\(false\)\s+\.overlay/)
puts 'PASS production drag wiring: full compact background/padding, passive-content hit passthrough, controls outside gesture ancestry, real-window gating and shared drag lifecycle'
abort 'Dock/Cmd+Tab placeholder preferences must remain independent' unless appearance.include?('pick(.showFullSizeWindowlessDockPreviews, cmdTab: .showFullSizeWindowlessCmdTabPreviews)')
%w[default popover].each do |style|
  abort "#{style} header reservation ignores visibility" unless view.include?("effectiveShouldShowHeader && effectiveAppNameStyle == .#{style}")
end
abort 'Header and summary must share opacity transitions' unless block(view, '    private func hoverTitleBaseView(').include?('.transition(.opacity)') && view.include?('selectionSummary.transition(.opacity)')
abort 'Frame refresh must ignore hidden panels' unless block(panel, '    private func refreshPanelFrameToFitContent(').include?('guard isVisible, let hostingView = contentView')
abort 'Frame refresh callback bypasses scheduling' unless block(panel, '    private func setupFrameRefreshObserver(').include?('schedulePanelFrameRefresh()')

source = <<~'SWIFT'
import Foundation
struct App { var processIdentifier = 1 }
struct WindowInfo { let id: Int; var isWindowlessApp = false; var app = App() }
struct NSScreen {}
enum DockPosition { case bottom, cmdTab }
enum Input { case programmatic, keyboard }
@MainActor final class State {
 var windows: [WindowInfo] = []
 var currIndex = -1
 var selectionInputSource = Input.keyboard
 var lastKnownBestGuessMonitor: NSScreen?
 var refreshes = 0
 var height = 0
 var onFrameRefreshNeeded: (() -> Void)?
 func reconcileCheckedWindows() {}
 func refreshFocusedWindowID(from: [WindowInfo]? = nil) {}
 func refreshDesktopNumbers() {}
 func scheduleActiveFocusedWindowRefresh() {}
 func updateSelectionIndex(_ index: Int, source: Input) { currIndex = index; selectionInputSource = source }
 func recomputeAndPublishDimensions(dockPosition: DockPosition, bestGuessMonitor: NSScreen, isMockPreviewActive: Bool = false) {
   height = hasRealWindows ? 300 : 40
 }
SWIFT
source += block(state, '    var hasRealWindows: Bool') + "\n"
source += block(state, '    func setWindows(') + "\n"
source += block(state, '    func mergeWindows(') + "\n"
source += block(state, '    private func mergeIdentity(') + "\n}\n"
source += <<~'SWIFT'
struct HeaderState { var windowSwitcherActive: Bool; var hasRealWindows: Bool }
struct Appearance { var showFullSizeWindowlessPreviews: Bool }
struct Header {
 let previewStateCoordinator: HeaderState
 let effectiveShowAppName: Bool
 let usesCompactRows: Bool
 let resolvedAppearance: Appearance
 var visible: Bool { effectiveShouldShowHeader }
SWIFT
source += header_visibility + "\n}\n"
source += <<~'SWIFT'
@MainActor final class Panel {
 var frameRefreshScheduled = false
 var isVisible = true
 var measurements = 0
 var measuredHeight = 0
 let state: State
 init(_ state: State) { self.state = state }
 func refreshPanelFrameToFitContent() {
   guard isVisible else { return }
   measurements += 1
   measuredHeight = state.height
 }
 func schedule() { schedulePanelFrameRefresh() }
SWIFT
source += block(panel, '    private func schedulePanelFrameRefresh(') + "\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async throws {
   for switcher in [false, true] {
     for real in [false, true] {
       for enabled in [false, true] {
         for compact in [false, true] {
           for fullSize in [false, true] {
             let header = Header(previewStateCoordinator: HeaderState(windowSwitcherActive: switcher, hasRealWindows: real),
                                 effectiveShowAppName: enabled, usesCompactRows: compact,
                                 resolvedAppearance: Appearance(showFullSizeWindowlessPreviews: fullSize))
             precondition(header.visible == (!switcher && enabled && (real || (!compact && fullSize))))
           }
         }
       }
     }
   }
   let state = State(), screen = NSScreen()
   let placeholder = WindowInfo(id: 0, isWindowlessApp: true)
   let real = WindowInfo(id: 1)
   let initial = State()
   initial.onFrameRefreshNeeded = { preconditionFailure("Initial presentation requested a redundant resize") }
   initial.setWindows([real], dockPosition: .bottom, bestGuessMonitor: screen)
   initial.setWindows([], dockPosition: .bottom, bestGuessMonitor: screen)
   state.setWindows([placeholder], dockPosition: .bottom, bestGuessMonitor: screen)
   let panel = Panel(state)
   state.onFrameRefreshNeeded = { state.refreshes += 1; panel.schedule() }
   state.mergeWindows([real], dockPosition: .bottom, bestGuessMonitor: screen)
   precondition(state.refreshes == 1 && panel.measurements == 0)
   panel.schedule(); panel.schedule()
   try await Task.sleep(nanoseconds: 30_000_000)
   precondition(panel.measurements == 1 && panel.measuredHeight == 300)
   state.currIndex = 0
   state.mergeWindows([real], dockPosition: .bottom, bestGuessMonitor: screen)
   precondition(state.refreshes == 1 && state.currIndex == 0 && state.selectionInputSource == .keyboard)
   state.mergeWindows([placeholder], dockPosition: .bottom, bestGuessMonitor: screen)
   try await Task.sleep(nanoseconds: 30_000_000)
   precondition(state.refreshes == 2 && panel.measuredHeight == 40)
   state.setWindows([real], dockPosition: .cmdTab, bestGuessMonitor: screen)
   try await Task.sleep(nanoseconds: 30_000_000)
   precondition(state.refreshes == 3 && panel.measuredHeight == 300)
   state.mergeWindows([real, WindowInfo(id: 2)], dockPosition: .cmdTab, bestGuessMonitor: screen)
   precondition(state.refreshes == 4)
   panel.isVisible = false
   try await Task.sleep(nanoseconds: 30_000_000)
   precondition(panel.measurements == 3 && !panel.frameRefreshScheduled)
   panel.isVisible = true; panel.schedule()
   try await Task.sleep(nanoseconds: 30_000_000)
   precondition(panel.measurements == 4)
   state.onFrameRefreshNeeded = nil
   print("PASS placeholder/real same-count transitions, both directions, direct replacement, unchanged rows, selection identity, count changes, coalesced deferred sizing and hidden/reopened panel cleanup; 32 production header visibility cases, independent mode settings and shared reservations/transitions")
 }
}
SWIFT
Dir.mktmpdir('dockfork-preview-layout-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Preview layout fixture compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Preview layout checks failed' unless system("#{dir}/checks")
end

native_source = <<~'SWIFT'
import AppKit
import SwiftUI
enum CardRadius { static let innerPadding = 6.0 }
@MainActor final class Counts { var changes = 0; var ends = 0; var clicks = 0; var activations = 0 }
struct Row: View {
 let counts: Counts
 var previewBodyDrag: AnyGesture<DragGesture.Value>? {
  AnyGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
   .onChanged { _ in counts.changes += 1 }.onEnded { _ in counts.ends += 1 })
 }
 var body: some View {
  HStack(spacing: 10) {
   Color.blue.frame(width: 32, height: 32).allowsHitTesting(false)
    .overlay {
     Button { counts.clicks += 1 } label: { Color.white.frame(width: 24, height: 24) }.buttonStyle(.plain)
    }
    .onContinuousHover { _ in }
   Text("Window title").allowsHitTesting(false)
   Spacer()
   Button { counts.clicks += 1 } label: { Color.red.frame(width: 32, height: 32) }.buttonStyle(.plain)
  }
  .padding(.vertical, 8)
  .frame(width: 400, height: 80, alignment: .leading)
SWIFT
native_source += compact_background + "\n"
native_source += <<~'SWIFT'
  .background {
   RoundedRectangle(cornerRadius: 8).fill(.regularMaterial).padding(.horizontal, -CardRadius.innerPadding)
  }
  .padding(.horizontal, CardRadius.innerPadding)
  .contentShape(Rectangle())
  .onContinuousHover { _ in }
  .onTapGesture { counts.activations += 1 }
 }
}
@main struct Checks {
 @MainActor static func pump(_ duration: Double) { RunLoop.current.run(until: Date().addingTimeInterval(duration)) }
 @MainActor static func main() {
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  app.finishLaunching()
  guard NSScreen.screens.first != nil else { print("SKIP native compact dragging: no WindowServer display access"); return }
  let counts = Counts()
  let window = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 400 + 2 * CardRadius.innerPadding, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  window.contentView = NSHostingView(rootView: Row(counts: counts))
  window.orderFrontRegardless()
  window.contentView?.layoutSubtreeIfNeeded()
  pump(0.2)
  func send(from: CGPoint, to: CGPoint) {
   let timestamp = ProcessInfo.processInfo.systemUptime
   let dragged = from != to
   let events: [(NSEvent.EventType, CGPoint)] = dragged
    ? [(.leftMouseDown, from), (.leftMouseDragged, to), (.leftMouseUp, to)]
    : [(.leftMouseDown, from), (.leftMouseUp, to)]
   for (index, entry) in events.enumerated() {
    app.postEvent(NSEvent.mouseEvent(with: entry.0, location: entry.1, modifierFlags: [], timestamp: timestamp + Double(index) * 0.05, windowNumber: window.windowNumber, context: nil, eventNumber: index + 1, clickCount: 1, pressure: entry.0 == .leftMouseUp ? 0 : 1)!, atStart: false)
   }
   while let event = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.05), inMode: .default, dequeue: true) { app.sendEvent(event) }
   pump(0.1)
  }
  for (label, x, y, shouldDrag) in [("title", 100.0, 40.0, true), ("empty body", 250, 40, true), ("top padding", 180, 76, true), ("bottom padding", 180, 4, true), ("left padding", 3, 40, true), ("right padding", 400 + 2 * CardRadius.innerPadding - 3, 40, true), ("control", 390, 40, false), ("checkbox", 24, 40, false)] {
   let before = counts.ends
   send(from: CGPoint(x: x, y: y), to: CGPoint(x: 270, y: 40))
   precondition((counts.ends > before) == shouldDrag, label)
   precondition(counts.clicks == 0, "Dragging must not click a control")
  }
  let before = counts.ends
  send(from: CGPoint(x: 270, y: 40), to: CGPoint(x: 390, y: 40))
  precondition(counts.ends == before + 1 && counts.clicks == 0, "Body drag crossing a control lost its origin")
  for x in [24.0, 390.0] { send(from: CGPoint(x: x, y: 40), to: CGPoint(x: x, y: 40)) }
  precondition(counts.clicks == 2 && counts.ends == before + 1, "Ordinary checkbox/control clicks changed")
  precondition(counts.activations == 0, "A drag/control click activated the row")
  send(from: CGPoint(x: 270, y: 40), to: CGPoint(x: 270, y: 40))
  precondition(counts.activations == 1 && counts.ends == before + 1 && counts.clicks == 2, "Ordinary body activation changed")
  print("PASS native SwiftUI compact background above material chrome: title, empty body, all padded edges, control/checkbox drag exclusion, body-to-control crossing, ordinary control clicks and body activation; only helper-panel events, no pointer/focus/user-window manipulation")
 }
}
SWIFT
Dir.mktmpdir('dockfork-compact-drag-') do |dir|
  File.write("#{dir}/checks.swift", native_source)
  abort 'Compact drag fixture compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Compact drag checks failed' unless system("#{dir}/checks")
end

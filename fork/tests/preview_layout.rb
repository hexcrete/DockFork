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

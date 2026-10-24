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
 func reconcileSelectionRange() {}
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
SWIFT
native_source += block(compact, 'enum CompactPreviewCardLayout {') + "\n"
native_source += <<~'SWIFT'
@MainActor final class Counts { var changes = 0; var ends = 0; var clicks = 0; var activations = 0 }
struct Row: View {
 let counts: Counts
 var previewBodyDrag: AnyGesture<DragGesture.Value>? {
  AnyGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
   .onChanged { _ in counts.changes += 1 }.onEnded { _ in counts.ends += 1 })
 }
 var body: some View {
  HStack(spacing: CompactPreviewCardLayout.spacing) {
   Color.blue.frame(width: 32, height: 32).allowsHitTesting(false)
    .overlay {
     Button { counts.clicks += 1 } label: { Color.white.frame(width: 24, height: 24) }.buttonStyle(.plain)
    }
    .onContinuousHover { _ in }
   Text("Window title").allowsHitTesting(false)
   Spacer()
   Button { counts.clicks += 1 } label: { Color.red.frame(width: 32, height: 32) }.buttonStyle(.plain)
  }
  .padding(.vertical, CompactPreviewCardLayout.verticalPadding)
  .frame(width: 400, height: 80, alignment: .leading)
SWIFT
native_source += compact_background + "\n  .opacity(0.25)\n"
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

opacity = '.opacity(isHighlighted || isChecked ? 1.0 : appearance.unselectedContentOpacity)'
abort 'Compact opacity must affect contents before shared chrome, not the entire card' unless compact_body.scan(opacity).size == 1 && compact_body.index(opacity) < compact_body.index('.previewCardChrome(')
chrome_start = compact_body.index('            .previewCardChrome(')
opening = compact_body.index('(', chrome_start)
depth = 0
chrome_end = (opening...compact_body.length).find do |i|
  depth += 1 if compact_body[i] == '('
  depth -= 1 if compact_body[i] == ')'
  depth.zero?
end
chrome_call = compact_body[chrome_start..chrome_end]
chrome = File.read("#{root}/DockDoor/Components/dockStyle.swift")
view_helpers = File.read("#{root}/DockDoor/Extensions/View.swift")
render_source = <<~'SWIFT'
import AppKit
import SwiftUI
enum Defaults {
 struct Key<T> { let value:T }
 static subscript<T>(_ key:Key<T>)->T {key.value}
}
extension Defaults.Key where T == Double {
 static let previewCornerRadius = Self(value:8)
}
extension Defaults.Key where T == Bool { static let uniformCardRadius = Self(value:true) }
@propertyWrapper struct Default<T> {
 let wrappedValue:T
 init(_ key:Defaults.Key<T>){wrappedValue=key.value}
}
struct BackgroundAppearance: Equatable {let color:Color}
struct BlurView: View {
 let cornerRadius:Double
 let appearance:BackgroundAppearance
 var body:some View {appearance.color}
}
SWIFT
render_source += block(chrome, 'enum CardRadius {') + "\n" + block(chrome, 'private struct PreviewCardChromeModifier:') + "\n"
render_source += block(view_helpers, 'enum BorderedBackgroundMetrics {') + "\n"
render_source += "extension View {\n" + block(chrome, '    func previewCardChrome(') + "\n"
render_source += block(view_helpers, '    func borderedBackground(_ content: some ShapeStyle, lineWidth: CGFloat = 1.0, shape:') + "\n"
render_source += block(view_helpers, '    func borderedBackground(_ content: some ShapeStyle, lineWidth: CGFloat = 1.0, cornerRadius:') + "\n}\n"
render_source += <<~'SWIFT'
struct Appearance {
 let unselectedContentOpacity:Double
 let hidePreviewCardBackground:Bool
 let globalPaddingMultiplier:CGFloat = 1
 let hoverHighlightColor:Color? = .blue
 let selectionOpacity:Double = 0.4
 let activeAppIndicatorColor:Color = .green
}
struct CardProbe:View {
 let appearance:Appearance
 let isHighlighted:Bool
 let isChecked:Bool
 let isActiveWindow:Bool
 let backgroundAppearance:BackgroundAppearance
 let uniformCardRadius=true
 var body:some View {
  HStack {Color.red.frame(width:16,height:16);Spacer(minLength:0)}
   .frame(width:160,height:48)
SWIFT
render_source += "   #{opacity}\n" + chrome_call + "\n"
render_source += <<~'SWIFT'
   .padding(.horizontal,CardRadius.innerPadding)
 }
}
@main struct MaterialChecks {
 @MainActor static func render(dim:Double,hidden:Bool,selected:Bool,checked:Bool,active:Bool,outerHidden:Bool,dark:Bool,custom:Bool)->NSBitmapImageRep {
  let surface:Color=custom ? Color(red:0.3,green:0.2,blue:0.6):Color(white:dark ? 0.2:0.8)
  let card=CardProbe(appearance:Appearance(unselectedContentOpacity:dim,hidePreviewCardBackground:hidden),isHighlighted:selected,isChecked:checked,isActiveWindow:active,backgroundAppearance:BackgroundAppearance(color:surface))
   .background(outerHidden ? Color.clear:Color(white:dark ? 0.1:0.95))
   .environment(\.colorScheme,dark ? .dark:.light)
  let renderer=ImageRenderer(content:card)
  renderer.scale=1
  return NSBitmapImageRep(cgImage:renderer.cgImage!)
 }
 static func components(_ image:NSBitmapImageRep,_ x:Int,_ y:Int)->[CGFloat] {
  let color=image.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
  return [color.redComponent,color.greenComponent,color.blueComponent,color.alphaComponent]
 }
 static func difference(_ first:[CGFloat],_ second:[CGFloat])->CGFloat {zip(first,second).map{abs($0-$1)}.max()!}
 @MainActor static func main() {
  _=NSApplication.shared
  var cases=0
  for dark in [false,true] {for custom in [false,true] {for outer in [false,true] {for hidden in [false,true] {for active in [false,true] {for (selected,checked) in [(false,false),(true,false),(false,true)] {
   let original=render(dim:1,hidden:hidden,selected:selected,checked:checked,active:active,outerHidden:outer,dark:dark,custom:custom)
   let dimmed=render(dim:0.2,hidden:hidden,selected:selected,checked:checked,active:active,outerHidden:outer,dark:dark,custom:custom)
   precondition(original.pixelsWide==dimmed.pixelsWide && original.pixelsHigh==dimmed.pixelsHigh)
   for x in [2,100] {
    precondition(difference(components(original,x,24),components(dimmed,x,24))<0.01,"Material/highlight/border must not be dimmed with content")
   }
   let delta=difference(components(original,14,24),components(dimmed,14,24))
   if selected || checked {precondition(delta<0.01,"Selected/checked content must remain full strength")}
   else {precondition(delta>0.1,"Unselected content must retain configured dimming")}
   if outer && hidden {
    precondition(components(dimmed,100,24)[3]<0.01,"Hiding both backgrounds must remain transparent")
   }
   cases+=1
  }}}}}}
  print("PASS shared Compact chrome opacity: \(cases) light/dark, custom fill, outer/card visibility, active, selected and checked raster cases; production chrome with deterministic material fill, not native glass certification")
 }
}
SWIFT
drag_style_source = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/DragPreviewCoordinator.swift")
consts = File.read("#{root}/DockDoor/consts.swift")
drag_declarations = block(consts,'enum CompactModeItemSize:').sub(', Defaults.Serializable','')+"\n"+block(consts,'enum SpacesBarItemSize:').sub(', Defaults.Serializable','')+"\n"
drag_declarations += block(compact,'enum CompactPreviewCardLayout {')+"\n"
drag_declarations += <<~'SWIFT'
final class NSRunningApplication {
 let processIdentifier:Int32
 let bundleIdentifier:String?
 let icon:NSImage?=NSImage(size:CGSize(width:32,height:32))
 init(_ pid:Int32,_ bundle:String?){processIdentifier=pid;bundleIdentifier=bundle}
}
struct WindowInfo {let app:NSRunningApplication}
struct PreviewAppearanceSettings {
 var compactModeItemSize:CompactModeItemSize
 var globalPaddingMultiplier:CGFloat=0.7
 var hidePreviewCardBackground=false
}
enum GhostTestSettings {static var size=SpacesBarItemSize.small}
extension Defaults.Key where T == CGFloat {static var globalPaddingMultiplier:Self{Self(value:0.7)}}
extension Defaults.Key where T == Bool {static var hidePreviewCardBackground:Self{Self(value:false)}}
extension Defaults.Key where T == SpacesBarItemSize {static var spacesBarItemSize:Self{Self(value:GhostTestSettings.size)}}
enum SpacesBarLayout {
 static var pillHeight:CGFloat{Defaults[.spacesBarItemSize].rowHeight}
 static var scale:CGFloat{Defaults[.spacesBarItemSize].scale}
 static var font:Font{Defaults[.spacesBarItemSize].primaryFont}
 static var textFont:NSFont{Defaults[.spacesBarItemSize].primaryAppKitFont}
 static var horizontalInset:CGFloat{SpacePillMetrics(height:pillHeight).horizontalInset}
}
SWIFT
bar_source = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SearchWindow.swift")
drag_declarations += "enum MaterialPillStyle {static let horizontalInset:CGFloat=9.125}\nenum WindowStateIndicator {static let styledContentPadding:CGFloat=4}\n"
drag_declarations += block(bar_source,'struct SpacePillMetrics {')+"\n"+block(bar_source,'private struct AppWindowCountSubscript:')+"\nextension View {\n"+block(bar_source,'    func appWindowCount(')+"\n}\n"
discovery_source=File.read("#{root}/DockDoor/Utilities/Window Management/WindowDiscoveryShared.swift")
drag_declarations += "enum ManagedSpacePresentation {\n"+block(discovery_source,'    static func applicationKey(')+"\n}\n"
drag_declarations += block(bar_source,'enum SpacesBarAppLayout {')+"\n"
drag_declarations += "enum AppIconStripFormatting {\n"+block(appearance,'    static func width(')+"\n"+block(appearance,'    static func visibleCount(total:')+"\n}\n"
drag_declarations += block(drag_style_source,'struct PreviewDragCardStyle:')+"\nextension View {\n"+block(drag_style_source,'    func previewDragCard(')+"\n}\n"
%w[PreviewDragApp PreviewDragIcon PreviewDragActionSymbol WindowGroupDragCard SpaceDragLabel].each{|name|drag_declarations += block(drag_style_source,"struct #{name}:")+"\n"}
drag_checks = <<~'SWIFT'
 @MainActor static func checkDragCards() {
  let background=BackgroundAppearance(color:.gray)
  let image=NSImage(size:CGSize(width:32,height:32))
let a=NSRunningApplication(10,"a"),b=NSRunningApplication(20,"b"),alias=NSRunningApplication(21,"b")
let n1=NSRunningApplication(30,nil),n2=NSRunningApplication(31,nil)
let windows=[a,b,a,n1,alias,n2].map{WindowInfo(app:$0)}
let grouped=PreviewDragApp.grouped(windows)
precondition(grouped.map(\.id)==["a","b","pid:30","pid:31"] && grouped.map(\.windowCount)==[2,2,1,1],"Group by Space app identity in first-selected order")
precondition(grouped[1].app === b && windows.count==6,"Grouping is presentation-only and retains the first representative app")
precondition(PreviewDragApp.grouped(Array(repeating:WindowInfo(app:a),count:10000)).first?.windowCount==10000)
  for size in CompactModeItemSize.allCases {
   var settings=PreviewAppearanceSettings(compactModeItemSize:size)
   let style=PreviewDragCardStyle.compact(appearance:settings,uniformCardRadius:true,backgroundAppearance:background)
   precondition(style.height==size.rowHeight && style.iconSize==size.iconSize && style.textFont==size.primaryAppKitFont && style.font==size.primaryFont)
   let pill=SpacePillMetrics(height:size.rowHeight)
   precondition(style.spacing==pill.spacing && style.horizontalInset==pill.horizontalInset)
   var counterSettings=PreviewAppearanceSettings(compactModeItemSize:size)
   counterSettings.hidePreviewCardBackground=true
   let counterStyle=PreviewDragCardStyle.compact(appearance:counterSettings,uniformCardRadius:true,backgroundAppearance:background)
   let one=counterStyle.groupLayout(total:1,maximumWidth:1000)
   let counterCard=WindowGroupDragCard(icons:[PreviewDragIcon(id:"a",image:image,windowCount:12)],overflow:0,width:one.width,style:counterStyle)
   let counterRenderer=ImageRenderer(content:counterCard.environment(\.colorScheme,.light))
   counterRenderer.scale=1
   let pixels=NSBitmapImageRep(cgImage:counterRenderer.cgImage!)
   let iconRight=Int(ceil((one.width+style.iconSize+style.actionWidth)/2))
   let visibleCount=(0..<pixels.pixelsHigh).contains{y in
    ((iconRight+1)..<pixels.pixelsWide).contains{x in pixels.colorAt(x:x,y:y)!.alphaComponent>0.1}
   }
   precondition(visibleCount,"Subscript must remain visible in the side padding, not be clipped at the icon boundary")
   settings.compactModeItemSize = .xxxLarge;settings.hidePreviewCardBackground=true
   precondition(style.height==size.rowHeight && !style.hideBackground,"Window style must be captured, not read live")
   for total in [2,6,7,42,10000] {for maximum:CGFloat in [1,40,100,240,1000] {
    let layout=style.groupLayout(total:total,maximumWidth:maximum)
    precondition(layout.visible<=min(6,total) && layout.width<=maximum && layout.width>0)
    let icons=(0..<layout.visible).map{PreviewDragIcon(id:"app-\($0)",image:image,windowCount:$0+1)}
    precondition(Set(icons.map(\.id)).count==icons.count,"Visible app groups need stable identities")
    let card=WindowGroupDragCard(icons:icons,overflow:total-icons.count,width:layout.width,style:style)
    let measured=NSHostingView(rootView:card).fittingSize
    precondition(abs(measured.width-layout.width)<0.1 && measured.height==size.rowHeight,"Group card must match source height and fitted width")
    let room=maximum-style.horizontalInset*2-style.actionWidth
    var expected=0
    for count in (0...min(total,6)).reversed() {
     let overflow=total-count
     let suffix=overflow>0 ? ("+\(overflow)" as NSString).size(withAttributes:[.font:style.textFont]).width:0
     let required=CGFloat(count)*style.iconSize+CGFloat(max(0,count-1))*style.spacing+suffix+(count>0 && overflow>0 ? style.spacing:0)
     if required<=room{expected=count;break}
    }
    precondition(layout.visible==expected,"Overflow must measure the real primary-font +N and respect the six-icon cap")
   }}
  }
  for size in SpacesBarItemSize.allCases {
   GhostTestSettings.size=size
   let style=PreviewDragCardStyle.spacesBar(backgroundAppearance:background)
   precondition(style.height==size.rowHeight && style.iconSize==SpacesBarAppLayout.iconSize && style.font==size.primaryFont)
   GhostTestSettings.size = .small
   var measured:CGSize?
   for symbol in ["nosign","arrow.triangle.merge","arrow.left.arrow.right","arrow.left","arrow.right"] {
    let label=SpaceDragLabel(title:"Desktop 12",symbol:symbol,style:style,maximumWidth:600)
    let fitting=NSHostingView(rootView:label).fittingSize
    precondition(fitting.height==size.rowHeight && fitting.width<=600)
    if let previous=measured{precondition(previous==fitting,"Changing target glyph must not move the label anchor")}
    measured=fitting
   }
   for maximum:CGFloat in [1,40,120] {
    let label=SpaceDragLabel(title:String(repeating:"Long Desktop ",count:10),symbol:"nosign",style:style,maximumWidth:maximum)
    let fitting=NSHostingView(rootView:label).fittingSize
    precondition(fitting.width<=maximum+0.1 && fitting.height==size.rowHeight,"Long Space labels must fit without shrinking card height")
   }
  }
  GhostTestSettings.size = .small
  print("PASS source-styled drag cards: all seven sizes, captured fonts/spacing/material policy, measured overflow/cap/narrow widths, merged-app counts/first-selection order, stable target glyphs and long labels; production views with deterministic material")
 }
SWIFT
render_source.sub!('@main struct MaterialChecks {',drag_declarations+"\n@main struct MaterialChecks {\n"+drag_checks)
render_source.sub!("  _=NSApplication.shared\n  var cases=0", "  _=NSApplication.shared\n  checkDragCards()\n  var cases=0")

Dir.mktmpdir('dockfork-compact-opacity-') do |dir|
  File.write("#{dir}/checks.swift",render_source)
  abort 'Compact chrome fixture compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
  abort 'Compact chrome checks failed' unless system("#{dir}/checks")
end

indicator = block(appearance, 'struct WindowStateIndicator:')
abort 'Shared Space/state indicator must keep its intrinsic width instead of compressing on control reveal' unless indicator.include?('.fixedSize(horizontal: true, vertical: false)')

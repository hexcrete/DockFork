#!/usr/bin/env ruby
# Compile the production Space model against inert app/window metadata.
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
shared = File.read("#{root}/DockDoor/Utilities/Window Management/WindowDiscoveryShared.swift")
state = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift")
view = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview.swift")
menu = block(view, '    func makeMenu(for window:')
abort 'Menu must share one model and one native-tab collapse' unless menu.scan('ManagedSpacePresentation.snapshot(').size == 1 && menu.scan('WindowUtil.collapseNativeTabsIfNeeded(').size == 1
abort 'All menus must use configured Window sort order without session branching' unless menu.include?('WindowUtil.getAllWindowsIgnoringSwitcherFilters()') && !menu.include?('windowSwitcherActive') && !shared.include?('usesWindowOrder')

abort 'Old presentation builders must be removed' if view.include?('private func apps(on space:') || view.include?('private func menuTitle(for space:')
abort 'Menu must preserve fullscreen availability and current badges' unless menu.include?('!entry.isFullscreen || showUnavailable') && menu.include?('if presentedSpace.isCurrent,')
abort 'Menu must keep native shared icon formatting' unless view.include?('AppIconStripFormatting.attributedIcons(appIcons, maximumVisible: max(0, 5 - attachmentCount)')
bar = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SearchWindow.swift")
abort 'Space labels must share Compact Mode primary typography and measurement' unless bar.include?('Defaults[.spacesBarItemSize].primaryFont') && bar.include?('Defaults[.spacesBarItemSize].primaryAppKitFont') && bar.include?('let font = SpacesBarLayout.textFont')
panel = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
cache = File.read("#{root}/DockDoor/Utilities/Window Management/SpaceWindowCacheManager.swift")
abort 'Bar must refresh with cache metadata and display topology' unless block(cache, '    private func flushCoordinatorChanges()').include?('preview.refreshSpacesBar(metadataOnly: true)') && panel.include?('spacesBarScreenObserver = NotificationCenter.default.addObserver(') && panel.include?('spacesBarScreenObserver = nil') && panel.include?('if metadataOnly, fingerprint == spacesBarFingerprint { return }') && block(cache, '    private func flushCoordinatorChanges()').include?('preview.windowSwitcherCoordinator.windowSwitcherActive, Defaults[.enableSpacesBar]')
settings = File.read("#{root}/DockDoor/Views/Settings/WindowSwitcherBehaviorSettingsView.swift") + File.read("#{root}/DockDoor/Views/Settings/AppearanceSettingsView.swift")
catalog = File.read("#{root}/DockDoor/Views/Settings/Search/SettingsSearchCatalog.swift")
reset = File.read("#{root}/DockDoor/Views/Settings/MainSettingsView.swift")
%w[enableSpacesBar spacesBarItemSize spacesBarPreferDetails spacesBarMinimumWidth spacesBarLabels spacesBarFixedWidth spacesBarMaximumWidth spacesBarPillWidth spacesBarHideWhenSingle].each do |key|
  abort "Unwired bar setting #{key}" unless settings.include?("windowSwitcher.#{key}") && catalog.include?("windowSwitcher.#{key}") && reset.include?("Defaults[.#{key}] = Defaults.Keys.#{key}.defaultValue")
end
%w[spacesBarItemSize spacesBarLabels spacesBarFixedWidth spacesBarPreferDetails spacesBarMinimumWidth spacesBarMaximumWidth spacesBarPillWidth].each do |key|
  entry = catalog.lines.find { |line| line.include?("id: \"windowSwitcher.#{key}\"") }
  abort "Visual setting must navigate to Appearance: #{key}" unless entry&.include?('tab: "Appearance"')
end
abort 'Bar must share the switcher container and hide native scrollbars' unless bar.include?('BaseHoverContainer(bestGuessMonitor: screen') && bar.include?('CardGridScrollView.ContainerView(scrollsVertically: false)') && !bar.include?('ScrollView(.horizontal')
abort 'Display titles must use isolated existing scroll updates and native dividers' unless bar.include?('Divider().frame(width: SpacesBarLayout.dividerWidth') && bar.include?('PreviewHeaderLayout.textFont') && bar.include?('view.scroller.onOffsetChange = nil') && bar.include?('CATransaction.setDisableActions(true)') && !bar.include?('SpacesBarTitlePosition')
abort 'Tiny width requests must retain the scaled single-number shape' unless panel.include?('max(SpacesBarLayout.minimumPillWidth, requestedWidth.isFinite ? min(600, max(10, requestedWidth)) : 240)') && settings.scan('in: 10 ... 600, step: 10').size == 3
abort 'Bar must reuse native edge-scroll timing and zone settings' unless bar.include?('CardGridScrollView.edgeScrollZoneSize') && bar.include?('scroller.updateEdgeScroll(request: request, speed: speed)') && bar.include?('@Default(.mouseHoverAutoScrollSpeed)') && bar.include?('.fadeOnEdges(axis: .horizontal')
abort 'Bar must use shared icon fitting and native accessibility' unless bar.include?('AppIconStripFormatting.visibleCount') && bar.include?('.accessibilityLabel') && bar.include?('.accessibilityHidden(true)')
abort 'Bar must remain gated, internal and inherit preview capture policy' unless panel.include?('guard windowSwitcherCoordinator.windowSwitcherActive, Defaults[.enableSpacesBar]') && panel.include?('WindowUtil.registerInternalWindow') && panel.include?('panel.sharingType = sharingType') && !block(bar, 'final class SpacesBarWindow:').include?('sharingType = .none')
abort 'Bar must preserve scroll state and cached membership' unless panel.include?('hosting.rootView = barView') && panel.include?('if fingerprint != spacesBarFingerprint')
abort 'Single-Space hiding must retain topology observation' unless panel.include?('removeSpacesBar(keepTopologyObserver: true)')
activation = panel.split('activate: { [weak self] entry in',2).last.split("\n        )",2).first
abort 'Space activation must dismiss through the shared lifecycle before both occupied/empty transitions' unless activation.index('appDelegate.dismissPreviews()') < activation.index('WindowUtil.switchToManagedSpace')
abort 'A late switch completion must not dismiss a reopened switcher' if activation.split('WindowUtil.switchToManagedSpace',2).last.include?('hideWindow()')
abort 'Count must overlay the icon slot alongside the shared badge component' unless bar.include?('.overlay(alignment: .bottomTrailing)') && bar.include?('PreviewAppIcon(icon: app.application.icon') && bar.include?('@Default(.switcherShowAppIconBadges)') && bar.include?('@Default(.switcherAppIconBadgeScale)')
count_style = bar.split('Text("\(app.windowCount)")',2).last&.split('.accessibilityHidden(true)',2)&.first
abort 'Subscript must not have badge-like decoration' if count_style.nil? || count_style.match?(/\.shadow\(|\.background\(/)
pill_style = block(bar, '    private func pill(')
abort 'Space cards must share preview-card styling and centered labels' unless pill_style.include?('.previewCardChrome(') && pill_style.include?('hideBackground: hideCardBackground') && pill_style.include?('uniformCardRadius: uniformCardRadius') && !pill_style.include?('.materialPill(') && pill_style.include?('frame(width: titleWidth, alignment: .center)')
abort 'Space cards must honor active-border visibility and actual hover independently' unless bar.include?('@Default(.showActiveWindowBorder)') && pill_style.include?('isHighlighted: viewport.hoveredSpaceID == entry.id, isActiveWindow: showActiveWindowBorder && entry.isCurrent') && pill_style.include?('highlightColor: highlightColor ?? Color(nsColor: .controlAccentColor)') && pill_style.include?('.onHover { hovering in')
abort 'Companions must follow actual native frames without content rebuilding' unless panel.include?('if spacesBarWindow != nil { positionCompanionWindows() }') && !panel.include?('positionSpacesBar(relativeTo: targetFrame)')
model = block(shared, 'enum ManagedSpacePresentation {')
abort 'Space model must not retain screenshots or discover windows' if model.match?(/let \w+: (?:\[)?WindowInfo|\.image\b|\.axElement\b|Task\b|Timer\b|\.addObserver\b|getAllWindows/)

source = <<~'SWIFT'
import Foundation
import CoreGraphics
typealias CGWindowID = UInt32
typealias CGSSpaceID = UInt64
enum SpaceMenuDisplayMode { case numberOnly, fullName }
final class NSRunningApplication {
 static var running: [pid_t: NSRunningApplication] = [:]
 let processIdentifier: pid_t
 let localizedName: String?
 let bundleIdentifier: String?
 var isTerminated = false
 init(_ pid: pid_t, _ name: String?, _ bundle: String?) {
  processIdentifier=pid; localizedName=name; bundleIdentifier=bundle; Self.running[pid]=self
 }
 init?(processIdentifier pid: pid_t) {
  guard let app=Self.running[pid] else {return nil}
  processIdentifier=pid; localizedName=app.localizedName; bundleIdentifier=app.bundleIdentifier; isTerminated=app.isTerminated
 }
}
struct WindowInfo {
 let id: CGWindowID
 let app: NSRunningApplication
 let ownerApp: NSRunningApplication
 var isWindowlessApp: Bool
 let spaceID: Int?
 init(_ id: CGWindowID, _ app: NSRunningApplication, space: Int? = nil, owner: NSRunningApplication? = nil, windowless: Bool = false) {
  self.id=id; self.app=app; ownerApp=owner ?? app; spaceID=space; isWindowlessApp=windowless
 }
}
enum WindowUtil { static var internalIDs: Set<CGWindowID> = [999]; static func isInternalWindow(_ id: CGWindowID) -> Bool { internalIDs.contains(id) } }
enum Membership {
 static var responses: [CGWindowID: [CGSSpaceID]] = [:]
 static var reads: [CGWindowID: Int] = [:]
}
extension CGWindowID {
 func cgsSpaces() -> [CGSSpaceID] { Membership.reads[self,default:0]+=1; return Membership.responses[self] ?? [] }
}
SWIFT
source += block(state, 'struct PreviewWindowIdentity:') + "\n"
%w[ManagedSpaceKind ManagedSpaceDescriptor ManagedDisplayDescriptor ManagedSpaceDestination].each do |name|
  signature = name == 'ManagedSpaceKind' ? "enum #{name}:" : "struct #{name} {"
  source += block(shared, signature) + "\n"
end
source += "enum WindowSpaces {\n static func displayName(for id: String) -> String? { id == \"first\" ? \"Built-in Display\" : nil }\n"
source += block(shared, '    static func sourceSpaceIDs(for window:') + "\n}\n"
source += model + "\n"
source += block(File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/BaseHoverContainer.swift"), 'enum HoverContainerPadding {') + "\n"
sizes = block(File.read("#{root}/DockDoor/consts.swift"), 'enum CompactModeItemSize:')
sizes = sizes.sub(', Defaults.Serializable', '')
space_sizes = block(File.read("#{root}/DockDoor/consts.swift"), 'enum SpacesBarItemSize:').sub(', Defaults.Serializable', '')
font_space_sizes = space_sizes
['    var primaryFont:', '    var primaryAppKitFont:'].each { |signature| space_sizes = space_sizes.sub(block(space_sizes, signature), '') }
font_sizes = sizes
['    var primaryFont:', '    var primaryAppKitFont:', '    var secondaryFont:'].each { |signature| sizes = sizes.sub(block(sizes, signature), '') }
source += sizes + "\n" + space_sizes + "\n"
source += <<~'SWIFT'
enum PreviewHeaderLayout { static let horizontalInset: CGFloat = 20 }
enum SearchWindow { static let searchHeight: CGFloat = 40; static let panelEdgeOffset: CGFloat = -4 }
enum WindowStateIndicator { static let styledMinimumAspectRatio: CGFloat = 1.2; static let styledContentPadding: CGFloat = 4 }
enum MaterialPillStyle { static let horizontalInset: CGFloat = 9.125 }
enum Defaults { struct Key<T> { let value: T }; static var size = SpacesBarItemSize.small; static subscript<T>(_ key: Key<T>) -> T { key.value } }
extension Defaults.Key where T == CGFloat { static var globalPaddingMultiplier: Self { Self(value:1) } }
extension Defaults.Key where T == SpacesBarItemSize { static var spacesBarItemSize: Self { Self(value:Defaults.size) } }
enum WindowPreviewHoverContainer {
 struct PreviewLayoutMetrics {
  let contentInset: CGFloat
  static func resolve(compact:Bool, onlyWindowlessDockLikeRows:Bool,paddingMultiplier:CGFloat)->Self { Self(contentInset:14 * paddingMultiplier) }
 }
}
SWIFT

layout = block(bar, 'enum SpacesBarLayout {')
layout = layout.lines.reject { |line| line.include?('static var font:') || line.include?('static var textFont:') || line.include?('static var headingFont:') || line.include?('static var headingTextFont:') || line.include?('static var headingHeight:') }.join
source += layout.sub("enum SpacesBarLayout {", "enum SpacesBarLayout {\n static var headingHeight: CGFloat { 14 * scale }") + "\n"
source += block(bar, 'enum SpacesBarAppLayout {') + "\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() {
  precondition(SpacesBarLayout.widths(ideal:[200,300],labels:[40,60],maximum:240,available:600,fixed:false)==[200,240])
  precondition(SpacesBarLayout.widths(ideal:[200,300],labels:[48,60],maximum:240,available:108,fixed:false)==[48,60])
  precondition(SpacesBarLayout.widths(ideal:[200,300],labels:[48,60],maximum:240,available:1,fixed:false)==[48,60], "Only label widths constrain shrinking; overflow then scrolls")
  precondition(SpacesBarLayout.widths(ideal:[200,300],labels:[40,60],maximum:240,available:100,fixed:true)==[240,240])
  precondition(SpacesBarLayout.widths(ideal:[],labels:[],maximum:240,available:600,fixed:false).isEmpty)
  precondition(SpacesBarLayout.widths(ideal:[10,30],labels:[8,28],maximum:240,available:100,fixed:false)==[48,48], "Short labels must use the shared Space indicator ratio")
  precondition(SpacesBarLayout.reservation(displayCount:1,search:true)==108)
  precondition(SpacesBarLayout.reservation(displayCount:1,search:false)==80)
  for size in SpacesBarItemSize.allCases {
   Defaults.size = size
   let scale = size.scale
   precondition(abs(SpacesBarLayout.pillHeight - 40 * scale) < 0.001)
   precondition(abs(SpacesBarAppLayout.iconSize - 24 * scale) < 0.001)
   precondition(abs(SpacesBarAppLayout.countFontSize - 9 * scale) < 0.001)
   precondition(abs(SpacesBarAppLayout.spacing - 6 * scale) < 0.001)
   precondition(SpacesBarLayout.minimumPillWidth >= SpacesBarLayout.pillHeight)
   precondition(SpacesBarLayout.height(displayCount:1) > SpacesBarLayout.pillHeight)
   precondition(SpacesBarLayout.widths(ideal:[800], labels:[48], maximum:240, available:500, fixed:true)==[240])
  }
  precondition(SpacesBarItemSize.medium.localizedName == CompactModeItemSize.medium.localizedName)
  precondition(abs(SpacesBarItemSize.medium.scale - CompactModeItemSize.xLarge.iconSize / CompactModeItemSize.large.iconSize)<0.001)
  for old in CompactModeItemSize.allCases {
   let preserved = SpacesBarItemSize(rawValue:old.rawValue)!
   precondition(preserved.scale == old.iconSize / CompactModeItemSize.large.iconSize)
  }
  precondition(SpacesBarItemSize.xxxLarge.scale > SpacesBarItemSize.xxLarge.scale)
  precondition(SpacesBarItemSize.xxLarge.scale > SpacesBarItemSize.xLarge.scale)
  Defaults.size = .small
precondition(abs(SpacesBarLayout.widths(ideal:[400,500], labels:[100,120], maximum:600, available:500, fixed:false, minimum:160).reduce(0,+)-500)<0.001)
precondition(SpacesBarLayout.widths(ideal:[400,500], labels:[100,120], maximum:600, available:100, fixed:false, minimum:160)==[160,160], "Screen preference scrolls only after reaching minimum widths")
precondition(SpacesBarLayout.widths(ideal:[400,800], labels:[100,120], maximum:600, available:100, fixed:false, preferDetails:true)==[400,600], "Details preference must not compress contents to the viewport")
precondition(SpacesBarLayout.widths(ideal:[100], labels:[250], maximum:900, available:100, fixed:false, minimum:160)==[250], "Names take priority over shrinking to minimum")
precondition(SpacesBarLayout.widths(ideal:[100], labels:[10], maximum:80, available:100, fixed:false, minimum:160)==[80], "Screen clamp wins over configured minimum")
let gridTop: CGFloat = 300

  let searchY = SpacesBarLayout.searchY(gridTop:gridTop)
  precondition(searchY == gridTop - HoverContainerPadding.container + SearchWindow.panelEdgeOffset)
  let barBottom = searchY + SearchWindow.searchHeight + SpacesBarLayout.gap
  precondition(barBottom - (searchY + SearchWindow.searchHeight) == SpacesBarLayout.gap)
for search in [false,true] {
 for grid in [CGRect(x:100,y:100,width:900,height:500),CGRect(x:450,y:250,width:200,height:200),CGRect(x:100,y:100,width:900,height:500)] {
  let bar=SpacesBarLayout.frame(grid:grid,size:CGSize(width:600,height:124),screen:CGRect(x:0,y:0,width:2000,height:2000),search:search,alignment:0.5)
  let lower=search ? SpacesBarLayout.searchY(gridTop:grid.maxY)+SearchWindow.searchHeight : grid.maxY-SpacesBarLayout.outerPadding
  precondition(bar.minY+SpacesBarLayout.outerPadding-lower==(search ? SpacesBarLayout.searchGap : SpacesBarLayout.gap),"Attachment gap must remain unchanged through search resize/reversal")
  precondition(bar.midX==grid.midX)
 }
}
  let zebra=NSRunningApplication(11,"Zebra","example.zebra")
  let alpha=NSRunningApplication(12,"Alpha","example.alpha")
  let alphaInstance=NSRunningApplication(13,"Alpha","example.alpha")
  let helper1=NSRunningApplication(20,"Helper",nil), helper2=NSRunningApplication(21,"Helper",nil)
  let owner=NSRunningApplication(111,"Helper process","example.zebra.helper")
  let dead=NSRunningApplication(30,"Terminated","example.dead"); dead.isTerminated=true
  let fullscreenOwner=NSRunningApplication(40,"Full App","example.full")
  let own=NSRunningApplication(ProcessInfo.processInfo.processIdentifier,"DockFork","example.own")
  let bigID: CGSSpaceID = 9_007_199_254_740_993
  func space(_ id: CGSSpaceID, _ kind: ManagedSpaceKind?, _ number: Int, owners: Set<pid_t> = []) -> ManagedSpaceDescriptor {
   ManagedSpaceDescriptor(id:id,kind:kind,number:number,desktopNumber:kind == .desktop ? number : nil,ownerPIDs:owners)
  }
  let first=ManagedDisplayDescriptor(identifier:"first",currentSpaceID:1,spaces:[space(1,.desktop,1),space(2,.desktop,2),space(3,.fullscreen,3,owners:[111,40,30,99999,own.processIdentifier]),space(4,.system,4),space(5,nil,5)])
  let second=ManagedDisplayDescriptor(identifier:"second",currentSpaceID:bigID,spaces:[space(bigID,.desktop,6)])
  let unknown=ManagedDisplayDescriptor(identifier:"unknown",currentSpaceID:nil,spaces:[space(9,.system,9)])
  let topology=[first,second,unknown]
  let w1=WindowInfo(1,zebra,space:1,owner:owner), w2=WindowInfo(2,alpha,space:1)
  let w3=WindowInfo(3,alphaInstance,space:1), sticky=WindowInfo(4,zebra,space:1)
  let windows=[w1,w2,w3,sticky,w1,WindowInfo(5,helper1,space:2),WindowInfo(6,helper2,space:2),WindowInfo(0,alpha,windowless:true),WindowInfo(7,alpha,space:1,windowless:true),WindowInfo(999,zebra,space:1),WindowInfo(8,dead,space:1)]
  Membership.responses=[1:[1],2:[1],3:[1],4:[1,bigID],6:[2]]
  let ordered=ManagedSpacePresentation.snapshot(displays:topology,orderedWindows:windows)
  precondition(ordered.map(\.id)==["first","second"])
  precondition(ordered[0].name=="Built-in Display" && ordered[1].name=="Display 2")
  precondition(ordered[0].spaces.map(\.id)==[1,2,3] && ordered[1].spaces[0].id==bigID)
  let desktop=ordered[0].spaces[0], full=ordered[0].spaces[2]
  precondition(desktop.isCurrent && !desktop.isFullscreen && full.isFullscreen && !full.isCurrent)
  precondition(ordered[1].spaces[0].isCurrent)
  precondition(desktop.apps.map { $0.application.processIdentifier }==[11,12])
  precondition(desktop.apps.map(\.windowCount)==[2,2])
  precondition(desktop.apps[0].windowIdentities==[PreviewWindowIdentity(w1),PreviewWindowIdentity(sticky)])
  precondition(desktop.apps[1].windowIdentities==[PreviewWindowIdentity(w2),PreviewWindowIdentity(w3)])
  precondition(ordered[1].spaces[0].apps[0].windowIdentities==[PreviewWindowIdentity(sticky)])
  precondition(ordered[0].spaces[1].apps.map { $0.application.processIdentifier }==[20,21],"Unbundled apps must not collapse together")
  precondition(full.apps.map { $0.application.processIdentifier }==[11,40],"Fullscreen owner fallback must resolve display-app identities and omit dead/missing/internal owners")
  precondition(full.apps.allSatisfy { $0.windowCount==0 },"An owner PID must not invent window counts or action targets")
  precondition(desktop.title(mode:.numberOnly)=="1" && desktop.title(mode:.fullName)=="Desktop 1")
  precondition(full.title(mode:.fullName)=="Zebra + Full App")
  precondition(Membership.reads==[1:1,2:1,3:1,4:1,5:1,6:1],"Read membership once per represented window, never once per Space or duplicate row")
  let reversed=ManagedSpacePresentation.snapshot(displays:topology,orderedWindows:[w3,w2,w1,sticky])
  precondition(reversed[0].spaces[0].apps.map { $0.application.processIdentifier }==[13,11],"App order must follow supplied window order, never app names")
  precondition(reversed[0].spaces[0].apps.map(\.windowCount)==[2,2])
  let other=WindowInfo(70,zebra,space:2), later=WindowInfo(71,zebra,space:1)
  let perSpace=ManagedSpacePresentation.snapshot(displays:topology,orderedWindows:[other,w2,later])
  precondition(perSpace[0].spaces[0].apps.map { $0.application.processIdentifier }==[12,11],"Ordering must use each Space's first contributing window, not the app's first window on another Space")
  Membership.reads=[:]
  let empty=ManagedSpacePresentation.snapshot(displays:topology,orderedWindows:[])
  precondition(empty[0].spaces[0].apps.isEmpty && empty[0].spaces[1].apps.isEmpty)
  precondition(empty[1].spaces[0].apps.isEmpty && empty[0].spaces[2].apps.count==2)
  precondition(Membership.reads.isEmpty)
  precondition(ManagedSpacePresentation.snapshot(displays:[unknown],orderedWindows:windows).isEmpty)
  precondition(Membership.reads.isEmpty,"Unavailable topology must do no membership reads")
  let noOwners=ManagedDisplayDescriptor(identifier:"third",currentSpaceID:nil,spaces:[space(55,.fullscreen,1)])
  let fallback=ManagedSpacePresentation.snapshot(displays:[noOwners],orderedWindows:[])[0].spaces[0]
  precondition(fallback.title(mode:.fullName)=="Full Screen")
  let retainedIDs=desktop.apps.flatMap(\.windowIdentities)
  let changed=ManagedSpacePresentation.snapshot(displays:[second],orderedWindows:[sticky])
  precondition(changed[0].spaces[0].apps[0].windowIdentities==[PreviewWindowIdentity(sticky)] && retainedIDs.count==4,"Topology refresh must produce a new immutable value")
  _=owner; _=fullscreenOwner
  print("PASS production Space snapshot: ordering/fallback, per-app counts, stable IDs, multi-Space membership, cached fallback, owner/display mapping, native-representative identity deduplication, empty/fullscreen/system Spaces, internal/windowless/terminated exclusions, generated labels and bounded membership reads")
 }
}
SWIFT
Dir.mktmpdir('dockfork-space-presentation-') do |dir|
  File.write("#{dir}/checks.swift",source)
  abort 'Space snapshot compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
  abort 'Space snapshot checks failed' unless system("#{dir}/checks")
end

# Exercise the production bar adapter and shared scrolling engine without sending
# events to user windows or moving the pointer/focus.
scroll_source = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview Supporting/CardGridScrollView.swift")
native_source = "import AppKit\nimport SwiftUI\ntypealias CGSSpaceID = UInt64\n" + font_sizes + "\n" + font_space_sizes + "\n"
native_source += "enum CardGridScrollView { static let edgeScrollZoneSize: CGFloat = 50\n"
native_source += block(scroll_source, '    enum EdgeScrollRequest:') + "\n"
native_source += block(scroll_source, '    final class ContainerView:') + "\n"
native_source += block(scroll_source, '    final class FlippedView:') + "\n}\n"
native_source += block(bar, 'struct SpacesBarDisplayHeading:') + "\n"
native_source += block(bar, 'final class SpacesBarHeadingOverlay:') + "\n"
native_source += block(bar, 'final class SpacesBarViewport:') + "\n"
native_source += block(bar, 'final class SpacesBarWindow:') + "\n"
native_source += block(bar, 'struct SpacesBarScroll:') + "\n"
material = File.read("#{root}/DockDoor/Components/MaterialPill.swift")
view_extensions = File.read("#{root}/DockDoor/Extensions/View.swift")
preview = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview.swift")
native_source += block(view_extensions, 'enum BorderedBackgroundMetrics {') + "\n"
native_source += "extension View {\n" + block(view_extensions, '    func borderedBackground(_ content: some ShapeStyle, lineWidth: CGFloat = 1.0, shape:') + "\n}\n"
native_source += <<~'SWIFT'
struct BackgroundAppearance { static func resolve() -> Self { Self() } }
struct BlurView: View {
 let shape: Capsule
 let appearance: BackgroundAppearance
 var body: some View { Color.gray.clipShape(shape) }
}
enum SpacesBarLayout {
 static let innerPadding: CGFloat = 14
 static let headingInset: CGFloat = 20
 static let headingTextFont = NSFont.preferredFont(forTextStyle:.body)
 static let headingHeight: CGFloat = 16
 static let scale: CGFloat = 1
 static let font = Font.headline
 static let textFont = NSFont.preferredFont(forTextStyle:.headline)
 static let fullscreenWidth: CGFloat = 20
 static let pillHeight: CGFloat = 40
 static var horizontalInset: CGFloat { MaterialPillStyle.horizontalInset + WindowStateIndicator.styledContentPadding }
}
enum WindowStateIndicator { static let styledContentPadding: CGFloat = 4 }
enum SpaceMenuDisplayMode { case numberOnly }
enum ManagedSpacePresentation {
 struct App { let application: NSRunningApplication; let windowCount: Int }
 struct Entry {
  let id: UInt64 = 1
  let label: String
  let apps: [App] = []
  let isFullscreen = false
  let isCurrent = true
  func title(mode: SpaceMenuDisplayMode) -> String { label }
 }
}
SWIFT
native_source += block(material, 'struct MaterialPillStyle:') + "\n"
native_source += "extension View {\n" + block(material, '    func materialPill(') + "\n}\n"
native_source += "enum AppIconStripFormatting {\n" + block(preview, '    static func width(') + "\n" + block(preview, '    static func visibleCount(total:') + "\n}\n"
native_source += "extension SpacesBarLayout {\n" + block(bar, '    static func titleInset(') + "\n" + block(bar, '    static func pinnedTitleOffset(') + "\n}\n"
native_source += "enum Defaults { struct Key<T> { let value:T }; static subscript<T>(_ key:Key<T>)->T {key.value} }\nextension Defaults.Key where T == SpacesBarItemSize {static var spacesBarItemSize: Self {Self(value:.small)}}\n"
native_source += block(bar, 'enum SpacesBarAppLayout {') + "\n"
native_source += block(File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedHoverAppTitle.swift"), 'struct PreviewAppIcon:') + "\n"
native_source += <<~'SWIFT'
struct AppIconBadgeOverlay: View {
 let bundleURL: URL?
 let iconSize: CGFloat
 let scale: CGFloat
 let mockPreviewActive: Bool
 var body: some View { Color.clear }
}
SWIFT
native_source += <<~'SWIFT'
enum CardRadius {
 static func previewCard(uniform:Bool,paddingMultiplier:CGFloat)->Double { 8 }
}
extension View {
 func previewCardChrome(uniformCardRadius:Bool,paddingMultiplier:CGFloat,expansionEdges:Edge.Set,hideBackground:Bool,
                        isHighlighted:Bool,isActiveWindow:Bool,highlightColor:Color,highlightOpacity:Double,
                        activeBorderColor:Color,backgroundAppearance:BackgroundAppearance)->some View {
  background(Color.clear)
 }
}
SWIFT
native_source += <<~'SWIFT'
struct PillProbe: View {
 let uniformCardRadius = true
 let hideCardBackground = false
 let showActiveWindowBorder = true
 let viewport = SpacesBarViewport()
 let paddingMultiplier: CGFloat = 1
 let highlightColor: Color? = nil
 let highlightOpacity: Double = 0.4
 let activeBorderColor = Color.accentColor
 let showBadges = false
 let badgeScale: CGFloat = 1
 let width: CGFloat
 let label: String
 var widths: [UInt64: CGFloat] { [1:width] }
 let labels = SpaceMenuDisplayMode.numberOnly
 func activate(_ entry: ManagedSpacePresentation.Entry) {}
 var body: some View { pill(ManagedSpacePresentation.Entry(label:label)).fixedSize() }
SWIFT
native_source += block(bar, '    private func pill(') + "\n}\n"
native_source += "struct AppSlotProbe: View {\n let count: Int\n let showBadges = false\n let badgeScale: CGFloat = 1\n var body: some View {\n  let app = ManagedSpacePresentation.App(application:NSRunningApplication.current,windowCount:count)\n"
native_source += "                    PreviewAppIcon(icon: app.application.icon, bundleURL: app.application.bundleURL,\n                                   size: SpacesBarAppLayout.iconSize, showBadge: showBadges,\n                                   badgeScale: badgeScale, mockPreviewActive: false)\n                        .overlay(alignment: .bottomTrailing) {\n                            if app.windowCount > 1 {\n                                Text(\"\(app.windowCount)\")\n                                    .font(.system(size: SpacesBarAppLayout.countFontSize, weight: .bold))\n                                    .foregroundStyle(.primary)\n                                    .offset(x: 2, y: 4)\n                            }\n                        }\n    " + "\n }\n}\n"
native_source += "enum HoverContainerPadding { static let container: CGFloat = 24; static let dockStyleOuter: CGFloat = 2 }\n"
native_source += "class SearchWindow: NSPanel { static let searchHeight: CGFloat = 40; static let panelEdgeOffset: CGFloat = -4\n func targetFrame(relativeTo frame: CGRect, on screen: NSScreen?) -> CGRect { CGRect(x:frame.midX-150,y:SpacesBarLayout.searchY(gridTop:frame.maxY),width:300,height:40) }\n}\n"
native_source += "extension SpacesBarLayout { static let outerPadding: CGFloat = 26; static let gap: CGFloat = 8\n"
native_source += bar.lines.find { |line| line.include?('static var searchGap:') }.strip + "\n"
native_source += bar.lines.find { |line| line.include?('static func searchY(') }.strip + "\n"
native_source += block(bar, '    static func frame(grid:') + "\n}\n"
native_source += <<~'SWIFT'
final class CompanionProbe: NSPanel {
 var isPositioningCompanions = false
 var searchWindow: SearchWindow?
 var spacesBarWindow: SpacesBarWindow?
 func spacesBarFrame(relativeTo grid: CGRect, size: CGSize, screen: NSScreen) -> CGRect {
  SpacesBarLayout.frame(grid:grid,size:size,screen:screen.visibleFrame,search:searchWindow != nil,alignment:0.5)
 }
 func watch() {
  for name in [NSWindow.didMoveNotification,NSWindow.didResizeNotification] {
   NotificationCenter.default.addObserver(self,selector:#selector(positionCompanionWindows),name:name,object:nil)
  }
 }
 deinit { NotificationCenter.default.removeObserver(self) }
SWIFT
native_source += block(panel, '    @objc private func positionCompanionWindows()').sub('panelAnchor?.screen ?? screen','screen') + "\n}\n"
native_source += <<~'SWIFT'
@main struct NativeChecks {
 @MainActor static func main() {
  _ = NSApplication.shared
  guard !NSScreen.screens.isEmpty else { print("SKIP native Space viewport: no display access"); return }
  for size in SpacesBarItemSize.allCases {
   let text = "Desktop 12"
   let hosted = NSHostingView(rootView: Text(text).font(size.primaryFont).fixedSize())
   let measured = (text as NSString).size(withAttributes:[.font:size.primaryAppKitFont]).width
   precondition(abs(hosted.fittingSize.width - measured) < 2, "Primary SwiftUI font and AppKit measurement must agree: \(size)")
  }
  let testFont = NSFont.systemFont(ofSize:13,weight:.semibold)
for total in 1...8 {
 for room: CGFloat in [20,40,90,140,500] {
  let count = AppIconStripFormatting.visibleCount(total:total,availableWidth:room,iconSize:24,font:testFont,spacing:12)
  if let count {
   let remaining = total-count
   let suffixWidth = remaining>0 ? ("+\(remaining)" as NSString).size(withAttributes:[.font:testFont]).width : 0
   let required = CGFloat(count)*24 + CGFloat(max(0,count-1))*12 + (remaining>0 && count>0 ? 12 : 0) + suffixWidth
   precondition(required<=room,"Explicit-gap fitting must match the rendered icon-to-counter gap")
  }
 }
}
for total in 0...8 {

   for room: CGFloat in [1,20,40,90,500] {
    var expected: Int?
    if total>0 {
     var count=min(total,Int(room/24))
     while count>=0 {
      let remaining=total-count
      let suffix=remaining>0 ? (count>0 ? " +\(remaining)" : "+\(remaining)") : ""
      let required=AppIconStripFormatting.width(iconCount:count,iconSize:24,font:testFont)+(suffix as NSString).size(withAttributes:[.font:testFont]).width
      if required<=room { expected=count; break }
      count-=1
     }
    }
    precondition(AppIconStripFormatting.visibleCount(total:total,availableWidth:room,iconSize:24,font:testFont)==expected,"Native menu fitting must remain unchanged")
   }
  }
  for count in [1,2,99] {
   let slot=NSHostingView(rootView:AppSlotProbe(count:count)).fittingSize
   precondition(slot==CGSize(width:24,height:24),"Window counts must not change icon slot size")
  }
let screen=NSScreen.screens[0]
let original=CGRect(x:screen.visibleFrame.minX+100,y:screen.visibleFrame.minY+100,width:600,height:300)
let parent=CompanionProbe(contentRect:original,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
parent.alphaValue=0
parent.orderFront(nil)
let companion=SpacesBarWindow()
companion.alphaValue=0
companion.setFrame(parent.spacesBarFrame(relativeTo:original,size:CGSize(width:400,height:124),screen:screen),display:false)
parent.spacesBarWindow=companion
parent.addChildWindow(companion,ordered:.above)
companion.orderFront(nil)
parent.watch()
for rect in [original,CGRect(x:original.minX+150,y:original.minY+70,width:250,height:130),original] {
 parent.setFrame(rect,display:false)
 RunLoop.main.run(until:Date().addingTimeInterval(0.03))
 let expected=parent.spacesBarFrame(relativeTo:parent.frame,size:companion.frame.size,screen:screen)
 precondition(abs(companion.frame.minX-expected.minX)<=0.5 && abs(companion.frame.minY-expected.minY)<=0.5,"Native child movement must not compound companion offsets")
}
parent.removeChildWindow(companion)
companion.orderOut(nil)
parent.spacesBarWindow=nil
parent.orderOut(nil)
  let captureProbe=SpacesBarWindow()
  let parentProbe=NSPanel()
  precondition(captureProbe.sharingType==parentProbe.sharingType,"Bar must not opt out of screenshots by default")
  for width: CGFloat in [48,100,240] {
   let hosting=NSHostingView(rootView:PillProbe(width:width,label:"1"))
   let size=hosting.fittingSize
   precondition(abs(size.width-width)<0.1 && abs(size.height-40)<0.1,"Rendered production pill must match allocated size including material and border padding: \(size)")
  }
  let window=NSPanel(contentRect:NSRect(x:0,y:0,width:900,height:56),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  let view=SpacesBarScroll.ViewportView(frame:NSRect(x:0,y:0,width:900,height:56))
  window.contentView=view
  view.scroller.contentSize=CGSize(width:1600,height:56)
  view.initialCenter=950
  view.edgeScrolling=true
  view.speed=4
  view.layout()
  precondition(view.scroller.bounds.width==900 && view.scroller.maxOffset==700)
  precondition(view.scroller.offset==500,"Initial current Space must center in the full viewport")
view.updateHeadings([SpacesBarDisplayHeading(name:"Display",start:14,width:1200)])
view.scroller.onOffsetChange = { [weak view] _ in view?.positionHeadings() }
for offset: CGFloat in [100,200,500] {
 view.scroller.scroll(to:offset,animated:false)
 let label = view.headingOverlay.subviews[0] as! NSTextField
 precondition(label.frame.minX==34,"Pinned labels must move synchronously with the scroller and keep app-header padding")
 precondition(label.font==SpacesBarLayout.headingTextFont)
 precondition(label.layer?.animationKeys()?.isEmpty != false,"Scrolling must not animate title frames")
}
for name in ["Built-in Retina Display", "DELL U2723QE", "Studio Display"] {
 let headings = [SpacesBarDisplayHeading(name:name,start:14,width:1200)]
 view.updateHeadings(headings)
 let label = view.headingOverlay.subviews[0] as! NSTextField
 let reference = NSTextField(labelWithString:name)
 reference.font=SpacesBarLayout.headingTextFont
 reference.sizeToFit()
 precondition(label.frame.width==reference.frame.width,"Native cell padding must be included in the title width")
 view.frame.size.width=30
 view.layout()
 precondition(label.frame.width==reference.frame.width,"Viewport width must not truncate a title that fits its section")
 view.updateHeadings(headings)
 precondition(label.frame.width==reference.frame.width,"Repeated refresh must not replace cached fitted widths with constrained widths")
 view.frame.size.width=900
 view.layout()
}
precondition(view.headingOverlay.hitTest(NSPoint(x:40,y:20)) == nil)

let moved=NSEvent.mouseEvent(with:.mouseMoved,location:NSPoint(x:895,y:20),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:0,pressure:0)!
  view.mouseMoved(with:moved)
  RunLoop.main.run(until:Date().addingTimeInterval(0.12))
  precondition(view.scroller.offset>500,"Shared edge scrolling must advance while hovered")
  view.mouseExited(with:moved)
  let stopped=view.scroller.offset
  RunLoop.main.run(until:Date().addingTimeInterval(0.08))
  precondition(view.scroller.offset==stopped,"Leaving the edge must stop scrolling")
  view.edgeScrolling=false
  view.mouseMoved(with:moved)
  RunLoop.main.run(until:Date().addingTimeInterval(0.08))
  precondition(view.scroller.offset==stopped,"Disabled edge scrolling must not start a timer")
  view.scroller.contentSize=CGSize(width:900,height:56)
  precondition(view.scroller.maxOffset==0 && view.scroller.offset==0)
  view.scroller.stopEdgeScroll()
  window.orderOut(nil)
  print("PASS native Spaces viewport: measured production-pill dimensions, full-width layout, initial centering, shared edge scrolling, exit/disable cleanup and nonoverflow clamping; no user-window events")
 }
}
SWIFT
Dir.mktmpdir('dockfork-space-viewport-') do |dir|
  File.write("#{dir}/checks.swift",native_source)
  abort 'Native Space viewport compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
  abort 'Native Space viewport checks failed' unless system("#{dir}/checks")
end

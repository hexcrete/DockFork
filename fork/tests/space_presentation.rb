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
util = File.read("#{root}/DockDoor/Utilities/Window Management/WindowUtil.swift")
ordering_source = <<~'SWIFT'
import Foundation
typealias CGWindowID = UInt32
let kCGNullWindowID: UInt32 = 0
let kCGWindowNumber = "number"
enum WindowListOption { case excludeDesktopElements }
var windowListReads = 0
func CGWindowListCopyWindowInfo(_ options: [WindowListOption], _ relative: UInt32) -> Any? {
 windowListReads += 1
 return [["number": NSNumber(value: 1)], ["number": NSNumber(value: 2)]]
}
struct App { let processIdentifier: Int }
struct WindowInfo { let id: UInt32; let lastAccessedTime: Date; let app: App }
enum Ordering {
SWIFT
ordering_source += block(util, '    private static func spaceSwitchCandidatesByRecency(').sub('private static', 'static') + "\n}\n"
ordering_source += <<~'SWIFT'
@main struct OrderingChecks {
 static func main() {
  func w(_ id: UInt32, _ time: Double, _ pid: Int = 1) -> WindowInfo { .init(id: id, lastAccessedTime: Date(timeIntervalSince1970: time), app: App(processIdentifier: pid)) }
  let ranked = Ordering.spaceSwitchCandidatesByRecency([w(1,1), w(3,3), w(2,2)])
  precondition(ranked.map(\.id) == [3,2,1], "Focus recency must beat stacking order and missing WindowServer ranks")
  precondition(windowListReads == 1, "One existing window-list read, never one per comparison")
  let tied = Ordering.spaceSwitchCandidatesByRecency([w(5,1,9), w(2,1), w(4,1,2), w(1,1), w(3,1,2)])
  precondition(tied.map(\.id) == [1,2,3,4,5], "Equal timestamps retain stacking, PID and window-ID tie-breaks")
  precondition(Ordering.spaceSwitchCandidatesByRecency([]).isEmpty)
  print("PASS production Space-switch ordering: recency first, stacking/identity ties and unchanged single window-list read")
 }
}
SWIFT
Dir.mktmpdir('dockfork-space-order-') do |dir|
  File.write("#{dir}/checks.swift", ordering_source)
  abort 'Space ordering compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Space ordering checks failed' unless system("#{dir}/checks")
end
shared = File.read("#{root}/DockDoor/Utilities/Window Management/WindowDiscoveryShared.swift")
keybind_source = File.read("#{root}/DockDoor/Utilities/KeybindHelper.swift")
builder = block(keybind_source, '    private func buildSwitcherWindows(')
filter_source = <<~'SWIFT'
import Foundation
typealias CGSSpaceID = UInt64
enum SwitcherInvocationMode { case allWindows, currentSpaceOnly, currentMonitorCurrentSpace, activeAppCurrentSpace, currentMonitorOnly, activeAppOnly }
enum Key { case includeHiddenWindowsInSwitcher, showWindowsFromCurrentSpaceOnlyInSwitcher, showWindowsFromCurrentMonitorOnlyInSwitcher, excludeWindowlessAppsFromCurrentMonitorSwitcherScopes, excludeWindowlessAppsFromCurrentSpaceSwitcherScopes, showWindowlessAppsInSwitcher, limitSwitcherToFrontmostApp }
enum Defaults { static var hidden = true; static subscript(_ key: Key) -> Bool { key == .showWindowlessAppsInSwitcher || (key == .includeHiddenWindowsInSwitcher && hidden) } }
struct WindowInfo { let id: Int; let app: Int; let space: Int; var isMinimized = false; var isHidden = false; var isWindowlessApp = false; var appHidden = false; var isEffectivelyHiddenForUI: Bool { isHidden || appHidden } }
struct PreviewWindowIdentity: Hashable { let id: Int; init(_ w: WindowInfo) { id = w.id } }
enum WindowUtil {
 static var all = [WindowInfo(id: 1, app: 1, space: 1), WindowInfo(id: 2, app: 1, space: 2), WindowInfo(id: 3, app: 2, space: 2, isHidden: true)]
 static func getAllWindowsOfAllApps() -> [WindowInfo] { all }
 static func getAllWindowsIgnoringSwitcherFilters() -> [WindowInfo] { all }
 static func collapseNativeTabsIfNeeded(_ w: [WindowInfo]) -> [WindowInfo] { w }
 static func filterWindowsByCurrentSpace(_ w: [WindowInfo]) -> [WindowInfo] { w.filter { $0.space == 1 } }
 static func filterWindowsByCurrentMonitor(_ w: [WindowInfo]) -> [WindowInfo] { w.filter { $0.space == 1 } }
 static func getWindowsForFrontmostApp(from w: [WindowInfo]) -> [WindowInfo] { w.filter { $0.app == 1 } }
 static func sortWindowsForSwitcher(_ w: [WindowInfo]) -> [WindowInfo] { w }
 static func sortWindowsForSwitcherByRecency(_ w: [WindowInfo]) -> [WindowInfo] { w }
 static func groupWindowsByApp(_ w: [WindowInfo]) -> [WindowInfo] { var seen = Set<Int>(); return w.filter { seen.insert($0.app).inserted } }
 static func getWindowlessRunningApps(existingWindows: [WindowInfo]) -> [WindowInfo] { [.init(id: 0, app: 3, space: 1, isWindowlessApp: true)] }
}
@MainActor final class Builder {
SWIFT
filter_source += builder.sub('private func ', 'func ') + "\n" + block(keybind_source, '    private func isActiveAppMode(') + "\n}\n"
filter_source += <<~'SWIFT'
@main struct FilterChecks {
 @MainActor static func main() {
  let b = Builder(), members = Set(WindowUtil.all.filter { $0.space == 2 }.map(PreviewWindowIdentity.init))
  precondition(b.buildSwitcherWindows(mode: .currentMonitorCurrentSpace).map(\.id) == [1,0])
  precondition(b.buildSwitcherWindows(mode: .currentMonitorCurrentSpace, spaceMembers: members).map(\.id) == [2,3], "Space filter overrides spatial scope before grouping and omits placeholders")
  precondition(b.buildSwitcherWindows(mode: .activeAppCurrentSpace, spaceMembers: members).map(\.id) == [2], "Active-app exclusion must survive Space override")
  Defaults.hidden = false
  precondition(b.buildSwitcherWindows(mode: .currentSpaceOnly, spaceMembers: members).map(\.id) == [2], "Hidden/minimized exclusion must survive Space override")
  let hiddenApp = WindowInfo(id: 4, app: 4, space: 2, appHidden: true)
  WindowUtil.all.append(hiddenApp)
  precondition(b.buildSwitcherWindows(mode: .currentSpaceOnly, spaceMembers: members.union([PreviewWindowIdentity(hiddenApp)])).map(\.id) == [2], "App-level hidden state must remain excluded")
  precondition(b.buildSwitcherWindows(mode: .allWindows, spaceMembers: []).isEmpty, "Empty Space must not become an unfiltered invocation")
  precondition(b.buildSwitcherWindows(mode: .currentMonitorCurrentSpace).map(\.id) == [1,0], "Clearing restores the invocation scope")
  print("PASS production Space filter builder: spatial override, clear restoration, grouping order, empty/fullscreen membership, hidden/app exclusions and placeholder omission")
 }
}
SWIFT
Dir.mktmpdir('dockfork-space-filter-') do |dir|
  File.write("#{dir}/checks.swift", filter_source)
  abort 'Space filter compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Space filter checks failed' unless system("#{dir}/checks")
end
state = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift")
publication_source = <<~'SWIFT'
import Combine
struct WindowInfo { let id: Int; var isWindowlessApp = false }
struct PreviewWindowIdentity: Hashable { let id: Int; init(_ window: WindowInfo) { id = window.id } }
final class PublicationProbe: ObservableObject {
 @Published private var storedWindows: [WindowInfo] = []
 var activeSpaceMembers: Set<PreviewWindowIdentity>?
 var invalidations = 0
 func invalidateFilterCache() { invalidations += 1 }
SWIFT
publication_source += block(state, '    var windows: [WindowInfo] {') + "\n}\n"
publication_source += <<~'SWIFT'
@main struct PublicationChecks {
 static func main() {
  let probe = PublicationProbe(), a = WindowInfo(id: 1), b = WindowInfo(id: 2)
  var publications = 0
  let subscription = probe.objectWillChange.sink { publications += 1 }
  probe.windows = [a,b]
  precondition(publications == 1 && probe.windows.count == 2)
  probe.activeSpaceMembers = [PreviewWindowIdentity(b)]
  for _ in 0..<100 { probe.windows = [a,b,WindowInfo(id: 0, isWindowlessApp: true)] }
  precondition(publications == 101 && probe.invalidations == 101 && probe.windows.map(\.id) == [2], "Filtered replacement must publish once without observer/setter recursion")
  probe.windows.append(a)
  precondition(publications == 102 && probe.windows.map(\.id) == [2], "In-place updates must share filtering before publication")
  probe.activeSpaceMembers = []
  probe.windows = [a,b]
  precondition(publications == 103 && probe.windows.isEmpty)
  probe.activeSpaceMembers = nil
  probe.windows = [a,b]
  precondition(publications == 104 && probe.windows.count == 2)
  withExtendedLifetime(subscription) {}
  print("PASS production Combine window publication: repeated filtered writes, in-place mutation, empty membership, clearing and exactly one publication/invalidation per write")
 }
}
SWIFT
Dir.mktmpdir('dockfork-filter-publication-') do |dir|
  File.write("#{dir}/checks.swift", publication_source)
  abort 'Window publication compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Window publication checks failed' unless system("#{dir}/checks")
end
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
%w[enableSpacesBar spacesBarItemSize spacesBarPreferDetails spacesBarMinimumWidth spacesBarLabels spacesBarFixedWidth spacesBarMaximumWidth spacesBarPillWidth spacesBarHideWhenSingle spacesBarFilterWindows spacesBarActivateAppIcons spacesBarShowAppIcons].each do |key|
  abort "Unwired bar setting #{key}" unless settings.include?("windowSwitcher.#{key}") && catalog.include?("windowSwitcher.#{key}") && reset.include?("Defaults[.#{key}] = Defaults.Keys.#{key}.defaultValue")
end
%w[spacesBarShowAppIcons spacesBarItemSize spacesBarLabels spacesBarFixedWidth spacesBarPreferDetails spacesBarMinimumWidth spacesBarMaximumWidth spacesBarPillWidth].each do |key|
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
activation = block(panel, '    private func activateSpace(')
app_activation = block(panel, '    private func activateSpaceApp(')
abort 'Icon activation must confirm a real resident target and protect reopened sessions' unless app_activation.include?('current.windowIdentities.first(where:') && app_activation.include?('await window.bringToFrontConfirmed()') && app_activation.include?('session == windowSwitcherCoordinator.pointerInteractionSessionID') && app_activation.index('if succeeded') < app_activation.index('appDelegate.dismissPreviews()') && !app_activation.include?('application.activate(')
abort 'Space activation must dismiss through the shared lifecycle before both occupied/empty transitions' unless activation.index('appDelegate.dismissPreviews()') < activation.index('WindowUtil.switchToManagedSpace')
abort 'A late switch completion must not dismiss a reopened switcher' if activation.split('WindowUtil.switchToManagedSpace',2).last.include?('hideWindow()')
abort 'Count must overlay the icon slot alongside the shared badge component' unless bar.include?('.overlay(alignment: .bottomTrailing)') && bar.include?('PreviewAppIcon(icon: app.application.icon') && bar.include?('@Default(.switcherShowAppIconBadges)') && bar.include?('@Default(.switcherAppIconBadgeScale)')
count_style = bar.split('Text("\(app.windowCount)")',2).last&.split('.accessibilityHidden(true)',2)&.first
abort 'Subscript must not have badge-like decoration' if count_style.nil? || count_style.match?(/\.shadow\(|\.background\(/)
pill_style = block(bar, '    private func pill(')
label_region = pill_style.split('ZStack(alignment: .leading)', 2).last&.split('ForEach(', 2)&.first
abort 'Filter label must retain stable child views and full-size symbol geometry' unless label_region && !label_region.include?('if filteredSpace') && !label_region.include?('if titleParts') && !label_region.include?('.transition(') && label_region.include?('width: SpacesBarLayout.clearSymbolSize') && label_region.include?('.allowsHitTesting(filteredSpace == entry.id)')
abort 'Clear filter must precede the Space label' unless pill_style.index('Button(action: clearFilter)') < pill_style.index('Text(title).lineLimit(1)')
abort 'Filter label must slide within its reserved slot using shared animation policy' unless label_region.include?('.offset(x: titleParts.button + titleParts.spacing)') && label_region.include?('.previewControlVisibilityAnimation(') && label_region.include?('-SpacesBarLayout.minimumLabelWidth')
abort 'Bar refresh must not recommit unchanged native scroll geometry' unless bar.include?('if view.scroller.contentSize != contentSize') && bar.include?('if view.hosting.frame != contentFrame')
abort 'Space cards must share preview-card styling and centered labels' unless pill_style.include?('.previewCardChrome(') && pill_style.include?('hideBackground: hideCardBackground') && pill_style.include?('uniformCardRadius: uniformCardRadius') && !pill_style.include?('.materialPill(') && pill_style.include?('frame(width: titleWidth, height:')
abort 'Space cards must honor active-border visibility and actual hover independently' unless bar.include?('@Default(.showActiveWindowBorder)') && pill_style.include?('isHighlighted: (enableMouseHoverInSwitcher && viewport.hoveredSpaceID == entry.id) || highlightedSpace == entry.id, isActiveWindow: showActiveWindowBorder && entry.isCurrent') && pill_style.include?('highlightColor: highlightColor ?? Color(nsColor: .controlAccentColor)') && pill_style.include?('.onContinuousHover { phase in')
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
source += "import AppKit\nextension CompactModeItemSize {\n" + block(font_sizes, '    var primaryAppKitFont:') + "\n}\nextension SpacesBarItemSize {\n" + block(font_space_sizes, '    var primaryAppKitFont:') + "\n}\n"
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
layout = layout.lines.reject { |line| line.include?('static var font:') || line.include?('static var headingFont:') || line.include?('static var headingTextFont:') || line.include?('static var headingHeight:') }.join
source += layout.sub("enum SpacesBarLayout {", "enum SpacesBarLayout {\n static var headingHeight: CGFloat { 14 * scale }") + "\n"
source += block(bar, 'enum SpacesBarAppLayout {') + "\n"
source += block(state, '    enum SpaceNavigationRequest:') + "\n"
source += "func navigationIndex(ids:[UInt64],current:UInt64?,highlightedSpaceID:UInt64?,backward:Bool,startNext:Bool)->Int { SpaceNavigationRequest.cycle(backward:backward).targetIndex(ids:ids,current:current,highlighted:highlightedSpaceID,startNext:startNext)! }\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() {
  precondition(navigationIndex(ids:[1,2,3],current:2,highlightedSpaceID:nil,backward:false,startNext:true)==2)
  precondition(navigationIndex(ids:[1,2,3],current:2,highlightedSpaceID:nil,backward:true,startNext:true)==0)
  precondition(navigationIndex(ids:[1,2,3],current:2,highlightedSpaceID:nil,backward:false,startNext:false)==1)
  precondition(navigationIndex(ids:[1,2,3],current:2,highlightedSpaceID:3,backward:false,startNext:false)==0)
  precondition(SpaceNavigationRequest.current.targetIndex(ids:[1,2,3],current:2,highlighted:nil,startNext:true)==1, "Scripted focus must not apply cycle-entry advance")
  precondition(SpaceNavigationRequest.cycle(backward:true).targetIndex(ids:[1,2,3],current:1,highlighted:nil,startNext:true)==2)
  precondition(SpaceNavigationRequest.current.targetIndex(ids:[],current:2,highlighted:nil,startNext:true)==nil)
  for width: CGFloat in [8,14,20,26,100,240] {
   let parts = SpacesBarLayout.titleParts(width:width,filtered:true,spacing:6)
   precondition(abs(parts.button + parts.text + parts.spacing - width) < 0.001 && parts.text >= 0 && parts.button <= width)
   precondition(SpacesBarLayout.titleParts(width:width,filtered:false,spacing:6).text == width)
  }
  precondition(SpacesBarLayout.widths(ideal:[200,300],labels:[40,60],maximum:240,available:600,fixed:false)==[200,240])
  precondition(SpacesBarLayout.widths(ideal:[200,300],labels:[48,60],maximum:240,available:108,fixed:false)==[48,60])
  precondition(SpacesBarLayout.widths(ideal:[200,300],labels:[48,60],maximum:240,available:1,fixed:false)==[48,60], "Only label widths constrain shrinking; overflow then scrolls")
  precondition(SpacesBarLayout.widths(ideal:[200,300],labels:[40,60],maximum:240,available:100,fixed:true)==[240,240])
  precondition(SpacesBarLayout.widths(ideal:[],labels:[],maximum:240,available:600,fixed:false).isEmpty)
  precondition(SpacesBarLayout.widths(ideal:[10,30],labels:[8,28],maximum:240,available:100,fixed:false)==[48,48], "Short labels must use the shared Space indicator ratio")
  precondition(SpacesBarLayout.reservation(displayCount:1,search:true)==108)
  precondition(SpacesBarLayout.reservation(displayCount:1,search:false)==80)
  for fraction: CGFloat in [0,0.1,0.49,0.5,0.9] {
   let fitted = SpacesBarLayout.windowSize(CGSize(width:240+fraction,height:300+fraction),maximum:CGSize(width:600.8,height:500.8))
   precondition(fitted.width == ceil(240+fraction) && fitted.height == ceil(300+fraction))
   let clamped = SpacesBarLayout.windowSize(CGSize(width:900,height:900),maximum:CGSize(width:600.8,height:500.8))
   precondition(clamped == CGSize(width:600,height:500), "Native integral sizing must not round beyond the available area")
  }
  for size in SpacesBarItemSize.allCases {
   Defaults.size = size
   let scale = size.scale
   precondition(abs(SpacesBarLayout.pillHeight - 40 * scale) < 0.001)
   precondition(abs(SpacesBarAppLayout.iconSize - 24 * scale) < 0.001)
   precondition(abs(SpacesBarAppLayout.countFontSize - 9 * scale) < 0.001)
   precondition(abs(SpacesBarAppLayout.spacing - 6 * scale) < 0.001)
   precondition(SpacesBarLayout.minimumPillWidth >= SpacesBarLayout.pillHeight)
   let label = SpacesBarLayout.labelWidth(1, fullscreen:false) - SpacesBarLayout.horizontalInset * 2
   precondition(label >= SpacesBarLayout.clearSymbolSize)
   let parts = SpacesBarLayout.titleParts(width:SpacesBarLayout.minimumLabelWidth, filtered:true, spacing:6*scale)
   precondition(parts.button >= SpacesBarLayout.clearSymbolSize && parts.text == 0, "Numeric labels must fit the same full-size symbol as names")
   precondition(SpacesBarLayout.height(displayCount:1) > SpacesBarLayout.pillHeight)
   precondition(SpacesBarLayout.height(displayCount:2).rounded() == SpacesBarLayout.height(displayCount:2), "Reservation and native panel height must use the same integral size")
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
for fraction: CGFloat in [0,0.1,0.49,0.5,0.9] {
 let grid = CGRect(x:100,y:100,width:301,height:500)
 let bar = SpacesBarLayout.frame(grid:grid,size:CGSize(width:400+fraction,height:124+fraction),screen:CGRect(x:0,y:0,width:2000,height:2000),search:true,alignment:0.5)
 precondition(bar == bar.integral, "Companion target frames must survive AppKit rounding unchanged")
 let searchBottom = SpacesBarLayout.searchY(gridTop:grid.maxY)
 let pillInset: CGFloat = 5.375
 let lowerGap = searchBottom + pillInset - (grid.maxY-SpacesBarLayout.outerPadding)
 let upperGap = bar.minY+SpacesBarLayout.outerPadding - (searchBottom+SearchWindow.searchHeight-pillInset)
 precondition(lowerGap == upperGap, "Search capsule's symmetric insets must leave equal visible gaps")
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

# Exercise mouse-owned Space navigation without changing a real session or pointer.
hover_source = <<~'SWIFT'
import Foundation
import CoreGraphics
typealias CGSSpaceID = UInt64
enum Key { case enableSpacesBar, enableMouseHoverInSwitcher }
enum Defaults {
 static var enabled = true, hover = false
 static subscript(_ key: Key) -> Bool { key == .enableSpacesBar ? enabled : hover }
}
enum NSEvent { static var mouseLocation = CGPoint.zero }
@MainActor final class HoverState {
 var isDraggingPreview = false
 var mouseHighlightedSpaceID: CGSSpaceID?
 enum SelectionInputSource { case programmatic, keyboard, mouse }
 enum NavigationTarget: Equatable { case windows, space(CGSSpaceID) }
 var navigationTarget = NavigationTarget.windows
 var spaceNavigationInputSource = SelectionInputSource.programmatic
 var windowSwitcherActive = true, isPointerSelecting = false, pointerInteractionReady = true, hasMovedSinceOpen = false
 var initialHoverLocation: CGPoint? = .zero
 var currIndex = 4, writes = 0
 func setIndex(to index: Int, shouldScroll: Bool, source: SelectionInputSource) { currIndex = index; writes += 1 }
SWIFT
hover_source += block(state, '    func hoverSpace(') + "\n" + block(state, '    func registerMouseMovementSinceOpen(') + "\n}\n"
hover_source += <<~'SWIFT'
@main struct HoverChecks {
 @MainActor static func main() {
  let state = HoverState()
  NSEvent.mouseLocation = CGPoint(x: 20, y: 0)
  state.hoverSpace(2, hovering: true)
  precondition(state.navigationTarget == .windows && state.writes == 0, "Disabled hover must not affect navigation")
  Defaults.hover = true
  state.pointerInteractionReady = false
  state.hoverSpace(2, hovering: true)
  precondition(state.writes == 0)
  state.pointerInteractionReady = true
  NSEvent.mouseLocation = .zero
  state.hoverSpace(2, hovering: true)
  precondition(state.writes == 0, "Stationary pointer must not steal keyboard navigation")
  NSEvent.mouseLocation = CGPoint(x: 20, y: 0)
  state.hoverSpace(2, hovering: true)
  precondition(state.navigationTarget == .space(2) && state.spaceNavigationInputSource == .mouse && state.currIndex == -1)
  state.hoverSpace(2, hovering: true)
  precondition(state.writes == 1, "Movement within the same pill must not repeat selection work")
  state.navigationTarget = .windows; state.spaceNavigationInputSource = .programmatic
  state.hasMovedSinceOpen = false; state.initialHoverLocation = NSEvent.mouseLocation
  NSEvent.mouseLocation = CGPoint(x: 40, y: 0)
  for _ in 0..<50 { state.hoverSpace(2, hovering: true) }
  precondition(state.navigationTarget == .windows && state.writes == 1, "Clearing the filter must survive continued movement within its pill")
  state.hoverSpace(2, hovering: false)
  state.hoverSpace(2, hovering: true)
  precondition(state.navigationTarget == .space(2) && state.writes == 2, "Leaving and re-entering must permit a new highlight")
  state.hoverSpace(3, hovering: true)
  state.hoverSpace(2, hovering: false)
  precondition(state.navigationTarget == .space(3), "Late exit must not clear another pill")
  state.hoverSpace(3, hovering: false)
  precondition(state.navigationTarget == .windows && state.currIndex == -1, "Leaving must not restore a stale window release target")
  state.hoverSpace(3, hovering: true)
  Defaults.hover = false
  state.hoverSpace(3, hovering: true)
  precondition(state.navigationTarget == .windows, "Disabling shared hover must clear mouse-owned navigation")
  state.hoverSpace(3, hovering: false)
  state.isDraggingPreview = true
  Defaults.hover = true
  let beforeDrag = state.writes
  state.hoverSpace(4, hovering: true)
  precondition(state.writes == beforeDrag, "A window drag must not change the Space highlight/filter")
  state.isDraggingPreview = false
  Defaults.hover = false
  precondition(state.mouseHighlightedSpaceID == nil, "Exit must clear hover-entry tracking even while shared hover is disabled")
  state.navigationTarget = .space(4); state.spaceNavigationInputSource = .keyboard
  state.hoverSpace(4, hovering: true)
  precondition(state.navigationTarget == .space(4), "Disabling mouse hover must preserve keyboard navigation")
  Defaults.hover = true
  state.hoverSpace(4, hovering: false)
  precondition(state.navigationTarget == .space(4), "Mouse exit must retain keyboard-owned selection")
  state.isPointerSelecting = true
  state.hoverSpace(5, hovering: true)
  precondition(state.navigationTarget == .space(4), "Checkbox sweep must not become Space navigation")
  state.isPointerSelecting = false; state.windowSwitcherActive = false
  state.hoverSpace(5, hovering: true)
  precondition(state.navigationTarget == .space(4), "Stale callbacks must not change a closed session")
  print("PASS production Space hover: opt-in, pointer readiness/movement, stable targets, exit/input ownership, sweep and session guards")
 }
}
SWIFT
Dir.mktmpdir('dockfork-space-hover-') do |dir|
  File.write("#{dir}/checks.swift", hover_source)
  abort 'Space hover compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Space hover checks failed' unless system("#{dir}/checks")
end

activation_source = <<~'SWIFT'
import Foundation
struct PreviewWindowIdentity: Hashable { let id: Int; init(_ w: Window) { id = w.id } }
enum Key { case spacesBarActivateAppIcons, spacesBarShowAppIcons }
enum Defaults { static var enabled = true, iconsVisible = true; static subscript(_ key: Key) -> Bool { key == .spacesBarShowAppIcons ? iconsVisible : enabled } }
enum NSSound { static var beeps = 0; static func beep() { beeps += 1 } }
final class AppDelegate { var dismissals = 0; func dismissPreviews() { dismissals += 1 } }
enum NSApp { static var delegate: AnyObject? = AppDelegate() }
struct Application { let processIdentifier: Int }
enum ManagedSpacePresentation {
 struct App { let application: Application; let windowIdentities: [PreviewWindowIdentity] }
 struct Entry { let id: Int; let apps: [App] }
 struct Display { let spaces: [Entry] }
}
@MainActor final class Window {
 let id: Int; var success = true, calls = 0, warps = 0; var onActivation: (() -> Void)?
 init(_ id: Int) { self.id = id }
 func bringToFrontConfirmed() async -> Bool { calls += 1; onActivation?(); return success }
 func warpMouseToCenterIfNeeded() { warps += 1 }
}
@MainActor enum WindowUtil { static var windows: [Window] = []; static func getAllWindowsIgnoringSwitcherFilters() -> [Window] { windows } }
final class State { var windowSwitcherActive = true, pointerInteractionSessionID = 1 }
@MainActor final class ActivationProbe {
 var isVisible = true, windowSwitcherCoordinator = State()
 var spacesBarSections: [ManagedSpacePresentation.Display] = []
 func hideWindow() { isVisible = false }
SWIFT
activation_source += app_activation.sub('private func ', 'func ') + "\n}\n"
activation_source += <<~'SWIFT'
@main struct ActivationChecks {
 @MainActor static func main() async {
  let a = Window(1), b = Window(2), probe = ActivationProbe()
  let app = ManagedSpacePresentation.App(application: Application(processIdentifier: 3), windowIdentities: [PreviewWindowIdentity(b), PreviewWindowIdentity(a)])
  let entry = ManagedSpacePresentation.Entry(id: 5, apps: [app])
  probe.spacesBarSections = [.init(spaces: [entry])]; WindowUtil.windows = [a,b]
  let delegate = NSApp.delegate as! AppDelegate
  Defaults.enabled = false
  await probe.activateSpaceApp(app, in: entry)
  precondition(a.calls == 0 && b.calls == 0)
  Defaults.enabled = true; Defaults.iconsVisible = false
  await probe.activateSpaceApp(app, in: entry)
  precondition(a.calls == 0 && b.calls == 0, "Hidden icons cannot activate resident windows")
  Defaults.iconsVisible = true
  await probe.activateSpaceApp(app, in: entry)
  precondition(b.calls == 1 && a.calls == 0 && delegate.dismissals == 1 && b.warps == 1, "Resident order, not cache order, selects the leading target")
  b.success = false
  await probe.activateSpaceApp(app, in: entry)
  precondition(delegate.dismissals == 1 && NSSound.beeps == 1, "Failure must retain previews")
  b.success = true; b.onActivation = { probe.windowSwitcherCoordinator.pointerInteractionSessionID += 1 }
  await probe.activateSpaceApp(app, in: entry)
  precondition(delegate.dismissals == 1 && b.warps == 1, "Stale completion must not dismiss or warp a newer session")
  b.onActivation = nil; WindowUtil.windows = [a]
  await probe.activateSpaceApp(app, in: entry)
  precondition(a.calls == 1 && delegate.dismissals == 2, "Missing leading identity must use the next known resident")
  WindowUtil.windows = []
  await probe.activateSpaceApp(app, in: entry)
  precondition(delegate.dismissals == 2 && NSSound.beeps == 2, "No real target must refuse without generic app activation")
  print("PASS production Space app activation: gating, resident ordering, missing targets, confirmation, failure and stale-session guards")
 }
}
SWIFT
Dir.mktmpdir('dockfork-space-app-') do |dir|
  File.write("#{dir}/checks.swift", activation_source)
  abort 'Space activation compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Space activation checks failed' unless system("#{dir}/checks")
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
native_source += block(bar, 'final class SpacesBarHostedState:') + "\n" + block(bar, 'struct SpacesBarHostedContent:') + "\n"
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
 static let itemSpacing: CGFloat = 12
 static let dividerWidth: CGFloat = 1
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
 struct App { let application: NSRunningApplication; let windowCount: Int; var windowIdentities: [UInt64] { windowCount > 0 ? [1] : [] } }
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
native_source += "final class PreviewStateCoordinator { weak var spaceDragViewport: SpacesBarScroll.ViewportView? }\n"
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
 static let innerPadding: CGFloat = 2
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
animation_source = File.read("#{root}/DockDoor/Extensions/SwiftUIUtils.swift")
native_source += block(File.read("#{root}/DockDoor/Views/Hover Window/WindowPreviewInteractionModifier.swift"), 'struct PreviewDragTargetHighlight:') + "\n"
native_source += block(animation_source, 'enum PreviewControlAnimation {') + "\n" + block(animation_source, 'private struct PreviewControlVisibilityAnimation:') + "\n"
native_source += "extension View {\n" + block(animation_source, '    func previewControlVisibilityAnimation(') + "\n}\n"
native_source += "extension SpacesBarLayout {\n" + bar.lines.grep(/static var (clearSymbolSize|minimumLabelWidth):/).join + block(bar, '    static func titleParts(') + "\n}\n"
native_source += <<~'SWIFT'
struct PillProbe: View {
 let showAnimations = false
 let controlAnimationDuration = 0.1
 let showAppIcons = true
 let activateAppIcons = false
 let enableMouseHoverInSwitcher = true
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
 var filteredSpace: UInt64? = nil
 func clearFilter() {}
 let highlightedSpace: UInt64? = nil
 let labels = SpaceMenuDisplayMode.numberOnly
 func activate(_ entry: ManagedSpacePresentation.Entry) {}
 func hover(_ id: UInt64, _ hovering: Bool) {}
 func activateApp(_ app: ManagedSpacePresentation.App, _ entry: ManagedSpacePresentation.Entry) {}
 var body: some View { pill(ManagedSpacePresentation.Entry(label:label)).fixedSize() }
SWIFT
native_source += block(bar, '    private func pill(') + "\n}\n"
native_source += "struct AppSlotProbe: View {\n let count: Int\n let showBadges = false\n let badgeScale: CGFloat = 1\n var body: some View {\n  let app = ManagedSpacePresentation.App(application:NSRunningApplication.current,windowCount:count)\n"
native_source += "                    PreviewAppIcon(icon: app.application.icon, bundleURL: app.application.bundleURL,\n                                   size: SpacesBarAppLayout.iconSize, showBadge: showBadges,\n                                   badgeScale: badgeScale, mockPreviewActive: false)\n                        .overlay(alignment: .bottomTrailing) {\n                            if app.windowCount > 1 {\n                                Text(\"\(app.windowCount)\")\n                                    .font(.system(size: SpacesBarAppLayout.countFontSize, weight: .bold))\n                                    .foregroundStyle(.primary)\n                                    .offset(x: 2, y: 4)\n                            }\n                        }\n    " + "\n }\n}\n"
native_source += "enum HoverContainerPadding { static let container: CGFloat = 24; static let dockStyleOuter: CGFloat = 2 }\n"
native_source += "enum SharedPreviewWindowCoordinator { struct Instance { let spacesBarReservation: CGFloat = 1 }; static let activeInstance: Instance? = Instance() }\n"
native_source += "class SearchWindow: NSPanel { static let searchWidth: CGFloat = 300; static let searchHeight: CGFloat = 40; static let panelEdgeOffset: CGFloat = -4\n" + block(bar, '    func targetFrame(relativeTo frame:') + "\n}\n"
native_source += "extension SpacesBarLayout { static let outerPadding: CGFloat = 26; static let gap: CGFloat = 8\n"
native_source += bar.lines.find { |line| line.include?('static var searchGap:') }.strip + "\n"
native_source += bar.lines.find { |line| line.include?('static func searchY(') }.strip + "\n"
native_source += block(bar, '    static func frame(grid:') + "\n}\n"
native_source += "extension SpacesBarLayout {\n" + block(bar, '    static func windowSize(') + "\n}\n"
native_source += <<~'SWIFT'
final class CompanionProbe: NSPanel {
 var isPositioningCompanions = false
 var searchWindow: SearchWindow?
 var spacesBarWindow: SpacesBarWindow?
 var panelAnchor: (screen: NSScreen, origin: (CGSize) -> CGPoint)?
 var spaceFilterTop: CGFloat?
 let spacesBarSections = [1]
 let windowSwitcherCoordinator = (windowSwitcherActive: true, unused: false)
 func previewPlacementFrame(on screen: NSScreen) -> CGRect { screen.visibleFrame }
 func constrainHeaderTop(_ origin: CGPoint, windowSize: CGSize, screen: NSScreen) -> CGPoint { origin }
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
native_source += "struct PillFrameProbe {\n struct Item { let id: UInt64 }\n struct Section { let spaces: [Item] }\n let sections: [Section]\n let widths: [UInt64: CGFloat]\n    var dropFrames: [CGSSpaceID: CGRect] {\n        var x = SpacesBarLayout.innerPadding\n        let y = SpacesBarLayout.innerPadding + (sections.count > 1 ? SpacesBarLayout.headingHeight + 4 * SpacesBarLayout.scale : 0)\n        var frames: [CGSSpaceID: CGRect] = [:]\n        for (index, display) in sections.enumerated() {\n            if index > 0 { x += SpacesBarLayout.itemSpacing + SpacesBarLayout.dividerWidth }\n            for entry in display.spaces {\n                let width = widths[entry.id] ?? SpacesBarLayout.pillHeight\n                frames[entry.id] = CGRect(x: x, y: y, width: width, height: SpacesBarLayout.pillHeight)\n                x += width + SpacesBarLayout.itemSpacing\n            }\n        }\n        return frames\n    }\n\n\n}\n"
native_source += "extension CompanionProbe {\n" + block(panel, '    private func anchoredOrigin(').sub('private func','func') + "\n}\n"
native_source += <<~'SWIFT'
enum SlideSamples { static var values: [CGFloat] = [] }
struct SlideProbe: AnimatableModifier {
 var position: CGFloat
 var animatableData: CGFloat { get { position } set { position = newValue } }
 func body(content: Content) -> some View {
  SlideSamples.values.append(position)
  return content.offset(x:position)
 }
}
@main struct NativeChecks {
 @MainActor static func main() {
  _ = NSApplication.shared
  guard !NSScreen.screens.isEmpty else { print("SKIP native Space viewport: no display access"); return }
let firstSection = PillFrameProbe.Section(spaces:[.init(id:1),.init(id:2)])
let lastSection = PillFrameProbe.Section(spaces:[.init(id:3)])
let itemWidths: [UInt64:CGFloat] = [1:100,2:200,3:120]
let singleFrames = PillFrameProbe(sections:[firstSection],widths:itemWidths).dropFrames
precondition(singleFrames[1] == CGRect(x:SpacesBarLayout.innerPadding,y:SpacesBarLayout.innerPadding,width:100,height:SpacesBarLayout.pillHeight))
precondition(singleFrames[2]!.minX == singleFrames[1]!.maxX + SpacesBarLayout.itemSpacing)
let multiFrames = PillFrameProbe(sections:[firstSection,lastSection],widths:itemWidths).dropFrames
precondition(multiFrames[3]!.minX == multiFrames[2]!.maxX + SpacesBarLayout.itemSpacing*2 + SpacesBarLayout.dividerWidth)
precondition(multiFrames[3]!.minY == SpacesBarLayout.innerPadding + SpacesBarLayout.headingHeight + 4*SpacesBarLayout.scale)
  let animationPanel = NSPanel(contentRect:CGRect(x:20,y:20,width:160,height:40),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  animationPanel.ignoresMouseEvents = true
  let animationViewport = SpacesBarScroll.ViewportView(frame:CGRect(x:0,y:0,width:160,height:40))
  animationViewport.hosting.frame = animationViewport.bounds
  animationPanel.contentView = animationViewport
  func slide(_ x: CGFloat) -> AnyView { AnyView(Color.gray.frame(width:20,height:20).modifier(SlideProbe(position:x))) }
  animationViewport.updateContent(slide(0),filteredSpace:nil,animation:nil)
  animationPanel.orderFront(nil)
  RunLoop.main.run(until:Date().addingTimeInterval(0.15))
  SlideSamples.values = []
  animationViewport.updateContent(slide(40),filteredSpace:1,animation:.linear(duration:0.3))
  RunLoop.main.run(until:Date().addingTimeInterval(0.06))
  SlideSamples.values = []
  animationViewport.updateContent(slide(40),filteredSpace:1,animation:.linear(duration:0.3))
  RunLoop.main.run(until:Date().addingTimeInterval(0.5))
  precondition(SlideSamples.values.contains { $0>0 && $0<40 }, "Hosted filter content must receive an animation transaction, not jump directly to the result")
  SlideSamples.values = []
  animationViewport.updateContent(slide(0),filteredSpace:nil,animation:nil)
  RunLoop.main.run(until:Date().addingTimeInterval(0.1))
  precondition(!SlideSamples.values.contains { $0>0 && $0<40 }, "Disabled motion must update the hosting root immediately")
  animationPanel.orderOut(nil)
  print("PASS native hosted content animation: real intermediate frames and immediate disabled-motion update")
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
let search = SearchWindow(contentRect:CGRect(x:0,y:0,width:300,height:40),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
search.alphaValue=0
parent.searchWindow=search
parent.addChildWindow(search,ordered:.above)
search.orderFront(nil)
let pinnedTop = original.maxY
parent.spaceFilterTop=pinnedTop
parent.panelAnchor=(screen,{ size in CGPoint(x:original.midX-size.width/2,y:original.midY-size.height/2) })
for (width,height): (CGFloat,CGFloat) in [(301.2,220.1),(301,300.49),(302.4,130.9),(301,299.5),(301.2,220.1),(301,300.49)] {
 let size=SpacesBarLayout.windowSize(CGSize(width:width,height:height),maximum:screen.visibleFrame.size)
 parent.setFrame(CGRect(origin:parent.anchoredOrigin(for:size)!,size:size),display:false)
 RunLoop.main.run(until:Date().addingTimeInterval(0.03))
 precondition(parent.frame.maxY == pinnedTop, "Fractional filtered heights must not move the stack's pinned top")
 precondition(search.frame == search.targetFrame(relativeTo:parent.frame,on:screen), "Search must match its exact integral target after native child movement")
 precondition(companion.frame == parent.spacesBarFrame(relativeTo:parent.frame,size:companion.frame.size,screen:screen), "Bar and search must share exact attachment geometry")
}
parent.removeChildWindow(search)
search.orderOut(nil)
parent.searchWindow=nil
parent.removeChildWindow(companion)
companion.orderOut(nil)
parent.spacesBarWindow=nil
parent.orderOut(nil)
  let captureProbe=SpacesBarWindow()
  let parentProbe=NSPanel()
  precondition(captureProbe.sharingType==parentProbe.sharingType,"Bar must not opt out of screenshots by default")
  for width: CGFloat in [48,100,240] {
   for label in ["1", "Desktop 12"] {
    for filtered: UInt64? in [nil,1] {
     let hosting=NSHostingView(rootView:PillProbe(width:width,label:label,filteredSpace:filtered))
     let size=hosting.fittingSize
     precondition(abs(size.width-width)<0.1 && abs(size.height-40)<0.1,"Rendered production pill must match allocated size with/without filter control: \(size)")
    }
   }
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
window.ignoresMouseEvents = true
window.orderFront(nil)
view.edgeScrolling = false
view.dropFrames = [1:CGRect(x:100,y:8,width:200,height:40),2:CGRect(x:320,y:8,width:200,height:40)]
view.desktopDropIDs = [1]
var dropID: UInt64?
view.onDropTargetChanged = { dropID = $0 }
func screenPoint(_ x: CGFloat, _ y: CGFloat = 20) -> CGPoint { window.convertPoint(toScreen:view.scroller.convert(CGPoint(x:x,y:y),to:nil)) }
view.updateDrag(at:screenPoint(150))
precondition(dropID==1 && view.spaceForDrop(at:screenPoint(150))==1)
view.updateDrag(at:screenPoint(400))
precondition(dropID==nil && view.spaceForDrop(at:screenPoint(400))==2,"Fullscreen pill remains a refusal hit, not an ordinary placement")
view.updateDrag(at:screenPoint(310));precondition(dropID==nil,"Pill gaps cannot receive window moves")
view.scroller.contentSize=CGSize(width:1600,height:56)
view.scroller.onOffsetChange = { [weak view] _ in view?.refreshDragTarget() }
view.updateDrag(at:screenPoint(150));precondition(dropID==1)
view.scroller.scroll(to:220,animated:false)
precondition(dropID==nil && view.spaceForDrop(at:screenPoint(150))==2,"Stationary drag must track live scroll offset")
view.updateDrag(at:nil);precondition(dropID==nil)
window.orderOut(nil)
precondition(view.spaceForDrop(at:screenPoint(150))==nil,"Hidden bar has no live drop targets")
print("PASS native Space drop hits: Desktop/fullscreen distinction, gaps, live scroll offsets, stationary pointer refresh and hidden/cancelled cleanup; test-owned panel only")
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

history = "import Foundation\ntypealias CGSSpaceID = UInt64\n"
%w[ManagedSpaceKind ManagedSpaceDescriptor ManagedDisplayDescriptor].each do |name|
 history += block(shared, name == 'ManagedSpaceKind' ? "enum #{name}:" : "struct #{name} {") + "\n"
end
history += block(shared, 'struct SpaceVisitHistory {') + "\n"
history += <<~'SWIFT'
@main struct HistoryChecks {
 static func main() {
  func display(_ current:UInt64, _ ids:[UInt64] = [1,2,3], _ name:String = "one") -> ManagedDisplayDescriptor {
   ManagedDisplayDescriptor(identifier:name,currentSpaceID:current,spaces:ids.map {ManagedSpaceDescriptor(id:$0,kind:.desktop,number:Int($0),desktopNumber:Int($0),ownerPIDs:[])})
  }
  var history = SpaceVisitHistory()
  precondition(history.ordered([1,2,3]) == [1,2,3])
  history.update([display(1)]); history.update([display(2)]); history.update([display(3)])
  precondition(history.ordered([1,2,3]) == [3,2,1])
  for _ in 0..<30 {history.update([display(3)])}
  precondition(history.ordered([1,2,3]) == [3,2,1], "Unchanged snapshots/highlighting cannot invent visits")
  history.update([display(3),display(4,[4,5],"two")])
  history.update([display(3),display(5,[4,5],"two")])
  precondition(history.ordered([1,2,3]) == [3,2,1] && history.ordered([4,5]) == [5,4])
  history.update([display(3,[1,3])]); history.update([display(3)])
  precondition(history.ordered([1,2,3]) == [3,1,2], "Deleted/reintroduced IDs must not inherit obsolete visit ranks")
  print("PASS Space visit ordering: sequential fallback, current/previous visits, empty Desktop metadata, unchanged snapshots, independent displays and removed IDs")
 }
}
SWIFT
Dir.mktmpdir('dockfork-space-visits-') do |dir|
 File.write("#{dir}/checks.swift",history)
 abort 'Space history compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Space history checks failed' unless system("#{dir}/checks")
end

abort 'Hidden Space icons must reserve no app width or render overflow' unless panel.include?('CGFloat(Defaults[.spacesBarShowAppIcons] ? entry.apps.count : 0)') && bar.include?('let apps = showAppIcons ? entry.apps : []') && bar.include?('total: apps.count, availableWidth: iconRoom') && bar.include?('count < apps.count')
abort 'Icon activation setting must remain editable with a visibility explanation' unless settings.include?('if !spacesBarShowAppIcons {') && settings.include?('Enable \"Appearance > Spaces Bar > Show app icons in the Spaces Bar\" to use this.') && !settings.include?('.disabled(!spacesBarShowAppIcons)')
puts 'PASS Space icon visibility: default-on preference wiring, Appearance search/reset, no hidden icon width/overflow and gated activation'

# Exercise the shared dropdown/drop executor with fake confirmed moves, never live windows.
util = File.read("#{root}/DockDoor/Utilities/Window Management/WindowUtil.swift")
drop_source = <<~'SWIFT'
import Foundation
struct PreviewWindowIdentity: Hashable { let id: Int; init(_ w: WindowInfo) { id = w.id } }
final class App { var isHidden = false; let processIdentifier = 1 }
struct WindowInfo {
 let id: Int; let app: App; var isMinimized = false
 @MainActor func bringToFrontConfirmed() async -> Bool { Model.focus.append(id); return true }
}
struct Space { let id: Int; let kind = Kind.desktop; enum Kind { case desktop, fullscreen } }
struct ManagedSpaceDestination { let space: Space }
final class WindowActionRequest { var allowed: Set<Int>; var mayForeground = true
 init(_ ids: [Int]) { allowed = Set(ids) }
 func contains(_ id: PreviewWindowIdentity) -> Bool { allowed.contains(id.id) }
}
enum Outcome: Equatable { case completed, failed, cancelled }
final class ActionFeedbackHandle {
 var results: [Int: Outcome] = [:]
 func finish(_ id: PreviewWindowIdentity, _ result: Outcome) { if results[id.id] == nil { results[id.id] = result } }
 func finishRemaining(_ result: Outcome) {}
}
@MainActor enum Model {
 static var members: [Int: Set<Int>] = [:], invalid = Set<Int>(), failures = Set<Int>(), pending = Set<Int>()
 static var issued: [Int] = [], focus: [Int] = [], cancels = 0, active = true, afterMove: (() -> Void)?
 static func reset() { members = [:]; invalid = []; failures = []; pending = []; issued = []; focus = []; cancels = 0; active = true; afterMove = nil }
}
@MainActor enum WindowSpaces {
 static func managedDisplays() -> [Int] { [1] }
 static func validateMoveSourceConfirmed(_ w: WindowInfo, in displays: [Int]) async -> Int? { Model.invalid.contains(w.id) ? 1 : nil }
 static func sourceSpaceIDs(for w: WindowInfo) -> Set<Int> { Model.members[w.id] ?? [1] }
}
@MainActor enum WindowUtil {
 struct PreviewBatchResult { var succeeded: [WindowInfo] = []; var failed: [PreviewWindowIdentity] = [] }
 static func readCachedWindows(for pid: Int) -> [WindowInfo] { [] }
 static func setHiddenStateConfirmed(for app: App, isHidden: Bool) async -> Bool { app.isHidden = isHidden; return true }
 static func setMinimizedWindowsConfirmed(_ ws: [WindowInfo], isMinimized: Bool) async -> [WindowInfo] { ws }
 static func performConfirmedSpaceMove(_ w: WindowInfo, to d: ManagedSpaceDestination, dismissPreviews: (() -> Void)?,
                                      switchToDestination: Bool, isRequestActive: @escaping () -> Bool,
                                      completion: @escaping (Bool) -> Void) -> (() -> Void)? {
  precondition(!switchToDestination)
  Model.issued.append(w.id)
  let task = Task { @MainActor in
   try? await Task.sleep(nanoseconds: UInt64(w.id == 1 ? 30_000_000 : 5_000_000))
   guard !Task.isCancelled, isRequestActive(), !Model.pending.contains(w.id) else { return }
   let success = !Model.failures.contains(w.id) && !Model.invalid.contains(w.id)
   if success { Model.members[w.id] = [d.space.id] }
   completion(success); Model.afterMove?()
  }
  return { Model.cancels += 1; task.cancel() }
 }
SWIFT
drop_source += block(util, '    static func movePreviewWindows(') + "\n}\n"
drop_source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async {
  let app = App(), windows = [1,2,3].map { WindowInfo(id: $0, app: app) }, destination = ManagedSpaceDestination(space: Space(id: 2))
  func run(_ ids: [Int], follows: Bool = false, mayFollow: Bool = true, feedback: ActionFeedbackHandle? = nil) async -> WindowUtil.PreviewBatchResult {
   await WindowUtil.movePreviewWindows(windows, to: destination, request: WindowActionRequest(ids), followsDestination: follows,
                                      dismissPreviews: nil, mayFollow: { mayFollow }, isRequestActive: { Model.active }, feedback: feedback)
  }
  Model.reset(); let feedback = ActionFeedbackHandle()
  let partial = await run([1,3], feedback: feedback)
  precondition(Set(partial.succeeded.map(\.id)) == [1,3] && partial.failed.map(\.id) == [2])
  precondition(Model.issued == [1,3] && Model.focus.isEmpty && feedback.results[2] == .failed && Model.cancels == 2)
  Model.reset(); Model.failures = [2]
  let mixed = await run([1,2,3], follows: true)
  precondition(mixed.failed.map(\.id) == [2] && Model.focus == [1], "Follow selected order, not callback order")
  Model.reset(); app.isHidden = true
  _ = await run([1,2,3], follows: false)
  precondition(app.isHidden && Model.focus.isEmpty, "No-follow preserves hidden state")
  Model.reset(); _ = await run([1,2,3], follows: true, mayFollow: false)
  precondition(Model.focus.isEmpty, "Dropdown stale-presentation follow guard")
  Model.reset(); Model.members[1] = [2]
  let sameAndMoved = await run([1,2,3])
  precondition(Model.issued == [2,3] && sameAndMoved.failed.isEmpty && sameAndMoved.succeeded.count == 3)
  Model.reset(); Model.members = [1:[2],2:[2],3:[2]]
  let noop = await run([1,2,3]); precondition(noop.failed.count == 3 && Model.issued.isEmpty)
  Model.reset(); Model.invalid = [2]
  let invalid = await run([1,2,3]); precondition(invalid.failed.map(\.id) == [2])
  Model.reset(); Model.active = false
  _ = await run([1,2,3]); precondition(Model.issued.isEmpty)
  Model.reset(); Model.pending = [1,2,3]
  let task = Task { @MainActor in await run([1,2,3]) }
  try? await Task.sleep(nanoseconds: 20_000_000); task.cancel(); _ = await task.value
  precondition(Model.cancels == 3 && Model.focus.isEmpty, "Cancellation closes pending moves without foregrounding")
  print("PASS shared Space batch executor: admission, partial failure, stable follow order, no-follow state, stale dropdown guard, existing-destination handling, invalid source, inactive request and cancellation cleanup; fake operations only")
 }
}
SWIFT
Dir.mktmpdir('dockfork-space-drops-') do |dir|
 File.write("#{dir}/checks.swift", drop_source)
 abort 'Shared Space move compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Shared Space move checks failed' unless system("#{dir}/checks")
end

container = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreviewHoverContainer.swift")
drop = block(container, '    private func completeSpaceDrop(')
finish = block(container, '    private func finishPreviewDrag(')
abort 'Space bar drops must take precedence over tiling and ordinary pointer placement' unless finish.index('containsSpacesBar(location)') < finish.index('completeTileDrop') && finish.include?('cancelPreviewDrag(token: session.token); return')
abort 'Drops must reuse released lifetime, ownership, shared move, target filtering and follow preference' unless %w[completeDrop movePreviewWindows beginPreviewActionRequest previewTargets switchToDestinationSpaceAfterMoving].all? { |term| drop.include?(term) } && !drop.include?('placeDraggedWindows') && !drop.include?('setWindowFrame')
abort 'Dropdown groups must use the same Space executor' unless block(panel, '    func performCheckedSpaceMove(').include?('WindowUtil.movePreviewWindows')
puts 'PASS Space drop route: bar-first refusal, common group move, ordered targets, ownership, retained operation lifetime, follow setting and no geometry placement'

abort 'Successful Space pill drops must keep previews open unless destination following dismisses them' if drop.include?('onWindowTap?()')
puts 'PASS Space drop dismissal: no ordinary drop/activation callback; only shared destination-follow dismissal'

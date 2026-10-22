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
model = block(shared, 'enum ManagedSpacePresentation {')
abort 'Space model must not retain screenshots or discover windows' if model.match?(/let \w+: (?:\[)?WindowInfo|\.image\b|\.axElement\b|Task\b|Timer\b|\.addObserver\b|getAllWindows/)

source = <<~'SWIFT'
import Foundation
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
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() {
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

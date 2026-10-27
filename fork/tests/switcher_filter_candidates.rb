#!/usr/bin/env ruby
require 'tmpdir'
def block(source, signature)
  start=source.index(signature) or abort "Missing #{signature}"
  opening=source.index(/\{\n/,start); depth=0
  (opening...source.length).each do |i|
    depth+=1 if source[i]=='{'; depth-=1 if source[i]=='}'
    return source[start..i] if depth.zero?
  end
  abort "Unclosed #{signature}"
end
root=File.expand_path('../..',__dir__)
keys=File.read("#{root}/DockDoor/Utilities/KeybindHelper.swift")
util=File.read("#{root}/DockDoor/Utilities/Window Management/WindowUtil.swift")
source=<<~'SWIFT'
import Foundation
import CoreGraphics
typealias CGSSpaceID=UInt64
typealias AXUIElement=Int
final class NSRunningApplication {
 let processIdentifier:Int32;let bundleIdentifier:String?;var localizedName:String?;var isTerminated=false
 init(_ pid:Int32){processIdentifier=pid;bundleIdentifier="app\(pid)";localizedName="App \(pid)"}
}
final class NSWorkspace {static let shared=NSWorkspace();var frontmostApplication:NSRunningApplication?;var runningApplications:[NSRunningApplication]=[]}
final class NSScreen {
 static var screens:[NSScreen]{[current]}
 var cgFrame:CGRect{CGRect(x:0,y:0,width:1000,height:1000)}
 static var current=NSScreen("one");let id:String
 init(_ id:String){self.id=id}
 static func screenFromQuartzPoint(_ point:CGPoint)->NSScreen{current}
 func uniqueIdentifier()->String{id}
}
enum DockObserver {static func getMousePosition()->CGPoint{.zero}}
enum DockPosition {case bottom}
enum SwitcherInvocationMode:CaseIterable {case allWindows,currentSpaceOnly,currentMonitorOnly,currentMonitorCurrentSpace,activeAppOnly,activeAppCurrentSpace}
enum WindowPreviewSortOrder {case recentlyUsed,creationOrder,screenPosition,alphabeticalByTitle,alphabeticalByAppName}
struct Key<T> {let name:String}
enum Defaults {static var values:[String:Any]=[:];static subscript<T>(_ key:Key<T>)->T {values[key.name] as! T}}
SWIFT
bools=%w[enableSpacesBar includeHiddenWindowsInSwitcher limitSwitcherToFrontmostApp showWindowsFromCurrentSpaceOnlyInSwitcher showWindowsFromCurrentMonitorOnlyInSwitcher showWindowlessAppsInSwitcher excludeWindowlessAppsFromCurrentMonitorSwitcherScopes excludeWindowlessAppsFromCurrentSpaceSwitcherScopes collapseNativeTabsIntoSingleWindow sortMinimizedToEnd]
source+="extension Key where T==Bool {\n"+bools.map{|s|"static var #{s}:Self {.init(name:\"#{s}\")}"}.join("\n")+"\n}\n"
source+=<<~'SWIFT'
extension Key where T==[String] {
 static var groupedAppsInSwitcher:Self{.init(name:"groupedAppsInSwitcher")}
 static var appNameFilters:Self{.init(name:"appNameFilters")}
}
extension Key where T==WindowPreviewSortOrder {static var windowSwitcherSortOrder:Self{.init(name:"windowSwitcherSortOrder")}}
struct WindowInfo {
 var frame=CGRect.zero
 let id:UInt32;let app:NSRunningApplication;var space:UInt64=1;var monitor="one";var image=0
 var isMinimized=false,isHidden=false,isWindowlessApp=false,isNativeRepresentative=true
 var windowName:String?;var lastAccessedTime=Date.distantPast,creationTime=Date.distantPast
 var axOverride:Int?;var axElement:Int{axOverride ?? Int(id)}
 var isEffectivelyHiddenForUI:Bool{isHidden}
 static func windowlessEntry(for app:NSRunningApplication)->Self{Self(id:0,app:app,isWindowlessApp:true)}
}
struct PreviewWindowIdentity:Hashable {
 let pid:Int32;let windowID:UInt32
 init(pid:Int32,windowID:UInt32){self.pid=pid;self.windowID=windowID}
 init(_ w:WindowInfo){self.init(pid:w.app.processIdentifier,windowID:w.id)}
}
final class Cache {
 var revision:UInt=0,windows:[WindowInfo]=[]
 func readSnapshot()->(revision:UInt,windows:[WindowInfo]){(revision,windows)}
}
enum WindowUtil {
 static let desktopSpaceWindowCacheManager=Cache()
 static var collections=0,sorts=0,groups=0,collapses=0,spaceReads=0
 static var activeSpace:UInt64=1
 static func evictTerminatedApps(){let cache=desktopSpaceWindowCacheManager;if cache.windows.contains(where:{$0.app.isTerminated}){cache.windows.removeAll{$0.app.isTerminated};cache.revision+=1}}
 static func getAllWindowsIgnoringSwitcherFilters()->[WindowInfo]{collections+=1;return sortWindowsForSwitcher(desktopSpaceWindowCacheManager.windows)}
 static func getAllWindowsOfAllApps()->[WindowInfo]{switcherWindows(from:getAllWindowsIgnoringSwitcherFilters())}
 static func collapseNativeTabsIfNeeded(_ w:[WindowInfo])->[WindowInfo]{collapses+=1;return Defaults[.collapseNativeTabsIntoSingleWindow] ? w.filter(\.isNativeRepresentative):w}
 static func filterWindowsByCurrentSpace(_ w:[WindowInfo])->[WindowInfo]{spaceReads+=1;return w.filter{$0.space==activeSpace}}
 static func filterWindowsByCurrentMonitor(_ w:[WindowInfo])->[WindowInfo]{w.filter{$0.monitor==NSScreen.current.id}}
 static func getWindowsForFrontmostApp(from w:[WindowInfo])->[WindowInfo]{w.filter{$0.app.processIdentifier==NSWorkspace.shared.frontmostApplication?.processIdentifier}}
 static func getWindowlessRunningApps(existingWindows:[WindowInfo])->[WindowInfo]{
  let existing=Set(existingWindows.map{$0.app.processIdentifier})
  return NSWorkspace.shared.runningApplications.filter{!$0.isTerminated && !existing.contains($0.processIdentifier) && !Defaults[.appNameFilters].contains($0.bundleIdentifier ?? "")}.map{WindowInfo.windowlessEntry(for:$0)}
 }
 static func groupingBundleIdentifiers(for w:WindowInfo)->[String]{[w.app.bundleIdentifier!]} 
SWIFT
%w[readSwitcherCacheSnapshot switcherWindows sortWindowsForSwitcher sortWindowsForSwitcherByRecency groupWindowsByApp].each{|name|source+=block(util,"    static func #{name}(")+"\n"}
%w[sortWindowsByScreenPosition orderedScreens screenPositionKey].each{|name|source+=block(util,"    private static func #{name}(")+"\n"}
sort=block(util,'    private static func sortWindowsWithOptions(')
source+=sort.sub('var sortedWindows:', 'sorts+=1; var sortedWindows:')+"\n}\n"
group=block(util,'    static func groupWindowsByApp(')
source=source.sub(group,group.sub('let groupedApps =','groups+=1; let groupedApps ='))
source+=block(keys,'struct SwitcherFilterCandidates {')+"\n"
source+=<<~'SWIFT'
final class PreviewStateCoordinator {
 var windowSwitcherActive=true
 var activeSpaceMembers:Set<PreviewWindowIdentity>?
 var preparedSpaceFilterCandidates:SwitcherFilterCandidates?
 var onSpaceFilterChanged:(()->Void)?,onFrameRefreshNeeded:(()->Void)?
 var rows:[WindowInfo]=[]
}
final class SharedPreviewWindowCoordinator {var isVisible=true;var screen:NSScreen?;let windowSwitcherCoordinator=PreviewStateCoordinator()}
@MainActor final class Harness {
 var currentSessionId=UUID(),publications=0
SWIFT
source+=block(keys,'    private struct FilterPreparationKey:')+"\n"
%w[buildSwitcherWindows installSpaceFilter isActiveAppMode].each{|name|source+=block(keys,"    private func #{name}(").sub('private func','func')+"\n"}
source+=<<~'SWIFT'
 func applyRefreshedSwitcherWindows(_ rows:[WindowInfo],coordinator:PreviewStateCoordinator,dockPosition:DockPosition,bestGuessMonitor:NSScreen){publications+=1;coordinator.rows=rows}
}
@main struct Checks {
 @MainActor static func main(){
SWIFT
bools.each{|s|source+="Defaults.values[\"#{s}\"]=#{%w[enableSpacesBar includeHiddenWindowsInSwitcher showWindowlessAppsInSwitcher].include?(s)}\n"}
source+=<<~'SWIFT'
  Defaults.values["windowSwitcherSortOrder"]=WindowPreviewSortOrder.recentlyUsed
  Defaults.values["groupedAppsInSwitcher"]=["app1"];Defaults.values["appNameFilters"]=[String]()
  let a=NSRunningApplication(1),b=NSRunningApplication(2),empty=NSRunningApplication(3)
  NSWorkspace.shared.runningApplications=[a,b,empty];NSWorkspace.shared.frontmostApplication=a
  let cache=WindowUtil.desktopSpaceWindowCacheManager
  cache.windows=[WindowInfo(id:1,app:a,space:1,windowName:"First",lastAccessedTime:Date(timeIntervalSince1970:3)),WindowInfo(id:2,app:a,space:2,monitor:"two",windowName:"Second",lastAccessedTime:Date(timeIntervalSince1970:2)),WindowInfo(id:3,app:b,space:2,monitor:"two",windowName:"Third",lastAccessedTime:Date(timeIntervalSince1970:1))]
  let state=SharedPreviewWindowCoordinator(),h=Harness(),c=state.windowSwitcherCoordinator
  h.installSpaceFilter(previewCoordinator:state,mode:.currentMonitorCurrentSpace,screen:NSScreen.current,dockPosition:.bottom)
  let one=Set([PreviewWindowIdentity(cache.windows[0])]),two=Set(cache.windows.dropFirst().map(PreviewWindowIdentity.init))
  c.activeSpaceMembers=two;c.onSpaceFilterChanged?()
  precondition(c.rows.map(\.id)==[2,3],"Space membership must precede app grouping")
  c.activeSpaceMembers=one;c.onSpaceFilterChanged?()
  c.activeSpaceMembers=nil;c.onSpaceFilterChanged?()
  precondition(c.rows.map(\.id)==[1,0],"Clear restores scoped invocation and placeholder")
  let collections=WindowUtil.collections,sorts=WindowUtil.sorts,groups=WindowUtil.groups,collapses=WindowUtil.collapses,spatial=WindowUtil.spaceReads
  for _ in 0..<20 {for members:Set<PreviewWindowIdentity>? in [two,one,nil]{c.activeSpaceMembers=members;c.onSpaceFilterChanged?()}}
  precondition(WindowUtil.collections==collections && WindowUtil.sorts==sorts && WindowUtil.groups==groups && WindowUtil.collapses==collapses && WindowUtil.spaceReads==spatial,"Warm filtering must not recollect, sort, group, collapse or query spatial scope")
  print("COUNT 60 warm filter transitions: collections=0, sorts=0, groups=0, native-tab passes=0, Space scope reads=0")
  cache.windows[1].image=99;c.activeSpaceMembers=two;c.onSpaceFilterChanged?()
  precondition(c.rows.first!.image==99 && WindowUtil.sorts==sorts,"Image-only updates resolve current cache values without rebuilding")
  cache.windows[1].lastAccessedTime=Date(timeIntervalSince1970:10);cache.revision+=1
  c.onSpaceFilterChanged?();precondition(WindowUtil.sorts>sorts,"Metadata/recency revision must invalidate preparation")
  var before=WindowUtil.sorts;c.preparedSpaceFilterCandidates=nil;c.onSpaceFilterChanged?();precondition(WindowUtil.sorts>before,"Topology notifications must invalidate preparation")
  before=WindowUtil.sorts;Defaults.values["windowSwitcherSortOrder"]=WindowPreviewSortOrder.alphabeticalByTitle
  c.onSpaceFilterChanged?();precondition(WindowUtil.sorts>before,"Sort preferences must invalidate preparation")
  before=WindowUtil.sorts;Defaults.values["groupedAppsInSwitcher"]=[String]()
  c.onSpaceFilterChanged?();precondition(WindowUtil.sorts>before,"Grouping preferences must invalidate preparation")
  before=WindowUtil.sorts;NSScreen.current=NSScreen("two");c.activeSpaceMembers=nil;c.onSpaceFilterChanged?()
  precondition(WindowUtil.sorts>before && c.rows.map(\.id)==[0],"Monitor scope changes must not reuse the old projection")
  NSScreen.current=NSScreen("one")
  let newcomer=NSRunningApplication(4);NSWorkspace.shared.runningApplications.append(newcomer)
  c.onSpaceFilterChanged?();precondition(c.rows.filter(\.isWindowlessApp).map{ $0.app.processIdentifier }==[3,4],"New windowless apps must invalidate the prepared placeholder list")
  Defaults.values["appNameFilters"]=["app4"];c.onSpaceFilterChanged?()
  precondition(c.rows.filter(\.isWindowlessApp).map{$0.app.processIdentifier}==[3])
  cache.windows[1].isHidden=true;cache.revision+=1;Defaults.values["includeHiddenWindowsInSwitcher"]=false
  c.activeSpaceMembers=two;c.onSpaceFilterChanged?();precondition(c.rows.map(\.id)==[3])
  cache.windows.removeAll{$0.id==3};cache.revision+=1;c.onSpaceFilterChanged?();precondition(c.rows.isEmpty,"Removed targets cannot survive in prepared projections")
  let accepted=h.publications;h.currentSessionId=UUID();c.onSpaceFilterChanged?();precondition(h.publications==accepted,"Old-session callbacks must not update a successor session")
  let off=SharedPreviewWindowCoordinator();Defaults.values["enableSpacesBar"]=false
  h.installSpaceFilter(previewCoordinator:off,mode:.allWindows,screen:NSScreen.current,dockPosition:.bottom)
  precondition(off.windowSwitcherCoordinator.onSpaceFilterChanged==nil)
  Defaults.values["enableSpacesBar"]=true
  let original=WindowInfo(id:88,app:a,image:1),alternate=WindowInfo(id:88,app:a,image:2,axOverride:888)
  var duplicates=SwitcherFilterCandidates(spaces:[alternate,original],groupByApp:false)
  duplicates.prepareInvocation([alternate,original])
  let duplicateMembers=Set([PreviewWindowIdentity(original)])
  precondition(duplicates.resolve(members:duplicateMembers,windows:[original,alternate]).map(\.image)==[2,1],"Duplicate IDs must resolve their own AX entry in prepared order")
  precondition(duplicates.resolve(members:nil,windows:[original,alternate]).map(\.image)==[2,1])
  var cases=0
  for mode in SwitcherInvocationMode.allCases {for hidden in [false,true]{for grouped in [false,true]{
   Defaults.values["includeHiddenWindowsInSwitcher"]=hidden;Defaults.values["groupedAppsInSwitcher"]=grouped ? ["app1"]:[]
   let p=SharedPreviewWindowCoordinator(),r=Harness();r.installSpaceFilter(previewCoordinator:p,mode:mode,screen:NSScreen.current,dockPosition:.bottom)
   for members:Set<PreviewWindowIdentity>? in [one,two,[],nil] {
    p.windowSwitcherCoordinator.activeSpaceMembers=members;p.windowSwitcherCoordinator.onSpaceFilterChanged?()
    let expected=r.buildSwitcherWindows(mode:mode,spaceMembers:members).map(PreviewWindowIdentity.init)
    precondition(p.windowSwitcherCoordinator.rows.map(PreviewWindowIdentity.init)==expected,"Prepared/original builder mismatch")
    cases+=1
   }
  }}}
  print("PASS production preparation/callback/resolution: \(cases) builder equivalence cases, current images, membership-before-grouping, active-app exceptions, placeholders, scope restoration, recency/topology/preferences/monitor/app invalidation, removal, stale sessions and disabled installation; inert targets only")
 }
}
SWIFT
Dir.mktmpdir('dockfork-filter-candidates-') do |dir|
  File.write("#{dir}/checks.swift",source)
  abort 'Filter candidates compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
  abort 'Filter candidate checks failed' unless system("#{dir}/checks")
end
panel=File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
state=File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift")
abort 'Prepared candidates must clear on topology, bar removal and session teardown' unless block(panel,'    func refreshSpacesBar(').include?('preparedSpaceFilterCandidates = nil') && block(panel,'    private func removeSpacesBar(').include?('preparedSpaceFilterCandidates = nil') && block(state,'    func deactivateKeybindSession(').include?('preparedSpaceFilterCandidates = nil')
abort 'Prepared candidates must not retain screenshot-bearing rows' if block(keys,'struct SwitcherFilterCandidates {').match?(/let \w+: \[WindowInfo\]|var \w+: \[WindowInfo\]|CGImage|NSImage/)
puts 'PASS prepared-candidate teardown and screenshot-retention contracts'

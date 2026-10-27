#!/usr/bin/env ruby
# Count production refresh/model work with inert OS/cache boundaries, not native latency.
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
panel = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
util = File.read("#{root}/DockDoor/Utilities/Window Management/WindowUtil.swift")
state = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift")
source = <<~'SWIFT'
import Foundation
import CoreGraphics
typealias CGSSpaceID = UInt64
typealias CGWindowID = UInt32
enum SpaceMenuDisplayMode {case numberOnly,fullName}
enum WindowPreviewSortOrder {case recentlyUsed,creationOrder,alphabeticalByTitle,alphabeticalByAppName}
final class NSRunningApplication:Equatable {
 let processIdentifier:pid_t,localizedName:String?,bundleIdentifier:String?
 var isTerminated=false
 init(_ pid:pid_t){processIdentifier=pid;localizedName="App \(pid)";bundleIdentifier="test.app.\(pid)"}
 init?(processIdentifier:pid_t){self.processIdentifier=processIdentifier;localizedName=nil;bundleIdentifier=nil}
 static func ==(a:NSRunningApplication,b:NSRunningApplication)->Bool{a.processIdentifier==b.processIdentifier}
}
final class NSScreen {
 let identifier:String,localizedName:String
 init(_ id:String){identifier=id;localizedName=id}
 static var screens=[NSScreen("one"),NSScreen("two")]
}
struct WindowInfo {
 let id:CGWindowID,app:NSRunningApplication
 var ownerApp:NSRunningApplication{app}
 var spaceID:Int?,windowName:String?
 var isMinimized=false,isHidden=false,isFullscreen:Bool?=false,isWindowlessApp=false
 var lastAccessedTime:Double=0,creationTime:Double=0
 var isEffectivelyHiddenForUI:Bool{isHidden}
}
@MainActor enum Counts {
 static var values:[String:Int]=[:]
 static func add(_ name:String,_ amount:Int=1){values[name,default:0]+=amount}
 static let fields=["topology","cacheReads","sorts","fingerprints","fingerprintWindows","displayResolutions","screenIdentifiers","models","membership"]
}
@MainActor enum World {
 static var windows:[WindowInfo]=[],displays:[ManagedDisplayDescriptor]=[],membership:[CGWindowID:[CGSSpaceID]]=[:]
}
extension CGWindowID {
 @MainActor func cgsSpaces()->[CGSSpaceID]{Counts.add("membership");return World.membership[self] ?? []}
}
@MainActor enum Defaults {
 struct Key<T>{let value:T}
 static var enabled=true
 static subscript<T>(_ key:Key<T>)->T{key.value}
}
@MainActor extension Defaults.Key where T==Bool {
 static var enableSpacesBar:Self{.init(value:Defaults.enabled)}
 static var spacesBarRecentlyUsed:Self{.init(value:false)}
 static var collapseNativeTabsIntoSingleWindow:Self{.init(value:false)}
 static var spacesBarHideWhenSingle:Self{.init(value:false)}
 static var sortMinimizedToEnd:Self{.init(value:true)}
}
extension Defaults.Key where T==WindowPreviewSortOrder {static var windowSwitcherSortOrder:Self{.init(value:.recentlyUsed)}}
@MainActor enum DispatchQueue {
 static var work:[@MainActor ()->Void]=[]
 static let main=Queue()
 @MainActor struct Queue{func async(_ action:@escaping @MainActor ()->Void){DispatchQueue.work.append(action)}}
 static func drain(){let actions=work;work=[];for action in actions{action()}}
}
enum NSApplication {static let didChangeScreenParametersNotification=Notification.Name("inert-screen")}
final class NotificationCenter {
 static let `default`=NotificationCenter()
 func addObserver(forName:Notification.Name,object:Any?,queue:OperationQueue?,using:@escaping (Notification)->Void)->NSObjectProtocol{NSObject()}
 func removeObserver(_ observer:NSObjectProtocol){}
}
SWIFT
source += block(state, 'struct PreviewWindowIdentity:') + "\n"
%w[ManagedSpaceKind ManagedSpaceDescriptor ManagedDisplayDescriptor ManagedSpaceDestination].each do |name|
  source += block(shared, "#{name == 'ManagedSpaceKind' ? 'enum' : 'struct'} #{name}:") + "\n"
end
source += <<~'SWIFT'
@MainActor enum WindowSpaces {
 static func managedDisplays(includeOwners:Bool)->[ManagedDisplayDescriptor]{Counts.add("topology");return World.displays}
 static func recordBarSpaceVisits(_ displays:[ManagedDisplayDescriptor]){}
 static func barSpaceOrder(_ displays:[ManagedDisplayDescriptor])->[CGSSpaceID]{displays.flatMap{$0.spaces.map(\.id)}}
 private static func displayIdentifiers(for screen:NSScreen)->Set<String>{Counts.add("screenIdentifiers");return [screen.identifier]}
SWIFT
source += block(shared, '    static func screen(forDisplayIdentifier').sub('NSScreen.screens.first', 'Counts.add("displayResolutions"); return NSScreen.screens.first') + "\n"
source += block(shared, '    static func displayName(') + "\n"
source += block(shared, '    static func sourceSpaceIDs(') + "\n}\n"
source += <<~'SWIFT'
@MainActor enum WindowUtil {
 @MainActor struct Cache {func getAllWindows()->[WindowInfo]{Counts.add("cacheReads");return World.windows}}
 static let desktopSpaceWindowCacheManager=Cache()
 static func evictTerminatedApps(){}
 static func isInternalWindow(_ id:CGWindowID)->Bool{false}
 static func collapseNativeTabsIfNeeded(_ windows:[WindowInfo])->[WindowInfo]{windows}
 static func registerInternalWindow(_ id:CGWindowID){}
SWIFT
source += block(util, '    static func getAllWindowsIgnoringSwitcherFilters(') + "\n"
source += block(util, '    static func sortWindowsForSwitcher(') + "\n"
source += block(util, '    private static func sortWindowsWithOptions(').sub('        var sortedWindows:', '        Counts.add("sorts")' + "\n        var sortedWindows:") + "\n}\n"
source += block(shared, 'enum ManagedSpacePresentation {').sub('        var windowsBySpace:', '        Counts.add("models")' + "\n        var windowsBySpace:") + "\n"
source += <<~'SWIFT'
struct SpaceContentsTopology:Equatable {init(_ displays:[ManagedDisplayDescriptor]){}}
final class SpacesBarWindow {let windowNumber=1}
final class RefreshState {
 enum Target {case windows,space(CGSSpaceID)}
 enum Input {case programmatic}
 var windowSwitcherActive=true,pointerInteractionSessionID:UInt=1
 var preparedSpaceFilterCandidates:Int?,mouseHighlightedSpaceID:CGSSpaceID?
 var navigationTarget=Target.windows,spaceNavigationInputSource=Input.programmatic
}
@MainActor final class Probe {
 let windowSwitcherCoordinator=RefreshState()
 var pendingSpacesBarRefresh:(token:UUID,session:UInt,reason:SpacesBarRefresh)?
 var spacesBarScreenObserver:NSObjectProtocol?
 var spacesBarPresentationDisplays:[ManagedDisplayDescriptor]?,spacesBarSpaceChangeSnapshot:[ManagedDisplayDescriptor]?
 var spacesBarSections:[ManagedSpacePresentation.Display]=[],spacesBarAllSections:[ManagedSpacePresentation.Display]=[]
 var spacesBarFingerprint:[String]=[],spacesBarWindow:SpacesBarWindow?
 struct Drag {let displays:[ManagedDisplayDescriptor]}
 var contentsDragSession:Drag?,highlightedSpaceID:CGSSpaceID?
 let isVisible=true,frame=0
 func cancelContentsDrag(){contentsDragSession=nil}
 func updateSpaceFilter(){}
 func updateSpacesBarReservation(){}
 func positionSpacesBar(relativeTo:Int){}
 func schedulePanelFrameRefresh(){}
 func removeSpacesBar(keepTopologyObserver:Bool=false){pendingSpacesBarRefresh=nil;spacesBarWindow=nil;spacesBarSections=[]}
SWIFT
source += block(panel, '    struct SpacesBarRefresh:') + "\n"
source += block(panel, '    func requestSpacesBarRefresh(') + "\n"
source += block(panel, '    func refreshSpacesBar(').sub('            let fingerprint =', '            Counts.add("fingerprints"); Counts.add("fingerprintWindows", windows.count)' + "\n            let fingerprint =") + "\n}\n"
source += <<~'SWIFT'
@main struct Measurement {
 @MainActor static func main(){
  print("windows,scenario,"+Counts.fields.joined(separator:","))
  for n in [8,128,512] {
   Defaults.enabled=true
   let apps=(1...max(1,n/4)).map{NSRunningApplication(pid_t($0))}
   World.windows=(1...n).map{WindowInfo(id:CGWindowID($0),app:apps[($0-1)%apps.count],spaceID:($0-1)%6+1,windowName:"Window \($0)",lastAccessedTime:Double(n-$0),creationTime:Double($0))}
   World.membership=Dictionary(uniqueKeysWithValues:World.windows.map{($0.id,$0.id%7==0 ? [CGSSpaceID(1),CGSSpaceID(4)]:[CGSSpaceID($0.spaceID!)])})
   World.displays=["one","two"].enumerated().map{i,id in .init(identifier:id,currentSpaceID:CGSSpaceID(i*3+1),spaces:(1...3).map{.init(id:CGSSpaceID(i*3+$0),kind:.desktop,number:i*3+$0,desktopNumber:i*3+$0,ownerPIDs:[])})}
   let probe=Probe()
   func measure(_ name:String,queries:Int,sorts:Int,fingerprints:Int,models:Int,membership:Int,_ action:()->Void){
    Counts.values=[:];action()
    let expected=["topology":queries,"cacheReads":sorts,"sorts":sorts,"fingerprints":fingerprints,"fingerprintWindows":fingerprints*World.windows.count,"displayResolutions":2*(fingerprints+models),"screenIdentifiers":3*(fingerprints+models),"models":models,"membership":membership]
    precondition(Counts.fields.allSatisfy{Counts.values[$0,default:0]==expected[$0,default:0]},"Unexpected production counts: \(name) \(Counts.values)")
    print("\(n),\(name),"+Counts.fields.map{String(Counts.values[$0,default:0])}.joined(separator:","))
   }
   measure("open",queries:1,sorts:1,fingerprints:1,models:1,membership:n){probe.refreshSpacesBar()}
   measure("warm_layout_x100",queries:0,sorts:0,fingerprints:0,models:0,membership:0){for _ in 0..<100{probe.refreshSpacesBar(.layout)}}
   measure("unchanged_batch_x10",queries:1,sorts:1,fingerprints:1,models:0,membership:0){for _ in 0..<10{probe.requestSpacesBarRefresh(.topology)};DispatchQueue.drain()}
   measure("unchanged_refresh",queries:1,sorts:1,fingerprints:1,models:0,membership:0){probe.refreshSpacesBar(.topology)}
   measure("recency_change",queries:0,sorts:1,fingerprints:1,models:1,membership:n){World.windows[n-1].lastAccessedTime=Double(n*10);probe.refreshSpacesBar(.contents)}
   measure("supplied_topology",queries:0,sorts:1,fingerprints:1,models:1,membership:n){let display=World.displays[0];World.displays[0] = .init(identifier:display.identifier,currentSpaceID:2,spaces:display.spaces);probe.refreshSpacesBar(.topology,displays:World.displays)}
   measure("desktop_added",queries:1,sorts:1,fingerprints:1,models:1,membership:n){let display=World.displays[1];World.displays[1] = .init(identifier:display.identifier,currentSpaceID:display.currentSpaceID,spaces:display.spaces+[.init(id:7,kind:.desktop,number:7,desktopNumber:7,ownerPIDs:[])]);probe.refreshSpacesBar(.topology)}
   measure("state_change",queries:1,sorts:1,fingerprints:1,models:1,membership:n){World.windows[0].isMinimized=true;probe.refreshSpacesBar(.topology)}
   measure("membership_change",queries:1,sorts:1,fingerprints:1,models:1,membership:n){World.windows[0].spaceID=2;World.membership[World.windows[0].id]=[2];probe.refreshSpacesBar(.topology)}
   measure("window_removed",queries:1,sorts:1,fingerprints:1,models:1,membership:n-1){World.windows.removeLast();probe.refreshSpacesBar(.topology)}
   measure("disabled",queries:0,sorts:0,fingerprints:0,models:0,membership:0){Defaults.enabled=false;probe.requestSpacesBarRefresh(.topology);DispatchQueue.drain();probe.refreshSpacesBar(.topology)}
  }
  print("PASS production refresh/sort/model operation counts; inert OS boundaries, no native latency or FPS measurements")
 }
}
SWIFT
Dir.mktmpdir('dockfork-space-refresh-costs-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Refresh measurement compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Refresh measurement failed' unless system("#{dir}/checks")
end

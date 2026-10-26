#!/usr/bin/env ruby
require 'tmpdir'
require 'open3'
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
path = 'DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift'
current = File.read("#{root}/#{path}")
original, status = Open3.capture2('git', '-C', root, 'show', "15ba5d51:#{path}")
abort 'Missing characterization source' unless status.success?
source = <<~'SWIFT'
import Foundation
typealias pid_t = Int32
typealias AXUIElement = Int
final class App {let processIdentifier:pid_t;var eligible=true;init(_ pid:pid_t){processIdentifier=pid}}
struct WindowInfo:Equatable {
 let id:Int;let app:App;var axElement:Int;var image=0;var isWindowlessApp=false
 var viewSnapshot:[Int]{[id,Int(app.processIdentifier),image,isWindowlessApp ? 1:0]}
 static func ==(l:Self,r:Self)->Bool{l.id==r.id && l.app.processIdentifier==r.app.processIdentifier && l.axElement==r.axElement}
}
struct PreviewWindowIdentity:Hashable {let pid:pid_t;let windowID:Int;init(_ w:WindowInfo){pid=w.app.processIdentifier;windowID=w.id}}
enum DockPosition{case bottom}
enum DockUtils{static func getDockPosition()->DockPosition{.bottom}}
final class NSScreen{}
enum Key{case showWindowlessAppsInSwitcher}
enum Defaults{static var placeholders=false;static subscript(_ key:Key)->Bool{placeholders}}
enum WindowUtil {
 static var cached:[WindowInfo]=[]
 static func windowlessEntryIfEligible(for app:App,existingWindows:[WindowInfo])->WindowInfo? {
  guard app.eligible,!existingWindows.contains(where:{$0.app.processIdentifier==app.processIdentifier}) else{return nil}
  return WindowInfo(id:0,app:app,axElement: -Int(app.processIdentifier)-1,isWindowlessApp:true)
 }
}
final class SharedPreviewWindowCoordinator {
 static var activeInstance:SharedPreviewWindowCoordinator?=SharedPreviewWindowCoordinator()
 var hasVisibleSpacesBar=false,hides=0
 func hideWindow(){hides+=1}
}
@MainActor class Probe {
 enum Source {case keyboard,mouse,programmatic}
 var stored:[WindowInfo]=[],publications=0
 var activeSpaceMembers:Set<PreviewWindowIdentity>?
 var windows:[WindowInfo] {
  get{stored}
  set{stored=activeSpaceMembers.map{members in newValue.filter{!$0.isWindowlessApp && members.contains(PreviewWindowIdentity($0))}} ?? newValue;publications+=1}
 }
 var currIndex = -1,selectionSource:Source = .keyboard
 var checked=Set<PreviewWindowIdentity>()
 var checkedWindowCount:Int{checked.count}
 var isKeybindSessionActive=true,windowSwitcherActive=true
 var selectionLayoutGeneration:UInt=0
 var lastKnownBestGuessMonitor:NSScreen?=NSScreen();var lastKnownDockPosition:DockPosition = .bottom;var activeSpaceFilterID:Int?
 var fits=0,frames=0,focus=0,selectionFits=0
 var rangeOrder:[PreviewWindowIdentity]?
 var onFrameRefreshNeeded:(()->Void)?
 init(){onFrameRefreshNeeded={ [weak self] in self?.frames+=1 }}
 func updateSelectionIndex(_ index:Int,source:Source){currIndex=windows.indices.contains(index) ? index : -1;selectionSource=source}
 func recomputeAndPublishDimensions(dockPosition:DockPosition,bestGuessMonitor:NSScreen){fits+=1}
 func scheduleActiveFocusedWindowRefresh(){focus+=1}
 func reconcileSelectionRange(){if let rangeOrder,rangeOrder != windows.map(PreviewWindowIdentity.init){self.rangeOrder=nil}}
 func refreshSelectionLayout(){selectionFits+=1;scheduleSelectionLayout()}
 func consumeWindowlessSelection(in targets:[WindowInfo],refreshLayout:Bool=true){
  let before=checked.isEmpty;checked.subtract(targets.filter(\.isWindowlessApp).map(PreviewWindowIdentity.init))
  if refreshLayout,before != checked.isEmpty{refreshSelectionLayout()}
 }
 func reconcileCheckedWindows(refreshLayout:Bool=true){
  let before=checked.isEmpty
  var live=Set(WindowUtil.cached.map(PreviewWindowIdentity.init))
  let represented=Set(WindowUtil.cached.map{ $0.app.processIdentifier })
  live.formUnion(windows.filter{$0.isWindowlessApp && !represented.contains($0.app.processIdentifier)}.map(PreviewWindowIdentity.init))
  checked.formIntersection(live)
  if refreshLayout,before != checked.isEmpty{refreshSelectionLayout()}
 }
 func reset(_ rows:[WindowInfo],index:Int){stored=rows;currIndex=index;publications=0;fits=0;frames=0;focus=0;selectionFits=0}
SWIFT
source += block(current, '    func refreshSelectionLayout(').sub('func refreshSelectionLayout(', 'func scheduleSelectionLayout(') + "\n"
source += <<~'SWIFT'
}
@MainActor final class Current:Probe {
SWIFT
%w[applyCacheChanges reconcileWindowChanges].each { |name| source += block(current, "    #{name == 'reconcileWindowChanges' ? 'private ' : ''}func #{name}(") + "\n" }
['    func removeWindow(at', '    func removeWindow(byAx', '    func addWindows('].each { |sig| source += block(current, sig) + "\n" }
source += "}\n@MainActor final class Reference:Probe {\n"
['    func applyCacheChanges(', '    func removeWindow(at', '    func removeWindow(byAx', '    func addWindows('].each { |sig| source += block(original, sig) + "\n" }
source += <<~'SWIFT'
}
@main struct Checks {
 @MainActor static func main() async {
  let apps=(1...3).map{App(pid_t($0))}
  func win(_ id:Int,_ app:Int=0,_ ax:Int?=nil)->WindowInfo{WindowInfo(id:id,app:apps[app],axElement:ax ?? id+app*1000)}
  func signatures(_ rows:[WindowInfo])->[[Int]]{rows.map{$0.viewSnapshot+[$0.axElement]}}
  var cases=0
  for seed in 0..<180 {for placeholders in [false,true]{for selection in [-1,0,3,7]{
   Defaults.placeholders=placeholders
   let rows=(0..<8).map{win($0,$0%3)}
   let removalRows=rows.enumerated().filter{($0.offset+seed)%4==0}.map(\.element)
   let removed=seed%2==0 ? removalRows : Array(removalRows.reversed())
   let updated=rows.enumerated().filter{($0.offset+seed)%3==0}.map{pair in var w=pair.element;w.image=seed+1;return w}
   let added=[win(20+seed,seed%3),win(40+seed,(seed+1)%3)]
   WindowUtil.cached=rows.filter{w in !removed.contains{$0.axElement==w.axElement}}+added
   let c=Current(),r=Reference();c.reset(rows,index:selection);r.reset(rows,index:selection)
   c.checked=Set(rows.map(PreviewWindowIdentity.init));r.checked=c.checked
   c.applyCacheChanges(removed:removed,added:added,updated:updated)
   r.applyCacheChanges(removed:removed,added:added,updated:updated)
   precondition(signatures(c.windows)==signatures(r.windows),"Membership/order mismatch seed \(seed)")
   precondition(c.currIndex==r.currIndex && c.selectionSource==r.selectionSource && c.checked==r.checked,"Selection mismatch seed \(seed), selected \(selection)")
   precondition(c.fits<=1 && c.frames<=1 && c.focus<=1 && c.publications<=1 && c.selectionFits==0)
   cases+=1
  }}}
  print("PASS \(cases) frozen-reference batch cases: updates/removals/additions, ordered placeholders and highlighted/checked selection; one row publication/layout/frame/focus request")
  Defaults.placeholders=false
  let rows=(0..<64).map{win($0)}
  WindowUtil.cached=Array(rows.suffix(44))
  let c=Current(),r=Reference();c.reset(rows,index:30);r.reset(rows,index:30)
  c.applyCacheChanges(removed:Array(rows.prefix(20)),added:[],updated:[])
  r.applyCacheChanges(removed:Array(rows.prefix(20)),added:[],updated:[])
  precondition(c.fits==1 && c.frames==1 && c.focus==1 && c.publications==1 && r.fits==20)
  print("COUNT 20 removals: layout/frame/focus requests before=20 each, after=1 each; row publications before=20, after=1")
  c.reset(rows,index:1);var image=rows[1];image.image=99
  c.applyCacheChanges(removed:[],added:[],updated:[image,image])
  precondition(c.fits==0 && c.frames==0 && c.focus==0 && c.publications==1)
  c.applyCacheChanges(removed:[],added:[],updated:[image])
  precondition(c.publications==1)
  // Duplicate IDs retain first-match update semantics; AX removal must not remove its peer.
  let first=win(1,0,10),second=win(1,0,11),other=win(1,1,20)
  c.reset([first,second,other],index:1)
  var fresh=first;fresh.image=7;fresh.axElement=12
  c.applyCacheChanges(removed:[first,first],added:[],updated:[fresh])
  precondition(c.windows.count==3 && c.windows[0].image==7 && c.windows[1].axElement==11)
  c.removeWindow(at:1);precondition(c.windows.map(\.axElement)==[12,20])
  c.reset([first,first,second],index:2)
  c.applyCacheChanges(removed:[first,first],added:[],updated:[])
  precondition(c.windows.count==1 && c.windows[0].axElement==11 && c.currIndex==0)
  // Mixed replacement must not dismiss midway; Dock admissions retain the original PID.
  let panel=SharedPreviewWindowCoordinator.activeInstance!;panel.hides=0
  c.reset([first],index:0);c.isKeybindSessionActive=false
  c.applyCacheChanges(removed:[first],added:[other,win(8)],updated:[])
  precondition(c.windows.map(\.id)==[8] && panel.hides==0)
  // Empty grids stay open with a bar and can accept new switcher residents.
  c.isKeybindSessionActive=true;panel.hasVisibleSpacesBar=true
  c.applyCacheChanges(removed:[win(8)],added:[],updated:[])
  precondition(c.windows.isEmpty && panel.hides==0)
  c.addWindows([first]);precondition(c.windows==[first])
  panel.hasVisibleSpacesBar=false;c.removeWindow(at:0);precondition(panel.hides==1)
  // Space membership excludes additions without producing layout work.
  c.reset([first],index:0);c.activeSpaceMembers=[PreviewWindowIdentity(first)]
  c.addWindows([other]);precondition(c.windows==[first] && c.publications==0 && c.fits==0)
  c.activeSpaceMembers=nil
  Defaults.placeholders=true
  let placeholder=WindowUtil.windowlessEntryIfEligible(for:apps[0],existingWindows:[])!
  c.reset([placeholder],index:0);c.checked=[PreviewWindowIdentity(placeholder)]
  c.rangeOrder=c.windows.map(PreviewWindowIdentity.init)
  c.addWindows([first,win(2)])
  precondition(c.windows.map(\.id)==[1,2] && c.checked.isEmpty && c.selectionFits==0 && c.fits==1 && c.rangeOrder==nil)
  c.reset([first],index:0);c.checked=[PreviewWindowIdentity(other)];WindowUtil.cached=[first]
  c.applyCacheChanges(removed:[other],added:[],updated:[])
  precondition(c.windows==[first] && c.selectionFits==1 && c.fits==0)
await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
precondition(c.fits==1 && c.frames==1,"Offscreen checked-selection cleanup must retain its deferred layout")
c.reset(rows,index:30);c.refreshSelectionLayout()
c.applyCacheChanges(removed:Array(rows.prefix(20)),added:[],updated:[])
await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
precondition(c.fits==1 && c.frames==1,"Final batch fit must invalidate an older queued selection-summary fit")
print("PASS image-only/no-op gates, duplicate IDs/AX entries, replacement, app scoping, final-state dismissal, empty bar grid, filters, placeholder checks and range cleanup")
 }
}
SWIFT
Dir.mktmpdir('dockfork-preview-batch-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Batch fixture compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Batch fixture failed' unless system("#{dir}/checks")
end

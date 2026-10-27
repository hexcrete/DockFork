#!/usr/bin/env ruby
require 'tmpdir'
require 'open3'

def block(source, signature)
  start=source.index(signature) or abort "Missing #{signature}"
  opening=source.index(/\{\n/,start);depth=0
  (opening...source.length).each do |i|
    depth+=1 if source[i]=='{';depth-=1 if source[i]=='}'
    return source[start..i] if depth.zero?
  end
  abort "Unclosed #{signature}"
end

root=File.expand_path('../..',__dir__)
presenter=File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
state=File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift")
source=<<~'SWIFT'
import Foundation
import Combine
import QuartzCore
typealias CGWindowID=UInt32
struct Key<T>{let read:()->T}
enum Defaults {
 static var border=false,animations=true,fade=0.2
 static subscript<T>(_ key:Key<T>)->T{key.read()}
}
extension Key where T==Bool {
 static var showActiveWindowBorder:Self{Self{Defaults.border}}
 static var showAnimations:Self{Self{Defaults.animations}}
 static var debugMode:Self{Self{false}}
}
extension Key where T==Double {
 static var fullSizePreviewFadeOutDuration:Self{Self{Defaults.fade}}
}
enum DebugLogger{static func log(_ text:String,details:String){}}
final class Probe:@unchecked Sendable {
 let lock=NSLock();var count=0
 func read()->CGWindowID?{lock.withLock{count+=1};return 7}
 var reads:Int{lock.withLock{count}}
}
enum WindowUtil {
 static let probe=Probe()
 static func focusedWindowID(processIdentifier:pid_t)->CGWindowID?{probe.read()}
}
@MainActor final class NSWorkspace {
 static let shared=NSWorkspace()
 struct App{let processIdentifier:pid_t}
 var frontmostApplication:App?=App(processIdentifier:1)
}
struct WindowInfo {let id:CGWindowID;let app:NSWorkspace.App;let lastAccessedTime:Date}
@MainActor final class State:ObservableObject {
 enum Showing{case fullWindowPreview}
 var fullWindowPreviewActive=false,windowSwitcherActive=true
 @Published var focusedWindowID:CGWindowID?
 var windows=[WindowInfo(id:7,app:.init(processIdentifier:1),lastAccessedTime:Date())]
 var activeFocusRefreshTask:Task<Void,Never>?,pendingActiveFocusRefreshRequest=false,showingCalls=0
 func setShowing(_ state:Showing,toState:Bool){showingCalls+=1;fullWindowPreviewActive=toState;scheduleActiveFocusedWindowRefresh()}
SWIFT
source+=block(state,'    private func applyActiveFocusedWindowID(')+"\n"
source+=block(state,'    func scheduleActiveFocusedWindowRefresh()')+"\n}\n"
source+=<<~'SWIFT'
@MainActor final class NSPanel {
 var isVisible=true,alphaValue=1.0,contentView:NSPanel?=nil
 func animator()->NSPanel{self}
 func orderOut(_ sender:Any?){isVisible=false}
 func removeFromSuperview(){}
}
@MainActor enum NSEvent {
 static var removals=0
 static func removeMonitor(_ monitor:Any){removals+=1}
}
@MainActor final class NSAnimationContext {
 var duration=0.0,timingFunction:CAMediaTimingFunction?
 static var completions:[()->Void]=[]
 static func runAnimationGroup(_ changes:(NSAnimationContext)->Void,completionHandler:@escaping ()->Void){changes(NSAnimationContext());completions.append(completionHandler)}
}
@MainActor final class Preview {
 let windowSwitcherCoordinator=State()
 var fullPreviewWindow:NSPanel?,fullPreviewRefresh:(task:Task<Void,Never>,token:UUID)?
 var fullPreviewSource:Int?,activeFullPreviewHoverID:UUID?,fullPreviewFadeOutToken:UUID?
 var focusFadeTimer:Timer?,focusFadeLocalMonitor:Any?,focusFadeGlobalMonitor:Any?
 var focusFadeSelection:Int?,focusFadeMode:Int?,isPreviewFocusFaded=false
 var snapshots=0,opacityRestores=0
 func publishTapSnapshot(){snapshots+=1}
 func setPreviewFocusOpacity(_ opacity:Float,duration:Double){precondition(opacity==1 && duration==0);opacityRestores+=1}
SWIFT
source+=block(presenter,'    private func stopPreviewFocusFade()')+"\n"
source+=block(presenter,'    func hideFullPreviewWindow()')+"\n"
source+=block(presenter,'    private func removeFullPreviewWindow(')+"\n}\n"
source+=<<~'SWIFT'
@main struct Checks {
 @MainActor static func main()async {
  let idle=Preview();var notices=0
  let token=idle.windowSwitcherCoordinator.objectWillChange.sink{notices+=1}
  for _ in 0..<100 {idle.hideFullPreviewWindow();idle.windowSwitcherCoordinator.scheduleActiveFocusedWindowRefresh()}
  precondition(idle.snapshots==0 && idle.opacityRestores==0 && idle.windowSwitcherCoordinator.showingCalls==0 && notices==0 && WindowUtil.probe.reads==0)
  print("COUNT 100 idle hides + disabled-border refreshes: snapshots=0, showing calls=0, publications=0, AX reads=0")
  _=token

  // Each non-panel lifetime must still be cancelled, cleared and published.
  for kind in 0..<5 {
   let p=Preview()
   let task=Task<Void,Never>{try? await Task.sleep(nanoseconds:5_000_000_000)}
   switch kind {
   case 0:p.fullPreviewRefresh=(task,UUID())
   case 1:p.fullPreviewSource=1
   case 2:p.activeFullPreviewHoverID=UUID()
   case 3:p.windowSwitcherCoordinator.fullWindowPreviewActive=true
   default:
    p.focusFadeMode=1;p.focusFadeSelection=0;p.isPreviewFocusFaded=true
    p.focusFadeLocalMonitor=1;p.focusFadeGlobalMonitor=2
    p.focusFadeTimer=Timer(timeInterval:5,repeats:false){_ in}
   }
   let timer=p.focusFadeTimer
   p.hideFullPreviewWindow()
   precondition(p.fullPreviewRefresh==nil && p.fullPreviewSource==nil && p.activeFullPreviewHoverID==nil && !p.windowSwitcherCoordinator.fullWindowPreviewActive && p.snapshots==1)
   if kind==0{precondition(task.isCancelled)}else{task.cancel()}
   if kind==4{precondition(p.focusFadeMode==nil && p.focusFadeSelection==nil && p.focusFadeLocalMonitor==nil && p.focusFadeGlobalMonitor==nil && p.focusFadeTimer==nil && !p.isPreviewFocusFaded && p.opacityRestores==1 && NSEvent.removals==2 && timer?.isValid==false)}
   let calls=p.windowSwitcherCoordinator.showingCalls
   precondition(calls==(kind==3 ? 1:0))
   p.hideFullPreviewWindow();precondition(p.snapshots==1 && p.windowSwitcherCoordinator.showingCalls==calls)
  }

  // A live fade must not restart, and its stale completion cannot remove a replacement.
  let fading=Preview(),panel=NSPanel();fading.fullPreviewWindow=panel
  fading.windowSwitcherCoordinator.fullWindowPreviewActive=true
  fading.hideFullPreviewWindow()
  precondition(panel.alphaValue==0 && fading.fullPreviewFadeOutToken != nil && NSAnimationContext.completions.count==1)
  let fadeToken=fading.fullPreviewFadeOutToken
  fading.hideFullPreviewWindow()
  precondition(fading.fullPreviewFadeOutToken==fadeToken && NSAnimationContext.completions.count==1 && fading.windowSwitcherCoordinator.showingCalls==1)
  let finish=NSAnimationContext.completions.removeFirst();finish()
  for _ in 0..<100 where fading.fullPreviewWindow != nil{try? await Task.sleep(nanoseconds:1_000_000)}
  precondition(fading.fullPreviewWindow==nil && fading.fullPreviewFadeOutToken==nil && !panel.isVisible)
  let old=Preview();old.fullPreviewWindow=NSPanel();old.hideFullPreviewWindow()
  let stale=NSAnimationContext.completions.removeFirst(),replacement=NSPanel()
  old.fullPreviewWindow=replacement;old.fullPreviewFadeOutToken=nil;stale()
  try? await Task.sleep(nanoseconds:5_000_000)
  precondition(old.fullPreviewWindow===replacement && replacement.isVisible)
  for animated in [true,false] {
   Defaults.animations=animated;Defaults.fade=animated ? 0:0.2
   let p=Preview();p.fullPreviewWindow=NSPanel();p.hideFullPreviewWindow()
   precondition(p.fullPreviewWindow==nil && NSAnimationContext.completions.isEmpty)
  }

  let state=State();state.focusedWindowID=7
  var publications=0;let stateToken=state.objectWillChange.sink{publications+=1}
  state.pendingActiveFocusRefreshRequest=true
  let pending=Task<Void,Never>{try? await Task.sleep(nanoseconds:5_000_000_000)}
  state.activeFocusRefreshTask=pending
  state.scheduleActiveFocusedWindowRefresh()
  precondition(pending.isCancelled && state.activeFocusRefreshTask==nil && !state.pendingActiveFocusRefreshRequest && publications==1 && state.focusedWindowID==nil)
  state.scheduleActiveFocusedWindowRefresh();precondition(publications==1)
  _=stateToken

  // Enabled confirmation keeps its existing first read and two delayed rechecks.
  Defaults.border=true
  let enabled=State();enabled.scheduleActiveFocusedWindowRefresh()
  for _ in 0..<1000 where enabled.activeFocusRefreshTask != nil{try? await Task.sleep(nanoseconds:1_000_000)}
  precondition(enabled.focusedWindowID==7 && WindowUtil.probe.reads==3 && enabled.activeFocusRefreshTask==nil)
  print("PASS production idle/cancellation: pending geometry, hover/source/state ownership, fade resources, fade continuation/stale completion, animations off, disabled-border cleanup and unchanged three-read enabled schedule; fake panels/AX only")
 }
}
SWIFT
Dir.mktmpdir('dockfork-preview-idle-') do |dir|
 baseline=source
 ['DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift',
  'DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift'].zip([presenter,state]).each do |path,current|
  original,status=Open3.capture2('git','-C',root,'show',"4ebdadbb:#{path}")
  abort 'Missing frozen idle-work baseline' unless status.success?
  signature=path.include?('SharedPreviewWindowCoordinator') ? '    func hideFullPreviewWindow()' : '    func scheduleActiveFocusedWindowRefresh()'
  baseline=baseline.sub(block(current,signature),block(original,signature))
 end
 baseline=baseline[0...baseline.index('@main struct Checks')]+<<~'SWIFT'
 @main struct Before {
  @MainActor static func main(){
   let idle=Preview();var notices=0
   let token=idle.windowSwitcherCoordinator.objectWillChange.sink{notices+=1}
   for _ in 0..<100{idle.hideFullPreviewWindow();idle.windowSwitcherCoordinator.scheduleActiveFocusedWindowRefresh()}
   precondition(idle.snapshots==100 && idle.windowSwitcherCoordinator.showingCalls==100 && notices==200 && WindowUtil.probe.reads==0)
   _=token
   print("COUNT frozen baseline, 100 idle hides + disabled-border refreshes: snapshots=100, showing calls=100, publications=200, AX reads=0")
  }
 }
 SWIFT
 File.write("#{dir}/before.swift",baseline)
 abort 'Baseline compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/before.swift",'-o',"#{dir}/before")
 abort 'Baseline characterization failed' unless system("#{dir}/before")
 File.write("#{dir}/checks.swift",source)
 abort 'Idle checks compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Idle checks failed' unless system("#{dir}/checks")
end

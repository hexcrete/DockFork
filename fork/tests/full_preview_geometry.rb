#!/usr/bin/env ruby
require 'tmpdir'
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
info=File.read("#{root}/DockDoor/Utilities/Window Management/WindowInfo.swift")
presenter=File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
point=File.read("#{root}/DockDoor/Extensions/CoreGraphics/CGPoint.swift")
dock=File.read("#{root}/DockDoor/Utilities/DockObserver.swift")
request=block(presenter,'    private func requestFullPreviewWindow(')
refresh=block(presenter,'    func refreshDisplayedFullPreview(after updates:')
render=block(presenter,'    private func showFullPreviewWindow(')
worker=block(info,'    func readPreviewGeometry(')
abort 'Geometry must use existing workers, no UI/capture/query dependencies or retries' unless worker.include?('WindowFrameTransactions.run(for: ownerPID)') && !worker.match?(/NSScreen|WindowInfo|CGImage|WindowSpaces|Task.sleep|capture/)
abort 'Presentation must not perform live AX reads' if render.include?('axElement.') || request.include?('axElement.position(') || request.include?('axElement.size(')
%w[performShowWindow refreshDisplayedFullPreviewIfNeeded].each do |name|
 method=block(presenter,"    private func #{name}(")
 abort "#{name} bypasses geometry requests" unless method.include?('requestFullPreviewWindow(') && !method.match?(/axElement\.(position|size)\(/)
end
source=<<~'SWIFT'
import Foundation
import CoreGraphics
typealias pid_t=Int32
final class Gate:@unchecked Sendable {let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0);func hasEntered()->Bool{entered.wait(timeout:.now()) == .success}}
final class Model:Equatable,@unchecked Sendable {
 static func ==(l:Model,r:Model)->Bool{l===r}
 let lock=NSLock();var positionValue:CGPoint?=CGPoint(x:100,y:100),sizeValue:CGSize?=CGSize(width:600,height:400)
 var positionGate:Gate?,sizeGate:Gate?;var calls:[String]=[]
 func position()throws->CGPoint?{precondition(!Thread.isMainThread);let gate=lock.withLock{calls.append("position");let g=positionGate;positionGate=nil;return g};gate?.entered.signal();gate?.release.wait();return lock.withLock{positionValue}}
 func size()throws->CGSize?{precondition(!Thread.isMainThread);let gate=lock.withLock{calls.append("size");let g=sizeGate;sizeGate=nil;return g};gate?.entered.signal();gate?.release.wait();return lock.withLock{sizeValue}}
 func reset(){lock.withLock{calls=[]}}
 var reads:[String]{lock.withLock{calls}}
}
struct NSScreen:Equatable {
 let id:String;let frame:CGRect;var visibleFrame:CGRect{frame}
 static var screens=[NSScreen(id:"main",frame:CGRect(x:0,y:0,width:1512,height:982)),NSScreen(id:"left",frame:CGRect(x:-1500,y:0,width:1500,height:1000))]
 static var main:NSScreen?{screens.first}
 func uniqueIdentifier()->String{id}
 static func screen(containing frame:CGRect)->NSScreen?{screens.first{!$0.frame.intersection(frame).isEmpty}}
}
extension CGPoint {
SWIFT
source+=block(point,'    func screen()')+"\n"+block(point,'    func distance(to point:')+"\n}\n"
source+="enum DockObserver {\n"+block(dock,'    private static func computeOffsets(')+"\n"+block(dock,'    static func cgPointFromNSPoint(')+"\n}\n"
source+=<<~'SWIFT'
struct PreviewWindowIdentity:Hashable {let id:Int;init(_ w:WindowInfo){id=w.id}}
SWIFT
source+=block(info,'enum WindowFrameTransactions {')+"\n"
source+="extension WindowFrameTransactions {static var workerCount:Int {lock.withLock{workers.count}}}\n"
source+="struct WindowFrameTarget {let element:Model;let ownerPID:pid_t;let identity:PreviewWindowIdentity\n"+worker+"\n"+block(info,'    func frame(primaryMaxY:')+"\n}\n"
source+=<<~'SWIFT'
struct WindowFrameContext {let primaryMaxY=NSScreen.screens.first!.frame.maxY}
struct WindowInfo {
 let id:Int;var axElement:Model;var pid:pid_t=1;var image=1;var imageCapturedTime=Date(timeIntervalSince1970:1)
 var frameTarget:WindowFrameTarget{WindowFrameTarget(element:axElement,ownerPID:pid,identity:PreviewWindowIdentity(self))}
SWIFT
source+=block(info,'    func readWindowFrame()')+"\n}\n"
source+=<<~'SWIFT'
enum Key{case hover}
enum PreviewHoverAction{case previewFullSize,none}
enum Defaults{static var action:PreviewHoverAction = .previewFullSize;static subscript(_ key:Key)->PreviewHoverAction{action}}
enum PreviewFocusFadeMode{case dock,windowSwitcher;var hoverActionKey:Key{.hover}}
@MainActor final class State {
 enum Showing {case fullWindowPreview}
 var pointerInteractionSessionID:UInt=1,fullWindowPreviewActive=false;var current:WindowInfo?
 func getCurrentWindow()->WindowInfo?{current}
 func setShowing(_ state:Showing,toState:Bool){fullWindowPreviewActive=toState}
}
@MainActor final class Panel {
 var isVisible=true;var contentView:Int?=1
 func orderOut(_ sender:Any?){isVisible=false}
}
@MainActor final class Preview {
 var fullPreviewRefresh:(token:UUID,capturedAt:Date,pendingWindow:WindowInfo?,task:Task<Void,Never>)?
 var fullPreviewWindow:Panel?=Panel(),fullPreviewSource:(identity:PreviewWindowIdentity,capturedAt:Date)?
 var fullPreviewFadeOutToken:UUID?,activeFullPreviewHoverID:UUID?=UUID()
 let windowSwitcherCoordinator=State()
 var canPresentPreviews=true,isVisible=true,previewFocusFadeMode:PreviewFocusFadeMode = .dock
 var rendered:[(Int,Int,CGRect,Bool)]=[],snapshots=0
 func publishTapSnapshot(){snapshots+=1}
 func stopPreviewFocusFade(){}
 func request(_ window:WindowInfo){windowSwitcherCoordinator.current=window;requestFullPreviewWindow(for:window,on:NSScreen.main!)}
 func showFullPreviewWindow(for w:WindowInfo,frame:CGRect,isRefresh:Bool = false){rendered.append((w.id,w.image,frame,isRefresh));if fullPreviewWindow==nil{fullPreviewWindow=Panel()};fullPreviewWindow!.isVisible=true;fullPreviewSource=(PreviewWindowIdentity(w),w.imageCapturedTime)}
SWIFT
source+=request+"\n"+refresh+"\n"
hide=block(presenter,'    func hideFullPreviewWindow()')
source+=hide[0...hide.index('        guard let fullPreviewWindow else')]+"fullPreviewWindow=nil\npublishTapSnapshot()\n}\n}\n"
source+=<<~'SWIFT'
@MainActor func waitEntered(_ gate:Gate)async {
 for _ in 0..<2000 {if gate.hasEntered(){return};try? await Task.sleep(nanoseconds:1_000_000)}
 preconditionFailure("Worker did not start")
}
@main struct Checks {
 @MainActor static func main() async {
  let refused=Preview(),unused=Model();refused.isVisible=false;refused.request(WindowInfo(id:0,axElement:unused))
  precondition(refused.fullPreviewRefresh==nil && unused.reads.isEmpty)
  let screens=NSScreen.screens
  let model=Model(),preview=Preview(),initial=WindowInfo(id:1,axElement:model)
  let gate=Gate();model.positionGate=gate
  preview.request(initial);let task=preview.fullPreviewRefresh!.task,initialToken=preview.fullPreviewRefresh!.token
  await waitEntered(gate)
  precondition(preview.fullPreviewWindow?.isVisible==false && preview.rendered.isEmpty,"Old target must disappear, without showing cached geometry")
  var mainActorRan=false;await Task{@MainActor in mainActorRan=true}.value
  precondition(mainActorRan && preview.rendered.isEmpty,"Held AX must not block input/presentation")
  var newer=initial;newer.image=9;newer.imageCapturedTime+=1
  preview.refreshDisplayedFullPreview(after:[newer]);preview.refreshDisplayedFullPreview(after:[newer])
  precondition(preview.fullPreviewRefresh!.token == initialToken && model.reads==["position"])
  gate.release.signal();await task.value
  precondition(preview.rendered.count==1 && preview.rendered[0].1==9 && preview.rendered[0].2==CGRect(x:100,y:482,width:600,height:400))
  precondition(model.reads==["position","size"] && preview.fullPreviewRefresh==nil && WindowFrameTransactions.workerCount==0)
  print("COUNT initial preview: position/size AX reads before=3 on UI thread, after=2 on shared worker; repeated pending image updates add 0 reads")
  // Partial failures retain the prior position/size fallback rules, including other displays.
  for pos:CGPoint? in [CGPoint(x:100,y:100),CGPoint(x:-1400,y:50),nil] {for size:CGSize? in [CGSize(width:600,height:400),nil]{
   let m=Model();m.positionValue=pos;m.sizeValue=size
   let p=Preview();p.request(WindowInfo(id:2,axElement:m));await p.fullPreviewRefresh?.task.value
   let screen=pos.flatMap{$0.screen()} ?? NSScreen.main!,resolvedSize=size ?? screen.frame.size
   let origin=pos ?? CGPoint(x:screen.frame.midX,y:screen.frame.midY),converted=DockObserver.cgPointFromNSPoint(origin,forScreen:screen)
   precondition(p.rendered.count==1 && p.rendered[0].2==CGRect(x:converted.x,y:converted.y-resolvedSize.height,width:resolvedSize.width,height:resolvedSize.height))
   precondition(m.reads==["position","size"])
  }}
  // A newer target in another app completes while the old app's read remains blocked.
  let slow=Model(),slowGate=Gate();slow.positionGate=slowGate
  let latest=Preview();latest.request(WindowInfo(id:3,axElement:slow,pid:3));let old=latest.fullPreviewRefresh!.task
  await waitEntered(slowGate)
  let fast=Model();latest.request(WindowInfo(id:4,axElement:fast,pid:4));await latest.fullPreviewRefresh?.task.value
  precondition(latest.rendered.map{$0.0}==[4])
  slowGate.release.signal();await old.value
  precondition(latest.rendered.map{$0.0}==[4] && slow.reads==["position"])
// Explicit requests replace even the same window when session ownership changes.
let same=Preview(),sameModel=Model(),sameGate=Gate();sameModel.positionGate=sameGate
let sameWindow=WindowInfo(id:7,axElement:sameModel,pid:7)
same.request(sameWindow);let sameOld=same.fullPreviewRefresh!.task,sameToken=same.fullPreviewRefresh!.token
await waitEntered(sameGate)
same.activeFullPreviewHoverID=UUID();same.windowSwitcherCoordinator.pointerInteractionSessionID+=1
var sameNew=sameWindow;sameNew.image=17;same.request(sameNew);let sameLatest=same.fullPreviewRefresh!.task
precondition(same.fullPreviewRefresh!.token != sameToken)
sameGate.release.signal();await sameOld.value;await sameLatest.value
precondition(same.rendered.count==1 && same.rendered[0].1==17 && sameModel.reads==["position","position","size"])
// Same-app successors cannot overtake an in-flight AX call, and queued cancellation does no AX.

  let queued=Preview(),held=Model(),heldGate=Gate();held.positionGate=heldGate
  queued.request(WindowInfo(id:5,axElement:held,pid:5));let heldTask=queued.fullPreviewRefresh!.task;await waitEntered(heldGate)
  let skipped=Model();queued.request(WindowInfo(id:6,axElement:skipped,pid:5));let skippedTask=queued.fullPreviewRefresh!.task
  await Task.yield();precondition(skipped.reads.isEmpty)
  queued.hideFullPreviewWindow();heldGate.release.signal();await heldTask.value;await skippedTask.value
  precondition(skipped.reads.isEmpty && queued.rendered.isEmpty)
  for change in 0..<10 {
   let m=Model(),g=Gate(),p=Preview();m.positionGate=g
   p.request(WindowInfo(id:10,axElement:m));let pending=p.fullPreviewRefresh!.task;await waitEntered(g)
   switch change {
    case 0:p.hideFullPreviewWindow()
    case 1:p.activeFullPreviewHoverID=UUID()
    case 2:p.windowSwitcherCoordinator.pointerInteractionSessionID+=1
    case 3:p.canPresentPreviews=false
    case 4:Defaults.action = .none
    case 5:NSScreen.screens=Array(screens.prefix(1))
    case 6:p.isVisible=false
    case 7:p.windowSwitcherCoordinator.current=nil
    case 8:p.windowSwitcherCoordinator.current=WindowInfo(id:10,axElement:Model())
    default:var replacement=WindowInfo(id:10,axElement:Model());replacement.imageCapturedTime+=2;p.refreshDisplayedFullPreview(after:[replacement])
   }
   g.release.signal();await pending.value
   precondition(p.rendered.isEmpty && p.fullPreviewRefresh==nil,"Stale/disabled/disconnected request must not appear")
   Defaults.action = .previewFullSize;NSScreen.screens=screens
  }
  // Cancellation after size has started still refuses publication.
  let final=Preview(),sized=Model(),sizeGate=Gate();sized.sizeGate=sizeGate
  final.request(WindowInfo(id:11,axElement:sized));let sizing=final.fullPreviewRefresh!.task;await waitEntered(sizeGate)
  final.hideFullPreviewWindow();sizeGate.release.signal();await sizing.value
  precondition(final.rendered.isEmpty && sized.reads==["position","size"])
  // Real cache refresh retains its existing separate unreadable-frame policy and result placement.
  newer.image=12;newer.imageCapturedTime+=1
  preview.refreshDisplayedFullPreview(after:[newer]);await preview.fullPreviewRefresh?.task.value
  precondition(preview.rendered.count==2 && preview.rendered.last!.1==12 && preview.rendered.last!.3)
  precondition(WindowFrameTransactions.workerCount==0)
  print("PASS production fresh geometry: responsive main actor, worker-only reads, coalesced latest images, partial fallbacks, negative displays, independent apps, same-app ordering, queued/in-flight cancellation, stale hover/session/modal/setting/display/AX replacement rejection, existing cache refresh and worker cleanup; inert targets only")
 }
}
SWIFT
Dir.mktmpdir('dockfork-full-preview-') do |dir|
 File.write("#{dir}/checks.swift",source)
 abort 'Full-preview geometry compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Full-preview geometry checks failed' unless system("#{dir}/checks")
end

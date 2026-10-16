#!/usr/bin/env ruby
# Exercises production AX placement using test doubles; never manipulates live windows.
require 'tmpdir'
def block(s,sig)
 a=s.index(sig) or abort sig;b=s.index('{',a);d=0
 (b...s.length).each{|i|d+=1 if s[i]=='{';d-=1 if s[i]=='}';return s[a..i] if d==0}
end
source=File.read(File.expand_path('../../DockDoor/Utilities/Window Management/WindowInfo.swift', __dir__))
s=<<~'SWIFT'
import Foundation
import CoreGraphics
struct ScreenFrame {var maxY:CGFloat=982}
struct NSScreen {var frame=ScreenFrame();static let screens=[NSScreen()];func uniqueIdentifier()->String {"test"}}
let kAXPositionAttribute="position",kAXSizeAttribute="size"
enum FakeValue {case point(CGPoint),size(CGSize)}
enum AXValue {static func from(point:CGPoint)->FakeValue? {.point(point)};static func from(size:CGSize)->FakeValue? {.size(size)}}
struct App {var processIdentifier:Int32=1}
final class ModeAX {
 static let shared=ModeAX();var enabled=true;var failAfterWrite=false;var writes:[Bool]=[]
 func attribute<T>(_ key:String,_ type:T.Type)throws->T? {enabled as? T}
 func setAttribute(_ key:String,_ value:Bool)throws {writes.append(value);enabled=value;if failAfterWrite {throw NSError(domain:"AX",code:1)}}
}
final class Model {

 var frame=CGRect(x:20,y:30,width:400,height:300)
 var writes:[String]=[];var positionWrites=0;var ignorePositions=0;var fails=false;var minWidth:CGFloat=0
 var oldPositionHeightLimit:CGFloat=0;var rejectPosition=false;var rejectSize=false;var refreshes=0;var frameReads=0;var settlesOnSecondRead=false;var pendingOrigin:CGPoint?;var noReadableFrame=false
 func size()throws->CGSize? {fails ? nil : frame.size}
 func setAttribute(_ key:String,_ value:FakeValue)throws {
  writes.append(key)
  if fails || (rejectPosition && key==kAXPositionAttribute) || (rejectSize && key==kAXSizeAttribute) {throw NSError(domain:"AX",code:1)}
  switch value {
   case let .point(p):positionWrites+=1;let origin=CGPoint(x:p.x,y:982-p.y-frame.height);if positionWrites>ignorePositions {frame.origin=origin} else {pendingOrigin=origin}
   case let .size(s):let maxY=frame.maxY;frame.size=CGSize(width:max(minWidth,s.width),height:oldPositionHeightLimit>0 && positionWrites==0 ? min(s.height,oldPositionHeightLimit) : s.height);frame.origin.y=maxY-frame.height
  }
 }
}
enum WindowUtil {static func refreshCachedPreviewAfterProgrammaticResize(_ window:WindowInfo,targetScreenIdentifier:String) {window.axElement.refreshes+=1}}
enum DebugLogger {static func log(_ name:String,details:String){}}
struct PreviewWindowIdentity {init(_ w:WindowInfo){}}
final class FakeSnap {func remove(_ id:PreviewWindowIdentity){}}
enum WindowSnapRegistry {static let existing:FakeSnap?=nil}
struct WindowInfo {
 let id:Int=1;let app=App();let axElement:Model;let appAxElement=ModeAX.shared
 func currentWindowFrame()->CGRect? {axElement.frameReads+=1;if axElement.noReadableFrame{return nil};if axElement.settlesOnSecondRead && axElement.frameReads==2,let origin=axElement.pendingOrigin {axElement.frame.origin=origin};return axElement.frame}
SWIFT
s=block(source,'enum WindowFramePlacementResult {')+"\n"+s
s+=block(source,'    private func applyWindowFrame(')+"\n@MainActor\n"+block(source,'    func setWindowFrameResult(')+"\n}\n"
s+=<<~'SWIFT'
let target=CGRect(x:50,y:100,width:700,height:600)
let screen=NSScreen()
let immediate=Model()
let ok=await WindowInfo(axElement:immediate).setWindowFrameResult(target,on:screen,isRequestActive:{true})
precondition(ok == .confirmed && immediate.frame==target && immediate.refreshes==1 && immediate.writes==["size","position"])
let clamped=Model();clamped.oldPositionHeightLimit=450
let completed=await WindowInfo(axElement:clamped).setWindowFrameResult(target,on:screen,isRequestActive:{true})
precondition(completed == .confirmed && clamped.frame==target && clamped.writes==["size","position","size"] && clamped.frameReads==1 && clamped.refreshes==1)
let matching=Model();matching.frame=target
let unchanged=await WindowInfo(axElement:matching).setWindowFrameResult(target,on:screen,isRequestActive:{true})
precondition(unchanged == .confirmed && matching.writes==["position"] && matching.refreshes==1)
let delayed=Model();
delayed.ignorePositions=1;delayed.settlesOnSecondRead=true
let recovered=await WindowInfo(axElement:delayed).setWindowFrameResult(target,on:screen,isRequestActive:{true})
precondition(recovered == .confirmed && delayed.frame==target && delayed.refreshes==1 && delayed.writes.count==2 && delayed.frameReads==2)
let refused=Model();refused.minWidth=900
let failed=await WindowInfo(axElement:refused).setWindowFrameResult(target,on:screen,isRequestActive:{true})
precondition(failed == .unconfirmed && refused.writes.count==3 && refused.frameReads==2 && refused.refreshes==1)
let inactive=Model()
let stale=await WindowInfo(axElement:inactive).setWindowFrameResult(target,on:screen,isRequestActive:{false})
precondition(stale == .failed && inactive.writes.isEmpty && inactive.refreshes==0)
let broken=Model();broken.fails=true
let invalid=await WindowInfo(axElement:broken).setWindowFrameResult(target,on:screen,isRequestActive:{true})
precondition(invalid == .failed && broken.refreshes==0 && broken.writes.count==2)
let missingFrame=Model();missingFrame.noReadableFrame=true
let unreadable=await WindowInfo(axElement:missingFrame).setWindowFrameResult(target,on:screen,isRequestActive:{true})
precondition(unreadable == .failed && missingFrame.frameReads==2 && missingFrame.refreshes==1)
let positionRejected=Model();positionRejected.rejectPosition=true
let partiallySized=await WindowInfo(axElement:positionRejected).setWindowFrameResult(target,on:screen,isRequestActive:{true})
precondition(partiallySized == .failed && positionRejected.refreshes==1 && positionRejected.frame.size==target.size)
let sizeRejected=Model();sizeRejected.rejectSize=true
let partiallyMoved=await WindowInfo(axElement:sizeRejected).setWindowFrameResult(target,on:screen,isRequestActive:{true})
precondition(partiallyMoved == .failed && sizeRejected.refreshes==1 && sizeRejected.positionWrites==1)
let cancelled=Model();
cancelled.ignorePositions=100
let task=Task {await WindowInfo(axElement:cancelled).setWindowFrameResult(target,on:screen,isRequestActive:{true})}
try await Task.sleep(nanoseconds:30_000_000);task.cancel()
let cancelledResult=await task.value
precondition(cancelledResult == .failed && cancelled.writes.count==2 && cancelled.refreshes==0)
precondition(ModeAX.shared.enabled,"Cancellation stranded Enhanced UI disabled")
let superseded=Model();superseded.ignorePositions=100
var active=true
let pending=Task {await WindowInfo(axElement:superseded).setWindowFrameResult(target,on:screen,isRequestActive:{active})}
try await Task.sleep(nanoseconds:30_000_000);active=false
let obsolete=await pending.value
precondition(obsolete == .failed && superseded.writes.count==2 && superseded.refreshes==0 && superseded.frameReads==1)
for original in [false,true] {
 ModeAX.shared.enabled=original;ModeAX.shared.failAfterWrite=true;ModeAX.shared.writes=[]
 let model=Model()
 let result=await WindowInfo(axElement:model).setWindowFrameResult(target,on:screen,isRequestActive:{true})
 precondition(result == .confirmed && ModeAX.shared.enabled==original)
 precondition(ModeAX.shared.writes == (original ? [false,true] : []),"Incorrect scoped restoration")
}
print("PASS: prior Enhanced UI state restored even when the app reports errors after applying mode writes; no mode held across cancellation")
print("PASS: source-extracted ordered writes, immediate success, one delayed recheck without rewriting, refusal after two reads, inactive/superseded requests, AX failure, partial size/position failure reconciliation, cancellation and one targeted preview refresh")
SWIFT
Dir.mktmpdir('dockfork-frame-placement-') do |dir|
 path="#{dir}/Checks.swift"
 File.write(path,s)
 abort 'Swift compilation failed' unless system('swiftc','-swift-version','5','-suppress-warnings',path,'-o',"#{dir}/checks")
 abort 'Frame placement checks failed' unless system("#{dir}/checks")
end

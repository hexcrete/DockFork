#!/usr/bin/env ruby
# Exercises production AX placement using test doubles; never manipulates live windows.
require 'tmpdir'
def block(s,sig)
 a=s.index(sig) or abort sig;b=s.index(/\{\n/,a);d=0
 (b...s.length).each{|i|d+=1 if s[i]=='{';d-=1 if s[i]=='}';return s[a..i] if d==0}
end
source=File.read(File.expand_path('../../DockDoor/Utilities/Window Management/WindowInfo.swift', __dir__))
s=<<~'SWIFT'
import Foundation
import CoreGraphics
final class Gate: @unchecked Sendable {let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)}
@MainActor func waitEntered(_ gate:Gate) async throws {
 for _ in 0..<2000 {if gate.entered.wait(timeout:.now()) == .success {return};try await Task.sleep(nanoseconds:1_000_000)}
 preconditionFailure("Worker never entered")
}
extension WindowFrameTransactions {static var testWorkerCount:Int {lock.withLock {workers.count}};static func testUsers(_ pid:pid_t)->Int {lock.withLock {workers[pid]?.users ?? 0}}}
struct NSScreen {var frame=CGRect(x:0,y:0,width:1512,height:982);var usableFrame:CGRect?;var identifier="test";var visibleFrame:CGRect {usableFrame ?? frame};static let screens=[NSScreen()];static let main:NSScreen?=NSScreen();static func screen(containing frame:CGRect)->NSScreen? {NSScreen()};var snappingFrame:CGRect {frame};func uniqueIdentifier()->String {identifier}}
let kAXPositionAttribute="position",kAXSizeAttribute="size"
enum FakeValue {case point(CGPoint),size(CGSize)}
enum AXValue {static func from(point:CGPoint)->FakeValue? {.point(point)};static func from(size:CGSize)->FakeValue? {.size(size)}}
typealias pid_t = Int32
struct App {var processIdentifier:Int32=1}
typealias AXUIElement=Model
func AXUIElementCreateApplication(_ pid:Int32)->Model {Model.application}

final class ModeAX {
 static let shared=ModeAX();var reads=0;var disableGate:Gate?;var enabled=true;var failAfterWrite=false;var writes:[Bool]=[]
 func attribute<T>(_ key:String,_ type:T.Type)throws->T? {reads+=1;return enabled as? T}
 func setAttribute(_ key:String,_ value:Bool)throws {writes.append(value);enabled=value;if !value,let gate=disableGate {disableGate=nil;gate.entered.signal();gate.release.wait()};if failAfterWrite {throw NSError(domain:"AX",code:1)}}
}
final class Model {
 static let application=Model()
 func attribute<T>(_ key:String,_ type:T.Type)throws->T? {precondition(!Thread.isMainThread);return try ModeAX.shared.attribute(key,type)}
 func setAttribute(_ key:String,_ value:Bool)throws {precondition(!Thread.isMainThread);try ModeAX.shared.setAttribute(key,value)}
 func position()throws->CGPoint? {precondition(!Thread.isMainThread);calls.append("read position");if let gate=readGate {readGate=nil;gate.entered.signal();gate.release.wait()};frameReads+=1;if noReadableFrame{return nil};if settlesOnSecondRead && frameReads==2,let origin=pendingOrigin {frame.origin=origin};return CGPoint(x:frame.minX,y:982-frame.maxY)}

 var minimized=false;func isMinimized()throws->Bool {precondition(!Thread.isMainThread);return minimized};var fullscreen=false;func isFullscreen()throws->Bool {precondition(!Thread.isMainThread);return fullscreen};var readGate:Gate?;var writeGate:Gate?;var frame=CGRect(x:20,y:30,width:400,height:300)
 var calls:[String]=[];var sizeFailures:Set<Int>=[];var writes:[String]=[];var positionWrites=0;var ignorePositions=0;var fails=false;var minWidth:CGFloat=0
 var oldPositionHeightLimit:CGFloat=0;var rejectPosition=false;var rejectSize=false;var refreshes=0;var sizeReads=0;var frameReads=0;var settlesOnSecondRead=false;var pendingOrigin:CGPoint?;var noReadableFrame=false
 func size()throws->CGSize? {precondition(!Thread.isMainThread);calls.append("read size");sizeReads+=1;return fails || sizeFailures.contains(sizeReads) ? nil : frame.size}
 func setAttribute(_ key:String,_ value:FakeValue)throws {
  precondition(!Thread.isMainThread);calls.append("write \(key)");writes.append(key)
  if fails || (rejectPosition && key==kAXPositionAttribute) || (rejectSize && key==kAXSizeAttribute) {throw NSError(domain:"AX",code:1)}
  switch value {
   case let .point(p):positionWrites+=1;let origin=CGPoint(x:p.x,y:982-p.y-frame.height);if positionWrites>ignorePositions {frame.origin=origin} else {pendingOrigin=origin}
   case let .size(s):let maxY=frame.maxY;frame.size=CGSize(width:max(minWidth,s.width),height:oldPositionHeightLimit>0 && positionWrites==0 ? min(s.height,oldPositionHeightLimit) : s.height);frame.origin.y=maxY-frame.height;if let gate=writeGate {writeGate=nil;gate.entered.signal();gate.release.wait()}
  }
 }
}
extension Int {func cgsSpaces()->[UInt64] {[1]}}
enum WindowUtil {
 static var reconciliations=0,captures=0
 static var dragUpdates:[(CGRect,String?)]=[]
 static var lastRefreshScreen:String?
 static let programmaticResizeRefreshDelayNanos:UInt64=180_000_000
 static func resetDragPublication() {reconciliations=0;captures=0;dragUpdates=[];lastRefreshScreen=nil}
 static func scheduleCachedWindowMetadataReconciliation(pid:Int32,windowID:Int){reconciliations+=1}
 static func refreshCachedPreviewAfterProgrammaticResize(_ window:WindowInfo,targetScreenIdentifier:String?) {window.axElement.refreshes+=1;captures+=1;lastRefreshScreen=targetScreenIdentifier}
 static func updateCachedWindowState(_ window:WindowInfo,spaceID:Int?,screenIdentifier:String??,frame:CGRect) {dragUpdates.append((frame,screenIdentifier ?? nil))}
 static func scheduleForcedPreviewRecapture(pid:Int32,windowID:Int,fallbackWindowInfo:WindowInfo?,targetScreenIdentifier:String?,delayNanos:UInt64) {captures+=1}
}
enum DebugLogger {static func log(_ name:String,details:String){}}
struct PreviewWindowIdentity:Hashable {let pid:Int32,id:Int;var windowID:Int {id};init(_ w:WindowInfo){pid=w.app.processIdentifier;id=w.id}}
final class FakeSnap {func remove(_ id:PreviewWindowIdentity){}}
enum WindowSnapRegistry {static let existing:FakeSnap?=nil}
struct WindowInfo {
 var id:Int=1;var app=App();let axElement:Model;var imageCapturedTime=Date(timeIntervalSince1970:0);var isWindowlessApp=false;var spaceID:Int?=1;var ownerApp:App {app}
SWIFT
s=block(source,'enum WindowFramePlacementResult {')+"\n"+s
s=block(source,'enum WindowFrameTransactions {')+"\n"+block(source,'struct WindowFrameContext {')+"\n"+block(source,'struct WindowFrameTarget {')+"\n"+s
s+=block(source,'    func readFullscreenState(')+"\n"+block(source,'    func readMinimizedState(')+"\n"
s+=block(source,'    enum WindowPositionRect {')+"\n"+block(source,'    var frameTarget:')+"\n@MainActor\n"+block(source,'    private func publishFrameResult(')+"\n@MainActor\n"+block(source,'    func setWindowFrameResult(')+"\n@MainActor\n"+block(source,'    func positionWindow(')+"\n@MainActor\n"+block(source,'    func readWindowFrame(')+"\n@MainActor\n"+block(source,'    func setWindowFrame(')+"\n}\n"
observer=File.read(File.expand_path('../../DockDoor/Utilities/DockObserver.swift',__dir__))
start=observer.index('            let pid = window.ownerApp.processIdentifier',observer.index('private func handleTitleBarScroll')) || observer.index('            let pid = window.ownerApp.processIdentifier')
finish=observer.index('            titleBarActionTasks[pid] = (token, task)',start) or abort 'Missing title-bar enqueue'
enqueue=observer[start...(finish+'            titleBarActionTasks[pid] = (token, task)'.length)]
s+=<<~'SWIFT'
enum DefaultKey {case titleBarScrollRestoreWindowInterval}
enum Defaults {static subscript(_ key:DefaultKey)->Int {5}}
@MainActor final class TitleBar {
 enum VerticalScrollAction {case maximize,center}
 enum SizingMode {case uniform,separate}
 struct PendingRestoreState {let windowId:Int;let processIdentifier:pid_t;let action:VerticalScrollAction;let originalFrame:CGRect;let expirationDate:Date}
 var pendingTitleBarRestoreState:PendingRestoreState?
 var titleBarActionTasks:[pid_t:(token:UUID,task:Task<Void,Never>)]=[:]
 var latestTitleBarAction:UUID?
 var centeredWindowSizingMode:SizingMode = .uniform
 var centeredWindowScale:CGFloat=0.6,centeredWindowWidthScale:CGFloat=0.6,centeredWindowHeightScale:CGFloat=0.6,centeredWindowLockAspectRatio=false
 func enqueue(_ window:WindowInfo,normalizedDeltaY:CGFloat,now:Date) {
SWIFT
s+=enqueue+"\n}\n"+block(observer,'    private func handleTitleBarVerticalScroll(')+"\n"+block(observer,'    private func performTitleBarVerticalScrollAction(')+"\n}\n"
presenter=File.read(File.expand_path('../../DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift',__dir__))
cache=File.read(File.expand_path('../../DockDoor/Utilities/Window Management/SpaceWindowCacheManager.swift',__dir__))
refresh=block(presenter,'    func refreshDisplayedFullPreview(after updates:')
abort 'Cache updates must refresh the actual full-preview owner' unless cache.include?('preview.refreshDisplayedFullPreview(after: batch.updated)')
abort 'Full-preview refresh must not capture or read AX on the UI thread' if refresh.include?('axElement.') || refresh.include?('captureWindowImage') || refresh.include?('Task.sleep')
abort 'Full-preview hide must cancel pending refresh' unless block(presenter,'    func hideFullPreviewWindow()').include?('fullPreviewRefresh?.task.cancel()')
abort 'Full-preview updates must retain the hosting view' unless block(presenter,'    private func showFullPreviewWindow(').include?('hostingView.rootView = previewView')
s+=<<~'SWIFT'
@MainActor final class PreviewPanel {var isVisible=true}
@MainActor final class FullPreview {
 var fullPreviewWindow:PreviewPanel?=PreviewPanel()
 var fullPreviewFadeOutToken:UUID?
 var fullPreviewSource:(identity:PreviewWindowIdentity,capturedAt:Date)?
 var fullPreviewRefresh:(token:UUID,capturedAt:Date,task:Task<Void,Never>)?
 var rendered:[(PreviewWindowIdentity,Date,CGRect)]=[]
 func showFullPreviewWindow(for window:WindowInfo,on screen:NSScreen,frame:CGRect) {
  rendered.append((PreviewWindowIdentity(window),window.imageCapturedTime,frame))
  fullPreviewSource=(PreviewWindowIdentity(window),window.imageCapturedTime)
 }
SWIFT
s+=refresh+"\n}\n"
util=File.read(File.expand_path('../../DockDoor/Utilities/Window Management/WindowUtil.swift',__dir__))
placement=block(util,'    static func placeWindowCentered(')
abort 'Drag placement retains UI-thread AX calls' if placement.include?('axElement.')
abort 'Group drop must await placement under its existing owner' unless block(util,'    static func placeDraggedWindows(').include?('await placeWindowCentered(window, at: center, on: screen, isRequestActive: isRequestActive)')
s+="\nextension WindowUtil {\n"+block(util,'    struct WindowPlacementResult {')+"\n@MainActor\n"+placement+"\n}\n"
s+=<<~'SWIFT'
@main struct Checks { @MainActor static func main() async throws {
let target=CGRect(x:50,y:100,width:700,height:600)
let screen=NSScreen()
let immediate=Model()
let ok=await WindowInfo(axElement:immediate).setWindowFrameResult(target,on:screen,isRequestActive:{true})
precondition(ok == .confirmed && immediate.frame==target && immediate.refreshes==1 && immediate.writes==["size","position"] && immediate.sizeReads==3 && immediate.frameReads==1 && ModeAX.shared.reads==1)
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
// Execute the production ordinary Fill/Center/restore wrappers, not just Auto Tile's writer.
ModeAX.shared.failAfterWrite=false;ModeAX.shared.enabled=true
let ordinary=Model()
let filled=await WindowInfo(axElement:ordinary).positionWindow(.leftHalf)
precondition(filled && ordinary.frame==CGRect(x:0,y:0,width:756,height:982) && ordinary.refreshes==1 && ordinary.sizeReads==3 && ordinary.frameReads==1)
let centered=await WindowInfo(axElement:ordinary).positionWindow(.center,widthScale:0.5,heightScale:0.5)
precondition(centered && ordinary.frame.size==CGSize(width:756,height:491) && ordinary.frame.midX==756 && ordinary.frame.midY==491 && ordinary.refreshes==2)
let restored=await WindowInfo(axElement:ordinary).setWindowFrame(target,on:screen)
let restoredFrame=await WindowInfo(axElement:ordinary).readWindowFrame()
precondition(restored && restoredFrame==target && ordinary.refreshes==3)
let full=Model();full.fullscreen=true
let refusedFull=await WindowInfo(axElement:full).positionWindow(.rightHalf)
precondition(!refusedFull && full.writes.isEmpty && full.refreshes==0)
print("PASS ordinary Fill/Center/restore wrappers: background preflight and frame reads/writes, geometry and fullscreen exclusion")
// Hold the actual production queue
// Prove other apps and the main actor remain runnable.
let queueGate=Gate(), firstEntered=Gate()
let first=Task { await WindowFrameTransactions.run(for:11) { _ in
 firstEntered.entered.signal();queueGate.release.wait();return 1
}}
try await waitEntered(firstEntered)
let secondEntered=Gate()
let queued=Task {await WindowFrameTransactions.run(for:11) { _ in secondEntered.entered.signal();return 2 }}
let cancelledQueued=Task {await WindowFrameTransactions.run(for:11) { _ in preconditionFailure("Cancelled queued work executed");return 3 }}
for _ in 0..<2000 {if WindowFrameTransactions.testUsers(11)==3 {break};try await Task.sleep(nanoseconds:1_000_000)}
precondition(WindowFrameTransactions.testUsers(11)==3)
cancelledQueued.cancel()
let independent=await WindowFrameTransactions.run(for:12) { _ in precondition(!Thread.isMainThread);return 4 }
precondition(independent==4 && secondEntered.entered.wait(timeout:.now()) == .timedOut)
var mainActorAdvanced=false;mainActorAdvanced=true
precondition(mainActorAdvanced)
queueGate.release.signal()
let firstValue=await first.value, queuedValue=await queued.value, cancelledValue=await cancelledQueued.value
precondition(firstValue==1 && queuedValue==2 && cancelledValue==nil)
precondition(WindowFrameTransactions.testWorkerCount==0,"Completed workers must be released")

// Cancel after a size write takes effect. No position/correction may follow, but cleanup must.
ModeAX.shared.enabled=true;ModeAX.shared.writes=[]
let partial=Model(), sizeGate=Gate();partial.writeGate=sizeGate
let partialTask=Task {await WindowInfo(axElement:partial).setWindowFrameResult(target,on:screen,isRequestActive:{true})}
try await waitEntered(sizeGate)
precondition(partial.writes==["size"] && ModeAX.shared.enabled==false)
partialTask.cancel();sizeGate.release.signal()
let partialResult=await partialTask.value
precondition(partialResult == .failed && partial.writes==["size"] && partial.frame.size==target.size)
precondition(ModeAX.shared.enabled && ModeAX.shared.writes==[false,true] && partial.refreshes==0)
precondition(WindowUtil.reconciliations>0,"Actual partial writes need metadata reconciliation")

// Cancel while the app is applying Enhanced UI. Restore even if disable reports an error.
ModeAX.shared.enabled=true;ModeAX.shared.writes=[];ModeAX.shared.failAfterWrite=true
let modeGate=Gate();ModeAX.shared.disableGate=modeGate
let modeModel=Model()
let modeTask=Task {await WindowInfo(axElement:modeModel).setWindowFrameResult(target,on:screen,isRequestActive:{true})}
try await waitEntered(modeGate)
modeTask.cancel();modeGate.release.signal()
let modeResult=await modeTask.value
precondition(modeResult == .failed && modeModel.writes.isEmpty && ModeAX.shared.enabled)
precondition(ModeAX.shared.writes==[false,true])
ModeAX.shared.failAfterWrite=false
precondition(WindowFrameTransactions.testWorkerCount==0)
print("PASS production workers: independent apps, same-app serialization, main-actor progress during held AX, queued/between-write cancellation, Enhanced UI restoration after errors/cancellation, partial reconciliation and worker cleanup")
let titleBar=TitleBar(), titleWindow=Model(), titleGate=Gate()
let originalTitleFrame=titleWindow.frame;titleWindow.writeGate=titleGate
let titleInfo=WindowInfo(axElement:titleWindow)
titleBar.enqueue(titleInfo,normalizedDeltaY:1,now:Date())
try await waitEntered(titleGate)
titleBar.enqueue(titleInfo,normalizedDeltaY:1,now:Date())
let titleTask=titleBar.titleBarActionTasks[1]!.task
titleGate.release.signal();await titleTask.value
precondition(titleWindow.frame==originalTitleFrame && titleBar.pendingTitleBarRestoreState==nil && titleBar.titleBarActionTasks.isEmpty,"Queued repeated title-bar actions must restore their original frame")
let blockedTitle=Model(), blockedTitleGate=Gate();blockedTitle.writeGate=blockedTitleGate
let otherTitle=Model()
titleBar.enqueue(WindowInfo(axElement:blockedTitle),normalizedDeltaY:1,now:Date())
try await waitEntered(blockedTitleGate)
titleBar.enqueue(WindowInfo(app:App(processIdentifier:2),axElement:otherTitle),normalizedDeltaY:1,now:Date())
await titleBar.titleBarActionTasks[2]!.task.value
precondition(otherTitle.frame==screen.frame && titleBar.pendingTitleBarRestoreState?.processIdentifier==2)
let blockedTitleTask=titleBar.titleBarActionTasks[1]!.task
blockedTitleGate.release.signal();await blockedTitleTask.value
precondition(titleBar.pendingTitleBarRestoreState?.processIdentifier==2 && titleBar.titleBarActionTasks.isEmpty,"Old title-bar completion overwrote newer state")
print("PASS production title-bar scheduling: per-app FIFO, repeated restore, independent apps, stale publication and task cleanup")


let fullPreview=FullPreview(), captureModel=Model()
let firstCapture=Date(timeIntervalSince1970:1), secondCapture=Date(timeIntervalSince1970:2)
var captured=WindowInfo(axElement:captureModel,imageCapturedTime:firstCapture)
let capturedIdentity=PreviewWindowIdentity(captured)
fullPreview.fullPreviewSource=(capturedIdentity,Date(timeIntervalSince1970:0))
fullPreview.refreshDisplayedFullPreview(after:[WindowInfo(id:2,axElement:captureModel,imageCapturedTime:firstCapture)])
precondition(fullPreview.fullPreviewRefresh==nil && captureModel.frameReads==0)
fullPreview.refreshDisplayedFullPreview(after:[captured])
await fullPreview.fullPreviewRefresh?.task.value
precondition(fullPreview.rendered.count==1 && fullPreview.rendered[0].1==firstCapture && fullPreview.rendered[0].2==captureModel.frame)
precondition(fullPreview.fullPreviewRefresh==nil && captureModel.frameReads==1)
fullPreview.refreshDisplayedFullPreview(after:[captured])
precondition(fullPreview.fullPreviewRefresh==nil && captureModel.frameReads==1)
let refreshGate=Gate();captureModel.readGate=refreshGate
captured.imageCapturedTime=secondCapture
fullPreview.refreshDisplayedFullPreview(after:[captured])
let oldRefresh=fullPreview.fullPreviewRefresh!.task, oldRefreshToken=fullPreview.fullPreviewRefresh!.token
try await waitEntered(refreshGate)
fullPreview.refreshDisplayedFullPreview(after:[captured])
precondition(fullPreview.fullPreviewRefresh?.token==oldRefreshToken,"Duplicate metadata restarted the same capture refresh")
captured.imageCapturedTime=Date(timeIntervalSince1970:3);captureModel.frame=target
fullPreview.refreshDisplayedFullPreview(after:[captured])
let newestRefresh=fullPreview.fullPreviewRefresh!.task
refreshGate.release.signal();await oldRefresh.value;await newestRefresh.value
precondition(fullPreview.rendered.count==2 && fullPreview.rendered.last!.1==captured.imageCapturedTime && fullPreview.rendered.last!.2==target)
precondition(fullPreview.fullPreviewRefresh==nil)
for disappearance in [true,false] {
 let gate=Gate();captureModel.readGate=gate;captured.imageCapturedTime+=1
 fullPreview.fullPreviewSource=(capturedIdentity,Date(timeIntervalSince1970:0))
 fullPreview.refreshDisplayedFullPreview(after:[captured])
 let pending=fullPreview.fullPreviewRefresh!.task
 try await waitEntered(gate)
 if disappearance {fullPreview.fullPreviewSource=nil;fullPreview.fullPreviewWindow?.isVisible=false;pending.cancel()}
 else {fullPreview.fullPreviewSource=(PreviewWindowIdentity(WindowInfo(id:2,axElement:captureModel)),Date())}
 gate.release.signal();await pending.value
 precondition(fullPreview.rendered.count==2 && fullPreview.fullPreviewRefresh==nil,"Stale full-preview refresh resurrected a closed/replaced preview")
 fullPreview.fullPreviewWindow?.isVisible=true
}
fullPreview.fullPreviewSource=(capturedIdentity,Date(timeIntervalSince1970:0))
fullPreview.fullPreviewFadeOutToken=UUID()
fullPreview.refreshDisplayedFullPreview(after:[captured])
precondition(fullPreview.fullPreviewRefresh==nil)
fullPreview.fullPreviewFadeOutToken=nil
captureModel.noReadableFrame=true
fullPreview.refreshDisplayedFullPreview(after:[captured]);await fullPreview.fullPreviewRefresh?.task.value
precondition(fullPreview.rendered.count==2 && fullPreview.fullPreviewRefresh==nil)
captureModel.noReadableFrame=false;captured.imageCapturedTime+=1
fullPreview.refreshDisplayedFullPreview(after:[captured]);await fullPreview.fullPreviewRefresh?.task.value
precondition(fullPreview.rendered.count==3 && fullPreview.rendered.last!.2==target)
let readsBeforeClosed=captureModel.frameReads
fullPreview.fullPreviewWindow=nil;captured.imageCapturedTime+=1
fullPreview.refreshDisplayedFullPreview(after:[captured])
precondition(fullPreview.fullPreviewRefresh==nil && captureModel.frameReads==readsBeforeClosed)
print("PASS full-size cache refresh: displayed identity/image/geometry, unrelated/duplicate/stale update gates, latest-wins cancellation, hide/hover replacement/fade protection, unreadable-frame cleanup and no work without a visible panel")

let stateModel=Model();stateModel.fullscreen=true;stateModel.minimized=true
let stateWindow=WindowInfo(axElement:stateModel)
let liveFull=await stateWindow.readFullscreenState(),liveMin=await stateWindow.readMinimizedState()
precondition(liveFull==true && liveMin==true && stateModel.writes.isEmpty)
let stateGate=Gate();stateModel.writeGate=stateGate
let stateBlocker=Task {await stateWindow.setWindowFrameResult(target,on:screen,isRequestActive:{true})}
try await waitEntered(stateGate)
let staleRead=Task {await stateWindow.readFullscreenState()}
for _ in 0..<2000 {if WindowFrameTransactions.testUsers(1)==2 {break};try await Task.sleep(nanoseconds:1_000_000)}
staleRead.cancel();stateGate.release.signal();_ = await stateBlocker.value
let cancelledState=await staleRead.value;precondition(cancelledState==nil && WindowFrameTransactions.testWorkerCount==0)
print("PASS action preflight state reads: production workers execute off main, share app serialization, accept live state and cancel queued reads without writes")

// Compare unchanged ordinary drop call counts and visible-frame placement, including another display.
let dragScreen=NSScreen(frame:CGRect(x:0,y:0,width:1200,height:900),usableFrame:CGRect(x:0,y:40,width:1200,height:830),identifier:"destination")
let dragCases:[(CGSize,CGPoint,CGRect)]=[
 (CGSize(width:400,height:300),CGPoint(x:600,y:450),CGRect(x:400,y:300,width:400,height:300)),
 (CGSize(width:400,height:300),CGPoint(x:-100,y:450),CGRect(x:0,y:300,width:400,height:300)),
 (CGSize(width:400,height:300),CGPoint(x:2000,y:450),CGRect(x:800,y:300,width:400,height:300)),
 (CGSize(width:400,height:300),CGPoint(x:600,y:-100),CGRect(x:400,y:40,width:400,height:300)),
 (CGSize(width:400,height:300),CGPoint(x:600,y:2000),CGRect(x:400,y:570,width:400,height:300)),
 (CGSize(width:1800,height:1100),CGPoint(x:600,y:450),CGRect(x:0,y:40,width:1200,height:830))
]
for (size,pointer,expected) in dragCases {
 WindowUtil.resetDragPublication()
 let model=Model();model.frame.size=size
 let modeReads=ModeAX.shared.reads
 let placement=await WindowUtil.placeWindowCentered(WindowInfo(axElement:model),at:pointer,on:dragScreen)
 let fits=size.width<=1200 && size.height<=830
 let calls=fits ? ["read size","read size","write position","read position","read size"] : ["read size","write size","read size","write position","read position","read size"]
 precondition(placement != nil && model.frame==expected && model.calls==calls)
 precondition(placement!.frame==CGRect(x:expected.minX,y:982-expected.maxY,width:expected.width,height:expected.height) && placement!.screenIdentifier=="destination")
 precondition(WindowUtil.dragUpdates.count==1 && WindowUtil.dragUpdates[0].0==placement!.frame && WindowUtil.captures==1 && WindowUtil.reconciliations==1)
 precondition(ModeAX.shared.reads==modeReads,"Drag changed the inherited Enhanced UI policy")
}
WindowUtil.resetDragPublication()
let constrainedDrag=Model();constrainedDrag.frame.size=CGSize(width:1800,height:1100);constrainedDrag.minWidth=1400
let constrainedDrop=await WindowUtil.placeWindowCentered(WindowInfo(axElement:constrainedDrag),at:CGPoint(x:600,y:450),on:dragScreen)
precondition(constrainedDrop != nil && constrainedDrag.frame==CGRect(x:-100,y:40,width:1400,height:830))
let otherScreen=NSScreen(frame:CGRect(x:-1440,y:-600,width:1440,height:900),usableFrame:CGRect(x:-1440,y:-560,width:1440,height:820),identifier:"other-display")
let otherGeometry=Model()
let otherDrop=await WindowUtil.placeWindowCentered(WindowInfo(axElement:otherGeometry),at:CGPoint(x:-200,y:-800),on:otherScreen)
precondition(otherDrop != nil && otherGeometry.frame==CGRect(x:-400,y:-560,width:400,height:300) && otherDrop!.screenIdentifier=="other-display")
print("PASS drag geometry/call counts: center, every edge, usable rather than snapping bounds, oversized fitting, app minimum size, negative-coordinate display and AX-coordinate cache publication")

for kind in 0..<5 {
 WindowUtil.resetDragPublication()
 let model=Model()
 var info=WindowInfo(axElement:model)
 if kind==0 {model.fails=true}
 if kind==1 {info.isWindowlessApp=true}
 if kind==2 {model.frame.size = .zero}
 if kind==3 {model.rejectPosition=true}
 let result=await WindowUtil.placeWindowCentered(info,at:CGPoint(x:500,y:500),on:dragScreen,isRequestActive:{kind != 4})
 precondition(result==nil && WindowUtil.dragUpdates.isEmpty && WindowUtil.captures==0)
 precondition(WindowUtil.reconciliations==(kind==3 ? 1 : 0))
 if kind==1 || kind==4 {precondition(model.calls.isEmpty)}
}
WindowUtil.resetDragPublication()
let partialDrag=Model();partialDrag.frame.size=CGSize(width:1800,height:1100);partialDrag.rejectPosition=true
let partialDrop=await WindowUtil.placeWindowCentered(WindowInfo(axElement:partialDrag),at:CGPoint(x:500,y:500),on:dragScreen)
precondition(partialDrop==nil && WindowUtil.dragUpdates.isEmpty && partialDrag.refreshes==1 && WindowUtil.lastRefreshScreen==nil && WindowUtil.reconciliations==1)
let readFallback=Model();readFallback.noReadableFrame=true;readFallback.sizeFailures=[3]
let fallbackDrop=await WindowUtil.placeWindowCentered(WindowInfo(axElement:readFallback),at:CGPoint(x:600,y:450),on:dragScreen)
precondition(fallbackDrop != nil && fallbackDrop!.frame==CGRect(x:400,y:382,width:400,height:300))
print("PASS drag failures: invalid/windowless/stale targets, partial resize reconciliation without optimistic display/frame cache, and unchanged accepted-position/readback fallback")

WindowUtil.resetDragPublication()
let fitGate=Gate(), pendingDrag=Model();pendingDrag.frame.size=CGSize(width:1800,height:1100);pendingDrag.writeGate=fitGate
let pendingDrop=Task {await WindowUtil.placeWindowCentered(WindowInfo(axElement:pendingDrag),at:CGPoint(x:500,y:500),on:dragScreen)}
try await waitEntered(fitGate)
let anotherDrag=Model()
let anotherDrop=await WindowUtil.placeWindowCentered(WindowInfo(app:App(processIdentifier:2),axElement:anotherDrag),at:CGPoint(x:600,y:450),on:dragScreen)
precondition(anotherDrop != nil && pendingDrag.writes==["size"])
pendingDrop.cancel();fitGate.release.signal()
let cancelledDrop=await pendingDrop.value
precondition(cancelledDrop==nil && pendingDrag.writes==["size"] && WindowUtil.dragUpdates.count==1 && WindowUtil.captures==1 && WindowUtil.reconciliations==2)

WindowUtil.resetDragPublication()
let sharedGate=Gate(), sharedResize=Model();sharedResize.writeGate=sharedGate
let runningResize=Task {await WindowInfo(axElement:sharedResize).setWindowFrameResult(target,on:screen,isRequestActive:{true})}
try await waitEntered(sharedGate)
let queuedDrag=Model()
let queuedDrop=Task {await WindowUtil.placeWindowCentered(WindowInfo(axElement:queuedDrag),at:CGPoint(x:500,y:500),on:dragScreen)}
for _ in 0..<2000 {if WindowFrameTransactions.testUsers(1)==2 {break};try await Task.sleep(nanoseconds:1_000_000)}
precondition(WindowFrameTransactions.testUsers(1)==2 && queuedDrag.calls.isEmpty,"Drag bypassed the application's active frame transaction")
queuedDrop.cancel();sharedGate.release.signal()
_ = await runningResize.value
let cancelledQueuedDrop=await queuedDrop.value
precondition(cancelledQueuedDrop==nil && queuedDrag.calls.isEmpty && WindowUtil.dragUpdates.isEmpty && WindowFrameTransactions.testWorkerCount==0)
print("PASS drag transaction ownership: main-actor progress during held fitting AX, independent apps, same-app resize/drag serialization, queued/in-flight cancellation, no stale publication and queue cleanup")

}}
SWIFT
Dir.mktmpdir('dockfork-frame-placement-') do |dir|
 path="#{dir}/Checks.swift"
 File.write(path,s)
 abort 'Swift compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library','-suppress-warnings',path,'-o',"#{dir}/checks")
 abort 'Frame placement checks failed' unless system("#{dir}/checks")
end

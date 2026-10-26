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
app=File.read("#{root}/DockDoor/AppDelegate.swift")
ax=File.read("#{root}/DockDoor/Extensions/AXUIElement.swift")
keys=File.read("#{root}/DockDoor/Utilities/KeybindHelper.swift")
frames=File.read("#{root}/DockDoor/Utilities/Window Management/WindowInfo.swift")
probe=block(ax,'func isAccessibilityReady()')
recover=block(keys,'    func recover()')
wake=block(app,'    @objc private func handleSystemWake(')
abort 'Readiness must remain main-actor input capture with background AX reads' unless ax.include?("@MainActor\nfunc isAccessibilityReady() async") && probe.include?('WindowFrameTransactions.run(for: pid)') && !probe.match?(/allWindows|windowsByBruteForce|captureWindowImage|Task.sleep/)
abort 'Necessary recovery must not dismiss a newer session asynchronously' if recover.include?('Task {')
abort 'Keep existing display debounce and observer cleanup infrastructure' unless block(app,'    @objc private func handleScreenParametersChanged(').include?('asyncAfter(deadline: .now() + 2.0') && block(app,'    func applicationWillTerminate(').include?('wakeRecoveryTask?.cancel()')
source=<<~'SWIFT'
import Foundation
typealias pid_t=Int32
final class Gate:@unchecked Sendable{let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0);func started()->Bool{entered.wait(timeout:.now()) == .success}}
final class Element:@unchecked Sendable {
 let lock=NSLock();var roleValue:String?="AXApplication",windowsValue:[Element]?=[];var gate:Gate?;var failRole=false,failWindows=false;var calls:[String]=[]
 func role()throws->String?{precondition(!Thread.isMainThread);let g=lock.withLock{calls.append("role");let g=gate;gate=nil;return g};g?.entered.signal();g?.release.wait();if failRole{throw NSError(domain:"AX",code:1)};return roleValue}
 func windows()throws->[Element]?{precondition(!Thread.isMainThread);lock.withLock{calls.append("windows")};if failWindows{throw NSError(domain:"AX",code:2)};return windowsValue}
 var reads:[String]{lock.withLock{calls}}
}
struct RunningApp{let bundleIdentifier:String;let processIdentifier:pid_t}
final class NSWorkspace{static let shared=NSWorkspace();var runningApplications=[RunningApp(bundleIdentifier:"com.apple.finder",processIdentifier:1)]}
enum AXModel{static let lock=NSLock();static var element=Element();static var creates=0,timeouts:[Double]=[]}
func AXUIElementCreateApplication(_ pid:pid_t)->Element{precondition(!Thread.isMainThread);return AXModel.lock.withLock{AXModel.creates+=1;return AXModel.element}}
func AXUIElementSetMessagingTimeout(_ element:Element,_ seconds:Double){precondition(!Thread.isMainThread);AXModel.lock.withLock{AXModel.timeouts.append(seconds)}}
let kAXApplicationRole="AXApplication",kAXWindowRole="AXWindow",kAXScrollAreaRole="AXScrollArea"
SWIFT
source+=block(frames,'enum WindowFrameTransactions {')+"\n@MainActor\n"+probe+"\n"
source+=<<~'SWIFT'
final class Tap{var valid=true,enabled=true}
final class Loop{var valid=true}
enum DockObserver{static var canPostEvents=true}
func CFMachPortIsValid(_ tap:Tap)->Bool{tap.valid}
func CFRunLoopSourceIsValid(_ loop:Loop)->Bool{loop.valid}
enum CGEvent{static func tapIsEnabled(tap:Tap)->Bool{tap.enabled}}
enum Trust{static var allowed=true}
func AXIsProcessTrusted()->Bool{Trust.allowed}
enum DebugLogger{static var events:[String]=[];static func log(_ name:String,details:String){events.append(details)}}
@MainActor final class Preview {
 var active=true,hides=0
 func hideWindow(){active=false;hides+=1}
}
@MainActor final class Switching {
 var cancels=0
 func isActive(previewCoordinator:Preview)->Bool{previewCoordinator.active}
 func cancelSwitching(previewCoordinator:Preview){cancels+=1;previewCoordinator.active=false}
}
@MainActor final class Keys {
 var eventTap:Tap?=Tap(),runLoopSource:Loop?=Loop(),resets=0
 var switcherSessionActive=true,hasProcessedModifierRelease=false,isCommandKeyCurrentlyDown=true,lastCmdTabObservedActive=true,cmdTabActionPerformed=true
 let windowSwitchingCoordinator=Switching(),previewCoordinator=Preview()
 func reset(){resets+=1}
SWIFT
source+=recover+"\n}\n"
source+=<<~'SWIFT'
@MainActor final class Resource {var resets=0;func reset(){resets+=1}}
@MainActor final class Script {
 var results:[Bool],calls=0,hold=false,pending:CheckedContinuation<Bool,Never>?
 init(_ results:[Bool]){self.results=results}
 func read()async->Bool{calls+=1;if hold{return await withCheckedContinuation{pending=$0}};return results.isEmpty ? false:results.removeFirst()}
 func release(_ result:Bool){let p=pending;pending=nil;p?.resume(returning:result)}
}
@MainActor enum ProbeScript {
 static var current=Script([true]),delays:[UInt64]=[]
 static func read()async->Bool{let script=current;return await script.read()}
 static func sleep(_ delay:UInt64)async{delays.append(delay);await Task.yield()}
}
@MainActor final class App:NSObject {
 var wakeRecoveryTask:Task<Void,Never>?,wakeRecoveryGeneration:UInt=0,screenParametersDebounce:DispatchWorkItem?
 let dockObserver:Resource?=Resource(),keybindHelper:Keys?=Keys(),appClosureObserver:Resource?=Resource(),dockLocker:Resource?=Resource(),windowGestureController:Resource?=Resource()
 func start(){handleSystemWake()}
SWIFT
source+=wake.sub('try? await Task.sleep(nanoseconds: delay)','await ProbeScript.sleep(delay)').sub('await isAccessibilityReady()','await ProbeScript.read()')+"\n"
source+=block(app,'    func recoverObserversAndTaps()')+"\n}\n"
source+=<<~'SWIFT'
@MainActor func waitFor(_ condition:()->Bool)async {
 for _ in 0..<5000{if condition(){return};await Task.yield()}
 preconditionFailure("Expected phase never started")
}
@main struct Checks {
 @MainActor static func main()async {
  func model(_ element:Element){AXModel.lock.withLock{AXModel.element=element;AXModel.creates=0;AXModel.timeouts=[]}}
  let empty=Element();model(empty)
  let emptyReady=await isAccessibilityReady();precondition(emptyReady,"Healthy empty Finder must be ready")
  precondition(empty.reads==["role","windows"] && AXModel.timeouts==[1])
  let child=Element();child.roleValue="AXWindow";let populated=Element();populated.windowsValue=[child];model(populated)
  let populatedReady=await isAccessibilityReady();precondition(populatedReady && child.reads==["role"])
  let desktop=Element();desktop.roleValue="AXScrollArea";let desktopOnly=Element();desktopOnly.windowsValue=[desktop];model(desktopOnly)
  let desktopReady=await isAccessibilityReady();precondition(desktopReady,"Finder desktop without ordinary windows must be ready")
  precondition(desktopOnly.reads==["role","windows"] && desktop.reads==["role"],"Desktop acceptance must add no AX reads")
  for role in ["AXUnknown", "AXGroup"] {
   let invalid=Element();invalid.roleValue=role;let e=Element();e.windowsValue=[invalid];model(e)
   let ready=await isAccessibilityReady();precondition(!ready,"Unexpected child roles must remain invalid")
  }
  let unreadable=Element();unreadable.failRole=true;let e=Element();e.windowsValue=[unreadable];model(e)
  let unreadableReady=await isAccessibilityReady();precondition(!unreadableReady)
  let malformed=Element();malformed.windowsValue=[malformed];model(malformed)
  let malformedReady=await isAccessibilityReady();precondition(malformedReady==false,"Application-as-child must remain invalid");malformed.windowsValue=[]
  for kind in 0..<4 {
   let e=Element();if kind==0{e.failRole=true};if kind==1{e.failWindows=true};if kind==2{e.windowsValue=nil};if kind==3{e.roleValue="AXUnknown"};model(e)
   let refused=await isAccessibilityReady();precondition(refused==false)
  }
  let prior=NSWorkspace.shared.runningApplications;NSWorkspace.shared.runningApplications=[]
  let missingFinder=await isAccessibilityReady();precondition(missingFinder==false);NSWorkspace.shared.runningApplications=prior
  let blocked=Element(),gate=Gate();blocked.gate=gate;model(blocked)
  let readiness=Task{@MainActor in await isAccessibilityReady()}
  await waitFor{gate.started()}
  var progressed=false;await Task{@MainActor in progressed=true}.value
  precondition(progressed && blocked.reads==["role"])
  readiness.cancel();gate.release.signal();let cancelled=await readiness.value;precondition(cancelled==false)
  precondition(blocked.reads==["role"],"Cancelled probe must not issue later AX calls")
  for _ in 0..<3 {
   let k=Keys();k.recover();precondition(k.resets==0 && k.previewCoordinator.active && k.switcherSessionActive && k.isCommandKeyCurrentlyDown && !k.hasProcessedModifierRelease)
  }
  for failure in 0..<6 {
   let k=Keys();switch failure{case 0:k.eventTap=nil;case 1:k.eventTap!.valid=false;case 2:k.eventTap!.enabled=false;case 3:k.runLoopSource=nil;case 4:Trust.allowed=false;default:DockObserver.canPostEvents=false}
   k.recover();precondition(k.resets==1 && k.previewCoordinator.hides==1 && k.windowSwitchingCoordinator.cancels==1 && !k.switcherSessionActive && k.hasProcessedModifierRelease)
   // A new session after required recovery must not be closed by a queued cleanup callback.
   k.previewCoordinator.active=true;await Task.yield();precondition(k.previewCoordinator.active)
   Trust.allowed=true;DockObserver.canPostEvents=true
  }
  let invalidSource=Keys();invalidSource.runLoopSource!.valid=false;invalidSource.recover();precondition(invalidSource.resets==1)
  ProbeScript.delays=[];ProbeScript.current=Script([false,true])
  let a=App();let debounce=DispatchWorkItem{};a.screenParametersDebounce=debounce;a.start();let normal=a.wakeRecoveryTask!
  await normal.value
  precondition(ProbeScript.delays==[1_000_000_000,2_000_000_000] && debounce.isCancelled && a.screenParametersDebounce==nil)
  precondition(a.dockObserver!.resets==1 && a.appClosureObserver!.resets==1 && a.dockLocker!.resets==1 && a.windowGestureController!.resets==1)
  precondition(a.keybindHelper!.resets==0 && a.keybindHelper!.previewCoordinator.active && a.wakeRecoveryTask==nil)
  ProbeScript.delays=[];let failing=Script([]);ProbeScript.current=failing
  let timed=App();timed.start();await timed.wakeRecoveryTask!.value
  precondition(ProbeScript.delays==[1_000_000_000,2_000_000_000,4_000_000_000,8_000_000_000] && failing.calls==4)
  precondition(timed.dockObserver!.resets==1 && timed.keybindHelper!.previewCoordinator.active)
  // Supersession while a noninterruptible probe is pending must reject its eventual result.
  let held=Script([]);held.hold=true;ProbeScript.current=held
  let newer=App();newer.start();let old=newer.wakeRecoveryTask!;await waitFor{held.pending != nil}
  ProbeScript.current=Script([true]);newer.start();await newer.wakeRecoveryTask!.value
  held.release(true);await old.value;precondition(newer.dockObserver!.resets==1)
  // External posting-state recovery supersedes an older wake probe as well.
  let external=Script([]);external.hold=true;ProbeScript.current=external
  let b=App();b.start();let obsolete=b.wakeRecoveryTask!;await waitFor{external.pending != nil}
  b.recoverObserversAndTaps();external.release(true);await obsolete.value
  precondition(b.dockObserver!.resets==1 && b.wakeRecoveryTask==nil)
  print("PASS production readiness: empty/desktop-only/populated Finder, unchanged desktop AX read counts, unexpected roles, AX failures/nil/partial initialization, missing Finder, worker-only reads, main-actor progress and cancellation between calls")
  print("PASS production recovery: healthy tap/session preserved; invalid/disabled/missing resources, posting refusal and revocation rebuild and synchronously dismiss; all other resource resets retained")
  print("COUNT bounded wake retries: delays=1/2/4/8 seconds, 4 probes; timeout preserves healthy switcher; superseded wake/external recovery causes no duplicate reset")
 }
}
SWIFT
Dir.mktmpdir('dockfork-wake-') do |dir|
 File.write("#{dir}/checks.swift",source)
 abort 'Wake checks compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
 abort 'Wake checks failed' unless system("#{dir}/checks")
end

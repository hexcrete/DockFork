#!/usr/bin/env ruby
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
cache = File.read("#{root}/DockDoor/Utilities/Window Management/SpaceWindowCacheManager.swift")
production = block(cache, 'class SpaceWindowCacheManager {')
# Keep real cache locking, diffing, suppression and deferred batching; replace UI delivery only.
production = production.sub(block(production, '    private func flushCoordinatorChanges()'), <<~'SWIFT')
    private func flushCoordinatorChanges() {
        Delivery.batches.append(takePendingCoordinatorChanges())
    }
SWIFT
source = <<~'SWIFT'
import Foundation
typealias CGWindowID=Int
struct PreviewWindowIdentity {let pid:Int32;let windowID:Int}
final class WindowSnapRegistry {static var existing:WindowSnapRegistry?;func remove(_ identity:PreviewWindowIdentity){}}
enum Metrics {static var idReads=0}
struct App {let processIdentifier:Int32}
struct Snapshot:Hashable {var title="";var minimized=false;var hidden=false;var fullscreen=false;var space=1;var image=0}
struct WindowInfo:Hashable {
 let rawID:Int
 var id:Int {Metrics.idReads+=1;return rawID}
 var app:App
 var ax:Int
 var viewSnapshot=Snapshot()
 var lastAccessedTime=Date.distantPast
 static func ==(lhs:Self,rhs:Self)->Bool {lhs.rawID==rhs.rawID && lhs.app.processIdentifier==rhs.app.processIdentifier && lhs.ax==rhs.ax}
 func hash(into hasher:inout Hasher){hasher.combine(rawID);hasher.combine(app.processIdentifier)}
}
enum DebugLogger {static func log(_ event:String,details:String){}}
typealias Changes=(removed:Set<WindowInfo>,added:Set<WindowInfo>,updated:[WindowInfo])
enum Delivery {static var batches:[(removed:[WindowInfo],added:[WindowInfo],updated:[WindowInfo])]=[]}
struct Signature:Hashable {
 let id:Int,pid:Int32,ax:Int,snapshot:Snapshot
 init(_ w:WindowInfo){id=w.rawID;pid=w.app.processIdentifier;ax=w.ax;snapshot=w.viewSnapshot}
}
func signatures<S:Sequence>(_ windows:S)->Set<Signature> where S.Element==WindowInfo {Set(windows.map(Signature.init))}
func same(_ a:Changes,_ b:Changes)->Bool {
 signatures(a.removed)==signatures(b.removed) && signatures(a.added)==signatures(b.added) && signatures(a.updated)==signatures(b.updated) && a.updated.count==b.updated.count
}
// Frozen pre-optimization comparison, including first-match behavior for duplicate IDs.
func reference(_ old:Set<WindowInfo>,_ new:Set<WindowInfo>)->Changes {
 let oldIDs=Set(old.map(\.id)),newIDs=Set(new.map(\.id))
 let removedIDs=oldIDs.subtracting(newIDs),addedIDs=newIDs.subtracting(oldIDs)
 let removed=old.filter{removedIDs.contains($0.id)},added=new.filter{addedIDs.contains($0.id)}
 var updated:[WindowInfo]=[]
 for id in oldIDs.intersection(newIDs) {
  if let previous=old.first(where:{$0.id==id}),let current=new.first(where:{$0.id==id}),previous != current || previous.viewSnapshot != current.viewSnapshot {updated.append(current)}
 }
 return (removed,added,updated)
}
func window(_ id:Int,pid:Int32=42,ax:Int?=nil,image:Int=0)->WindowInfo {
 WindowInfo(rawID:id,app:App(processIdentifier:pid),ax:ax ?? id,viewSnapshot:Snapshot(image:image))
}
SWIFT
source += production + "\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func drain() async {await withCheckedContinuation{continuation in DispatchQueue.main.async{continuation.resume()}}}
 @MainActor static func main() async throws {
  var cases=0
  for seed in 0..<512 {
   var old=Set<WindowInfo>(),new=Set<WindowInfo>()
   for id in 0..<24 {
    if (id+seed)%4 != 0 {old.insert(window(id))}
    if (id+seed)%5 != 0 {
     var w=window(id,ax:(id+seed)%7==0 ? id+100:id,image:(id+seed)%3)
     w.viewSnapshot.title="title\((id+seed)%2)";w.viewSnapshot.minimized=(id+seed)%8==0
     w.viewSnapshot.hidden=(id+seed)%9==0;w.viewSnapshot.fullscreen=(id+seed)%10==0
     w.viewSnapshot.space=1+(id+seed)%3
     new.insert(w)
    }
    if (id+seed)%11==0 {old.insert(window(id,ax:id+200));new.insert(window(id,ax:id+300,image:2))}
   }
   for (a,b) in [(old,new),(new,old),(old,old),(new,new),(old,Set<WindowInfo>()),(Set<WindowInfo>(),new)] {
    precondition(same(reference(a,b),SpaceWindowCacheManager.changes(from:a,to:b)),"Diff mismatch seed \(seed)")
    cases+=1
   }
  }
  for n in [8,64,256,1024] {
   let windows=Set((0..<n).map{window($0)})
   Metrics.idReads=0;_ = reference(windows,windows);let before=Metrics.idReads
   Metrics.idReads=0;_ = SpaceWindowCacheManager.changes(from:windows,to:windows);let after=Metrics.idReads
   precondition(before==n*n+5*n && after==4*n,"ID-access counts must characterize quadratic versus linear traversal")
   print("COUNT unchanged windows=\(n): original ID reads=\(before), indexed=\(after)")
  }
  let manager=SpaceWindowCacheManager(),old:Set<WindowInfo>=[window(1),window(2)]
  manager.writeCache(pid:42,windowSet:old)
  precondition(Delivery.batches.isEmpty,"Delivery must stay deferred")
  await drain();precondition(Delivery.batches.count==1 && signatures(Delivery.batches[0].added)==signatures(old))
  Delivery.batches=[]
  let new:Set<WindowInfo>=[window(2,image:1),window(3)]
  manager.writeCache(pid:42,windowSet:new)
  await drain();let batch=Delivery.batches[0]
  precondition(Delivery.batches.count==1 && same((Set(batch.removed),Set(batch.added),batch.updated),reference(old,new)))
  Delivery.batches=[]
  manager.updateCache(pid:42){$0=new}
  await drain();precondition(Delivery.batches.isEmpty,"Unchanged entries must not publish")
  manager.updateCache(pid:42){$0=old}
  await drain();let reverse=Delivery.batches[0]
  precondition(Delivery.batches.count==1 && same((Set(reverse.removed),Set(reverse.added),reverse.updated),reference(new,old)))
  Delivery.batches=[]
  enum Failure:Error {case expected}
  do {
   try await manager.withCoordinatorNotificationsSuppressed(for:42) {
    manager.writeCache(pid:42,windowSet:new)
    try await manager.withCoordinatorNotificationsSuppressed(for:42){manager.updateCache(pid:42){$0=[window(9)]}}
    manager.writeCache(pid:43,windowSet:[window(1,pid:43)])
    await drain();precondition(Delivery.batches.count==1 && Delivery.batches[0].added.allSatisfy{$0.app.processIdentifier==43},"Suppression must be per app")
    throw Failure.expected
   }
  } catch Failure.expected {}
  precondition(signatures(manager.readCache(pid:42))==signatures([window(9)]),"Suppression must not discard cache writes")
  Delivery.batches=[]
  manager.updateCache(pid:42){$0=[window(9,image:1)]}
  await drain();precondition(Delivery.batches.count==1 && Delivery.batches[0].updated.count==1,"Throwing/nested suppression must restore publication")
  Delivery.batches=[]
  manager.writeCache(pid:42,windowSet:[]);manager.writeCache(pid:42,windowSet:[window(10)])
  await drain();precondition(Delivery.batches.count==1 && Delivery.batches[0].removed.count==1 && Delivery.batches[0].added.count==1,"Writes in one turn must retain existing batching")
  manager.purgeAll();await drain();precondition(manager.getAllWindows().isEmpty)
  print("PASS production cache reconciliation: \(cases) reference comparisons, duplicate IDs/AX replacement/image/metadata/removal cases, real write/update paths, deferred batches, per-app nested/throwing suppression and purge; inert windows only")
 }
}
SWIFT
Dir.mktmpdir('dockfork-cache-reconciliation-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Cache checks compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Cache checks failed' unless system("#{dir}/checks")
end
%w[writeCache updateCache].each do |name|
  method=block(cache,"    func #{name}(")
  abort "#{name} must retain lock and suppression before comparison" unless method.index('cacheLock.lock()') < method.index('guard suppressionDepth == 0') && method.index('guard suppressionDepth == 0') < method.index('let changes = Self.changes(') && method.include?('defer { cacheLock.unlock() }')
  order=%w[notifyCoordinatorOfRemovedWindows notifyCoordinatorOfAddedWindows notifyCoordinatorOfUpdatedWindows].map{|call|method.index(call) or abort "Missing #{call}"}
  abort "#{name} notification order changed" unless order==order.sort
end
abort 'Diff helper must not reintroduce linear searches or native queries' if block(cache,'    static func changes(').match?(/first\(where:|AXUIElement|managedDisplays|NSWorkspace/)

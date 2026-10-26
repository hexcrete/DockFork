#!/usr/bin/env ruby
require 'tmpdir'
measure_invalidation = ARGV.delete('--measure-invalidation')
abort "Unknown arguments: #{ARGV.join(' ')}" unless ARGV.empty?

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
# Keep real cache locking, diffing, suppression, batching and delivery; record drained batches.
production = production.sub('let batch = takePendingCoordinatorChanges()', 'let batch = takePendingCoordinatorChanges(); Delivery.batches.append(batch)')
source = <<~'SWIFT'
import Foundation
typealias CGWindowID=Int
typealias CGImage=Int
struct PreviewWindowIdentity {
 let pid:Int32;let windowID:Int
 init(pid:Int32,windowID:Int){self.pid=pid;self.windowID=windowID}
 init(_ window:WindowInfo){self.init(pid:window.app.processIdentifier,windowID:window.id)}
}
final class WindowSnapRegistry {
 static var existing:WindowSnapRegistry?
 var hasRecords=true,updates:[WindowInfo]=[]
 func remove(_ identity:PreviewWindowIdentity){}
 func reconcileCachedWindows(_ windows:[WindowInfo]){updates+=windows}
}
enum Key {case enableSpacesBar}
enum Defaults {static var enabled=true;static subscript(_ key:Key)->Bool {enabled}}
final class PreviewState {
 var windowSwitcherActive=true,updates:[WindowInfo]=[]
 func applyCacheChanges(removed:[WindowInfo],added:[WindowInfo],updated:[WindowInfo]){updates+=updated}
}
final class SharedPreviewWindowCoordinator {
 static var activeInstance:SharedPreviewWindowCoordinator?
 let windowSwitcherCoordinator=PreviewState()
 enum Reason {case topology}
 var refreshes=0,fullPreviewUpdates:[WindowInfo]=[]
 func requestSpacesBarRefresh(_ reason:Reason){refreshes+=1}
 func refreshDisplayedFullPreview(after updates:[WindowInfo]){fullPreviewUpdates+=updates}
}
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
 var imageCapturedTime=Date.distantPast
 var image:CGImage? {get {viewSnapshot.image==0 ? nil:viewSnapshot.image} set {viewSnapshot.image=newValue ?? 0}}
 static func ==(lhs:Self,rhs:Self)->Bool {lhs.rawID==rhs.rawID && lhs.app.processIdentifier==rhs.app.processIdentifier && lhs.ax==rhs.ax}
 func hash(into hasher:inout Hasher){hasher.combine(rawID);hasher.combine(app.processIdentifier)}
}
enum DebugLogger {static func log(_ event:String,details:String){}}
typealias Changes=(removed:Set<WindowInfo>,added:Set<WindowInfo>,updated:[WindowInfo])
enum Delivery {static var batches:[(removed:[WindowInfo],added:[WindowInfo],updated:[WindowInfo],refreshSpacesBar:Bool)]=[]}
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
if measure_invalidation
  source += <<~'SWIFT'
// Synthetic metadata comparison is a measurement model, not a proposed production key.
struct Metadata:Hashable {
 let identity:Signature
 let recency:Date
 init(_ w:WindowInfo){var metadata=w;metadata.image=nil;identity=Signature(metadata);recency=w.lastAccessedTime}
}
@MainActor func measureInvalidation() async {
 let repetitions=100
 for count in [16,512] {
  for kind in ["unchanged-write","unchanged-update","known-image","generic-image","recency","state","membership"] {
   let manager=SpaceWindowCacheManager()
   manager.writeCache(pid:42,windowSet:Set((1...count).map{window($0,image:1)}))
   var preparedRevision=manager.readSnapshot().revision
   var misses=0,revisions=0,unchanged=0,unchangedValues=0,comparedRows=0,writerNS:UInt64=0,comparisonNS:UInt64=0
   for step in 1...repetitions {
    let before=manager.readSnapshot()
    let old=Set(before.windows)
    var next=old
    if kind=="membership" {
     next.remove(next.first(where:{$0.rawID==count+step-1})!)
     next.insert(window(count+step,image:1))
    } else if !kind.hasPrefix("unchanged") {
     var w=next.first(where:{$0.rawID==1})!;next.remove(w)
     if kind=="recency" {w.lastAccessedTime=Date(timeIntervalSince1970:Double(step))}
     else if kind=="state" {w.viewSnapshot.minimized.toggle()}
     else {w.image=step+1}
     next.insert(w)
    }
    let compareStart=DispatchTime.now().uptimeNanoseconds
    let equivalent=Set(old.map(Metadata.init))==Set(next.map(Metadata.init))
    comparisonNS+=DispatchTime.now().uptimeNanoseconds-compareStart
    comparedRows+=old.count+next.count
    if equivalent {unchanged+=1}
    if equivalent && signatures(old)==signatures(next) {unchangedValues+=1}
    let start=DispatchTime.now().uptimeNanoseconds
    switch kind {
    case "known-image":manager.updateImage(pid:42,windowID:1,image:step+1,capturedAt:Date(timeIntervalSince1970:Double(step)))
    case "unchanged-update","generic-image","recency","state":manager.updateCache(pid:42){$0=next}
    default:manager.writeCache(pid:42,windowSet:next)
    }
    writerNS+=DispatchTime.now().uptimeNanoseconds-start
    let after=manager.readSnapshot()
    revisions+=Int(after.revision-before.revision)
    // One filter interaction after each write, with all other preparation-key fields held fixed.
    if after.revision != preparedRevision {misses+=1;preparedRevision=after.revision}
   }
   let expectsChange=["recency","state","membership"].contains(kind)
   precondition(unchanged==(expectsChange ? 0:repetitions))
   precondition(unchangedValues==(kind.hasPrefix("unchanged") ? repetitions:0))
   precondition(revisions==(kind=="known-image" ? 0:repetitions) && misses==revisions)
   print("MEASURE windows=\(count) case=\(kind) writes=\(repetitions) genericWrites=\(kind=="known-image" ? 0:repetitions) unchangedValues=\(unchangedValues) unchangedMetadata=\(unchanged) revisionChanges=\(revisions) revisionKeyMisses=\(misses) comparisonRows=\(comparedRows) writerMs=\(Double(writerNS)/1e6) comparisonMs=\(Double(comparisonNS)/1e6)")
  }
 }
 print("PASS measurement only: source-extracted writers; one simulated filter interaction per write; modeled metadata comparison; no native discovery, production instrumentation or invalidation-policy change")
}
SWIFT
  keys=File.read("#{root}/DockDoor/Utilities/KeybindHelper.swift")
  filter=block(keys,'    private func installSpaceFilter(')
  abort 'Revision-key miss model no longer matches preparation guard' unless filter.include?('revision: snapshot.revision') && filter.include?('if preparedKey != key || coordinator.preparedSpaceFilterCandidates == nil')
end
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

  let images=SpaceWindowCacheManager(),preview=SharedPreviewWindowCoordinator(),registry=WindowSnapRegistry()
  SharedPreviewWindowCoordinator.activeInstance=preview;WindowSnapRegistry.existing=registry
  var resident=window(20,image:1)
  resident.viewSnapshot.title="Current native tab";resident.viewSnapshot.space=7
  resident.viewSnapshot.hidden=true;resident.viewSnapshot.minimized=true;resident.viewSnapshot.fullscreen=true
  resident.lastAccessedTime=Date(timeIntervalSince1970:10)
  images.writeCache(pid:42,windowSet:[resident]);await drain()
  let initial=preview.refreshes
  for image in 2...9 {
   images.updateImage(pid:42,windowID:20,image:image,capturedAt:Date(timeIntervalSince1970:Double(image)))
   await drain()
  }
  precondition(preview.refreshes==initial && preview.windowSwitcherCoordinator.updates.count==8 && preview.fullPreviewUpdates.count==8 && registry.updates.count==8,"Image-only batches must reach all original consumers without bar metadata refresh")
  let current=images.readCache(pid:42).first!
  var expected=resident;expected.image=9
  precondition(signatures([current])==signatures([expected]) && current.lastAccessedTime==resident.lastAccessedTime && current.imageCapturedTime==Date(timeIntervalSince1970:9),"Captures must retain current identity, tab title, state, Space and recency")
  print("COUNT 8 separate image-only batches: Spaces Bar refresh requests before=8, after=\(preview.refreshes-initial); small/full-preview deliveries=8 each")
  Delivery.batches=[]
  images.updateImage(pid:42,windowID:20,image:10,capturedAt:Date())
  images.updateImage(pid:42,windowID:20,image:11,capturedAt:Date())
  await drain()
  precondition(Delivery.batches.count==1 && Delivery.batches[0].updated.count==2 && !Delivery.batches[0].refreshSpacesBar,"Image-only batching must retain every image update")

  for metadataFirst in [false,true] {
   Delivery.batches=[];let refreshes=preview.refreshes
   func metadata(){images.updateCache(pid:42){windows in var w=windows.first!;windows.remove(w);w.viewSnapshot.space+=1;windows.insert(w)}}
   if metadataFirst {metadata()}
   images.updateImage(pid:42,windowID:20,image:metadataFirst ? 12:13,capturedAt:Date())
   if !metadataFirst {metadata()}
   await drain()
   precondition(Delivery.batches.count==1 && Delivery.batches[0].refreshSpacesBar && preview.refreshes==refreshes+1,"Mixed batches must keep metadata work in either arrival order")
  }
  let generic=preview.refreshes
  images.updateCache(pid:42){windows in var w=windows.first!;windows.remove(w);w.image=14;windows.insert(w)}
  await drain();precondition(preview.refreshes==generic+1,"Unknown/generic image writes must retain topology fallback")
  images.writeCache(pid:42,windowSet:[window(20,ax:200,image:15),window(21)])
  images.updateImage(pid:42,windowID:20,image:16,capturedAt:Date())
  await drain();precondition(preview.refreshes==generic+2,"Membership/AX replacement must keep metadata work when an image arrives too")
  Delivery.batches=[]
  let known=images.readCache(pid:42).first(where:{$0.id==20})!
  images.updateImage(pid:42,windowID:20,image:16,capturedAt:Date(timeIntervalSince1970:99))
  images.updateImage(pid:42,windowID:20,image:17,capturedAt:Date(),missingOnly:true)
  images.updateImage(pid:42,windowID:20,image:18,capturedAt:Date(),rejectIfImageExists:true)
  images.updateImage(pid:99,windowID:20,image:18,capturedAt:Date())
  images.updateImage(pid:42,windowID:999,image:18,capturedAt:Date())
  await drain()
  precondition(Delivery.batches.isEmpty && signatures(images.readCache(pid:42).filter{$0.id==20})==signatures([known]),"Same-image, missing-only, rejected and absent targets must not publish or create rows")
  precondition(images.readCache(pid:42).first(where:{$0.id==20})!.imageCapturedTime==Date(timeIntervalSince1970:99),"Same-pointer capture timestamps still update silently")
  images.updateImage(pid:42,windowID:21,image:19,capturedAt:Date(),rejectIfImageExists:true)
  await drain();precondition(images.readCache(pid:42).first(where:{$0.id==21})!.image==19,"Preserve rejected-image fallback when no prior image exists")
  Delivery.batches=[]
  try await images.withCoordinatorNotificationsSuppressed(for:42){images.updateImage(pid:42,windowID:20,image:20,capturedAt:Date())}
  await drain();precondition(Delivery.batches.isEmpty && images.readCache(pid:42).first(where:{$0.id==20})!.image==20,"Image writes must honor existing suppression")
  images.writeCache(pid:42,windowSet:[])
  images.updateImage(pid:42,windowID:20,image:21,capturedAt:Date())
  await drain();precondition(images.readCache(pid:42).isEmpty,"A completed capture must not resurrect a removed row")
  images.writeCache(pid:42,windowSet:[window(20,image:1)]);await drain()
  let gated=preview.refreshes
  Defaults.enabled=false
  images.updateImage(pid:42,windowID:20,image:2,capturedAt:Date())
  images.updateCache(pid:42){$0.insert(window(22))};await drain()
  precondition(preview.refreshes==gated,"Disabled Spaces Bar must do no cache-triggered work")
  Defaults.enabled=true;preview.windowSwitcherCoordinator.windowSwitcherActive=false
  images.writeCache(pid:42,windowSet:[window(20,image:3)]);await drain()
  precondition(preview.refreshes==gated,"Inactive switcher must do no bar work")
  preview.windowSwitcherCoordinator.windowSwitcherActive=true
  images.updateImage(pid:42,windowID:20,image:4,capturedAt:Date())
  SharedPreviewWindowCoordinator.activeInstance=nil;await drain()
  precondition(preview.refreshes==gated,"Teardown before deferred delivery must not refresh the old preview")
  WindowSnapRegistry.existing=nil
  let revisions=SpaceWindowCacheManager()
  revisions.writeCache(pid:42,windowSet:[window(1)])
  let start=revisions.readSnapshot().revision
  revisions.updateImage(pid:42,windowID:1,image:1,capturedAt:Date())
  precondition(revisions.readSnapshot().revision==start,"Image-only writes must preserve candidate validity")
  revisions.updateCache(pid:42){windows in var w=windows.first!;windows.remove(w);w.lastAccessedTime=Date();windows.insert(w)}
  precondition(revisions.readSnapshot().revision==start+1,"Recency-only writes must invalidate candidates even without view notifications")
  try await revisions.withCoordinatorNotificationsSuppressed(for:42){revisions.updateCache(pid:42){$0.insert(window(2))}}
  precondition(revisions.readSnapshot().revision==start+2,"Suppressed metadata mutations must invalidate candidates")
  revisions.removeFromCache(pid:42,windowId:2)
  precondition(revisions.readSnapshot().revision==start+3 && revisions.readSnapshot().windows.count==1,"Removal and snapshot revision must be atomic")
  await drain()
  print("PASS production screenshot delivery: image-only and mixed batches, conservative unknown writes, AX/tab/membership changes, unchanged metadata, missing/rejected images, suppression, removal, disabled/inactive paths and teardown; no native queries")
 }
}
SWIFT
source=source.sub('  var cases=0', '  if CommandLine.arguments.contains("--measure-invalidation") {await measureInvalidation(); return}' + "\n  var cases=0") if measure_invalidation
Dir.mktmpdir('dockfork-cache-reconciliation-') do |dir|
  File.write("#{dir}/checks.swift", source)
  options=measure_invalidation ? ['-O']:[]
  abort 'Cache checks compilation failed' unless system('swiftc', *options, '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  arguments=measure_invalidation ? ['--measure-invalidation']:[]
  abort 'Cache checks failed' unless system("#{dir}/checks", *arguments)
end
%w[writeCache updateCache].each do |name|
  method=block(cache,"    func #{name}(")
  abort "#{name} must retain lock and suppression before comparison" unless method.index('cacheLock.lock()') < method.index('guard suppressionDepth == 0') && method.index('guard suppressionDepth == 0') < method.index('let changes = Self.changes(') && method.include?('defer { cacheLock.unlock() }')
  order=%w[notifyCoordinatorOfRemovedWindows notifyCoordinatorOfAddedWindows notifyCoordinatorOfUpdatedWindows].map{|call|method.index(call) or abort "Missing #{call}"}
  abort "#{name} notification order changed" unless order==order.sort
end
abort 'Diff helper must not reintroduce linear searches or native queries' if block(cache,'    static func changes(').match?(/first\(where:|AXUIElement|managedDisplays|NSWorkspace/)

image_writer=block(cache,'    func updateImage(')
abort 'Image-only writer must remain limited to existing rows and image fields' unless image_writer.include?('let previous = windows.first(') && image_writer.scan(/current\.\w+ =/).sort==['current.image =','current.imageCapturedTime ='] && image_writer.include?('refreshSpacesBar: false')
abort 'Image writer must not add native queries inside the cache lock' if image_writer.match?(/AXUIElement|managedDisplays|NSWorkspace|shouldRejectCapturedImage/)
util=File.read("#{root}/DockDoor/Utilities/Window Management/WindowUtil.swift")
%w[forceRefreshCachedWindowImages refreshCachedWindowImagesAfterOpenNewWindow].each do |name|
  method=block(util,"    static func #{name}(")
  abort "#{name} must not merge stale metadata from capture results" unless method.include?('updateCachedWindowImage(image, for: window)') && !method.include?('updateDesktopSpaceWindowCache(')
end
abort 'Resize recapture must retain metadata/topology publication' unless block(util,'    private static func scheduleForcedPreviewRecapture(').include?('updateDesktopSpaceWindowCache(with: refreshedWindowInfo)')
puts 'PASS image-only routing and conservative resize/discovery refresh contracts'

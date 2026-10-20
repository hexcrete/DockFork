#!/usr/bin/env ruby
# Compile the production discovery rules. Optional --live PID only reads that app's focused window.
require 'tmpdir'
require 'open3'

def block(source, signature)
  start = source.index(signature) or abort "Missing #{signature}"
  first = source.index('{', start)
  depth = 0
  (first...source.length).each do |i|
    depth += 1 if source[i] == '{'
    depth -= 1 if source[i] == '}'
    return source[start..i] if depth.zero?
  end
  abort "Unclosed #{signature}"
end
root = File.expand_path('../..', __dir__)
shared = File.read("#{root}/DockDoor/Utilities/Window Management/WindowDiscoveryShared.swift")
ax = File.read("#{root}/DockDoor/Extensions/AXUIElement.swift")
util = File.read("#{root}/DockDoor/Utilities/Window Management/WindowUtil.swift")
abort 'AX discovery must pass app identity into both existing candidate scans' unless block(ax, '    static func allWindows(').scan('unreachedCGWindowIDs(in: candidates, excluding: knownIDs, app: app)').size == 2
abort 'Startup retry must share candidate acceptance' unless block(util, '    static func shouldRetryStartupDiscovery(').include?('excluding: cachedIDs.union(ignoredIDs), app: app)')
abort 'SCK must share layer acceptance using the actual owner' unless block(util, '    static func captureAndCacheWindowInfo(').include?('WindowCandidateDiscriminator.acceptsWindowLayer(app: ownerApp, level: Int32(window.windowLayer), frame: window.frame)')
abort 'Elevated candidates must not bypass named AX-window validation through buttons' unless block(util, '    static func captureAndCacheWindowInfo(').include?('(window.windowLayer == 0 && (closeButton != nil || minimizeButton != nil)) ||')
source = <<~'SWIFT'
import Cocoa
struct WindowCandidateAttributes {
 var title: String? = "Game", role: String? = kAXWindowRole, subrole: String? = "AXUnknown"
 var size: CGSize? = CGSize(width:1512,height:982), position: CGPoint? = .zero
 var hasCloseButton = false
}
enum Key { case disableMinWindowSizeFilter, enableLivePreview }
enum Defaults { static subscript(_ key: Key) -> Bool { false } }
SWIFT
live_pid = ARGV[0] == '--live' && Integer(ARGV[1], exception: false)
abort 'Usage: wine_discovery.rb [--live PID]' unless ARGV.empty? || (live_pid && live_pid > 0 && ARGV.size == 2)
unless live_pid
  source += <<~'SWIFT'
struct NSRunningApplication { var bundleIdentifier: String?; var executableURL: URL? }
enum Displays {
 static var reads = 0, fails = false
 static var frames: [CGRect] = [CGRect(x:0,y:0,width:1512,height:982),CGRect(x:-1920,y:200,width:1920,height:1080)]
}
func CGGetDisplaysWithPoint(_ point: CGPoint, _ limit: UInt32, _ display: UnsafeMutablePointer<CGDirectDisplayID>?, _ count: UnsafeMutablePointer<UInt32>?) -> CGError {
 Displays.reads += 1
 if Displays.fails { return .failure }
 let index = Displays.frames.firstIndex { $0.contains(point) }
 count?.pointee = index == nil ? 0 : 1
 if let index { display?.pointee = UInt32(index + 1) }
 return .success
}
func CGDisplayBounds(_ display: CGDirectDisplayID) -> CGRect { Displays.frames[Int(display)-1] }
enum Server { static var spaces: [UInt32:[Int]] = [1:[7]]; static var internalIDs: Set<UInt32> = [] }
extension UInt32 { func cgsSpaces() -> [UInt64] { (Server.spaces[self] ?? []).map(UInt64.init) } }
enum WindowUtil { static func isInternalWindow(_ id: UInt32) -> Bool { Server.internalIDs.contains(id) } }
enum WindowSpaces { static func allManagedSpaceIDs() -> Set<Int> { [4,7] } }
func currentActiveSpaceIDs() -> Set<Int> { [4] }
SWIFT
end
source += block(shared, 'enum WindowCandidateDiscriminator {') + "\n"
if live_pid
  source += <<~SWIFT
@_silgen_name("_AXUIElementGetWindow") func windowID(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError
func read(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
 var value: CFTypeRef?
 return AXUIElementCopyAttributeValue(element,name as CFString,&value) == .success ? value : nil
}
let pid: pid_t = #{live_pid}
guard AXIsProcessTrusted(), let app = NSRunningApplication(processIdentifier:pid) else { fatalError("AX permission or running app unavailable") }
let application = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(application,1)
guard let value = read(application,kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { fatalError("No focused window exposed") }
let window = value as! AXUIElement
var id: CGWindowID = 0
precondition(windowID(window,&id) == .success && id != 0)
var position = CGPoint.zero, size = CGSize.zero
if let value = read(window,kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() { AXValueGetValue(value as! AXValue,.cgPoint,&position) }
if let value = read(window,kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() { AXValueGetValue(value as! AXValue,.cgSize,&size) }
let entries = CGWindowListCopyWindowInfo([.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
guard let entry = entries.first(where:{($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id}),
 let level = (entry[kCGWindowLayer as String] as? NSNumber)?.int32Value else { fatalError("WindowServer entry unavailable") }
let attributes = WindowCandidateAttributes(title:read(window,kAXTitleAttribute) as? String,role:read(window,kAXRoleAttribute) as? String,subrole:read(window,kAXSubroleAttribute) as? String,size:size,position:position)
let rejection = WindowCandidateDiscriminator.rejectionReason(app:app,windowID:id,level:level,attributes:attributes)
print("Read-only live discovery: pid=\\(pid) window=\\(id) title=\\(attributes.title ?? "") level=\\(level) frame=\\(CGRect(origin:position,size:size)) rejection=\\(rejection ?? "none") AXFullScreen=\\(String(describing:read(window,"AXFullScreen")))")
precondition(rejection == nil, "Real window still rejected")
SWIFT
else
  source += block(shared, 'func isValidCGWindowEntry(') + "\n" + block(shared, 'func unreachedCGWindowIDs(') + "\n"
  baseline, status = Open3.capture2('git', '-C', root, 'show', '2a64ca4dfc65ea1fd5e468eaeb5c8d452f702ae7:DockDoor/Utilities/Window Management/WindowDiscoveryShared.swift')
  abort 'Missing committed discovery baseline' unless status.success?
  source += block(baseline, 'enum WindowCandidateDiscriminator {').sub('enum WindowCandidateDiscriminator', 'enum BaselineDiscriminator') + "\n"
  source += <<~'SWIFT'
let wine = NSRunningApplication(bundleIdentifier:nil,executableURL:URL(fileURLWithPath:"/tmp/winetemp-test/Game.exe"))
let preloader = NSRunningApplication(bundleIdentifier:nil,executableURL:URL(fileURLWithPath:"/opt/wine/bin/wine64-preloader"))
let helper = NSRunningApplication(bundleIdentifier:"com.codeweavers.CrossOverHelper.test",executableURL:nil)
let native = NSRunningApplication(bundleIdentifier:"org.example.App",executableURL:nil)
let unknown = NSRunningApplication(bundleIdentifier:nil,executableURL:URL(fileURLWithPath:"/opt/tools/other"))
let spoofed = NSRunningApplication(bundleIdentifier:"org.example.App",executableURL:wine.executableURL)
let game = WindowCandidateAttributes()
func accepted(_ app: NSRunningApplication, _ attributes: WindowCandidateAttributes, _ level: Int32) -> Bool {
 WindowCandidateDiscriminator.isActualWindow(app:app,windowID:1,level:level,attributes:attributes)
}
let status = CGWindowLevelForKey(.statusWindow)+1, shielding = CGShieldingWindowLevel()+1
for app in [wine,preloader,helper] {
 for level in [status,status+1,shielding,shielding+1] {
  precondition(accepted(app,game,level))
  for frame in Displays.frames {
   var attributes = game; attributes.position = frame.origin; attributes.size = frame.size
   precondition(accepted(app,attributes,level), "Secondary display coordinates must use Quartz geometry")
  }
 }
}
var comparisons = 0
for app in [wine,preloader,helper,native,unknown,spoofed] {
 for level: Int32 in [0,3,8,24,25,status,status+1,101,1000,shielding,shielding+1] {
  for title: String? in [nil,""," ","Game"] {
   for subrole: String? in [nil,"AXUnknown",kAXStandardWindowSubrole,kAXDialogSubrole] {
    for frame in [Displays.frames[0],CGRect(x:0,y:482,width:500,height:500),CGRect(x:0,y:0,width:1512,height:33)] {
     var a = game; a.title=title; a.subrole=subrole; a.position=frame.origin; a.size=frame.size
     let previous = BaselineDiscriminator.isActualWindow(app:app,windowID:1,level:level,attributes:a)
     let current = accepted(app,a,level)
     let knownWine = app.bundleIdentifier == helper.bundleIdentifier ||
      (app.bundleIdentifier == nil && [wine.executableURL,preloader.executableURL].contains(app.executableURL))
     let added = [status,status+1,shielding,shielding+1].contains(level) && knownWine
     let expected = added && title == "Game" && subrole == "AXUnknown" && frame == Displays.frames[0]
     precondition(current == (previous || expected), "Unexpected acceptance change: \(app) \(level) \(a)")
     comparisons += 1
    }
   }
  }
 }
}
var a = game; a.role = kAXGroupRole; precondition(!accepted(wine,a,status))
a = game; a.position = nil; precondition(!accepted(wine,a,status))
a = game; a.size = CGSize(width:CGFloat.nan,height:982); precondition(!accepted(wine,a,status))
a = game; a.position = CGPoint(x:1,y:0); precondition(accepted(wine,a,status))
a.position = CGPoint(x:2,y:0); precondition(!accepted(wine,a,status))
let reads = Displays.reads
precondition(WindowCandidateDiscriminator.acceptsWindowLayer(app:nil,level:0,frame:.zero))
precondition(!WindowCandidateDiscriminator.acceptsWindowLayer(app:native,level:status,frame:Displays.frames[0]))
precondition(!WindowCandidateDiscriminator.acceptsWindowLayer(app:wine,level:101,frame:Displays.frames[0]))
precondition(Displays.reads == reads, "Normal/non-Wine/unsupported levels must not query displays")
func entry(_ id: UInt32, _ frame: CGRect, level: Int32 = status) -> [String:AnyObject] {
 [kCGWindowNumber as String:NSNumber(value:id),kCGWindowLayer as String:NSNumber(value:level),kCGWindowBounds as String:frame.dictionaryRepresentation]
}
let candidates = [entry(1,Displays.frames[0]),entry(2,CGRect(x:0,y:0,width:1512,height:33),level:0),entry(3,CGRect(x:0,y:482,width:500,height:500))]
precondition(unreachedCGWindowIDs(in:candidates,excluding:[],app:wine) == [1])
precondition(unreachedCGWindowIDs(in:candidates,excluding:[1],app:wine).isEmpty)
precondition(unreachedCGWindowIDs(in:candidates,excluding:[],app:native).isEmpty)
precondition(unreachedCGWindowIDs(in:candidates,excluding:[]).isEmpty)
var missingLayer = entry(1,Displays.frames[0]); missingLayer.removeValue(forKey:kCGWindowLayer as String)
precondition(unreachedCGWindowIDs(in:[missingLayer],excluding:[],app:wine).isEmpty)
Server.internalIDs = [1]; precondition(unreachedCGWindowIDs(in:candidates,excluding:[],app:wine).isEmpty)
Server.internalIDs = []; Server.spaces[1] = [8]; precondition(unreachedCGWindowIDs(in:candidates,excluding:[],app:wine).isEmpty)
Server.spaces[1] = [7]; Displays.fails = true
precondition(!accepted(wine,game,status))
precondition(unreachedCGWindowIDs(in:candidates,excluding:[],app:wine).isEmpty)
Displays.fails = false; Displays.frames = []
precondition(!accepted(wine,game,status))
print("PASS \(comparisons) baseline comparisons: only named screen-sized known Wine/CrossOver fullscreen windows newly accepted; helper, role, identity, level, geometry, display-error and internal/known/removed-Space exclusions retained")
print("PASS shared SCK/AX/startup routing and no display queries for normal/non-Wine/unsupported-level windows; native fullscreen state unchanged")
SWIFT
end
Dir.mktmpdir('dockfork-wine-discovery-') do |dir|
  File.write("#{dir}/checks.swift",source)
  output, status = Open3.capture2e('swiftc','-swift-version','5',"#{dir}/checks.swift",'-o',"#{dir}/checks")
  abort output unless status.success?
  output, status = Open3.capture2e("#{dir}/checks")
  puts output
  abort 'Wine discovery checks failed' unless status.success?
end

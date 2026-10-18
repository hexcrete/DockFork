#!/usr/bin/env ruby
# Run the production pure grouping tests without launching apps or requiring an Xcode test host.
require 'tmpdir'
require 'open3'
root = File.expand_path('../..', __dir__)
grouping = File.read("#{root}/DockDoor/Utilities/Window Management/NativeTabGrouping.swift")
tests = File.read("#{root}/DockDoorTests/NativeTabGroupingTests.swift")
methods = tests.scan(/@Test func (\w+)\(\)/).flatten
abort 'No native-tab grouping cases found' if methods.empty?
checks = tests.sub('@testable import DockDoor', '').sub('import Testing', '').gsub('@Test ', '').gsub('#expect(', 'precondition(')
runner = "\n@main struct Checks { static func main() {\n" + methods.map { |name| "NativeTabGroupingTests().#{name}()" }.join("\n") + "\nprint(\"PASS #{methods.size} production native-tab grouping cases\")\n} }\n"
Dir.mktmpdir('native-tab-grouping-') do |dir|
  File.write("#{dir}/checks.swift", grouping + "\n" + checks + runner)
  output, status = Open3.capture2e('xcrun', 'swiftc', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort output unless status.success?
  output, status = Open3.capture2e("#{dir}/checks")
  puts output
  abort 'Native-tab grouping tests failed' unless status.success?
end

# Exercise actual discovery acceptance, including the previously unlearned-tab reproduction.
def swift_function(source, signature)
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
shared = File.read("#{root}/DockDoor/Utilities/Window Management/WindowDiscoveryShared.swift")
policy = swift_function(shared, 'func shouldExcludeInactiveNativeTab(') + "\n" + swift_function(shared, 'func shouldAcceptWindow(')
baseline, status = Open3.capture2('git', '-C', root, 'show', 'd8d1a61d5de9f70d2152db27f1f331cc0e6fcfc6:DockDoor/Utilities/Window Management/WindowDiscoveryShared.swift')
abort 'Missing pre-fix discovery baseline' unless status.success?
policy += "\n" + swift_function(baseline, 'func shouldAcceptWindow(').sub('func shouldAcceptWindow(', 'func baselineAcceptsWindow(')
util = File.read("#{root}/DockDoor/Utilities/Window Management/WindowUtil.swift")
purify = swift_function(util, '    static func purifyAppCache(')
abort 'Cached minimized/hidden rows must use the same native-tab policy' unless purify.include?('shouldRemove = shouldExcludeInactiveNativeTab(') && purify.include?('window.isMinimized || window.isHidden, window.isFullscreen == false') && purify.include?('!hasValidCGWindow')
cache_decision = purify[purify.index('                var shouldRemove =')...purify.index('                if shouldRemove {')]
dock = File.read("#{root}/DockDoor/Utilities/DockObserver.swift")
cache_to_filter = dock[dock.index('        var cachedWindows: [WindowInfo] = []')...dock.index('        // Filter cached windows by current space before showing preview')]
abort 'Dock must not collapse the same cache twice' unless cache_to_filter.scan('collapseNativeTabsIfNeeded').size == 1
fixture = <<~'SWIFT'
import Foundation
import CoreGraphics
struct Key { static let collapseNativeTabsIntoSingleWindow = Key() }
enum Defaults { static var collapse = true; static subscript(_ key: Key) -> Bool { collapse } }
let kAXMainAttribute = "AXMain"
struct AXUIElement {
 var minimized = false, fullscreen = false, main = false
 func isFullscreen() throws -> Bool? { Server.fullscreenQueryFails ? nil : fullscreen }
 func isMinimized() throws -> Bool? { minimized }
 func closeButton() throws -> Int? { 1 }
 func minimizeButton() throws -> Int? { 1 }
 func attribute<T>(_ key: String, _ type: T.Type) throws -> T? { main as? T }
}
struct NSRunningApplication { var processIdentifier: Int32 = 777; var isHidden = false }
struct CachedWindow {
 let id: UInt32 = 1
 var axElement = AXUIElement()
 var app = NSRunningApplication(), ownerApp = NSRunningApplication()
 var isMinimized = true, isHidden = false
 var isFullscreen: Bool? = false
 var scWindow: Int? = nil
}
enum WindowOwnerResolver { static func ownerBelongsToDisplayApp(_ owner: NSRunningApplication, displayApp: NSRunningApplication) -> Bool { true } }
func isValidElement(_ element: AXUIElement) -> Bool { true }
func findCGEntry(for id: UInt32, in candidates: [[String: AnyObject]]) -> [String: AnyObject]? { candidates.first }
func isValidCGWindowEntry(_ entry: [String: AnyObject]) -> Bool { (entry["valid"] as? NSNumber)?.boolValue == true }
enum WindowUtil { static func isInternalWindow(_ id: UInt32) -> Bool { false } }
enum WindowSpaces { static func allManagedSpaceIDs() -> Set<Int> { [4, 7] } }
enum Server { static var spaces: [Int] = []; static var ordered: Bool? = false; static var reads = 0; static var spaceReads = 0; static var spaceQueryFails = false; static var fullscreenQueryFails = false }
typealias CGSSpaceID = UInt64
let kCGSAllSpacesMask: UInt64 = 7
func CGSMainConnectionID() -> UInt32 { 0 }
func CGSCopySpacesForWindows(_ connection: UInt32, _ mask: UInt64, _ windows: CFArray) -> CFArray? {
 Server.spaceReads += 1
 return Server.spaceQueryFails ? nil : Server.spaces.map { NSNumber(value: $0) } as CFArray
}
func SLSWindowIsOrderedIn(_ id: UInt32) -> Bool? { Server.reads += 1; return Server.ordered }
func isNoninteractiveUntitledDialog(_ el: AXUIElement) -> Bool { false }
SWIFT
space_source = File.read("#{root}/DockDoor/Extensions/CoreGraphics/CGWindowID.swift")
fixture += "\nextension UInt32 {\n" + swift_function(space_source, '    func cgsSpaces()') + "\n" + swift_function(space_source, '    func cgsSpacesIfAvailable()') + "\n}\n"
fixture += policy + "\n"
fixture += "\nfunc cachedSurvives(_ window: CachedWindow, entry: [String: AnyObject]?) -> Bool {\nlet geometryAliasWindowIDs: Set<UInt32> = []\nlet cgCandidates = entry.map { [$0] } ?? []\nlet activeSpaceIDs: Set<Int> = [4]\nlet managedSpaceIDs: Set<Int> = [4, 7]\n" + cache_decision + "\nreturn !shouldRemove\n}\n"
fixture += <<~'SWIFT'
@main struct Checks {
 static func accepted(minimized: Bool = true, hidden: Bool = false, fullscreen: Bool = false, onscreen: Bool = false, captured: Bool = false) -> Bool {
  shouldAcceptWindow(axWindow: AXUIElement(minimized: minimized, fullscreen: fullscreen), windowID: 1,
   cgEntry: [kCGWindowIsOnscreen as String: NSNumber(value: onscreen)],
   app: NSRunningApplication(isHidden: hidden), activeSpaceIDs: [4], scBacked: captured)
 }
 static func main() {
  var kept = 0
  for i in 0..<15 {
   Server.spaces = i < 3 ? [4] : []
   Server.ordered = i == 0
   if accepted(minimized: i != 0, onscreen: i == 0) { kept += 1 }
  }
  precondition(kept == 3, "Restoration must not turn 3 real windows into 15 rows even without prior grouping")
  Defaults.collapse = false; kept = 0
  for i in 0..<15 {
   Server.spaces = i < 3 ? [4] : []; Server.ordered = false
   if accepted() { kept += 1 }
  }
  precondition(kept == 15, "Disabled collapsing must preserve minimized-tab behavior")
  Defaults.collapse = true
  for minimized in [false,true] {
   for hidden in [false,true] where minimized || hidden {
    Server.spaces = [4]; Server.ordered = false; let before = Server.reads
    precondition(accepted(minimized:minimized,hidden:hidden))
    precondition(Server.reads == before, "Space-backed minimized/hidden windows need no extra native query")
    Server.spaces = [7]; precondition(accepted(minimized:minimized,hidden:hidden))
    Server.spaces = []; Server.ordered = false
    precondition(!accepted(minimized:minimized,hidden:hidden))
    precondition(accepted(minimized:minimized,hidden:hidden,fullscreen:true))
    precondition(accepted(minimized:minimized,hidden:hidden,onscreen:true))
    precondition(accepted(minimized:minimized,hidden:hidden,captured:true))
    Server.ordered = nil; precondition(accepted(minimized:minimized,hidden:hidden))
    Server.ordered = true; precondition(accepted(minimized:minimized,hidden:hidden))
   }
  }
  Server.spaces = []; Server.ordered = false
  let before = Server.reads
  Defaults.collapse = false; precondition(accepted()); precondition(Server.reads == before)
  Defaults.collapse = true; precondition(!accepted()); precondition(Server.reads == before+1)
  Server.spaceQueryFails = true
  let failedReads = Server.reads
  precondition(accepted(), "A failed Space query must not be treated as proof of an inactive tab")
  precondition(Server.reads == failedReads)
  precondition(UInt32(1).cgsSpaces().isEmpty, "Legacy callers retain their empty-on-error contract")
  Server.spaceQueryFails = false
  Server.fullscreenQueryFails = true
  precondition(accepted(), "A failed fullscreen read must not allow the new filter to hide a minimized window")
  precondition(Server.reads == failedReads)
  Server.fullscreenQueryFails = false
  Server.spaces = [4]; Server.ordered = false
  precondition(!accepted(minimized:false), "Ordinary ghost-window validation is unchanged")
  for collapse in [false, true] {
   Defaults.collapse = collapse
   for entry in [nil, ["valid": NSNumber(value: false)], ["valid": NSNumber(value: true)]] as [[String: AnyObject]?] {
    for (minimized,hidden) in [(true,false),(false,true),(true,true)] {
     var window = CachedWindow()
     window.isMinimized = minimized; window.isHidden = hidden; window.app.isHidden = hidden; window.axElement.minimized = minimized
     Server.spaces = []; Server.ordered = false
     let reads = Server.reads
     let spaceReads = Server.spaceReads
     precondition(cachedSurvives(window,entry:entry) == !collapse)
     precondition(Server.reads == reads + (collapse ? 1 : 0), "Cleanup must query native ordering at most once, and never when disabled")
     let hasValidRecord = (entry?["valid"] as? NSNumber)?.boolValue == true
     precondition(Server.spaceReads == spaceReads + (hasValidRecord || collapse ? 1 : 0), "Cleanup must not add a Space query when disabled or duplicate the normal acceptance query")
     Server.spaces = [7]; let mappedReads = Server.reads
     precondition(cachedSurvives(window,entry:entry)); precondition(Server.reads == mappedReads)
     Server.spaces = []; Server.ordered = nil; precondition(cachedSurvives(window,entry:entry))
     Server.ordered = true; precondition(cachedSurvives(window,entry:entry))
     Server.spaceQueryFails = true; Server.ordered = false
     precondition(cachedSurvives(window,entry:entry), "Cleanup must retain rows if Space metadata is unavailable")
     Server.spaceQueryFails = false
     window.isFullscreen = true; window.axElement.fullscreen = true
     Server.ordered = false; precondition(cachedSurvives(window,entry:entry))
     window.isFullscreen = nil; window.axElement.fullscreen = false
     if entry?["valid"] as? NSNumber != true { precondition(cachedSurvives(window,entry:entry)) }
    }
   }
  }
  var comparisons = 0
  for collapse in [false,true] {
   Defaults.collapse = collapse
   for flags in 0..<32 {
    let minimized = flags & 1 != 0, hidden = flags & 2 != 0, fullscreen = flags & 4 != 0
    let onscreen = flags & 8 != 0, captured = flags & 16 != 0
    for spaces in [[],[4],[7]] as [[Int]] {
     Server.spaces = spaces
     for ordered in [false,true,nil] as [Bool?] {
      Server.ordered = ordered
      let baseline = baselineAcceptsWindow(axWindow:AXUIElement(minimized:minimized,fullscreen:fullscreen),windowID:1,
       cgEntry:[kCGWindowIsOnscreen as String:NSNumber(value:onscreen)],app:NSRunningApplication(isHidden:hidden),activeSpaceIDs:[4],scBacked:captured)
      let excludedTab = collapse && (minimized || hidden) && !fullscreen && !onscreen && !captured && spaces.isEmpty && ordered == false
      precondition(accepted(minimized:minimized,hidden:hidden,fullscreen:fullscreen,onscreen:onscreen,captured:captured) == (baseline && !excludedTab))
      comparisons += 1
     }
    }
   }
  }
  print("PASS \(comparisons) baseline comparisons: only the intended enabled, minimized/hidden, unassigned, ordered-out state changes")
  print("PASS production discovery: unlearned 3-to-15 regression, disabled behavior, real minimized/hidden/off-Space windows, fullscreen/SCK/on-screen/error fallbacks and native-query gates")
  print("PASS production cache cleanup: valid/invalid/missing records, hidden/minimized/fullscreen/unknown states, native-query failures and disabled/mapped query gates")
 }
}
SWIFT
Dir.mktmpdir('native-tab-discovery-') do |dir|
  File.write("#{dir}/checks.swift", fixture)
  output, status = Open3.capture2e('xcrun', 'swiftc', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort output unless status.success?
  output, status = Open3.capture2e("#{dir}/checks")
  puts output
  abort 'Native-tab discovery checks failed' unless status.success?
end

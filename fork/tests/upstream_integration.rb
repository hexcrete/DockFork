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
util = File.read("#{root}/DockDoor/Utilities/Window Management/WindowUtil.swift")
source = <<~'SWIFT'
import Foundation
import CoreGraphics
final class NSScreen {
 let cgFrame:CGRect
 init(_ frame:CGRect){cgFrame=frame}
 static var screens:[NSScreen]=[]
}
struct WindowInfo {let id:Int;let frame:CGRect}
final class NSRunningApplication {
 enum Policy {case regular,accessory,prohibited}
 let bundleIdentifier:String?
 let processIdentifier:pid_t
 var isTerminated=false
 static var apps:[pid_t:NSRunningApplication]=[:]
 var activationPolicy=Policy.regular
 init(_ id:String?,pid:pid_t=1){bundleIdentifier=id;processIdentifier=pid;Self.apps[pid]=self}
 init?(processIdentifier:pid_t){guard let app=Self.apps[processIdentifier] else{return nil};self.processIdentifier=processIdentifier;bundleIdentifier=app.bundleIdentifier;isTerminated=app.isTerminated;activationPolicy=app.activationPolicy}
}
enum Defaults {
 struct Key<T> {let value:T}
 static var excluded:[String]=[]
 static var quitEnabled=true
 static subscript<T>(_ key:Key<T>)->T{key.value}
}
extension Defaults.Key where T==[String] {static var quitAppOnWindowCloseExcludedApps:Self{Self(value:Defaults.excluded)}}
extension Defaults.Key where T==Bool {static var quitAppOnWindowClose:Self{Self(value:Defaults.quitEnabled)}}
let finderAppIdentifier="com.apple.finder"
enum Session {static var locked=false}
func testSessionDictionary()->[String:Any]?{["CGSSessionScreenIsLocked":Session.locked]}
let kCGWindowLayer="layer",kCGWindowNumber="number"
enum Ordered {static var ids:Set<UInt32>=[];static var reads=0}
func SLSWindowIsOrderedIn(_ id:UInt32)->Bool?{Ordered.reads+=1;return Ordered.ids.contains(id)}
enum WindowUtil {
 static var candidates:[[String:Any]]=[],valid:Set<UInt32>=[]
 static var cache:[pid_t:[WindowInfo]]=[:]
 static func readCachedWindows(for pid:pid_t)->[WindowInfo]{cache[pid] ?? []}
 static func getCGWindowCandidates(for pid:pid_t)->[[String:Any]]{candidates}
 static func isValidCGWindowCandidate(_ id:UInt32,in values:[[String:Any]])->Bool{valid.contains(id)}
SWIFT
%w[sortWindowsByScreenPosition orderedScreens screenPositionKey quitBlockReason hasOrderedInWindow].each do |name|
  source += block(util, "    private static func #{name}(").sub('private static func', 'static func') + "\n"
end
source += block(util, '    static func shouldQuitAppOnWindowClose(') + "\n"
source += block(util, '    static var isScreenLocked:').sub('CGSessionCopyCurrentDictionary()', 'testSessionDictionary()') + "\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 static func main(){
  NSScreen.screens=[NSScreen(CGRect(x:1000,y:-200,width:1000,height:1000)),NSScreen(CGRect(x:0,y:0,width:1000,height:1000))]
  let a=WindowInfo(id:1,frame:CGRect(x:20,y:30,width:400,height:400))
  let b=WindowInfo(id:2,frame:CGRect(x:50,y:20,width:400,height:400))
  let c=WindowInfo(id:3,frame:CGRect(x:20,y:10,width:400,height:400))
  let d=WindowInfo(id:4,frame:CGRect(x:1100,y:-100,width:400,height:400))
  let unknown=WindowInfo(id:5,frame:.zero),offscreen=WindowInfo(id:6,frame:CGRect(x:-2000,y:0,width:100,height:100))
  let tie=WindowInfo(id:7,frame:a.frame)
  precondition(WindowUtil.sortWindowsByScreenPosition([d,unknown,b,a,offscreen,c,tie]).map(\.id)==[3,1,7,2,4,5,6])
  precondition(WindowUtil.screenPositionKey(for:CGRect(x:900,y:0,width:500,height:500),screens:WindowUtil.orderedScreens())?.screen==1,"Use greatest display overlap")
  NSScreen.screens=[]
  precondition(WindowUtil.sortWindowsByScreenPosition([b,a]).map(\.id)==[2,1],"Unknown geometry keeps input order")
  let app=NSRunningApplication("test.app")
  precondition(WindowUtil.quitBlockReason(for:app)==nil)
  Session.locked=true;precondition(WindowUtil.quitBlockReason(for:app)=="screen locked");Session.locked=false
  app.activationPolicy = .accessory;precondition(WindowUtil.quitBlockReason(for:app)=="not a regular app")
  app.activationPolicy = .prohibited;precondition(WindowUtil.quitBlockReason(for:app)=="not a regular app")
  app.activationPolicy = .regular;Defaults.excluded=["test.app"];precondition(WindowUtil.quitBlockReason(for:app)=="excluded")
  Defaults.excluded=[];precondition(WindowUtil.quitBlockReason(for:NSRunningApplication(nil))==nil)
  let regular=NSRunningApplication("test.close",pid:10)
  WindowUtil.cache[10]=[a]
  precondition(WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10))
  Defaults.excluded=["test.close"];precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10),"DockFork Close must respect the same exclusion as native Close")
  Defaults.excluded=[];Session.locked=true;precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10));Session.locked=false
  regular.activationPolicy = .accessory;precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10));regular.activationPolicy = .regular
  regular.isTerminated=true;precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10));regular.isTerminated=false
  WindowUtil.cache[10]=[a,b];precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10))
  WindowUtil.cache[10]=[];precondition(WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10))
  Defaults.quitEnabled=false;precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:10));Defaults.quitEnabled=true
  _=NSRunningApplication(finderAppIdentifier,pid:11);precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:11))
  precondition(!WindowUtil.shouldQuitAppOnWindowClose(processIdentifier:99),"Missing app must not become a Quit fallback")
  print("PASS shared Close-to-Quit policy: excluded, locked, accessory, terminated, Finder, disabled, missing and multi-window cases refuse; eligible last/windowless entries retain behavior")
  WindowUtil.candidates=[[kCGWindowLayer:1,kCGWindowNumber:1],[kCGWindowLayer:0,kCGWindowNumber:2],[kCGWindowLayer:0,kCGWindowNumber:3]]
  WindowUtil.valid=[3];Ordered.ids=[3];precondition(WindowUtil.hasOrderedInWindow(pid:1) && Ordered.reads==1)
  Ordered.ids=[];precondition(!WindowUtil.hasOrderedInWindow(pid:1))
  print("PASS upstream integration: cached screen sorting/overlap/stable fallback and lock/policy/exclusion/ordered-window quit guards; inert data only")
 }
}
SWIFT
Dir.mktmpdir('dockfork-upstream-integration-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Integration compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Integration checks failed' unless system("#{dir}/checks")
end
verify = block(util, '    private static func verifyNoWindowsRemain(')
abort 'Quit must retain both upstream guards and shared ownership' unless verify.include?('hasOrderedInWindow(pid: pid)') && verify.index('quitBlockReason(for: app)') < verify.index('.quit(force: false)') && !verify.include?('app.terminate()')
buttons = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/Traffic Light Buttons.swift")
abort 'Native accessible traffic lights must retain shared dimensions' unless buttons.include?('return Button {') && buttons.include?('.accessibilityLabel(action.localizedName)') && buttons.include?('Self.buttonFrameSize * buttonScale')
puts 'PASS integration source contracts: shared Quit ownership and native accessible/sized traffic lights'

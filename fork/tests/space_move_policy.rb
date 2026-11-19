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
  abort 'Unclosed block'
end
root = File.expand_path('../..', __dir__)
util = File.read("#{root}/DockDoor/Utilities/Window Management/WindowUtil.swift")
source = <<~'SWIFT'
import Foundation
struct WindowInfo {let id:Int
 @MainActor func bringToFrontConfirmed() async -> Bool {WindowUtil.focus.append(id);return true}
}
struct PreviewWindowIdentity:Hashable {let id:Int;init(_ w:WindowInfo){id=w.id}}
final class WindowActionRequest {var allowed:Set<Int>=[1,2];var mayForeground=true
 func contains(_ id:PreviewWindowIdentity)->Bool {allowed.contains(id.id)}
}
@MainActor enum WindowUtil {
 static var visible=false, focus:[Int]=[], reveal:[Int]=[], switches=0, reads=0, failSwitch=false, failReveal=false
 static var afterSwitch:(()->Void)?,afterReveal:(()->Void)?
 static func reset(){visible=false;focus=[];reveal=[];switches=0;reads=0;failSwitch=false;failReveal=false;afterSwitch=nil;afterReveal=nil}
 static func canBringWindowToFrontWithoutSpaceSwitch(_ w:WindowInfo)->Bool {reads+=1;return visible}
 static func revealManagedDesktopForActivation(_ w:WindowInfo)async->Bool {switches+=1;afterSwitch?();visible = !failSwitch;return visible}
 static func revealWindowConfirmed(_ w:WindowInfo)async->Bool {reveal.append(w.id);afterReveal?();return !failReveal}
SWIFT
source += block(util, '    static func completeSpaceMovePresentation(') + "\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async {
 let windows=[WindowInfo(id:1),WindowInfo(id:2)]
 for visible in [false,true] {for follow in [false,true] {for foreground in [false,true] {
  WindowUtil.reset();WindowUtil.visible=visible;let request=WindowActionRequest();var dismissals=0
  let failed=await WindowUtil.completeSpaceMovePresentation(windows,followsDestination:follow,bringToFront:foreground,request:request,dismissPreviews:{dismissals+=1},mayFollow:{true},isRequestActive:{true})
  let switched=follow && !visible
  let raised=foreground && (visible || follow)
  precondition(failed.isEmpty && WindowUtil.switches == (switched ? 1:0) && dismissals == (switched ? 1:0))
  precondition(WindowUtil.reveal == (raised ? [2,1]:[]) && WindowUtil.focus == (raised ? [2,1]:[]))
  if !follow && !foreground {precondition(WindowUtil.reads==0)}
 }}}
 WindowUtil.reset();let request=WindowActionRequest();var active=true
 WindowUtil.afterSwitch={active=false}
 _=await WindowUtil.completeSpaceMovePresentation(windows,followsDestination:true,bringToFront:true,request:request,dismissPreviews:nil,mayFollow:{true},isRequestActive:{active})
 precondition(WindowUtil.reveal.isEmpty && WindowUtil.focus.isEmpty)
 WindowUtil.reset();WindowUtil.visible=true
 WindowUtil.afterReveal={request.allowed=[]}
 _=await WindowUtil.completeSpaceMovePresentation(windows,followsDestination:false,bringToFront:true,request:request,dismissPreviews:nil,mayFollow:{true},isRequestActive:{true})
 precondition(WindowUtil.focus.isEmpty)
 WindowUtil.reset();let fresh=WindowActionRequest();WindowUtil.failSwitch=true
 let failed=await WindowUtil.completeSpaceMovePresentation(windows,followsDestination:true,bringToFront:true,request:fresh,dismissPreviews:nil,mayFollow:{true},isRequestActive:{true})
 precondition(failed==[PreviewWindowIdentity(windows[0])] && WindowUtil.focus.isEmpty)
 WindowUtil.reset();fresh.mayForeground=false
 _=await WindowUtil.completeSpaceMovePresentation(windows,followsDestination:true,bringToFront:true,request:fresh,dismissPreviews:nil,mayFollow:{true},isRequestActive:{true})
 precondition(WindowUtil.reads==0 && WindowUtil.switches==0)
 WindowUtil.reset();fresh.mayForeground=true;WindowUtil.visible=true;WindowUtil.failReveal=true
 let refused=await WindowUtil.completeSpaceMovePresentation(windows,followsDestination:false,bringToFront:true,request:fresh,dismissPreviews:nil,mayFollow:{true},isRequestActive:{true})
 precondition(Set(refused)==Set(windows.map(PreviewWindowIdentity.init)) && WindowUtil.focus.isEmpty)
 print("PASS Space move policy: all toggle/visibility combinations, no-op query gate, reverse group order, state-preserving follow, failed switch/reveal and stale ownership")
 }
}
SWIFT
contents = block(util, '    static func moveSpaceContents(')
abort 'Content operations must explicitly preserve state' unless contents.include?('bringToFront: false') && contents.include?('followsDestination: false')
abort 'Single and batch moves must share completion policy' unless %w[performConfirmedSpaceMove movePreviewWindows].all? { |name| block(util,"    static func #{name}(").include?('completeSpaceMovePresentation(') }
Dir.mktmpdir('dockfork-space-policy-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Compilation failed' unless system('swiftc', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Policy checks failed' unless system("#{dir}/checks")
end

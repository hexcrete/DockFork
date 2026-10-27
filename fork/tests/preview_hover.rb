#!/usr/bin/env ruby
require 'tmpdir'

def block(source, signature)
  start=source.index(signature) or abort "Missing #{signature}"
  opening=source.index(/\{\n/, start); depth=0
  (opening...source.length).each do |i|
    depth+=1 if source[i]=='{'; depth-=1 if source[i]=='}'
    return source[start..i] if depth.zero?
  end
  abort "Unclosed #{signature}"
end

root=File.expand_path('../..', __dir__)
views="#{root}/DockDoor/Views/Hover Window"
container=File.read("#{views}/WindowPreviewHoverContainer.swift")
state=File.read("#{views}/WindowPreview Supporting/PreviewStateCoordinator.swift")
grid=File.read("#{views}/WindowPreview Supporting/CardGridScrollView.swift")
panel=File.read("#{views}/Shared Components/SharedPreviewWindowCoordinator.swift")
fade_update=block(panel,'    private func updatePreviewFocusFade()')
abort 'Native hover must reuse existing fade monitors' unless fade_update.scan('registerPreviewFocusPointerActivity(event)').length==2
abort 'Fade-off must stop before monitor installation' unless fade_update.index('guard canRunPreviewFocusFade else') < fade_update.index('NSEvent.addLocalMonitorForEvents') && fade_update.include?('stopPreviewFocusFade()')
abort 'Fade eligibility must require the active mode preference' unless block(panel,'    private var canRunPreviewFocusFade:').include?('guard Defaults[previewFocusFadeMode.enabledKey] else { return false }')
stop_fade=block(panel,'    private func stopPreviewFocusFade()')
abort 'Fade teardown must remove both monitors and timer' unless %w[focusFadeTimer?.invalidate() focusFadeLocalMonitor focusFadeGlobalMonitor NSEvent.removeMonitor].all?{|token|stop_fade.include?(token)}
abort 'Grid detach must release native hover routing' unless block(grid,'        func detach(').include?('previewCoordinator?.hoverGrid = nil') && block(grid,'        func detach(').include?('onHoverIndexChange = nil')
%w[WindowPreview.swift WindowPreviewCompact.swift].each do |file|
  source=File.read("#{views}/#{file}")
  abort "#{file} must identify the exiting card" unless source.include?('onHoverIndexChange?(index, nil)') && !source.include?('onHoverIndexChange?(nil, nil)')
end
source=<<~'SWIFT'
import Foundation
import CoreGraphics
enum SelectionInputSource {case mouse,keyboard,programmatic}
enum DockPosition {case bottom,cmdTab}
struct App {let processIdentifier:Int}
struct WindowInfo {let id:Int;let app:App}
@MainActor final class State {
 var isDraggingPreview=false,isPointerSelecting=false,windowSwitcherActive=false
 var currIndex = -1,selectionInputSource=SelectionInputSource.programmatic
 var moved=true,pointerChecks=0,writes=0
 var windows=[WindowInfo(id:1,app:App(processIdentifier:1)),WindowInfo(id:2,app:App(processIdentifier:1))]
 weak var hoverGrid:Grid?
 func registerMouseMovementSinceOpen()->Bool{pointerChecks+=1;return moved}
 func setIndex(to index:Int,shouldScroll:Bool,source:SelectionInputSource){updateSelectionIndex(index,source:source,shouldScroll:shouldScroll)}
 func updateSelectionIndex(_ index:Int,source:SelectionInputSource,shouldScroll:Bool){precondition(!shouldScroll);writes+=1;currIndex=index;selectionInputSource=source}
SWIFT
source+=block(state,'    func clearSelectionIfMouseSource(')+"\n}\n"
source+=<<~'SWIFT'
@MainActor final class Hover {
 let previewStateCoordinator=State()
 var dockPosition=DockPosition.bottom,enableMouseHoverInSwitcher=true
 var edgeScrollRequest:Int?,refreshes=0
 func refreshHighlightActionIfNeeded(){refreshes+=1}
SWIFT
source+=block(container,'    private func handleHoverIndexChange(').sub('private func handleHoverIndexChange','func hover')+"\n}\n"
source+=<<~'SWIFT'
enum FlowItem:Hashable {case window(Int),header}
struct ContentKey {let id:Int;let pid:Int}
final class Window {var isVisible=true;var origin=CGPoint.zero;func convertPoint(fromScreen p:CGPoint)->CGPoint{CGPoint(x:p.x-origin.x,y:p.y-origin.y)}}
final class Container {
 var isInteractive=true,offset=CGPoint.zero
 var hitTests=0
 var window:Window?=Window()
 func convert(_ p:CGPoint,from:Any?)->CGPoint{p}
 func contentPoint(for p:CGPoint)->CGPoint? {hitTests+=1;guard CGRect(x:0,y:0,width:210,height:80).contains(p) else{return nil};return CGPoint(x:p.x+offset.x,y:p.y+offset.y)}
}
@MainActor final class Grid {
 var container:Container?=Container()
 var previewCoordinator:State?
 var contentKey=[ContentKey(id:1,pid:1),ContentKey(id:2,pid:1)]
 var frames:[FlowItem:CGRect]=[.window(0):CGRect(x:0,y:0,width:100,height:80),.window(1):CGRect(x:110,y:0,width:100,height:80)]
 var onHoverIndexChange:((Int,CGPoint?)->Bool)?
}
extension Grid {
SWIFT
%w[windowForDrop updateHover].each{|name|source+=block(grid,"        func #{name}(")+"\n"}
source+=block(grid,'        private func windowIndex(')+"\n}\n"
source+=<<~'SWIFT'
struct NSEvent {
 enum Kind {case mouseMoved,scrollWheel,leftMouseDragged,leftMouseDown}
 static var mouseLocation=CGPoint.zero
 let type:Kind;var windowNumber=100
}
@MainActor final class Panel {
 let windowSwitcherCoordinator:State
 var windowNumber=100,isVisible=true,canRunPreviewFocusFade=true,activity=0
 var trackingMenus=Set<Int>()
 init(_ state:State){windowSwitcherCoordinator=state}
 func registerPreviewFocusActivity(){activity+=1}
SWIFT
source+=block(panel,'    private func registerPreviewFocusPointerActivity(').sub('private func','func')+"\n}\n"
source+=<<~'SWIFT'
@main struct Checks {
 @MainActor static func main() {
  let point=CGPoint(x:10,y:10)
  var sequences=0
  for mode in 0..<3 {
   for reverse in [false,true] {
    let h=Hover(),s=h.previewStateCoordinator
    s.windowSwitcherActive=mode==2;h.dockPosition=mode==1 ? .cmdTab:.bottom
    let first=reverse ? 1:0,next=reverse ? 0:1
    precondition(h.hover(first,point) && s.currIndex==first)
    // Characterization: the former anonymous exit unconditionally cleared the next highlight.
    precondition(h.hover(next,point));let priorWrites=s.writes
    precondition(!h.hover(first,nil) && s.currIndex==next && s.writes==priorWrites && h.refreshes==0)
    precondition(h.hover(next,point) && s.writes==priorWrites,"Repeated active events must not publish unchanged selection")
    precondition(!h.hover(next,nil) && s.currIndex == -1 && h.refreshes==1)
    precondition(h.hover(first,point))
    _=h.hover(first,nil);precondition(s.currIndex == -1)
    precondition(h.hover(next,point) && s.currIndex==next,"Exit-before-entry must still work")
    s.selectionInputSource = .keyboard
    _=h.hover(next,nil);precondition(s.currIndex==next,"Pointer exit must not erase keyboard selection")
    sequences+=1
   }
  }
  for guardCase in 0..<5 {
   let h=Hover(),s=h.previewStateCoordinator;s.currIndex=0;s.selectionInputSource = .mouse
   switch guardCase {
   case 0:s.isDraggingPreview=true
   case 1:s.isPointerSelecting=true
   case 2:h.edgeScrollRequest=1
   case 3:s.windowSwitcherActive=true;h.enableMouseHoverInSwitcher=false
   default:s.moved=false
   }
   precondition(!h.hover(1,point) && s.currIndex==0 && s.writes==0)
  }
  let h=Hover(),s=h.previewStateCoordinator,g=Grid(),p=Panel(h.previewStateCoordinator)
  g.previewCoordinator=s;s.hoverGrid=g;g.onHoverIndexChange=h.hover
  precondition(h.hover(0,point))
  NSEvent.mouseLocation=CGPoint(x:150,y:20)
  // No SwiftUI entry callback: only native movement reaches the real shared handler.
  p.registerPreviewFocusPointerActivity(NSEvent(type:.mouseMoved))
  precondition(s.currIndex==1,"Native movement must recover missed SwiftUI card entry")
  let writes=s.writes
  p.registerPreviewFocusPointerActivity(NSEvent(type:.mouseMoved))
  _=h.hover(0,nil);precondition(s.currIndex==1 && s.writes==writes,"Duplicate native delivery and late SwiftUI exit must not republish or clear selection")
  NSEvent.mouseLocation=point
  let guardedHits=g.container!.hitTests
  for event in [NSEvent(type:.scrollWheel),NSEvent(type:.leftMouseDragged),NSEvent(type:.leftMouseDown),NSEvent(type:.mouseMoved,windowNumber:200)] {
   p.registerPreviewFocusPointerActivity(event);precondition(s.currIndex==1)
  }
  p.trackingMenus=[1];p.registerPreviewFocusPointerActivity(NSEvent(type:.mouseMoved));precondition(s.currIndex==1);p.trackingMenus=[]
  p.canRunPreviewFocusFade=false
  for _ in 0..<100 {p.registerPreviewFocusPointerActivity(NSEvent(type:.mouseMoved))}
  precondition(s.currIndex==1 && g.container!.hitTests==guardedHits,"Fade-off and excluded events must do zero grid hit testing")
  p.canRunPreviewFocusFade=true
  p.isVisible=false;p.registerPreviewFocusPointerActivity(NSEvent(type:.mouseMoved));precondition(s.currIndex==1);p.isVisible=true
  g.container!.offset=CGPoint(x:110,y:0)
  precondition(g.windowForDrop(at:point)?.id==2,"Hover and drops must share current scrolling geometry")
  g.container!.window!.origin=CGPoint(x:-300,y:200)
  precondition(g.windowForDrop(at:CGPoint(x:-290,y:210))?.id==2)
  precondition(g.windowForDrop(at:CGPoint(x:-310,y:210))==nil)
  s.windows.removeLast();precondition(g.windowForDrop(at:CGPoint(x:-290,y:210))==nil,"Removed targets must not survive native hit testing")
  print("PASS native-input routing: missing SwiftUI callback, duplicate delivery, late exit, event/window/menu/disabled/visibility guards, shared scrolled/display geometry and removed-target rejection")
  print("COUNT fade disabled: 100 residual movement callbacks, zero grid hit tests or selection changes; source guards prevent monitor installation and retain teardown")
  print("PASS production hover: \(sequences) mode/direction sequences, late exits, normal exit/re-entry, repeated motion, keyboard ownership, initial-hover/drag/selection/edge-scroll guards; no native input or AX calls")
 }
}
SWIFT
Dir.mktmpdir('dockfork-preview-hover-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Hover checks compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
  abort 'Hover checks failed' unless system("#{dir}/checks")
end

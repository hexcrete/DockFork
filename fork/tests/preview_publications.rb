#!/usr/bin/env ruby
require 'tmpdir'
require 'open3'

def block(source, signature)
  start=source.index(signature) or abort "Missing #{signature}"
  opening=source.index(/\{\n/,start);depth=0
  (opening...source.length).each do |i|
    depth+=1 if source[i]=='{';depth-=1 if source[i]=='}'
    return source[start..i] if depth.zero?
  end
  abort "Unclosed #{signature}"
end

native=ARGV.delete('--native')
abort "Unknown arguments: #{ARGV.join(' ')}" unless ARGV.empty?
root=File.expand_path('../..',__dir__)
path='DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift'
view_path='DockDoor/Views/Hover Window/WindowPreviewHoverContainer.swift'
current=File.read("#{root}/#{path}")
view=File.read("#{root}/#{view_path}")
start=view.index("        .background {\n            SelectionReader") or abort 'Missing selection observer'
finish=view.index('        .onChange(of: scrolledFromStart)',start) or abort 'Missing observer boundary'
observer=view[start...finish]
frozen,status=Open3.capture2('git','-C',root,'show',"9d48fba9:#{path}")
abort 'Missing characterized baseline' unless status.success?
source=<<~'SWIFT'
import AppKit
import Combine
import SwiftUI
struct OrderedPreviewSelection {}
struct WindowInfo {let id:Int}
struct PreviewWindowIdentity {init(_ window:WindowInfo){}}
typealias CGSSpaceID=UInt64
enum DockPosition {case bottom,cmdTab}
SWIFT
[['Current',current],['Frozen',frozen]].each do |name,state|
  selection=block(state,'final class SwitcherSelectionState:')
  source+=selection.sub('class SwitcherSelectionState:',"class #{name}Selection:").gsub('PreviewStateCoordinator.',"#{name}State.")+"\n"
  source+="@MainActor final class #{name}State:ObservableObject {\nlet selection=#{name}Selection()\n"
  source+=<<~'SWIFT'
  var windows=(0..<128).map{WindowInfo(id:$0)},shouldScrollToIndex=true
  var isDraggingPreview=false,isPointerSelecting=false,windowSwitcherActive=true
  var hasMovedSinceOpen=true
  var tapStateDidChange:(()->Void)?,onNavigationTargetChanged:(()->Void)?
  var range=false,rangeEnds=0
  func endSelectionRange(){if range{range=false;rangeEnds+=1}}
  func extendSelectionRange(through:PreviewWindowIdentity){}
  func registerMouseMovementSinceOpen()->Bool{hasMovedSinceOpen}
  SWIFT
  source+=block(state,'    enum SelectionInputSource {')+"\n"
  source+=state.lines.find{|l|l.include?('enum NavigationTarget:')}+"\n"
  source+="var spaceNavigationInputSource=SelectionInputSource.programmatic\n"
  source+=block(state,'    var currIndex:')+"\n"
  if state.include?('@Published var navigationTarget:')
    source+=block(state,'    @Published var navigationTarget:')+"\n"
  else
    source+=state.lines.find{|l|l.include?('@Published private var storedNavigationTarget:')}
    source+=block(state,'    var navigationTarget:')+"\n"
  end
  if state.include?('@Published private(set) var selectionInputSource:')
    source+=state.lines.find{|l|l.include?('@Published private(set) var selectionInputSource:')}
  else
    source+=block(state,'    private(set) var selectionInputSource:')+"\n"
  end
  %w[updateSelectionIndex setIndex clearSelectionIfMouseSource].each{|n|source+=block(state,"    func #{n}(")+"\n"}
  source+="}\n@MainActor final class #{name}Hover {\nlet previewStateCoordinator=#{name}State()\nvar dockPosition=DockPosition.bottom,enableMouseHoverInSwitcher=true\nvar edgeScrollRequest:Int?,refreshes=0\nfunc refreshHighlightActionIfNeeded(){refreshes+=1}\n"
  source+=block(view,'    private func handleHoverIndexChange(').sub('private func handleHoverIndexChange','func hover')+"\n}\n"
end
if native
  source+=block(view,'private struct SelectionReader<').gsub('SwitcherSelectionState','CurrentSelection')+"\n"
  source+=<<~SWIFT
  @MainActor final class NativeTrace { var sources:[String]=[];var cleared=false }
  @MainActor struct ObservedContent:View {
    @ObservedObject var previewStateCoordinator:CurrentState
    @State private var edgeScrollRequest:Int?=1
    let trace:NativeTrace
    var body:some View {
      Color.clear.frame(width:100,height:100)
      #{observer}
    }
    func refreshHighlightActionIfNeeded(){
      trace.sources.append(String(describing:previewStateCoordinator.selectionInputSource))
      trace.cleared=edgeScrollRequest==nil
    }
  }
  @MainActor func verifyNativeObservation(){
    guard CGSessionCopyCurrentDictionary() != nil else {print("SKIP native SwiftUI observation: no display");return}
    let app=NSApplication.shared
    app.setActivationPolicy(.prohibited);app.finishLaunching()
    let state=CurrentState(),trace=NativeTrace()
    state.setIndex(to:0,shouldScroll:false,source:.mouse)
    let panel=NSPanel(contentRect:NSRect(x:-10000,y:-10000,width:100,height:100),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    panel.isReleasedWhenClosed=false
    panel.contentView=NSHostingView(rootView:ObservedContent(previewStateCoordinator:state,trace:trace))
    panel.orderFrontRegardless()
    defer {panel.close()}
    func drain(){RunLoop.main.run(until:Date().addingTimeInterval(0.15))}
    drain()
    state.setIndex(to:0,shouldScroll:false,source:.keyboard);drain()
    precondition(trace.sources.last=="keyboard" && trace.cleared,"Source-only keyboard takeover must reach SwiftUI observer")
    state.setIndex(to:0,shouldScroll:false,source:.mouse);drain()
    precondition(trace.sources.last=="mouse","Source-only mouse takeover must reach SwiftUI observer")
    print("PASS native SwiftUI observer: same-index keyboard/mouse takeover and edge-scroll cancellation; offscreen owned panel, no input posted")
  }
  SWIFT
end
source+=<<~'SWIFT'
@main struct Checks {
 @MainActor static func main(){
  let point=CGPoint(x:10,y:10)
  for mode in 0..<3 {
   for exits in [false,true] {
    let c=CurrentHover(),f=FrozenHover(),a=c.previewStateCoordinator,b=f.previewStateCoordinator
    a.windowSwitcherActive=mode==2;b.windowSwitcherActive=mode==2
    c.dockPosition=mode==1 ? .cmdTab:.bottom;f.dockPosition=c.dockPosition
    precondition(c.hover(0,point) && f.hover(0,point))
    var parents=0,oldParents=0,children=0,oldChildren=0,taps=0,oldTaps=0,nav=0,oldNav=0
    var tokens=Set<AnyCancellable>()
    a.objectWillChange.sink{parents+=1}.store(in:&tokens);b.objectWillChange.sink{oldParents+=1}.store(in:&tokens)
    a.selection.objectWillChange.sink{children+=1}.store(in:&tokens);b.selection.objectWillChange.sink{oldChildren+=1}.store(in:&tokens)
    a.tapStateDidChange={taps+=1};b.tapStateDidChange={oldTaps+=1}
    a.onNavigationTargetChanged={nav+=1};b.onNavigationTargetChanged={oldNav+=1}
    for index in 1...100 {
     if exits {_ = c.hover(index-1,nil);_ = f.hover(index-1,nil)}
     precondition(a.currIndex==b.currIndex && String(describing:a.selectionInputSource)==String(describing:b.selectionInputSource))
     precondition(c.hover(index,point) && f.hover(index,point))
     precondition(a.currIndex==b.currIndex && String(describing:a.selectionInputSource)==String(describing:b.selectionInputSource))
    }
    precondition(oldParents==(exits ? 300:100) && oldChildren==(exits ? 200:100))
    precondition(parents==(exits ? 200:0) && taps==oldTaps && nav==oldNav && nav==0)
    precondition(children==oldChildren)
    print("COUNT mode=\(mode) exits=\(exits): 100 transitions parent notifications \(oldParents)->\(parents), selection notifications \(oldChildren)->\(children), snapshot requests preserved=\(taps)")
    // True navigation changes must still publish and notify exactly once.
    let before=parents,callbacks=nav
    a.navigationTarget = .space(7)
    precondition(parents==before+1 && nav==callbacks+1 && a.navigationTarget == .space(7))
    a.navigationTarget = .space(7)
    precondition(parents==before+1 && nav==callbacks+1)
    a.spaceNavigationInputSource = .mouse
    _=c.hover(101,point)
    precondition(a.navigationTarget == .windows && a.spaceNavigationInputSource == .programmatic && nav==callbacks+2)
    // Source-only changes must retain their original observation without changing the selected index.
    var sources:[String]=[]
    a.objectWillChange.sink{sources.append(String(describing:a.selectionInputSource))}.store(in:&tokens)
    let beforeSource=parents,snapshotCount=taps
    a.setIndex(to:101,shouldScroll:false,source:.keyboard)
    precondition(a.currIndex==101 && a.selectionInputSource == .keyboard && taps==snapshotCount)
    a.clearSelectionIfMouseSource();precondition(a.currIndex==101)
    precondition(parents==beforeSource+1 && !sources.isEmpty)
    // Preserve existing same-index publication needed by keyboard reveal subscribers.
    let oldChildCount=children
    a.setIndex(to:101,shouldScroll:true,source:.keyboard)
    precondition(children==oldChildCount+1 && a.shouldScrollToIndex)
    a.range=true;a.setIndex(to:102,shouldScroll:false,source:.mouse)
    precondition(!a.range && a.rangeEnds==1)
    _=c.hover(101,nil);precondition(a.currIndex==102,"Late exits must not erase the new highlight")
   }
  }
  print("PASS publication/input semantics: all modes, mouse exit ownership, source-only changes, real Space handoff, same-target no-ops, snapshot ownership, keyboard reveal and range teardown")
  NATIVE_OBSERVATION
 }
}
SWIFT
source=source.sub('  NATIVE_OBSERVATION',native ? '  verifyNativeObservation()':'')
abort 'Input-source reaction must retain its existing observation' unless observer.include?('.onChange(of: previewStateCoordinator.selectionInputSource)') && observer.include?('edgeScrollRequest = nil') && observer.include?('refreshHighlightActionIfNeeded()')
Dir.mktmpdir('dockfork-preview-publications-') do |dir|
  File.write("#{dir}/checks.swift",source)
  abort 'Publication checks compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
  abort 'Publication checks failed' unless system("#{dir}/checks")
end

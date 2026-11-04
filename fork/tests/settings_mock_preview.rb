#!/usr/bin/env ruby
require 'open3'
require 'tmpdir'
ROOT = File.expand_path('../..', __dir__)
def read(path) = File.read(File.join(ROOT, 'DockDoor', path))
def block(source, marker)
 start = source.index(marker) or abort "Missing #{marker}"
 opening = source.index('{', start)
 depth = 0
 (opening...source.size).each do |index|
  depth += 1 if source[index] == '{'
  depth -= 1 if source[index] == '}'
  return source[start..index] if depth.zero?
 end
 abort "Unclosed #{marker}"
end
def prefix(source, marker, boundary)
 full = block(source, marker)
 finish = full.index(boundary) or abort "Missing boundary #{boundary}"
 full[0...finish].sub('private func', 'func')
end
base='Views/Hover Window/'
container=read(base+'WindowPreviewHoverContainer.swift')
regular=read(base+'WindowPreview.swift')
compact=read(base+'WindowPreviewCompact.swift')
state=read(base+'WindowPreview Supporting/PreviewStateCoordinator.swift')
buttons=read(base+'Shared Components/Traffic Light Buttons.swift')
mock=read('Views/Settings/Shared Components/SettingsMockPreview.swift')
abort 'Settings examples must use shared reactive appearance, not a divergent snapshot' if mock.include?('@Default(') || mock.include?('appearanceOverride:') || mock.include?('PreviewAppearanceSettings(')
abort 'Mock ownership must be explicit and cached samples retained' unless mock.include?('PreviewStateCoordinator(isMockPreview: true)') && mock.include?('cachedMockWindows') && mock.include?('mockPreviewActive: true')
abort 'Dummy window creation must not read a fake AX element' unless mock.include?('readsAXTitle: false')
abort 'Mock focus must use a sample identity without OS discovery' unless state.include?('if isMockPreview { focusedWindowID = newWindows.first?.id } else { refreshFocusedWindowID(from: newWindows) }')
abort 'Mock selection must not be reconciled against real windows' unless block(state,'    func reconcileCheckedWindows(').include?('guard !isMockPreview, checkedWindowCount > 0')
%w[externalDragSpringLoading windowPreviewInteractions].each do |modifier|
 [regular,compact].each do |source|
  guards=source.enum_for(:scan,/\.if\(!mockPreviewActive\) \{ view in/).map{block(source[Regexp.last_match.begin(0)..],'.if(!mockPreviewActive)')}
  abort "Mock must not install #{modifier}" unless guards.any?{|body|body.include?(".#{modifier}(")}
 end
end
abort 'Body activation must be inert in settings' unless container.include?('if !mockPreviewActive { activateApp() }')
abort 'More must be hoverable but must not open a real-window menu' unless block(regular,'struct PreviewOverflowButton:').include?('guard !mockPreviewActive else { return }')
abort 'Regular selection control must retain the live visibility policy' if block(regular,'    private var hasSelectionControl:').include?('!mockPreviewActive')
abort 'Compact selection control must allow local mock hover' unless compact.include?('mockPreviewActive || SharedPreviewWindowCoordinator.activeInstance?') && !compact.include?('appearance.enableMultiWindowSelection, !mockPreviewActive,')
flow=block(container,'    private func buildFlowStack(')
mock_flow=block(flow[flow.index('            let makeCard:')..],'            if mockPreviewActive {')
abort 'Scaled mocks must keep all cards in one SwiftUI hierarchy' unless mock_flow.include?('AnyLayout(') && mock_flow.include?('makeCard(item)') && mock_flow.include?('.padding(layout.inset)') && !mock_flow.include?('CardGridScrollView(')
abort 'Real previews must retain native virtualization' unless flow.include?('CardGridScrollView(') && flow.include?('makeCard: makeCard')
form=read('Views/Settings/Shared Components/SettingsForm.swift')
abort 'Pinned/scaled preview hit testing must remain bounded' unless form.include?(".clipped()\n                        .contentShape(Rectangle())") && mock.include?(".clipped()\n            .contentShape(Rectangle())")
actions=block(container,'            let handleCardAction: (WindowAction) -> Void = {')
abort 'Mock dispatch must precede all real session/action ownership' unless actions.index('if mockPreviewActive') < actions.index('SharedPreviewWindowCoordinator.activeInstance') && actions.include?("handleWindowAction(action, at: index)\n                    return")
code=<<~'SWIFT'
import Foundation
import AppKit

typealias WindowInfo = Int
class SampleSelection {
 var windows=[1,2];var currIndex=0;var checked:Set<Int>=[];var indexUpdates=0
 func toggleCheckedWindow(_ window:Int){if !checked.insert(window).inserted{checked.remove(window)}}
 func setIndex(to index:Int,shouldScroll:Bool,source:Source){currIndex=index;indexUpdates+=1}
 func clearSelectionIfMouseSource(shouldScroll:Bool){currIndex = -1}
}
enum Source {case mouse}
enum WindowAction:CaseIterable {case toggleWindowSelection,close,quit,forceQuit,minimize,hide,openNewWindow,maximize,toggleFullScreen,selectAllWindows,none}
final class Actions {
 let mockPreviewActive:Bool;let previewStateCoordinator=SampleSelection();var liveCalls=0
 init(_ mock:Bool){mockPreviewActive=mock}
SWIFT
code+=prefix(container,'    private func handleWindowAction(_ action:','        if action == .selectAllWindows')+"liveCalls += 1\n}\n"
code+=prefix(container,'    private func handleHoverIndexChange(','        guard !previewStateCoordinator.isDraggingPreview')+"liveCalls += 1;return false\n}\n}\n"
code+=<<~'SWIFT'
enum TrafficLightButtonsVisibility:CaseIterable {case dimmedOnPreviewHover,dimmedUntilButtonHover,fullOpacityOnPreviewHover,alwaysVisible,never}
struct Buttons {let displayMode:TrafficLightButtonsVisibility;let isHovering:Bool
SWIFT
code+=block(buttons,'    private var buttonOpacity:').sub('private var','var')+"\n}\n"
code+="final class Lifetime {let isMockPreview:Bool;var windows=[1,2];var liveCalls=0\ninit(_ mock:Bool){isMockPreview=mock}\n"
[['    func scheduleActiveFocusedWindowRefresh()','        guard Defaults'],['    func refreshSelectionLayout()','        selectionLayoutGeneration'],['    private func pinCheckedSelectionIfNeeded()','        if Defaults'],['    private func reconcileWindowChanges(','        let previousCheckedCount'],['    func mergeWindows(','        guard !windows.isEmpty']].each do |marker,boundary|
 code+=prefix(state,marker,boundary)+"liveCalls += 1\n}\n"
end
code+=prefix(state,'    func mergeRefreshedRowsForPID(','        let before = windows')+"liveCalls += 1;return ([3],true)\n}\n}\n"
code+=<<~'SWIFT'
let mock=Actions(true)
for action in WindowAction.allCases where action != .toggleWindowSelection {mock.handleWindowAction(action,at:0)}
precondition(mock.liveCalls==0 && mock.previewStateCoordinator.windows==[1,2])
mock.handleWindowAction(.toggleWindowSelection,at:0);precondition(mock.previewStateCoordinator.checked==[1])
mock.handleWindowAction(.toggleWindowSelection,at:0);precondition(mock.previewStateCoordinator.checked.isEmpty)
mock.handleWindowAction(.toggleWindowSelection,at:-1);mock.handleWindowAction(.toggleWindowSelection,at:99)
precondition(mock.handleHoverIndexChange(1,CGPoint(x:0,y:0)));precondition(mock.previewStateCoordinator.currIndex==1)
for _ in 0..<100 {precondition(mock.handleHoverIndexChange(1,CGPoint(x:0,y:0)))}
precondition(mock.previewStateCoordinator.indexUpdates==1)
precondition(!mock.handleHoverIndexChange(0,nil) && mock.previewStateCoordinator.currIndex==1)
precondition(!mock.handleHoverIndexChange(1,nil) && mock.previewStateCoordinator.currIndex == -1)
let live=Actions(false);for action in WindowAction.allCases{live.handleWindowAction(action,at:0)}
precondition(live.liveCalls==WindowAction.allCases.count)
for mode in TrafficLightButtonsVisibility.allCases {for hovering in [false,true]{
 let value=Buttons(displayMode:mode,isHovering:hovering).buttonOpacity
 let expected:Double = mode == .never ? 0 : (mode == .dimmedOnPreviewHover || mode == .dimmedUntilButtonHover) && !hovering ? 0.25:1
 precondition(value==expected)
}}
for mocked in [true,false]{
 let lifetime=Lifetime(mocked)
 lifetime.scheduleActiveFocusedWindowRefresh();lifetime.refreshSelectionLayout();lifetime.pinCheckedSelectionIfNeeded()
 lifetime.reconcileWindowChanges(removed:[1],added:[3],updated:[4])
 lifetime.mergeWindows([3],dockPosition:.bottom,bestGuessMonitor:NSScreen.main!)
 let result=lifetime.mergeRefreshedRowsForPID(42,replacementRows:[3],dockPosition:.bottom,bestGuessMonitor:nil)
 precondition(lifetime.liveCalls == (mocked ? 0:6))
 precondition(result.didPublish == !mocked && result.mergedWindows == (mocked ? [1,2]:[3]))
}
print("PASS production mock dispatch/hover: all real actions refused, local checkbox toggles, invalid indices, outgoing hover ordering; live dispatch unchanged")
print("PASS production dimming: all five visibility modes and button-hover states")
print("PASS production mock lifetime: no focus/cache/layout/session side effects, original samples preserved; live boundaries unchanged")
SWIFT
# Only the screen and Dock-position parameter types are needed; no native windows are queried or manipulated.
code=code.sub('import AppKit',"enum DockPosition {case bottom}\nclass NSScreen {static let main:NSScreen?=NSScreen()}")
Dir.mktmpdir('dockfork-settings-mock-') do |dir|
 input=File.join(dir,'checks.swift');binary=File.join(dir,'checks');File.write(input,code)
 output,status=Open3.capture2e('swiftc',input,'-o',binary)
 abort output unless status.success?
 output,status=Open3.capture2e(binary);puts output;abort 'Mock fixture did not pass' unless status.success?
end
puts 'PASS shared appearance/checkbox routing, no live input modifiers/menus, single-hierarchy scaling and bounded pinned geometry'
unless ARGV.include?('--native')
 puts 'Native scaled-control checks are opt-in: --native (test-owned panel only)'
 exit
end

# Synthetic clicks stay inside a test-owned nonactivating panel; the pointer is not moved.
native=<<~'SWIFT'
import AppKit
import SwiftUI
struct BackgroundAppearance {}
enum MaterialPillStyle {static let horizontalPadding:CGFloat=4,verticalPadding:CGFloat=4}
extension View {
 func materialPill(backgroundAppearance:BackgroundAppearance)->some View{self}
 func previewControlVisibilityAnimation(isVisible:Bool,duration:Double,animationsEnabled:Bool)->some View{self}
}
struct PreviewSelectionInteraction {
 let isDragOrigin:Bool;let toggle:()->Void;let drag:AnyGesture<DragGesture.Value>;let end:()->Void
}
SWIFT
native+=block(regular,'struct PreviewSelectionCheckbox:')+"\n"
native+=block(mock,'private struct ScaledToFit:')+"\n"
native+=<<~'SWIFT'
@MainActor final class Geometry:ObservableObject {
 @Published var checked=[false,false]
 var frames:[Int:CGRect]=[:],clicks:[Int:Int]=[:]
 func click(_ id:Int){clicks[id,default:0]+=1;if id%2==1{checked[id/2].toggle()}}
}
struct Measure:ViewModifier {
 let id:Int;let state:Geometry
 func body(content:Content)->some View {
  content.background{GeometryReader{proxy in
   Color.clear.onAppear{state.frames[id]=proxy.frame(in:.named("root"))}
    .onChange(of:proxy.frame(in:.named("root"))){state.frames[id]=$0}
  }.allowsHitTesting(false)}
 }
}
struct Card:View {
 @ObservedObject var state:Geometry;let id:Int
 var body:some View {
  HStack(spacing:24){
   Button{state.click(id*2)}label:{Circle().fill(.yellow).frame(width:20,height:20)}.buttonStyle(.plain)
    .modifier(Measure(id:id*2,state:state))
   PreviewSelectionCheckbox(isChecked:state.checked[id],isVisible:true,color:.blue,toggle:{state.click(id*2+1)})
    .modifier(Measure(id:id*2+1,state:state))
   Text("Title").allowsHitTesting(false)
  }.frame(width:200,height:80)
 }
}
struct Layout {let laysOutItemsInRows:Bool;let centerLines=true;let spacing:CGFloat=10;let inset:CGFloat=8}
struct Probe:View {
 @ObservedObject var state:Geometry;let rows:Bool;let maximumHeight:CGFloat
 var body:some View {
  let layout=Layout(laysOutItemsInRows:rows)
  let lines=[[0,1]]
  let makeCard:(Int)->AnyView={AnyView(Card(state:state,id:$0))}
  let mockPreviewActive=true
  Group {
SWIFT
native+=mock_flow+"\n"
native+=<<~'SWIFT'
  }.modifier(ScaledToFit(maxHeight:maximumHeight))
   .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
   .coordinateSpace(name:"root")
 }
}
@main struct Checks {
 @MainActor static func pump(_ time:Double){RunLoop.main.run(until:Date().addingTimeInterval(time))}
 @MainActor static func main(){
  let app=NSApplication.shared;app.setActivationPolicy(.prohibited);app.finishLaunching()
  guard NSScreen.screens.first != nil else{print("SKIP native scaled sample geometry: no display");return}
  var count=0
  for rows in [false,true]{for maximumHeight:CGFloat in [400,160,100,60]{
   let state=Geometry()
   let panel=NSPanel(contentRect:CGRect(x:100,y:100,width:600,height:420),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
   panel.isReleasedWhenClosed=false
   let host=NSHostingView(rootView:Probe(state:state,rows:rows,maximumHeight:maximumHeight))
   panel.contentView=host;panel.orderFront(nil);host.layoutSubtreeIfNeeded();pump(0.15)
   precondition(state.frames.count==4,"Every displayed control must have geometry")
   for id in 0..<4{
    guard let rect=state.frames[id] else{preconditionFailure("Missing control")}
    precondition(rect.width>0 && rect.height>0 && rect.minX>=0 && rect.maxX<=host.bounds.width+1)
    let point=host.convert(CGPoint(x:rect.midX,y:host.isFlipped ? rect.midY:host.bounds.height-rect.midY),to:nil)
    let expected=state.clicks[id,default:0]+1
    let now=ProcessInfo.processInfo.systemUptime
    for (i,type) in [NSEvent.EventType.leftMouseDown,.leftMouseUp].enumerated(){
     app.postEvent(NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:now-0.02+Double(i)*0.02,windowNumber:panel.windowNumber,context:nil,eventNumber:i,clickCount:1,pressure:type == .leftMouseUp ? 0:1)!,atStart:false)
    }
    let deadline=Date().addingTimeInterval(0.1)
    while Date()<deadline,let event=app.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true){app.sendEvent(event)}
    pump(0.02)
    precondition(state.clicks[id]==expected,"Displayed center must activate its own scaled control: rows=\(rows),height=\(maximumHeight),id=\(id),frame=\(rect),clicks=\(state.clicks)")
    count+=1
   }
   precondition(state.checked==[true,true])
   panel.close()
  }}
  print("PASS production mock flow + ScaledToFit + checkbox: \(count) visible-center clicks across both axes and four scales, no pointer movement or working windows")
 }
}
SWIFT
Dir.mktmpdir('dockfork-scaled-mock-') do |dir|
 input=File.join(dir,'checks.swift');binary=File.join(dir,'checks');File.write(input,native)
 output,status=Open3.capture2e('swiftc','-swift-version','5','-parse-as-library',input,'-o',binary)
 abort output unless status.success?
 output,status=Open3.capture2e(binary);puts output;abort 'Scaled mock control geometry did not pass' unless status.success?
end

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
bar=File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SearchWindow.swift")
shared=File.read("#{root}/DockDoor/Utilities/Window Management/WindowDiscoveryShared.swift")
preview=File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview.swift")
source="import AppKit\nimport SwiftUI\nimport Combine\ntypealias CGSSpaceID=UInt64\n"
%w[ManagedSpaceKind ManagedSpaceDescriptor ManagedDisplayDescriptor ManagedSpaceDestination SpaceContentsGap SpaceContentsDropTarget].each do |name|
  source+=block(shared,(%w[ManagedSpaceKind SpaceContentsDropTarget].include?(name) ? "enum #{name}:" : "struct #{name}:"))+"\n"
end
source+=<<~'SWIFT'
struct PreviewWindowIdentity:Hashable {let pid:Int32;let windowID:UInt32}
enum SpaceMenuDisplayMode {case numberOnly,fullName}
enum ManagedSpacePresentation {
SWIFT
model=block(shared,'enum ManagedSpacePresentation {')
%w[App Entry Display].each{|name|source+=block(model,"    struct #{name}:")+"\n"}
source+="}\n"
source+=<<~'SWIFT'
struct SpacesBarPreparedLayout {struct Key:Equatable {var value=0}}
struct BackgroundAppearance:Equatable {var tint:Double=0}
SWIFT
%w[SpacesBarContentKey SpacesBarInteraction].each{|name|source+=block(bar,"struct #{name}:")+"\n"}
%w[SpacesBarHostedState SpacesBarHostedContent].each{|name|source+=block(bar,"#{name=='SpacesBarHostedState' ? 'final class':'struct'} #{name}:")+"\n"}
formatting=block(preview,'enum AppIconStripFormatting {')
source+=formatting.sub(block(formatting,'    static func attributedIcons('),'')+"\n"
source+=<<~'SWIFT'
func reference(total:Int,available:CGFloat,icon:CGFloat,font:NSFont,spacing:CGFloat?,maximum:Int?=nil)->Int? {
 guard total>0,available>0 else{return nil}
 var count=min(total,max(0,maximum ?? total),Int(available/icon))
 while count>=0 {
  let remaining=total-count,suffix=remaining>0 ? (count>0 ? " +\(remaining)":"+\(remaining)"):""
  let gap=spacing ?? ("\u{00A0}" as NSString).size(withAttributes:[.font:font]).width
  var required=CGFloat(count)*icon+CGFloat(max(0,count-1))*gap+(suffix as NSString).size(withAttributes:[.font:font]).width
  if let spacing,remaining>0,count>0{required+=spacing-(" " as NSString).size(withAttributes:[.font:font]).width}
  if required<=available{return count};count-=1
 }
 return nil
}
enum Samples {static var values:[CGFloat]=[]}
struct Slide:AnimatableModifier {
 var x:CGFloat
 var animatableData:CGFloat {get{x}set{x=newValue}}
 func body(content:Content)->some View{Samples.values.append(x);return content.offset(x:x)}
}
@main struct Checks {
 @MainActor static func main(){
  var cases=0
  for total in [0,1,2,5,12,24] {for fontSize:CGFloat in [13,24,36]{for spacing:CGFloat in [0,6,12]{
   let font=NSFont.systemFont(ofSize:fontSize),icon=fontSize*1.4
   var measurements=0
   let fit=AppIconStripFormatting.PreparedFit(total:total,iconSize:icon,font:font,spacing:spacing,measure:{text,font in measurements+=1;return (text as NSString).size(withAttributes:[.font:font]).width})
   let cold=measurements
   for width in stride(from:0,through:700,by:7) {
    let available=CGFloat(width),expected=reference(total:total,available:available,icon:icon,font:font,spacing:spacing)
    precondition(fit.visibleCount(availableWidth:available)==expected && AppIconStripFormatting.visibleCount(total:total,availableWidth:available,iconSize:icon,font:font,spacing:spacing)==expected,"Prepared/shared fit must match frozen algorithm")
    cases+=1
   }
   precondition(measurements==cold,"Warm fitting must perform no text measurements")
   for maximum in [-1,0,1,5] {
    precondition(AppIconStripFormatting.visibleCount(total:total,availableWidth:100,iconSize:icon,font:font,maximumVisible:maximum)==reference(total:total,available:100,icon:icon,font:font,spacing:nil,maximum:maximum))
   }
  }}}
  print("PASS prepared/shared icon fitting: \(cases) frozen-reference cases, nil/default spacing and maximum limits; warm fit text measurements=0")
  let space=ManagedSpaceDescriptor(id:1,kind:.desktop,number:1,desktopNumber:1,ownerPIDs:[])
  let display=ManagedDisplayDescriptor(identifier:"test",currentSpaceID:1,spaces:[space])
  let entry=ManagedSpacePresentation.Entry(destination:.init(display:display,space:space),apps:[.init(application:.current,windowIdentities:[.init(pid:1,windowID:11)])])
  let key=SpacesBarContentKey(layout:.init(),sections:[.init(id:"test",name:"Test",spaces:[entry])],widths:[1:160],gapProgress:0,size:CGSize(width:160,height:40),allowedGaps:[],coordinator:nil,session:1,flags:[true],colors:[.red],scalars:[1],background:.init())
  let state=SpacesBarHostedState();var publications=0
  let subscription=state.objectWillChange.sink{publications+=1}
  func content(_ x:CGFloat)->AnyView{AnyView(Color.gray.frame(width:20,height:20).modifier(Slide(x:x)))}
  state.update({content(0)},key:key,interaction:.init(),animation:nil)
  let cold=publications
  for _ in 0..<100 {state.update({content(0)},key:key,interaction:.init(),animation:nil)}
  precondition(publications==cold && state.revision==1,"Scroll/fade-only passes must not publish content")
  state.update({content(2)},key:key,interaction:.init(highlighted:1),animation:nil)
  precondition(publications==cold+1,"Keyboard highlight must publish exactly once")
  state.update({content(3)},key:key,interaction:.init(highlighted:1,control:1,hovered:1),animation:nil)
  precondition(publications==cold+2,"Hover and filter-control state must remain live")
  state.update({content(4)},key:key,interaction:.init(filtered:1),animation:nil)
  precondition(publications==cold+3,"Filter state must remain live")
  state.update({content(5)},key:key,interaction:.init(dropTarget:1,contentsTarget:.space(1)),animation:nil)
  precondition(publications==cold+4,"Drop highlight must remain live")
  func changed(layout:SpacesBarPreparedLayout.Key=key.layout,sections:[ManagedSpacePresentation.Display]=key.sections,widths:[UInt64:CGFloat]=key.widths,gap:CGFloat=0,size:CGSize=key.size,gaps:Set<SpaceContentsGap>=[],coordinator:ObjectIdentifier?=nil,session:UInt?=1,flags:[Bool]=key.flags,colors:[Color?]=key.colors,scalars:[CGFloat]=key.scalars,background:BackgroundAppearance=key.background)->SpacesBarContentKey {
   .init(layout:layout,sections:sections,widths:widths,gapProgress:gap,size:size,allowedGaps:gaps,coordinator:coordinator,session:session,flags:flags,colors:colors,scalars:scalars,background:background)
  }
  let newEntry=ManagedSpacePresentation.Entry(destination:entry.destination,apps:[.init(application:.current,windowIdentities:[.init(pid:1,windowID:22)])])
  let owner=NSObject()
  let variants=[changed(layout:.init(value:1)),changed(sections:[.init(id:"test",name:"Changed",spaces:[entry])]),changed(sections:[.init(id:"test",name:"Test",spaces:[newEntry])]),changed(widths:[1:200]),changed(gap:0.5),changed(size:CGSize(width:200,height:40)),changed(gaps:[.init(displayID:"test",beforeSpaceID:1)]),changed(coordinator:ObjectIdentifier(owner)),changed(session:2),changed(flags:[false]),changed(colors:[.blue]),changed(scalars:[2]),changed(background:.init(tint:0.3))]
  for variant in variants {
   state.update({content(0)},key:key,interaction:.init(),animation:nil)
   let before=publications
   state.update({content(0)},key:variant,interaction:.init(),animation:nil)
   precondition(publications==before+1,"Changed content/geometry/style/targets must publish")
  }
  print("COUNT 100 scroll/fade-only updates: hosted publications before=100, after=0; real interaction changes publish once each; \(variants.count) presentation invalidations pass")
  let app=NSApplication.shared;app.setActivationPolicy(.accessory)
  let panel=NSPanel(contentRect:CGRect(x:20,y:20,width:100,height:40),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  panel.ignoresMouseEvents=true
  let hosted=SpacesBarHostedState()
  panel.contentView=NSHostingView(rootView:SpacesBarHostedContent(state:hosted))
  hosted.update({content(0)},key:key,interaction:.init(),animation:nil)
  panel.orderFront(nil);RunLoop.main.run(until:Date().addingTimeInterval(0.12))
  Samples.values=[]
  hosted.update({content(40)},key:key,interaction:.init(filtered:1),animation:.linear(duration:0.3))
  for _ in 0..<12 {RunLoop.main.run(until:Date().addingTimeInterval(0.035))}
  precondition(Samples.values.contains{$0>0 && $0<40},"Filter changes must retain native intermediate animation frames")
  Samples.values=[]
  hosted.update({content(0)},key:key,interaction:.init(),animation:nil)
  RunLoop.main.run(until:Date().addingTimeInterval(0.12))
  precondition(!Samples.values.contains{$0>0 && $0<40},"Disabled/reduced-motion transaction must update immediately")
  panel.orderOut(nil);panel.contentView=nil
  var released:SpacesBarHostedState?=SpacesBarHostedState();weak var weakState=released
  released!.update({content(0)},key:key,interaction:.init(),animation:nil);released=nil
  precondition(weakState==nil,"Prepared content must not own its presenter")
  _=subscription
  print("PASS production hosted presenter: exact publication gating, model identity changes, native filter animation, immediate no-animation path and cleanup; only a disposable mouse-inert panel")
 }
}
SWIFT
Dir.mktmpdir('dockfork-bar-presentation-') do |dir|
  File.write("#{dir}/checks.swift",source)
  abort 'Presentation compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
  abort 'Presentation checks failed' unless system("#{dir}/checks")
end
scroll=block(bar,'struct SpacesBarScroll:')
abort 'Content factory must not bypass publication gating' unless scroll.include?('view.updateContent(content, key: contentKey, interaction: interaction, animation: contentAnimation)')
abort 'Prepared fit must retain original fallback' unless bar.include?('let fit = preparedLayout.iconFits[entry.id], fit.requiredWidths.count == apps.count + 1') && bar.include?('preparedLayout.key.iconSize == SpacesBarAppLayout.iconSize') && bar.include?('preparedLayout.key.font == font') && bar.include?('AppIconStripFormatting.visibleCount(')
puts 'PASS production adapter and unknown-layout fitting fallback contracts'

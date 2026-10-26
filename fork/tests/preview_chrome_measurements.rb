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
preview=File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview.swift")
state=File.read("#{root}/DockDoor/Views/Hover Window/WindowPreview Supporting/PreviewStateCoordinator.swift")
panel=File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
shared=File.read("#{root}/DockDoor/Utilities/Window Management/WindowDiscoveryShared.swift")
bar=File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SearchWindow.swift")
source=<<~'SWIFT'
import AppKit
struct WindowPreviewHoverContainer {struct WindowDimensions:Equatable {var size:CGSize;var maxDimensions:CGSize}}
enum DockPosition {case bottom,left}
struct App {var localizedName:String?="App"}
final class ImageToken {}
struct WindowInfo {
 var id:Int;var windowName:String?;var app=App();var image:ImageToken?=ImageToken()
 var isWindowlessApp=false,isWineWindow=false,hasLimitedWindowControls=false,isMinimized=false,isHidden=false
 var isFullscreen:Bool?=false;var closeButton:Int?=1;var spaceID:Int?=7,spaceNumberOverride:Int?
 var isEffectivelyHiddenForUI:Bool{isHidden && isFullscreen != true}
 var spaceNumber:Int? {Metrics.numberReads+=1;return spaceNumberOverride ?? spaceID.flatMap{SpaceNumberResolver.fallback[$0]}}
}
struct PreviewWindowIdentity:Hashable {let id:Int;init(_ w:WindowInfo){id=w.id}}
enum WindowStateIndicatorPlacement {case off,onWindowPreviews,nextToTrafficLightButtons}
enum WindowAction {case close,quit,minimize,maximize
 func isSupported(for w:WindowInfo)->Bool{!(w.isFullscreen==true && (self == .minimize || self == .maximize))}
}
enum WindowTitleFontSize {case system,subheadline,caption2,caption,footnote,body,headline,title3,title2,title}
SWIFT
source+="extension WindowTitleFontSize {\n"+block(preview,'    var appKitTextStyle:')+"\n}\n"
source+=<<~'SWIFT'
struct PreviewAppearanceSettings:Equatable {
 var showSpaceNumberIndicator=false,showWindowlessAppQuitButton=true
 var enabledTrafficLightButtons:Set<WindowAction>=[.close,.quit,.minimize]
 var windowStateIndicatorPlacement=WindowStateIndicatorPlacement.onWindowPreviews
 var windowTitleFontSize=WindowTitleFontSize.body,windowStateIndicatorFontSize=WindowTitleFontSize.body
 var geometryVersion=0
 static var current=Self()
 static func resolve(windowSwitcherActive:Bool,dockPosition:DockPosition)->Self{current}
}
struct BackgroundAppearance:Equatable {var version=0;static var current=Self();static func resolve()->Self{current}}
final class Screen {var visibleFrame=CGRect(x:0,y:0,width:900,height:700);var backingScaleFactor:CGFloat=2}
typealias NSScreen=Screen
enum Key {case enableMultiWindowSelection,showUncheckedSelectionCheckboxes,uniformCardRadius,showAppIconOnly}
enum Defaults {static var unchecked=false;static subscript(_ k:Key)->Bool{k == .enableMultiWindowSelection || (k == .showUncheckedSelectionCheckboxes && unchecked)}}
enum Metrics {static var fits=0,panelFits=0,layouts=0,alive=0,numberReads=0;static var zero=false}
enum SpaceNumberResolver {
 static let lock=NSLock();static var numbersByID:[Int:Int]=[:],fallback:[Int:Int]=[:]
SWIFT
source+=block(shared,'    static func cachedNumber(')+"\n}\n"
source+=block(preview,'func resolvedTrafficLightButtons(')+"\n"+block(preview,'enum WindowStateSymbolResolver {')+"\n"
source+=<<~'SWIFT'
struct WindowPreview {
 var windowInfo:WindowInfo;var onTap:(()->Void)?;var index:Int;var dockPosition:DockPosition;var bestGuessMonitor:NSScreen
 var uniformCardRadius:Bool;var handleWindowAction:(WindowAction)->Void;var isSelected:Bool;var windowSwitcherActive:Bool
 var dimensions:WindowPreviewHoverContainer.WindowDimensions;var showAppIconOnly:Bool;var mockPreviewActive:Bool
 var onHoverIndexChange:((Int?,CGPoint?)->Bool)?;var onDragHoverIndexChange:((Int?)->Void)?
 var useLivePreview:Bool;var skeletonMode:Bool;var appearance:PreviewAppearanceSettings;var backgroundAppearance:BackgroundAppearance
 var focusedWindowID:Int?;var currentSpaceNumbers:Set<Int>;var isChecked:Bool
SWIFT
pv=block(preview,'struct WindowPreview:')
source+=block(pv,'    struct ChromeMeasurementKey:')+"\n"+block(pv,'    var chromeMeasurementKey:')+"\n"
%w[previewTitle isEffectivelyHidden windowStateSymbols visibleWindowStateLabel windowStateLabel effectiveTrafficLightButtons].each{|name|source+=block(pv,"    private var #{name}:")+"\n"}
source+="}\n"
source+=<<~'SWIFT'
class NSView {
 var value=CGSize(width:300,height:200)
 func layoutSubtreeIfNeeded(){Metrics.layouts+=1}
 var fittingSize:CGSize{Metrics.panelFits+=1;return value}
}
final class NSHostingView<Content>:NSView {
 let rootView:Content
 init(rootView:Content){self.rootView=rootView;Metrics.alive+=1}
 deinit{Metrics.alive-=1}
 override var fittingSize:CGSize {
  guard let sample=rootView as? WindowPreview else{return super.fittingSize}
  Metrics.fits+=1
  if sample.appearance.showSpaceNumberIndicator && sample.windowInfo.spaceID != nil {_=sample.windowInfo.spaceNumber}
  return CGSize(width:sample.dimensions.size.width,height:Metrics.zero ? 0:sample.dimensions.size.height+(sample.isChecked ? 35:20))
 }
}
struct Selection {struct Checked {var membership:Set<PreviewWindowIdentity>=[]};var checkedWindows=Checked()}
@MainActor final class Probe {
 var windows:[WindowInfo]=[];var selection=Selection()
 private var switcherChromeMeasurements:[(key:WindowPreview.ChromeMeasurementKey,height:CGFloat)]=[]
 var count:Int{switcherChromeMeasurements.count}
 func clear(){switcherChromeMeasurements.removeAll()}
SWIFT
source+=block(state,'    private func measureSwitcherCardChromeHeight(').sub('private func','func')+"\n}\n"
source+="enum SpacesBarLayout {\n"+block(bar,'    static func windowSize(')+"\n}\n"
source+=<<~'SWIFT'
final class SizingState {var hasActiveSearch=false,windowSwitcherActive=true,expectedContentSizeIsExact=true;var expectedContentSize=CGSize(width:300,height:200)}
@MainActor final class FrameProbe {
 var isVisible=true,contentView:NSView?=NSHostingView(rootView:WindowPreviewHoverContainer())
 var panelAnchor:(screen:NSScreen,value:Int)?=(NSScreen(),0),maximum=CGSize(width:600,height:400)
 var windowSwitcherCoordinator=SizingState(),spacesBarSections:[Int]=[],spaceFilterTop:CGFloat?
 var frame=CGRect(x:0,y:0,width:300,height:200),origin=CGPoint.zero,originCalls=0,placements=0
 func maximumPreviewSize(on:NSScreen)->CGSize{maximum}
 func anchoredOrigin(for:CGSize)->CGPoint?{originCalls+=1;return origin}
 func setFrame(_ frame:CGRect,display:Bool){self.frame=frame}
 func animator()->FrameProbe{self}
 func animateWithUserPreference(_ action:()->Void){action()}
 func positionCompanionWindows(){placements+=1}
SWIFT
source+=block(panel,'    private func refreshPanelFrameToFitContent(').sub('private func','func')+"\n}\n"
source+=<<~'SWIFT'
@main struct Checks {
 @MainActor static func main(){
  let p=Probe(),screen=NSScreen()
  p.windows=[WindowInfo(id:1,windowName:"First"),WindowInfo(id:2,windowName:"Second")]
  p.selection.checkedWindows.membership=[PreviewWindowIdentity(p.windows[1])]
  typealias D=WindowPreviewHoverContainer.WindowDimensions
  var dims=[0:D(size:CGSize(width:300,height:200),maxDimensions:CGSize(width:320,height:240)),1:D(size:CGSize(width:300,height:200),maxDimensions:CGSize(width:320,height:240))]
  func measure()->CGFloat?{p.measureSwitcherCardChromeHeight(dimensionsMap:dims,dockPosition:.bottom,bestGuessMonitor:screen)}
  precondition(measure()==35 && Metrics.fits==2 && p.count==2 && Metrics.alive==0)
  let coldStart=Metrics.fits
  for _ in 0..<100 {p.clear();precondition(measure()==35)}
  let coldFits=Metrics.fits-coldStart,warmFits=Metrics.fits
  precondition(coldFits==200)
  for _ in 0..<100 {precondition(measure()==35)}
  precondition(Metrics.fits==warmFits,"Warm normal/checked geometry must not create or fit hosting views")
  print("COUNT 100 normal+checked passes: uncached skeleton fits=\(coldFits), warm=\(Metrics.fits-warmFits); retained hosting views=0")
  weak var oldImage=p.windows[0].image
  p.windows[0].image=ImageToken()
  precondition(oldImage==nil && measure()==35 && Metrics.fits==warmFits,"Image replacement must not invalidate or be retained in geometry keys")
  p.windows[0].id=99
  precondition(measure()==35 && Metrics.fits==warmFits,"Equivalent geometry must not depend on row/window identity")
  var before=Metrics.fits;dims[0]!.size.width-=40;_=measure();precondition(Metrics.fits==before+1)
  before=Metrics.fits;PreviewAppearanceSettings.current.geometryVersion+=1;_=measure();precondition(Metrics.fits==before+2)
  before=Metrics.fits;BackgroundAppearance.current.version+=1;_=measure();precondition(Metrics.fits==before+2)
  before=Metrics.fits;p.windows[0].windowName="Changed";_=measure();precondition(Metrics.fits==before+1)
  before=Metrics.fits;p.windows[0].app.localizedName="Changed app";_=measure();precondition(Metrics.fits==before+1)
  before=Metrics.fits;p.windows[0].isMinimized=true;_=measure();precondition(Metrics.fits==before+1)
  before=Metrics.fits;p.windows[0].isMinimized=false;p.windows[0].closeButton=nil;_=measure();precondition(Metrics.fits==before+1)
  before=Metrics.fits;p.windows[0].isFullscreen=true;_=measure();precondition(Metrics.fits==before+1)
  before=Metrics.fits;screen.backingScaleFactor=1;_=measure();precondition(Metrics.fits==before+2)
  before=Metrics.fits;screen.visibleFrame.size.width-=1;_=measure();precondition(Metrics.fits==before+2)
  before=Metrics.fits;PreviewAppearanceSettings.current.windowTitleFontSize = .title;_=measure();precondition(Metrics.fits==before+2)
  before=Metrics.fits;PreviewAppearanceSettings.current.windowStateIndicatorFontSize = .caption;_=measure();precondition(Metrics.fits==before+2)
  for i in 0..<50 {p.windows[0].windowName="Window \(i)";_=measure();precondition(p.count<=2 && Metrics.alive==0)}
  Defaults.unchecked=true
  precondition(measure()==20 && p.count==1,"No optional checked sample when checkboxes already occupy normal geometry")
  p.clear();Metrics.zero=true;before=Metrics.fits
  precondition(measure()==nil && measure()==nil && p.count==0 && Metrics.fits==before+2,"Invalid fits must not be cached")
  Metrics.zero=false
  let missing=p.measureSwitcherCardChromeHeight(dimensionsMap:[:],dockPosition:.bottom,bestGuessMonitor:screen)
  precondition(missing==nil && p.count==0)
  PreviewAppearanceSettings.current.showSpaceNumberIndicator=true
  SpaceNumberResolver.numbersByID=[:];before=Metrics.fits
  _=measure();_=measure();precondition(Metrics.fits==before+2 && p.count==0,"Unknown numbering must preserve fitting fallback")
  precondition(Metrics.numberReads==2,"Only the original view fallback may resolve unknown numbering")
  SpaceNumberResolver.numbersByID[7]=12;before=Metrics.fits;_=measure();_=measure()
  precondition(Metrics.fits==before+1 && Metrics.numberReads==3)
  before=Metrics.fits;SpaceNumberResolver.numbersByID[7]=13;_=measure();precondition(Metrics.fits==before+1)
  p.clear();precondition(p.count==0 && Metrics.alive==0)
  print("PASS production sample keys/measurement: dimensions, complete appearance/background, titles, controls/state, fonts, screen/scale, checked sample, Space numbering, unknown/invalid fallback, bounded cache and image/view release; no live AX/topology/window operations")
let f=FrameProbe();Metrics.panelFits=0;Metrics.layouts=0
for _ in 0..<50{f.refreshPanelFrameToFitContent()}
precondition(Metrics.panelFits==50 && Metrics.layouts==50,"Retain final fitting until prediction validity can be proven")
f.contentView!.value=CGSize(width:350,height:240)
f.refreshPanelFrameToFitContent()
precondition(f.windowSwitcherCoordinator.expectedContentSizeIsExact && f.frame.size==CGSize(width:350,height:240),"Metadata can change intrinsic size before recomputation despite a stale exact prediction")
f.origin=CGPoint(x:10,y:20);f.refreshPanelFrameToFitContent();precondition(f.frame.origin==f.origin)
f.windowSwitcherCoordinator.hasActiveSearch=true;f.contentView!.value=CGSize(width:220,height:180)
f.refreshPanelFrameToFitContent();precondition(f.frame.size==CGSize(width:220,height:180),"Search must size only its filtered rows")
f.windowSwitcherCoordinator.hasActiveSearch=false;f.windowSwitcherCoordinator.expectedContentSize=f.frame.size
f.contentView=NSView();f.contentView!.value=f.frame.size;f.refreshPanelFrameToFitContent()
f.contentView=NSHostingView(rootView:WindowPreviewHoverContainer());f.contentView!.value=f.frame.size
f.windowSwitcherCoordinator.windowSwitcherActive=false;f.refreshPanelFrameToFitContent()
f.windowSwitcherCoordinator.windowSwitcherActive=true;f.windowSwitcherCoordinator.expectedContentSizeIsExact=false
f.refreshPanelFrameToFitContent()
precondition(Metrics.panelFits==56 && Metrics.layouts==56)
print("PASS unchanged production panel fitting: 50 stable fits/layouts retained, stale exact prediction, intrinsic growth, search, unknown content, Dock/Compact fallback and anchor changes; no panel-fitting shortcut")
 }
}
SWIFT
Dir.mktmpdir('dockfork-chrome-measurements-') do |dir|
  File.write("#{dir}/checks.swift",source)
  abort 'Chrome checks compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',"#{dir}/checks.swift",'-o',"#{dir}/checks")
  abort 'Chrome checks failed' unless system("#{dir}/checks")
end
%w[deactivateKeybindSession].each{|name|abort 'Chrome samples must clear on session teardown' unless block(state,"    func #{name}(").include?('switcherChromeMeasurements.removeAll()')}
key=block(pv,'    var chromeMeasurementKey:')
abort 'Geometry key must use cached-only numbering and not retain/query screenshots or AX' if key.include?('windowInfo.spaceNumber :') || key.match?(/\.image\b(?! != nil)|AXUIElement|managedDisplays/)
abort 'Chrome keys must reject unknown rendering contexts' unless key.include?('guard skeletonMode, windowSwitcherActive, !mockPreviewActive, !useLivePreview')
puts 'PASS cache teardown, cached-only key and unknown-rendering-context contracts'

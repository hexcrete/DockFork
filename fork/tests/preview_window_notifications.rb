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
coordinator = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
geometry = block(coordinator, '        for name in [NSWindow.didMoveNotification,')
focus = block(coordinator, '        for name in [NSWindow.didBecomeKeyNotification,')
abort 'Keep the existing five subscriptions, routing geometry and focus separately' unless geometry.scan(/NSWindow\.did\w+Notification/).length == 3 && geometry.include?('#selector(previewGeometryDidChange)') && focus.scan(/NSWindow\.did\w+Notification/).length == 2 && focus.include?('#selector(publishTapSnapshot)')
abort 'Preserve self-resize anchor handling and teardown' unless coordinator.include?('#selector(panelDidResize), name: NSWindow.didResizeNotification, object: self') && block(coordinator, '    deinit {').include?('NotificationCenter.default.removeObserver(self)')
source = <<~'SWIFT'
import AppKit
@MainActor final class Probe: NSPanel {
 var searchWindow:NSPanel?,spacesBarWindow:NSPanel?,fullPreviewWindow:NSPanel?
 var snapshots=0,placements=0
 @objc private func publishTapSnapshot(){snapshots+=1;if spacesBarWindow != nil{placements+=1}}
 func installReference(){
  for name in [NSWindow.didMoveNotification,NSWindow.didResizeNotification,NSWindow.didBecomeKeyNotification,NSWindow.didResignKeyNotification,NSWindow.didExposeNotification] {
   NotificationCenter.default.addObserver(self,selector:#selector(publishTapSnapshot),name:name,object:nil)
  }
 }
 func install(){
SWIFT
source += geometry + "\n" + focus + "\n}\n"
source += block(coordinator, '    @objc private func previewGeometryDidChange(') + "\n"
source += <<~'SWIFT'
 func detach(){NotificationCenter.default.removeObserver(self)}
}
@main struct Checks {
 @MainActor static func main(){
  _=NSApplication.shared
  func panel()->NSPanel{NSPanel(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)}
  let probe=Probe(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  probe.searchWindow=panel();probe.spacesBarWindow=panel();probe.fullPreviewWindow=panel()
  let unrelated=[panel(),panel(),panel()]
  let center=NotificationCenter.default
  let geometry:[Notification.Name]=[NSWindow.didMoveNotification,NSWindow.didResizeNotification,NSWindow.didExposeNotification]
  probe.installReference()
  for _ in 0..<100 {for window in unrelated {for name in geometry {center.post(name:name,object:window)}}}
  let originalSnapshots=probe.snapshots,originalPlacements=probe.placements
  precondition(originalSnapshots==900 && originalPlacements==900)
  probe.detach();probe.snapshots=0;probe.placements=0;probe.install()
  for name in geometry {
   for window in [probe,probe.searchWindow!,probe.spacesBarWindow!,probe.fullPreviewWindow!] {
    let before=probe.snapshots,placements=probe.placements
    center.post(name:name,object:window)
    precondition(probe.snapshots==before+1 && probe.placements==placements+1,"Owned geometry must update synchronously")
   }
  }
  let before=probe.snapshots,placements=probe.placements
  for _ in 0..<100 {for window in unrelated {for name in geometry {center.post(name:name,object:window)}}}
  for name in geometry {center.post(name:name,object:nil);center.post(name:name,object:NSObject())}
  precondition(probe.snapshots==before && probe.placements==placements,"Unrelated/malformed geometry must do no preview work")
  print("COUNT 900 unrelated move/resize/expose events: preview snapshots before=\(originalSnapshots), placements before=\(originalPlacements); after=0 each")
  for name in [NSWindow.didBecomeKeyNotification,NSWindow.didResignKeyNotification] {
   for window in [probe,unrelated[0]] {
    let count=probe.snapshots;center.post(name:name,object:window)
    precondition(probe.snapshots==count+1,"Focus notifications must retain the broad route")
   }
  }
  let oldBar=probe.spacesBarWindow!,newBar=panel();probe.spacesBarWindow=newBar
  let count=probe.snapshots
  center.post(name:NSWindow.didMoveNotification,object:oldBar)
  precondition(probe.snapshots==count,"Removed companions must not match by a stale identity")
  center.post(name:NSWindow.didMoveNotification,object:newBar)
  precondition(probe.snapshots==count+1)
  probe.spacesBarWindow=nil;probe.searchWindow=nil;probe.fullPreviewWindow=nil
  let disabledCount=probe.snapshots,disabledPlacements=probe.placements
  center.post(name:NSWindow.didResizeNotification,object:probe)
  center.post(name:NSWindow.didMoveNotification,object:newBar)
  precondition(probe.snapshots==disabledCount+1 && probe.placements==disabledPlacements,"Missing/disabled companions must remain inert")
  probe.detach();let detachedCount=probe.snapshots
  center.post(name:NSWindow.didMoveNotification,object:probe)
  center.post(name:NSWindow.didBecomeKeyNotification,object:unrelated[0])
  precondition(probe.snapshots==detachedCount)
  precondition(!probe.isVisible && unrelated.allSatisfy{!$0.isVisible},"The fixture must not show or focus any panels")
  print("PASS production notification routing: immediate owned-panel geometry, unchanged focus, replacement/disabled companions, nil/non-window objects and observer cleanup; no shown panels or working windows")
 }
}
SWIFT
Dir.mktmpdir('dockfork-preview-notifications-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Notification checks compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Notification checks failed' unless system("#{dir}/checks")
end

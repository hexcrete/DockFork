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
constants = File.read("#{root}/DockDoor/consts.swift")
catalog = File.read("#{root}/DockDoor/Views/Settings/Search/SettingsSearchCatalog.swift")
mode = block(constants, 'enum PreviewFocusFadeMode:')
helper = 'Fade the preview container after a pause to reveal the highlighted window’s full-size preview. Mouse or keyboard input restores it.'
abort 'All modes must share the concise explainer' unless block(mode, '    var helperText:').include?(helper) && catalog.scan(helper).length == 3
%w[Window\ Switcher Dock\ previews Cmd+Tab\ previews].each do |name|
  title = "Enable #{name} fade out when resting on a preview"
  abort "Mismatched fade title: #{name}" unless mode.include?("\"#{title}\"") && catalog.include?("\"#{title}\"")
end
abort 'Remove the old disclaimer from settings' if mode.include?('(Experimental)') || mode.include?('The cause has not been resolved.')
coordinator = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
abort 'Grid, search and Spaces Bar must share fade/restore/cleanup' unless block(coordinator, '    private func setPreviewFocusOpacity(').include?('[contentView, searchWindow?.contentView, spacesBarWindow?.contentView]')
abort 'Activity must restore smoothly' unless block(coordinator, '    func registerPreviewFocusActivity()').include?('restorePreviewFocusOpacity(animated: true)')
stop = block(coordinator, '    private func stopPreviewFocusFade()')
abort 'Teardown must cancel timers/monitors and restore even an interrupted return animation' unless %w[invalidate removeMonitor focusFadeMode].all? { |token| stop.include?(token) } && stop.include?('if wasMonitoring { setPreviewFocusOpacity(1, duration: 0) }')
source = "import AppKit\nimport SwiftUI\nimport QuartzCore\nenum PreviewHoverAction { case previewFullSize, none }\n"
source += block(coordinator, 'enum PreviewFocusFadePolicy {') + "\n"
source += <<~'SWIFT'
let app = NSApplication.shared
let panel = NSPanel(contentRect: NSRect(x: 40, y: 40, width: 120, height: 120), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear
let hosting = NSHostingView(rootView: Color.red.frame(width: 120, height: 120))
panel.contentView = hosting
hosting.wantsLayer = true
panel.orderFrontRegardless()
defer { panel.orderOut(nil) }
let layer = hosting.layer!
func tick(_ time: Double = 0.04) { CATransaction.flush(); RunLoop.current.run(until: Date().addingTimeInterval(time)) }
func targetsPanel() -> Bool { NSWindow.windowNumber(at: NSPoint(x: 100, y: 100), belowWindowWithWindowNumber: 0) == panel.windowNumber }
tick()
precondition(targetsPanel())
// Characterize the original failure using the same transparent native panel.
layer.opacity = 0
tick()
precondition(!targetsPanel(), "Characterization: zero render opacity must lose WindowServer targeting")
for opacity: Float in [0, 0.01, 0.2, 0.5, 1] {
 PreviewFocusFadePolicy.setOpacity(opacity, on: layer, duration: 0)
 tick()
 precondition(targetsPanel(), "Faded panel must remain a native mouse target")
 precondition(hosting.alphaValue == 1 && panel.alphaValue == 1)
 precondition(hosting.hitTest(NSPoint(x: 60, y: 60)) != nil)
}
PreviewFocusFadePolicy.setOpacity(0, on: layer, duration: 0.3)
tick()
let halfway = layer.presentation()!.opacity
precondition(halfway > 0.01 && halfway < 1)
PreviewFocusFadePolicy.setOpacity(1, on: layer, duration: 0.2)
let returning = layer.animation(forKey: "previewFocusFade") as! CABasicAnimation
precondition(abs((returning.fromValue as! Float) - halfway) < 0.02, "Interrupted animations must begin at rendered opacity")
PreviewFocusFadePolicy.setOpacity(1, on: layer, duration: 0, onlyNewContent: true)
precondition(layer.animation(forKey: "previewFocusFade") != nil, "Unchanged-content refresh must not interrupt restoration")
PreviewFocusFadePolicy.setOpacity(1, on: layer, duration: 0)
precondition(layer.animation(forKey: "previewFocusFade") == nil && layer.opacity == 1, "Teardown/disabled animations restore immediately")
precondition(PreviewFocusFadePolicy.bounded(.nan, fallback: 0.2, range: 0...0.5) == 0.2)
precondition(PreviewFocusFadePolicy.canFade(enabled: true, hoverAction: .previewFullSize, containerVisible: true, fullPreviewVisible: true, hasSelection: true, menuTracking: false))
precondition(!PreviewFocusFadePolicy.canFade(enabled: false, hoverAction: .previewFullSize, containerVisible: true, fullPreviewVisible: true, hasSelection: true, menuTracking: false))
precondition(!PreviewFocusFadePolicy.canFade(enabled: true, hoverAction: .previewFullSize, containerVisible: true, fullPreviewVisible: true, hasSelection: true, menuTracking: true))
print("PASS native resting fade: reproduce zero-opacity hit loss; stable native targeting and view hits at all settings; smooth interrupted restore; refresh preservation; immediate cleanup; eligibility")
SWIFT
Dir.mktmpdir('dockfork-focus-fade-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Resting fade compilation failed' unless system('swiftc', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Resting fade checks failed' unless system("#{dir}/checks")
end

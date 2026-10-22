#!/usr/bin/env ruby
# Exercise production hit classification and zone caching without querying other apps.
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
zone = File.read("#{root}/DockDoor/Utilities/Window Gestures/WindowGestureZone.swift")
controller = File.read("#{root}/DockDoor/Utilities/Window Gestures/WindowGestureController.swift")
keys = File.read("#{root}/DockDoor/consts.swift")
view = File.read("#{root}/DockDoor/Views/Settings/GesturesSettingsView.swift")
catalog = File.read("#{root}/DockDoor/Views/Settings/Search/SettingsSearchCatalog.swift")
reset = File.read("#{root}/DockDoor/Views/Settings/MainSettingsView.swift")
key = 'disableTitleBarGesturesOverInteractiveElements'
title = 'Disable title bar gestures over interactive elements'
description = 'Skip controls, tabs and scrollable areas. Unrecognized areas are left to the app.'
abort 'Setting must default Off' unless keys.include?("Key<Bool>(\"#{key}\", default: false)")
abort 'Missing reset handling' unless reset.include?("Defaults.reset(.#{key})")
abort 'Missing matching setting/search strings' unless view.include?("Toggle(\"#{title}\"") && catalog.include?("title: String(localized: \"#{title}\")") && view.include?("Text(\"#{description}\")") && catalog.include?("description: String(localized: \"#{description}\")")
abort 'Missing matching search target' unless view.include?('.settingsSearchTarget("windowGestures.disableOverInteractiveElements")') && catalog.include?('id: "windowGestures.disableOverInteractiveElements"')
window = block(zone, '    private static func windowZone(')
abort 'Strict mode must reject both geometry-only fallback paths' unless window.scan(/guard !excludesInteractiveElements else \{ return \.notHere \}\s+return cachedTitleBarZone/).size == 2
abort 'Scrollable ancestors must be rejected before tab handling or window lookup' unless window.index('guard acceptsTitleBarHit(') < window.index('WindowUtil.windowInfo(') && window.index('guard acceptsTitleBarHit(') < window.index('if let tabIndex')
abort 'Upstream control exclusions must remain' unless window.include?('if let role = chain.first?.role, interactiveRoles.contains(role)')
abort 'Parent traversal must distinguish a complete chain' unless window.include?('var reachedWindow = hitNode.role == kAXWindowRole as String') && window.include?('reachedWindow = true')

source = <<~'SWIFT'
import AppKit
typealias AXUIElement = Int
enum Classification {
SWIFT
source += zone.lines.find { |line| line.include?('private static let backgroundRoles:') }.sub('private ', '')
source += block(zone, '    private struct AXNode {').sub('private ', '') + "\n"
source += block(zone, '    private static func acceptsTitleBarHit(').sub('private ', '') + "\n}\n"
source += <<~'SWIFT'
enum Key { case disableTitleBarGesturesOverInteractiveElements }
enum Defaults { static var strict = false; static subscript(_ key: Key) -> Bool { strict } }
struct Zone: Equatable { let window: Int?; let name: String }
enum WindowGestureZoneResolver {
 static var calls = 0, result: Zone?
 static func resolve(at point: CGPoint) -> Zone? { calls += 1; return result }
}
enum DebugLogger {
 static func measureSlow<T>(_ name: String, thresholdMs: Double, details: String, _ body: () -> T) -> T { body() }
}
final class Cache {
 static let zoneReuseWindow = 0.6
 var recentZone: RecentZone?
SWIFT
source += block(controller, '    private struct RecentZone {').sub('private ', '').gsub('WindowGestureZone?', 'Zone?') + "\n"
source += block(controller, '    private func zone(at point:').sub('private ', '').gsub('WindowGestureZone?', 'Zone?') + "\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 static func main() {
  func hit(_ roles: [String?], complete: Bool = true, strict: Bool = true) -> Bool {
   let chain = roles.enumerated().map { Classification.AXNode(element: $0.offset, role: $0.element, subrole: nil, parent: nil) }
   return Classification.acceptsTitleBarHit(chain, reachedWindow: complete, excludesInteractiveElements: strict)
  }
  let allowed: [String?] = ["AXGroup", "AXToolbar", "AXStaticText", "AXImage"]
  let rejected: [String?] = ["AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXLink", "AXDisclosureTriangle", "AXTextField", "AXSlider", "AXComboBox", "AXIncrementor", "AXValueIndicator", "AXTabGroup", "AXTextArea", "AXScrollBar", "AXScrollArea", "AXTable", "AXOutline", "AXList", "AXBrowser", "AXGrid", "AXLayoutArea", "AXWebArea", "AXUnknown", nil]
  precondition(hit([]) && hit(allowed))
  precondition(!hit(allowed, complete: false))
  for role in allowed {
   precondition(hit([role]) && hit(["AXStaticText", role, "AXToolbar"]), "Recognized title-bar backgrounds must remain available")
  }
  for role in rejected {
   precondition(!hit([role]) && !hit(["AXStaticText", role, "AXToolbar"]), "Interactive/content ancestors must block child labels")
   precondition(hit([role], strict: false) && hit([role], complete: false, strict: false), "Disabled option must preserve existing classification")
  }
  precondition(!hit(["AXStaticText", "AXRadioButton", "AXTabGroup", "AXToolbar"]), "Tab strips must be rejected without a scrolling ancestor")
  precondition(!hit(["AXImage", "AXTabGroup", "AXGroup"]), "Tab icons must be rejected without scrolling metadata")
  let cache = Cache(), origin = CGPoint(x: 100,y: 100), nearby = CGPoint(x: 102,y: 100)
  let window = Zone(window: 1,name: "window"), dock = Zone(window: nil,name: "dock"), menu = Zone(window: nil,name: "menu")
  WindowGestureZoneResolver.result = window
  precondition(cache.zone(at: origin, now: 0) == window)
  _ = cache.zone(at: nearby, now: 0.1)
  precondition(WindowGestureZoneResolver.calls == 1)
  Defaults.strict = true; WindowGestureZoneResolver.result = nil
  precondition(cache.zone(at: nearby, now: 0.2) == nil && WindowGestureZoneResolver.calls == 2, "Enabling must reject old broad window cache")
  WindowGestureZoneResolver.result = window
  _ = cache.zone(at: origin, now: 0.3)
  WindowGestureZoneResolver.result = nil
  precondition(cache.zone(at: nearby, now: 0.4) == nil && WindowGestureZoneResolver.calls == 4, "Window approval must not leak onto nearby controls or tab strips")
  Defaults.strict = false; WindowGestureZoneResolver.result = window
  precondition(cache.zone(at: origin, now: 0.5) == window, "Disabling must not reuse a strict refusal")
  Defaults.strict = true
  for zone in [dock, menu] {
   cache.recentZone = nil; WindowGestureZoneResolver.result = zone
   let before = WindowGestureZoneResolver.calls
   _ = cache.zone(at: origin, now: 1); _ = cache.zone(at: nearby, now: 1.1)
   precondition(WindowGestureZoneResolver.calls == before + 1, "Dock/menu caching must stay unchanged")
  }
  print("PASS production background policy, interactive/content ancestry, tab strips without scrolling metadata, unknown/incomplete hits, default-Off behavior, setting transitions and cache isolation")
 }
}
SWIFT
Dir.mktmpdir('dockfork-titlebar-policy-') do |dir|
  File.write("#{dir}/checks.swift", source)
  abort 'Gesture policy compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', "#{dir}/checks.swift", '-o', "#{dir}/checks")
  abort 'Gesture policy checks failed' unless system("#{dir}/checks")
end

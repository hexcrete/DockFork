#!/usr/bin/env ruby
# Static wiring audit. Does not open DockFork or read/write live preferences.
ROOT = File.expand_path('../..', __dir__)
def read(path)
  File.read(File.join(ROOT, path))
end
def check(condition, message)
  abort message unless condition
end

view = read('DockDoor/Views/Settings/KeybindsSettingsView.swift')
controls = view[view.index('private struct WindowSelectionSettingsSection:')...view.index('private struct SpacesSettingsSection:')]
range_helper = 'Select a range by Shift-clicking another checkbox, dragging from a checkbox across previews, or holding the Toggle Window Selection shortcut while using arrow keys.'
check(controls.match?(/if enabled \{\s+Text\(String\(localized: "#{Regexp.escape(range_helper)}"\)\)/), 'Range-selection explainer must appear only when selection is enabled')
catalog = read('DockDoor/Views/Settings/Search/SettingsSearchCatalog.swift')
keys = read('DockDoor/consts.swift')
bindings = controls.scan(/@Default\(\.(\w+)\) private var (\w+)/).to_h.invert
expected = {
  'enableMultiWindowSelection' => 'false', 'keepWindowSwitcherOpenWhenSelected' => 'false',
  'enableWindowlessAppSelection' => 'true',
  'showWindowSelectionSummary' => 'true', 'showUncheckedSelectionCheckboxes' => 'true',
  'selectionCheckboxVisibility' => '.previewHover', 'linkTiledWindowsWhenResizing' => 'false',
  'maximumTilingRows' => '2', 'maximumTilingColumns' => '3',
  'tileOnlyWhatFits' => 'false', 'fillActionsAutoTileSelection' => 'false'
}
check(bindings.values.sort == expected.keys.sort, 'Selection/tiling preference inventory changed; review this audit')
seen = []
section = nil
binding = title = nil
literal = /"(?:\\.|[^"\\])*"/
controls.each_line do |line|
  section = Regexp.last_match(1) if line =~ /SettingsGroup\(header: "([^"]+)"/
  if line =~ /(?:isOn|selection): \$(\w+)/
    binding = Regexp.last_match(1)
    title = line[/\A\s*(?:Toggle|Picker)\((?:String\(localized: )?(#{literal})/, 1]
  end
  next unless line =~ /\.settingsSearchTarget\("([^"]+)"\)/
  id = Regexp.last_match(1)
  key = bindings.fetch(binding)
  check(id == "gestures.#{key}", "Wrong search target for #{key}")
  check(catalog.scan(/\bid: "#{Regexp.escape(id)}"/).size == 1, "Missing/duplicate catalog entry: #{id}")
  start = catalog.index("id: \"#{id}\"")
  item = catalog[start...catalog.index("\n        ),", start)]
  check(item.include?('tab: "Keybinds"'), "Wrong tab for #{id}")
  check(item.include?("section: String(localized: \"#{section}\")"), "Wrong section for #{id}")
  check(title && item.include?("title: String(localized: #{title})"), "Title mismatch for #{id}")
  description = item[/description: String\(localized: (#{literal})/, 1]
  check(description && controls.include?(description), "Helper text mismatch for #{id}")
  default = keys[/static let #{key} = Key<[^>]+>\("#{key}", default: ([^)]+)\)/, 1]
  check(default == expected.fetch(key), "Default changed for #{key}: #{default}")
  seen << key
end
check(seen.sort == expected.keys.sort, 'A preference has no indexed control, or a control is duplicated')
check(controls.include?('Text("Auto Tile")'), 'Auto Tile subsection missing')
engine = read('DockDoor/Views/Settings/Search/SettingsSearchEngine.swift')
check(engine.include?('"Keybinds"'), 'Settings search does not recognize the Keybinds tab')
check(read('DockDoor/Utilities/Misc Utils.swift').include?('Defaults.removeAll()'), 'Review reset coverage')
backup = read('DockDoor/Utilities/SettingsBackupManager.swift')
check(backup.include?('domain.mapValues(jsonValue(fromPlist:))') && backup.include?('defaults.setPersistentDomain(settings, forName: domainName)'), 'Review generic backup/restore coverage')
puts "PASS #{seen.size} settings: bindings, defaults, search IDs/titles/helpers/sections, reset and backup paths"

util = read('DockDoor/Utilities/Window Management/WindowUtil.swift')
catalog = read('DockDoor/Utilities/Window Management/WindowActionCatalog.swift')
check(util.include?('fillActionsAutoTile: Defaults[.fillActionsAutoTileSelection]'), 'Fill toggle not connected to shared batch routing')
check(util.include?('guard Defaults[.tileOnlyWhatFits] else { return eligible }') && util.include?('Array(eligible.prefix(capacity))'), 'Capacity toggle not connected to shared eligible targets')
check(util.include?('let windows = autoTileTargets(from: windows)') && catalog.include?('targets = WindowUtil.autoTileTargets(from: targets)'), 'Shared/direct Auto Tile eligibility disconnected')
check(catalog.include?('self == .autoTileSelectedWindows || (windowCount > 1 && fillActionsAutoTile)'), 'Review explicit Auto Tile versus group Fill routing')
check(read('DockDoor/Views/Hover Window/WindowPreviewHoverContainer.swift').include?('WindowUtil.tilePreviewWindows(windows, direction: .neutral, bringToFront: true'), 'Drag-to-tile lost explicit Auto Tile routing')
check(read('DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift').include?('performPreviewBatchAction(.autoTileSelectedWindows, on: targets'), 'Selection summary lost explicit Auto Tile routing')
scripts = read('DockDoor/Utilities/ScriptCommands.swift')
check(scripts.include?('WindowUtil.performPreviewBatchAction(action, on: windows)') && scripts.include?('WindowUtil.tilePreviewWindows(windows, direction: direction, bringToFront: foreground)'), 'Script action/tiling routes disconnected')
puts 'PASS shared Fill, explicit Auto Tile, drag, summary and AppleScript routes; run linked_tiling.rb for behavior checks'

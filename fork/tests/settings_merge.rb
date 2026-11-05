#!/usr/bin/env ruby
require 'json'
require 'open3'
require 'set'

ROOT = File.expand_path('../..', __dir__)
SETTINGS = 'DockDoor/Views/Settings'
PANES = {
  'MainSettingsView' => 'General', 'DockPreviewsSettingsView' => 'DockPreviews',
  'WindowSwitcherBehaviorSettingsView' => 'WindowSwitcher', 'CmdTabSettingsView' => 'CmdTab',
  'GesturesSettingsView' => 'Gestures', 'KeybindsSettingsView' => 'Keybinds',
  'AppearanceSettingsView' => 'Appearance', 'FiltersSettingsView' => 'Filters',
  'WidgetSettingsView' => 'Widgets', 'AdvancedSettingsView' => 'Advanced', 'SupportSettingsView' => 'Support'
}.freeze

def source_block(source, start)
  opening = source.index('{', start)
  depth = 0
  (opening...source.length).each do |index|
    depth += 1 if source[index] == '{'
    depth -= 1 if source[index] == '}'
    return source[start..index] if depth.zero?
  end
  abort "Unclosed source block at #{start}"
end

def source_call(source, start)
  opening = source.index('(', start)
  depth = 0
  (opening...source.length).each do |index|
    depth += 1 if source[index] == '('
    depth -= 1 if source[index] == ')'
    return source[start..index] if depth.zero?
  end
  abort "Unclosed source call at #{start}"
end

def inventory(sources)
  nodes = {}
  sources.each do |path, source|
    source.to_enum(:scan, /^(?:private )?struct (\w+)[^\n]*\{/).each do
      match = Regexp.last_match
      nodes[match[1]] = { 'path' => path, 'source' => source_block(source, match.begin(0)) }
    end
  end
  nodes.each_value do |node|
    node['targets'] = (node['source'].scan(/settingsSearchTarget\("((?:[^"\\]|\\.)*)"\)/).flatten +
      node['source'].scan(/\w+Target: "([^"]+)"/).flatten).reject { |id| id.include?('\\(') }.uniq
    node['children'] = node['source'].scan(/\b([A-Z]\w*)\s*\(/).flatten.uniq.select { |name| nodes.key?(name) }
  end
  targets = Hash.new { |hash, key| hash[key] = [] }
  PANES.each do |pane, tab|
    remaining = [pane]
    seen = Set.new
    until remaining.empty?
      name = remaining.pop
      next unless seen.add?(name) && (node = nodes[name])
      node['targets'].each { |id| targets[id] << tab unless targets[id].include?(tab) }
      remaining.concat(node['children'])
    end
  end
  { 'targets' => targets, 'nodes' => nodes }
end

Dir.chdir(ROOT)
current = inventory(Dir.glob("#{SETTINGS}/**/*.swift").to_h { |path| [path, File.read(path)] })
if ARGV.include?('--inventory')
  puts JSON.generate(current)
  exit
end

base = JSON.parse(File.read('fork/version.json')).fetch('upstreamCommit')
abort 'Invalid upstream base' unless base.match?(/\A[0-9a-f]{40}\z/)
paths, status = Open3.capture2('git', 'ls-tree', '-r', '--name-only', base, '--', SETTINGS)
abort 'Cannot read upstream Settings inventory' unless status.success?
upstream = inventory(paths.lines.map(&:strip).select { |path| path.end_with?('.swift') }.to_h do |path|
  source, result = Open3.capture2('git', 'show', "#{base}:#{path}")
  abort "Cannot read #{path}" unless result.success?
  [path, source]
end)
# These upstream controls were intentionally replaced by existing fork behavior, not lost during reorganization.
replaced = Set.new(%w[appearance.spaceNumber appearance.distinguishMinimized dockPreviews.restoreAllMinimizedOnClick])
errors = []
form_source = File.read("#{SETTINGS}/Shared Components/SettingsForm.swift")
header_source = source_block(form_source, form_source.index('.safeAreaInset('))
errors << 'Pinned headers must clip and bound hit testing after their background' unless header_source.index('.background(') < header_source.index('.clipped()').to_i && header_source.include?('.contentShape(Rectangle())')
mock_source = File.read("#{SETTINGS}/Shared Components/SettingsMockPreview.swift")
scaled_source = source_block(mock_source, mock_source.index('private struct ScaledToFit:'))
errors << 'Scaled preview overflow must be clipped and hit testing bounded' unless scaled_source.match?(/\.scaleEffect\(scale\).*?\.clipped\(\)\s*\.contentShape\(Rectangle\(\)\)/m)
cmd_source = current['nodes'].fetch('CmdKeyShortcutsSection')['source']
row_source = source_block(cmd_source, cmd_source.index('private func cmdShortcutRow('))
errors << 'Preview assignment must precede flexible space and the action picker' unless row_source.index('KeyCaptureButton(') < row_source.index('Spacer(minLength: 8)').to_i && row_source.index('Spacer(minLength: 8)') < row_source.index('Picker("Action"').to_i
errors << 'Preview clash warning must immediately follow its assignment, not the action menu' unless row_source.index('SettingsShortcutConflictWarning(') < row_source.index('Spacer(minLength: 8)')
errors << 'Preview rows must not retain numbered labels or inline Add controls' if row_source.include?('LabeledContent(') || row_source.include?('ControlGroup')
errors << 'Preview Add must append a stable pending record' unless cmd_source.include?('cmdShortcuts.append(pending)') && cmd_source.include?('SettingsShortcutListFooter(title: "Add a Shortcut"')
keybind_source = current['nodes'].fetch('WindowSwitcherKeybindSection')['source']
mode_picker = current['nodes'].fetch('SettingsShortcutModePicker')['source']
errors << 'Mode picker must compress without an unnecessarily narrow cap' unless mode_picker.include?('.frame(minWidth: 44, maxWidth: 260, alignment: .trailing)') && mode_picker.include?('.layoutPriority(-1)') && !mode_picker.include?('.fixedSize(')
fitting_row = current['nodes'].fetch('SettingsShortcutRow')['source']
errors << 'Shortcut assignments and mode menus must share one aligned top row' unless fitting_row.include?('HStack(spacing: 8)') && fitting_row.include?('Spacer(minLength: 8)') && !fitting_row.include?('ViewThatFits')
alternate_row = source_block(keybind_source, keybind_source.index('private func alternateShortcutRow('))
errors << 'Alternate checkboxes must occupy an indented second row' unless alternate_row.include?('SettingsDependentRows {') && alternate_row.index('SettingsShortcutModePicker(') < alternate_row.index('Toggle("Double-tap"')
errors << 'Alternate Shortcuts must use only upstream storage, not transfers or hidden legacy records' if keybind_source.include?('persistentSwitcherShortcuts') || keybind_source.include?('alternateRowOrder') || keybind_source.include?('orderedAlternateIDs')
['Press and release the chosen modifier, then press it again to open the switcher without a trigger key.', 'Keep the switcher open after releasing the shortcut modifiers.'].each do |help|
 errors << "Missing Alternate Shortcuts tooltip: #{help}" unless alternate_row.include?(".help(\"#{help}\")")
end
errors << 'Quick Switch must disable only Persistent, retaining Double-tap and scope' unless alternate_row.scan('.disabled(shortcut.quickSwitch)').length == 1 && alternate_row.include?('Toggle("Quick Switch"')
errors << 'Last Focused must be a Quick Switch row, not a separate editor' if keybind_source.include?('lastFocusedShortcutsSection') || current['nodes'].key?('ScopedShortcutRows') || current['nodes'].key?('KeyCombinationCaptureButton')
keyboard_source = File.read('DockDoor/Utilities/KeybindHelper.swift')
errors << 'Every shortcut list must share the Add/Reset footer' unless keybind_source.include?('SettingsShortcutListFooter(') && cmd_source.include?('SettingsShortcutListFooter(')
errors << 'Preview footer must not retain legacy extra top padding' if cmd_source.include?('.padding(.top, 4)')
capture_controls = current['nodes'].fetch('SettingsKeyCaptureControls')['source']
errors << 'Shared warning must follow key capture and precede reset' unless capture_controls.index('KeyCaptureButton(') < capture_controls.index('SettingsShortcutConflictWarning(').to_i && capture_controls.index('SettingsShortcutConflictWarning(') < capture_controls.index('SettingsResetButton(').to_i
spaces_settings = current['nodes'].fetch('SpacesSettingsSection')['source']
errors << 'Space shortcuts must share the single Spaces section' unless spaces_settings.scan('SettingsSection(').size == 1 && spaces_settings.include?('SettingsSection("Spaces")') && spaces_settings.include?('Toggle("Enable Spaces Shortcuts"')
errors << 'Spaces shortcut explanation must belong to its row, not the section footer' unless spaces_settings.include?('.settingsAnnotation("When a window preview is focused,') && !spaces_settings.include?('SettingsSection("Spaces", footer:')
tiling = current['nodes'].fetch('TilingSettingsSection')['source']
errors << 'Auto Tile controls must share Tiling and have explicit prefixes' unless tiling.scan('SettingsSection(').size == 1 && ['Auto Tile maximum rows:', 'Auto Tile maximum columns:', 'Auto Tile only what fits'].all? { |title| tiling.include?("\"#{title}\"") }
feedback_tabs = current['targets']['gestures.enableActionFeedback']
errors << 'Action Feedback must live only in Appearance' unless feedback_tabs == ['Appearance'] && current['targets']['gestures.actionFeedbackPosition'] == ['Appearance']
errors << 'Click behavior must use the shorter label' unless keybind_source.include?('Picker("Clicks trigger:"') && !keybind_source.include?('Left/right clicks trigger:')
errors << 'Space-cycle keys must use labeled shared capture/reset controls' unless spaces_settings.include?('return LabeledContent(title)') && spaces_settings.include?('SettingsKeyCaptureControls(keyCode: key,') && !spaces_settings.include?('Button("Clear")')
errors << 'Search and Selection key must share capture/reset alignment' unless keybind_source.include?('SettingsKeyCaptureControls(keyCode: $selectionKeyCode') && keybind_source.include?('SettingsKeyCaptureControls(keyCode: $searchTriggerKey, defaultKeyCode: Defaults.Keys.searchTriggerKey.defaultValue')
dependent_rows = current['nodes'].fetch('SettingsDependentRows')['source']
errors << 'Dependent settings must retain individual native rows, without a nested stack or section' unless dependent_rows.include?('Group { content }') && dependent_rows.include?('.padding(.leading, 20)') && !dependent_rows.match?(/\b(?:VStack|Section|SettingsSection)\s*[({]/)
%w[WindowStateIndicatorSettingsSection WindowSelectionSettingsSection ActionFeedbackSettingsSection].each do |name|
  errors << "#{name} lost its dependent-row hierarchy" unless current['nodes'].fetch(name)['source'].include?('SettingsDependentRows {')
end
upstream['targets'].each do |id, tabs|
  next if replaced.include?(id)
  actual = current['targets'][id]
  errors << "#{id}: upstream #{tabs.inspect}, fork #{actual.inspect}" unless actual && (tabs - actual).empty?
end
%w[KeybindsSettingsView GesturesSettingsView DockPreviewsSettingsView CmdTabSettingsView WindowSwitcherBehaviorSettingsView].each do |name|
  node = current['nodes'].fetch(name)
  errors << "#{name} retains a standalone divider inside a native Form" if node['source'].match?(/^\s*Divider\(/)
end
%w[CmdKeyShortcutsSection WindowSwitcherKeybindSection TrackpadSwitcherSwipeSection].each do |name|
  node = current['nodes'].fetch(name)
  errors << "#{name} retains a standalone divider inside a native Form" if node['source'].match?(/^\s*Divider\(/)
end
dock_source = current['nodes'].fetch('DockPreviewsSettingsView')['source']
appearance_rows = source_block(dock_source, dock_source.index('private var appearanceRows:'))
errors << 'Dock indicator section must be a peer Form section, not nested in Appearance' if appearance_rows.include?('windowStateIndicatorSection')
shortcuts = current['nodes'].fetch('WindowSwitcherKeybindSection')['source']
errors << 'Alternate shortcuts must use combined modifier controls including existing Shift support' unless shortcuts.include?('ModifierKeyToggles(modifierFlags: alternateModifierBinding') && shortcuts.include?('includesShift: true')
errors << 'Viewing Settings must not materialize inherited alternate modifiers' if shortcuts.include?('materializeInheritedAlternateModifiers')
errors << 'Retired shortcut storage must not be reintroduced' if shortcuts.include?('@Default(.additionalAlternateKeybinds)')
all = current['nodes'].values.map { |node| node['source'] }.join("\n")
upstream_constants, result = Open3.capture2('git', 'show', "#{base}:DockDoor/consts.swift")
abort 'Cannot read upstream preference declarations' unless result.success?
preference_names = ->(text) { text.scan(/static let (\w+)\s*= Key</).flatten.to_set }
fork_preferences = preference_names.call(File.read('DockDoor/consts.swift')) - preference_names.call(upstream_constants)
reset_counts = Hash.new(0)
Dir.glob("#{SETTINGS}/**/*.swift").each do |path|
  text = File.read(path)
  aliases = text.scan(/@Default\(\.(\w+)\)\s+(?:private\s+)?var (\w+)/).to_h.invert
  text.to_enum(:scan, /\bSettingsSliderRow\(/).each do
    call = source_call(text, Regexp.last_match.begin(0))
    key = aliases[call[/value:\s*\$(\w+)/, 1]]
    next unless key && fork_preferences.include?(key)
    errors << "#{path}: #{key} slider has no declared-default reset" unless call.include?("defaultValue: Defaults.Keys.#{key}.defaultValue")
    reset_counts[:sliders] += 1
  end
  text.to_enum(:scan, /\bPicker\([^\n]*?selection: \$(\w+)\)\s*\{/).each do
    match = Regexp.last_match
    key = aliases[match[1]]
    next unless key && fork_preferences.include?(key)
    start = match.begin(0)
    after = text[(start + source_block(text, start).length)..]
    errors << "#{path}: dropdowns must not get reset glyphs, matching upstream's control types" if after.lstrip.start_with?('.settingsReset(')
    reset_counts[:pickers] += 1
  end
end
errors << 'Generic picker reset wrapper must be removed' if all.include?('SettingsValueReset') || all.include?('func settingsReset<')
compact_source = File.read("#{SETTINGS}/Appearance/CompactModeSection.swift")
%w[windowSwitcherCompactThreshold dockPreviewCompactThreshold cmdTabCompactThreshold].each do |name|
  errors << "Upstream #{name} must not receive a new glyph" if compact_source.include?("defaultValue: Defaults.Keys.#{name}.defaultValue")
end
fade_source = current['nodes'].fetch('PreviewFocusFadeSettings')['source']
%w[delay duration opacity].each { |name| errors << "Missing shared #{name} reset" unless fade_source.include?("defaultValue: mode.#{name}Key.defaultValue") }
errors << 'Shortcut clashes must use the shared compact warning, not inline messages or tinted rows' if all.include?('Text(conflict.localizedMessage)') || cmd_source.include?('Color.red.opacity')
%w[CmdKeyShortcutsSection WindowSwitcherKeybindSection].each do |name|
  errors << "#{name} does not use shared conflict warnings" unless current['nodes'].fetch(name)['source'].include?('SettingsShortcutConflictWarning(')
end
errors << 'Scoped shortcut lists must use bottom Add, not inline +/- or count-per-mode caps' if shortcuts.include?('ControlGroup') || shortcuts.include?('count < SwitcherInvocationMode.allCases.count')
errors << 'Legacy settings helpers survived reconciliation' if all.include?('sliderSetting(') || all.include?('SettingsIllustratedToggle(')
abort errors.join("\n") unless errors.empty?
puts "PASS upstream Settings placement: #{upstream['targets'].length - replaced.length} shared target locations, explicit retired-control exceptions, native Form rows, and merged alternate controls"
puts "PASS upstream-matched reset scope: #{reset_counts[:sliders]} direct fork sliders, #{reset_counts[:pickers]} fork dropdowns without glyphs, shared fork fade/range controls; upstream thresholds unchanged"

require 'tmpdir'
def declaration(source, signature)
  start = source.index(signature) or abort "Missing #{signature}"
  source_block(source, start)
end
constants = File.read('DockDoor/consts.swift')
keyboard = File.read('DockDoor/Utilities/KeybindHelper.swift')
dock = File.read("#{SETTINGS}/DockPreviewsSettingsView.swift")
modifier = File.read("#{SETTINGS}/Shared Components/ModifierKeyToggles.swift")
source = "import Foundation\nimport AppKit\nimport Carbon\nimport SwiftUI\nimport CoreGraphics\n"
capture_source = File.read('DockDoor/Components/KeyCaptureButton.swift')
source += declaration(keyboard, 'enum ShortcutModifier:') + "\n"
source += declaration(capture_source, 'final class SettingsShortcutCaptureState {') + "\n"
handler_source = declaration(keyboard, '    private func handleEvent(')
recovery = source_block(handler_source, handler_source.index('if let passthrough = reEnableIfNeeded'))
abort 'Tap recovery must clear all transient key trackers' unless recovery.include?('modifierDoubleTapState = ModifierDoubleTapState()') && recovery.include?('pressedModifierKeyCodes.removeAll()')
abort 'Primary key-code zero must display its real key label' if declaration(shortcuts, '    private var triggerKeyRow:').include?('keybind.keyCode != 0')
switcher_settings=File.read("#{SETTINGS}/WindowSwitcherBehaviorSettingsView.swift")
%w[spacesBarRecentlyUsed spacesBarFilterWindows enableSpacesBar spacesBarHideWhenSingle].each do |key|
 abort "Missing existing live Spaces callback: #{key}" unless switcher_settings.include?(".onChange(of: #{key})")
end
abort 'Native-tab presentation changes must refresh existing Space aggregates' unless File.read("#{SETTINGS}/DockPreviewsSettingsView.swift").include?('.onChange(of: collapseNativeTabsIntoSingleWindow)')
abort 'Capture must pass through before shortcut/repeat execution' unless handler_source.index('SettingsShortcutCaptureState.shared.isActive') < handler_source.index('// Keep consumed action keys suppressed')
ordinary_route = declaration(keyboard, '    private func determineActionForKeyDown(')
abort 'Held/persistent matching must choose the first row from one resolved list' unless ordinary_route.include?('let shortcuts = switcherShortcuts()') && ordinary_route.include?('let matchingShortcut = resolveAlternateShortcut(in: shortcuts, keyCode: keyCode, flags: flags)') && ordinary_route.include?('matchingShortcut.flatMap { $0.persistent || $0.quickSwitch ? nil : $0 }') && ordinary_route.include?('matchingShortcut.flatMap { $0.persistent && !$0.quickSwitch ? $0 : nil }')
abort 'Backward-modifier tolerance must be explicit, not inherited by action shortcuts' unless declaration(keyboard, '    private func modifierFlagsMatch(').include?('allowBackwardModifier: Bool = false')
abort 'Space-cycle shortcuts must use exact modifiers' unless handler_source.include?('if modifierFlagsMatch(spaceCycleKeybind, flags: flags),')
abort 'Retired fork shortcut stores must not be read, reset or migrated' if constants.include?('static let persistentSwitcherShortcuts') || constants.include?('static let persistentSwitcherStartsUnfocused') || keyboard.include?('Defaults[.persistentSwitcher') || File.read("#{SETTINGS}/MainSettingsView.swift").include?('Defaults[.persistentSwitcher')
held_route = source_block(handler_source, handler_source.index('if let action = handleModifierDoubleTap(event: event)'))
abort 'Double-tap actions must share the blacklist guard before choosing held/persistent/quick execution' unless held_route.index('WindowUtil.shouldIgnoreKeybindForFrontmostApp()') < held_route.index('if case let .openHeldSwitcher')
abort 'Held double-tap must claim its session before asynchronous presentation' unless held_route.index('beginSwitcherSession(with: keybind)') < held_route.index('Task {') && held_route.include?('rollbackSessionActive: rollbackActive')
abort 'Capture must clean up on view disappearance and finish' unless capture_source.include?('.onDisappear {') && capture_source.include?('SettingsShortcutCaptureState.shared.end(captureToken)')
[['enum ShortcutModifierKey:', constants], ['enum ModifierKeySide:', constants], ['enum SwitcherInvocationMode:', constants],
 ['struct AlternateSwitcherShortcut:', constants], ['struct ResolvedAlternateSwitcherShortcut', constants], ['enum AlternateSwitcherShortcutConflict:', constants], ['struct UserKeyBind:', keyboard],
 ['enum DockClickAction:', constants], ['private enum DockIconClickChoice:', dock]].each do |signature, text|
  source += declaration(text, signature).gsub(/, Defaults\.(?:Serializable|PreferRawRepresentable)/, '').sub('private enum', 'enum') + "\n"
end
source += <<~'SWIFT'
enum Action { case none, close }
struct CmdShortcut { var isPending = false; var action = Action.close; var keyCode: UInt16 }
enum Defaults {
 struct Key<T> { let value: T }
 static subscript<T>(_ key: Key<T>) -> T { get { key.value } set {} }
 static var alternateRows: [AlternateSwitcherShortcut] = []
 static var backward: UInt16 = 56
 static var switcherEnabled = true
 static var primary = UserKeyBind(keyCode:48,modifierFlags:Int(CGEventFlags.maskAlternate.rawValue))
 enum Keys {
  static var spacesBarMinimumIcons: Key<Int> { Key(value: 2) }
  static var spacesBarMaximumIcons: Key<Int> { Key(value: 6) }
 }
}
extension Defaults.Key where T == Bool {
 static var ignoreMainModifierSideForDependentShortcuts: Self { Self(value: false) }
 static var enableSpacesShortcuts: Self { Self(value: false) }
 static var enableWindowSwitcher: Self { Self(value: Defaults.switcherEnabled) }
}
extension Defaults.Key where T == UInt16 {
 static var switcherBackwardKeyCode: Self { Self(value: Defaults.backward) }
}
SWIFT
source += <<~'SWIFT'
extension Defaults.Key where T == [AlternateSwitcherShortcut] {
 static var alternateSwitcherShortcuts: Self { Self(value: Defaults.alternateRows) }
}
extension Defaults.Key where T == [CmdShortcut] {
 static var cmdShortcuts: Self { Self(value: []) }
}
extension Defaults.Key where T == UserKeyBind {
 static var UserKeybind: Self { Self(value: Defaults.primary) }
}
SWIFT
source += "enum WindowSwitcherShortcutResolver {\n"
%w[normalizedModifiers dependentShortcutKeybind spaceNumber conflictsWithSpacesShortcut alternateConflict resolvedAlternateShortcuts heldShortcutOverlaps combinationsMatch sidesOverlap].each do |name|
  prefix = %w[combinationsMatch sidesOverlap].include?(name) ? '    private static func ' : '    static func '
  signature = name == 'spaceNumber' ? prefix + 'spaceNumber(forPhysicalKeyCode' : prefix + name + '('
  source += declaration(constants, signature) + "\n"
end
source += "}\n"
source += "enum ModifierPolicy {\n" + declaration(modifier, '    static func toggledModifiers(') + "\n}\n"
source += declaration(constants, 'struct SpacesBarIconLimits:') + "\n"
source += "extension Defaults.Key where T == Int {\n static var Int64maskControl: Self { Self(value: Int(CGEventFlags.maskControl.rawValue)) }
 static var Int64maskAlternate: Self { Self(value: Int(CGEventFlags.maskAlternate.rawValue)) }
 static var Int64maskCommand: Self { Self(value: Int(CGEventFlags.maskCommand.rawValue)) }
 static var spacesBarMinimumIcons: Self { Self(value: 2) }\n static var spacesBarMaximumIcons: Self { Self(value: 6) }\n}\n"
source += "extension Defaults.Key { var defaultValue: T { value } }\n"
appearance_source = File.read("#{SETTINGS}/AppearanceSettingsView.swift")
source += "struct IconResetOwner {\n @Binding var spacesBarMinimumIcons: Int\n @Binding var spacesBarMaximumIcons: Int\n"
['    private var iconLimits:', '    private var minimumIcons:', '    private var maximumIcons:', '    private func resetIconLimits('].each do |signature|
  source += declaration(appearance_source, signature).sub('private var', 'var').sub('private func', 'func') + "\n"
end
source += "}\n"
source += "struct DockOwner {\n @Binding var shouldHideOnDockItemClick: Bool\n @Binding var dockClickAction: DockClickAction\n" + declaration(dock, '    private var dockIconClickChoice:').sub('private var', 'var') + "\n}\n"
source += "struct AlternateOwner {\n @Binding var alternateSwitcherShortcuts: [AlternateSwitcherShortcut]\n"
['    private func editedShortcut(', '    private func editShortcut(', '    private func alternateModifierBinding(', '    private func persistentBinding(', '    private func doubleTapBinding(', '    private var canAddAlternateShortcut:'].each do |signature|
  source += declaration(shortcuts, signature).sub('private func', 'func').sub('private var', 'var') + "\n"
end
source += "}\n"
primary = File.read("#{SETTINGS}/ShortcutCapture.swift")
source += "struct RecorderParent { var isRecording=true; var modifierKey=Int(CGEventFlags.maskAlternate.rawValue); var currentKeybind: UserKeyBind? = Defaults[.UserKeybind] }\nfinal class Recorder { var parent=RecorderParent()\n"
source += declaration(primary, '        func handleKeyEvent(') + "\n}\n"
source += "final class Detector {\n"
['    private enum ModifierDoubleTapAction {', '    private struct ModifierDoubleTapState {', '    private func handleModifierDoubleTap(', '    private func isWithinModifierDoubleTapInterval('].each do |signature|
 source += declaration(keyboard, signature).sub('private enum','enum').sub('private struct','struct').sub('private func','func') + "\n"
end
source += "var modifierDoubleTapState = ModifierDoubleTapState()\n}\n"
upstream_keyboard, upstream_result = Open3.capture2('git', 'show', "#{base}:DockDoor/Utilities/KeybindHelper.swift")
abort 'Cannot read upstream shortcut matching' unless upstream_result.success?
source += "struct UpstreamMatcher {\n" + declaration(upstream_keyboard, '    private func modifierFlagsMatch(').sub('private func', 'func') + "\n}\n"
source += "final class ModifierMatcher {\n var pressedModifierKeyCodes: Set<UInt16> = []\n var switcherSessionActive=false\n var activeSessionKeybind=Defaults[.UserKeybind]\n var isBackwardModifierPressed=false\n var shortcutReads=0\n"
['    private func modifierFlagsMatch(', '    private func modifierSideMatches(', '    private func activeBackwardModifierFlag(',
 '    private static func eventFlagForKeyCode(', '    private static func modifierKeyCodes(', '    private func canUseBackwardModifier(',
 '    private func backwardModifierIsPressed(', '    private func updateModifierStatesFromFlags(', '    private func resolveAlternateShortcut(',
 '    private func isCmdTabWindowSwitcherKeybind(', '    private func updatePressedModifierKeyCodes('].each do |signature|
 source += declaration(keyboard, signature).sub('private func', 'func').sub('private static func', 'static func') + "\n"
end
source += "func switcherShortcuts() -> [ResolvedAlternateSwitcherShortcut] { shortcutReads += 1; return WindowSwitcherShortcutResolver.resolvedAlternateShortcuts(Defaults.alternateRows,mainKeybind:Defaults[.UserKeybind],previewShortcuts:[]) }\n}\n"
quick_branch = source_block(ordinary_route, ordinary_route.index('if let matchingShortcut, matchingShortcut.quickSwitch {'))
source += declaration(keyboard, 'private final class PreviewActionKeyPressState {').sub('private final class','final class') + "\n"
source += "enum WindowUtil { static var ignoresKeybind=false; static func shouldIgnoreKeybindForFrontmostApp() -> Bool { ignoresKeybind } }\n@MainActor final class QuickDispatchProbe { var calls:[SwitcherInvocationMode]=[]; let actionKeyPressState=PreviewActionKeyPressState()\n func switchToLastFocusedWindow(mode:SwitcherInvocationMode) { calls.append(mode) }\n func dispatch(_ matchingShortcut:ResolvedAlternateSwitcherShortcut?, event:CGEvent) -> (shouldConsume:Bool,actionTask:(() async -> Void)?) {\n let keyCode=event.getIntegerValueField(.keyboardEventKeycode)\n" + quick_branch + "\n return (false,nil)\n }\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async throws {
  let capture = SettingsShortcutCaptureState.shared
  precondition(!capture.isActive)
  var cancelled = 0
  var first: UUID?
  first = capture.begin { cancelled += 1; capture.end(first) }
  precondition(capture.isActive)
  var second: UUID?
  second = capture.begin { cancelled += 1; capture.end(second) }
  precondition(cancelled == 1 && capture.isActive)
  capture.end(first)
  precondition(capture.isActive)
  NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
  precondition(cancelled == 2 && !capture.isActive)
  NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
  precondition(cancelled == 2)
  let third = capture.begin { cancelled += 1 }
  capture.end(third)
  capture.end(third)
  precondition(!capture.isActive && cancelled == 2)
  print("PASS production capture ownership: supersession, stale cleanup, deactivation, completed/cancelled cleanup and no remaining observer")
  let masks=[CGEventFlags.maskControl, .maskAlternate, .maskCommand, .maskShift].map { Int($0.rawValue) }
  for bits in 0..<16 {
   let flags=masks.enumerated().reduce(0) { $0 | ((bits & (1 << $1.offset)) != 0 ? $1.element : 0) }
   for mask in masks {
    let expected=flags ^ mask
    precondition(ModifierPolicy.toggledModifiers(flags,mask:mask,allowsEmpty:true)==expected)
    precondition(ModifierPolicy.toggledModifiers(flags,mask:mask,allowsEmpty:false)==(expected==0 ? flags : expected))
   }
  }
  final class State {
   var enabled=false
   var action=DockClickAction.hide
   var rows=[AlternateSwitcherShortcut(keyCode:0,modifierSide:.right,mode:.currentSpaceOnly,isConfigured:true)]
  }
  let state=State()
  let dock=DockOwner(shouldHideOnDockItemClick:Binding(get:{state.enabled},set:{state.enabled=$0}),dockClickAction:Binding(get:{state.action},set:{state.action=$0}))
  for action in DockClickAction.allCases {
   dock.dockIconClickChoice.wrappedValue=DockIconClickChoice(action:action)
   precondition(state.enabled && state.action==action && dock.dockIconClickChoice.wrappedValue.action==action)
   dock.dockIconClickChoice.wrappedValue = .nothing
   precondition(!state.enabled && state.action==action && dock.dockIconClickChoice.wrappedValue == .nothing)
  }
  let owner=AlternateOwner(alternateSwitcherShortcuts:Binding(get:{state.rows},set:{state.rows=$0}))
  let id=state.rows[0].id
  let main=UserKeyBind(keyCode:48,modifierFlags:masks[1],modifierSide:.left)
  precondition(owner.alternateModifierBinding(for:id).wrappedValue==0)
  precondition(state.rows[0].resolvedKeybind(mainKeybind:main)?.modifierSide == .left)
  let combined=masks[0] | masks[1] | masks[3]
  owner.alternateModifierBinding(for:id).wrappedValue=combined
  let explicit=state.rows[0].resolvedKeybind(mainKeybind:main)!
  precondition(explicit.modifierFlags==combined && explicit.modifierSide == .right && explicit.keyCode==0)
  let roundTrip=try JSONDecoder().decode([AlternateSwitcherShortcut].self,from:JSONEncoder().encode(state.rows))
  precondition(roundTrip==state.rows && roundTrip[0].id==id && roundTrip[0].mode == .currentSpaceOnly)
  owner.alternateModifierBinding(for:id).wrappedValue=0
  let inherited=state.rows[0].resolvedKeybind(mainKeybind:main)!
  precondition(inherited.modifierFlags==main.modifierFlags && inherited.modifierSide==main.modifierSide)
  let editingOrder = state.rows.map(\.id)
  let saved = state.rows[0]
  owner.persistentBinding(for:id).wrappedValue = true
  precondition(state.rows[0].persistent && state.rows[0].id == id)
  precondition(state.rows.map(\.id) == editingOrder)
  let resolved = WindowSwitcherShortcutResolver.resolvedAlternateShortcuts(state.rows, mainKeybind:main, previewShortcuts:[])
  precondition(resolved.count == 1 && resolved[0].persistent)
  precondition(resolved[0].keybind.modifierSide == main.modifierSide)
  owner.persistentBinding(for:id).wrappedValue = false
  precondition(state.rows == [saved])
  let earlier = AlternateSwitcherShortcut(keyCode:0, modifierFlags:combined, isConfigured:true)
  let later = AlternateSwitcherShortcut(keyCode:0, modifierFlags:combined, isConfigured:true)
  state.rows = [earlier, later]
  for persistent in [true, false, true] {
   owner.persistentBinding(for:earlier.id).wrappedValue = persistent
   owner.persistentBinding(for:later.id).wrappedValue = !persistent
   precondition(state.rows.map(\.id) == [earlier.id, later.id])
   let active = WindowSwitcherShortcutResolver.resolvedAlternateShortcuts(state.rows, mainKeybind:main, previewShortcuts:[])
   precondition(active.map(\.id) == [earlier.id], "Earlier visible duplicate must win regardless of Persistent")
   precondition(WindowSwitcherShortcutResolver.alternateConflict(at:1,shortcuts:state.rows,mainKeybind:main,previewShortcuts:[]) == .duplicate)
  }
  let pending = AlternateSwitcherShortcut(isPending:true)
  state.rows = [pending]
  owner.persistentBinding(for:pending.id).wrappedValue = true
  owner.doubleTapBinding(for:pending.id).wrappedValue = true
  precondition(!state.rows[0].isPending && state.rows[0].usesDoubleTap)
  owner.doubleTapBinding(for:pending.id).wrappedValue = false
  precondition(state.rows.count == 1 && state.rows[0].id == pending.id && state.rows[0].isPending && !owner.canAddAlternateShortcut)
  precondition(state.rows[0].resolvedKeybind(mainKeybind:main) == nil)
  var double = saved
  double.usesDoubleTap = true; double.doubleTapKey = .control; double.doubleTapSide = .right
  state.rows = [double]
  owner.persistentBinding(for:id).wrappedValue = true
  owner.persistentBinding(for:id).wrappedValue = false
  precondition(state.rows == [double])
  let encoded = try JSONEncoder().encode(state.rows)
  let decodedRows = try JSONDecoder().decode([AlternateSwitcherShortcut].self,from:encoded)
  precondition(decodedRows == state.rows)
  var upstream = try JSONSerialization.jsonObject(with:JSONEncoder().encode(saved)) as! [String:Any]
  upstream.removeValue(forKey:"persistent")
  let upstreamRow = try JSONDecoder().decode(AlternateSwitcherShortcut.self, from:JSONSerialization.data(withJSONObject:upstream))
  precondition(!upstreamRow.persistent && upstreamRow.id == saved.id)
var legacy = try JSONSerialization.jsonObject(with:JSONEncoder().encode(saved)) as! [String:Any]
legacy["noHighlight"] = true
let legacyRow = try JSONDecoder().decode(AlternateSwitcherShortcut.self, from:JSONSerialization.data(withJSONObject:legacy))
precondition(legacyRow == saved, "Obsolete row metadata must not change saved shortcut bindings")
let rewritten = try JSONSerialization.jsonObject(with:JSONEncoder().encode(legacyRow)) as! [String:Any]
precondition(rewritten["noHighlight"] == nil)

  print("PASS one-store shortcut editing: stable ID/order, Persistent-independent precedence, unfinished-row visibility, pending protection, key zero, inherited sides and upstream metadata defaults")
let recorder=Recorder()
func key(_ code:UInt16,_ flags:NSEvent.ModifierFlags = []) -> NSEvent {
 NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)!
}
let recordedBefore=recorder.parent.currentKeybind
recorder.handleKeyEvent(key(UInt16(kVK_Escape),.capsLock))
precondition(!recorder.parent.isRecording && recorder.parent.currentKeybind == recordedBefore)
recorder.parent.isRecording=true
recorder.handleKeyEvent(key(UInt16(kVK_Escape),[.capsLock,.numericPad]))
precondition(!recorder.parent.isRecording && recorder.parent.currentKeybind == recordedBefore)
recorder.parent.isRecording=true
recorder.handleKeyEvent(key(0,.option))
precondition(!recorder.parent.isRecording && recorder.parent.currentKeybind?.keyCode == 0)
func modifierEvent(_ key:UInt16,_ flags:CGEventFlags,_ seconds:Double) -> CGEvent {
 let event=CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:true)!
 event.type = .flagsChanged; event.flags=flags; event.timestamp=UInt64(seconds*1_000_000_000)
 return event
}
let matcher=ModifierMatcher()
var exactCases=0
let modifiers=ShortcutModifierKey.allCases
for savedBits in 0..<16 {
 let required=modifiers.enumerated().reduce(0) { $0 | ((savedBits & (1 << $1.offset)) == 0 ? 0 : $1.element.modifierFlags) }
 for eventBits in 0..<16 {
  let held=modifiers.enumerated().filter { (eventBits & (1 << $0.offset)) != 0 }.map(\.element)
  let flags=CGEventFlags(rawValue:UInt64(held.reduce(0) { $0 | $1.modifierFlags }))
  for side in ModifierKeySide.allCases {
   let binding=UserKeyBind(keyCode:0,modifierFlags:required,modifierSide:side)
   matcher.pressedModifierKeyCodes=Set(held.map { side == .right ? $0.keyCodes.right : $0.keyCodes.left })
   let expected=required == Int(flags.rawValue)
   precondition(matcher.modifierFlagsMatch(binding,flags:flags) == expected)
   precondition(matcher.modifierFlagsMatch(binding,flags:flags.union([.maskAlphaShift,.maskNumericPad]),allowBackwardModifier:false) == expected)
   exactCases += 2
   if expected && side != .either {
    for member in held {
     let selected=side == .right ? member.keyCodes.right : member.keyCodes.left
     let opposite=side == .right ? member.keyCodes.left : member.keyCodes.right
     matcher.pressedModifierKeyCodes.remove(selected); matcher.pressedModifierKeyCodes.insert(opposite)
     precondition(!matcher.modifierFlagsMatch(binding,flags:flags,allowBackwardModifier:false), "Every selected modifier must honor its chosen side")
     matcher.pressedModifierKeyCodes.insert(selected); matcher.pressedModifierKeyCodes.remove(opposite)
     exactCases += 1
    }
   }
  }
 }
}
let opt=Int(CGEventFlags.maskAlternate.rawValue)
let optShift=opt | Int(CGEventFlags.maskShift.rawValue)
let baseRow=AlternateSwitcherShortcut(keyCode:0,modifierFlags:opt,isConfigured:true)
let shiftedRow=AlternateSwitcherShortcut(keyCode:0,modifierFlags:optShift,isConfigured:true)
let rows=[baseRow, shiftedRow]
let resolvedRows=WindowSwitcherShortcutResolver.resolvedAlternateShortcuts(rows,mainKeybind:main,previewShortcuts:[])
precondition(resolvedRows.count == 2, "Explicit Shift and non-Shift alternates are distinct")
matcher.pressedModifierKeyCodes=[UInt16(kVK_Option),UInt16(kVK_Shift)]
matcher.switcherSessionActive=false
precondition(matcher.resolveAlternateShortcut(in:Array(resolvedRows.prefix(1)),keyCode:0,flags:[.maskAlternate,.maskShift]) == nil)
precondition(matcher.resolveAlternateShortcut(in:resolvedRows,keyCode:0,flags:[.maskAlternate,.maskShift])?.id == shiftedRow.id)
precondition(matcher.resolveAlternateShortcut(in:resolvedRows,keyCode:1,flags:.maskAlternate) == nil)
matcher.switcherSessionActive=true; matcher.activeSessionKeybind=resolvedRows[0].keybind
precondition(matcher.resolveAlternateShortcut(in:Array(resolvedRows.prefix(1)),keyCode:0,flags:[.maskAlternate,.maskShift])?.id == baseRow.id)
precondition(matcher.resolveAlternateShortcut(in:resolvedRows,keyCode:0,flags:[.maskAlternate,.maskShift])?.id == shiftedRow.id, "Explicit bindings take precedence over in-session reverse cycling")
let persistentRow=ResolvedAlternateSwitcherShortcut(id:baseRow.id,keybind:resolvedRows[0].keybind,mode:baseRow.mode,persistent:true,quickSwitch:false)
precondition(matcher.resolveAlternateShortcut(in:[persistentRow],keyCode:0,flags:[.maskAlternate,.maskShift]) == nil)
matcher.switcherSessionActive=false
Defaults.backward=UInt16(kVK_Control)
matcher.pressedModifierKeyCodes=[UInt16(kVK_Option),UInt16(kVK_Control)]
precondition(matcher.resolveAlternateShortcut(in:Array(resolvedRows.prefix(1)),keyCode:0,flags:[.maskAlternate,.maskControl]) == nil)
let requiredCombo=UserKeyBind(keyCode:0,modifierFlags:opt | Int(CGEventFlags.maskControl.rawValue),modifierSide:.left)
let released=matcher.updateModifierStatesFromFlags(event:modifierEvent(UInt16(kVK_Control),.maskAlternate,10),keyBoardShortcutSaved:requiredCombo)
precondition(!released.currentSwitcherModifierIsPressed, "A required modifier cannot become optional because it is also the backward key")
Defaults.backward=UInt16(kVK_RightOption)
matcher.pressedModifierKeyCodes=[UInt16(kVK_Option),UInt16(kVK_RightOption),UInt16(kVK_Control)]
precondition(matcher.canUseBackwardModifier(.maskAlternate,with:requiredCombo))
precondition(matcher.backwardModifierIsPressed(flags:[.maskAlternate,.maskControl],initializer:requiredCombo))
Defaults.backward=56
let cmdRow=AlternateSwitcherShortcut(keyCode:48,modifierFlags:Int(CGEventFlags.maskCommand.rawValue),persistent:true,isConfigured:true)
Defaults.alternateRows=[cmdRow]
matcher.pressedModifierKeyCodes=[UInt16(kVK_Command)]
precondition(matcher.isCmdTabWindowSwitcherKeybind(keyCode:48,flags:.maskCommand), "Persistent Cmd+Tab alternates must route to their executor")
matcher.pressedModifierKeyCodes.insert(UInt16(kVK_Shift))
precondition(!matcher.isCmdTabWindowSwitcherKeybind(keyCode:48,flags:[.maskCommand,.maskShift]))
let reads=matcher.shortcutReads
Defaults.switcherEnabled=false
precondition(!matcher.isCmdTabWindowSwitcherKeybind(keyCode:48,flags:.maskCommand) && matcher.shortcutReads == reads)
Defaults.switcherEnabled=true
Defaults.primary=UserKeyBind(keyCode:48,modifierFlags:Int(CGEventFlags.maskCommand.rawValue))
precondition(matcher.isCmdTabWindowSwitcherKeybind(keyCode:48,flags:[.maskCommand,.maskShift]), "Primary reverse cycling remains available")
Defaults.primary=main
let upstreamMatcher=UpstreamMatcher()
precondition(upstreamMatcher.modifierFlagsMatch(opt,flags:[.maskAlternate,.maskShift]))
precondition(upstreamMatcher.modifierFlagsMatch(optShift,flags:.maskAlternate))
precondition(!matcher.modifierFlagsMatch(UserKeyBind(keyCode:0,modifierFlags:opt),flags:[.maskAlternate,.maskShift],allowBackwardModifier:false))
precondition(!matcher.modifierFlagsMatch(UserKeyBind(keyCode:0,modifierFlags:optShift),flags:.maskAlternate,allowBackwardModifier:false))
print("PASS production modifier matching: \(exactCases) exact/side/caps cases, explicit Shift bindings, active-only reverse, required-modifier release, persistent Cmd+Tab routing and disabled-path gating; upstream Shift omission reproduced without posting events")
var quick=AlternateSwitcherShortcut(keyCode:0,modifierFlags:combined,persistent:true,quickSwitch:true,isConfigured:true)
let quickResolved=WindowSwitcherShortcutResolver.resolvedAlternateShortcuts([quick],mainKeybind:main,previewShortcuts:[])
precondition(quickResolved.count == 1 && quickResolved[0].quickSwitch && quickResolved[0].persistent)
precondition(WindowSwitcherShortcutResolver.alternateConflict(at:1,shortcuts:[quick,quick],mainKeybind:main,previewShortcuts:[]) == .duplicate)
matcher.switcherSessionActive=true; matcher.activeSessionKeybind=quickResolved[0].keybind
matcher.pressedModifierKeyCodes=[UInt16(kVK_Control),UInt16(kVK_Option),UInt16(kVK_Shift)]
precondition(matcher.resolveAlternateShortcut(in:quickResolved,keyCode:0,flags:[.maskControl,.maskAlternate,.maskShift])?.quickSwitch == true)
let dispatch=QuickDispatchProbe()
let quickEvent=modifierEvent(0,[.maskControl,.maskAlternate,.maskShift],11)
let accepted=dispatch.dispatch(quickResolved[0],event:quickEvent)
precondition(accepted.shouldConsume && accepted.actionTask != nil)
await accepted.actionTask?()
precondition(dispatch.calls == [quick.mode])
quickEvent.setIntegerValueField(.keyboardEventAutorepeat,value:1)
let repeated=dispatch.dispatch(quickResolved[0],event:quickEvent)
precondition(repeated.shouldConsume && repeated.actionTask == nil && dispatch.calls.count == 1)
quickEvent.setIntegerValueField(.keyboardEventAutorepeat,value:0)
WindowUtil.ignoresKeybind=true
precondition(!dispatch.dispatch(quickResolved[0],event:quickEvent).shouldConsume)
WindowUtil.ignoresKeybind=false
Defaults.switcherEnabled=false
precondition(!dispatch.dispatch(quickResolved[0],event:quickEvent).shouldConsume)
Defaults.switcherEnabled=true
quick.quickSwitch=false
let ordinary=WindowSwitcherShortcutResolver.resolvedAlternateShortcuts([quick],mainKeybind:main,previewShortcuts:[])[0]
precondition(!dispatch.dispatch(ordinary,event:quickEvent).shouldConsume)
precondition(ordinary.persistent, "Turning Quick Switch off retains disabled option values")
print("PASS Quick Switch production dispatch: shared scopes/conflicts, exactly one executor, repeat suppression, disabled/ignored refusal, no ordinary/persistent presentation and retained option values")
var doubleCases=0
for modifier in ShortcutModifierKey.allCases {
 for side in ModifierKeySide.allCases {
  let row=AlternateSwitcherShortcut(usesDoubleTap:true,doubleTapKey:modifier,doubleTapSide:side)
  Defaults.alternateRows=[row]
  let code=side == .right ? modifier.keyCodes.right : modifier.keyCodes.left
  let flags=CGEventFlags(rawValue:UInt64(modifier.modifierFlags))
  let detector=Detector()
  precondition(detector.handleModifierDoubleTap(event:modifierEvent(code,flags,1)) == nil)
  precondition(detector.handleModifierDoubleTap(event:modifierEvent(code,[],1.01)) == nil)
  let result=detector.handleModifierDoubleTap(event:modifierEvent(code,flags,1.02))
  guard case .openHeldSwitcher? = result else { preconditionFailure("Expected held double-tap: \(modifier) \(side), interval=\(NSEvent.doubleClickInterval), keys=\(detector.modifierDoubleTapState.pressedKeyCodes), timestamps=\(detector.modifierDoubleTapState.firstPressTimestampByKeyCode)") }
  for extra in ShortcutModifierKey.allCases where extra != modifier {
   let rejected=Detector()
   let extraFlag=CGEventFlags(rawValue:UInt64(extra.modifierFlags))
   precondition(rejected.handleModifierDoubleTap(event:modifierEvent(code,flags.union(extraFlag),2)) == nil)
   precondition(rejected.handleModifierDoubleTap(event:modifierEvent(code,extraFlag,2.01)) == nil)
   precondition(rejected.handleModifierDoubleTap(event:modifierEvent(code,flags.union(extraFlag),2.02)) == nil)
   precondition(rejected.handleModifierDoubleTap(event:modifierEvent(code,extraFlag,2.03)) == nil)
   doubleCases += 1
  }
  if side != .either {
   let wrong=side == .left ? modifier.keyCodes.right : modifier.keyCodes.left
   let rejected=Detector()
   precondition(rejected.handleModifierDoubleTap(event:modifierEvent(wrong,flags,3)) == nil)
   precondition(rejected.handleModifierDoubleTap(event:modifierEvent(wrong,[],3.01)) == nil)
   precondition(rejected.handleModifierDoubleTap(event:modifierEvent(wrong,flags,3.02)) == nil)
  }
  Defaults.alternateRows[0].persistent=true
  let persistent=Detector()
  let caps=flags.union(.maskAlphaShift)
  precondition(persistent.handleModifierDoubleTap(event:modifierEvent(code,caps,4)) == nil)
  precondition(persistent.handleModifierDoubleTap(event:modifierEvent(code,.maskAlphaShift,4.01)) == nil)
  guard case .openPersistentSwitcher? = persistent.handleModifierDoubleTap(event:modifierEvent(code,caps,4.02)) else { preconditionFailure("Expected persistent double-tap") }
Defaults.alternateRows[0].quickSwitch=true
let quickDouble=Detector()
precondition(quickDouble.handleModifierDoubleTap(event:modifierEvent(code,flags,4.1)) == nil)
precondition(quickDouble.handleModifierDoubleTap(event:modifierEvent(code,[],4.11)) == nil)
guard case .switchToLastFocusedWindow? = quickDouble.handleModifierDoubleTap(event:modifierEvent(code,flags,4.12)) else { preconditionFailure("Quick Switch must retain double-tap without opening the switcher") }
Defaults.alternateRows[0].quickSwitch=false
  let interrupted=Detector()
  precondition(interrupted.handleModifierDoubleTap(event:modifierEvent(code,flags,5)) == nil)
  precondition(interrupted.handleModifierDoubleTap(event:modifierEvent(code,[],5.01)) == nil)
  interrupted.modifierDoubleTapState.resetSequence()
  precondition(interrupted.handleModifierDoubleTap(event:modifierEvent(code,flags,5.02)) == nil)
  let expired=Detector()
  precondition(expired.handleModifierDoubleTap(event:modifierEvent(code,flags,6)) == nil)
  precondition(expired.handleModifierDoubleTap(event:modifierEvent(code,[],6.01)) == nil)
  precondition(expired.handleModifierDoubleTap(event:modifierEvent(code,flags,6.02+NSEvent.doubleClickInterval)) == nil)
 }
}
print("PASS production recorder Caps Lock cancellation/key zero; double-tap held/persistent, side checks, Caps Lock, interruption/expiry and \(doubleCases) preheld-extra-modifier refusals; synthetic events only")
  final class LimitsState { var minimum = 0; var maximum = 0 }
  let limitsState = LimitsState()
  let reset = IconResetOwner(spacesBarMinimumIcons:Binding(get:{limitsState.minimum},set:{limitsState.minimum=$0}),spacesBarMaximumIcons:Binding(get:{limitsState.maximum},set:{limitsState.maximum=$0}))
  var resetCases = 0
  for minimum in 0...10 {
   for maximum in minimum...20 {
    limitsState.minimum = minimum; limitsState.maximum = maximum
    reset.resetIconLimits()
    precondition(limitsState.minimum == 2 && limitsState.maximum == 6)
    resetCases += 1
   }
  }
  print("PASS legacy shortcut metadata decoding and \(resetCases) coupled icon-range resets through production bindings")
  let before=state.rows
  owner.alternateModifierBinding(for:UUID()).wrappedValue=combined
  precondition(state.rows==before)
  print("PASS production Settings bindings: 128 modifier mutations, nonempty primary, Shift/combinations, inherited modifier+side, zero key, missing IDs, stable JSON/UUID/mode, and all Dock click choices including cycling")
 }
}
SWIFT
Dir.mktmpdir('dockfork-settings-bindings-') do |dir|
  path = File.join(dir, 'checks.swift')
  File.write(path, source)
  abort 'Settings binding compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', path, '-o', File.join(dir, 'checks'))
  abort 'Settings binding checks failed' unless system(File.join(dir, 'checks'))
end

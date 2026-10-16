#!/usr/bin/env ruby
require 'json'

root = File.expand_path('../..', __dir__)
path = ARGV.fetch(0, File.join(root, 'fork/presets/DockFork-Showcase.json'))
preset = JSON.parse(File.read(path))
abort 'Unexpected backup envelope' unless preset.keys.sort == %w[app appVersion formatVersion settings]
abort 'Unsupported backup format' unless preset['app'] == 'DockDoor' && preset['formatVersion'] == 1
version = JSON.parse(File.read(File.join(root, 'fork/version.json'))).fetch('forkVersion')
abort 'Preset version differs from planned release' unless preset['appVersion'] == version
settings = preset.fetch('settings')
abort 'Settings must be a dictionary' unless settings.is_a?(Hash)
known = File.read(File.join(root, 'DockDoor/consts.swift')).scan(/Key(?:<[^\n]*?>)?\(\s*"([^"\n]+)"/).flatten
unknown = settings.keys - known
abort "Unrecognized preference keys: #{unknown.join(', ')}" unless unknown.empty?
private_keys = settings.keys.grep(/\A(?:NS|Apple|SU)|bookmark|credential|token|permission|windowOrder(?!ing)|windowHistory|folderPaths|reopenSettings/i)
abort "Private/system state: #{private_keys.join(', ')}" unless private_keys.empty?
abort 'Debug logging must be disabled' unless settings['debugMode'] == false

ids = []
row_keys = %w[id isConfigured isPending keyCode mode modifierFlags modifierSide doubleTapKey doubleTapSide usesDoubleTap action]
row_lists = %w[alternateSwitcherShortcuts persistentSwitcherShortcuts lastFocusedWindowShortcuts cmdShortcuts]
settings.each do |key, value|
  next unless row_lists.include?(key)
  abort "Invalid shortcut list: #{key}" unless value.is_a?(Array)
  value.each do |encoded|
    row = JSON.parse(encoded)
    abort "Unexpected shortcut fields: #{key}" unless row.is_a?(Hash) && (row.keys - row_keys).empty?
    id = row.fetch('id')
    abort 'Shortcut IDs must be generic and unique' unless id.match?(/\A00000000-0000-4000-8000-\d{12}\z/) && !ids.include?(id)
    abort 'Pending shortcuts must not be published' if row['isPending'] == true
    ids << id
  end
end

def inspect_value(value)
  case value
  when Hash
    value.each { |key, child| inspect_value(key); inspect_value(child) }
  when Array
    value.each { |child| inspect_value(child) }
  when String
    abort 'Possible personal data or opaque payload' if value.match?(%r{/(?:Users|home|private|Volumes)/|file:|https?://|[\w.+-]+@[\w.-]+|-----BEGIN|\b(?:gh[pousr]_|github_pat_|sk-)[A-Za-z0-9]|[A-Za-z0-9+/]{80,}={0,2}}i)
    inspect_value(JSON.parse(value)) if value.start_with?('{', '[')
  when TrueClass, FalseClass, Integer, Float, NilClass
  else
    abort 'Unsupported preference value'
  end
end

inspect_value(preset)
puts "PASS #{settings.size} known preferences and #{ids.size} shortcut rows: envelope, generic IDs, nested JSON and privacy markers"
puts 'This focused check does not replace manual review of a new export or a packaged-asset privacy audit.'

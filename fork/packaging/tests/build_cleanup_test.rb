#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

script = File.read(File.expand_path('../../package.sh', __dir__))
prune = script[/^prune_old_builds\(\) \{\n.*?^\}/m] or abort 'Missing production cleanup function'
abort 'Cleanup must be opt-in' unless script.include?('clean_old_builds=false') && script.include?('--clean-old-builds) clean_old_builds=true; shift ;;')
abort 'Cleanup must cover all successful exits' unless script.scan(/^\s*if \$clean_old_builds; then prune_old_builds; fi$/).size == 3
dev = script[script.index('    open "$dev_app"')..]
abort 'Development cleanup must follow successful launch' unless dev.index('prune_old_builds') < dev.index('exit 0')
abort 'Build PID must be trap-owned' unless script.include?('rm -f "$destination/.build-pid"') && script.include?('printf \'%s\\n\' "$$" > "$destination/.build-pid"')

def check(value, message)
  abort message unless value
end

Dir.mktmpdir('dockfork cleanup ') do |temporary|
  output = File.join(temporary, 'output with spaces')
  FileUtils.mkdir_p(output)
  commit = 'a' * 40
  make = lambda do |name|
    path = File.join(output, name)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'SOURCE-COMMIT.txt'), "#{commit}\n")
    File.write(File.join(path, 'BUILD-METADATA.json'), JSON.generate('sourceCommit' => commit))
    path
  end
  current = make.call('DockFork-aaaaaaa-working-NEW123')
  old = make.call('DockFork-aaaaaaa-working-OLD123')
  failed = make.call('DockFork-aaaaaaa-working-FAIL12')
  release = make.call('DockFork-aaaaaaa-REL123')
  zipped = make.call('DockFork-aaaaaaa-working-ZIP123')
  File.write(File.join(zipped, 'package.zip'), 'keep')
  manifest = make.call('DockFork-aaaaaaa-working-SHA123')
  File.write(File.join(manifest, 'SHA256SUMS.txt'), 'keep')
  unrelated = make.call('keep my files')
  malformed_name = make.call('DockFork-aaaaaaa-working-manual-not-generated')
  bad_json = make.call('DockFork-aaaaaaa-working-BAD123')
  File.write(File.join(bad_json, 'BUILD-METADATA.json'), 'not JSON')
  wrong_metadata = make.call('DockFork-aaaaaaa-working-META12')
  File.write(File.join(wrong_metadata, 'BUILD-METADATA.json'), JSON.generate('sourceCommit' => 'b' * 40))
  wrong_prefix = make.call('DockFork-bbbbbbb-working-HASH12')
  missing_record = make.call('DockFork-aaaaaaa-working-MISS12')
  File.delete(File.join(missing_record, 'SOURCE-COMMIT.txt'))
  active = make.call('DockFork-aaaaaaa-working-LIVE12')
  File.write(File.join(active, '.build-pid'), Process.pid.to_s)
  invalid_pid = make.call('DockFork-aaaaaaa-working-PID123')
  File.write(File.join(invalid_pid, '.build-pid'), 'not a pid')
  oversized_pid = make.call('DockFork-aaaaaaa-working-HUGE12')
  File.write(File.join(oversized_pid, '.build-pid'), '9' * 100)
  dead = make.call('DockFork-aaaaaaa-working-DEAD12')
  pid = Process.spawn(RbConfig.ruby, '-e', 'exit')
  Process.wait(pid)
  File.write(File.join(dead, '.build-pid'), pid.to_s)
  dev_app = File.join(output, 'dev', 'DockFork.app')
  FileUtils.mkdir_p(dev_app)
  outside = File.join(temporary, 'outside')
  FileUtils.mkdir_p(outside)
  sentinel = File.join(outside, 'keep.txt')
  File.write(sentinel, 'keep')
  linked_directory = File.join(output, 'DockFork-aaaaaaa-working-LINK12')
  File.symlink(outside, linked_directory)
  File.symlink(outside, File.join(old, 'external'))
  linked_record = make.call('DockFork-aaaaaaa-working-LINK34')
  File.delete(File.join(linked_record, 'SOURCE-COMMIT.txt'))
  File.symlink(File.join(current, 'SOURCE-COMMIT.txt'), File.join(linked_record, 'SOURCE-COMMIT.txt'))
  same_name_file = File.join(output, 'DockFork-aaaaaaa-working-FILE12')
  File.write(same_name_file, 'keep')

  wrapper = prune + <<~'SH'

    output="$1"
    destination="$2"
    if "$3"; then prune_old_builds; fi
  SH
  run = lambda { |enabled, destination = current|
    Open3.capture2e('bash', '-euo', 'pipefail', '-c', wrapper, 'cleanup-test', output, destination, enabled.to_s)
  }
  out, status = run.call(false)
  check(status.success? && File.directory?(old), "Disabled cleanup changed outputs: #{out}")
  out, status = run.call(true, outside)
  check(!status.success? && File.directory?(old), 'Cleanup accepted a current build outside its output root')
  preserved = [current, release, zipped, manifest, unrelated, malformed_name, bad_json,
               wrong_metadata, wrong_prefix, missing_record, active, invalid_pid, oversized_pid, dev_app,
               linked_directory, linked_record, same_name_file, sentinel]
  out, status = run.call(true)
  check(status.success?, out)
  check([old, failed, dead].none? { |path| File.exist?(path) }, 'Recognized stale builds were not removed')
  check(preserved.all? { |path| File.exist?(path) }, 'Cleanup removed a protected or unrelated entry')
  check(File.read(sentinel) == 'keep', 'Cleanup followed a nested symlink')
  out, status = run.call(true)
  check(status.success? && !out.include?('Removed old local build:'), 'Repeated cleanup was not idempotent')
end
puts 'PASS production build cleanup: opt-in/success gates, stale/failed/dead builds, current/active builds, releases, installed app, metadata checks, symlinks, output paths and idempotence'

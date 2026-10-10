require 'json'
require 'open3'
require 'tmpdir'

validator = File.expand_path('../version_metadata.rb', __dir__)
checks = 0

Dir.mktmpdir('dockfork-version-tests-') do |root|
  run = lambda do |*args|
    stdout, stderr, status = Open3.capture3(*args)
    raise "Command failed: #{stderr}" unless status.success?
    stdout.strip
  end
  git = ->(*args) { run.call('git', '-C', root, *args) }
  git.call('init', '--quiet', '--object-format=sha1')
  git.call('config', 'user.name', 'Version Test')
  git.call('config', 'user.email', 'test@example.invalid')
  git.call('config', 'commit.gpgsign', 'false')
  git.call('config', 'tag.gpgsign', 'false')
  git.call('config', 'core.hooksPath', '/dev/null')
  git.call('commit', '--quiet', '--allow-empty', '-m', 'Upstream release')
  release = git.call('rev-parse', 'HEAD')
  git.call('tag', '1.0.0')
  git.call('commit', '--quiet', '--allow-empty', '-m', 'Later upstream changes')
  base = git.call('rev-parse', 'HEAD')
  git.call('commit', '--quiet', '--allow-empty', '-m', 'Fork changes')
  source = git.call('rev-parse', 'HEAD')
  metadata = {
    'forkVersion' => '0.1.0', 'upstreamRelease' => '1.0.0',
    'upstreamReleaseCommit' => release, 'upstreamCommit' => base
  }
  input = File.join(root, 'version.json')
  output = File.join(root, 'result.json')
  check = lambda do |record, expected_success, expected_message = nil, override = ''|
    File.write(input, record.is_a?(String) ? record : JSON.generate(record))
    _, stderr, status = Open3.capture3('/usr/bin/ruby', validator, root, source, override, input, output)
    raise "Unexpected validation result: #{stderr}" unless status.success? == expected_success
    if expected_message && !stderr.include?(expected_message)
      raise "Missing error #{expected_message.inspect}: #{stderr}"
    end
    checks += 1
    status.success? ? JSON.parse(File.read(output)) : nil
  end

  result = check.call(metadata, true)
  raise 'Default version or base was lost' unless result.fetch('forkVersion') == '0.1.0' && result.fetch('upstreamCommit') == base
  raise 'Missing later-upstream label' unless result.fetch('upstreamIncludesChanges') && result.fetch('sourceCommit') == source
  result = check.call(metadata, true, nil, '0.2.0')
  raise 'Version override failed' unless result.fetch('forkVersion') == '0.2.0'
  raise 'Override changed the input' unless JSON.parse(File.read(input)) == metadata
  result = check.call(metadata.merge('upstreamCommit' => release), true)
  raise 'Exact release incorrectly marked as later changes' if result.fetch('upstreamIncludesChanges')

  check.call('{', false, 'Invalid version record')
  check.call(metadata.merge('unexpected' => true), false, 'Unexpected version record fields')
  check.call(metadata.merge('forkVersion' => '01.0.0'), false, 'Invalid forkVersion')
  check.call(metadata.merge('forkVersion' => 1), false, 'Invalid forkVersion')
  check.call(metadata, false, 'Invalid version override', '0.2.0; echo unsafe')
  check.call(metadata.merge('upstreamCommit' => '0' * 40), false, 'Git validation failed')
  check.call(metadata.merge('upstreamCommit' => base.upcase), false, 'full lowercase SHA-1')
  check.call(metadata.merge('upstreamReleaseCommit' => source), false, 'release is not included')
  check.call(metadata.merge('upstreamReleaseCommit' => base), false, 'does not match its local tag')
  check.call(metadata.merge('upstreamRelease' => '1.9.0'), false, 'Missing upstream release tag')
  orphan = git.call('commit-tree', "#{source}^{tree}", '-m', 'Unmerged history')
  check.call(metadata.merge('upstreamCommit' => orphan, 'upstreamReleaseCommit' => orphan), false, 'base is not included')

  git.call('tag', '1.1.0', base)
  check.call(metadata, false, 'included release 1.1.0 is newer')
  git.call('tag', '-d', '1.1.0')
  git.call('remote', 'add', 'upstream', 'https://github.com/ejbills/DockDoor.git')
  git.call('update-ref', 'refs/remotes/upstream/main', base)
  check.call(metadata, true)
  check.call(metadata.merge('upstreamCommit' => release), false, 'does not match the merged remote history')
  git.call('update-ref', 'refs/remotes/upstream/main', source)
  check.call(metadata, false, 'does not match the merged remote history')
  unmerged = git.call('commit-tree', "#{source}^{tree}", '-p', base, '-m', 'Unmerged upstream changes')
  git.call('update-ref', 'refs/remotes/upstream/main', unmerged)
  git.call('tag', '2.0.0', unmerged)
  check.call(metadata, true)
end

puts "#{checks} version metadata cases passed"

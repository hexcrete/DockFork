require 'json'
require 'open3'

root, source_commit, override, input, output = ARGV
abort 'Expected repository, source commit, version override, input and output paths.' unless ARGV.size == 5

def git(root, *args)
  stdout, stderr, status = Open3.capture3('git', '-C', root, *args)
  abort "Git validation failed: #{stderr.strip}" unless status.success?
  stdout.strip
end

def ancestor?(root, earlier, later)
  _, stderr, status = Open3.capture3('git', '-C', root, 'merge-base', '--is-ancestor', earlier, later)
  abort "Ancestry check failed: #{stderr.strip}" unless [0, 1].include?(status.exitstatus)
  status.success?
end

begin
  metadata = JSON.parse(File.read(input))
rescue JSON::ParserError, SystemCallError => error
  abort "Invalid version record: #{error.message}"
end

keys = %w[forkVersion upstreamRelease upstreamReleaseCommit upstreamCommit]
abort 'Unexpected version record fields.' unless metadata.is_a?(Hash) && metadata.keys.sort == keys.sort
version_pattern = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
%w[forkVersion upstreamRelease].each do |key|
  abort "Invalid #{key}: expected X.Y.Z." unless metadata[key].is_a?(String) && metadata[key].match?(version_pattern)
end
abort 'Invalid version override: expected X.Y.Z.' unless override.empty? || override.match?(version_pattern)

release_commit = metadata.fetch('upstreamReleaseCommit')
base = metadata.fetch('upstreamCommit')
[source_commit, release_commit, base].each do |commit|
  abort 'Commit identifiers must be full lowercase SHA-1 hashes.' unless commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/)
  abort "Not a commit: #{commit}" unless git(root, 'cat-file', '-t', commit) == 'commit'
end
abort 'Recorded upstream release is not included in its base commit.' unless ancestor?(root, release_commit, base)
abort 'Recorded upstream base is not included in the build.' unless ancestor?(root, base, source_commit)

# Use only included stable release tags; an unmerged new release must not change the label.
tags = git(root, 'tag', '--merged', base).lines.map(&:strip).select { |tag| tag.match?(version_pattern) }
latest_tag = tags.max_by { |tag| tag.split('.').map(&:to_i) }
if latest_tag && (latest_tag.split('.').map(&:to_i) <=> metadata.fetch('upstreamRelease').split('.').map(&:to_i)) == 1
  abort "Version record is stale: included release #{latest_tag} is newer. Update fork/version.json."
end
release_tag = metadata.fetch('upstreamRelease')
abort "Missing upstream release tag #{release_tag}. Fetch that tag from ejbills/DockDoor before packaging." unless tags.include?(release_tag)
tagged_commit = git(root, 'rev-parse', "refs/tags/#{release_tag}^{commit}")
abort 'Recorded release commit does not match its local tag.' unless tagged_commit == release_commit

# A normal fork clone may lack an upstream remote; pinned ancestry remains verifiable offline.
upstream_urls = %w[https://github.com/ejbills/DockDoor http://github.com/ejbills/DockDoor git@github.com:ejbills/DockDoor ssh://git@github.com/ejbills/DockDoor]
git(root, 'remote').lines.map(&:strip).each do |remote|
  url = git(root, 'remote', 'get-url', remote).sub(/\.git\z/, '')
  next unless upstream_urls.include?(url)
  ref = "refs/remotes/#{remote}/main"
  _, _, status = Open3.capture3('git', '-C', root, 'show-ref', '--verify', '--quiet', ref)
  next unless status.success?
  merged_bases = git(root, 'merge-base', '--all', source_commit, ref).lines.map(&:strip)
  abort 'Upstream record does not match the merged remote history. Update fork/version.json.' unless merged_bases == [base]
end

metadata['forkVersion'] = override unless override.empty?
metadata['sourceCommit'] = source_commit
metadata['upstreamIncludesChanges'] = base != release_commit
File.write(output, JSON.pretty_generate(metadata) + "\n")

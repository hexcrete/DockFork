#!/usr/bin/env ruby
require 'open3'

script=File.read(File.expand_path('../../package.sh',__dir__))
defaults=script[/^version=""\n.*?^configuration=Release$/m] or abort 'Missing defaults'
usage=script[/^usage\(\) \{\n.*?^\}/m] or abort 'Missing usage'
parser=script[/^while \[\[ \$# -gt 0 \]\]; do\n.*?(?=^commit=\$)/m] or abort 'Missing option parser'
builder=script[/^build_args=\(\n.*?(?=^printf 'Building DockFork)/m] or abort 'Missing build arguments'
marker=script[/^if \$development; then\n    \/usr\/libexec\/PlistBuddy -c "Add :DockForkOptimizedDevelopment bool \$optimized" "\$plist"\nfi$/m]
abort 'Optimized marker must be development-only' unless marker
abort 'Normal build command changed' unless script.include?('configuration=Debug') && script.include?('--dev) development=true; shift ;;')
abort 'Optimized mode must still exit before ZIP creation' unless script.index('Local certificate-signed development app launched:') < script.index('archive="DockFork-')

# Execute the production parser and argument builder; never invoke signing/build/install tools.
harness=defaults+"\n"+usage+"\n"+<<~'SH'+parser+<<~'SH'+builder+<<~'SH'
uname() { printf 'Darwin\n'; }
security() { printf '1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: Fixture"\n'; }
SH
source_dir='/tmp/source with spaces'
work='/tmp/build with spaces'
SH
printf 'CONFIG=%s\nOPT=%s\nDEV=%s\nTRACKED=%s\nCLEAN=%s\n' "$configuration" "$optimized" "$development" "$include_working_tree" "$clean_old_builds"
printf 'ARG:%s\n' "${build_args[@]}"
SH
cases=[
 [[], 'Release',false,false,false],
 [['--dev'], 'Debug',false,true,false],
 [['--dev','--optimized','--clean-old-builds'], 'Debug',true,true,true],
 [['--optimized','--dev'], 'Debug',true,true,false],
 [['--dev','--optimized','--prepare-only'], 'Debug',true,true,false],
 [['--dev','--optimized','--signing-identity','A'*40], 'Debug',true,true,false]
]
cases.each do |args,configuration,optimized,development,clean|
 out,status=Open3.capture2e('bash','-euo','pipefail','-c',harness,'options-test',*args)
 abort "Option case failed #{args}: #{out}" unless status.success?
 expected=["CONFIG=#{configuration}","OPT=#{optimized}","DEV=#{development}","TRACKED=#{development}","CLEAN=#{clean}"]
 abort "Wrong mode #{args}: #{out}" unless expected.all?{|line|out.lines.map(&:strip).include?(line)}
 argv=out.lines.grep(/^ARG:/).map{|l|l.delete_prefix('ARG:').strip}
 abort 'Source/build path argument splitting' unless argv.include?('/tmp/source with spaces/DockDoor.xcodeproj') && argv.include?('/tmp/build with spaces/DerivedData')
 abort 'Unexpected optimization override' unless argv.count('SWIFT_OPTIMIZATION_LEVEL=-O')==(optimized ? 1:0)
 abort 'Unexpected coverage override' unless argv.count('ENABLE_CODE_COVERAGE=NO')==(!development || optimized ? 1:0)
 abort 'Identity override changed' unless argv.include?('CODE_SIGNING_ALLOWED=NO') && argv.include?('DEVELOPMENT_TEAM=')
end
[['--optimized'],['--optimized','--include-working-tree'],['--dev','--unknown']].each do |args|
 out,status=Open3.capture2e('bash','-euo','pipefail','-c',harness,'options-test',*args)
 abort "Unsafe options accepted: #{args}" unless status.exitstatus==2 && !out.include?('ARG:')
end
out,status=Open3.capture2e('bash','-euo','pipefail','-c',harness,'options-test','--help')
abort 'Help must explain local-only optimization' unless status.success? && out.include?('--optimized requires --dev') && !out.include?('ARG:')
puts 'PASS production development options: unchanged normal Debug/Release, opt-in -O/no coverage, flag order, explicit certificate, clean/prepare options, path quoting, unsafe-mode refusal, help and local-only marker; no builds/signing/app manipulation'

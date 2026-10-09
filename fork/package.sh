#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
output="$root/fork/dist"
version=""
prepare_only=false
include_working_tree=false

usage() {
    cat <<'EOF'
Usage: ./fork/package.sh [--output DIRECTORY] [--version X.Y.Z] [--prepare-only] [--include-working-tree]

Build committed HEAD as an Apple Silicon, ad-hoc-signed DockFork release.
Release mode performs no account, provisioning, installation, launch or publication operations.
--prepare-only creates the patched source snapshot without building it.
--include-working-tree includes tracked app/source changes for local testing only.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|--version)
            [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
            if [[ "$1" == --output ]]; then output="$2"; else version="$2"; fi
            shift 2
            ;;
        --prepare-only) prepare_only=true; shift ;;
        --include-working-tree) include_working_tree=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ $(uname -s) == Darwin ]] || { echo 'macOS is required.' >&2; exit 1; }
if [[ -n "$version" && ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Version must be X.Y.Z.' >&2
    exit 2
fi
commit=$(git -C "$root" rev-parse HEAD)
short_commit=${commit:0:7}
label="$short_commit"
if $include_working_tree; then label="${short_commit}-working"; fi
mkdir -p "$output"
output=$(cd "$output" && pwd)
destination=$(mktemp -d "$output/DockFork-${label}-XXXXXX")
work=$(mktemp -d "${TMPDIR:-/tmp}/DockFork-package-XXXXXX")
trap 'rm -rf "$work"' EXIT
source_dir="$work/source"
mkdir -p "$source_dir"

# Archive committed sources, never the local Dev project identity or preferences.
git -C "$root" archive "$commit" | tar -xf - -C "$source_dir"
git -C "$root" archive --format=tar.gz --prefix=DockDoor-source/ "$commit" > "$destination/DockFork-${short_commit}-source.tar.gz"
if $include_working_tree; then
    git -C "$root" diff --binary "$commit" -- DockDoor Assets BuildTools DockDoorTests > "$destination/WORKING-TREE.patch"
    if [[ -s "$destination/WORKING-TREE.patch" ]]; then
        git -C "$source_dir" apply --check "$destination/WORKING-TREE.patch"
        git -C "$source_dir" apply "$destination/WORKING-TREE.patch"
    fi
    echo 'Local test build: includes tracked source changes, excludes local project identity and untracked files.'
fi
git -C "$source_dir" apply --check "$root/fork/packaging/DockFork.patch"
git -C "$source_dir" apply "$root/fork/packaging/DockFork.patch"

# Scope identity changes to the app target, not its Swift package dependencies.
/usr/bin/ruby - "$source_dir/DockDoor.xcodeproj/project.pbxproj" "$version" <<'RUBY'
path, version = ARGV
project = File.read(path)
count = 0
project.gsub!(/\t\t[0-9A-F]+ \/\* (?:Debug|Release) \*\/ = \{\n.*?\n\t\t\};/m) do |block|
    next block unless block.include?('INFOPLIST_FILE = DockDoor/Info.plist;')
    count += 1
    replacements = {
        'PRODUCT_NAME' => 'DockFork',
        'PRODUCT_BUNDLE_IDENTIFIER' => 'io.github.hexcrete.DockFork',
        'INFOPLIST_KEY_CFBundleDisplayName' => 'DockFork',
        'INFOPLIST_KEY_NSAppleEventsUsageDescription' => '"DockFork uses AppleEvents to fetch music info from Music and Spotify."',
        'INFOPLIST_KEY_NSCalendarsUsageDescription' => '"DockFork uses EventKit to fetch task info from Calendar."'
    }
    unless version.empty?
        replacements['MARKETING_VERSION'] = version
        replacements['CURRENT_PROJECT_VERSION'] = version
    end
    replacements.each do |key, value|
        pattern = /^(\s*#{Regexp.escape(key)} = )[^\n]+;/
        abort "Unexpected app setting: #{key}" unless block.scan(pattern).size == 1
        block.sub!(pattern) { "#{$1}#{value};" }
    end
    block.sub!("\t\t\t\tPRODUCT_NAME = DockFork;", "\t\t\t\tPRODUCT_NAME = DockFork;\n\t\t\t\tPRODUCT_MODULE_NAME = DockDoor;\n\t\t\t\tEXECUTABLE_NAME = DockFork;\n\t\t\t\tINFOPLIST_KEY_CFBundleName = DockFork;")
    block
end
abort 'Expected exactly two DockDoor app configurations' unless count == 2
File.write(path, project)
RUBY

plist="$source_dir/DockDoor/Info.plist"
for key in SUFeedURL SUPublicEDKey SUEnableDownloaderService SUEnableInstallerLauncherService; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$plist"
done
/usr/libexec/PlistBuddy -c 'Add :SUEnableAutomaticChecks bool false' "$plist"
/usr/libexec/PlistBuddy -c 'Add :SUAllowsAutomaticUpdates bool false' "$plist"
/usr/libexec/PlistBuddy -c 'Add :SUSendProfileInfo bool false' "$plist"
/usr/libexec/PlistBuddy -c 'Add :DockForkDistribution bool true' "$plist"

cp "$root/fork/packaging/DockFork.patch" "$destination/DockFork.patch"
printf '%s\n' "$commit" > "$destination/SOURCE-COMMIT.txt"
shasum -a 256 "$root/fork/packaging/DockFork.patch" | awk '{print $1}' > "$destination/PACKAGING-PATCH-SHA256.txt"

if $prepare_only; then
    mv "$source_dir" "$destination/source"
    printf 'Prepared source only: %s\n' "$destination/source"
    exit 0
fi

os_major=$(sw_vers -productVersion | cut -d. -f1)
xcode_major=$(xcodebuild -version | awk '/^Xcode / {split($2, v, "."); print v[1]}')
[[ "$os_major" -ge 27 && "$xcode_major" -ge 27 ]] || {
    echo 'Building requires macOS 27 and Xcode 27 or later.' >&2
    exit 1
}

build_args=(
    -project "$source_dir/DockDoor.xcodeproj" -scheme DockDoor
    -configuration Release -derivedDataPath "$work/DerivedData"
    -destination 'generic/platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
    ENABLE_HARDENED_RUNTIME=NO
)
printf 'Building Release source %s; log: %s\n' "$label" "$destination/build.log"
if ! xcodebuild "${build_args[@]}" build > "$destination/build.log" 2>&1; then
    tail -n 50 "$destination/build.log" >&2
    exit 1
fi

app="$destination/DockFork.app"
ditto "$work/DerivedData/Build/Products/Release/DockFork.app" "$app"
app_plist="$app/Contents/Info.plist"
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_plist") == io.github.hexcrete.DockFork ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_plist") == DockFork ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :DockForkDistribution' "$app_plist") == true ]]
if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app_plist" >/dev/null 2>&1; then
    echo 'Unsafe package: upstream update feed remains.' >&2
    exit 1
fi
[[ $(lipo -archs "$app/Contents/MacOS/DockFork") == arm64 ]]

# Sign nested code inside-out, including Sparkle's bundled helpers.
while IFS= read -r -d '' file; do
    if /usr/bin/file -b "$file" | grep -q 'Mach-O'; then
        codesign --force --sign - --timestamp=none --options 0 "$file"
    fi
done < <(find "$app/Contents" -type f -print0)
while IFS= read -r -d '' bundle; do
    codesign --force --sign - --timestamp=none --options 0 "$bundle"
done < <(find "$app/Contents" -depth -type d \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' \) -print0)
codesign --force --sign - --timestamp=none --options 0 \
    --entitlements "$root/fork/packaging/DockFork.entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_plist")
archive="DockFork-${app_version}-${label}-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$destination/$archive"
cp "$root/fork/presets/DockFork-Showcase.json" "$destination/DockFork-Showcase.json"
cp "$root/LICENSE" "$destination/LICENSE"
cp "$root/fork/packaging/INSTALL.md" "$destination/INSTALL.md"
(
    cd "$destination"
    shasum -a 256 "$archive" "DockFork-${short_commit}-source.tar.gz" \
        DockFork-Showcase.json DockFork.patch INSTALL.md LICENSE SOURCE-COMMIT.txt \
        PACKAGING-PATCH-SHA256.txt > SHA256SUMS.txt
    if $include_working_tree; then shasum -a 256 WORKING-TREE.patch >> SHA256SUMS.txt; fi
)
printf 'Package ready (ad-hoc signed, not notarized): %s\n' "$destination"

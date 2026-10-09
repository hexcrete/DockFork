#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
output="$root/fork/dist"
version=""
prepare_only=false
include_working_tree=false
development=false
signing_identity="-"
configuration=Release

usage() {
    cat <<'EOF'
Usage: ./fork/package.sh [--output DIRECTORY] [--version X.Y.Z] [--prepare-only] [--include-working-tree]
       ./fork/package.sh --dev [--signing-identity CERTIFICATE_SHA1]

Build committed HEAD as an Apple Silicon, ad-hoc-signed DockFork release.
Release mode performs no account, provisioning, installation, launch or publication operations.
--prepare-only creates the patched source snapshot without building it.
--include-working-tree includes tracked app/source changes for local testing only.
--dev builds Debug with tracked source changes, certificate-signs, replaces and
      launches the fixed local app at fork/dist/dev/DockFork.app. No release ZIP.
--signing-identity selects a local Apple Development certificate for --dev.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|--version|--signing-identity)
            [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
            case "$1" in
                --output) output="$2" ;;
                --version) version="$2" ;;
                --signing-identity) signing_identity="$2" ;;
            esac
            shift 2
            ;;
        --prepare-only) prepare_only=true; shift ;;
        --include-working-tree) include_working_tree=true; shift ;;
        --dev) development=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ $(uname -s) == Darwin ]] || { echo 'macOS is required.' >&2; exit 1; }
if [[ -n "$version" && ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Version must be X.Y.Z.' >&2
    exit 2
fi
if $development; then
    configuration=Debug
    include_working_tree=true
    identities=$(security find-identity -v -p codesigning | awk '/"Apple Development:/ {print $2}')
    if [[ "$signing_identity" == - ]]; then
        count=$(printf '%s\n' "$identities" | awk 'NF {count++} END {print count+0}')
        [[ "$count" == 1 ]] || {
            echo 'Choose one valid Apple Development certificate with --signing-identity SHA1.' >&2
            exit 1
        }
        signing_identity="$identities"
    fi
    if [[ ! "$signing_identity" =~ ^[A-Fa-f0-9]{40}$ ]] || \
        ! printf '%s\n' "$identities" | grep -Fxiq "$signing_identity"; then
        echo 'The selected Apple Development signing identity is not available.' >&2
        exit 1
    fi
elif [[ "$signing_identity" != - ]]; then
    echo '--signing-identity is only supported with --dev; release signing remains ad-hoc.' >&2
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
cleanup() {
    if [[ -n "${installation:-}" ]]; then
        if [[ -d "$installation/previous.app" && ! -e "$dev_app" ]]; then
            mv "$installation/previous.app" "$dev_app"
        fi
        rm -rf "$installation"
    fi
    rm -rf "$work"
}
trap cleanup EXIT
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
    -configuration "$configuration" -derivedDataPath "$work/DerivedData"
    -destination 'generic/platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
    ENABLE_HARDENED_RUNTIME=NO
)
printf 'Building %s source %s; log: %s\n' "$configuration" "$label" "$destination/build.log"
if ! xcodebuild "${build_args[@]}" build > "$destination/build.log" 2>&1; then
    tail -n 50 "$destination/build.log" >&2
    exit 1
fi

app="$destination/DockFork.app"
ditto "$work/DerivedData/Build/Products/$configuration/DockFork.app" "$app"
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
        codesign --force --sign "$signing_identity" --timestamp=none --options 0 "$file"
    fi
done < <(find "$app/Contents" -type f -print0)
while IFS= read -r -d '' bundle; do
    codesign --force --sign "$signing_identity" --timestamp=none --options 0 "$bundle"
done < <(find "$app/Contents" -depth -type d \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' \) -print0)
codesign --force --sign "$signing_identity" --timestamp=none --options 0 \
    --entitlements "$root/fork/packaging/DockFork.entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

if $development; then
    dev_directory="$output/dev"
    dev_app="$dev_directory/DockFork.app"
    mkdir -p "$dev_directory"
    [[ ! -L "$dev_app" ]] || { echo 'Refusing to replace a symlinked development app.' >&2; exit 1; }
    if [[ -e "$dev_app" ]]; then
        [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$dev_app/Contents/Info.plist") == io.github.hexcrete.DockFork ]] || {
            echo 'Refusing to replace a different application at the development path.' >&2
            exit 1
        }
    fi
    installation=$(mktemp -d "$dev_directory/.DockFork-install-XXXXXX")
    ditto "$app" "$installation/DockFork.app"
    codesign --verify --deep --strict "$installation/DockFork.app"
    # Replace only after a successful build and signature verification.
    osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
var apps = $.NSWorkspace.sharedWorkspace.runningApplications;
for (var i = 0; i < apps.count; i++) {
    var app = apps.objectAtIndex(i);
    if (ObjC.unwrap(app.bundleIdentifier) === 'io.github.hexcrete.DockFork') {
        if (!app.terminate) throw new Error('DockFork refused termination');
    }
}
JXA
    still_running=true
    for ((attempt=0; attempt<5; attempt++)); do
        if pgrep -f '/Contents/MacOS/DockFork( |$)' >/dev/null; then
            sleep 1
            continue
        else
            status=$?
            [[ "$status" == 1 ]] || {
                echo 'Cannot verify that DockFork has exited; leaving the installed app unchanged.' >&2
                exit 1
            }
            still_running=false
            break
        fi
    done
    if $still_running; then
        echo 'DockFork is still running; quit it before replacing the development app.' >&2
        exit 1
    fi
    if [[ -e "$dev_app" ]]; then mv "$dev_app" "$installation/previous.app"; fi
    mv "$installation/DockFork.app" "$dev_app"
    open "$dev_app"
    printf 'Local certificate-signed development app launched: %s\n' "$dev_app"
    exit 0
fi

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

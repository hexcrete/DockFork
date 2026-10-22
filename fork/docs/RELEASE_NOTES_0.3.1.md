# DockFork 0.3.1 Prerelease

Status: the user has explicitly authorized a refreshed Release build with the sanitized October 22 preset. Build and artifact checks are pending. The earlier candidate from `586be06ae0de421e73d0ce7ec5d537509c1c3806` remains superseded and must not be distributed. No tag, upload or publication is authorized. Screenshots remain deferred.

## Changes Since 0.3.0

- Fix checkbox-drag and held-shortcut range selection ending during an unchanged background window refresh. Actual displayed membership/order changes still end the range normally.
- Add Gestures > Options > Disable title bar gestures over scrollable areas and tabs, default Off. When enabled, skip scrolling/content ancestors and recognized tab groups/tab-button subroles, including tab bars without scrolling metadata. Other controls keep the standard gesture rules.
- Remove an unused internal window-action argument without changing behavior.

The new filter uses the existing bounded Accessibility hit test. It adds no AX requests, observer, timer or polling. Window-hit cache reuse is bypassed at gesture starts while enabled so an earlier background hit cannot authorize a nearby tab/control hit. It is not exact draggable-region detection; custom apps can expose incomplete Accessibility metadata. Dock/menu-bar gestures and the separate legacy title-bar scroll feature are unchanged.

The committed preference key and default are retained from the earlier broad-filter implementation. The broader and narrower implementations are one evolved feature, not separate release features.

## Upstream and Settings

Upstream main was fetched October 22 and remains `77e4771d38cf69dc24f2f76c74a73e61fab54571`; no merge was needed. The newest published stable release is still 1.41.0 at `3d6a3cbaa9bbee17959122da7f0a349ca43056d0`, contained in that history.

The October 22 showcase export is sanitized to 249 recognized preferences and 14 generic-ID shortcut rows, labeled 0.3.1. Remove save-panel geometry, last file-dialog root directory, cached screen-recording permission and the reopen-settings flag; keep debug logging Off. Compared with the October 20 preset, enable the title-bar scrolling/tab filter and omit the previously included custom Persistent Switcher shortcut, as supplied. Other shortcut definitions and all other preference values are unchanged. No personal paths, accounts, URLs, window titles, bookmarks or opaque payloads were found in retained values or nested shortcut JSON. No live import or preference reset is performed. The old candidate does not contain this preset; the newly authorized build must include it unchanged.

## Validation and Publication Gate

The user verified the selection-refresh correction and the final narrower title-bar filter in the development app. Seventeen regression suites, formatting/diff checks and signed development build/source/running-path checks passed for those changes. These reports do not establish Release-candidate installation or interaction coverage.

Fresh validation passed all seventeen regression suites, 19 version-metadata cases, build-cleanup checks, focused SwiftFormat checks and diff/script syntax checks. The unchanged native Compact Mode title hit test failed once and passed on retry; no assertion was weakened. Artifact validation passed for the superseded candidate only; it does not validate a future package containing the refreshed preset. Build the candidate from committed sources with `./fork/package.sh --clean-old-builds`. Record its exact source, asset inventory, checksums, signatures and privacy checks after building. Keep the tested assets unchanged after approval.

Before publication, test the exact candidate: selection sweeps and held-shortcut ranges across background refreshes in regular/Compact Window Switcher; enabled/disabled title-bar filtering over empty title bars, ordinary controls, scrolling contents and tab bars. Confirm Dock/menu-bar gestures remain unchanged. Export a settings backup before any optional import.

Ad-hoc signed, Apple Silicon and not notarized. Replacing an ad-hoc build can require removing and re-adding affected system permissions. Updates remain manual. Browser-quarantine/Gatekeeper testing, older macOS releases, exhaustive custom-app/display coverage and media remain unverified. Do not infer them from packaging checks.

Use [the concise release body](RELEASE_BODY_0.3.1.md) for a future GitHub description, not this preparation record. Publication requires approval after candidate testing. Published 0.3.0 assets remain untouched.

## Superseded Candidate Record — Do Not Distribute

- Source: `586be06ae0de421e73d0ce7ec5d537509c1c3806`. Later handoff documentation does not change or rebuild this candidate.
- Folder: `fork/dist/DockFork-586be06-mE8m3w`.
- App ZIP: `DockFork-0.3.1-586be06-arm64.zip`.
- ZIP SHA-256: `13363eda20d8269ab63b9cc26bdb829aaf5da3073534341e311638b40f70bd30`.
- Apple Silicon Release, ad-hoc signed and not notarized, retaining the established DockFork name and bundle ID. Upstream update feed remains disabled; upstream metadata is unchanged.
- The actual package passes 8,079 artifact assertions: nine payload checksums, ten-file release inventory, app/version/upstream/source metadata, arm64/ad-hoc signature checks, absence of development/signing/coverage payloads, ZIP integrity, extracted app content/mode/link correspondence, exact committed-source archive and sidecar/preset correspondence, and clean packaging-patch applicability.
- The privacy-marker audit scanned 480 app/source/sidecar files for configured private home/temp paths, actual local development-certificate identities, private-key material and GitHub token patterns, including UTF-16 path/identity representations. No matching markers were found. Intentional public upstream attribution remains. This is not comprehensive secret or malware certification.
- The packaged preset has 249 recognized preferences and 15 generic-ID shortcut rows. Its setting values match the published 0.3.0 preset; only its export version label changes. No preference import occurred.
- Release mode did not install or launch the app. Old-build cleanup preserved the installed development app and Release packages. Build logs are private local artifacts, not release assets.
- Historical asset inventory only, not eligible for publication: `DockFork-0.3.1-586be06-arm64.zip`, `DockFork-586be06-source.tar.gz`, `DockFork-Showcase.json`, `DockFork.patch`, `INSTALL.md`, `LICENSE`, `SOURCE-COMMIT.txt`, `PACKAGING-PATCH-SHA256.txt`, `BUILD-METADATA.json`, `SHA256SUMS.txt`. Exclude `build.log`, the unpacked app folder and every unlisted file.

This candidate is superseded because it was prepared prematurely and lacks the refreshed preset. Its historical checksums and audit results above do not apply to a future rebuild. Do not test it as the final release, distribute or publish it. The user has since authorized the refreshed build; its new source, checksum and audit results must be recorded separately, followed by exact-candidate testing. No Release app has been installed or launched and no preset imported.

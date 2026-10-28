# DockFork Build and Release Guide

DockFork is a GPL-3.0 fork of [DockDoor](https://github.com/ejbills/DockDoor). Application features remain in the existing source tree; this directory contains fork-only packaging, optional presets and publication records. Exclude `fork/` and fork-specific root documentation from upstream PRs. Follow the [upstream contribution checklist](docs/UPSTREAM_CONTRIBUTIONS.md).

## Stable Release 0.4.0

Version **[0.4.0](https://github.com/hexcrete/DockFork/releases/tag/v0.4.0)** is published as the latest **stable release**, not a prerelease. The user-tested package from `23850ba04cf7c5e523d53ea2be45607419327e57` was published without rebuilding. All ten public assets download and match the audited local hashes. Previous release assets are unchanged.

- [Published release notes](docs/RELEASE_BODY_0.4.0.md)
- [Release source, asset audit and testing status](docs/RELEASE_NOTES_0.4.0.md)
- [Changes and showcase](docs/CHANGES_AND_SHOWCASE.md)
- [Capture checklist](docs/SHOWCASE_CHECKLIST.md)
- [Commit ledger](docs/COMMIT_LEDGER.md) and [resource audit](docs/RESOURCE_LIFECYCLE_AUDIT.md)

Screenshots and recordings remain deferred. A stable release designation does not imply notarization, browser-quarantine testing or complete app/OS/display coverage.

## Build a DockFork Package

Requires macOS 27 and Xcode 27 or later, with Xcode selected as the developer directory. Initial dependency resolution needs network access. From the repository root:

```sh
# Committed-source, ad-hoc-signed Release package; does not install or launch:
./fork/package.sh --clean-old-builds
# Inspect the isolated distribution snapshot without compiling:
./fork/package.sh --prepare-only --clean-old-builds
# Optional per-build version override:
./fork/package.sh --version 1.0.0 --clean-old-builds
```

Release mode uses committed HEAD. Commit reviewed source, version, preset and packaging inputs before building. `--include-working-tree` is a local-test exception: it includes tracked app changes in DockDoor, Assets, BuildTools and DockDoorTests, records WORKING-TREE.patch and labels output working. It excludes untracked files and project changes. Never distribute working-tree or development builds.

The script creates a unique output directory under gitignored `fork/dist/`, builds in a temporary isolated snapshot and leaves the original Xcode project unchanged. Temporary sources/derived data are deleted. Release packaging does not install, launch, import settings, tag, upload or publish. Fork identity and updater changes are applied only to the snapshot.

Routine builds use `--clean-old-builds`. After success, guarded cleanup removes recognized old development/local-test outputs in the selected directory. It preserves the current output, installed app, Release ZIP/checksum directories, active builds, symlinks and unrelated entries. Without the flag, outputs are retained. Safety checks: `ruby fork/packaging/tests/build_cleanup_test.rb`.

### Stable Local Development Build

```sh
./fork/package.sh --dev --clean-old-builds
# Optional optimized Debug comparison; not a distribution package:
./fork/package.sh --dev --optimized --clean-old-builds
```

Development builds use the existing local Apple Development certificate, preserve the DockFork identity/preferences, gracefully replace the running instance and launch `fork/dist/dev/DockFork.app`. Verify that exact executable is running. With multiple certificates, select one using `--signing-identity CERTIFICATE_SHA1`; do not commit private identity details. Development builds are not release assets.

The optional optimized mode retains Debug configuration and code paths but uses Swift `-O` with coverage disabled. `DockForkOptimizedDevelopment` identifies the mode in the installed Info.plist. Normal Debug uses the same identity and path. User comparison found optimized DockFork and upstream similarly smooth; this is not a matched two-source benchmark or measured FPS result.

The development snapshot includes tracked source changes but excludes untracked files and project changes. New source registration must be committed before relying on this command. Builds do not run the regression suites automatically.

### Fork and Upstream Versions

`version.json` records DockFork version **0.4.0**, incorporated upstream commit `3044142c907b9cdd49917628847a04970450a8e6`, stable upstream release **1.41.0**, and its exact release commit `3d6a3cbaa9bbee17959122da7f0a349ca43056d0`. The included 1.41.1b1 tag is a beta, not the stable base.

After a future merge, fetch upstream tags and select the newest published stable release contained in the merged history. Never label an unmerged release as the base or infer it from Xcode's project version. Run `ruby fork/packaging/tests/version_metadata_test.rb`. Packaging validates ancestry/tag identity and embeds version/base metadata in the isolated app and BUILD-METADATA.json for Support > Updates.

### Release Assets and Validation

Only these ten files are eligible for upload after candidate testing and approval:

- `DockFork-<version>-<commit>-arm64.zip`
- `DockFork-<commit>-source.tar.gz`
- `DockFork.patch`
- `SOURCE-COMMIT.txt`
- `BUILD-METADATA.json`
- `INSTALL.md`
- `LICENSE`
- `DockFork-Showcase.json`
- `PACKAGING-PATCH-SHA256.txt`
- `SHA256SUMS.txt`

Keep `build.log`, the unpacked app, test logs, development outputs and private notes local. Do not upload an entire output directory. Audit ZIP integrity, extracted app correspondence, nested ad-hoc signatures, exact committed source, applied overlay, updater isolation, sidecar correspondence and every checksum. Release builds disable coverage and strip debug maps before signing to avoid distributing local build-path data; inspect the actual artifacts rather than assuming flags provide privacy.

Application identity is DockFork.app, executable DockFork, bundle/preference domain `io.github.hexcrete.DockFork`. Diagnostics use `~/Library/Application Support/DockFork/Diagnostics`. The source module and compatible AppleScript commands retain DockDoor naming. Automatic upstream updates are disabled; downloads are manual. Distribution source/issue links target DockFork; intentional upstream attribution, donation, Pro, community and translation links remain.

See [installation and signing limitations](packaging/INSTALL.md). Ad-hoc signing is not notarization or Developer ID approval. A rebuilt ad-hoc app can require re-adding permissions even at the same path. Browser quarantine/Gatekeeper, first launch, permissions and preset import must be tested on the exact candidate; build checks do not establish them. Never disable Gatekeeper globally.

## Optional Showcase Preset

[DockFork-Showcase.json](presets/DockFork-Showcase.json) is the sanitized October 27 export for 0.4.0: **273 recognized preferences and 15 generic-ID shortcut rows**. It is not the default app configuration and is never imported automatically. Published releases retain their own attached presets.

Export a settings backup first, then use General > Backup & Restore > Import Settings. **Import replaces the preference domain**, omitted values return to defaults and the app requests a restart. The required `app: DockDoor` envelope is importer compatibility, not a choice of destination preference domain.

Privacy review removes save-panel geometry, last file-dialog directory, cached recording permission and the reopen-settings flag. Debug logging is Off. Shortcut IDs are generic; supplied actions, keys, modifiers, sides, ordering and other preference values are preserved. No personal paths, accounts, URLs, window titles, bookmarks or opaque payloads remain in retained values. The source export is unchanged. Check with `ruby fork/tests/showcase_preset.rb`; inspect new exports again before distribution.

The preset enables Spaces Bar, multi-selection, action/cursor feedback and the optional title-bar scroll/tab exclusion. It uses numeric Flexible pills with icon limits 2/6, toolbar Space indicators, and minimal-reveal keyboard scrolling. These are supplied showcase choices, not changes to application defaults. Review shortcuts and system swipe conflicts before import. Actual import/installation testing remains pending.

Fresh defaults keep Spaces Bar and multi-selection Off. Spaces Bar defaults are Medium items, Flexible 2/6 icons, Fixed width 160 points and icon activation On. Per-mode Space indicators default Off, with current-Space highlighting On when enabled. Existing saved choices are preserved.

## Maintaining Publication Records

Follow the fork-only maintenance instructions in [AGENTS.md](../AGENTS.md#fork-documentation-maintenance-required). Keep the guide, release status, capture checklist, resource/contribution notes and ledger consistent. The roadmap was removed by request. Preserve dated audit evidence and do not present old development stages as current limitations or tests.

Ledger entries record exact hashes/category/purpose/file counts once each, through an explicit tip. A documentation commit cannot include its own final hash; record it in the next update. Published [0.2.0](docs/RELEASE_NOTES_0.2.0.md) and [0.3.0](docs/RELEASE_NOTES_0.3.0.md) records remain historical evidence, not verification of a new package.

## Development Validation

`./fork/package.sh --dev --clean-old-builds` builds, signs, installs and relaunches; it does **not** run the Ruby regression suites. Run focused checks separately when testing is authorized. A feature being complete does not make its regressions obsolete.

| Changed behavior | Focused checks under `fork/tests/` |
|---|---|
| Preview hover transitions, publication scope, outgoing-card exits or resting fade | `preview_publications.rb` with optional `--native` offscreen SwiftUI observation check; `preview_hover.rb`, `preview_keyboard.rb`, `preview_focus_fade.rb` |
| Window-cache reconciliation, batching, image-only delivery or suppression | `cache_reconciliation.rb`, `frame_placement.rb`; `space_presentation.rb --refresh-only` for refresh scheduling without unrelated native layout/drag fixtures |
| Wake/unlock/display recovery, readiness or keyboard-resource health | `wake_recovery.rb`, `preview_keyboard.rb`, `frame_placement.rb` |
| Full-size preview geometry, request lifetime, idle cleanup or cache refresh | `preview_idle.rb`, `full_preview_geometry.rb`, `frame_placement.rb`, `preview_window_notifications.rb`, `preview_focus_fade.rb` |
| Preview panel notifications, companion geometry or input snapshots | `preview_window_notifications.rb`, `preview_keyboard.rb`, `frame_placement.rb`, `preview_focus_fade.rb` |
| Cache batches applied to preview rows, standalone additions/removals | `preview_batch_reconciliation.rb`, `cache_reconciliation.rb`, `selection_ranges.rb`, `linked_tiling.rb` |
| Space-filter candidate preparation, ordering or invalidation | `switcher_filter_candidates.rb`, `cache_reconciliation.rb`, `selection_ranges.rb`, `preview_keyboard.rb`; `space_presentation.rb --refresh-only` for topology lifecycle |
| Spaces Bar content publication, icon fitting or pill presentation | `spaces_bar_presentation.rb` (add `--model-only` to skip its native animation panel); `space_presentation.rb --model-only` for model/prepared sizing; `--viewport-compile-only` additionally compiles the existing native viewport fixture without running its drag checks |
| Spaces Bar refresh-cost measurement | `space_refresh_costs.rb` counts production refresh/sort/resident-model operations with inert OS/cache providers; optional, no native latency/FPS claim or app instrumentation |
| Regular switcher sample/chrome sizing or final panel-fitting safety | `preview_chrome_measurements.rb`, `preview_keyboard.rb`, `selection_ranges.rb`; `space_presentation.rb --model-only` for related layout/filter behavior |
| Card layout, drag ghosts, Spaces presentation | `preview_layout.rb`, `space_presentation.rb` |
| Selection or keyboard/session routing | `selection_ranges.rb`, `preview_keyboard.rb` |
| Ownership, worker scheduling or frame transactions | `action_ownership.rb`, `action_responsiveness.rb`, `frame_placement.rb` |
| Auto Tile, linked resize or tiling settings | `linked_tiling.rb`, `tiling_settings.rb` |
| Native-tab discovery or Close | `native_tab_grouping.rb`, `native_tab_close.rb` |
| Resting fade and native mouse targeting | `preview_focus_fade.rb` uses a disposable panel; no working windows or pointer movement |
| Popup execution, styling or lifetime | `action_feedback.rb` |
| Cmd+Tab app actions, Quit or scripting | `cmd_tab_close.rb`, `quit_actions.rb`, `script_actions.rb` |
| Title-bar hit classification or Wine discovery | `window_gesture_zones.rb`, `wine_discovery.rb` |
| Curated preset changes | `showcase_preset.rb` |

Use `ruby fork/tests/<name>.rb` for an applicable check; include related rows when shared behavior changes. Packaging/version/preset asset validation remains separate from application regressions. Full-suite runs are appropriate for broad shared-operation changes, merges with a broad impact, or release preparation, not every cosmetic rebuild. Builds and source assertions do not replace manual interaction or downloaded-installation testing.

October 24 source-only test audit: all eighteen suites still cover active behavior. None is deleted solely because its feature shipped. Obsolete source-location assertions were updated for the shared drop-intent resolver and the new single-window card-shadow policy. Test execution is explicitly skipped in this pass. The previously intermittent native popup fade-in assertion remains unresolved; do not remove it or declare it fixed to obtain a passing run. Native render/timing fixtures need WindowServer access and can be affected by machine load; retain those limits when reporting results.

For the measurement-only cache-invalidation checkpoint, run `ruby fork/tests/cache_reconciliation.rb --measure-invalidation`. This uses inert synthetic targets and production-source writers, printing revision counts and synthetic comparison timings. It does not profile the running app or change cache policy. Run without the flag for normal cache regressions.

## October 27 upstream integration checkpoint

Upstream main through `3044142c` is merged as `3655c66a` before the next release is planned. It adds automatic-quit safety/exclusions, optional cached screen-position sorting, centralized links/identifiers and accessibility/Reduce Motion refinements. The newest incorporated stable release remains **1.41.0**; the included 1.41.1b1 tag is a beta. Preserve the fork's ownership, adaptive controls, asynchronous readiness and reduced-motion fades. Focused checks, version validation and signed/running development verification pass; native manual verification remains pending. No new Release package, version bump, preset import or publication is part of this checkpoint. Optional focused merge checks: `ruby fork/tests/upstream_integration.rb`.

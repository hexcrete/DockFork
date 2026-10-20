# Fork-Only Publication Assets

Keep publication-only material here so it can be excluded from upstream contributions:

- `docs/`: feature guide, commit ledger, showcase checklist, roadmap, contribution notes, and resource audit.
- `presets/`: reviewed example preferences for optional release assets.
- `package.sh` and `packaging/`: isolated DockFork packaging and installation instructions.
- `version.json`: DockFork's version and its verified upstream release/commit base.
- `dist/`: ignored local package outputs. Future showcase media should also live under this directory.

Application features stay in the existing DockDoor source locations. **Upstream PRs exclude this directory and fork-specific root `AGENTS.md`/`README.md` changes.** Follow the [required upstream contribution checklist](docs/UPSTREAM_CONTRIBUTIONS.md#fork-only-exclusions), including mixed-commit extraction and final-diff review. File exclusions alone do not make a feature upstream-ready.

## Maintaining Publication Records

Follow the [required documentation maintenance instructions](../AGENTS.md#fork-documentation-maintenance-required) after changes. The ledger has an explicit coverage tip, including fork-only commits; the showcase guide describes current behavior, while the capture checklist tracks candidates without implying media or tests were completed. Keep roadmap, resource audits, contribution gates, packaging guidance, and preset privacy notes current when affected. Ledger maintenance commits receive their exact hash in the next update; do not claim coverage through an unrecorded commit.

## Latest Prerelease: 0.3.0

The [public release body](docs/RELEASE_BODY_0.3.0.md) is separate from the detailed preparation/audit record below. It is the published release description; the detailed record retains audit results and testing gaps.

The [0.3.0 release notes and gate](docs/RELEASE_NOTES_0.3.0.md) cover changes since the published 0.2.0 package: optional action/cursor feedback, range selection, explicit Quit/Force Quit, off-main action work, shared batch ownership, native-tab and Wine/CrossOver handling, and input/windowless-preview fixes. The latest upstream merge is website-only; DockDoor 1.41.0 remains the included stable release, with history through `77e4771`. [0.3.0 is published as a prerelease](https://github.com/hexcrete/DockFork/releases/tag/v0.3.0) from the unchanged audited candidate `6d3eb470`; see the publication record below. Screenshots are deferred, not required.

The current optional preset is the sanitized October 20 export for 0.3.0: 249 preferences and 15 generic-ID shortcut rows. It enables action feedback and Mouse Follows Focus feedback using trigger-based placement. It is not imported automatically and does not change application defaults. Published 0.1.0 and 0.2.0 assets retain their original presets.

## Previous Prerelease: 0.2.0

[Version 0.2.0 is published as a prerelease](https://github.com/hexcrete/DockFork/releases/tag/v0.2.0). Application behavior is reviewed October 16 through `d17f1b55`, including ordered selection, batch actions, group dragging, tiling, ordered AppleScript window lists, Select All, search clearing, adaptive preview controls and progressive traffic-light overflow, shared Space information in action menus, selection accessibility, the recent Dock-click/startup/header-hover/tiling fixes, shortened settings explainers, and optional windowless-app selection with one-shot checks. Read the [release notes and publication record](docs/RELEASE_NOTES_0.2.0.md).

The published [0.1.0 prerelease](https://github.com/hexcrete/DockFork/releases/tag/v0.1.0) remains unchanged. The 0.2.0 Release candidate from `c863e62` is built and audited, including the refreshed optional preset and Release-only privacy safeguards. See the candidate record under Release Assets and Validation. [DockFork 0.2.0](https://github.com/hexcrete/DockFork/releases/tag/v0.2.0) is now published from the unchanged audited candidate. Draft download-back checks and anonymous public-download verification passed; the publication record below retains the remaining installation/testing gaps. Screenshots and recordings are deferred, not a release gate. Do not distribute the certificate-signed development app.

The published 0.2.0 preset is the reviewed 246-preference October 16 export with 15 shortcut rows; the repository now holds the separately reviewed 0.3.0 preset. Explicitly importing it enables selection, drag-to-tile, linked resizing and Window Gestures; these remain Off in fresh application defaults. The preset is never automatically imported. Actual candidate privacy checks passed; manual Release and preset-import testing are still required. Earlier Debug and 0.1.0 checks do not substitute for those tests.

New 0.2.0 defaults: Windowless-app selection in standalone Window Switcher is On under enabled multi-selection; Quit and Open New Window included those apps in the 0.2.0 batch targets; current code also supports the explicit Force Quit action. Show selection summary is On, gated by enabled selection and checked windows; maximum tiling rows is 2 and columns is 3. Window Selection and Tiling have separate sections under Keybinds. Tile only what fits and group Fill-to-Auto-Tile default Off; overflow stacks in existing cells, and ordinary Fill does not switch Spaces. See the [settings reference](docs/CHANGES_AND_SHOWCASE.md#selection-and-tiling-settings) for locations, defaults and verification commands. Existing saved choices are preserved.

Post-0.2.0 development separates **Quit App** from **Force Quit App**. Normal preview Quit and Close-to-Quit no longer force-quit because Option is held. Force Quit is independently assignable and available in native menus, including for selected windowless apps; it may discard unsaved changes. AppleScript adds explicit normal/force requests using window-ID targeting. The documented Dock-icon Quick Quit gesture is unchanged. See the [development guide](docs/CHANGES_AND_SHOWCASE.md#in-development-explicit-quit-actions) for behavior, examples and test gaps. These changes are not included in the published 0.2.0 package.

## Build a DockFork Package

The packaging script is a fork-only CLI distribution workflow, not a replacement for upstream's Xcode development instructions. Building requires macOS 27 and Xcode 27 or later, with Xcode selected as the active developer directory. Initial dependency resolution requires network access. No Apple account is required for this ad-hoc-signing workflow.

```sh
./fork/package.sh --clean-old-builds
# Optional release version override:
./fork/package.sh --version 1.0.0 --clean-old-builds
# Inspect the isolated source overlay without building:
./fork/package.sh --prepare-only --clean-old-builds
# Local testing of tracked, uncommitted source changes (not a release):
./fork/package.sh --include-working-tree --clean-old-builds
```

By default the script uses **committed HEAD**, not uncommitted application changes or the local project overrides. `--include-working-tree` is an explicit local-test exception: it applies tracked changes in `DockDoor`, `Assets`, `BuildTools`, and `DockDoorTests`, records them in `WORKING-TREE.patch`, and labels the output `working`. It excludes untracked files and project-file changes. Do not publish these test builds; commit reviewed changes and rebuild normally for release. The script reads the packaging patch, entitlements, installation guide, and optional preset from this checkout. Commit and review those assets before publishing a release. A future upstream change that invalidates the overlay stops packaging rather than silently skipping it.

Each invocation creates a unique directory under `fork/dist/` (or `--output DIRECTORY`). Temporary build sources and derived data are deleted afterward. The original project is not edited. Release packaging does not install, launch, import preferences, publish, or push anything.

Pass `--clean-old-builds` on routine rebuilds to remove older local-test/development output after success. Cleanup requires generated folder names, source-commit records and matching build metadata. It keeps the current build, installed `dev/DockFork.app`, Release packages, active builds, symlinks and unrelated/unrecognized entries. ZIPs and checksum manifests protect packaged outputs even with a `working` label. Failed invocations retain old output and remove their temporary active-build marker; the next successful invocation can clean recognized failed builds. Without the flag, old output is retained. Cleanup is limited to the selected output directory. Run its safety tests with `ruby fork/packaging/tests/build_cleanup_test.rb`.

The resulting app uses `DockFork.app`, executable `DockFork`, and bundle/preference identity `io.github.hexcrete.DockFork`. Its Swift module and scripting command names remain DockDoor-compatible. The overlay disables Sparkle construction and replaces update checks with manual fork-release downloads; upstream feed/signing keys are removed. Diagnostics use a separate DockFork directory. See [installation and signing limitations](packaging/INSTALL.md).

### Fork and Upstream Versions

`version.json` keeps four independent fields: `forkVersion`, `upstreamRelease`, `upstreamReleaseCommit`, and `upstreamCommit`. The record now selects `0.2.0` for the next prerelease; the published first prerelease remains `0.1.0`. The current base is DockDoor release `1.41.0` plus upstream changes through `3e08721`. Upstream's Xcode project still says `1.18.3`; it is not the published release version and is no longer used as DockFork's default version.

Support > Updates displays the DockFork version and a separate `Based on DockDoor 1.41.0 + upstream changes · 3e08721` line. The full base hash is available by hovering over that line. An exact release base omits `+ upstream changes`. These values are embedded during packaging, not fetched at runtime. Standard DockDoor builds remain unchanged.

After an upstream merge:

1. Fetch the upstream release tags, then choose the newest **published stable release already included** in the incorporated upstream commit. Do not simply use GitHub's latest release if it is not merged.
2. Record the release version, its full tag commit (`git rev-parse <release-tag>^{commit}`), and the full incorporated upstream commit in `version.json`.
3. Keep `forkVersion` independent. Update it for a fork release, or use `--version X.Y.Z` for a one-build override without editing the record.
4. Review the diff, run `ruby fork/packaging/tests/version_metadata_test.rb`, build, and verify the displayed base before publishing.

Packaging requires complete local Git history and the pinned release tag. If a clone lacks that tag, fetch it from the official repository (for the current record: `git fetch https://github.com/ejbills/DockDoor.git tag 1.41.0`). The validator checks release-tag identity, release-to-base and base-to-build ancestry, and any newer included stable tags. If a remote points to the official DockDoor repository and has a `main` tracking ref, it also checks that the recorded base matches the merged remote history; fetching unmerged upstream changes does not change the label. Without such a remote, ancestry/tag checks still run offline, but confirming freshness of the base remains part of merge review. Shallow clones may need their history completed.

Release mode reads the record from committed HEAD; local test/development mode reads the working record. The existing source-only exclusion still applies to untracked app files, but packaging explicitly uses its current fork-only assets, including this record and the validator. Commit and review those assets before a release. The script embeds version/base values in the isolated app's Info.plist and verifies them after building, without changing the source project. `BUILD-METADATA.json` records the effective fork version, upstream release/base hashes, source commit, and whether later upstream commits are included.

### Window State and Spaces Defaults

The application's preference declarations supply these defaults for the added features in both DockDoor and DockFork builds, with existing preference key names unchanged:

- Dock, Window Switcher, and Cmd+Tab: window state/Space indicator dock styling enabled; swap with traffic lights enabled, limited to Compact Mode.
- Spaces dropdown: show the Current badge and unavailable Spaces.

These are fallbacks for unset preferences, not a migration or forced configuration. Saved or imported choices take precedence; resetting the corresponding settings restores these defaults. The packaging overlay does not override them.

### Stable Local Development Build

```sh
./fork/package.sh --dev --clean-old-builds
# If multiple Apple Development certificates are available:
./fork/package.sh --dev --clean-old-builds --signing-identity CERTIFICATE_SHA1
```

This local-only mode builds Debug with tracked working-tree source changes and uses your installed Apple Development certificate. With exactly one valid development identity, selection is automatic; otherwise select its SHA-1 from `security find-identity -v -p codesigning`. No account name or certificate fingerprint is stored in tracked files, and no certificates or private keys are exported. macOS may request access to the signing key.

After successful build and signature verification, the script gracefully quits any running DockFork instance, replaces `fork/dist/dev/DockFork.app`, and launches that fixed app path. It does not quit DockDoor, clear preferences, or modify the source project. The whole `fork/dist/` directory is gitignored. Quit DockDoor yourself if it is running, to avoid competing shortcuts.

Changing from ad-hoc signing may require granting permissions once again. Later builds should retain them while the signing certificate, designated requirement, bundle ID, and installed path remain compatible. Replacing or expiring the certificate, changing identity, or returning to an ad-hoc package can require approval again. A development certificate is not Developer ID distribution signing or notarization.

Development mode creates no release ZIP and must not be distributed; its signature identifies your development account. Run the ordinary packaging command separately for the initial ad-hoc release workflow.

The certificate-signed Debug workflow, nested signature checks, fixed-path replacement and exact-path launch have passed, including the October 15 tiling/activation fixes. Its designated requirement is certificate-based, not tied to a binary hash. Permission retention across subsequent builds still needs verification after granting access to this signed build.

The October 15 integration includes DockDoor 1.41.0 and later upstream metadata through `3e08721`. Settings now separate Gestures from Keybinds. The signed Debug build/relaunch, source-overlay/binary/signature correspondence, 84 isolated gesture/swipe/frame/reservation cases and 19 version cases passed after adapting gesture minimization to the existing confirmed-state helper. New manual gesture/display testing remains pending. This integration predates the authorized October 16 Release-candidate build; current validation is recorded under Release Assets and Validation.

The published 0.2.0 code includes default-Off linked resizing under Keybinds > Tiling. It works without enabling multi-selection or Window Gestures and applies only within layouts tiled together. Initial integration tests ran while the Mac was locked. Later unlocked tests and user reports cover the tiling, drag-completion and independent Fill fixes; native linked-edge and exhaustive display coverage remain limited. See the dated evidence in the [resource audit](docs/RESOURCE_LIFECYCLE_AUDIT.md).

### Release Assets and Validation

Publish these together after testing the package:

- `DockFork-<version>-<commit>-arm64.zip`: ad-hoc-signed Apple Silicon app.
- `DockFork-<commit>-source.tar.gz`, `DockFork.patch`, and `SOURCE-COMMIT.txt`: exact committed source and the applied overlay.
- `INSTALL.md`, `LICENSE`, `SHA256SUMS.txt`, and `PACKAGING-PATCH-SHA256.txt`.
- `BUILD-METADATA.json`: effective version and exact upstream/source ancestry for this package.
- `DockFork-Showcase.json`: optional preferences, never automatically imported.

Release packaging explicitly disables code-coverage instrumentation so dependency profiling symbols do not retain local temporary build paths. It also strips debug-symbol maps from Release Mach-O files before signing, preserving executable instructions and exported symbols. This does not change the source project or the development build mode. Verify the resulting binaries rather than inferring privacy from build flags.

Keep `build.log` local: it can contain developer paths and is not a release asset. Do not publish the entire output directory indiscriminately. A successful signature verification establishes package integrity, not Developer ID trust or notarization.

Before release, quit the development instance and test DockFork's fresh permissions, independent preferences, all three preview modes, shortcuts, widgets, diagnostics export, and `tell application "DockFork"` scripting. Verify the update button opens the fork releases rather than upstream. Test the downloaded/quarantined ZIP on another Mac as well. Building with a macOS 13 deployment target does not itself prove compatibility with macOS 13; supported versions require runtime testing.

[DockFork 0.1.0](https://github.com/hexcrete/DockFork/releases/tag/v0.1.0) is published as a prerelease. Build, signatures, checksums, source/asset correspondence and user-reported macOS 27 testing by local transfer passed. Downloaded/quarantined installation and older-OS compatibility remain unverified.

### 0.2.0 Candidate, October 16

October 16, 2026 candidate: `c863e628d17d8c80985cd77533ff94db03d6444a`. Built on macOS 27.0.1 with Xcode 27.0 as an arm64, ad-hoc-signed Release app. Existing Swift 6 compatibility warnings remain in the current Swift 5 language mode; this is not a warning-free build. All 19 package checks passed: nine asset checksums, ZIP integrity, 219 extracted bundle entries' contents/modes/links, deep/strict nested signatures and ad-hoc identity, exact committed source archive, clean packaging-overlay application, committed preset/license/install-guide correspondence, source/upstream version metadata and disabled upstream updater feed. The privacy-marker scan covered 462 app/source/sidecar files and found no configured private-home, development-identity, credential/private-key or temporary-build-path markers. Intentional public attribution remains. This is not a comprehensive secret-scanner certification. The application includes no development/debug/signing payloads; the temporary worksheet and local outputs are absent from its source archive. Release packaging disables coverage instrumentation and removes debug maps before signing. The preset has 246 reviewed preferences and 15 generic-ID shortcut rows, with debug logging Off.

Local package: `fork/dist/DockFork-c863e62-uTuBcN/DockFork-0.2.0-c863e62-arm64.zip`. ZIP SHA-256: `7c9456e9a7875f8fce593bf0877087cc0d83bd8b1460d2071a3d986d7ebe2263`. Preset SHA-256: `96e30b9d8dca6beb4d2c3fd82370c650e5a7b4dcaf6ef5e9bc76a6fd3e7b1555`. Publish only the ten allowlisted assets, never the development app, build logs, audit notes or the whole output directory. Earlier rejected candidates are not eligible for distribution. The Release app was not installed or launched, the preset was not imported, and the signed development app and live settings were left unchanged. Manual Release verification, downloaded/quarantined installation, minimum-OS validation and publication approval remain pending. No tag, push, draft, upload or publication was performed.

<details>
<summary>Historical 0.1.0 candidate and publication records</summary>

These dated stage records are retained for auditability. Statements such as publication pending describe that stage only. Versions 0.1.0, 0.2.0 and 0.3.0 are published as prereleases. See the [0.2.0 publication record](docs/RELEASE_NOTES_0.2.0.md) and [0.3.0 preparation gate](docs/RELEASE_NOTES_0.3.0.md#preparation-and-publication-gate).

Release validation, October 11, 2026: a committed-source candidate from `82f0a06600861d1a8fa9cf9fd024e1d61a273952` passed the arm64 Release build on macOS 27.0.1 / Xcode 27.0. All nine asset checksums, ZIP integrity, unpacked nested signatures, and all 219 bundle entries' contents, modes, and symlinks passed verification. Its source archive matched the committed tree; the packaging patch applied cleanly, and the bundled license, preset, and installation guide matched their source files. Embedded identity/version/source metadata and absence of the upstream updater feed were verified. This candidate predates the latest preset and label updates.

A later local test candidate used `--include-working-tree` to build the renamed swipe setting and attach the refreshed 237-setting preset. All ten asset checksums (including `WORKING-TREE.patch`), ZIP integrity, unpacked nested signatures, 219 bundle entries, preset correspondence, source-patch reconstruction, and identity/version checks passed. The committed archive plus the supplied patch reconstructs its changed app sources. All 19 version-metadata tests passed. These test candidates use DockFork `0.1.0`, based on DockDoor `1.40.7` plus changes through `0bd2e46`.

Neither earlier candidate was installed or launched; the running development app and preferences were left untouched. They remain ad-hoc signed, not notarized. The full Xcode test suite, clean-account/second-Mac installation, downloaded/quarantined installation, update/permission behavior, and minimum-OS runtime compatibility remain unverified. The build emits Swift 6 compatibility warnings in the current Swift 5 language mode; this is not a warning-free build. Build the final publication candidate from committed HEAD without `--include-working-tree`. Generated assets and logs remain gitignored under `fork/dist/`; publish only the asset allowlist above, never `build.log` or the entire directory.

Previous committed-source candidate, October 11, 2026: `9fcf28dbb82334e40ff7141d2b16e3661f9755b2` passed the arm64 Release build and includes the shared preview-centering and scroll-hit-target fixes plus the refreshed optional preset. All nine asset checksums, ZIP integrity, unpacked nested ad-hoc signatures, all 219 bundle entries (contents, modes, and symlinks), source archive correspondence, clean packaging-overlay application, preset/license/install-guide correspondence, identity/source/upstream metadata, and disabled upstream updater feed passed verification. All 19 version-metadata tests passed. Output: `fork/dist/DockFork-9fcf28d-aXldXK/DockFork-0.1.0-9fcf28d-arm64.zip`. The Release app was not installed or launched; the preset was not imported, and downloaded/quarantined installation testing and publication remain unperformed. The running signed development build and live preferences were left unchanged.

Upstream integration `325ef3f` now records base `7be384b` with latest included stable release 1.40.7. It incorporates upstream native-tab focus caching and Dock indicator stabilization plus beta appcast metadata; DockFork still does not use the upstream updater. The October 11 candidate above predates this merge; the October 12 candidate below incorporates it. User manual merge verification passed; no new Release installation test is inferred.

Previous committed-source candidate, October 12, 2026: `0cabb33081550df578d6ca39569d3a65ae6d0bb8` passed the arm64 Release build and includes upstream through `7be384b` plus both final-review safety fixes. All nine checksums, ZIP integrity, extracted nested ad-hoc signatures, all 219 bundle entries (contents, modes, symlinks), byte-exact committed source archive, clean overlay application, committed preset/license/install-guide/patch correspondence, source/upstream metadata and disabled upstream updater feed were verified. The 19 version-metadata cases passed. Output: `fork/dist/DockFork-0cabb33-amzRCD/DockFork-0.1.0-0cabb33-arm64.zip`. The Release app was not installed, launched, or published; the preset was not imported. Downloaded/quarantined installation, manual Release feature testing, and minimum-OS compatibility remain pending. The signed development instance and live preferences remained unchanged. A later documentation-only commit records this validation; it does not change the candidate's app sources or embedded source identity.

October 12 testing follow-up: Import Settings stalled in macOS file-panel initialization in the running development instance, not an installed Release. Import/Export deferral fix `4fdaa56` passed the signed Debug build/relaunch and the user reported it working. The existing `0cabb33` candidate does not contain this fix; rebuild and verify the Release before publishing. Full Xcode tests and Release verification of this fix remain pending. No backup was applied and no preferences reset during investigation.

Latest committed-source candidate, October 12, 2026: `36e635e8f0ad35cdd90fb390b3aa0195cefdd8b2` includes the Import/Export dialog fix and passed the arm64 Release build. All nine checksums, ZIP integrity, unpacked deep/strict ad-hoc signatures, 219 bundle entries, byte-exact source archive, overlay application, committed preset/license/install-guide/patch correspondence, source/upstream metadata and disabled upstream updater feed passed verification. All 19 version-metadata cases passed. Output: `fork/dist/DockFork-36e635e-UoauGA/DockFork-0.1.0-36e635e-arm64.zip`. Version remains 0.1.0, based on DockDoor 1.40.7 plus upstream through 7be384b. The Release app was not installed, launched or published; no preset was imported. Downloaded/quarantined installation and manual Release testing remain pending. The existing development app and preferences were not replaced. ZIP SHA-256: `22ec9f8c8bd8083b15f9d2983b5603cf689241f7a81b7c517d4ad41d5e30e0d5`.

Prerelease preparation, October 12, 2026: the user reports successful testing of the `36e635e` Release candidate on additional Macs running macOS 27, using locally transferred packages. Specific hardware configurations and individual feature scenarios are not inferred. Downloaded/quarantined Gatekeeper installation remains pending. A repeated privacy check scanned 431 app/source files and ZIP sidecar metadata, plus all 237 showcase preferences including nested shortcut JSON. No configured credential markers, private home paths, personal signing identities in the app, or private preset payloads were found. Upstream attribution, public GitHub identities, an upstream translation placeholder, and Sparkle's generic CI paths are intentional; this is not a comprehensive secret-scanner certification. All nine asset checksums passed again. Only the documented release-asset allowlist will be uploaded; development builds, logs and private notes remain excluded. Publication is not yet complete.

Draft prerelease preparation, October 12, 2026: annotated tag `v0.1.0` points to tested source `36e635e8f0ad35cdd90fb390b3aa0195cefdd8b2`. The approved release notes and exactly ten allowlisted assets were uploaded to a draft prerelease in hexcrete/DockFork. Authenticated download-back verification confirmed every asset, including the checksum list, matches the local package byte-for-byte. The remote tag target and draft/prerelease state were checked. The draft is not publicly published; publication is paused awaiting explicit confirmation. No application rebuild, installation, preferences change, public download/Gatekeeper test, or media capture was performed. Generated logs and development builds were not uploaded.

Published October 12, 2026: [DockFork 0.1.0 prerelease](https://github.com/hexcrete/DockFork/releases/tag/v0.1.0), tag `v0.1.0`, uses tested source `36e635e8f0ad35cdd90fb390b3aa0195cefdd8b2`. Exactly ten allowlisted assets were published with the approved notes. Authenticated download-back checks matched every asset byte-for-byte, all ten public asset links returned HTTP 200, and an anonymous app-ZIP download matched SHA-256 `22ec9f8c8bd8083b15f9d2983b5603cf689241f7a81b7c517d4ad41d5e30e0d5`. The remote annotated tag resolves to the embedded source commit; the release is public, not draft, and marked prerelease. No app rebuild, local installation, launch, settings import or media capture accompanied publication. User-reported testing covers additional Macs running macOS 27 after local transfer. A command-line download does not establish browser quarantine or Gatekeeper behavior; that installation test and older-OS runtime testing remain pending. Privacy review, upstream attribution and asset exclusions remain as recorded above.


</details>

## Optional Showcase Preset

[DockFork-Showcase.json](presets/DockFork-Showcase.json) is the sanitized October 20 example configuration for the 0.3.0 candidate. It is not the application's default configuration and must not be imported automatically. Published 0.1.0 and 0.2.0 releases retain their separately attached presets; updating this file does not replace those assets.

To try it, first export your existing settings, then use **General > Backup & Restore > Import Settings** in the fork build. Import replaces the current preference domain rather than merging only the included settings, and the app asks to restart. Omitted settings return to their defaults. Use a separately identified DockFork build; this preset alone does not isolate preferences from DockDoor.

### Privacy Review

The current preset was refreshed and privacy-reviewed October 20, 2026. It retains 249 recognized preferences from the supplied 253-key export. Review included every remaining string and nested shortcut JSON. Run `ruby fork/tests/showcase_preset.rb` for repeatable format, key-inventory, generic-ID and privacy-marker checks. These checks do not replace the actual packaged-asset audit or prove installation/import behavior.

- Removed four system/private-state entries: save-panel geometry, the last file-dialog root directory, cached screen-recording permission and the reopen-settings flag. No private directory value is retained.
- Preserved the required backup envelope with application version 0.3.0; no timestamp is added.
- Replaced all 15 shortcut-row UUIDs with unique generic IDs. Actions, keys, scopes, sides and row order remain those supplied.
- Debug logging is Off. Retained nonidentifying onboarding flags, which grant no permissions.
- No remaining personal file paths, bookmarks, account identifiers, email addresses, URLs, opaque payloads or window titles were found in the prepared preset.
- Relative to the earlier showcase, the only preference additions are enabled action feedback, trigger-based placement and enabled Mouse Follows Focus feedback. Generic-ID reassignment is not a shortcut behavior change.

The envelope intentionally retains `"app": "DockDoor"` because the current importer requires that marker. It does not select the destination preference domain or change the installed application's identity.

### Behavior to Review Before Importing

This is an opinionated showcase configuration, not a recommended setup for everyone. In particular, it configures Left Option + Tab, side-specific Command double taps, preview action shortcuts (including Close and Quit), numbered Spaces shortcuts, and trackpad swipe launching. Review **Gestures** and **Keybinds** after import and resolve conflicts with macOS gestures or other applications. Some appearance choices use newer macOS capabilities; results can differ by system version, display configuration, and Reduce Motion settings.

Privacy and import-format checks do not prove every interaction is appropriate on another person's Mac. Re-exported preferences must be reviewed again before publication: exports can include new private state and system metadata.

The October 20 preset retains multi-selection, drag-to-tile, linked resizing and Window Gestures; uses title-hover checkboxes, Shadowed Dock/Cmd+Tab headers, a 500-point Compact Mode width and embedded switcher controls. It preserves the supplied shortcut changes, including selection and Auto Tile actions, Minimize on M and Open New Window on N, and restores the Right Command double-tap persistent shortcut. Group Fill-to-Auto-Tile and Tile only what fits are Off. Unspecified settings use application defaults after import, including the 2-row/3-column Auto Tile limits. Some older scroll gestures are unavailable while Window Gestures is enabled. Existing full-size-preview and trackpad settings are retained. Action and cursor feedback are now enabled, with Based on trigger type placement and Different display only cursor following. This is a deliberate showcase setup, not a change to application defaults. The preset has not been imported into live settings. Release packaging is authorized; candidate validation and pending manual tests belong to the 0.3.0 handoff record.

## Public Testing Repository

[hexcrete/DockFork](https://github.com/hexcrete/DockFork) is a public GitHub fork of ejbills/DockDoor. The published fork branch is `better_dd_merged`; it is the default branch. `main` remains the upstream baseline rather than the fork's development branch. Local backup branches are not part of the publication.

The local `origin` remote continues to point to upstream. The separate `fork` remote points to DockFork, and ordinary pushes from the development branch target it. GitHub CLI's local default repository is DockFork; use an explicit upstream repository when preparing a separately approved contribution. Do not submit this full branch upstream.

At initial fork publication, inherited GitHub Actions were disabled pending fork-specific CI and automation review. This prevents upstream-specific translation/release automation from being treated as tested fork infrastructure. Issues are enabled for tester feedback. [The first prerelease](https://github.com/hexcrete/DockFork/releases/tag/v0.1.0) is now published, using the exact tested candidate. Screenshots and recordings will be assembled during testing, and none are marked captured merely because the repository is public.

## 0.2.0 Publication Record

Published October 17, 2026: [DockFork 0.2.0 prerelease](https://github.com/hexcrete/DockFork/releases/tag/v0.2.0), tag `v0.2.0`, resolves to the exact audited candidate source `c863e628d17d8c80985cd77533ff94db03d6444a`. A fresh fetch confirmed upstream main remained `3e08721ec56c6747dba04561ab57b03ec254d785`; no new merge or rebuild was needed. Exactly ten allowlisted assets were uploaded to a draft, downloaded with authentication and verified byte-for-byte against the local package, then published after the user's authorization. The remote annotated tag target, public non-draft/prerelease state and unchanged public release notes were verified. All ten public asset links returned HTTP 200; an anonymous app-ZIP download matched SHA-256 `7c9456e9a7875f8fce593bf0877087cc0d83bd8b1460d2071a3d986d7ebe2263`. The 246-preference/15-shortcut optional preset, source archive, overlay, license, installation guide and metadata remain those of the audited candidate. No development app, build log, signing certificate, private note or unlisted asset was uploaded. The fork's Actions are disabled; no inherited changelog workflow was triggered or changed. The original 0.1.0 release and upstream repository remain untouched. No application rebuild, installation, launch, preference import or media capture accompanied publication. The user's upgrade-permission observation is documented, not treated as exhaustive 0.2.0 feature testing. A command-line download does not test browser quarantine or Gatekeeper approval; that installation check, older-OS compatibility and screenshots remain pending.

## 0.3.0 Candidate Handoff, October 20 (Historical)

The committed-source candidate `6d3eb4707c7db4446c78786e8df6ceec279be7b2` is ready for manual testing, not published. Package: `fork/dist/DockFork-6d3eb47-uH0xrM/DockFork-0.3.0-6d3eb47-arm64.zip`. ZIP SHA-256: `c4d3a78a0a12a5de6854f9afd574ceb1032eed6ab0e6a3ad1b8d5583fb1fbe11`. It is arm64, ad-hoc signed and not notarized, with DockDoor stable base 1.41.0 plus upstream history through `77e4771`. All sixteen regression suites, 19 version cases and cleanup checks pass; the unchanged native Compact Mode title hit test needed one retry. All 257 artifact assertions pass, including exact source/sidecars, checksums, ZIP correspondence and signatures. The 477-file unpacked marker scan found no configured private-data markers; it is not comprehensive secret/malware certification. The sanitized preset has 249 preferences and 15 generic-ID shortcut rows, enabling the three supplied feedback preferences. It is optional and was not imported. The Release app was not installed/launched; the running development executable is unchanged. No push, tag, draft, upload or publication occurred. Manual upgrade/import, actual Release features, browser quarantine and broader display/OS coverage remain pending. Screenshots are deferred. See the [full handoff and asset allowlist](docs/RELEASE_NOTES_0.3.0.md#candidate-handoff). Future approval must refer to this exact package rather than a rebuild.

## 0.3.0 Publication, October 20

[DockFork 0.3.0](https://github.com/hexcrete/DockFork/releases/tag/v0.3.0) was published at 2026-10-20T20:15:17Z with explicit user authorization. Tag `v0.3.0` points to exact source `6d3eb4707c7db4446c78786e8df6ceec279be7b2`. The audited candidate was uploaded without rebuilding. All ten draft downloads and all ten anonymous public downloads match the local package byte-for-byte. The release is marked prerelease, uses the approved public body and omits logs, development builds and signing material. Previous release assets are unchanged.

No application installation, launch, live settings import or media capture accompanied publication. Manual candidate upgrade/import, browser quarantine/Gatekeeper approval, older OSes and broader display coverage remain unverified. Command-line downloads do not establish those results. See the [full publication record](docs/RELEASE_NOTES_0.3.0.md#publication-record).

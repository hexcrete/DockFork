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

## Build a DockFork Package

The packaging script is a fork-only CLI distribution workflow, not a replacement for upstream's Xcode development instructions. Building requires macOS 27 and Xcode 27 or later, with Xcode selected as the active developer directory. Initial dependency resolution requires network access. No Apple account is required for this ad-hoc-signing workflow.

```sh
./fork/package.sh
# Optional release version override:
./fork/package.sh --version 1.0.0
# Inspect the isolated source overlay without building:
./fork/package.sh --prepare-only
# Local testing of tracked, uncommitted source changes (not a release):
./fork/package.sh --include-working-tree
```

By default the script uses **committed HEAD**, not uncommitted application changes or the local Dev project identity. `--include-working-tree` is an explicit local-test exception: it applies tracked changes in `DockDoor`, `Assets`, `BuildTools`, and `DockDoorTests`, records them in `WORKING-TREE.patch`, and labels the output `working`. It excludes untracked files and project-file changes. Do not publish these test builds; commit reviewed changes and rebuild normally for release. The script reads the packaging patch, entitlements, installation guide, and optional preset from this checkout. Commit and review those assets before publishing a release. A future upstream change that invalidates the overlay stops packaging rather than silently skipping it.

Each invocation creates a unique directory under `fork/dist/` (or `--output DIRECTORY`). Temporary build sources and derived data are deleted afterward. The original project is not edited. Packaging does not install, launch, import preferences, publish, or push anything.

The resulting app uses `DockFork.app`, executable `DockFork`, and bundle/preference identity `io.github.hexcrete.DockFork`. Its Swift module and scripting command names remain DockDoor-compatible. The overlay disables Sparkle construction and replaces update checks with manual fork-release downloads; upstream feed/signing keys are removed. Diagnostics use a separate DockFork directory. See [installation and signing limitations](packaging/INSTALL.md).

### Fork and Upstream Versions

`version.json` keeps four independent fields: `forkVersion`, `upstreamRelease`, `upstreamReleaseCommit`, and `upstreamCommit`. The initial, unpublished DockFork version is `0.1.0`; the current base is DockDoor release `1.40.7` plus upstream changes through `7be384b`. Upstream's Xcode project still says `1.18.3`; it is not the published release version and is no longer used as DockFork's default version.

Support > Updates displays the DockFork version and a separate `Based on DockDoor 1.40.7 + upstream changes · 7be384b` line. The full base hash is available by hovering over that line. An exact release base omits `+ upstream changes`. These values are embedded during packaging, not fetched at runtime. Standard DockDoor builds remain unchanged.

After an upstream merge:

1. Fetch the upstream release tags, then choose the newest **published stable release already included** in the incorporated upstream commit. Do not simply use GitHub's latest release if it is not merged.
2. Record the release version, its full tag commit (`git rev-parse <release-tag>^{commit}`), and the full incorporated upstream commit in `version.json`.
3. Keep `forkVersion` independent. Update it for a fork release, or use `--version X.Y.Z` for a one-build override without editing the record.
4. Review the diff, run `ruby fork/packaging/tests/version_metadata_test.rb`, build, and verify the displayed base before publishing.

Packaging requires complete local Git history and the pinned release tag. If a clone lacks that tag, fetch it from the official repository (for the current record: `git fetch https://github.com/ejbills/DockDoor.git tag 1.40.7`). The validator checks release-tag identity, release-to-base and base-to-build ancestry, and any newer included stable tags. If a remote points to the official DockDoor repository and has a `main` tracking ref, it also checks that the recorded base matches the merged remote history; fetching unmerged upstream changes does not change the label. Without such a remote, ancestry/tag checks still run offline, but confirming freshness of the base remains part of merge review. Shallow clones may need their history completed.

Release mode reads the record from committed HEAD; local test/development mode reads the working record. The existing source-only exclusion still applies to untracked app files, but packaging explicitly uses its current fork-only assets, including this record and the validator. Commit and review those assets before a release. The script embeds version/base values in the isolated app's Info.plist and verifies them after building, without changing the source project. `BUILD-METADATA.json` records the effective fork version, upstream release/base hashes, source commit, and whether later upstream commits are included.

### Window State and Spaces Defaults

The application's preference declarations supply these defaults for the added features in both DockDoor and DockFork builds, with existing preference key names unchanged:

- Dock, Window Switcher, and Cmd+Tab: window state/Space indicator dock styling enabled; swap with traffic lights enabled, limited to Compact Mode.
- Spaces dropdown: show the Current badge and unavailable Spaces.

These are fallbacks for unset preferences, not a migration or forced configuration. Saved or imported choices take precedence; resetting the corresponding settings restores these defaults. The packaging overlay does not override them.

### Stable Local Development Build

```sh
./fork/package.sh --dev
# If multiple Apple Development certificates are available:
./fork/package.sh --dev --signing-identity CERTIFICATE_SHA1
```

This local-only mode builds Debug with tracked working-tree source changes and uses your installed Apple Development certificate. With exactly one valid development identity, selection is automatic; otherwise select its SHA-1 from `security find-identity -v -p codesigning`. No account name or certificate fingerprint is stored in tracked files, and no certificates or private keys are exported. macOS may request access to the signing key.

After successful build and signature verification, the script gracefully quits any running DockFork instance, replaces `fork/dist/dev/DockFork.app`, and launches that fixed app path. It does not quit DockDoor, clear preferences, or modify the source project. The whole `fork/dist/` directory is gitignored. Quit DockDoor yourself if it is running, to avoid competing shortcuts.

Changing from ad-hoc signing may require granting permissions once again. Later builds should retain them while the signing certificate, designated requirement, bundle ID, and installed path remain compatible. Replacing or expiring the certificate, changing identity, or returning to an ad-hoc package can require approval again. A development certificate is not Developer ID distribution signing or notarization.

Development mode creates no release ZIP and must not be distributed; its signature identifies your development account. Run the ordinary packaging command separately for the initial ad-hoc release workflow.

The local Debug build, nested certificate-signature checks, fixed-path replacement, and launch have passed. Its designated requirement is certificate-based, not tied to a binary hash. Permission retention across subsequent builds still needs verification after granting access to this signed build.

### Release Assets and Validation

Publish these together after testing the package:

- `DockFork-<version>-<commit>-arm64.zip`: ad-hoc-signed Apple Silicon app.
- `DockFork-<commit>-source.tar.gz`, `DockFork.patch`, and `SOURCE-COMMIT.txt`: exact committed source and the applied overlay.
- `INSTALL.md`, `LICENSE`, `SHA256SUMS.txt`, and `PACKAGING-PATCH-SHA256.txt`.
- `BUILD-METADATA.json`: effective version and exact upstream/source ancestry for this package.
- `DockFork-Showcase.json`: optional preferences, never automatically imported.

Keep `build.log` local: it can contain developer paths and is not a release asset. Do not publish the entire output directory indiscriminately. A successful signature verification establishes package integrity, not Developer ID trust or notarization.

Before release, quit the Dev instance and test DockFork's fresh permissions, independent preferences, all three preview modes, shortcuts, widgets, diagnostics export, and `tell application "DockFork"` scripting. Verify the update button opens the fork releases rather than upstream. Test the downloaded/quarantined ZIP on another Mac as well. Building with a macOS 13 deployment target does not itself prove compatibility with macOS 13; supported versions require runtime testing.

No release has been published. Source-only preparation, the complete Release build, nested ad-hoc signature verification, ZIP integrity, checksums, and local launch have passed. Manual feature testing and downloaded/quarantined installation validation remain pending.

Release validation, October 11, 2026: a committed-source candidate from `82f0a06600861d1a8fa9cf9fd024e1d61a273952` passed the arm64 Release build on macOS 27.0.1 / Xcode 27.0. All nine asset checksums, ZIP integrity, unpacked nested signatures, and all 219 bundle entries' contents, modes, and symlinks passed verification. Its source archive matched the committed tree; the packaging patch applied cleanly, and the bundled license, preset, and installation guide matched their source files. Embedded identity/version/source metadata and absence of the upstream updater feed were verified. This candidate predates the latest preset and label updates.

A later local test candidate used `--include-working-tree` to build the renamed swipe setting and attach the refreshed 237-setting preset. All ten asset checksums (including `WORKING-TREE.patch`), ZIP integrity, unpacked nested signatures, 219 bundle entries, preset correspondence, source-patch reconstruction, and identity/version checks passed. The committed archive plus the supplied patch reconstructs its changed app sources. All 19 version-metadata tests passed. These test candidates use DockFork `0.1.0`, based on DockDoor `1.40.7` plus changes through `0bd2e46`.

Neither earlier candidate was installed or launched; the running development app and preferences were left untouched. They remain ad-hoc signed, not notarized. The full Xcode test suite, clean-account/second-Mac installation, downloaded/quarantined installation, update/permission behavior, and minimum-OS runtime compatibility remain unverified. The build emits Swift 6 compatibility warnings in the current Swift 5 language mode; this is not a warning-free build. Build the final publication candidate from committed HEAD without `--include-working-tree`. Generated assets and logs remain gitignored under `fork/dist/`; publish only the asset allowlist above, never `build.log` or the entire directory.

Previous committed-source candidate, October 11, 2026: `9fcf28dbb82334e40ff7141d2b16e3661f9755b2` passed the arm64 Release build and includes the shared preview-centering and scroll-hit-target fixes plus the refreshed optional preset. All nine asset checksums, ZIP integrity, unpacked nested ad-hoc signatures, all 219 bundle entries (contents, modes, and symlinks), source archive correspondence, clean packaging-overlay application, preset/license/install-guide correspondence, identity/source/upstream metadata, and disabled upstream updater feed passed verification. All 19 version-metadata tests passed. Output: `fork/dist/DockFork-9fcf28d-aXldXK/DockFork-0.1.0-9fcf28d-arm64.zip`. The Release app was not installed or launched; the preset was not imported, and downloaded/quarantined installation testing and publication remain unperformed. The running signed development build and live preferences were left unchanged.

Upstream integration `325ef3f` now records base `7be384b` with latest included stable release 1.40.7. It incorporates upstream native-tab focus caching and Dock indicator stabilization plus beta appcast metadata; DockFork still does not use the upstream updater. The October 11 candidate above predates this merge; the October 12 candidate below incorporates it. User manual merge verification passed; no new Release installation test is inferred.

## Optional Showcase Preset

[DockFork-Showcase.json](presets/DockFork-Showcase.json) provides a sanitized example configuration. It is not the application's default configuration and must not be imported automatically. Attach this same JSON as a separate optional asset when creating the release; no release has been published yet.

To try it, first export your existing settings, then use **General > Backup & Restore > Import Settings** in the fork build. Import replaces the current preference domain rather than merging only the included settings, and the app asks to restart. Omitted settings return to their defaults. Use a separately identified DockFork build; this preset alone does not isolate preferences from DockDoor.

### Privacy Review

The current preset was refreshed and privacy-reviewed October 11, 2026. It retains 237 recognized preference keys from the latest 241-key export. Review included nested JSON stored inside shortcut strings, not just the outer JSON.

- Removed four private-state or system keys: the file-dialog directory bookmark, save-panel geometry, cached screen-recording permission, and the reopen-settings flag. This latest export contains no saved window order or window-title/focus history. No folder-specific sort dictionary or other opaque payload remains.
- Removed the exact export timestamp. Retained the nonpersonal format identifier and application version used for compatibility information.
- Verified all 15 shortcut-row UUIDs already use unique generic stable IDs; key combinations, actions, and scopes are unchanged.
- Kept debug logging off.
- Retained the generic `launched: true` flag to avoid replaying first-run onboarding after import. It contains no identifying information and does not grant macOS permissions; permission history remains excluded.
- No remaining file paths, bookmarks, binary payloads, account identifiers, email addresses, URLs, or window titles were found in the prepared preset.

The envelope intentionally retains `"app": "DockDoor"` because the current importer requires that marker. It does not select the destination preference domain or change the installed application's identity.

### Behavior to Review Before Importing

This is an opinionated showcase configuration, not a recommended setup for everyone. In particular, it configures Left Option + Tab, side-specific Command double taps, preview action shortcuts (including Close and Quit), numbered Spaces shortcuts, and trackpad swipe launching. Review **Gestures & Keybinds** after import and resolve conflicts with macOS gestures or other applications. Some appearance choices use newer macOS capabilities; results can differ by system version, display configuration, and Reduce Motion settings.

Privacy and import-format checks do not prove every interaction is appropriate on another person's Mac. Re-exported preferences must be reviewed again before publication: exports can include new private state and system metadata.

The latest refresh (`9fcf28d`) changes only app-header style to Popover and Window Switcher app-icon size from 35 pt to Automatic compared with the previous preset (`3d1e761`). All other sanitized preferences are semantically identical. This refresh preserves the supplied appearance/interaction choices, including same-Space Dock cycling preview retention, dimmed hover-only traffic lights, embedded Dock/Cmd+Tab controls, compact-style windowless Dock/Cmd+Tab rows, and compact thresholds of five. Updated shortcut/search keys are retained. It does not change application defaults or import settings. No import test of this latest preset is recorded; packaging checks are documented under [release validation](#release-assets-and-validation).

Previous committed-source candidate, October 12, 2026: `0cabb33081550df578d6ca39569d3a65ae6d0bb8` passed the arm64 Release build and includes upstream through `7be384b` plus both final-review safety fixes. All nine checksums, ZIP integrity, extracted nested ad-hoc signatures, all 219 bundle entries (contents, modes, symlinks), byte-exact committed source archive, clean overlay application, committed preset/license/install-guide/patch correspondence, source/upstream metadata and disabled upstream updater feed were verified. The 19 version-metadata cases passed. Output: `fork/dist/DockFork-0cabb33-amzRCD/DockFork-0.1.0-0cabb33-arm64.zip`. The Release app was not installed, launched, or published; the preset was not imported. Downloaded/quarantined installation, manual Release feature testing, and minimum-OS compatibility remain pending. The signed development instance and live preferences remained unchanged. A later documentation-only commit records this validation; it does not change the candidate's app sources or embedded source identity.

## Public Testing Repository

[hexcrete/DockFork](https://github.com/hexcrete/DockFork) is a public GitHub fork of ejbills/DockDoor. The published fork branch is `better_dd_merged`; it is the default branch. `main` remains the upstream baseline rather than the fork's development branch. Local backup branches are not part of the publication.

The local `origin` remote continues to point to upstream. The separate `fork` remote points to DockFork, and ordinary pushes from the development branch target it. GitHub CLI's local default repository is DockFork; use an explicit upstream repository when preparing a separately approved contribution. Do not submit this full branch upstream.

Inherited GitHub Actions are disabled while fork-specific CI and automation are reviewed. This prevents upstream-specific translation/release automation from being treated as tested fork infrastructure. Issues are enabled for tester feedback. No GitHub Release has been published yet; the verified local candidate is available for the separately approved first prerelease. Screenshots and recordings will be assembled during testing, and none are marked captured merely because the repository is public.

October 12 testing follow-up: Import Settings stalled in macOS file-panel initialization in the running development instance, not an installed Release. Import/Export deferral fix `4fdaa56` passed the signed Debug build/relaunch and the user reported it working. The existing `0cabb33` candidate does not contain this fix; rebuild and verify the Release before publishing. Full Xcode tests and Release verification of this fix remain pending. No backup was applied and no preferences reset during investigation.

Latest committed-source candidate, October 12, 2026: `36e635e8f0ad35cdd90fb390b3aa0195cefdd8b2` includes the Import/Export dialog fix and passed the arm64 Release build. All nine checksums, ZIP integrity, unpacked deep/strict ad-hoc signatures, 219 bundle entries, byte-exact source archive, overlay application, committed preset/license/install-guide/patch correspondence, source/upstream metadata and disabled upstream updater feed passed verification. All 19 version-metadata cases passed. Output: `fork/dist/DockFork-36e635e-UoauGA/DockFork-0.1.0-36e635e-arm64.zip`. Version remains 0.1.0, based on DockDoor 1.40.7 plus upstream through 7be384b. The Release app was not installed, launched or published; no preset was imported. Downloaded/quarantined installation and manual Release testing remain pending. The existing development app and preferences were not replaced. ZIP SHA-256: `22ec9f8c8bd8083b15f9d2983b5603cf689241f7a81b7c517d4ad41d5e30e0d5`.

Prerelease preparation, October 12, 2026: the user reports successful testing of the `36e635e` Release candidate on additional Macs running macOS 27, using locally transferred packages. Specific hardware configurations and individual feature scenarios are not inferred. Downloaded/quarantined Gatekeeper installation remains pending. A repeated privacy check scanned 431 app/source files and ZIP sidecar metadata, plus all 237 showcase preferences including nested shortcut JSON. No configured credential markers, private home paths, personal signing identities in the app, or private preset payloads were found. Upstream attribution, public GitHub identities, an upstream translation placeholder, and Sparkle's generic CI paths are intentional; this is not a comprehensive secret-scanner certification. All nine asset checksums passed again. Only the documented release-asset allowlist will be uploaded; development builds, logs and private notes remain excluded. Publication is not yet complete.

# DockFork 0.4.0 Candidate Preparation

Status: stable Release candidate built and artifact-audited; **not published or approved for publication**. The user authorized packaging after upstream merge verification. No prerelease flag is intended. Do not tag, upload or publish until the exact candidate is tested and approved.

## Release Inputs

- Public title: DockFork 0.4.0 - Spaces Bar and Preview Refinements.
- Public body: [RELEASE_BODY_0.4.0.md](RELEASE_BODY_0.4.0.md). Compare changes with published v0.3.0, not intermediate local candidates.
- Upstream main through `3044142c907b9cdd49917628847a04970450a8e6`; newest included stable release 1.41.0 at `3d6a3cbaa9bbee17959122da7f0a349ca43056d0`. Included beta 1.41.1b1 is not the stable base.
- Fork identity/signing workflow remains unchanged: Apple Silicon Release, ad-hoc signed, no notarization or automatic updater. Stable status does not change macOS trust/permission behavior.
- Roadmap removed by request, with links and maintenance instructions updated. Superseded draft public notes removed; historical packaging/commit evidence retained.
- Screenshots/recordings deferred, not claimed captured or approved.

## Preset Review

The supplied October 27 export is sanitized to 273 known preferences and 15 shortcut rows. Remove NSNavPanelExpandedSizeForSaveMode, NSOSPLastRootDirectory, lastKnownScreenRecordingPermission and reopenSettingsAfterRestart. Force debugMode Off, replace row IDs with deterministic generic UUIDs, and set the backup appVersion to 0.4.0. Preserve the DockDoor importer marker, format version and all other settings/shortcut behavior. No import or live preference change. The original export is untouched. Retired recognized preferences remain harmless stored values; no migration is introduced.

The preset enables Spaces Bar, multi-selection, action feedback, Mouse Follows Focus feedback and title-bar scroll/tab gesture filtering. It uses numeric Flexible pills, min/max 2/6, per-mode toolbar indicators and minimal-reveal keyboard scrolling. These are showcase choices, not fresh defaults. Export a backup before importing; import replaces settings.

## Validation Gate

Development features have user-reported verification, including the merged upstream controls and the direct-Close automatic-Quit exclusion follow-up. Release-preparation regressions, diff/link/privacy review and the artifact audit pass as detailed below. Do not infer exhaustive native coverage from these checks. Known native Compact drag fixture instability remains a documented test gap; no assertion was weakened or full native-suite pass claimed.

Build only after committing reviewed inputs, using `./fork/package.sh --clean-old-builds`. Record the exact source commit, output path, asset inventory, checksums, signatures and actual audit results below. Release packaging does not install or launch; leave the running development app/preferences unchanged.

## Candidate Handoff

Built October 27 with `./fork/package.sh --clean-old-builds` from exact source `23850ba04cf7c5e523d53ea2be45607419327e57`, after the compile correction described below. Output: `fork/dist/DockFork-23850ba-xZEI4i`. Later documentation-only commits do not change this candidate; do not rebuild it when approving or publishing.

The artifact audit passes 1,599 assertions across the ten allowlisted assets, 219 ZIP/app entries, seven ad-hoc-signed Mach-O files and 498 privacy-scanned app/source/sidecar files. Checks cover checksum inventory, ZIP integrity and extracted-app correspondence, nested signatures, arm64 architecture, exact committed source archive, applied overlay, sidecar correspondence, version/base metadata, updater isolation, and configured local path/development-identity/credential markers including UTF-16 encodings. This is not malware certification or an exhaustive secret scan. Build logs, the unpacked app and unlisted output files are not upload assets.

The running development executable and debug library remain byte-identical to their pre-build hashes. Release packaging did not install or launch the candidate or import the preset. The supplied export's SHA-256 remains unchanged.

After packaging, the user must test the exact ZIP as an upgrade and optionally import the preset after backing up. Browser-quarantine/Gatekeeper approval, first launch, permissions, older-macOS and exhaustive display/app coverage remain unverified until explicitly reported. After approval, tag this exact source as v0.4.0, create/verify a draft with exactly the allowlisted assets, then publish without the prerelease flag. Publication is a separate authorization step.

## Preparation Checks

Before committing inputs: 31 selected app fixtures and all three packaging fixtures pass. `space_presentation.rb --viewport-compile-only` compiles native viewport coverage without running it; `spaces_bar_presentation.rb --model-only` skips its native host animation panel. The known unstable native Compact drag fixture `preview_layout.rb` is excluded and not claimed passing. No live-window mutations were run. The feedback suite initially could not start because its extraction helper was missing; restoring the helper leaves assertions intact and the suite passes, including its owned popup panel. Full app SwiftFormat lint passes 212 files after two indentation-only lines were corrected, verified behavior-neutral with `git diff -w`.

Preset validation/correspondence and local Markdown file-target checks pass. Source export hash is unchanged, and no live preferences or installed app were modified by preparation. Upstream integration/Close correction has user-reported verification, not exhaustive new native mode/display/OS coverage. The corrected Release build and exact package audit pass; no publication is implied by these checks.

### Release-Only Compile Correction

The first Release attempt from preparation commit 314bf726 failed before packaging because Swift did not infer main-actor isolation for the weak switcher-dismissal callback. Explicitly annotate that closure @MainActor, matching its declared callback type. There is no new Task, delay or dismissal policy. The production registration now has an optimized, non-DEBUG fixture proving synchronous cancellation and weak ownership. Keyboard/registration and formatting checks pass; build the candidate from the committed correction, not the failed preparation attempt. No failed app/package is a distribution asset.

## Exact Asset Inventory

Only these files are eligible for upload after approval. All SHA-256 values were checked against the actual files.

| File | SHA-256 |
|---|---|
| `DockFork-0.4.0-23850ba-arm64.zip` | `684f1e74c391bb966f35b1c9882dbffcfcc619587d4a7cfb54b0c8c3f223ebe4` |
| `DockFork-23850ba-source.tar.gz` | `46a2bc7b2f8ceaa4235cc4a6e2361ad54ab224e4e79f17bac43bca144b3e7da3` |
| `DockFork.patch` | `a4aeb957cd9186e8dcef5db351e3a32ab72f7b080119f3d7fa0b4ae6c130d738` |
| `SOURCE-COMMIT.txt` | `b26d6662934a3e760f5fcdd9bf213b8375e298ce4818622db80e476020a806a9` |
| `BUILD-METADATA.json` | `a4d6494f508d624f1cf7b9f47147eedc36bf0232ec83c5f1f68b2b9f67f13801` |
| `INSTALL.md` | `3a639703ea4c094b187caf7cbf409c70595f09763f1e9fc140e102c504554608` |
| `LICENSE` | `c9713c9a9bb0b0373d344ce216ead29f9410e705609351bdbf61f8c747125dd5` |
| `DockFork-Showcase.json` | `fd467fb6f670ea6fd04e7f3e62ffed1c0bf1091f34a085d9244abb43d03986e6` |
| `PACKAGING-PATCH-SHA256.txt` | `96a6db7f9211e6096e5965a892669b6280c2364afaf0abe7ea5307b4a5bb97ba` |
| `SHA256SUMS.txt` | `a2980001cbcd768585ef7f410a01f2222f6dc532bf1a595f708d3853dbdc7f36` |

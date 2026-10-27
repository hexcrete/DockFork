# DockFork 0.4.0 Candidate Preparation

Status: preparing a stable release candidate; **not published or approved for publication**. The user authorized packaging after upstream merge verification. No prerelease flag is intended. Do not tag, upload or publish until the exact candidate is tested and approved.

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

Development features have user-reported verification, including the merged upstream controls and the direct-Close automatic-Quit exclusion follow-up. Do not infer exhaustive upstream/native coverage from the last fix test. Release-preparation regressions, final diff/link/privacy review and actual candidate audit are pending. Known native Compact drag fixture instability remains a documented test gap; no assertion will be weakened or full native-suite pass claimed.

Build only after committing reviewed inputs, using `./fork/package.sh --clean-old-builds`. Record the exact source commit, output path, asset inventory, checksums, signatures and actual audit results below. Release packaging does not install or launch; leave the running development app/preferences unchanged.

## Candidate Handoff

Pending build. Audit the ten allowlisted assets listed in [the build guide](../README.md#release-assets-and-validation). Exclude build logs, unpacked/development apps, private notes and unlisted files. Confirm byte-for-byte source/preset/license/installation/overlay correspondence, ZIP integrity, nested signatures, metadata/updater isolation and privacy markers including binary/UTF-16 local paths and development identities. An audit is not malware certification.

After packaging, the user must test the exact ZIP as an upgrade and optionally import the preset after backing up. Browser-quarantine/Gatekeeper approval, first launch, permissions, older-macOS and exhaustive display/app coverage remain unverified until explicitly reported. After approval, tag this exact source as v0.4.0, create/verify a draft with exactly the allowlisted assets, then publish without the prerelease flag. Publication is a separate authorization step.

## Preparation Checks

Before committing inputs: 31 selected app fixtures and all three packaging fixtures pass. `space_presentation.rb --viewport-compile-only` compiles native viewport coverage without running it; `spaces_bar_presentation.rb --model-only` skips its native host animation panel. The known unstable native Compact drag fixture `preview_layout.rb` is excluded and not claimed passing. No live-window mutations were run. The feedback suite initially could not start because its extraction helper was missing; restoring the helper leaves assertions intact and the suite passes, including its owned popup panel. Full app SwiftFormat lint passes 212 files after two indentation-only lines were corrected, verified behavior-neutral with `git diff -w`.

Preset validation/correspondence and local Markdown file-target checks pass. Source export hash is unchanged, and no live preferences or installed app were modified by preparation. Upstream integration/Close correction has user-reported verification, not exhaustive new native mode/display/OS coverage. Release build and exact package audit remain pending below; no publication is implied by these checks.

### Release-Only Compile Correction

The first Release attempt from preparation commit 314bf726 failed before packaging because Swift did not infer main-actor isolation for the weak switcher-dismissal callback. Explicitly annotate that closure @MainActor, matching its declared callback type. There is no new Task, delay or dismissal policy. The production registration now has an optimized, non-DEBUG fixture proving synchronous cancellation and weak ownership. Keyboard/registration and formatting checks pass; build the candidate from the committed correction, not the failed preparation attempt. No failed app/package is a distribution asset.

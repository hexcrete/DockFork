# DockFork 0.5.0 Release Candidate

Status: publication authorized by the user after reviewing the corrected release notes. Publish the existing audited package without rebuilding. Published 0.4.0 assets remain unchanged.

## Inputs

- Public release body: [RELEASE_BODY_0.5.0.md](RELEASE_BODY_0.5.0.md), compared with published v0.4.0.
- Attribution review separates upstream Settings/pinned previews, multiple Alternate Shortcuts and combined modifiers from fork extensions and repairs. Existing Double-tap is not presented as new. This public-copy correction does not change the audited package or its source identity.
- Fork version 0.5.0; Apple Silicon, ad-hoc signing, unchanged application identity and manual updates.
- Upstream through c58cf6c0ca0d0e35388ac8aa4790c80c5fbccfb8; newest contained stable release 1.42.2 at b6beb0129e9d7b59f2995eafc0d69ce272d7d129. The incoming 1.42.3b1 appcast is beta, not the stable base.
- November 4 export sanitized without importing or modifying the original file. Generic shortcut UUIDs, debug logging Off, no system/private state or retired preferences. The sole maintained preset is replaced in place; historical published packages are preserved.
- Screenshots remain deferred. Capture IDs and media approval states are unchanged.

## Validation and Approval

Automated/source checks do not establish downloaded/quarantined installation, permission continuity, preset import, exhaustive displays, older macOS or accessibility coverage. The user authorized publication; no additional installation or compatibility testing is inferred from that approval.

Preset audit: 270 recognized preferences and 15 shortcut rows. Removed 13 obsolete/private entries: `lastFocusedWindowShortcuts`, `lastKnownScreenRecordingPermission`, `NSNavPanelExpandedSizeForSaveMode`, `NSOSPLastRootDirectory`, `persistentSwitcherShortcuts`, `persistentSwitcherStartsUnfocused`, `reopenSettingsAfterRestart`, `showDockPreviewSpaceNumberIndicator`, `showSpaceNumber`, `showSwitcherSpaceNumberIndicator`, `spacesBarMaximumWidth`, `spacesBarMinimumWidth`, `spacesBarPreferDetails`. Only one maintained preset exists; replace it rather than retain an invalid current-version copy. Original Downloads export and historical Release archives are not deleted.

## Exact Candidate

- Source: `5da345933511899c2c315a7c2a2edbb1be63244b`.
- Local output: `fork/dist/DockFork-5da3459-NVxV9w`.
- Package: `DockFork-0.5.0-5da3459-arm64.zip`.
- ZIP SHA-256: `883b49baf2e5977fa3a91ceffde3a62c80aba4be71cfbda35f493dfbecfe5374`.
- Preset SHA-256: `93931f58dd8cc61a9d52becb9e166cdcad8fa346d4629a542f2cc47ddef765e4`.

`./fork/package.sh --clean-old-builds` built committed Release sources without installing or launching them. ZIP integrity and all nine checksum-manifest entries pass. The extracted app matches all 220 original bundle entries, including file modes, symlinks and bytes. Strict deep signature verification passes; all seven Mach-O files use ad-hoc signatures. The executable is arm64, has the unchanged DockFork identity and embeds the recorded source/upstream versions. Automatic updates remain disabled. No development marker, coverage instrumentation or checked private build-path strings occur in the distributed binaries.

The source archive matches `git archive` of the exact source commit. Its packaging overlay applies cleanly. The preset, overlay, installation guide and license match committed inputs. Only the ten allowlisted assets in the build guide are eligible for eventual upload; the app directory and build log stay local.

## Preparation Checks

Twelve focused suites pass: showcase preset, upstream integration, settings merge, settings mock previews, preview keyboard, preview publications, preview idle cleanup, preview batch reconciliation, preview chrome measurements, action ownership, native-tab Close and Wine discovery. Packaging cleanup, development-option and version-metadata tests also pass, including 19 version cases. `git diff --check` passes. Preparation changes no Swift source, runtime defaults, project configuration or signing policy.

No live UI inspection, working-window manipulation, preset import or Release launch was performed during preparation. Existing manual approvals apply to the development implementation, not installation of this exact ZIP. Before publication, test the extracted Release app's launch/permissions, unified shortcuts, pinned examples, Spaces Bar and normal actions. Import the optional preset only after exporting a backup. Download/quarantine, multi-display, VoiceOver and older-macOS coverage remain separate checks, not inferred from this build.

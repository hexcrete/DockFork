# DockFork 0.5.0 Release Candidate

Status: stable release candidate in preparation, not published. User approval is required before tagging, uploading or publication. Published 0.4.0 assets remain unchanged.

## Inputs

- Public release body: [RELEASE_BODY_0.5.0.md](RELEASE_BODY_0.5.0.md), compared with published v0.4.0.
- Fork version 0.5.0; Apple Silicon, ad-hoc signing, unchanged application identity and manual updates.
- Upstream through c58cf6c0ca0d0e35388ac8aa4790c80c5fbccfb8; newest contained stable release 1.42.2 at b6beb0129e9d7b59f2995eafc0d69ce272d7d129. The incoming 1.42.3b1 appcast is beta, not the stable base.
- November 4 export sanitized without importing or modifying the original file. Generic shortcut UUIDs, debug logging Off, no system/private state or retired preferences. The sole maintained preset is replaced in place; historical published packages are preserved.
- Screenshots remain deferred. Capture IDs and media approval states are unchanged.

## Validation and Approval

Candidate source and exact artifact audit will be recorded after packaging. Automated/source checks do not establish downloaded/quarantined installation, permission continuity, preset import, exhaustive displays, older macOS or accessibility coverage. The exact Release build requires user testing. No publication is authorized by preparation.

Preset audit: 270 recognized preferences and 15 shortcut rows. Removed 13 obsolete/private entries: `lastFocusedWindowShortcuts`, `lastKnownScreenRecordingPermission`, `NSNavPanelExpandedSizeForSaveMode`, `NSOSPLastRootDirectory`, `persistentSwitcherShortcuts`, `persistentSwitcherStartsUnfocused`, `reopenSettingsAfterRestart`, `showDockPreviewSpaceNumberIndicator`, `showSpaceNumber`, `showSwitcherSpaceNumberIndicator`, `spacesBarMaximumWidth`, `spacesBarMinimumWidth`, `spacesBarPreferDetails`. Only one maintained preset exists; replace it rather than retain an invalid current-version copy. Original Downloads export and historical Release archives are not deleted.

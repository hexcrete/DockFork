# DockFork 0.2.0 Prerelease Draft

Status: preparation only, October 14, 2026. No 0.2.0 tag, Release candidate or publication is recorded. The implementation review boundary is `dd28db3f3c016b9afeee616088a612f06eefbec8`; packaging must use committed HEAD after these preparation records are reviewed and committed.

## Release Notes

DockFork is a GPL-3.0 fork of [DockDoor](https://github.com/ejbills/DockDoor). This second testing release adds ordered multi-window selection, group actions and tiling to the existing preview, shortcut and Space-management features.

### New Since 0.1.0

- Select multiple real windows in Dock, Window Switcher and Cmd+Tab previews. Checks follow selection order and survive filtering. Use circular title/icon controls, an assigned Toggle Window Selection shortcut or mouse action, or Command-click in eligible persistent switchers. Select All affects the currently displayed, filtered windows.
- The selection summary is enabled by default and shows selected and outside-view counts, with Select All, Clear Selection and Tile Windows in all preview modes. Window Switcher also has one right-aligned app icon per checked window, including repeated apps; +N counts windows omitted from the icon strip. Narrow summaries hide icons, shorten the count, change Tile Windows and then the other buttons to glyphs, and finally scroll horizontally. The count and every action remain available. A separate option keeps Window Switcher open when windows are selected; normal held-modifier behavior remains the default.
- Apply preview actions and confirmed Space moves to checked groups. Mixed groups minimize or hide when any applicable target is restored or visible, and restore only when all applicable targets are minimized or hidden. Group fullscreen actions exit existing fullscreen members; fullscreen entry remains single-window.
- Dock/Cmd+Tab App Header Close All and Minimize All remain app-wide regardless of selection; their controls switch to glyphs and then horizontal scrolling when space is limited. Header names follow the configured overflow style and fall back to icon-only when too narrow for readable text. Use selection-aware traffic lights or Tile Windows to act on checked windows only.
- Drag checked windows together across Desktops and displays, with an ordered app-icon ghost and confirmed placement. Optional drop-to-tile puts the target window/group first, followed by the dragged selection.
- Auto Tile Selected Windows and directional Half/Quarter actions arrange groups in selection order. Configure row/column limits up to 6, with default limits of 2 rows and 3 columns. Overflow is arranged in repeated batches; a single-window Auto Tile fills the display. Applications can enforce minimum sizes.
- Existing AppleScript window actions accept an ordered list of window IDs where applicable. Batch scripts do not require UI selection; existing single-window syntax remains supported. Tile Windows exposes ordered tiling directly.

Multi-window selection, selection-driven keep-open behavior and drop-to-tile default Off. Show selection summary defaults On, but appears only with selection enabled and at least one checked window. Enable selection under **Gestures & Keybinds > Window Selection & Tiling**. Configure drag-to-tile under **Mouse Actions**. Existing saved settings and the optional showcase preset are not changed automatically.

### Fixes and UI Polish

- Adapt preview toolbars to narrow widths: shorten/omit title text, progressively overflow rightmost traffic-light actions and consolidate Space/state controls into native More menus, then reuse the selection-control location while preserving app icons and selected-state outlines. Preview and menu-bar action menus share Space/state information, with Move to Space before Arrange. Shared selection controls expose native selected-state accessibility metadata.

- Keep Shadowed app headers and their mouse-safe zone below the menu bar when preview panels reach the top of the screen.

- Keep pending cache validation separate for each app so large multi-app close groups do not cancel one another's stale-window cleanup.

- Correct Compact Mode drag-target shapes and highlight opacity.
- Extend the configurable traffic-light transition duration to 0.5 seconds while preserving Reduce Motion behavior.
- Acknowledge the one-time Cmd+Tab focus hint after actual preview focus. Hide app-header window actions when an app has no real windows.
- Improve contrast for embedded switcher titles with shared appearance-aware shadows. Add a native search clear button that works after repeated panel reuse.
- Limit Dock cycling to the active, visible app with multiple real windows. Inactive, single-window and windowless clicks retain native activation/reopening, while preview retention applies only to actual cycles.
- Avoid false five-second AX backoff during app startup and preserve explicitly identified window focus timestamps through discovery.
- Include Shadowed headers and selection summaries in hover and outside-click interaction bounds, without changing their appearance or adding timers. Header/summary button clicks no longer fall into the fixed transparent-margin exclusion; user verification of this latest correction passed, with final no-change publication guards checked in isolation and by a signed Debug build.

These are highlights, not the complete list. See the [changes guide](CHANGES_AND_SHOWCASE.md) and [commit ledger](COMMIT_LEDGER.md). Screenshots and recordings remain optional and have not been marked captured.

### Installation and Limitations

- Planned distribution: Apple Silicon, ad-hoc signed, not notarized, with manual updates. Follow the [installation guide](../packaging/INSTALL.md); do not disable Gatekeeper.
- Quit other DockDoor/DockFork instances before launching. Export settings before upgrading or importing the optional preset. Import replaces settings. A rebuilt ad-hoc release can require permission approval again.
- Partial batch failures are reported; successful members are not rolled back. Fullscreen and multi-Desktop sources have operation-specific restrictions. Overflow batches intentionally overlap earlier batches.
- Spaces Bar, pinned floating windows and the slide-out switcher are not included. Experimental full-size-preview container fading remains Off by default with known hover limitations.
- Development testing covers signed Debug builds, focused native/model checks and user-reported verification. The 0.2.0 Release build, downloaded/quarantined installation and older-macOS compatibility are not yet verified. Earlier 0.1.0 testing does not certify this release.

Report problems through this fork's Issues page. Review diagnostic logs for private information before attaching them.

## Preparation Checks

October 14: the 0.2.0 certificate-signed Debug build passed signature verification and is running from the fixed development location. Its binary matches the new build. All 19 version-metadata cases and formatter lint on the six touched Swift files passed; local Markdown file links and diff formatting passed. Git verification confirms exact-once ledger coverage of 268 commits through `dd28db3`. The showcase preset is byte-for-byte unchanged. User-reported summary/icon/header checks are recorded in the changes guide; these preparation checks add no manual feature or Release installation tests. The preparation commit itself is outside the ledger boundary and will be recorded in the next update.

## Publication Gate

- Review and commit preparation changes, including `fork/version.json`; then build with `./fork/package.sh` from committed HEAD.
- Record the exact source commit and final package directory. Verify version/base metadata, app identity, ZIP integrity, source/patch correspondence, nested signatures and every allowlisted asset checksum.
- Run a fresh privacy audit of the actual app, source archive and sidecar assets. Keep development signing identities, build logs, local paths and private notes out of distributed assets.
- Test the actual Release candidate, including preview modes, selection, batch actions, tiling, dragging, AppleScript, fresh-launch recency, search and header hover dismissal. Record test gaps rather than inferring them from Debug results.
- Obtain explicit upload/publication authorization. Tag the reviewed candidate commit, create a draft prerelease, verify uploaded assets, then publish. Do not retag or replace the tested 0.1.0 assets.
- After publication, separately test a browser-downloaded, quarantined ZIP on another Mac, including Gatekeeper, first launch, permissions, upgrade and settings import.

The current upstream record remains DockDoor 1.40.7 plus incorporated changes through `7be384b46da66f380bf3a9bb24ee6c6476bbd0dc`. No upstream fetch or merge is part of this preparation.

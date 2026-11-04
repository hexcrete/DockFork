## DockFork 0.5.0: Settings and Shortcut Refinements

DockFork is a GPL-licensed fork of [DockDoor](https://github.com/ejbills/DockDoor). This update incorporates upstream's Settings redesign and extends it with unified fork shortcut modes and gesture options.

### DockFork Changes

- Extends upstream's Alternate Shortcuts list with Left/Right/Either, filter scope, Persistent, No Highlight and Quick Switch. Quick Switch activates the last-focused window within its scope without opening the switcher. These consolidate the fork's previously separate shortcut modes.
- Corrected shortcut recording, exact Shift matching, conflict handling and key-code-zero assignments. Compact warning symbols expose details on hover.
- Restored dependent-setting indentation and fork shortcut-row alignment after adopting upstream's layout. Fork shortcut lists share Add/Remove and reset controls.
- Auto Tile controls now share Tiling; Space-cycle and numbered shortcuts share Spaces. Action Feedback is under Appearance.
- Appearance-only example hover and local checkbox toggles mirror the real cards, with correctly scaled targets. Examples never operate on real windows.
- Choose which three-/four-finger swipe directions may open the switcher. Disabled opening directions still work for navigation once it is open, allowing native macOS gestures to remain assigned selectively.
- Optional stricter title-bar detection supplements scrollable-area/tab exclusions for ambiguous browser tab strips. It can also exclude legitimate blank title-bar areas.

### Included From Upstream

- Redesigned Settings with native grouping and pinned preview examples.
- Multiple Alternate Shortcuts and combined-modifier shortcut controls, extended by the DockFork options above.
- Permission/Accessibility-observer lifecycle improvements, preview-action invocation handling and Cmd+Tab windowless-app fixes.

Includes DockDoor 1.42.2 and subsequent upstream changes through `c58cf6c0`. The fork retains its per-call observer-readiness checks. Existing single-modifier Double-tap is preserved, not introduced by this update.

### Installation and Configuration

- Apple Silicon package, ad-hoc signed and not notarized. Updates are manual; macOS approval and re-granting Accessibility or Screen Recording permissions may be necessary.
- Export a settings backup before replacing the app or importing the optional showcase preset. **Import replaces settings.**
- The refreshed preset uses the unified shortcut editor and omits retired settings. Older fork-only Persistent/last-focused shortcut assignments are not migrated; recreate them in Alternate Shortcuts if needed.
- Quit other DockDoor/DockFork instances before launching. Follow the included installation guide; do not disable Gatekeeper globally.

Screenshots and recordings remain deferred. See the [changes guide](https://github.com/hexcrete/DockFork/blob/better_dd_merged/fork/docs/CHANGES_AND_SHOWCASE.md) for details and [Issues](https://github.com/hexcrete/DockFork/issues) for reports.

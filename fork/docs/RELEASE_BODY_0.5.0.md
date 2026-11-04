## DockFork 0.5.0: Settings and Shortcut Refinements

DockFork is a GPL-licensed fork of [DockDoor](https://github.com/ejbills/DockDoor). This stable update refreshes Settings and makes alternate shortcuts more flexible.

### Settings and Shortcuts

- Redesigned, searchable Settings with pinned preview examples, clearer dependent controls and consistent shortcut editors.
- One Alternate Shortcuts list combines modifier combinations, Left/Right/Either, filter scope, Persistent, No Highlight and Quick Switch. Quick Switch activates the last-focused window within its scope without opening the switcher.
- Modifier-only Double-tap remains available with a chosen modifier and side. Ordinary key shortcuts support combined modifiers.
- Corrected shortcut recording, exact Shift matching, conflict handling and key-code-zero assignments. Compact warning symbols expose details on hover.
- Auto Tile controls now share Tiling; Space-cycle and numbered shortcuts share Spaces. Action Feedback is under Appearance.
- Appearance-only example hover and local checkbox toggles mirror the real cards, with correctly scaled targets. Examples never operate on real windows.

### Gestures and Upstream Improvements

- Choose which three-/four-finger swipe directions may open the switcher. Disabled opening directions still work for navigation once it is open, allowing native macOS gestures to remain assigned selectively.
- Optional stricter title-bar detection supplements scrollable-area/tab exclusions for ambiguous browser tab strips. It can also exclude legitimate blank title-bar areas.
- Incorporates DockDoor 1.42.2 plus subsequent upstream changes through `c58cf6c0`, including permission/observer lifecycle improvements, combined shortcut controls and Cmd+Tab fixes. The fork retains its per-call observer-readiness checks.

### Installation and Configuration

- Apple Silicon package, ad-hoc signed and not notarized. Updates are manual; macOS approval and re-granting Accessibility or Screen Recording permissions may be necessary.
- Export a settings backup before replacing the app or importing the optional showcase preset. **Import replaces settings.**
- The refreshed preset uses the unified shortcut editor and omits retired settings. Older fork-only Persistent/last-focused shortcut assignments are not migrated; recreate them in Alternate Shortcuts if needed.
- Quit other DockDoor/DockFork instances before launching. Follow the included installation guide; do not disable Gatekeeper globally.

Screenshots and recordings remain deferred. See the [changes guide](https://github.com/hexcrete/DockFork/blob/better_dd_merged/fork/docs/CHANGES_AND_SHOWCASE.md) for details and [Issues](https://github.com/hexcrete/DockFork/issues) for reports.

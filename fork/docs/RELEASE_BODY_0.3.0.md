## DockFork 0.3.0: Action feedback and interaction improvements

DockFork is a GPL-licensed fork of [DockDoor](https://github.com/ejbills/DockDoor). This prerelease adds action feedback, easier multi-window selection, and window-management fixes.

### New and improved

- **Action feedback:** optional popups show progress, results, and group-action counters. Display them at the cursor, over previews, or according to how you triggered the action.
- **Range selection:** Shift-click another checkbox, drag across previews from a checkbox, or hold your selection shortcut while using arrow keys.
- **Explicit Force Quit:** available in menus, shortcut assignments, and AppleScript. Normal Quit no longer becomes Force Quit simply because Option is held.
- **Cmd+Tab app-level Minimize:** minimize or restore the highlighted app's eligible windows before focusing an individual preview.
- **Mouse Follows Focus feedback:** optionally highlight the cursor's new location after it moves.

### Fixes and polish

- Closing a collapsed native-tab preview now closes the represented window, including Finder windows with differently named tabs. Minimized tab groups also remain grouped.
- Potentially slow window operations run off the UI thread, keeping input and feedback responsive.
- Batch actions protect their targets from overlapping commands without blocking unrelated windows.
- Dragging from preview controls no longer starts an invisible window drag. Holding an action shortcut no longer repeatedly executes it; navigation and typing still repeat normally.
- Corrected preview-container sizing and header visibility when windowless placeholders become real windows.
- Improved Wine/CrossOver game-window detection and controls, including unsupported-action filtering in groups. Wine resizing remains best-effort.

### Installation notes

- Apple Silicon build, ad-hoc signed and not notarized. Updates are manual.
- Quit other DockDoor/DockFork instances before launching. Upgrading may require removing and re-adding affected system permissions.
- The attached showcase preset is optional and now enables action feedback. **Export a settings backup before importing: import replaces existing settings.**
- Follow macOS Privacy & Security approval procedures; do not disable Gatekeeper.

These are highlights, not the complete list. See the [changes guide](https://github.com/hexcrete/DockFork/blob/better_dd_merged/fork/docs/CHANGES_AND_SHOWCASE.md) for details and known limitations. Screenshots and recordings will follow.

Report problems through [Issues](https://github.com/hexcrete/DockFork/issues). Review logs for private information before attaching them.

## DockFork 0.3.1: Selection and title-bar gesture fixes

A small testing update to DockFork 0.3.0.

- **Range-selection fix:** dragging from a checkbox or extending selection with a held shortcut no longer stops when a background refresh leaves the window list unchanged. Applies to regular and Compact Window Switcher.
- **Optional title-bar gesture filter:** enable **Gestures > Options > Disable title bar gestures over scrollable areas and tabs** to leave those areas to the app. Other controls retain the standard gesture rules. Off by default; detection depends on the app's Accessibility information.

Upstream is unchanged: DockDoor 1.41.0 plus incorporated history through `77e4771`. The refreshed optional showcase preset enables the title-bar scrolling/tab filter and omits the previously included custom Persistent Switcher shortcut. Application defaults are unchanged.

### Installation notes

- Apple Silicon, ad-hoc signed and not notarized. Updates are manual.
- Quit other DockDoor/DockFork instances before launching. Updating may require removing and re-adding affected Accessibility or Screen Recording permissions, then relaunching.
- Follow macOS Privacy & Security approval procedures; do not disable Gatekeeper.
- The optional showcase preset replaces settings on import. Export a backup first.
- Development fixes were user-tested. Exact Release-candidate installation and browser-quarantine/Gatekeeper testing are pending; older OS and exhaustive custom-app/display coverage are not confirmed.

See the [changes guide](https://github.com/hexcrete/DockFork/blob/better_dd_merged/fork/docs/CHANGES_AND_SHOWCASE.md) for details. Screenshots and recordings will follow.

Report problems through [Issues](https://github.com/hexcrete/DockFork/issues). Review diagnostic logs for private information before attaching them.

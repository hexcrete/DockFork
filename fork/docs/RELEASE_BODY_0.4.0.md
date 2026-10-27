## DockFork 0.4.0: Spaces Bar and Preview Refinements

DockFork is a GPL-licensed fork of [DockDoor](https://github.com/ejbills/DockDoor). Version 0.4.0 is our first stable release, bringing Space management into the Window Switcher alongside preview, input and reliability improvements.

### Spaces Bar

- An optional, horizontally scrollable Spaces Bar above the Window Switcher, with per-display sections, names or numbers, resident-app icons and window counts.
- Click a Space to switch, or click an app icon to focus its leading eligible window. Navigate with configurable cycle keys or the opposite axis of the existing trackpad switcher gesture; choose sequential or recently used ordering.
- Filter windows automatically when highlighting a Space, or apply a filter with the magnifier. Clear it from the pill or the switcher's filter header without clearing search or checked selections.
- Drag windows or selections onto Desktop pills to move them. Drag Desktop contents to move, swap or shift eligible windows, with target-aware feedback and animated drop zones.
- Native context menus expose applicable Space/window actions and shortcut hints. Shared AppleScript commands and accessible labels support the new controls.
- Fixed or Flexible pill widths, compact-size steps, optional app icons/badges and bounded icon counts keep the bar usable across narrow and multi-display layouts.

Space-content dragging moves windows, not native Desktop identities, wallpaper or app assignments. Creating/deleting Desktops and creating fullscreen/Split View Spaces by dropping are not supported.

### Preview and Input Polish

- Shared Compact Mode/card styling, source-sized drag previews, grouped app counts and clear drop-action symbols. Single-window dragging retains its window miniature.
- More consistent action names and selection scope across menus, plus applicable window actions when a Space is highlighted.
- Independent per-mode Space indicator placement and current-Space highlighting. The optional keyboard-scroll centering setting also supports minimal-reveal navigation.
- Improved filter controls, narrow-header fallbacks, companion spacing, search presentation, menu-bar toggling and fullscreen-Space removal handling.
- Optional title-bar gesture filtering over scrollable areas and tabs. Range selection no longer stops when a background refresh leaves the displayed windows unchanged.

### Reliability and Upstream Updates

- Corrected native scrolling ownership and more reliable hover handoff with resting fade enabled; the Spaces Bar fades with the other preview containers.
- Less repeated cache reconciliation, UI publication, layout, measurement and panel work. Full-size preview geometry resolves off the UI thread with stale-result protection. These changes target responsiveness, not guaranteed faster macOS window operations.
- Incorporates upstream automatic-Quit safety and exclusions, screen-position sorting, shared links and accessibility/Reduce Motion improvements. DockFork's Close actions respect the same automatic-Quit exclusions as native closing; explicit Quit and Force Quit remain separate.

### Installation Notes

- Apple Silicon build. Ad-hoc signed and not notarized; updates are manual. Stable release status does not change macOS trust or permission requirements.
- Quit other DockDoor/DockFork instances before launching. Upgrades may require removing and re-adding Accessibility or Screen Recording permissions.
- Follow the included installation guide and macOS Privacy & Security approval procedure. Do not disable Gatekeeper.
- The optional showcase preset enables the Spaces Bar and other demonstration settings. **Export a backup before importing: import replaces existing settings.**
- Browser-quarantined installation, older macOS versions and exhaustive app/display compatibility are not confirmed by build checks.

These are highlights, not the complete list of features, fixes and improvements. See the [changes guide](https://github.com/hexcrete/DockFork/blob/better_dd_merged/fork/docs/CHANGES_AND_SHOWCASE.md) for details. Screenshots and recordings will follow.

Report problems through [Issues](https://github.com/hexcrete/DockFork/issues). Review logs for private information before attaching them.

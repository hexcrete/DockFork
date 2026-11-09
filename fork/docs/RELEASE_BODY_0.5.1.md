## DockFork 0.5.1: Switcher and Dock Refinements

### DockFork Changes

- **Start persistent switchers with no window highlighted** is now one global option under Window Switcher > Behavior, rather than a checkbox on each alternate shortcut. It applies to menu-bar, AppleScript and persistent-shortcut launches, and to keyboard or swipe launches configured to stay open on release. It defaults off.

### Search Bar

Restored the upstream look while keeping DockFork's search improvements:

- The native clear button resets the text filter without taking focus away, so you can keep typing.
- Long queries stay on one line without resizing the bar. The shortcut hint disappears when the field takes focus, including on click.
- The Search Trigger Key respects modifier-side preferences and the active alternate shortcut. Conflicting bindings are flagged and won't trigger search.
- The bar reserves room when the results resize, sits evenly between the Spaces Bar and the window list, and no longer has an extra delay before appearing.

This update also fixes the shadow that lingered during fade-out. The search background stays visible when **Hide hover container background** is enabled.

### DockFork Fixes

- Clicking the top or bottom of the menu-bar icon's slot now closes the switcher instead of closing and immediately reopening it.
- Starting macOS Cmd+Tab releases any Dock reveal held by an open preview. A delayed Dock preview cannot reacquire it while Cmd+Tab is active.
- Dismissing previews or activating windows no longer waits for a fresh Accessibility query to release Dock reveal.

### Included From Upstream

Includes the changes from DockDoor 1.42.3 and 1.42.4 since the previous DockFork release.

- **Quit app when closing its last window** can target only selected apps. The existing exclusion-list mode remains the default.
- Dock previews can keep an auto-hidden Dock visible without changing the macOS auto-hide setting. This is on by default; saved choices are preserved.
- Fixed a crash when the pinned compact Calendar widget had four or more events.
- The Cmd+Tab Settings header image is hidden when Cmd+Tab enhancements are off. DockFork retains its interactive, bounded preview examples.
- Updated translations.

### Optional Showcase Preset

The refreshed preset enables the global no-highlight option and keeps the auto-hidden Dock visible during previews. Shortcut assignments are unchanged. Importing the preset replaces settings; export a backup first.

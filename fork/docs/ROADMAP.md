# DockFork Roadmap

These are future ideas, not shipped features or delivery promises. The [current guide](CHANGES_AND_SHOWCASE.md) and [commit ledger](COMMIT_LEDGER.md) describe what is implemented. Resolve feasibility and interaction choices before each feature is started.

## Publication First

The public source fork is established at [hexcrete/DockFork](https://github.com/hexcrete/DockFork). [The first prerelease](https://github.com/hexcrete/DockFork/releases/tag/v0.1.0) is published. Downloaded/quarantined installation testing and broader user feedback are next; showcase media will be assembled during that testing.

- Publish as a clearly attributed DockDoor fork while retaining original history and GPL-3.0 licensing.
- Validate the [isolated DockFork packaging script](../README.md#build-a-dockfork-package), including its distinct identity, signing, and installation; retain internal DockDoor naming.
- Initially offer source and an ad-hoc-signed Apple Silicon build, with manual downloads rather than upstream auto-updates.
- Verify the packaged fork version and recorded upstream base after each merge; keep the fork-only `version.json` and release build metadata distinct from upstream's project version.
- Export/import settings explicitly and document fresh permissions. Do not silently share DockDoor's preferences.
- Offer `fork/presets/DockFork-Showcase.json` as an optional, separately downloaded release asset, never an automatically applied configuration.
- Prepare small, dependency-aware upstream proposals only after discussing scope with the maintainer. Follow upstream's contribution and AI-disclosure rules; the human author reviews and writes submission text.
- Apply the [upstream contribution gates](UPSTREAM_CONTRIBUTIONS.md) to each proposed PR. Preserve upstream preferences/defaults, validate in Xcode, and require human-authored submission text; the complete fork is not a single upstream contribution.

## Spaces Bar in Window Switcher

- A horizontal Space-pill container, grouped by display, with names/numbers, resident app icons, per-app window counts, and fullscreen indicators.
- Optional app-icon activation, Space filtering, activation on double click, search integration, and recent/sequential ordering.
- Keyboard focus and forward/backward cycling, optional direct invocation with the bar focused, and selection on modifier release.
- Window drops onto eligible Spaces should reuse confirmed Space movement. Creating, closing, reordering, and fullscreen-creating Space gestures require separate private-API feasibility checks; no Mission Control parity is promised yet.
- Hide windowless apps while explicitly filtering by a Space. Reconcile bar/search/panel sizing through shared layout rules.

## Multi-Window Selection and Tiling

Approved implementation sequence, with a build/relaunch and manual approval before each commit and subsequent phase:

1. Selection controls and lifecycle. Committed in `fa76e57` and `a4150a5`; user manual verification passed October 13, with final review cleanup build-validated separately. Shared settings default Off. Real-window checks follow selection order, retain membership across filters, prune closed windows, and optionally show selected/outside-view counts in a separate header-style summary, default Off. Middle-click remains configurable through Toggle Window Selection. Eligible non-Command persistent standalone sessions also support Command-click. Checkboxes use the title region or app icon, with Always, On preview hover, and On title hover choices. Compact Mode maps On title hover to icon hover and its other choices to preview hover; hidden/unavailable titles outside Compact Mode fall back to preview hover; checked controls stay visible. Selection pins Window Switcher initializer/swipe dismissal, while Dock and Cmd+Tab retain normal hover dismissal, Escape and outside clicks dismiss and clear selection, and new launches, scope/initializer changes, and persistent/swipe takeovers reset checks, while repeated cycling of the same held shortcut retains them. Native keyboard-only Cmd+Tab release is unchanged.
2. Batch operations. Committed as `c827932`. User manual verification passed October 13; final cancellation cleanup is build/check validated separately. Checked targets operate on the ordered selection; unchecked targets remain single-window. Deduplicate app-wide operations by PID. Minimize/hide if any applicable target is unminimized/visible; restore/unhide only when all applicable targets are minimized/hidden. Exclude fullscreen windows from minimization and visible fullscreen-only apps from hiding. Exit all selected fullscreen members; when none are fullscreen, entry remains single-window on the initiator. Report per-window failures and keep existing transition safeguards.
3. Group dragging. Committed as `313e213`; user manual verification passed October 13. Snapshot ordered checked identities and geometry at drag start. Checked initiators drag the group; unchecked initiators remain single-window. The native material ghost shows up to six ordered icons with an overflow count. Preserve formation when it fits the destination usable area; otherwise individual placement fits/clamps members. Confirm Space moves before revealing and placing, raise in reverse check order so the first checked window leads, and keep previews on partial failure. Cancellation closes the ghost and cancels outstanding request-scoped moves. Aero Shake remains available in Dock and Cmd+Tab, with the entire group protected by Except, including global-minimize retries.
4. Tiling. Manual verification and final source review passed October 13. Auto Tile Selected Windows is a dedicated assignable action. Half/Quarter commands also arrange checked groups with their leading direction. The first checked window leads. Neutral layouts use one filled window, two halves, three with a leading half and two opposite quarters, or four quarters. Quarter commands with two/three windows use quarter-sized 2x2 cells and leave unused cells empty. Row/column upper bounds range 1-6, default 2x2, with a warning above 3; 1x1 disables auto-tiling. For larger groups, choose a balanced display-aspect-aware grid within those bounds, expand a short last row, and repeat the algorithm for ordered overflowing batches. A one-window remainder uses the requested fill direction. Auto Tile works on an individual window without requiring checked membership. Configured foregrounding raises all successful members. Shared menus and native AppleScript expose tiling and selection.
5. Drop-to-tile. The target window/group comes first in its existing selection order, followed by the dragged group; deduplicate identities. Use the target Desktop/display. Dropping a group onto itself does nothing. A 1x1 configuration moves without tiling.

Batch actions and group dragging are committed development changes. Tiling passed user manual verification and final source review October 13; drop-to-tile is not implemented yet. The separate scripting follow-up below precedes drop-to-tile. None of this selection development is included in the published 0.1.0 release. A dedicated selection-action popup and Spaces Bar remain later work.

## Pinned Floating Windows

- Display a live mirror while the source window is unfocused, using an appropriate floating/capture lifecycle.
- On hover or click according to the selected activation option, move/focus the real source window on the current Space; this is not a permanently noninteractive mirror.
- Add a pin state symbol and suspend/cancel appropriately for minimized, hidden, fullscreen, closed, or otherwise ineligible source windows.
- Reuse floating-widget infrastructure where suitable, but investigate focus, geometry, Space migration, capture cost, and cancellation before committing to the design.

## Slide-Out Window Switcher

- Mouse-first, single-column, compact switcher anchored left, right, or both, using the existing shared scope catalog separately per side.
- Optional activation while dragging, fullscreen-edge delay/second-push behavior where feasible, and search focus on open.
- A narrow icon-only idle state; hovered rows reveal full content without necessarily widening the entire background.
- Reuse session ownership, selection, and preview operations rather than a second global event pipeline. Edge conflicts across displays/fullscreen apps require testing.

## Full-Size Preview Focus

- The shipped resting-fade prototype remains experimental and off by default. Revisit it separately with reproducible interaction tests.
- Refine cursor-versus-keyboard ownership, non-control dwell timing, and an optional held key for temporarily hiding the preview container.
- Preserve hover targets, keyboard focus, menu tracking, accessibility, Reduce Motion, and cancellation when restoring the container.

## Deferred Engineering Work

- Harden upstream settings import against malformed or unsupported backup formats. Deliberately deferred from initial publication work.
- Continue measured reliability/performance investigation when diagnostics identify a concrete failure; don't advertise all hangs as solved.
- Follow the [optional-feature resource audit](RESOURCE_LIFECYCLE_AUDIT.md) for focused lifecycle follow-ups, prioritizing pending-operation shutdown and non-creating diagnostics cleanup over small allocation savings. Live-capture shutdown is already fixed.
- Re-audit optional presentation unification opportunities only when they reduce duplication without changing behavior or adding hot-path work.
- App-icon badges and reliable preview dragging are already implemented; remaining refinements should not be presented as wholly new roadmap features.

### Separate Scripting Follow-Up

After the tiling phase is manually approved and committed, extend applicable existing window commands to accept one window ID or an ordered list without depending on UI checks. Keep current single-window syntax, names, event codes and behavior; reuse batch visibility, app deduplication and confirmed Space operations, with bounded single replies and per-window failures. Keep Focus single-target and preserve group-fullscreen exit-only safety. The new Tile Windows command already accepts lists. Toggle Window Selection remains an optional open-preview integration command, not a prerequisite for programmatic batch operations. Keep this follow-up in a separate commit from tiling.

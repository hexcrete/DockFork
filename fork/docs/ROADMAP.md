# DockFork Roadmap

These are future ideas, not shipped features or delivery promises. The [current guide](CHANGES_AND_SHOWCASE.md) and [commit ledger](COMMIT_LEDGER.md) describe what is implemented. Resolve feasibility and interaction choices before each feature is started.

## Publication First

- Publish as a clearly attributed DockDoor fork while retaining original history and GPL-3.0 licensing.
- Validate the [isolated DockFork packaging script](../README.md#build-a-dockfork-package), including its distinct identity, signing, and installation; retain internal DockDoor naming.
- Initially offer source and an ad-hoc-signed Apple Silicon build, with manual downloads rather than upstream auto-updates.
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

- Select real windows through middle-click, an assignable preview action, and an optional title-side checkbox. In eligible non-Command persistent sessions, consider Command-click too; resolve conflicts first.
- Show compact selection feedback over the app icon; retain checked state visibly and suppress ordinary auto-dismiss while selection is active.
- Applicable actions, Space movement, and dragging should operate on the selected identity set, with per-window outcomes rather than silent all-or-nothing assumptions.
- A later selection action popup and deterministic auto-tiling: one maximized window; two halves; three with a left half plus two right quarters; four quarters. Layouts for five or more are undecided.
- Group drag ghosts can use app icons. Dropping onto another window/selection can combine ordered identities for tiling after explicit interaction rules are designed.

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

# DockFork: Changes and Showcase

DockFork is a fork of [DockDoor by ejbills](https://github.com/ejbills/DockDoor). DockDoor supplies the original application, Dock previews, Window Switcher, Cmd+Tab integration, widgets, and many settings. This guide describes the fork's additions and changes, not the origin of those existing capabilities.

**Publication preparation:** the [DockFork packaging script](../README.md#build-a-dockfork-package) prepares a separately identified distribution build. Release build/signature/checksum checks and local launch have passed; manual feature and downloaded/quarantined installation validation remain pending. Local development now uses certificate-signed DockFork at the fixed, gitignored `fork/dist/dev/DockFork.app` path. No release has been published.

## Reading This Guide

- [Complete commit ledger](COMMIT_LEDGER.md): every branch-only commit in the audited history, grouped by category.
- [Showcase capture checklist](SHOWCASE_CHECKLIST.md): choose which screenshots and recordings to publish.
- [Roadmap](ROADMAP.md): future ideas, not shipped capabilities.
- [Optional showcase preset](../README.md): privacy-reviewed preferences and import precautions.
- [Upstream contribution gates](UPSTREAM_CONTRIBUTIONS.md): compatibility, testing, and human-review requirements for proposing selected changes to DockDoor.
- [Original project](https://github.com/ejbills/DockDoor): upstream documentation, attribution, and releases.

Original feature audit: fork `9efa1cc`, upstream `0bd2e46`, October 8, 2026. The ledger now includes nineteen documentation/defaults/packaging/indicator/appearance/modal-lifecycle/windowless/dimming/pill-border follow-ups through `07c6793`, for 208 non-merge commits and three upstream-integration commits. Publication and defaults notes reflect those follow-ups; this is not a new whole-app safety audit. Intermediate implementations are not separate features. New upstream backup/import functionality is not claimed as a fork contribution.

## Compact and Windowless Previews

Compact width can be configured independently of regular preview width. Compact titles retain the app-name/window-title structure, with window-state text when state is not placed in the indicator. Windowless entries avoid stale window titles and retain appropriate app actions.

Dock and Cmd+Tab each offer “Show full size previews” beneath “Show preview for apps with no open windows”, default On. Outside Compact Mode, enabled uses the same card renderer as real windows; disabled uses the compact-style windowless row. Full-size placeholders inherit each mode’s embedded controls, title/pill styling, scaled traffic lights, alignment/edge spacing, icon sizing, and card chrome rather than a separate switcher-style toolbar. They retain the app-icon image and No Open Windows label, app-only actions, and no live capture or window dragging. Actual Compact Mode remains compact regardless of this option. This extends the fork’s earlier compact-only windowless presentation without changing the parent preview-enable defaults. Eight source-derived shared-renderer presentation checks and the final certificate-signed Debug build/relaunch passed; user manual verification passed. Implemented in `0b961e1`. The full Xcode test suite was not run for this change. No new timers, capture requests, or discovery work are introduced.

Non-compact Window Switcher placeholders follow embedded-control formatting, traffic-light scale, and default card proportions even with dynamic sizing enabled. Missing screenshots on real windows use an app-icon placeholder in a full-size card, retaining real-window actions rather than becoming compact rows.

**Showcase:** W01-W03 in the capture checklist. Entry points: Appearance > Compact Mode and the per-mode preview appearance settings. Representative commits: `e3b7a83`, `2a79e61`, `7b2491a`, `7368daf`, `717c1e0`.

## Window State and Space Indicators

Each preview mode has controls for the Space number and window-state presentation. Minimized, Hidden, and Full Screen states use distinct presentation, including `minus.circle` for minimized windows. State indicators can remain visible when there is no Space number to show.

Options include pill versus unstyled appearance, current-Space highlighting, indicator font size, swapping state/Space controls with traffic lights, and limiting that swap to Compact Mode. Embedded unstyled controls receive contrast shadows; non-embedded controls do not need those shadows.

Unstyled, non-embedded indicators do not reserve a horizontal gap for hover-hidden traffic lights. The shared control layout retains its height-based alignment while removing spacing for an invisible, zero-width neighbor. Fixed in `09a2cc2`; Debug build/relaunch and user verification passed.

The clickable Space indicator uses its full label bounds, including the unstyled number ring's interior and edges, without changing visible size or layout spacing. Fixed in `6a5599d`; Debug build/relaunch and user verification passed.

**Showcase:** I01-I04. Entry points: each mode's Window State Indicator settings and Appearance > General. Representative commits: `411618f`, `20d3b2f`, `356af10`, `6248aab`, `b435c0a`, `f7b64c9`, `f933cd0`.

## Moving and Switching Spaces

Clicking a Space indicator opens a native destination menu. It lists desktop Spaces, resident app icons, number-only or full-name labels, and optionally disabled fullscreen Spaces. A current-Space badge can be enabled. A fullscreen source offers an Exit Full Screen action before moving.

Confirmed window moves can optionally follow the destination. The same picker is available under Move to Space in the preview context menu. Numbered shortcuts use physical number-row keys, including on layouts such as Czech: 1-9 address those global Space numbers, and 0 addresses 10.

With a selected real preview, a numbered shortcut moves that window to an eligible Desktop. With a standalone Window Switcher open and no selection, it navigates to the numbered Desktop or fullscreen Space; this is distinct from moving a window. Fullscreen destination navigation must not be presented as permission to move another window into a fullscreen Space.

**Showcase:** S01-S05. Entry point: Gestures & Keybinds > Spaces. Representative commits: `cdd7b82`, `1c4ce38`, `381e839`, `0dce6a7`, `5ef868b`.

## Configurable Shortcuts and Scopes

Window Preview Keyboard Shortcuts and alternate launcher lists use editable rows with add/remove controls. Rows can be configured before recording a trigger. Effective-trigger conflicts are indicated rather than executing duplicate assignments.

Main and regular alternate initializer modifiers support Left, Right, or Either. Dependent preview shortcuts can ignore the main modifier's side when configured. Persistent and last-focused launchers support full combinations or modifier double taps, including physical side selection. Cmd+Tab preview actions use Command rather than the main Window Switcher modifier.

The shared, alphabetically displayed scope list contains Active App + Current Space, Active App Only, All Windows, Current Monitor + Current Space, Current Monitor Only, Current Space Only, and Window Switcher Defaults. All Windows is a global scope, whereas Window Switcher Defaults applies configured restrictions. Optional exclusions keep windowless apps out of location scopes. Lists allow up to the scope count; duplicate scopes are allowed, but conflicting triggers are not active.

**Showcase:** K01-K04. Entry point: Gestures & Keybinds. Representative commits: `6b62149`, `94b4361`, `19d4888`, `d2d063c`, `982c6d0`, `93074e7`, `d013ee1`, `be73708`.

## Persistent, Menu-Bar, and Swipe Sessions

The menu-bar icon can launch a persistent Window Switcher, with configurable left/right-click assignment. Persistent sessions remain open after initializer modifiers are released and can start with no highlighted window. Configured mouse-follow behavior remains available.

Trackpad swipes can optionally take ownership of persistent sessions and select on release. Keyboard cycling can take ownership back; invoking a held-modifier switcher explicitly changes the session to modifier-driven behavior. A held initializer takes precedence over swipe takeover. Swipe selection direction is reversible, with consistent horizontal/vertical defaults.

The base global swipe launcher came from upstream; these commits refine its selection direction and session ownership. Do not describe the entire upstream gesture launcher as newly invented by this fork.

**Showcase:** P01-P04. Entry point: Gestures & Keybinds > Window Switcher Shortcuts and Trackpad Gestures. Representative commits: `c9adbf9`, `2898dc6`, `78bfbf6`, `7797cdf`, `ae93b49`.

## Last-Focused Window Switching

Multiple scoped last-focused shortcuts activate the next eligible window in the shared chronological ordering without opening the switcher. Triggers use the same full-combination/double-tap editor. This path respects filters, distinguishes real windows from windowless entries, and follows the Mouse Follows Focus setting.

**Showcase:** R01. Entry point: Gestures & Keybinds > Switch to Last Focused Window. Representative commits: `af0bbcd`, `69507bc`, `bfaf5f4`. No latency improvement is claimed without measurements.

## Window and App Actions

The fork adds Dock window cycling, assignable bulk close/minimize actions, and a Bring to Current Space action shared across configurable action lists. Repeated Dock cycling uses a per-app ordering during the Dock hover session.

Keep-previews-after-action settings are independent from bringing moved/resized windows forward. Bulk minimize behavior considers minimizable windows rather than trying to minimize fullscreen windows. Header actions and Dock click actions share window-operation infrastructure; ordinary inactive-app clicks must still respect activation behavior.

**Showcase:** A01-A03. Entry points: Dock Interaction, Gestures & Keybinds, and the app header. Representative commits: `ffa82dd`, `bef9786`, `28075b2`, `2c1679d`, `4743b0e`, `df7bf47`.

## Native Menus and Scripting

Preview context menus share action construction with menu-bar Window Actions. They include action symbols, dynamic action names, Arrange, and the common Space picker. Preview menus show effective shortcut hints using the active session's modifier; menu-bar action menus omit those hints. Quit text and its symbol use matching styling.

AppleScript additions expose Space listing, confirmed window movement, Space navigation, and the shared persistent switcher launch path. Existing scripting commands remain part of DockDoor's original scripting interface. Current examples still target the development app's DockDoor name; publication documentation will distinguish DockFork's bundle identity without renaming command/event codes.

**Showcase:** M01-M02 and T01-T02. Representative commits: `5532376`, `5d50fd8`, `92908e2`, `4d38e51`, `da9f3f3`. See the [scripting dictionary](../../DockDoor/DockDoor.sdef).

## Search, Scrolling, and Layout

Horizontal Window Switcher grids respect the applicable row/screen limit, and cycling follows the layout's traversal direction. Compact Mode remains vertical. Dock, Window Switcher, and Cmd+Tab have configurable edge auto-scroll independent of Window Switcher hover selection, and auto-scroll waits for pointer movement after opening.

Entering an edge-scroll zone clears stale preview selection. Content clipping and fade edges follow the container, while search placement accounts for the panel size. Search helper text disappears while its input is active, including click focus. Placeholder-to-window replacement triggers appropriate panel resizing even when the row count is unchanged.

**Showcase:** L01-L04. Representative commits: `c802975`, `19b3ddd`, `8af3b00`, `08c52c6`, `f7e5a12`, `586407f`, `9151f2d`.

## Full-Size Preview Appearance

Shared controls provide opacity, a backdrop-blur checkbox, an inward border, and separate fade-in/fade-out durations. Backdrop blur affects content behind the preview, not its captured screenshot. Reduce Motion affects animation observations and should be disclosed in recordings.

Resting on a full-size preview can fade its container, but this feature is explicitly **experimental and off by default**. It can intermittently stop mouse-hover highlighting or make selection appear unresponsive; disable it if those issues occur. It is not a stability headline. Traffic-light visibility transitions have a shared configurable duration.

Live-preview follow-ups stop cached streams when none of their requesting modes remain enabled, preserve captures needed by another enabled mode, and reject stale asynchronous starts. Timed keep-alive still retains streams for the configured delay after closing previews; reopening cancels the old shutdown deadline. Its editable duration field applies whole-second changes on Return or focus loss. These improve upstream live-preview behavior rather than introduce live capture itself. Representative commits: `e8d0ad5`, `9efa1cc`.

**Showcase:** F01-F03 and V03. Entry point: Appearance > Full Size Previews and the per-mode experimental settings. Representative commits: `97096c7`, `3c0cf89`, `c2fa95d`, `220464d`, `1f7ce92`.

## Dragging and Spring-Loading

Regular and Compact Mode real-window previews share drag behavior, using a screenshot ghost or an app-icon fallback. Drop placement is centered at the pointer, uses destination-display bounds, and checks real operation outcomes. Aero Shake remains available in Dock and Cmd+Tab rather than standalone Window Switcher.

External-item spring-loading is separate: hovering over a preview reveals its window and dismisses the container so the native drag can continue. Dock icon hover behavior is not advertised as fixed; reproduction on clean upstream builds was also unreliable. Generic item-provider forwarding is not a shipped feature.

Spring-loading can be disabled or use the system speed. The fork's custom-delay default is 1.2 seconds with a 0.05-second slider step; the system-speed option defaults off.

**Showcase:** D01-D03. Entry point: Advanced > Spring-loading. Representative commits: `a7d61d1`, `78f65dd`, `1ceb007`, `ba665c2`.

## Discovery, Synchronization, and Diagnostics

Changes address fullscreen/Space metadata reconciliation, off-Space discovery, native tab grouping, nonstandard actionable windows, and live-capture proxy filtering. Calendar Info panes and some compatibility-layer windows are concrete examples, not guarantees for every popup or Wine application.

Preview recovery retains capture validation safeguards and uses appropriate placeholders when an image is still unavailable. Synchronization fixes address observed cache deadlocks, stale tasks, pointer activation, and event-state access. These are targeted fixes, not a claim that all crashes are eliminated.

Debug logging integrates hang diagnostics, bounded log storage, and ZIP export. A normal export may contain only the debug log when no hang artifact was produced. Logs and settings can contain private application/window information; they are not showcase assets without sanitization.

**Showcase:** B01-B04 and H01. Representative commits: `e2e4c45`, `a94bb4d`, `6fb1946`, `6fe02cc`, `f96dd57`, `77ee4d3`.

## Visual Polish and App Badges

Window Switcher app icons can show badges in normal and Compact Mode with independent visibility options and a badge-size control. Badges do not participate in icon layout geometry. Non-compact badges depend on the visible app header.

Shared appearance controls, mirrored title clusters, compact widget alignment, embedded-control contrast, control-edge spacing, and mock-preview hover visibility receive consistent handling across the applicable layouts.

Non-compact Window Switcher Automatic app icons use 35 points when window titles are eligible to appear and 20 points otherwise, regardless of missing/duplicate title text. Hover-only title visibility still switches between these sizes on highlight/hover. Real-window and windowless headers share the rule; explicit icon sizes retain their 16-64-point limits and Compact Mode sizing is unchanged. Fixed in `bdc62ae`; six focused sizing checks, Debug build/relaunch, and user verification passed.

**Showcase:** V01-V04 and I03. Representative commits: `023bfd2`, `a9f400a`, `82a8449`, `ba71716`, `9ce4a89`, `424c16c`, `1aebbc5`.

## Defaults Worth Disclosing

The fork preserves many existing behaviors, but it does not preserve every upstream default. The main shortcut defaults to Either-side Option + Tab, and traffic-light scale defaults to 1.0, matching upstream behavior. Custom spring-loading remains at 1.2 seconds rather than system speed, and full-size preview fades default to zero duration. Resting fade remains off, while both normal and compact Window Switcher app badges default on. See the [follow-up resource audit](RESOURCE_LIFECYCLE_AUDIT.md).

These are defaults for unset preferences, not instructions to reset an existing configuration. DockFork packaging uses a separate preference identity; explicitly import a reviewed settings export if you want your existing configuration.

Window state/Space indicators default to dock styling enabled in all three modes, with swapping enabled only in Compact Mode. The Spaces dropdown defaults to showing the Current badge and unavailable Spaces. These defaults are declared in the app, not overridden by packaging; existing saved choices remain unchanged.

## Modal Settings Dialogs

Settings import/export temporarily suspend previews and dismiss existing preview sessions before opening their modal dialogs. Preview launch shortcuts pass through while suspended; cancellation, errors, and completion restore launching. This prevents visible but input-blocked Dock previews from appearing frozen. Fixed in `6c51d22`; Debug build/relaunch and user verification passed. Backup formats and import semantics are unchanged.

## Publication Boundaries

The original GPL-3.0 license and upstream attribution are retained. This fork does not imply affiliation, endorsement, or ownership of DockDoor Pro. Upstream settings backup/import, the base trackpad launcher, and existing widgets should remain attributed to upstream.

The fork-only packaging workflow supplies a build-time DockFork identity, isolation from upstream auto-updates, an Apple Silicon release build recipe, a documented permission/installation flow, and a sanitized optional settings example. The complete package build, signature/checksum checks, and local launch passed; manual feature and downloaded-installation validation are still required before publication. Commit-history retention does not mean every historical commit is independently cherry-pickable; related implementation dependencies must be reviewed before preparing small upstream contributions.

### Traffic-Light Button Dimming

Both dimmed visibility choices dim only the traffic-light buttons, leaving the material pill undimmed, across Dock, Cmd+Tab, Window Switcher, Compact Mode, and mock previews. Whole-control hiding still follows preview hover/visibility and retains the stable pill layout. This corrects the fork’s `c832c1f` modifier-order change without restoring its conditional pill creation. Forty source-derived visibility/dimming checks, modifier-order checks, and the signed Debug build/relaunch passed; committed as `afa75e4` with user approval. Manual visual verification was not separately reported. The full Xcode test suite was not run. No new timers, observers, or discovery work are added.

### Control-Pill Borders

All material pills (search, titles, Space/state indicators, and traffic lights) use upstream’s subtle primary-color outline at 10% opacity and 1.5-point width rather than the preview container’s configurable white rim. Search uses the same shared style; there is no search-specific border override. Container border settings still control the preview container, not individual pills. The shared pill renderer still provides blur, highlight overlays, and padding; no per-mode copies or new background layers are added. This limits the broader styling effect introduced by `12e0a77`; it is not a claim that the reported artifact was a duplicated background. Source checks and the signed Debug build/relaunch passed. User visual verification passed; committed as `07c6793`. The full Xcode test suite was not run.

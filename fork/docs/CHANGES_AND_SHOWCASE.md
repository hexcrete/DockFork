# DockFork: Changes and Showcase

DockFork is a fork of [DockDoor by ejbills](https://github.com/ejbills/DockDoor). DockDoor supplies the original application, Dock previews, Window Switcher, Cmd+Tab integration, widgets, and many settings. This guide describes the fork's additions and changes, not the origin of those existing capabilities.

**Publication preparation:** the [DockFork packaging script](../README.md#build-a-dockfork-package) prepares a separately identified distribution build. Release build/signature/checksum checks and local launch have passed; manual feature and downloaded/quarantined installation validation remain pending. Local development now uses certificate-signed DockFork at the fixed, gitignored `fork/dist/dev/DockFork.app` path. No release has been published.

Release validation on October 11, 2026 covered a committed-source `82f0a06` candidate and a later working-tree test candidate containing the label rename and refreshed preset. Arm64 Release builds, checksums, ZIP integrity, exact unpacked bundle correspondence, nested ad-hoc signatures, source/patch correspondence, and version/identity checks passed. All 19 version-metadata tests passed. Neither candidate was launched or installed; development-app verification is not Release installation verification. Build a final candidate from committed HEAD before publication. Clean/downloaded installation, permissions/update behavior, manual Release feature tests, and minimum-OS compatibility remain pending. See [release validation](../README.md#release-assets-and-validation). Swift 6 compatibility warnings remain in the Swift 5 build; no full Xcode test-suite run is claimed.

## Reading This Guide

- [Complete commit ledger](COMMIT_LEDGER.md): every branch-only commit in the audited history, grouped by category.
- [Showcase capture checklist](SHOWCASE_CHECKLIST.md): choose which screenshots and recordings to publish.
- [Roadmap](ROADMAP.md): future ideas, not shipped capabilities.
- [Optional showcase preset](../README.md): privacy-reviewed preferences and import precautions.
- [Upstream contribution gates](UPSTREAM_CONTRIBUTIONS.md): compatibility, testing, and human-review requirements for proposing selected changes to DockDoor.
- [Original project](https://github.com/ejbills/DockDoor): upstream documentation, attribution, and releases.

Previous committed-source candidate, October 11, 2026: `9fcf28dbb82334e40ff7141d2b16e3661f9755b2` passed the arm64 Release build and includes the shared preview-centering and scroll-hit-target fixes plus the refreshed optional preset. All nine asset checksums, ZIP integrity, unpacked nested ad-hoc signatures, all 219 bundle entries (contents, modes, and symlinks), source archive correspondence, clean packaging-overlay application, preset/license/install-guide correspondence, identity/source/upstream metadata, and disabled upstream updater feed passed verification. All 19 version-metadata tests passed. Output: `fork/dist/DockFork-9fcf28d-aXldXK/DockFork-0.1.0-9fcf28d-arm64.zip`. The Release app was not installed or launched; the preset was not imported, and downloaded/quarantined installation testing and publication remain unperformed. The running signed development build and live preferences were left unchanged.

The optional showcase preset was refreshed again October 11, 2026 in `9fcf28d`: 237 recognized preferences remain after removing four private/system settings and the export timestamp. Nested shortcut records were reviewed, all 15 IDs remain generic, and debug logging remains off. Compared with the prior preset (`3d1e761`), only app-header style changes to Popover and Window Switcher app-icon size changes from 35 pt to Automatic. All other sanitized settings are semantically identical. This optional asset changes neither app defaults nor live preferences; no import test of this refresh is recorded.

Original feature audit: fork `9efa1cc`, upstream `0bd2e46`, October 8, 2026. The ledger now includes fifty later follow-ups/integrations through `36e635e`, for 238 non-merge commits and four upstream-integration commits (including four explicitly attributed upstream commits in the continuation). Publication and defaults notes reflect those follow-ups; this is not a new whole-app safety audit. Intermediate implementations are not separate features. New upstream backup/import functionality is not claimed as a fork contribution.

## Latest Upstream Integration

October 11: upstream advanced from `0bd2e46` to `7be384b`. The conflict-free merge `325ef3f` incorporates focused-native-tab caching and AX geometry (`8ede8d0`), Dock indicator resting-edge stabilization during icon bouncing (`7358716`), and two beta appcast updates. These are upstream fixes, not fork additions. Local PID-validated focus publishing, metadata reconciliation, native-tab grouping safeguards, and bounded missing-window caching remain intact. Signed Debug build and exact-path relaunch, nested signature, binary/source-overlay correspondence, 19 version-metadata checks and four existing scroll regression cases passed. The final review also ran 20 native-tab/scroll tests in an isolated harness using the production grouping/container code and checked-in test bodies; all passed. User manual merge verification passed; no separate exhaustive display/OS coverage is inferred. The full Xcode suite was not run. The last incorporated stable release remains 1.40.7; beta tags do not replace the stable base. The exact upstream commit and stable release are recorded in `fork/version.json`; packaging continues validating both against committed ancestry. The post-commit signed Debug build/relaunch and installed binary/source correspondence passed; embedded metadata was verified as source `325ef3f`, upstream `7be384b`, and stable release 1.40.7. The October 11 Release candidate predates this merge; the October 12 candidate incorporates it and the final safety fixes.

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

Trackpad swipes can optionally take ownership of persistent sessions and select on release. The setting is labeled "Select highlighted window when swiping in persistent Window Switchers" to distinguish the highlighted selection from the last-focused-window action; its preference key, default, and behavior are unchanged. Keyboard cycling can take ownership back; invoking a held-modifier switcher explicitly changes the session to modifier-driven behavior. A held initializer takes precedence over swipe takeover. Swipe selection direction is reversible, with consistent horizontal/vertical defaults.

Label/search-title update `1f72ecb`, validated October 11, 2026: matching source strings and `git diff --check` passed. The signed Debug build and signature checks passed; macOS initially returned launch error -600, then a retry launched the exact fixed development executable. Installed binary and build-source patch comparisons passed. Manual UI verification and the full Xcode suite were not performed for this wording-only update.

The base global swipe launcher came from upstream; these commits refine its selection direction and session ownership. Do not describe the entire upstream gesture launcher as newly invented by this fork.

**Showcase:** P01-P04. Entry point: Gestures & Keybinds > Window Switcher Shortcuts and Trackpad Gestures. Representative commits: `c9adbf9`, `2898dc6`, `78bfbf6`, `7797cdf`, `ae93b49`.

## Last-Focused Window Switching

Multiple scoped last-focused shortcuts activate the next eligible window in the shared chronological ordering without opening the switcher. Triggers use the same full-combination/double-tap editor. This path respects filters, distinguishes real windows from windowless entries, and follows the Mouse Follows Focus setting.

**Showcase:** R01. Entry point: Gestures & Keybinds > Switch to Last Focused Window. Representative commits: `af0bbcd`, `69507bc`, `bfaf5f4`. No latency improvement is claimed without measurements.

## Window and App Actions

The fork adds Dock window cycling, assignable bulk close/minimize actions, and a Bring to Current Space action shared across configurable action lists. Repeated Dock cycling uses a per-app ordering during the Dock hover session.

Keep-previews-after-action settings are independent from bringing moved/resized windows forward. Bulk minimize behavior considers minimizable windows rather than trying to minimize fullscreen windows. Header actions and Dock click actions share window-operation infrastructure; ordinary inactive-app clicks must still respect activation behavior.

**Showcase:** A01-A03. Entry points: Dock Interaction, Gestures & Keybinds, and the app header. Representative commits: `ffa82dd`, `bef9786`, `28075b2`, `2c1679d`, `4743b0e`, `df7bf47`.

Dock cycling fix (`dc5a805`): cycle only after releasing a click on the original app icon. On dragging, return the withheld original press to the native Dock before the first drag event, without re-entering DockDoor's event tap. Mouse-up/drag subscriptions and bounded press tracking exist only while the cycling override is enabled. Minimize/Hide, Shift-click, and configured preview-activation clicks retain their existing paths. Seven source-derived press lifetime/copy checks, signed Debug build, signature verification, and exact-path relaunch passed. User manual verification passed. The reviewed source matches the tested build; the full Xcode test suite was not run. No new timer or window discovery is added to the drag path.

Cycling option (`b7faf95`): Dock Interaction > Dock Click Action > Cycle through windows exposes Keep previews open when cycling through windows, default Off. It retains an already-visible Dock container only for same-Space activation, using the shared conservative Space-transition check also used by Unhide/Un-minimize. Off-Space or unknown-membership targets close previews before restoration/activation. Actual Space changes always use the ordinary dismissal lifecycle, even if prediction missed a transition. No Dock-visibility monitor, polling, discovery scan, or capture request is added.

AppKit-hosted cards refresh only the old/new active borders for focus-only changes, without grid remeasurement or reordering. AX focus updates validate the frontmost PID, preventing background apps from overwriting the border. Dock clicks use actual coordinates rather than a stale hover flag; native Dock dragging/replay remain unchanged. User manual verification passed for preview retention, focus/re-entry fixes, and transition dismissal.

Validation: 444 source-derived transition/preservation cases passed, including unknown membership, active Spaces on multiple displays, and no Space reads while preservation is ineligible. Earlier 120 focus-notification, 50 card-refresh, and 7 press checks passed. Latest signed Debug build, exact-path relaunch, signature and source-snapshot verification passed. Full Xcode suite and measured CPU comparison were not performed. Committed as `b7faf95` after manual approval.

## Native Menus and Scripting

Preview context menus share action construction with menu-bar Window Actions. They include action symbols, dynamic action names, Arrange, and the common Space picker. Preview menus show effective shortcut hints using the active session's modifier; menu-bar action menus omit those hints. Quit text and its symbol use matching styling.

AppleScript additions expose Space listing, confirmed window movement, Space navigation, and the shared persistent switcher launch path. Existing scripting commands remain part of DockDoor's original scripting interface. Current examples still target the development app's DockDoor name; publication documentation will distinguish DockFork's bundle identity without renaming command/event codes.

**Showcase:** M01-M02 and T01-T02. Representative commits: `5532376`, `5d50fd8`, `92908e2`, `4d38e51`, `da9f3f3`. See the [scripting dictionary](../../DockDoor/DockDoor.sdef).

## Search, Scrolling, and Layout

Horizontal Window Switcher grids respect the applicable row/screen limit, and cycling follows the layout's traversal direction. Compact Mode remains vertical. Dock, Window Switcher, and Cmd+Tab have configurable edge auto-scroll independent of Window Switcher hover selection, and auto-scroll waits for pointer movement after opening.

Entering an edge-scroll zone clears stale preview selection. Content clipping and fade edges follow the container, while search placement accounts for the panel size. Search helper text disappears while its input is active, including click focus. Placeholder-to-window replacement triggers appropriate panel resizing even when the row count is unchanged.

Scroll geometry follow-up (`295ef75`): shrinking card content now immediately commits the clamped scroll offset to its actual AppKit view position, keeping pointer hit targets aligned with visible cards. The missing commit is inherited from upstream's AppKit grid introduction (`23fccf2`) and remains in the incorporated main snapshot. The shared correction covers both axes, Compact Mode, Dock, Cmd+Tab, search filtering, and window removal; viewport resizing and axis changes already commit correctly. Sixteen production-container checks and four parameterized regression cases passed in an isolated AppKit/Swift Testing harness using the production container and checked-in test bodies. The signed Debug build and exact-path relaunch passed, with signature, binary, and reviewed source-patch correspondence verified. User manual verification passed for the reported scenario; no separate all-mode/display coverage is inferred. The full Xcode test suite was not run. Continuous scrolling keeps its existing layer-only optimization; no new timers, observers, or per-frame measurements are introduced.

Non-embedded preview centering: the shared regular-card stack centers its screenshot independently of toolbar width. Fork commit `a86d0c7` gave the switcher toolbar a fixed image-width frame; the existing outer toolbar padding then made it wider than the screenshot, exposing the inherited stack's leading alignment. Upstream's flexible switcher toolbar does not impose that fixed width. The current fix changes only stack alignment, not title/control alignment, card sizing, or padding. The same renderer covers regular and full-size placeholder cards in Dock, Cmd+Tab, and Window Switcher; Compact Mode is unchanged. A reduced offscreen SwiftUI reproduction measured a 3-point shift before the fix and zero afterward; 216 native-renderer width/padding/toolbar-position checks passed. The signed Debug build/relaunch, exact running path, signature, binary correspondence, and reviewed source-patch comparison passed. These are structural layout checks, not manual verification of every app mode; the full Xcode suite was not run. No timers, observers, measurement caches, or runtime state are added.

**Showcase:** L01-L04. Representative commits: `c802975`, `19b3ddd`, `8af3b00`, `08c52c6`, `f7e5a12`, `586407f`, `9151f2d`, `e2667b3`, `295ef75`.

## Full-Size Preview Appearance

Shared controls provide opacity, a backdrop-blur checkbox, an inward border, and separate fade-in/fade-out durations. Backdrop blur affects content behind the preview, not its captured screenshot. Reduce Motion affects animation observations and should be disclosed in recordings.

Resting on a full-size preview can fade its container, but this feature is explicitly **experimental and off by default**. It can intermittently stop mouse-hover highlighting or make selection appear unresponsive; disable it if those issues occur. It is not a stability headline. Traffic-light visibility and dimming transitions have a shared configurable duration. The Reduce Motion follow-up (`ae79432`) makes both the app's Reduce Motion preference and macOS Reduce Motion override that duration; zero disables only traffic-light transitions while other animations can remain enabled. The saved duration/default are unchanged. Twenty-five source-derived policy checks and all six visibility-gate checks passed. The signed Debug build succeeded; the first macOS launch request failed with -600, a retry succeeded, and the exact development executable and build-source patch were verified. User manual verification passed. The full Xcode test suite was not run. This uses SwiftUI's native accessibility environment and existing appearance snapshots without adding polling, timers, or explicit observers.

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

### Fork and Upstream Version Identity

The packaging follow-up (`b674d9c`) defaults the initial unpublished DockFork version to `0.1.0` and displays its upstream base separately in Support > Updates: DockDoor `1.40.7 + upstream changes`, commit `0bd2e46`. It records full hashes in `fork/version.json` and generated `BUILD-METADATA.json`; exact release bases omit the later-changes suffix. Packaging validates pinned tag identity and ancestry and checks freshness against available official upstream tracking refs. No runtime network requests, preferences, background work, source-project edits, or regular DockDoor UI changes are added. Nineteen isolated Git-history cases, working-source preparation, one-build version-override checks, and the signed Debug build passed. The initial macOS launch request failed with -600; a retry succeeded and the exact development executable, signature, and embedded fields were verified. User manual UI verification passed. Committed-source Release preparation passed after the implementation commit; the full Xcode test suite, a new complete Release package, and a downloaded-installation test have not been performed. Records must be refreshed after upstream merges; an offline clone without an upstream tracking ref cannot independently establish that the recorded base is the newest merged upstream state.

### Traffic-Light Button Dimming

Both dimmed visibility choices dim only the traffic-light buttons, leaving the material pill undimmed, across Dock, Cmd+Tab, Window Switcher, Compact Mode, and mock previews. Whole-control hiding still follows preview hover/visibility and retains the stable pill layout. This corrects the fork’s `c832c1f` modifier-order change without restoring its conditional pill creation. Forty source-derived visibility/dimming checks, modifier-order checks, and the signed Debug build/relaunch passed; committed as `afa75e4` with user approval. Manual visual verification was not separately reported. The full Xcode test suite was not run. No new timers, observers, or discovery work are added.

### Control-Pill Borders

All material pills (search, titles, Space/state indicators, and traffic lights) use upstream’s subtle primary-color outline at 10% opacity and 1.5-point width rather than the preview container’s configurable white rim. Search uses the same shared style; there is no search-specific border override. Container border settings still control the preview container, not individual pills. The shared pill renderer still provides blur, highlight overlays, and padding; no per-mode copies or new background layers are added. This limits the broader styling effect introduced by `12e0a77`; it is not a claim that the reported artifact was a duplicated background. Source checks and the signed Debug build/relaunch passed. User visual verification passed; committed as `07c6793`. The full Xcode test suite was not run.

## Final Review Follow-Ups

The October 11 final review led to targeted safety fixes, not new top-level features. Space navigation reads the cache without applying the switcher display sorter, rejects unrelated or ineligible windows before Accessibility reads, checks the remaining candidates off the main thread, and revalidates request identity and Space membership before activation. This preserves desktop/fullscreen destination behavior and front-to-back candidate ordering without adding discovery, observers, or repeating work. Resize delays share one conversion bounded to the existing 0-1 second range; non-finite values use the corresponding default. Debug log limits are bounded to the existing 1-100 MB range before byte arithmetic. Neither fix rewrites saved preferences or changes the backup format or normal slider behavior.

The packaging guide's current upstream-base example now matches `fork/version.json` (`7be384b`). Historical Release candidate validation remains unchanged; it does not validate these working-tree fixes. Validation: 55 isolated native-tab, scrolling, swipe, and numeric-boundary tests plus 19 version-metadata cases passed. The extracted production candidate-filter probe performed zero AX reads. The final certificate-signed Debug build and exact-path relaunch passed; installed/built binary and reviewed-source snapshot correspondence were verified. An earlier build attempt caught a log-helper type mismatch, corrected before the final build; an intermediate launch returned macOS error -600. No live preferences were reset or imported. User manual regression verification passed October 12 for the scenarios tested; no exhaustive display/OS coverage is inferred. The full Xcode suite was not run. Space safety is committed as `1b73971` and numeric safety as `221265f`. Recency tracking remains explicitly deferred to upstream.

Previous committed-source candidate, October 12, 2026: `0cabb33081550df578d6ca39569d3a65ae6d0bb8` passed the arm64 Release build and includes upstream through `7be384b` plus both final-review safety fixes. All nine checksums, ZIP integrity, extracted nested ad-hoc signatures, all 219 bundle entries (contents, modes, symlinks), byte-exact committed source archive, clean overlay application, committed preset/license/install-guide/patch correspondence, source/upstream metadata and disabled upstream updater feed were verified. The 19 version-metadata cases passed. Output: `fork/dist/DockFork-0cabb33-amzRCD/DockFork-0.1.0-0cabb33-arm64.zip`. The Release app was not installed, launched, or published; the preset was not imported. Downloaded/quarantined installation, manual Release feature testing, and minimum-OS compatibility remain pending. The signed development instance and live preferences remained unchanged. A later documentation-only commit records this validation; it does not change the candidate's app sources or embedded source identity.

## Public Testing Fork

October 12, 2026: [hexcrete/DockFork](https://github.com/hexcrete/DockFork) is established as a public fork of ejbills/DockDoor. The fork's development branch `better_dd_merged` is published as its default; upstream `main` is retained and local backup branches are not uploaded. The source history and original GPL attribution remain intact. A marker-based check of 51,796 fork-history lines found no common credential markers, and no sensitive/generated file paths were found in fork-only history; this is not a comprehensive secret-scanner certification.

Inherited Actions are disabled pending fork-aware review; no GitHub CI success is claimed. Issues are enabled. No Release, release tag, upstream PR, screenshot or recording is published by repository setup. The verified local Release candidate and its installation/testing boundaries remain as recorded above. Showcase media will be assembled during multi-user testing rather than blocking the initial prerelease.

Settings file-dialog follow-up, October 12: a development-instance hang sample showed Import waiting in macOS file-panel initialization while still inside a SwiftUI button update, before decoding a backup. Import and Export now defer their existing dialog operation to the next main-queue turn and share a reentrancy guard. Existing preview suspension, modal confirmation, backup format, and preferences are unchanged. The extracted production guard passed deferred-execution, overlapping-request, and reopening checks. The certificate-signed Debug build, strict signature verification, and exact-path relaunch passed. User reported the fix working October 12. Committed as `4fdaa56`; the existing `0cabb33` Release candidate does not include it. Full Xcode tests and Release verification of this fix have not been performed. The running app reported regular activation policy during investigation, so no Dock-icon policy change is justified by the evidence collected.

Latest committed-source candidate, October 12, 2026: `36e635e8f0ad35cdd90fb390b3aa0195cefdd8b2` includes the Import/Export dialog fix and passed the arm64 Release build. All nine checksums, ZIP integrity, unpacked deep/strict ad-hoc signatures, 219 bundle entries, byte-exact source archive, overlay application, committed preset/license/install-guide/patch correspondence, source/upstream metadata and disabled upstream updater feed passed verification. All 19 version-metadata cases passed. Output: `fork/dist/DockFork-36e635e-UoauGA/DockFork-0.1.0-36e635e-arm64.zip`. Version remains 0.1.0, based on DockDoor 1.40.7 plus upstream through 7be384b. The Release app was not installed, launched or published; no preset was imported. Downloaded/quarantined installation and manual Release testing remain pending. The existing development app and preferences were not replaced. ZIP SHA-256: `22ec9f8c8bd8083b15f9d2983b5603cf689241f7a81b7c517d4ad41d5e30e0d5`.

Prerelease preparation, October 12, 2026: the user reports successful testing of the `36e635e` Release candidate on additional Macs running macOS 27, using locally transferred packages. Specific hardware configurations and individual feature scenarios are not inferred. Downloaded/quarantined Gatekeeper installation remains pending. A repeated privacy check scanned 431 app/source files and ZIP sidecar metadata, plus all 237 showcase preferences including nested shortcut JSON. No configured credential markers, private home paths, personal signing identities in the app, or private preset payloads were found. Upstream attribution, public GitHub identities, an upstream translation placeholder, and Sparkle's generic CI paths are intentional; this is not a comprehensive secret-scanner certification. All nine asset checksums passed again. Only the documented release-asset allowlist will be uploaded; development builds, logs and private notes remain excluded. Publication is not yet complete.

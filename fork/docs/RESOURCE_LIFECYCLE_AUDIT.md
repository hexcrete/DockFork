# Optional-Feature Resource Audit

Checked October 8, 2026, against upstream `0bd2e46`; commit references below follow the current fork history. This is a targeted source audit and a read-only badge-notification probe, not a whole-application performance certification. No new regression tests were added or live preferences reset.

## Badge Notifications

The local macOS 27 Dock exposed 22 application items, including one badged item. All 22 rejected both `AXValueChanged` and `AXTitleChanged` registrations with `notificationUnsupported` (-25207), while the existing Dock-list selection notification registered successfully. The probe removed registrations and did not alter badges, print their contents, or request additional permissions.

[Apple's registration API](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification) explicitly allows unsupported-notification responses. [AltTab's current badge implementation](https://github.com/lwouis/alt-tab-macos/blob/master/src/switcher/state/Applications.swift) also uses throttled Accessibility reads rather than a badge-change observer.

There is no verified notification replacement to recommend from this investigation. This does not prove that every private notification on every OS version is unavailable. Retain the existing shared one-second refresh while visible badge consumers exist; do not add another observer or increase polling frequency without evidence.

## Checked Paths

| Area | Finding | Origin / next step |
|---|---|---|
| App badges | Conditional overlay creation; polling starts with subscribers and stops without them. Cleanup no longer creates the store. | Fork cleanup fixed in `6f05d62`; no further change recommended here. |
| Edge auto-scroll | Disabled state clears requests; timer requires overflow and an available edge, and stops at the boundary or teardown. | Fork; inspected guards appear appropriate. |
| Spring-loading | Off prevents new delayed hover tasks; leaving, identity changes, and disappearance cancel them. An already pending task does not recheck the enable preference before activation. | Fork; follow up on disabling during a pending operation. Keep release activation separate. |
| Focus fade | Mouse monitors and fade timer are gated and removed when ineligible. Its preference observer remains installed even when all modes are disabled. Menu tracking also serves shared preview interaction and must not be removed as if it were fade-only. | Fork; consider observing enable switches separately from enabled-feature parameters. |
| Diagnostics | Debug off does not start the heartbeat timer. Calling cleanup while never enabled still initializes the diagnostics queue and dispatches a cleanup block. | Fork; consider a non-creating, race-safe stop path. |
| Context menus / drag ghost | Menus and ghost windows are created on demand, but preview dismissal instantiates their lightweight controllers through `shared`. | Fork; potential non-creating cleanup, not an observed timer or capture leak. |
| Live capture | Confirmed per-mode disablement could leave cached streams running indefinitely. The fix tracks requesting contexts, observes enable switches only while cached captures exist, and synchronously invalidates pending starts before asynchronous shutdown. Cleanup is identity-checked to protect replacement captures. | Also present upstream; fixed in `e8d0ad5`; build and manual immediate/timed shutdown checks passed. Existing Dock-controlled full-size capture behavior is preserved. Duration editing fixed in `9efa1cc`. |
| Swipe launcher | Listener construction is gated by Window Switcher and swipe enablement. Settings require restart; callback checks the flags too. | Inherited upstream design. Do not claim immediate teardown when a restart is pending. |
| Shared media service | Activated at launch regardless of widget enablement. It also supports media-source detection and actions, so widget state alone is not a sufficient gate. | Also present upstream; map every consumer before changing activation. |
| Core discovery / event routing | Cache observers, Dock monitoring, and shared key routing serve multiple modes and actions. | Shared infrastructure; do not disable based on one optional feature's switch. |

## Suggested Follow-Up Order

1. Pending spring-loading cancellation when disabled, preserving release fallback.
2. Non-creating diagnostics cleanup with correct start/stop ordering.
3. Smaller allocation/subscription improvements for menu/drag cleanup and focus-fade parameters.

Live-capture shutdown and duration editing are complete. Keep the remaining lifecycle changes separate and validate each with build/relaunch and manual scenarios before committing; do not infer a measured CPU improvement from source inspection alone.

## Dock Cycling Follow-Up

October 10 Dock cycling follow-up (`dc5a805`): the existing Dock event tap includes mouse-up/drag events only while the cycling override is enabled. A per-tap tracker retains at most one copied mouse press; drag, release, disabled-tap recovery, replacement, and teardown discard it. The callback context has a weak observer reference and stays alive until event-thread invalidation completes. Settings observation uses weak captures; no additional event tap, timer, polling, or drag-path discovery is introduced. Signed Debug build/relaunch, seven press lifetime/copy checks, and user manual verification passed. Reviewed source matches the tested build; full Xcode suite not run. This follow-up is not a rerun of the October 8 audit or a measured performance comparison.

Keep-open cycling option (`b7faf95`), October 11: reuses the coordinator's one-second, target-PID app-activation suppression. Hiding the panel clears it; expiry, other app activation, mode mismatch, or disabling the preference invalidate it. Space changes are never suppressed. Preservation checks the selected target's live Space membership, with cached membership fallback and conservative dismissal when unknown, through the shared Unhide/Un-minimize transition helper. The check runs only for an eligible visible Dock container; async restoration rechecks before final activation. No new observer, timer, event tap, synchronous AX read, Dock monitor, or repeating work is introduced.

Existing active-focus refresh remains coalesced and border-gated. Focus-only grid updates refresh the old/new borders without geometry work. Source-PID validation rejects background-app focus notifications; actual click coordinates avoid stale hover-state gating. The 444 updated transition/preservation cases passed, including zero topology reads when ineligible; earlier 120 focus, 50 card-refresh, and 7 press checks passed. Latest signed Debug build, exact-path relaunch, signature and source-snapshot verification passed. User manual verification passed for the tested transition scenarios; no separate hardware/display coverage is inferred from that approval. This is not a rerun of the October 8 audit or a measured CPU comparison; full Xcode suite not run.

## Scroll Geometry Follow-Up

October 11 targeted review: content-size updates in the shared AppKit card grid could clamp the logical offset without committing the corresponding view origin. This omission dates to upstream `23fccf2`, not the fork's edge-scroll changes. The fix (`295ef75`) commits on content-size updates, using the existing no-op guard when the offset is unchanged. Viewport-size and axis-change paths already do so. Layer-only scrolling, timer ownership, weak captures, and teardown remain unchanged; no additional repeating work or measurement is added. Production-container coordinate checks and both-axis regression cases passed in an isolated native harness; signed Debug build/relaunch, reviewed source correspondence, and user manual verification of the reported issue passed. Separate all-mode/display manual coverage is not recorded, and the full Xcode suite was not run. This is not a rerun of the October 8 resource audit or a measured performance comparison.

## Default Compatibility

An unset main shortcut uses Either-side Option, and unset traffic-light scale is 1.0, matching upstream. Explicitly stored user choices remain unchanged. New-feature defaults and removed-preference compatibility were deliberately not changed in this pass.

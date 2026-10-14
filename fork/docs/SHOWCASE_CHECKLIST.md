# DockFork Showcase Capture Checklist

This is a menu of possible captures, not a requirement to record everything. Select rows, then attach the chosen media to [Changes and Showcase](CHANGES_AND_SHOWCASE.md). The commit ledger groups the complete implementation history for each topic.

Feature audit: `9efa1cc` against upstream `0bd2e46`, October 8, 2026; publication/defaults/control-spacing additions reviewed through `09a2cc2` on October 9. All capture selections below remain undecided. No media has been captured or approved by this checklist.

## Capture Conventions

- Use harmless sample window titles, files, browser pages, events, and music. Hide notifications and redact usernames, license details, logs, and app-specific private data.
- Record the current fork build, appearance settings, keyboard layout, and relevant toggles. Use a visible keystroke annotation for keyboard-only behavior.
- The latest optional preset refreshed October 11, 2026 in `9fcf28d` contains 237 reviewed preferences, including Popover app headers, Automatic switcher app-icon sizing, retained Dock cycling previews, dimmed hover-only traffic lights, embedded Dock/Cmd+Tab controls, compact-style windowless rows, updated shortcuts, and compact thresholds of five. Captures must reflect the settings actually used; no preset import or media capture is inferred from the JSON privacy review. The committed-source Release candidate `9fcf28d` includes this preset and the recent shared preview-centering/scroll-geometry fixes; build, checksums, ZIP integrity, signatures, source/preset correspondence, and metadata verification passed (see the release record in `fork/README.md`); earlier candidates contain older presets. No import or downloaded-installation verification of this latest refresh is recorded.
- For before/after media, use the same windows and settings on both builds. Clearly label historical comparisons versus comparisons with current upstream; do not attribute an upstream feature to the fork.
- Prefer short MP4 clips for interaction and PNG screenshots for settings/static layout. Chosen publication media goes in a reviewed repository asset directory; no empty or broken embeds are needed now.
- Capture light and dark mode for styling claims. For shared behaviors, add Dock/Cmd+Tab/Window Switcher examples where practical, not three copies of every video.
- Don't reproduce real hangs, crashes, destructive actions on valuable windows, or reset your live preferences to make a recording.
- Optional missing-image tests require a temporary mock build. Remove that change and rebuild before making a release.

## Development Selection Captures

These candidates require the new development build, not the published 0.1.0 release. Selection controls are committed and manually verified; batch actions also passed user manual verification October 13. No capture is recorded.

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | M01 | Screenshot: selection controls | Enable multi-window selection. Compare title-side Dock/Cmd+Tab controls, Window Switcher icon overlays, and Compact Mode. Include hidden titles/app headers, checked-only visibility, enlarged font-height title controls and material-backed icon checkboxes. Compare all three App Header Styles for the optional summary. Verify Compact On title hover responds only over the icon, including with mouse hover selection disabled; compare title/icon-hover fading with preview-hover fading, including animations disabled and Reduce Motion; preview-hover checkboxes must not interrupt traffic-light sliding; verify repeated held-shortcut cycling preserves ordered checks and highlight after both middle-click and assigned keyboard selection; verify keyboard actions followed by initializer release retain checked sessions. | `fa76e57`, `a4150a5` |
| [ ] | M02 | Video: ordered checks and session pinning | Enable Show selection summary, check several windows, filter one out, show counts, then uncheck/recheck. Use Select All with a search filter and verify it adds only displayed real windows, preserving earlier outside-view checks; repeat via an assigned shortcut with no highlight (Select All user verification passed October 13; capture pending). Enable Keep Window Switcher open when windows are selected to verify initializer release keeps the standalone switcher open; with it Off (default), checks must leave held-modifier/swipe dismissal unchanged (user verification passed October 13 for both modes; capture pending); Escape or an outside click dismisses the container and clears checks. Label this selection-only, not batch actions or tiling. | `fa76e57`, `a4150a5` |
| [ ] | MG01 | Video: checked-group actions | Compare checked versus unchecked initiators; mixed groups minimize/hide, uniformly minimized/hidden groups restore; fullscreen entry affects only the initiator, while exit affects all selected fullscreen members. Include fullscreen eligibility exclusions, same-app versus multi-app hide/quit, search-filtered checks, partial failures, and Space menu/number moves with follow Off/On. Capture basic batch actions here; directional group tiling belongs to MT01. | `c827932` |
| [ ] | MG02 | Video: checked-group dragging | Drag a checked group in regular/Compact Dock, Cmd+Tab and Window Switcher; show ordered icons, relative placement and edge clamping. Compare unchecked single dragging; include hidden/search-filtered members, another display, partial failures/cancellation, and Aero Shake Except protecting the whole group. No tiling yet. | `313e213` |
| [ ] | MT01 | Video: automatic and directional tiling | Assign Auto Tile Selected Windows. Show 1/2/3/4 checked windows, first-check leadership, Half direction and Quarter cells; then a larger grid, expanded last row, repeated overflow layouts, 1x1 move-only, 6x6 limits/warning, foreground On/Off, single-window Auto Tile, hidden/minimized members and current-Desktop relocation. Compare unchecked single actions and no-highlight keyboard activation; show shared context/menu-bar entries and scripting examples. | `6ae187c` |

| [ ] | MS01 | Video: scripted ordered window lists | Query window IDs, then use ordered lists without an open preview for mixed-state minimize/hide, directional Position, and confirmed Space moves with switching Off/On. Compare text-ID calls, exit-only fullscreen lists, duplicate IDs and partial failures. Focus remains single-window. | `d5bdb48`; live verification passed October 13, capture pending |

| [ ] | MT02 | Video: drag previews onto previews to tile | Enable dragging windows together to tile them in Mouse Actions. Test single-window drops with multi-selection Off; enable multi-selection for groups. In regular/Compact Dock, Cmd+Tab and Window Switcher, drag one unchecked window onto another, a checked group onto an unchecked target, and an unchecked window onto a checked target group. Show target-first order, self-drop no-op, 1x1 move-only, off-Space target Desktop/display selection, both scroll axes and edge-scroll release coordinates. Verify unavailable/windowless targets chime without dismissing. Compare preview/file target highlights, including compact rows with matching background bounds and undimmed drag feedback when unselected-content opacity is reduced; verify clearing on release/Escape/new sessions, no self/group highlight, and no file spring-loading during preview dragging. Drag foregrounding ignores the resize foreground preference. Feature Off retains free placement; ordinary drag-away and Aero Shake remain unchanged. | `7a6ec7d`; compact highlight follow-up passed user verification October 13; capture pending |

## Cmd+Tab First-Use Hint

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | CT01 | Video: one-time preview-focus hint | On a disposable fresh profile, open native Cmd+Tab previews while unfocused, then hover a preview and move into a gap. The tutorial must not return. Compare preview-cycle keyboard focus and reopening; settings mock previews must not acknowledge live onboarding. Do not reset the author's live preferences for a capture. | Development fix; user verification and review passed October 13; capture pending |

## Compact and Windowless Cards

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | W01 | Screenshot pair: independent compact width | Keep normal preview width constant; change compact width and compare the same rows. | `e3b7a83` |
| [ ] | W02 | Screenshot: compact state/title formatting | Include normal, minimized, hidden, and windowless apps; compare state placement options without losing the actual title. | `2a79e61`, `c95f197`, `628ddde` |
| [ ] | W03 | Screenshot grid: placeholders | Compare embedded/non-embedded and dynamic/fixed sizing; compare Dock/Cmd+Tab windowless “Show full size previews” On/Off outside Compact Mode and verify shared title styling, control scale/visibility, alignment, and edge spacing (user manual verification of the full-size feature passed; capture not yet recorded). With non-embedded controls, verify screenshot/app-icon centering on regular, missing-image, and full-size windowless cards; manual verification of the centering fix is pending. Optionally omit one mock screenshot and show full-size real-window controls. | `7b2491a`, `7368daf`, `717c1e0`, `0b961e1`, `e2667b3` |

## State and Space Controls

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | I01 | Screenshot: state indicator variants | Show Space plus state, state without number, and pill/unstyled variants. Use one Desktop to exercise state-only presentation. | `411618f`, `20d3b2f`, `356af10` |
| [ ] | I02 | Screenshot: current-Space highlight | Put windows on two Spaces; highlight the current one in pill and circle modes. | `6248aab` |
| [ ] | I03 | Screenshot matrix: control ordering | Swap traffic/state controls, including compact-only restriction; mix styled and unstyled controls with embedding on/off. Compare hover-hidden and permanently hidden traffic lights beside an unstyled, non-embedded indicator: no empty-slot gap. | `b435c0a`, `f7b64c9`, `9ce4a89`, `ba71716`, `09a2cc2` |
| [ ] | I04 | Screenshot: font and small rows | Compare indicator font sizes and small compact rows without clipped rings or pills. | `f933cd0` |

## Spaces

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | S01 | Screenshot pair: destination menu | Include an empty Desktop, a populated Desktop, and fullscreen/tiled Space; show number/full-name modes, icons, disabled rows, and Current badge. | `cdd7b82`, `5adb65f`, `381e839` |
| [ ] | S02 | Video: move and optionally follow | Move a normal window, then a minimized/hidden window; compare destination-follow off/on. Verify source and destination with Mission Control. | `cdd7b82`, `30b66fc` |
| [ ] | S03 | Video: physical numbered shortcuts | Enable Spaces shortcuts; move a selected preview and navigate with an unhighlighted persistent switcher. Include Czech layout without Shift if available; demonstrate 0 means global Space 10 only if ten Spaces are set up. | `1c4ce38`, `2898dc6` |
| [ ] | S04 | Video: exit fullscreen from picker | Invoke the source-window Exit Full Screen item; show it exits without intentionally focusing the window and without losing the preview session. | `0dce6a7` |
| [ ] | S05 | Screenshot/video: multi-display grouping | Requires a second display and separate Spaces; show menu grouping and cross-display destination behavior. Mark untested if unavailable. | `cdd7b82`, `1c4ce38` |

## Shortcut Configuration

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | K01 | Video: configure rows before recording | Add an unassigned row; choose its action/scope before recording. Show add-button gating, removal, and a duplicate-trigger warning. | `6b62149`, `94b4361`, `93074e7` |
| [ ] | K02 | Screenshot: scope catalog | Show the alphabetized seven-scope picker; optionally record switching scope in place and Defaults versus All Windows. | `94b4361`, `d2d063c`, `982c6d0` |
| [ ] | K03 | Settings screenshot + video: modifier side | Show Main Window Switcher Shortcut, Left/Right/Either, inherited-side override, and side-aware Backward Key recording. Use harmless actions to prove physical-side handling. | `d013ee1`, `428b2af` |
| [ ] | K04 | Video: double-tap and full combinations | Configure persistent/last-focused rows with a multi-modifier combination and a side-specific double tap; demonstrate a single/long tap does not launch. | `19d4888`, `af0bbcd`, `06c9471` |

## Persistent, Swipe, and MRU Sessions

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | P01 | Video: menu-bar click assignment | Toggle persistent switcher with one button and the app menu with the other; repeat with opposite assignment. | `c9adbf9`, `c46bfae` |
| [ ] | P02 | Video: persistent mouse-first session | Release launcher modifiers; use preview actions, search, and Mouse Follows Focus. Show optional unhighlighted start. | `19d4888`, `2898dc6`, `1571630` |
| [ ] | P03 | Video: swipe/keyboard ownership | Disable conflicting system gestures first. Enable "Select highlighted window when swiping in persistent Window Switchers"; swipe into a persistent session, take ownership with Tab, start a new swipe, and explicitly invoke a modifier session. Show selection on release only for the owning session. | `78bfbf6`, `ae93b49`, `1f72ecb` |
| [ ] | P04 | Video: reverse selection | Show horizontal and vertical swipe selection before/after reversal. Describe direction relative to the selected row, not just finger motion. | `7797cdf` |
| [ ] | R01 | Video: last-focused shortcuts | Use three innocuous windows and known focus order; show repeated switching and filtered scope, including starting from the desktop. No speed claim without timing. | `af0bbcd`, `69507bc`, `bfaf5f4` |

## Window Actions and Menus

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | A01 | Video: Dock window cycling | Open three windows in one active app; click repeatedly during a hover session, then leave/re-enter the icon. With cycling enabled, drag its Dock icon to reorder it and verify dragging does not cycle windows. Repeat with an inactive app, then switch to Minimize/Hide and back without restarting. Drag-preservation follow-up: user manual verification passed; media capture pending. Compare Keep previews open when cycling through windows Off/On: the existing panel stays in place and the active border follows same-Space cycling, including minimized/hidden targets. Off-Space/fullscreen transition targets must dismiss the panel before activation; verify it never remains stranded after the Dock disappears. User manual verification passed for retention, focus/re-entry fixes, and transition dismissal; media capture pending. | `28075b2`, `dc5a805`, `b7faf95` |
| [ ] | A02 | Video: bulk actions and header buttons | Show Minimize All/restore and Close All on disposable windows; include fullscreen exclusion and unchanged inactive-app activation behavior. | `ffa82dd`, `4743b0e`, `df7bf47` |
| [ ] | A03 | Screenshot/video: post-action choices | Compare keep-open and foreground options for move/resize; show bring-forward remains available independently. | `bef9786`, `26f33aa` |
| [ ] | M01 | Screenshot: enriched context menu | Open Arrange and Move to Space; include symbols, state-dependent titles, shortcut hints, and matching Quit styling. | `16a68eb`, `5ef868b`, `5532376` |
| [ ] | M02 | Video: menu actions in each session | Press one configured action while a preview menu is tracking. Compare held alternate modifier, persistent main modifier, and Cmd+Tab Command. Show menu-bar hierarchy without hints. | `5532376`, `5d50fd8`, `be73708`, `ccfec9d` |

## Layout and Search

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | L01 | Video: horizontal/vertical grids | Use enough windows to overflow; compare Max Rows 1/2 and Ignore screen size limit off, then Tab and arrow traversal. Compact Mode stays vertical. | `19b3ddd`, `8af3b00`, `f4ccf61` |
| [ ] | L02 | Video: edge auto-scroll | Start with pointer already at an edge: no scroll until movement. Enter the edge zone, show stale highlight cleared, then return over a real card. Repeat relevant mode/axis options. At the scrolled end, close enough windows or filter results to remove a row/column; verify pointer highlights and clicks still match visible cards, including when content stops overflowing (user manual verification of the reported scroll-geometry issue passed; mode-by-mode capture not recorded). | `bbb44ad`, `08c52c6`, `f7e5a12`, `295ef75` |
| [ ] | L03 | Screenshot/video: search placement and focus | Fill a switcher, open search, and show no blocking overlap. Click its empty field: helper disappears; dismiss input: helper can return. | `586407f`, `9151f2d` |
| [ ] | L04 | Video: windowless-to-window transition | Hover a windowless app, create one disposable window, and show the panel resizing even though its entry count remains one. | `c802975` |

## Full-Size Previews

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | F01 | Screenshot pairs: opacity/blur/border | Use a harmless patterned background. Blur affects the backdrop, not the preview screenshot; demonstrate the border without outer overhang. | `97096c7` |
| [ ] | F02 | Video: fade durations | Disable Reduce Motion for this capture; compare zero and longer fade-in/out durations with the same window. | `3c0cf89` |
| [ ] | F03 | Optional video: experimental resting fade | Explicitly enable the per-mode experimental feature, pause on non-control content, then move again. Label Experimental / Off by default and disclose intermittent hover-selection issues; disable it afterward if selection becomes unresponsive. | `c2fa95d`, `220464d` |

## Dragging

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | D01 | Video: compact and regular preview dragging | Drag a real window within a display and across Spaces. Show center-based placement and ghost cleanup; optionally test app-icon fallback in a temporary fixture. | `a7d61d1`, `78f65dd` |
| [ ] | D02 | Optional video: cross-display drag | Requires two displays; drop a large window on a smaller display and show the resulting usable placement. Do not claim resizing never occurs if macOS constrains the window. | `78f65dd` |
| [ ] | D03 | Video: external drag spring-loading | Drag a disposable file over a preview, wait for activation/dismissal, and finish the native drag onto a supporting app. Show custom delay and cancellation on leaving early. Don't frame this as a Dock-icon reliability fix. | `1ceb007`, `ba665c2` |

## Reliability and Diagnostics

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | B01 | Video: native tab grouping | Show two same-frame Safari/Finder windows on an unfocused Space remaining distinct; tabs in each window remain grouped. Include hide/unhide if stable. For upstream `8ede8d0` integrated in `325ef3f`, select different native tabs before invoking the switcher and verify activation returns to the selected tab; user manual merge verification passed; media remains unrecorded. | `4f703ed`, `abdc4ec`, `6fb1946`; upstream `8ede8d0` |
| [ ] | B02 | Video: fullscreen metadata | Use ordinary and tiled fullscreen; show state and Space numbering after settling, including Mission Control-created fullscreen Spaces. No intentionally malformed captures. | `e2e4c45`, `a94bb4d`, `1a5a978` |
| [ ] | B03 | Screenshot: actionable nonstandard windows | Show a harmless Calendar Info pane with only supported controls; do not include an autofill suggestion popup as a real window. Optional compatibility-layer example. | `804d85a`, `288262b` |
| [ ] | B04 | Optional temporary fixture: missing image | Omit the first settings mock image, compare all three modes with dynamic sizing and embedding, then restore the fixture. Historical capture failures are not required. | `6fe02cc`, `717c1e0` |
| [ ] | H01 | Screenshot: diagnostic controls | Show size-cap controls and export UI with no private log contents. Explain artifacts survive relevant failures, not that every ZIP contains a hang report. | `77ee4d3` |

## Visual Polish and Automation

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | V01 | Screenshot pair: app badges | Use an app with a genuine Dock badge; compare normal/compact visibility and size while alignment stays fixed. | `424c16c` |
| [ ] | V02 | Screenshot: compact widgets and clipping | Enable calendar/media widgets next to compact rows; show aligned edges and scroll content inside rounded borders. | `a9f400a`, `9c7ac61`, `ef27fdf` |
| [ ] | V03 | Video: traffic-light visibility animation | Compare duration zero/animated and hidden/dimmed modes, including the extended 0.5-second maximum (default remains 0.1 seconds). With a positive duration, enable the app's Reduce Motion and then macOS Reduce Motion separately: both dimming and visibility must become immediate. Disable both, verify the saved duration still applies, then set zero and check other animations remain enabled. Cover regular/Compact Mode in Dock, Window Switcher, and Cmd+Tab; avoid presenting mock hover behavior as a live-window bug. Reduce Motion follow-up: user manual verification passed; media capture pending. | `b4ce12a`, `1aebbc5`, `1f7ce92`, `ae79432` |
| [ ] | V04 | Screenshot pair: mirrored title cluster | Compare left/right title controls in non-compact Window Switcher; app icon mirrors with the title. With Automatic sizing, compare named, unnamed, duplicate-title, and windowless headers: 35 pt when titles are eligible to appear, 20 pt otherwise. With hover-only visibility, highlight/hover each row and verify the size follows visibility, not title content. Confirm explicit sizes and Compact Mode are unchanged. Automatic-size fix: `bdc62ae`; build and user verification passed, with no showcase media recorded. Other modes do not gain nonexistent header icons. | `82a8449`, `bdc62ae` |
| [ ] | T01 | Example/video: scripted Spaces | List Spaces, move a disposable window with/without following, then switch by number or returned ID. Redact identifiers if desired. | `92908e2`, `da9f3f3` |
| [ ] | T02 | Example/video: scripted switcher | Address the packaged app with `tell application "DockFork"`; invoke the shared persistent switcher, including configured windowless apps and normal filters. | `4d38e51`, `ac90770` |

## Fork Setup and Defaults

For S01-S05, also check clicks near the unstyled number ring's edges in regular and Compact Mode across all three preview modes. The picker should open without activating the parent row; state-only and mock indicators remain noninteractive. Hit-target fix: `6a5599d`; build/relaunch and user verification passed, but no showcase media is recorded.

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | Q01 | Screenshot pair: added-feature defaults | Use an unset test preference domain, not a reset of live preferences. Show styled state/Space pills and compact-only swapping; include the Current badge and unavailable Spaces. Existing saved choices may differ. | `0127698` |
| [ ] | Q02 | Optional video: showcase preset | Export the test configuration first, import the reviewed preset into DockFork, restart, and show selected appearance/shortcut choices. Disclose that import replaces settings and the preset is optional, not app defaults. Redact permission/account details. | `287c38f`, `9fcf28d` |
| [ ] | Q03 | Screenshot: fork/upstream version identity | In the packaged app, open Support > Updates and show the distinct DockFork version and incorporated DockDoor release/commit. Hover for the full base hash if helpful. Initial metadata: DockFork 0.1.0, DockDoor 1.40.7 plus later changes through 0bd2e46; this is not a published DockFork release. User manual verification passed; media capture pending. | `b674d9c` |

Packaging, signing, and contribution-boundary changes do not need screenshots. Record build/install validation separately in the packaging guide; media cannot establish signature trust, permission retention, or upstream readiness.

## No Required Screenshot

Import/export modal regression: with Dock or persistent Window Switcher previews open, open Import or Export Settings. Existing previews should close; Dock hover, switcher shortcuts, and trackpad launches should not open previews while the dialog owns input. Cancel, then verify every launcher works on the first attempt. Repeat import confirmation cancellation and invalid-file errors without applying a preset or resetting preferences. Fixed in `6c51d22`; build/relaunch and user verification passed. No showcase media recorded.

Cache locking, event snapshots, cancellation ownership, debounce/coalescing, numeric guards, common menu/layout construction, build-ignore rules, and upstream merges belong in the ledger and technical notes. Screenshots cannot prove their correctness or performance. Existing tests and real regression scenarios are better evidence; publish performance claims only with measurements.

Traffic-light dimming follow-up (`afa75e4`): compare dimmed buttons against the undimmed pill in both dimmed visibility options; cover compact/regular, embedded/non-embedded, light/dark, and unstyled controls. Keep hover-hidden pills fully hidden. Manual verification and media capture pending.

Control-pill border follow-up (`07c6793`): compare title, Space/state, and traffic-light edges with upstream in light/dark appearances, styled/un-styled and highlighted-current-Space states; verify search uses the same subtle pill border while preserving its size, placement, and input behavior. User visual verification passed; media capture pending.

Final-review safety follow-up, October 11: no new screenshot feature. For S03/S05, regression-test navigation to populated, empty, and fullscreen Spaces and rapid replacement requests; verify the newest request wins. An unrelated slow app must not be queried just to select a different Space. Numeric boundary tests for resize delays and log caps are automated technical evidence, not showcase media; do not import deliberately invalid preferences into the live app. Final signed Debug build, exact-path relaunch, source/binary correspondence, 55 isolated regression tests, 19 version-metadata cases, and zero-AX candidate filtering passed. User manual verification passed October 12 for the tested scenarios; media capture remains pending. Fix references: `1b73971` and `221265f`.

October 12 Release candidate `0cabb33` is available for future captures and manual installation tests at `fork/dist/DockFork-0cabb33-amzRCD/DockFork-0.1.0-0cabb33-arm64.zip`. Build, nine checksums, ZIP/extracted-bundle/signature, source/asset correspondence and metadata checks passed. Release installation/launch, downloaded/quarantined testing, preset import and media capture remain unperformed. Do not infer those from the approved signed Debug tests. The candidate uses DockFork 0.1.0 based on DockDoor 1.40.7 plus upstream changes through 7be384b.

Public fork setup, October 12: source is available at https://github.com/hexcrete/DockFork. Initial testing will precede fork showcase screenshots/recordings; all existing capture IDs and unchecked media status remain unchanged. Upstream README images are upstream examples, not evidence of DockFork capture or approval. Repository creation does not publish the local Release candidate.

October 12 file-dialog regression follow-up: test Import and Export from General settings, cancel each, and repeat. Confirm the chooser opens promptly, the settings window remains usable, the Dock icon is visible while settings are open, and preview launchers recover on cancellation. Do not apply a backup just to test dialog opening. Test the real import separately with an explicitly approved backup. The user reported the development fix working October 12; committed as `4fdaa56`. The `0cabb33` Release ZIP does not include it, and no Release verification of this fix is recorded. No capture status changes.

Rebuilt October 12 candidate `36e635e` supersedes `0cabb33` for testing and future captures: `fork/dist/DockFork-36e635e-UoauGA/DockFork-0.1.0-36e635e-arm64.zip`. It includes the settings-dialog fix. Build, nine checksums, ZIP/extracted-bundle signatures and correspondence, source/assets/overlay/metadata, and 19 version checks passed. Release installation/launch, preset import, downloaded/quarantined tests and media captures remain unperformed. No capture IDs or approval checkboxes changed.

October 12 user-reported Release testing: `36e635e` works on additional Macs running macOS 27 after local transfer. Downloaded/quarantined installation remains pending; no individual feature, hardware or preset-import claim is inferred. Media capture status remains unchanged.

Draft release `v0.1.0`, October 12: ten approved assets and release notes are uploaded and download-back verified against candidate `36e635e`. Tag ancestry matches the tested source. Publication remains paused; authenticated draft downloads do not establish public links or browser quarantine/Gatekeeper behavior. No media status changes.

Public prerelease `v0.1.0` is available at https://github.com/hexcrete/DockFork/releases/tag/v0.1.0, using candidate `36e635e`. All ten public asset links and an anonymous ZIP checksum were verified. macOS 27 local-transfer testing is user-reported; browser/quarantine/Gatekeeper verification and showcase media remain pending. No capture IDs or media checkboxes changed.

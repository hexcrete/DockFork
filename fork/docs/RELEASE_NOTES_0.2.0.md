# DockFork 0.2.0 Prerelease

Status: [published as a prerelease](https://github.com/hexcrete/DockFork/releases/tag/v0.2.0) October 17, 2026, from exact tested source `c863e628d17d8c80985cd77533ff94db03d6444a`. No rebuild. Ten uploaded assets, remote tag, release state and public downloads verified; original 0.1.0 assets untouched.

**Published with the user's authorization. This is a public prerelease for continued testing.** The updated optional preset is not imported automatically. Screenshots and recordings are deferred and are not a release gate.

## Release Notes

DockFork is a GPL-3.0 fork of [DockDoor](https://github.com/ejbills/DockDoor). This second testing release adds multi-window selection, group actions and automatic tiling, alongside preview and interaction fixes.

## Multi-window selection

- Select windows in Dock, Window Switcher and Cmd+Tab previews using checkboxes, configured shortcuts or mouse actions.
- Selection follows the order in which windows are checked and survives filtering.
- Select All selects the currently displayed, filtered windows.
- The selection summary provides Select All, Clear Selection and Tile Windows. In Window Switcher, it also shows an app icon for each selected window.
- An optional setting keeps Window Switcher open while windows are selected.
- Window Switcher can also select windowless apps. Only Quit and Open New Window act on those entries.

## Group actions and dragging

- Apply supported preview actions and confirmed Space moves to selected windows.
- Mixed groups minimize or hide when any applicable window is restored or visible; they restore only when all applicable windows are minimized or hidden.
- Group fullscreen actions exit fullscreen. Entering fullscreen remains a single-window action.
- Drag selected windows together across Desktops and displays.
- Optional drag-to-tile combines the target window or selection with the dragged windows, placing the target group first.

## Automatic tiling

- Auto Tile arranges windows in selection order, with configurable limits up to six rows and six columns. Defaults are two rows and three columns.
- Overflow windows stack within the same cells. Enable Tile only what fits to leave excess windows untouched.
- Half/Quarter Fill actions normally apply independently. An optional setting makes them use direction-aware Auto Tile for multiple selected windows.
- Optional linked resizing adjusts neighboring windows within the same tiled layout.
- Applications' minimum window sizes remain respected.

## AppleScript

- Existing window-action commands accept ordered lists of window IDs without requiring UI selection.
- Single-window and list commands share action failure reporting and the move/resize foreground preference.
- Single-window fullscreen commands toggle fullscreen; lists only exit it.
- Tile Windows exposes ordered automatic tiling directly.

## Fixes and UI polish

- More reliable tiling, foregrounding and completion of released window drags.
- Preview controls adapt to narrow widths, progressively moving actions into native More menus.
- Improved App Header and selection-summary alignment, sizing, hover boundaries and click handling.
- More reliable cleanup after closing large groups or quitting selected apps.
- Corrected Compact Mode drag-target highlights.
- Improved embedded-title contrast and a reusable native search-clear button.
- Corrected Dock cycling behavior for inactive, single-window and windowless apps.
- Improved activation-recency handling for newly launched applications.
- Selection controls expose accessibility selected-state information.

## Included from DockDoor 1.41.0

Two-finger window gestures, swipe-switcher sensitivity, custom-dock screen reservations, stricter Dock-hover validation and updated translations. These are upstream capabilities, adapted to work with DockFork's selection, tiling and session behavior.

## Defaults and optional preset

Multi-window selection, selection-driven keep-open behavior, drag-to-tile and linked resizing default Off. Enable selection under **Keybinds > Window Selection** and configure layouts under **Keybinds > Tiling**.

The optional showcase preset enables these features and includes customized appearance and shortcuts. It is never imported automatically. **Export a backup first: importing replaces existing settings.**

## Installation and limitations

- Apple Silicon build, ad-hoc signed and not notarized. Updates are manual.
- Quit other DockDoor/DockFork instances before launching. Rebuilt releases may require granting permissions again. When upgrading, an old permission entry can remain enabled but stop authorizing the replacement app; quit DockFork, remove the affected Accessibility or Screen Recording entry in System Settings, add the replacement app and enable access again, then relaunch.
- Follow macOS Privacy & Security approval procedures; do not disable Gatekeeper.
- Partial batch failures retain successful changes rather than rolling them back.
- Release build, signatures, checksums, source correspondence and privacy-marker checks passed. Testing is ongoing; downloaded/quarantined installation and older-macOS compatibility remain unverified.
- Spaces Bar, pinned floating windows and the slide-out switcher are not included. Experimental full-size-preview container fading remains Off by default with known hover limitations.

These are highlights, not the complete list. See the [changes guide](https://github.com/hexcrete/DockFork/blob/better_dd_merged/fork/docs/CHANGES_AND_SHOWCASE.md) for details. Screenshots and recordings will follow during testing.

Report problems through [this fork's Issues page](https://github.com/hexcrete/DockFork/issues). Review diagnostic logs for private information before attaching them.

## Historical Preparation Checks

The user-edited fork settings explainers have been shortened and grammar-reviewed in both the settings UI and search catalog. The temporary editing worksheet is not included in the release source. No defaults or application behavior changed.

October 16 preparation is reviewed through `d17f1b55`, plus the replacement preset and preflight documentation. It includes upstream integration `229d38a`, the gesture-minimization adapter, linked-resize timing and drag-lifetime corrections, configurable overflow, opt-in grouped Fill and revised helper text. Evidence below is scoped to the actual tests; it does not certify every display/app combination or a Release package.

| Area | Current evidence and remaining work |
|---|---|
| Source and documentation | Exact-once ledger coverage includes 318 commits through c863e62, with changed-file counts checked against Git. Settings paths, defaults, labels, search targets and action routing pass the source-only audit. This publication-record commit remains outside that explicit coverage boundary until its next ledger update. |
| Version metadata | All 19 validator cases pass again. The recorded merged upstream base is 3e08721, and its included stable release 1.41.0 resolves to 3d6a3cba. The record keeps DockFork 0.2.0 separate and validates committed ancestry. This preflight does not fetch or merge newer upstream history. |
| Debug validation | Feature validation through 3b4d311 included source-overlay/binary correspondence and 97 isolated unit tests. The later helper-copy update passed its own signed Debug build, signature check and fixed-path relaunch. This preflight re-ran 11,664 layouts, 2,660 linked-edge resizes, registry/placement/drop regressions and frame-writer checks with simulated native APIs. No full Xcode suite, new native sweep, whole-app performance/leak certification is claimed for that earlier pass. The actual Release candidate is recorded below. |
| Latest tiling/focus sweep | 27 scripted tiling calls with three expected minimum-size refusals, four rapid-focus pairs and four cross-Space focus checks passed without unexpected failures. Frames, Spaces, accessibility flags and original focus were restored. The later partial-write refresh correction has focused regression and signed Debug validation, not another full live sweep. |
| Showcase configuration | The supplied 249-setting export is reduced to 246 recognized preferences. Three system/private-state keys are removed, logging is Off, and two UUIDs are replaced with generic IDs. All 15 nested shortcut records and format/privacy checks pass. The replacement is not imported; actual Release import testing remains pending. |
| Release candidate and privacy | Not built. Audit the actual app, source archive and sidecars after the final preset and preparation commits. Existing 0.1.0 audits do not certify 0.2.0 assets. |
| Installation and media | Release upgrade/import and browser-quarantine/Gatekeeper testing remain pending. Screenshots and recordings are deliberately deferred. |

The ledger coverage boundary is explicit in [COMMIT_LEDGER.md](COMMIT_LEDGER.md); an uncommitted preparation or future commit is not silently included. No preferences were reset and no showcase media or Release validation is inferred from these checks.

## Publication Gate

- Configuration supplied, sanitized and reviewed. Keep a backup before any later import test; the 246-preference preset is optional and replaces settings on import.
- Complete: the reviewed preset and preparation are committed. The candidate keeps the agreed 0.2.0 prerelease version.
- Complete: the authorized Release build uses `./fork/package.sh` from exact commit `c863e62`, without a working-tree overlay. Do not distribute the development app.
- Complete: source, package directory, version/base metadata, identity, ZIP integrity, source/patch correspondence, nested signatures and allowlisted asset checksums are verified in the candidate record.
- Complete: the actual app, source archive and sidecars pass the recorded privacy-marker audit. Keep development signing identities, build logs, local paths and private notes out of distributed assets.
- Test the actual Release candidate, including preview modes, selection, batch actions, tiling, dragging, AppleScript, fresh-launch recency, search and header hover dismissal. Record test gaps rather than inferring them from Debug results.
- Complete: user authorization, fork push, exact candidate tag, draft asset verification and public prerelease publication are recorded below. No upstream push or 0.1.0 asset replacement occurred.
- After publication, separately test a browser-downloaded, quarantined ZIP on another Mac, including Gatekeeper, first launch, permissions, upgrade and settings import.

Do not block publication on showcase media alone. Do not replace missing Release tests with screenshots or earlier Debug results.

The current upstream record is DockDoor 1.41.0 plus changes through `3e08721ec56c6747dba04561ab57b03ec254d785`. Upstream main and tags were fetched for this integration; the published stable release and its included tag were verified. The current Release-candidate record below supersedes the earlier build-pending stage notes. Publication was paused at this stage; the completed October 17 publication is recorded below.

## Candidate Handoff

October 16, 2026 candidate: `c863e628d17d8c80985cd77533ff94db03d6444a`. Built on macOS 27.0.1 with Xcode 27.0 as an arm64, ad-hoc-signed Release app. Existing Swift 6 compatibility warnings remain in the current Swift 5 language mode; this is not a warning-free build. All 19 package checks passed: nine asset checksums, ZIP integrity, 219 extracted bundle entries' contents/modes/links, deep/strict nested signatures and ad-hoc identity, exact committed source archive, clean packaging-overlay application, committed preset/license/install-guide correspondence, source/upstream version metadata and disabled upstream updater feed. The privacy-marker scan covered 462 app/source/sidecar files and found no configured private-home, development-identity, credential/private-key or temporary-build-path markers. Intentional public attribution remains. This is not a comprehensive secret-scanner certification. The application includes no development/debug/signing payloads; the temporary worksheet and local outputs are absent from its source archive. Release packaging disables coverage instrumentation and removes debug maps before signing. The preset has 246 reviewed preferences and 15 generic-ID shortcut rows, with debug logging Off.

Local package: `fork/dist/DockFork-c863e62-uTuBcN/DockFork-0.2.0-c863e62-arm64.zip`. ZIP SHA-256: `7c9456e9a7875f8fce593bf0877087cc0d83bd8b1460d2071a3d986d7ebe2263`. Preset SHA-256: `96e30b9d8dca6beb4d2c3fd82370c650e5a7b4dcaf6ef5e9bc76a6fd3e7b1555`. Publish only the ten allowlisted assets, never the development app, build logs, audit notes or the whole output directory. Earlier rejected candidates are not eligible for distribution. The Release app was not installed or launched, the preset was not imported, and the signed development app and live settings were left unchanged. Manual Release verification, downloaded/quarantined installation, minimum-OS validation and publication approval remain pending. No tag, push, draft, upload or publication was performed.

## Integration Validation History

These are historical implementation-stage checks, not additional Release test claims.

Integration follow-up 1: Confirm gesture restoration and serialize asynchronous actions. Reuse confirmed unhide/unminimize and fullscreen-exit workers; foreground only successful restores and retain partial success. No fixed fullscreen delay or optimistic restore-cache writes. Production-source adapter tests and signed Debug build/relaunch passed. AppleScript availability and locked-session live testing are tracked separately; no manual gesture verification or Release build is claimed.

Integration follow-up 2: Restrict linked resizing to live same-Desktop neighbors. Use PID/window identities, generation checks, real perpendicular edge overlap, live membership/state validation, nonactivating confirmed neighbor writes and explicit detachment before programmatic placement or Space movement. Retain coalesced background processing without main-thread AX waits. Focused geometry/registry checks cover unrelated Spaces, stale targets, refused writes and identity reuse; full-app and locked-session results are recorded separately.

Integration follow-up 3: Bound snap-record lifetime and avoid retaining preview images. Records now keep identity, owner PID, AX handle, frames and membership without screenshot-bearing WindowInfo values. A bounded window-ID index routes physical-owner notifications correctly. Existing cache-removal/metadata/termination paths prune records without holding cache locks during registry operations; all Space moves detach through the shared low-level operation. Production-registry weak-image, metadata invalidation and cleanup checks passed, as did the signed Debug build/relaunch. The locked session exposes no live windows; native interaction tests remain pending.

Integration follow-up 4: Optional linked resizing for confirmed DockFork tiling batches. Link tiled windows when resizing defaults Off under Keybinds > Tiling and is independent of multi-selection and Window Gestures. Confirmed Auto Tile, selected Half/Quarter, drag-to-tile and scripting placements register separate overflow batches; preserve valid original restore sizes, detach moves/invalid members and keep native neighbor resizing nonactivating. A connected-edge solver handles three-window T junctions without joining disconnected collinear windows. Registration and extra frame reads are gated by the option; existing AX notifications are reused with no new event tap or polling. Mixed-origin groups remain separate, and disabling one option removes only its own records. Source-adapter and automated geometry checks pass; locked-session native testing remains pending.

Tiling foreground follow-up: honor foregrounding for AX-accepted but size-constrained placements, while preserving unconfirmed-layout errors and excluding those windows from linked resizing. App minimum sizes are still respected.

Linked-resize timing follow-up: preserve pointer intent from AX notification receipt so releasing the mouse while work is queued does not discard the update. Automated regression passes; native manual validation remains pending.

Linked-resize follow-up: skip restore-frame bookkeeping for 1×1 no-resize tiling and already-superseded requests; preserve the first resize notification when a snap record is replaced while earlier work is queued. Production-source adapter coverage now includes full tiling/registration, geometry stress, cancellation and lifecycle cleanup. Native locked-session validation remains pending.

## Publication Record

Published October 17, 2026: [DockFork 0.2.0 prerelease](https://github.com/hexcrete/DockFork/releases/tag/v0.2.0), tag `v0.2.0`, resolves to the exact audited candidate source `c863e628d17d8c80985cd77533ff94db03d6444a`. A fresh fetch confirmed upstream main remained `3e08721ec56c6747dba04561ab57b03ec254d785`; no new merge or rebuild was needed. Exactly ten allowlisted assets were uploaded to a draft, downloaded with authentication and verified byte-for-byte against the local package, then published after the user's authorization. The remote annotated tag target, public non-draft/prerelease state and unchanged public release notes were verified. All ten public asset links returned HTTP 200; an anonymous app-ZIP download matched SHA-256 `7c9456e9a7875f8fce593bf0877087cc0d83bd8b1460d2071a3d986d7ebe2263`. The 246-preference/15-shortcut optional preset, source archive, overlay, license, installation guide and metadata remain those of the audited candidate. No development app, build log, signing certificate, private note or unlisted asset was uploaded. The fork's Actions are disabled; no inherited changelog workflow was triggered or changed. The original 0.1.0 release and upstream repository remain untouched. No application rebuild, installation, launch, preference import or media capture accompanied publication. The user's upgrade-permission observation is documented, not treated as exhaustive 0.2.0 feature testing. A command-line download does not test browser quarantine or Gatekeeper approval; that installation check, older-OS compatibility and screenshots remain pending.

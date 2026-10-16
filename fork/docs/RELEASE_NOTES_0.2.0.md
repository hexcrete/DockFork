# DockFork 0.2.0 Prerelease Draft

Status: preparation only, October 15, 2026. Includes upstream 1.41.0 integration `229d38a`, with a follow-up adapting gesture minimization to the existing confirmed-state pipeline. No 0.2.0 Release candidate, tag, upload or publication is recorded.

**Release packaging is on hold until the updated showcase configuration is supplied and reviewed, and the user authorizes the build.** The existing preset is unchanged. Screenshots and recordings are deferred and are not a release gate.

## Release Notes

DockFork is a GPL-3.0 fork of [DockDoor](https://github.com/ejbills/DockDoor). This second testing release adds ordered multi-window selection, group actions and tiling to the existing preview, shortcut and Space-management features.

### New Since 0.1.0

- Select multiple real windows in Dock, Window Switcher and Cmd+Tab previews. Checks follow selection order and survive filtering. Use circular title/icon controls, an assigned Toggle Window Selection shortcut or mouse action, or Command-click in eligible persistent switchers. Select All affects the currently displayed, filtered windows.
- The selection summary is enabled by default and shows selected and outside-view counts, with Select All, Clear Selection and Tile Windows in all preview modes. Window Switcher also has one right-aligned app icon per checked window, including repeated apps; +N counts windows omitted from the icon strip. Narrow summaries hide icons, shorten the count, change Tile Windows and then the other buttons to glyphs, and finally scroll horizontally. The count and every action remain available. A separate option keeps Window Switcher open when windows are selected; normal held-modifier behavior remains the default.
- Apply preview actions and confirmed Space moves to checked groups. Mixed groups minimize or hide when any applicable target is restored or visible, and restore only when all applicable targets are minimized or hidden. Group fullscreen actions exit existing fullscreen members; fullscreen entry remains single-window.
- Dock/Cmd+Tab App Header Close All and Minimize All remain app-wide regardless of selection; their controls switch to glyphs and then horizontal scrolling when space is limited. Header names follow the configured overflow style and fall back to icon-only when too narrow for readable text. Use selection-aware traffic lights or Tile Windows to act on checked windows only.
- Drag checked windows together across Desktops and displays, with an ordered app-icon ghost and confirmed placement. Optional drop-to-tile puts the target window/group first, followed by the dragged selection.
- Auto Tile Selected Windows and directional Half/Quarter actions arrange groups in selection order. Configure row/column limits up to 6, with default limits of 2 rows and 3 columns. Overflow is arranged in repeated batches; a single-window Auto Tile fills the display. Applications can enforce minimum sizes.
- Existing AppleScript window actions accept an ordered list of window IDs where applicable. Batch scripts do not require UI selection; existing single-window syntax remains supported. Tile Windows exposes ordered tiling directly.

Multi-window selection, selection-driven keep-open behavior and drop-to-tile default Off. Show selection summary defaults On, but appears only with selection enabled and at least one checked window. Enable selection under **Keybinds > Window Selection & Tiling**. Configure drag-to-tile under **Mouse Actions**. Existing saved settings and the optional showcase preset are not changed automatically.

### Included From Upstream 1.41.0

Optional two-finger window gestures, swipe-switcher sensitivity, custom-dock screen reservations with AppleScript access, stricter Dock-hover validation and updated translations. Gesture settings now have their own Gestures tab; shortcuts, Spaces and selection/tiling are under Keybinds. These capabilities come from DockDoor; fork selection, confirmed placement and session behavior are preserved.

Integration follow-up 1: Confirm gesture restoration and serialize asynchronous actions. Reuse confirmed unhide/unminimize and fullscreen-exit workers; foreground only successful restores and retain partial success. No fixed fullscreen delay or optimistic restore-cache writes. Production-source adapter tests and signed Debug build/relaunch passed. AppleScript availability and locked-session live testing are tracked separately; no manual gesture verification or Release build is claimed.

Integration follow-up 2: Restrict linked resizing to live same-Desktop neighbors. Use PID/window identities, generation checks, real perpendicular edge overlap, live membership/state validation, nonactivating confirmed neighbor writes and explicit detachment before programmatic placement or Space movement. Retain coalesced background processing without main-thread AX waits. Focused geometry/registry checks cover unrelated Spaces, stale targets, refused writes and identity reuse; full-app and locked-session results are recorded separately.

Integration follow-up 3: Bound snap-record lifetime and avoid retaining preview images. Records now keep identity, owner PID, AX handle, frames and membership without screenshot-bearing WindowInfo values. A bounded window-ID index routes physical-owner notifications correctly. Existing cache-removal/metadata/termination paths prune records without holding cache locks during registry operations; all Space moves detach through the shared low-level operation. Production-registry weak-image, metadata invalidation and cleanup checks passed, as did the signed Debug build/relaunch. The locked session exposes no live windows; native interaction tests remain pending.

### Fixes and UI Polish

- Make tiling and foregrounding more reliable: confirm actual placement, finish resizes constrained by the old window position, and prevent rapid focus from unexpectedly expanding a tiled window. Applications' minimum-size restrictions are reported rather than treated as successful placement.
- Adapt preview toolbars to narrow widths: shorten/omit title text, progressively overflow rightmost traffic-light actions and consolidate Space/state controls into native More menus, then reuse the selection-control location while preserving app icons and selected-state outlines. Preview and menu-bar action menus share Space/state information, with Move to Space before Arrange. Shared selection controls expose native selected-state accessibility metadata.
- Keep Shadowed app headers and their mouse-safe zone below the menu bar when preview panels reach the top of the screen.
- Keep pending cache validation separate for each app so large multi-app close groups do not cancel one another's stale-window cleanup.
- Correct Compact Mode drag-target shapes and highlight opacity.
- Extend the configurable traffic-light transition duration to 0.5 seconds while preserving Reduce Motion behavior.
- Acknowledge the one-time Cmd+Tab focus hint after actual preview focus. Hide app-header window actions when an app has no real windows.
- Improve contrast for embedded switcher titles with shared appearance-aware shadows. Add a native search clear button that works after repeated panel reuse.
- Limit Dock cycling to the active, visible app with multiple real windows. Inactive, single-window and windowless clicks retain native activation/reopening, while preview retention applies only to actual cycles.
- Avoid false five-second AX backoff during app startup and preserve explicitly identified window focus timestamps through discovery.
- Include Shadowed headers and selection summaries in hover and outside-click interaction bounds, without changing their appearance or adding timers. Header/summary button clicks no longer fall into the fixed transparent-margin exclusion; user verification of this latest correction passed, with final no-change publication guards checked in isolation and by a signed Debug build.

These are highlights, not the complete list. See the [changes guide](CHANGES_AND_SHOWCASE.md) and [commit ledger](COMMIT_LEDGER.md). Screenshots and recordings will follow during testing; none are marked captured or approved.

### Installation and Limitations

- Planned distribution: Apple Silicon, ad-hoc signed, not notarized, with manual updates. Follow the [installation guide](../packaging/INSTALL.md); do not disable Gatekeeper.
- Quit other DockDoor/DockFork instances before launching. Export settings before upgrading or importing the optional preset. Import replaces settings. A rebuilt ad-hoc release can require permission approval again.
- Partial batch failures are reported; successful members are not rolled back. Fullscreen and multi-Desktop sources have operation-specific restrictions. Overflow batches intentionally overlap earlier batches.
- Smaller displays or apps with large minimum sizes can prevent a requested grid from fitting. Row/column limits are upper bounds, not a guarantee that every app supports that layout.
- Spaces Bar, pinned floating windows and the slide-out switcher are not included. Experimental full-size-preview container fading remains Off by default with known hover limitations.
- Development testing covers signed Debug builds, focused native/model checks and user-reported verification. The 0.2.0 Release build, downloaded/quarantined installation and older-macOS compatibility are not yet verified. Earlier 0.1.0 testing does not certify this release.
- The latest tiling/focus regression sweep used one display on macOS 27. Additional displays and exhaustive accessibility coverage remain unverified for that follow-up; Window Switcher VoiceOver navigation out of search was not completed.

Report problems through this fork's Issues page. Review diagnostic logs for private information before attaching them.

## Preparation Checks

October 15 preparation now includes upstream integration `229d38a` and its gesture-minimization adapter. Earlier tiling/activation and formatting checks retain their stated scope; they do not establish manual verification of the new upstream gestures.

| Area | Current evidence and remaining work |
|---|---|
| Source and documentation | Git confirms exact-once coverage of 292 commits through 229d38a and all recorded changed-file counts. Incoming changed-source formatting, unique search IDs, split-tab routing, AppleScript command codes, project registrations and packaging overlay checks pass. This follow-up commit remains outside the explicit ledger coverage boundary. |
| Version metadata | All 19 validator cases pass. Fetched upstream main is 3e08721, and included published stable release 1.41.0 resolves to 3d6a3cba. The record keeps DockFork 0.2.0 separate and validates committed ancestry. |
| Debug validation | The final signed Debug build/relaunch, exact running path, deep/strict signature, embedded upstream metadata, reviewed source overlay and installed/built binaries were verified. The first build caught an integration-only minimize-helper mismatch, corrected by reusing confirmed minimization. All 84 isolated gesture/swipe/session/frame/reservation tests, 19 version cases and retained placement/focus checks pass. No full Xcode suite, new manual gesture/display validation, performance run or Release ZIP is claimed. |
| Latest tiling/focus sweep | 27 scripted tiling calls with three expected minimum-size refusals, four rapid-focus pairs and four cross-Space focus checks passed without unexpected failures. Frames, Spaces, accessibility flags and original focus were restored. The later partial-write refresh correction has focused regression and signed Debug validation, not another full live sweep. |
| Showcase configuration | Await the updated export. Keep the current reviewed 237-preference preset unchanged until the replacement is sanitized and reviewed. Do not import it into live preferences automatically. |
| Release candidate and privacy | Not built. Audit the actual app, source archive and sidecars after the final preset and preparation commits. Existing 0.1.0 audits do not certify 0.2.0 assets. |
| Installation and media | Release upgrade/import and browser-quarantine/Gatekeeper testing remain pending. Screenshots and recordings are deliberately deferred. |

The ledger coverage boundary is explicit in [COMMIT_LEDGER.md](COMMIT_LEDGER.md); an uncommitted preparation or future commit is not silently included. No preferences were reset and no showcase media or Release validation is inferred from these checks.

## Publication Gate

- Receive the updated configuration, remove private/system state, review nested shortcut records and retain only intended showcase preferences. Review the sanitized difference and keep a backup before any later import test.
- Review and commit the approved preset and preparation changes. Keep `fork/version.json` at the agreed 0.2.0 prerelease version unless a new decision is made.
- Obtain authorization to build, then use `./fork/package.sh` from the exact committed candidate. Do not package the working tree or distribute the development app.
- Record the exact source commit and final package directory. Verify version/base metadata, app identity, ZIP integrity, source/patch correspondence, nested signatures and every allowlisted asset checksum.
- Run a fresh privacy audit of the actual app, source archive and sidecar assets. Keep development signing identities, build logs, local paths and private notes out of distributed assets.
- Test the actual Release candidate, including preview modes, selection, batch actions, tiling, dragging, AppleScript, fresh-launch recency, search and header hover dismissal. Record test gaps rather than inferring them from Debug results.
- Obtain explicit push/upload/publication authorization for hexcrete/DockFork. Tag the reviewed candidate commit, create a draft prerelease, verify uploaded assets, then publish. Do not push the complete fork upstream or retag/replace the tested 0.1.0 assets.
- After publication, separately test a browser-downloaded, quarantined ZIP on another Mac, including Gatekeeper, first launch, permissions, upgrade and settings import.

Do not block publication on showcase media alone. Do not replace missing Release tests with screenshots or earlier Debug results.

The current upstream record is DockDoor 1.41.0 plus changes through `3e08721ec56c6747dba04561ab57b03ec254d785`. Upstream main and tags were fetched for this integration; the published stable release and its included tag were verified. No fork Release build or publication is included.

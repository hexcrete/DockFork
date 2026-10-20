# DockFork 0.3.0 Prerelease

Status: Release-candidate preparation, not published. The user authorized the upstream merge, sanitized preset refresh and committed-source Release build. Candidate testing and explicit publication approval are still required. Screenshots and recordings are deferred, not a release gate.

## Release Notes

DockFork is a GPL-3.0 fork of [DockDoor](https://github.com/ejbills/DockDoor). This prerelease adds optional action feedback and range selection, improves action responsiveness and coordination, and fixes native-tab and Wine/CrossOver preview handling.

### Action feedback

- Optional popups show window/Space action progress and results, including group counters and failures.
- Choose cursor-following feedback, preview-centered feedback, or placement based on the trigger or preview focus.
- A native spinner appears when an operation remains pending for 0.7 seconds. Verified success uses a green check only after a spinner was shown; fast actions retain their action symbol.
- Feedback moves to the cursor when its affected previews disappear. Selection changes, ordinary activation and AppleScript remain silent.
- An optional Mouse Follows Focus popup highlights the cursor's new location.
- Committed window gestures share real action results without duplicating their existing HUD. Gesture feedback keeps its independent enablement.

### Selection and input

- Shift-click another checkbox to add a range without clearing existing selection.
- Drag from a checkbox to select or deselect a range. Reversing restores entries outside the range to their earlier state.
- Hold the Toggle Window Selection shortcut and use arrows to extend a range, including while search is focused.
- Holding an action shortcut executes it once per physical press. Tab/arrow navigation and search typing retain key repeat.
- Dragging from preview controls no longer starts an invisible window drag. Regular and Compact Mode body dragging remain available.

### Reliability and responsiveness

- Closing a collapsed native-tab group closes the represented window, including differently named Finder tabs.
- Native-tab groups remain grouped through minimization and visibility changes.
- Potentially slow hide/fullscreen, Close, move/resize, tiling and drag-placement Accessibility work runs off the main thread. This targets responsive input and feedback, not a guaranteed speedup of macOS window operations.
- Shared action ownership protects queued batch targets from interruption while permitting unrelated-window actions and rapid replacement of single-window requests.
- Cmd+Tab supports app-level Minimize/Restore before a preview is focused; focused previews retain their normal action route.
- Improved native external-drag spring-loading and windowless-to-real-preview sizing/header transitions.

### Explicit Quit actions

- Quit App always requests normal Quit. Holding Option for a switcher shortcut no longer changes it to Force Quit.
- Force Quit App is an explicit menu/shortcut action, also available through AppleScript. It can discard unsaved changes.
- The separately configured Dock Quick Quit gesture retains its documented modifier behavior.

### Wine and CrossOver

- Detect known Wine/CrossOver screen-sized game windows exposed at Wine's fullscreen window levels, including the reported Fallout 76 case.
- Keep supported actions available while hidden, skip unsupported targets in groups, and report unsupported direct attempts as failures.
- Supported actions include Quit/Force Quit, Hide/Unhide, Space moves, and best-effort geometry/tiling. Some Wine windows accept repositioning without resizing.
- No private CrossOver icon-file access or game-specific name rule is added. Compatibility with every Wine distribution or exclusive-fullscreen mode is not guaranteed.

### Settings and packaging

- Full-size windowless previews are labeled Show full size placeholders, separately for Dock and Cmd+Tab.
- Range-selection methods are explained below Enable multi-window selection.
- The fork build script can clean old recognized development outputs while preserving Release packages.
- Upstream DockDoor 1.41.0 remains the base, with upstream history incorporated through `77e4771d38cf69dc24f2f76c74a73e61fab54571`. The latest merge adds website compatibility content only, not app features.

### Defaults and showcase preset

Action feedback and Mouse Follows Focus feedback default Off. The refreshed optional preset enables both, with placement Based on trigger type. Its existing Mouse Follows Focus mode only jumps between displays. Multi-selection and other previously optional features keep their application defaults; range selection is available when selection is enabled.

The October 20 preset contains 249 reviewed preferences and 15 generic-ID shortcut rows. Four system/private-state entries were removed; debug logging is Off. It is an optional sidecar, not an app default or automatic import. **Export a backup before importing: import replaces existing settings.**

### Installation and limitations

- Apple Silicon, ad-hoc signed and not notarized. Updates remain manual.
- Quit other DockDoor/DockFork instances before launching. Replacing an ad-hoc build can require removing and re-adding its Accessibility or Screen Recording permission entries, then relaunching.
- Follow macOS Privacy & Security approval procedures. Do not disable Gatekeeper.
- Partial failures retain successful changes rather than rolling back the batch.
- Short feedback confirmations may expire during a Space transition; the unreliable timing workaround was removed.
- Older macOS versions, physical multi-display edge cases, every Wine build, and browser-quarantine/Gatekeeper installation remain unverified for this candidate.
- Spaces Bar, pinned floating windows and the slide-out switcher are not included. Experimental full-size-preview container fading remains Off by default with known hover limitations.

These are highlights, not the complete list. See the [changes guide](https://github.com/hexcrete/DockFork/blob/better_dd_merged/fork/docs/CHANGES_AND_SHOWCASE.md). Screenshots and recordings will follow during testing.

Report problems through [the fork's Issues page](https://github.com/hexcrete/DockFork/issues). Review diagnostic logs for private information before attaching them.

## Preparation and Publication Gate

- Upstream website-only merge `d50d6882` is committed. Stable 1.41.0 and its exact included release tag were rechecked against GitHub and fetched Git history.
- The supplied export is sanitized without modifying its source file or importing it into live preferences. The three new feedback preferences are enabled/configured as supplied. Shortcut actions, keys and order are preserved.
- All sixteen regression suites, 19 version-metadata cases and production build-cleanup checks pass. The unchanged native Compact Mode title hit test failed once and passed on retry; no assertion was weakened. Diff and packaging-script syntax checks pass. Existing feature-specific user reports do not replace Release-candidate testing.
- Build from committed sources with `./fork/package.sh --clean-old-builds`. Use the resulting ad-hoc Release package, not the certificate-signed development app.
- Audit the actual app ZIP, exact source archive, optional preset, packaging patch, installation guide, license, source commit, build metadata, patch checksum and checksum list. Exclude build logs, development apps, signing material and all unlisted files.
- Test the exact candidate before tagging/uploading. Preserve the tested assets rather than rebuilding after approval.
- No tag, push, draft, upload or publication is authorized by this preparation request. Publish only after separate explicit approval.

## Candidate Handoff

Pending build and artifact audit. The final candidate source, paths, checksums, audit results and remaining manual tests will be recorded here after verification. No Release installation, preference import, browser-download test or media capture has been performed during preparation.

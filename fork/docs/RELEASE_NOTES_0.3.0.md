# DockFork 0.3.0 Prerelease

Status: Publication explicitly authorized October 20, 2026; upload and publication verification pending. Exact candidate source: `6d3eb4707c7db4446c78786e8df6ceec279be7b2`. Publish the existing audited assets without rebuilding. Manual candidate installation/import and browser-quarantine testing remain unreported; authorization is not evidence that those tests passed. Screenshots and recordings are deferred, not a release gate.

Use [the approved public release body](RELEASE_BODY_0.3.0.md) for the GitHub release description. This file retains detailed change, audit and handoff records; do not paste it wholesale into the release description.

## Detailed Change Record

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

Built from committed source `6d3eb4707c7db4446c78786e8df6ceec279be7b2` on macOS 27.0.1 with Xcode 27.0, using the existing Release/ad-hoc workflow. The package is arm64, not notarized, and retains the established DockFork identity. Swift 6 compatibility warnings remain in Swift 5 mode; this is not a warning-free build.

- Package folder: `fork/dist/DockFork-6d3eb47-uH0xrM`.
- App ZIP: `DockFork-0.3.0-6d3eb47-arm64.zip`.
- ZIP SHA-256: `c4d3a78a0a12a5de6854f9afd574ceb1032eed6ab0e6a3ad1b8d5583fb1fbe11`.
- Optional preset SHA-256: `df2d59b96290764f6ae19cfc38af134aeca56243307f70e041081e900ed1e1e2`.
- All 257 artifact assertions pass: nine payload checksums, ten-asset inventory, exact source/sidecar correspondence, metadata and disabled upstream updater, arm64/ad-hoc signatures, absence of app development/signing/coverage payloads, ZIP integrity and all 219 extracted bundle entries' content/modes/links, clean packaging-overlay application, and packaged-preset checks.
- The privacy-marker scan covered 477 unpacked app/source/sidecar files, including binary and UTF-16 private-path/identity checks. No configured private-home, development-certificate identity, credential, private-key or temporary-build-path marker was found. Intentional public upstream attribution is retained. This is not comprehensive secret/malware certification.
- The Release app was not installed or launched; the preset was not imported. The running development app's executable checksum is unchanged. Cleanup removed the previous recognized local build output while preserving the installed app and this Release package.
- Only the ten allowlisted files in Preparation and Publication Gate may be uploaded later. Exclude `build.log`, the unpacked app directory, temporary audit scripts/results and every unlisted file. No tag, push, upload, draft or publication was performed.

### Manual Handoff Tests

1. Test this exact ZIP as an upgrade, including permissions and settings import after exporting a backup. Do not infer those results from the Debug build or privacy scan.
2. Check Dock, Window Switcher and Cmd+Tab in regular/Compact layouts: feedback, range selection with search, action-key repeat suppression, body/control drag separation and windowless transitions.
3. Test collapsed differently named Finder tabs through Close and Minimize/Restore, mixed selection actions and Cmd+Tab app-level Minimize. Use disposable targets for destructive actions.
4. Check Wine/CrossOver controls while visible/hidden, unsupported single failure, mixed-group exclusions and supported best-effort placement if applicable.
5. Browser-downloaded/quarantined installation on another Mac remains a separate Gatekeeper test after publication or an explicitly approved transfer workflow. Older OSes, exhaustive displays/apps/faults and screenshots remain unverified.

Keep the exact audited assets after approval. This handoff documentation is a later documentation-only commit; the app and corresponding source archive are not rebuilt to include their own future audit record. Publication requires separate explicit approval.

## Final Review

October 20 final review checked the public body against the changes since published 0.2.0 source `c863e62`. The body excludes older fork features, the website-only upstream merge, internal audit counts and local build paths. The public body and this detailed record are separate files.

All sixteen regression suites and both packaging suites pass again. The first sandboxed run could not launch Swift's macro helper; the unrestricted rerun passes without source changes. The artifact audit passes all 257 assertions again. Application, project, packaging, version and preset inputs remain identical to candidate source `6d3eb470`. No Release rebuild, launch, settings import or publication was performed.

No tracked temporary logs, coverage files, rejected patches, scratch worksheets or generated build outputs were found. Removed feedback consolidation/Space-transition experiments have no runtime hooks or preferences. Added declaration-reference checks found no unreferenced named functions or types; this is not a whole-program dead-code proof. Regression fixtures, historical release records and the ignored installed development app/current Release package are intentional, not cleanup candidates.

One non-blocking source leftover remains: the synchronous `WindowAction.perform` signature still accepts the unused `hiddenStateBeforeAction` argument after Hide moved to the confirmed executor. Its two callers also use that local snapshot for other presentation logic, so those locals must not be removed wholesale. Defer the unused-argument cleanup rather than change the audited candidate for a no-behavior refactor. Manual candidate upgrade/import tests, browser quarantine and broader display/OS coverage remain pending.

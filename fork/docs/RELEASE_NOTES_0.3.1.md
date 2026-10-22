# DockFork 0.3.1 Prerelease

Status: preparation in progress. No tag, upload or publication performed. The candidate must be tested and approved before publication. Screenshots and recordings remain deferred.

## Changes Since 0.3.0

- Fix checkbox-drag and held-shortcut range selection ending during an unchanged background window refresh. Actual displayed membership/order changes still end the range normally.
- Add Gestures > Options > Disable title bar gestures over scrollable areas and tabs, default Off. When enabled, skip scrolling/content ancestors and recognized tab groups/tab-button subroles, including tab bars without scrolling metadata. Other controls keep the standard gesture rules.
- Remove an unused internal window-action argument without changing behavior.

The new filter uses the existing bounded Accessibility hit test. It adds no AX requests, observer, timer or polling. Window-hit cache reuse is bypassed at gesture starts while enabled so an earlier background hit cannot authorize a nearby tab/control hit. It is not exact draggable-region detection; custom apps can expose incomplete Accessibility metadata. Dock/menu-bar gestures and the separate legacy title-bar scroll feature are unchanged.

The committed preference key and default are retained from the earlier broad-filter implementation. The broader and narrower implementations are one evolved feature, not separate release features.

## Upstream and Settings

Upstream main was fetched October 22 and remains `77e4771d38cf69dc24f2f76c74a73e61fab54571`; no merge was needed. The newest published stable release is still 1.41.0 at `3d6a3cbaa9bbee17959122da7f0a349ca43056d0`, contained in that history.

The optional showcase preset retains the reviewed October 20 settings, 249 preferences and 15 generic-ID shortcut rows. Only its export version label changes to 0.3.1. The new gesture preference is not added or enabled in the preset. No live import or preference reset is performed.

## Validation and Publication Gate

The user verified the selection-refresh correction and the final narrower title-bar filter in the development app. Seventeen regression suites, formatting/diff checks and signed development build/source/running-path checks passed for those changes. These reports do not establish Release-candidate installation or interaction coverage.

Fresh validation passed all seventeen regression suites, 19 version-metadata cases, build-cleanup checks, focused SwiftFormat checks and diff/script syntax checks. The unchanged native Compact Mode title hit test failed once and passed on retry; no assertion was weakened. Candidate-artifact validation remains pending. Build the candidate from committed sources with `./fork/package.sh --clean-old-builds`. Record its exact source, asset inventory, checksums, signatures and privacy checks after building. Keep the tested assets unchanged after approval.

Before publication, test the exact candidate: selection sweeps and held-shortcut ranges across background refreshes in regular/Compact Window Switcher; enabled/disabled title-bar filtering over empty title bars, ordinary controls, scrolling contents and tab bars. Confirm Dock/menu-bar gestures remain unchanged. Export a settings backup before any optional import.

Ad-hoc signed, Apple Silicon and not notarized. Replacing an ad-hoc build can require removing and re-adding affected system permissions. Updates remain manual. Browser-quarantine/Gatekeeper testing, older macOS releases, exhaustive custom-app/display coverage and media remain unverified. Do not infer them from packaging checks.

Use [the concise release body](RELEASE_BODY_0.3.1.md) for a future GitHub description, not this preparation record. Publication requires approval after candidate testing. Published 0.3.0 assets remain untouched.

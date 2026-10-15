# Preparing Upstream Contributions

Checked October 8, 2026 against the live [upstream contribution rules](https://github.com/ejbills/DockDoor/blob/main/CONTRIBUTING.md) and [PR template](https://github.com/ejbills/DockDoor/blob/main/.github/pull_request_template.md). Both matched the current checkout. Re-read them before each submission: this checklist is not a substitute for the maintainer's rules.

Publishing DockFork and submitting changes to DockDoor are separate activities. Preserve the fork's history and documented choices; do not offer the entire branch as one upstream PR or claim that it already complies with all upstream requirements.

## Fork-Only Exclusions

**Required before submission: review the complete PR diff against its upstream base, not just the selected commits or their titles.** Prepare a separate focused branch; keep the working fork and its history intact.

- Exclude the entire `fork/` directory: packaging scripts/overlays, presets, commit ledger, roadmap, showcase media, and publication documentation.
- This includes `fork/version.json`, the version validator/tests, build metadata, and the Support version label supplied by the packaging overlay; do not add these to upstream's project or version UI.
- Exclude fork-specific changes to root `AGENTS.md` and `README.md`. Keep upstream's versions by default; do not carry over fork branding or the fork build workflow.
- Exclude local identity/signing configuration, personal editor/agent files, private notes, temporary fixtures, and generated build outputs.
- Skip wholly fork-only commits. For mixed commits, extract only the required feature/fix changes and their necessary dependencies; do not cherry-pick the whole commit or silently discard a prerequisite fix.
- Allow documentation and project registrations that are genuinely required by the agreed upstream issue. This is not a blanket ban on editing those files; each included change must serve that issue rather than fork publication or local development.
- Audit the final changed-file list and every remaining hunk. Confirm there is no fork-only or unrelated content, then build and test that exact extracted branch under upstream's rules.

File exclusions alone do not make a feature upstream-ready. Preference/default compatibility, dependency adaptation, disabled-feature cost, maintainer scope approval, and testing still apply.

## Scope and Compatibility Gates

- Discuss one proposed feature with the maintainer in an issue before preparing its contribution. Our existing implementation is a prototype for that discussion, not evidence of prior scope approval. Bug reports use the issue template too.
- Prepare a focused branch against current upstream for each agreed issue or feature. Keep bug fixes, refactors, and features separate; include only the agreed scope and its reviewed dependencies.
- Retain every existing Defaults key and existing default. Introduce new keys when necessary; do not add migration code. Replacement of singular alternate-shortcut preferences and other preference-model changes need adaptation before submission. The main shortcut and traffic-light scale retain upstream defaults.
- New settings default to the existing behavior. Verify that disabled features do not construct their own observers, event taps, timers, or singletons. Do not claim this property without reviewing the selected patch.
- Reuse the existing event tap, manipulation observers, WindowUtil, cache, screen/coordinate helpers, and private-API bridges. Avoid duplicate infrastructure, unnecessary polling/global mouse monitors, and reading other apps' private files or databases.
- Place settings in the appropriate views and index every new preference in settings search. Audit each proposed patch against the current AGENTS.md conventions.

## Validation and Diff Gates

- Build and run from Xcode 27 or later on macOS 27 or later for upstream validation. Our approved CLI development/release workflow remains a fork workflow; it does not substitute for this upstream requirement.
- The human contributor tests the feature on their own Mac, including affected Dock orientations, displays, Spaces, fullscreen states, and disabled behavior. Record unavailable or untested cases honestly. Historical fork testing and CI alone do not certify a newly extracted PR.
- For visual changes, supply before/after screenshots or video in both light and dark mode. Only make performance-improvement claims with before/after measurements.
- Run the required formatter before pushing the contribution branch: `swift run -c release --package-path BuildTools swiftformat .`. Keep formatting changes limited to the proposed scope.
- Exclude local signing/team identity, personal editor/agent files, temporary fixtures, prints, and leftover debug instrumentation. Distinguish intentional diagnostic functionality from debugging artifacts and agree any diagnostics feature's scope first.
- Preserve localization conventions: only strings added by the PR belong in its Localizable.xcstrings diff; discard unrelated Xcode rewrites and leave translations to Crowdin.

## Human Submission Gates

- Start from the current PR template and retain every section. Use a Conventional Commit title, an issue-closing keyword for each linked issue, and allow maintainer edits.
- The human writes the description and review replies in their own words, covering every behavior change, rationale, and actual testing. The agent may provide technical notes, not prose to paste as the submission.
- Disclose Codex/ChatGPT assistance accurately, including implementation, debugging, and review where applicable. Do not imply assistance was merely autocomplete when it was more extensive.
- The human must understand and be able to explain every submitted line. They alone confirm and tick the review/testing checkboxes.
- No PR creation, edits, comments, or other posted PR text without human review and approval. Use a human-owned account, not an autonomous bot submission.
- Keep contributions current and respond to review; the maintainer closes stale conflicted or unanswered PRs.

## Submission Order

Start with a small reproducible correctness fix the maintainer agrees is useful. Extract its minimal dependencies, adapt preferences and defaults, and validate that exact patch. Discuss larger feature families separately after this first contribution, rather than treating the showcase or exhaustive commit ledger as a proposed merge request.

October 14 preparation candidates, not submitted PRs: the fast AX-not-ready observer backoff correction in `a308aed` can be discussed independently of pending-window recency. That commit contains both changes and fork records, so extract the agreed portion rather than cherry-picking it wholesale. The header hover-bound fix in `4ff8ddd` depends on fork header/selection layout helpers; adapt the app-header issue to upstream's actual layout and omit selection-specific behavior unless explicitly agreed. No new upstream fetch, compatibility certification or submission was performed during 0.2.0 preparation.

October 15 candidate, not a submitted PR: `c15292f` combines shared frame/activation fixes with fork-specific tiling confirmation and publication records. The near-edge synthetic focus click also exists in incorporated upstream; the small off-content mouse-down correction follows [AltTab commit ec30bb1](https://github.com/lwouis/alt-tab-macos/commit/ec30bb13084e68cb3cde32ec415fdba1fd92876e). Discuss the agreed bug first, extract only its required changes, and retain the relevant attribution when omitting fork documentation. Do not include the whole tiling feature or cherry-pick this mixed commit wholesale. Local scripted Debug tests do not replace upstream's Xcode and human-validation gates. This preparation performs no fetch, merge or GitHub submission.

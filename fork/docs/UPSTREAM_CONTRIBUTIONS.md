# Preparing Upstream Contributions

Checked October 8, 2026 against the live [upstream contribution rules](https://github.com/ejbills/DockDoor/blob/main/CONTRIBUTING.md) and [PR template](https://github.com/ejbills/DockDoor/blob/main/.github/pull_request_template.md). Both matched the current checkout. Re-read them before each submission: this checklist is not a substitute for the maintainer's rules.

Publishing DockFork and submitting changes to DockDoor are separate activities. Preserve the fork's history and documented choices; do not offer the entire branch as one upstream PR or claim that it already complies with all upstream requirements.

## Scope and Compatibility Gates

- Discuss one proposed feature with the maintainer in an issue before preparing its contribution. Our existing implementation is a prototype for that discussion, not evidence of prior scope approval. Bug reports use the issue template too.
- Prepare a focused branch against current upstream for each agreed issue or feature. Keep bug fixes, refactors, and features separate; omit `fork/`, the fork-specific README introduction, unrelated settings, and publication material.
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

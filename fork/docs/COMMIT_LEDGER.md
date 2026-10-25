# DockFork Complete Commit Ledger

Audit snapshot: fork `9efa1cc188ff3a1f64556360ca18ef2f1d41a857`; upstream `0bd2e46bb2c56d3bdb121883190728103fab3c99`.

The original frozen inventory covers **192 branch-only commits: 189 non-merge and 3 merge commits**, ending October 8, 2026. The continuation covers **237 later commits through `3b187f4914200555d932add5e50e46c9f4463677`: 429 total, 423 non-merge and 6 merge commits**. Category totals below describe the original snapshot; the continuation is counted separately. Coverage ends at that explicit tip, including preview-input Stage 3 and its verification records after user testing and final review. The user-verified Wine/CrossOver discovery fix and its documentation are included. The user-verified Wine action-support fix and its documentation are committed and included. The selection-range explainer, upstream website commit and merge/version-base update are included. The 0.3.0 preparation commit and exact Release-candidate source are included. The subsequent artifact-audit/handoff documentation commit is included. The public-body separation, final-review and publication-authorization documentation commit is included. The verified 0.3.0 publication-status documentation commit is included. The unused-action-argument cleanup commit is included. The user-verified selection-refresh correction is included. The user-verified broad title-bar exclusion option is included. The user-verified narrower scrolling/tab policy is included. The 0.3.1 preparation/source commit is included. The subsequent candidate-handoff documentation commit is included. The user later clarified that preparation was premature; that candidate is superseded. The October 22 preset refresh, corrected status records and authorized Release-build preparation are included. The refreshed-candidate audit/handoff documentation commit is included. Release publication is now held for Spaces Bar development. Stage 1 shared-model/menu work is user-verified, reviewed and committed within this boundary. Stage 2 layout/settings delivery is included after user testing, final review, eighteen passing regression suites and signed/running development validation. The Stage 2 ledger-record commit is included. Stage 3 navigation/filtering/sorting, optional Space-focused launch and scripting are user-verified, reviewed and included. Stage 4 window drops and Stage 5 two-axis swipes, their user verification and ledger records are included. Stage 6 Desktop-content operations, whole-pill dragging and shared target-aware labels are user-verified, reviewed and included. The Stage 6 ledger-record commit is included. The reviewed gap-animation implementation is included, with synchronized panel/pill widths and native hit geometry. The gap-animation ledger-record commit is included. The user-verified directional-gap correction is included. The directional-gap ledger-record commit is included. The user-verified shared Space-size Stage 1 is included. The user-verified Compact background Stage 2 is included. Source-styled drag-card Stage 3, shared window-drop indicators and single-window miniature overlays are committed and included; final automated suites were skipped at user request.

The latest records include the tiling/activation reliability fix, formatting-only cleanup and release-preparation records. The latest upstream integration and its ten incoming commits are included. The notification-timing, constrained-foregrounding and released-drag fixes are included through `86c3306`, with their exact hashes and changed-file counts. Any commit containing this ledger update must receive its exact hash, purpose and changed-file count in the next update; a commit cannot contain its own final hash. The overflow-policy and Fill-action settings changes are included through `3b4d311`. The discarded header selection-scoping experiment was never committed.

The inventory uses each commit's patch, changed-file list, added declarations/settings, and the current implementation for user-facing claims. It is a historical/documentation audit, not a fresh safety or performance certification of every intermediate revision. A Git patch-equivalence check found no exact equivalent among the 189 non-merge commits against the chosen upstream snapshot; that does not mean every broad feature concept is unique to this fork.

Read [Changes and Showcase](CHANGES_AND_SHOWCASE.md) for final behavior and [Capture Checklist](SHOWCASE_CHECKLIST.md) for visual candidates. Commit links target the public `hexcrete/DockFork` repository. Locally, inspect any entry with `git show <commit>`.

The October 8 update adds four reviewed follow-ups: migration removal, non-creating badge cleanup, context-aware live-capture shutdown, and an editable timed keep-alive field. These are fixes, not four additional top-level features.

## Roles

- **Feature**: feature entry point or option; describe its final implementation, not necessarily this historical revision.
- **Fix**: corrected existing behavior; not a new top-level capability.
- **Support**: refactor/performance infrastructure supporting a category; no numerical speedup implied.
- **Evolved**: an earlier design refined or replaced later; its note points to the current implementation.
- **UI / Maintenance / Integration**: presentation, build housekeeping, or upstream merge.

No recorded commit is described as a full revert without evidence. An Evolved row is not an additional independent release feature.

## Category Index

| Category | Commits |
|---|---:|
| [Compact and windowless cards](#compact) | 15 |
| [Window state and Space indicators](#state) | 16 |
| [Space movement and navigation](#spaces) | 8 |
| [Configurable shortcuts and filter scopes](#shortcuts) | 15 |
| [Persistent, menu-bar, swipe, and input sessions](#sessions) | 19 |
| [Window actions, Dock clicks, and post-action behavior](#actions) | 26 |
| [Native action menus and AppleScript](#menus) | 8 |
| [Search, scrolling, sizing, and navigation](#layout) | 19 |
| [Full-size and live preview appearance and lifecycle](#fullsize) | 7 |
| [Preview dragging and external spring-loading](#drag) | 4 |
| [Discovery, native tabs, fullscreen, and cache state](#discovery) | 27 |
| [Shared appearance, controls, widgets, and settings](#polish) | 14 |
| [App-icon badges](#badges) | 2 |
| [Diagnostics, synchronization, and numeric safety](#diagnostics) | 8 |
| [Build maintenance and upstream integration](#integration) | 4 |

<a id="compact"></a>

## Compact and windowless cards

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`e3b7a83`](https://github.com/hexcrete/DockFork/commit/e3b7a83de2222e6f9b8f8414ae8e82989fbcd07f) | feat: decouple compact mode width from preview width | Feature | 7 |
| [`1fe7adb`](https://github.com/hexcrete/DockFork/commit/1fe7adba09029e6dcb86f11ed7f5a39dcaa7cac0) | feat: add windowless app activation mode chooser | Feature | 10 |
| [`a6a7bd2`](https://github.com/hexcrete/DockFork/commit/a6a7bd241ecf3fc4fb3e05f920da592794fd885a) | feat: add switcher pills for hidden and windowless apps | Feature | 3 |
| [`ada279e`](https://github.com/hexcrete/DockFork/commit/ada279e6f8e935f4d235b91f40e75e1ab16254b3) | fix: respect mock preview state for windowless controls | Fix | 2 |
| [`157b66d`](https://github.com/hexcrete/DockFork/commit/157b66d01ce23028b666a20588dbd7ca95ad257f) | chore: remove legacy windowless activation toggle key | Maintenance | 2 |
| [`3ee8dae`](https://github.com/hexcrete/DockFork/commit/3ee8dae00b17c584067a27bae655bc8364160e0d) | refactor: split preview dimension lookup and fallback helpers<br>Earlier sizing-helper split; consolidated by 920efd4 and later placeholder fixes. | Evolved | 2 |
| [`f4194ce`](https://github.com/hexcrete/DockFork/commit/f4194cef168f385c201fd7397763d2adf3c5288d) | fix: keep windowless app entry after closing last switcher window | Fix | 1 |
| [`45b81b4`](https://github.com/hexcrete/DockFork/commit/45b81b46ece2c48ca7df4776922a9796ee671ab6) | fix: avoid full app scan when restoring windowless switcher entries | Fix | 2 |
| [`49ffaa7`](https://github.com/hexcrete/DockFork/commit/49ffaa7b3fbf6e40b510fe2983251f84e4f84ebb) | fix: use compact row styling for dock windowless previews | Fix | 1 |
| [`b18af84`](https://github.com/hexcrete/DockFork/commit/b18af84d3b4c3293b639af9f8512bdf98f65b3da) | fix: foreground apps after windowless window requests | Fix | 1 |
| [`c95f197`](https://github.com/hexcrete/DockFork/commit/c95f197830bebb18a1abc06043cc4d39b3a6428e) | fix: hide stale titles for windowless compact entries | Fix | 1 |
| [`5b61e21`](https://github.com/hexcrete/DockFork/commit/5b61e21f1fabff912bff486f14ed52d7a0605349) | fix: reconcile windowless and single-window filters | Fix | 6 |
| [`7b2491a`](https://github.com/hexcrete/DockFork/commit/7b2491a9a1d5b3ec7deb683d34227718dd42019c) | fix: align windowless placeholders with preview appearance | Fix | 3 |
| [`7368daf`](https://github.com/hexcrete/DockFork/commit/7368dafdf0e4c542a37015fc6e48e4bb89f361b4) | fix: preserve windowless card proportions with dynamic sizing | Fix | 1 |
| [`717c1e0`](https://github.com/hexcrete/DockFork/commit/717c1e0fbb76acc82cf96af5c9218edfec10f819) | fix: preserve full-size cards for missing window previews | Fix | 6 |

<a id="state"></a>

## Window state and Space indicators

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`d9677e8`](https://github.com/hexcrete/DockFork/commit/d9677e8721914021994b4173f594f995b090c0e7) | feat: add full screen window state indicators | Feature | 4 |
| [`9f4d609`](https://github.com/hexcrete/DockFork/commit/9f4d6094ba51f92f06241c158da0caf45a3b50e8) | feat: add Space indicators to window previews<br>Feature retained; per-mode state/Space presentation unified by d0c1249. | Evolved | 6 |
| [`9446f7e`](https://github.com/hexcrete/DockFork/commit/9446f7e8d3b32899a5c9b4fe7ffa88e923388371) | feat: add per-mode Space indicator controls | Feature | 9 |
| [`3976ef3`](https://github.com/hexcrete/DockFork/commit/3976ef3be96d922d7b0e8e0066520243f6efc541) | feat: add Space indicator styling options<br>Styling feature retained; later control metrics and font settings refine layout. | Evolved | 8 |
| [`fe4acfa`](https://github.com/hexcrete/DockFork/commit/fe4acfa6bf6fdc81d7e726a179da2ac35c0d7095) | feat: explain Space indicator styling option | Feature | 3 |
| [`411618f`](https://github.com/hexcrete/DockFork/commit/411618fc9a1ad6e87e1486d903855407149cb354) | feat: add status indicators to Space indicator pills | Feature | 8 |
| [`20d3b2f`](https://github.com/hexcrete/DockFork/commit/20d3b2fa18f24f1aad7957c5729bcecf512bae63) | fix: distinguish minimized and hidden indicators | Fix | 1 |
| [`356af10`](https://github.com/hexcrete/DockFork/commit/356af105c7c75d169ec7b0af62c0457d7e652a1c) | fix: show status indicators without a Space number | Fix | 2 |
| [`628ddde`](https://github.com/hexcrete/DockFork/commit/628dddead11c5802e7ce6fda57fe10e93bf027d1) | fix: respect compact status indicator settings | Fix | 1 |
| [`2a79e61`](https://github.com/hexcrete/DockFork/commit/2a79e61503974d084aa2c1fba6ffdc455a12ecae) | feat: prioritize compact window state labels | Feature | 1 |
| [`d0c1249`](https://github.com/hexcrete/DockFork/commit/d0c1249dc06792e0115a95fd99ddc6b238c16753) | feat: add per-mode window state indicator placement | Feature | 10 |
| [`6248aab`](https://github.com/hexcrete/DockFork/commit/6248aab0f03453cb6370cf694969815fab5e1bf4) | feat: highlight current Space number indicators | Feature | 11 |
| [`b435c0a`](https://github.com/hexcrete/DockFork/commit/b435c0a7e7da27708625736598d7cb4ebcce42ea) | feat: add per-mode preview pill ordering | Feature | 8 |
| [`f7b64c9`](https://github.com/hexcrete/DockFork/commit/f7b64c98fd2e595c79d948c9168b0c62342500dd) | feat: limit preview pill swapping to compact mode | Feature | 7 |
| [`f933cd0`](https://github.com/hexcrete/DockFork/commit/f933cd00629aee22ca7df823e0f1e30a6b2805e1) | feat: add window state indicator font size setting | Feature | 7 |
| [`5606370`](https://github.com/hexcrete/DockFork/commit/5606370d05ca31ea41389e9b75b9a6f75d893f7f) | fix: remove window state preference migration<br>Removes automatic rewriting of state-indicator placement preferences at launch. | Fix | 2 |

<a id="spaces"></a>

## Space movement and navigation

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`2c1679d`](https://github.com/hexcrete/DockFork/commit/2c1679d9210af7bb71a12c1ab1d09fd73c86e1d8) | feat: add bring to current space preview action | Feature | 1 |
| [`cdd7b82`](https://github.com/hexcrete/DockFork/commit/cdd7b824e52c87d403ea0f7d47f45360837ebb18) | feat: move windows between Spaces from preview indicators | Feature | 8 |
| [`e579313`](https://github.com/hexcrete/DockFork/commit/e5793134edce45533d81e12d3c158b0e1d1cee61) | fix: dismiss Space menu with previews | Fix | 2 |
| [`5adb65f`](https://github.com/hexcrete/DockFork/commit/5adb65f5dbc1f673d6ff5f893d1f736fc2794220) | fix: adapt fullscreen Space icons to appearance | Fix | 1 |
| [`30b66fc`](https://github.com/hexcrete/DockFork/commit/30b66fc0fe8e99d18dd266a30b1aa997e0d73074) | refactor: centralize managed Space destination handling | Support | 3 |
| [`1c4ce38`](https://github.com/hexcrete/DockFork/commit/1c4ce38911108a44e534b1ca194b0cf46af23c8d) | feat: add numbered Spaces shortcuts | Feature | 8 |
| [`381e839`](https://github.com/hexcrete/DockFork/commit/381e83998d8d55a2d95fe0411bcf54f88040617d) | feat: label current Space in destination menu | Feature | 4 |
| [`0dce6a7`](https://github.com/hexcrete/DockFork/commit/0dce6a708aba4ff36913224e22ee9a09b2149fc1) | feat: exit fullscreen from Space destination menu | Feature | 2 |

<a id="shortcuts"></a>

## Configurable shortcuts and filter scopes

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`f23c7e8`](https://github.com/hexcrete/DockFork/commit/f23c7e8ae2c24de7e0a1bc8bb9c2d9be88bd170d) | fix: display keycode 0 shortcuts correctly in settings<br>Historical single-alternate configuration; replaced by UUID-backed rows in 94b4361. | Evolved | 5 |
| [`6b62149`](https://github.com/hexcrete/DockFork/commit/6b62149e403df12ed6ef448f98b4b823e3ce242b) | feat: make window preview keyboard shortcuts configurable as a dynamic list | Feature | 5 |
| [`c93d424`](https://github.com/hexcrete/DockFork/commit/c93d4248f97299571d93f8aaade2af4153891330) | fix: respect configured modifier for preview shortcuts | Fix | 5 |
| [`27e77ff`](https://github.com/hexcrete/DockFork/commit/27e77ffc463d339ebe25aa2e0492a1dafde808ae) | refactor: unify assignable preview action lists | Support | 4 |
| [`94b4361`](https://github.com/hexcrete/DockFork/commit/94b436116d2046d70002333c2aa88c1b938c6e73) | feat: support multiple alternate switcher shortcuts | Feature | 7 |
| [`af0bbcd`](https://github.com/hexcrete/DockFork/commit/af0bbcd72bf472d0a362c845151f3655c2ab4177) | feat: add last focused window shortcuts<br>Feature retained; final MRU selection uses shared switcher ordering after 69507bc. | Evolved | 6 |
| [`d2d063c`](https://github.com/hexcrete/DockFork/commit/d2d063c163c0228becd6b0bc030a98e83e9f5da0) | feat: add monitor scopes to switcher shortcuts | Feature | 4 |
| [`982c6d0`](https://github.com/hexcrete/DockFork/commit/982c6d0f1e93c5a1920cf77254c84b3eb30cf2a6) | feat: filter windowless apps from location scopes | Feature | 5 |
| [`69507bc`](https://github.com/hexcrete/DockFork/commit/69507bc384c998a803b441ef4e94058bc21c95ae) | fix: use switcher MRU order for last focused shortcut | Fix | 2 |
| [`93074e7`](https://github.com/hexcrete/DockFork/commit/93074e7d39c3dea8e9c22695d1603fac58e75b51) | fix: defer recording for new shortcut rows | Fix | 3 |
| [`b56df65`](https://github.com/hexcrete/DockFork/commit/b56df655001ee13826e00fa7d2a3e2253365b4c8) | fix: show glyphs in double-tap modifier pickers | Fix | 1 |
| [`d013ee1`](https://github.com/hexcrete/DockFork/commit/d013ee103321cca065c54c71b71cacfd829d296e) | feat: support side-specific switcher modifier keys | Feature | 10 |
| [`428b2af`](https://github.com/hexcrete/DockFork/commit/428b2afff6e3a477bff9e32de89225825be4df13) | refactor: align modifier side naming | Support | 2 |
| [`be73708`](https://github.com/hexcrete/DockFork/commit/be737087f10b41f40cdb0cbcaf49bb9d8adc7323) | fix: use Command for Cmd+Tab preview shortcuts | Fix | 4 |
| [`bfaf5f4`](https://github.com/hexcrete/DockFork/commit/bfaf5f40bc9bd34fc0100e44411f217260592d8c) | fix: respect mouse follows focus in last focused shortcut | Fix | 1 |

<a id="sessions"></a>

## Persistent, menu-bar, swipe, and input sessions

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`fad5623`](https://github.com/hexcrete/DockFork/commit/fad5623de79e2f67c820479f2b3e614a1a857731) | fix: unify dock preview selection for mouse and keyboard | Fix | 4 |
| [`eeded1c`](https://github.com/hexcrete/DockFork/commit/eeded1ccf90bdf47ec08da550c08e43e04792df6) | feat: add compact-mode hover actions setting and shared dock gating | Feature | 6 |
| [`9aa806d`](https://github.com/hexcrete/DockFork/commit/9aa806d414385a2b1e7896327b36f21c35bcde3c) | feat: extend hover actions to window switcher and cmd+tab | Feature | 11 |
| [`2b09522`](https://github.com/hexcrete/DockFork/commit/2b09522ed1c78e6d3eaed7f691cd39314257608b) | fix: align cmd+tab hover selection with unified input model | Fix | 1 |
| [`af74149`](https://github.com/hexcrete/DockFork/commit/af7414934152ae409b7dfa840d67a32d2af298d6) | fix: restore native menu bar toggle behavior | Fix | 1 |
| [`c9adbf9`](https://github.com/hexcrete/DockFork/commit/c9adbf9082d4b291df117d533922beca78e0b63d) | feat: open window switcher from menu bar icon | Feature | 8 |
| [`c46bfae`](https://github.com/hexcrete/DockFork/commit/c46bfae01b57b2f2c4132a4d89bbdd4579d282ac) | fix: stabilize menu bar switcher and menu toggles | Fix | 2 |
| [`53735cf`](https://github.com/hexcrete/DockFork/commit/53735cf40761837f6693bdf2a4bf0a8824e5a28d) | fix: preserve menu bar switcher on modifier release | Fix | 1 |
| [`499bac8`](https://github.com/hexcrete/DockFork/commit/499bac8e42eb534e05b70c9dd84634c77ef9740a) | fix: respect user switcher settings for menu bar launch | Fix | 1 |
| [`d9f036a`](https://github.com/hexcrete/DockFork/commit/d9f036a7b7294fe5a8809290c5ea0efdf6f9dfcb) | fix: cancel switcher sessions on Space changes | Fix | 3 |
| [`19d4888`](https://github.com/hexcrete/DockFork/commit/19d4888f406219fd496005e6adaa5de5bbdc5282) | feat: add persistent window switcher shortcuts | Feature | 5 |
| [`2898dc6`](https://github.com/hexcrete/DockFork/commit/2898dc68e88b0a12c5211c360d47ceacbc0d0596) | feat: allow persistent switchers to start unhighlighted | Feature | 6 |
| [`1571630`](https://github.com/hexcrete/DockFork/commit/1571630c3b4d422d2892dca98e9d8343cf054493) | fix: respect mouse follows focus in persistent switchers | Fix | 3 |
| [`7444347`](https://github.com/hexcrete/DockFork/commit/74443470830ec52c38faaba5d0b520ad7d800c66) | fix: prevent synthetic preview hover activation | Fix | 8 |
| [`78bfbf6`](https://github.com/hexcrete/DockFork/commit/78bfbf61207b0d3405ce2c289d696d2c2c2ace57) | feat: allow swipe takeover of persistent window switchers | Feature | 7 |
| [`7797cdf`](https://github.com/hexcrete/DockFork/commit/7797cdf5c27ac214f4b81c8761f4543dd747f737) | feat: add reversible trackpad swipe selection | Feature | 6 |
| [`ae93b49`](https://github.com/hexcrete/DockFork/commit/ae93b49d50c4ba4391a542d1d658836f58aca446) | fix: distinguish swipe and modifier switcher ownership | Fix | 2 |
| [`43aef75`](https://github.com/hexcrete/DockFork/commit/43aef75bf72d074587f2d7996ed43dfc122ace26) | ui: reposition system swipe gesture explainer | UI | 1 |
| [`5674792`](https://github.com/hexcrete/DockFork/commit/56747922d3326af95280e5c58c7ba18d9ea1f829) | ui: clarify persistent and default switcher shortcut labels | UI | 3 |

<a id="actions"></a>

## Window actions, Dock clicks, and post-action behavior

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`613d39c`](https://github.com/hexcrete/DockFork/commit/613d39ca54dd92583d034f4a9b87fc632de576c1) | fix: keep window switcher open when quitting apps | Fix | 2 |
| [`0a23289`](https://github.com/hexcrete/DockFork/commit/0a23289f19409cf47f8d2a2a06e42c85dbf4fe4e) | fix: remove optimistic close/quit removal and close-all pre-removal | Fix | 3 |
| [`26b8544`](https://github.com/hexcrete/DockFork/commit/26b8544c0ecbbce8129444340b018b4a12ac276d) | fix: reconcile close/quit state after action across dock and switchers | Fix | 4 |
| [`0ee6be5`](https://github.com/hexcrete/DockFork/commit/0ee6be510381c6f583d3e4a7840c518e9ab86c12) | feat: reuse close-all behavior for windowless Close Window | Feature | 2 |
| [`219ab48`](https://github.com/hexcrete/DockFork/commit/219ab48d89ebfdf4d2ad88850175a41d03bbd97f) | feat: support close/quit shortcuts on highlighted cmd-tab app | Feature | 2 |
| [`adae447`](https://github.com/hexcrete/DockFork/commit/adae447d11610a6371ccfe62f1953b3d0ce60c43) | fix: harden minimize and hide outcome state sync | Fix | 4 |
| [`ffa82dd`](https://github.com/hexcrete/DockFork/commit/ffa82dd0ba9af315191b75a2183916e288cf49b1) | feat: add close-all and minimize-all preview actions | Feature | 1 |
| [`211d798`](https://github.com/hexcrete/DockFork/commit/211d7981a0aba1b8e95c03f4d28ac6d89f6e1f3b) | feat: toggle minimize-all to restore when all windows are minimized<br>Restore behavior retained; final minimize-state pipeline is in 4743b0e / df7bf47. | Evolved | 2 |
| [`1d4ad2b`](https://github.com/hexcrete/DockFork/commit/1d4ad2bb9d59c33241fba2d39d1b873aa4fb5b32) | fix: harden bulk action outcomes and context reconciliation | Fix | 3 |
| [`2b04303`](https://github.com/hexcrete/DockFork/commit/2b043033144a54bd6f0f6f1e462d4a1b235035bf) | fix: harden toggle full screen outcome with delayed confirmation | Fix | 4 |
| [`bef9786`](https://github.com/hexcrete/DockFork/commit/bef9786933ac707e7a6ec82660aba47796ed7d34) | feat: add keep-previews post-action settings and search indexing<br>Feature retained; initial enum-valued preference design replaced with toggles by f515ccb. | Evolved | 5 |
| [`967671b`](https://github.com/hexcrete/DockFork/commit/967671bdc53b6d14eb6551f77671cf7857ea1dfa) | refactor: route preview actions through category-aware shared flow<br>Category routing remains relevant; enum-valued post-action settings simplified by f515ccb. | Evolved | 5 |
| [`e6333dd`](https://github.com/hexcrete/DockFork/commit/e6333ddf87a71587643515bea0848df2950b1e8c) | fix: harden deferred action watchers and dedupe refresh tasks | Fix | 5 |
| [`f515ccb`](https://github.com/hexcrete/DockFork/commit/f515ccbc59cfe85f3c54baaf5ad2202dc3b1ef12) | refactor: collapse post-action preview behavior to keep-open toggles | Support | 6 |
| [`e09f632`](https://github.com/hexcrete/DockFork/commit/e09f6320e7aab63e656d195fa771631dfd800368) | refactor: remove dead post-action focus plumbing | Support | 3 |
| [`35f9eb1`](https://github.com/hexcrete/DockFork/commit/35f9eb1a82c2eb0341b01727d83dd8766f578b57) | fix: stabilize minimize and unminimize-all behavior | Fix | 3 |
| [`5dfb25c`](https://github.com/hexcrete/DockFork/commit/5dfb25c85528fffec1d098f4ed903feea3404b44) | fix: make aero shake global minimize reliable across spaces | Fix | 2 |
| [`4632319`](https://github.com/hexcrete/DockFork/commit/4632319b9f4bf37e3366efd44d4bad83a58940eb) | fix: resolve hide actions before dismissing previews | Fix | 4 |
| [`f670aa4`](https://github.com/hexcrete/DockFork/commit/f670aa4b51e8a302964ab9c6745747e0eff55bdc) | fix: preserve dock previews during hide actions | Fix | 5 |
| [`dc941a0`](https://github.com/hexcrete/DockFork/commit/dc941a0b0e94eefa45b3e21bb06e113ea768cf3d) | refactor: simplify boolean returns and condense minimize‑all state handling | Support | 3 |
| [`28075b2`](https://github.com/hexcrete/DockFork/commit/28075b212ff2757fbec90c01bacd32343e993ef8) | feat: add dock window cycling action | Feature | 5 |
| [`3d42eaa`](https://github.com/hexcrete/DockFork/commit/3d42eaadab951187b4003d0b0489bdbfc78b281e) | fix: preserve Cmd+Tab previews during shortcut actions | Fix | 2 |
| [`26f33aa`](https://github.com/hexcrete/DockFork/commit/26f33aaab3888aefd4241c352571f12f69ab2f4c) | fix: decouple move resize foreground behavior | Fix | 3 |
| [`385cf0b`](https://github.com/hexcrete/DockFork/commit/385cf0b0110a2a2e16de4af82952bfe1aa0962f8) | fix: preserve Cmd+Tab previews when foregrounding moved windows | Fix | 1 |
| [`4743b0e`](https://github.com/hexcrete/DockFork/commit/4743b0e0636b99c6ac56d8375258c3539e2e4796) | fix: stabilize Dock click window actions | Fix | 7 |
| [`df7bf47`](https://github.com/hexcrete/DockFork/commit/df7bf47a3d56ecf43c065e4e74053e8ecc18a7de) | refactor: unify minimize all window actions | Support | 2 |

<a id="menus"></a>

## Native action menus and AppleScript

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`16a68eb`](https://github.com/hexcrete/DockFork/commit/16a68eb4327e15771f575892ffc0e725fb6bf4a7) | refactor: use native preview context menus | Support | 3 |
| [`5ef868b`](https://github.com/hexcrete/DockFork/commit/5ef868bc8501dfc0527961ead96bfe2c47bfe1bb) | feat: add Space picker to preview context menus | Feature | 2 |
| [`5532376`](https://github.com/hexcrete/DockFork/commit/55323768dc8c4b3e0801122b986d6def4c311667) | feat: enrich preview context menus | Feature | 7 |
| [`5d50fd8`](https://github.com/hexcrete/DockFork/commit/5d50fd81b27760cc7efda9e9d70223dec67e93eb) | refactor: share native window action menu construction | Support | 3 |
| [`92908e2`](https://github.com/hexcrete/DockFork/commit/92908e257f29f98d32f6f79bc23300c9849c91e5) | feat: expose managed Spaces through AppleScript | Feature | 4 |
| [`4d38e51`](https://github.com/hexcrete/DockFork/commit/4d38e51d90cda278e8ed623b71be709db3694da8) | fix: launch scripted switcher through persistent session | Fix | 4 |
| [`da9f3f3`](https://github.com/hexcrete/DockFork/commit/da9f3f3b913f33bc8b328e05377872bcb759cdc2) | feat: switch managed Spaces through AppleScript | Feature | 3 |
| [`ccfec9d`](https://github.com/hexcrete/DockFork/commit/ccfec9d85e500425bb310f6dbbc58eb22032c2fd) | fix: preserve switcher while native menus handle clicks | Fix | 3 |

<a id="layout"></a>

## Search, scrolling, sizing, and navigation

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`12e0a77`](https://github.com/hexcrete/DockFork/commit/12e0a77319fadbabd66a183a7700ee4230d2a9c4) | fix: align switcher search pill styling and behavior | Fix | 2 |
| [`b2c930d`](https://github.com/hexcrete/DockFork/commit/b2c930d6c9461c77861058b5f2a82d47b7be36b1) | fix: prevent window switcher search pill jump by enforcing single-line editor behavior | Fix | 1 |
| [`d6c231f`](https://github.com/hexcrete/DockFork/commit/d6c231f8dfcc3e8eb996abdbfff93cd7d6aaf674) | feat: add window switcher anchor controls and refined offset controls | Feature | 5 |
| [`9cc45ae`](https://github.com/hexcrete/DockFork/commit/9cc45ae5471fbc4276b32f5b41804114c894dffe) | fix: make switcher padding area click-through for outside dismiss | Fix | 1 |
| [`5edebba`](https://github.com/hexcrete/DockFork/commit/5edebba05d4e48089db4822b16e55ac5badff55d) | fix: anchor edge auto-scroll to container edges | Fix | 1 |
| [`bbb44ad`](https://github.com/hexcrete/DockFork/commit/bbb44ad77c78dcbf84fd34c625da3f08eafab024) | fix: require pointer movement before edge auto-scroll | Fix | 2 |
| [`c802975`](https://github.com/hexcrete/DockFork/commit/c802975da0e63d1d94c07738e5bcdbb7be67bd84) | fix: resize previews after same-count window replacement | Fix | 1 |
| [`9c7ac61`](https://github.com/hexcrete/DockFork/commit/9c7ac612363eff2ca7680de8d0b2e0bf4becfb0a) | fix: align compact padding and scroll fades | Fix | 2 |
| [`ef27fdf`](https://github.com/hexcrete/DockFork/commit/ef27fdf537d0ba5c198646bf3aedd2e1033e1b2d) | fix: inset preview content from container border | Fix | 2 |
| [`19b3ddd`](https://github.com/hexcrete/DockFork/commit/19b3dddd4a13e7e6b4c792a35430aee9f6728b9e) | fix: restore horizontal window switcher scrolling | Fix | 4 |
| [`8af3b00`](https://github.com/hexcrete/DockFork/commit/8af3b00a1239bf92daff45b1242f47095f8ee93c) | fix: align switcher cycling with grid direction | Fix | 1 |
| [`08c52c6`](https://github.com/hexcrete/DockFork/commit/08c52c666ae90dcd16f2dd3b8995ef9b5131f19a) | fix: restore configurable edge auto-scroll across preview modes | Fix | 9 |
| [`920efd4`](https://github.com/hexcrete/DockFork/commit/920efd47fbafcd2e3bc051304a2dcc07ac89079c) | refactor: centralize preview layout decisions | Support | 4 |
| [`fc8d255`](https://github.com/hexcrete/DockFork/commit/fc8d255ac25e854ccb70b6aea7c087c576cd1e54) | refactor: unify preview card chrome | Support | 4 |
| [`f7e5a12`](https://github.com/hexcrete/DockFork/commit/f7e5a127f34a3403a800e4dd5f0b251ea75b30cc) | fix: clear preview selection during edge auto-scroll | Fix | 1 |
| [`586407f`](https://github.com/hexcrete/DockFork/commit/586407f834990a2949dc0e8eb68776cbd6be92d9) | fix: prevent window switcher search overlap | Fix | 2 |
| [`f4ccf61`](https://github.com/hexcrete/DockFork/commit/f4ccf6167a245a18188023987465aee33ff11037) | fix: support vertical arrow navigation in previews | Fix | 2 |
| [`ad279a5`](https://github.com/hexcrete/DockFork/commit/ad279a53fc6bb5b7a4923d0ec983a0038f86b953) | fix: hide search shortcut hint while active<br>First helper-focus fix; click-focus handling refined by 9151f2d. | Evolved | 1 |
| [`9151f2d`](https://github.com/hexcrete/DockFork/commit/9151f2d14e728441373a36b1b5789c6db2e4e6ac) | fix: hide search shortcut hint on click focus | Fix | 1 |

<a id="fullsize"></a>

## Full-size and live preview appearance and lifecycle

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`97096c7`](https://github.com/hexcrete/DockFork/commit/97096c7b0ffed42cd701105e5c631ce2e5d0898c) | feat: add full-size preview appearance controls | Feature | 5 |
| [`9b8bebf`](https://github.com/hexcrete/DockFork/commit/9b8bebf2cb1ed611e61868677a6a64a1a478d754) | fix: preserve keyboard-driven full-size preview updates | Fix | 2 |
| [`3c0cf89`](https://github.com/hexcrete/DockFork/commit/3c0cf896fd616c616143387667def90b07af0362) | feat: add full size preview fade controls | Feature | 4 |
| [`c2fa95d`](https://github.com/hexcrete/DockFork/commit/c2fa95d84a61c715b1efef688153d61e299930e9) | feat: fade preview containers while resting on full-size previews<br>Feature retained as experimental; 220464d changes its default to off. | Evolved | 9 |
| [`220464d`](https://github.com/hexcrete/DockFork/commit/220464ded2ab064e11ce31775977629ad250ddeb) | fix: mark preview resting fade experimental and default off | Fix | 3 |
| [`e8d0ad5`](https://github.com/hexcrete/DockFork/commit/e8d0ad51d6b5142c684edf7dc4026769b3cebd54) | fix: stop cached live captures when preview modes are disabled<br>Stops cached streams when their requesting modes are disabled; preserves other enabled contexts and rejects stale asynchronous starts. | Fix | 4 |
| [`9efa1cc`](https://github.com/hexcrete/DockFork/commit/9efa1cc188ff3a1f64556360ca18ef2f1d41a857) | fix: allow editing live preview keep-alive duration<br>Keeps the timed-duration field focused and commits edits on Return or focus loss instead of rewriting text during typing. | Fix | 1 |

<a id="drag"></a>

## Preview dragging and external spring-loading

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`a7d61d1`](https://github.com/hexcrete/DockFork/commit/a7d61d1ce1251667d7467f98eb9fab9f1aa698bb) | fix: harden window preview drag sessions | Fix | 4 |
| [`78f65dd`](https://github.com/hexcrete/DockFork/commit/78f65dd8fd0bb5cc332317b1723e68987df2c521) | feat: support reliable preview dragging across layouts | Feature | 3 |
| [`1ceb007`](https://github.com/hexcrete/DockFork/commit/1ceb00734b1ef28ae487662c5693b63b01423947) | fix: spring-load external drags onto preview windows | Fix | 5 |
| [`ba665c2`](https://github.com/hexcrete/DockFork/commit/ba665c2eb25c776123782ef44a9181a4d9b0bf61) | feat: configure preview spring-loading behavior | Feature | 4 |

<a id="discovery"></a>

## Discovery, native tabs, fullscreen, and cache state

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`581c0ed`](https://github.com/hexcrete/DockFork/commit/581c0ed39ea9d5f5e08df77ab61dbb6482ed29f8) | refactor: add debounced resize preview recapture helpers | Support | 1 |
| [`9835d4e`](https://github.com/hexcrete/DockFork/commit/9835d4e40b8b7922aa34beeacf74eb315008342c) | fix: refresh cached previews after programmatic and AX resize | Fix | 2 |
| [`fcc222a`](https://github.com/hexcrete/DockFork/commit/fcc222aff8b7ed03ac58482c15faaad6f996d93c) | feat: expose and apply resize preview refresh delay settings | Feature | 5 |
| [`7978711`](https://github.com/hexcrete/DockFork/commit/79787119a2a68bcb1dd64d4f9a52d1d503a4544a) | fix: stabilize switcher refresh merge and selection preservation | Fix | 2 |
| [`f9cf18f`](https://github.com/hexcrete/DockFork/commit/f9cf18f1442306ceb2d83af645c20abf536e9e37) | fix: prevent narrow fullscreen previews from bad capture aspect | Fix | 2 |
| [`9a05dc8`](https://github.com/hexcrete/DockFork/commit/9a05dc8e5361c44aba52448599b20803bd155ea3) | fix: align hidden/fullscreen preview semantics and tab recapture fallback | Fix | 2 |
| [`eed33ed`](https://github.com/hexcrete/DockFork/commit/eed33ed4b3a523135df90298e4d22e84e8cf7867) | perf: cache fullscreen state for hidden-window hot paths | Support | 2 |
| [`de8bef8`](https://github.com/hexcrete/DockFork/commit/de8bef8b957dc09be4c4014864d696c279b643b7) | perf: coalesce active-focused-window refresh scheduling | Support | 1 |
| [`15c148a`](https://github.com/hexcrete/DockFork/commit/15c148a66e7e0f29f66173e988d481cbe2654ea7) | fix: preserve switcher row order during app refresh after actions | Fix | 2 |
| [`991ba81`](https://github.com/hexcrete/DockFork/commit/991ba81947b4bff22162979116cbced0a9723349) | refactor: unify per-pid row refresh merge logic | Support | 3 |
| [`63b9612`](https://github.com/hexcrete/DockFork/commit/63b9612756c4f61f9495c8cae210918c1de7c867) | fix: filter noninteractive ghost window previews | Fix | 3 |
| [`9271005`](https://github.com/hexcrete/DockFork/commit/9271005e96cff738b5e500811530306fb6a6daf5) | fix: exclude internal panels from self previews | Fix | 1 |
| [`fdbdb3f`](https://github.com/hexcrete/DockFork/commit/fdbdb3fc6ff179e4dea018a7fe8b0f1c2d6a9e84) | fix: align Cmd+Tab windowless preview resolution | Fix | 4 |
| [`4815284`](https://github.com/hexcrete/DockFork/commit/4815284b7ea7d7d2a56d288f6ebe5629aeaa7787) | fix: harden Cmd+Tab preview discovery lifecycle | Fix | 2 |
| [`337f79c`](https://github.com/hexcrete/DockFork/commit/337f79c1c6fd7e7bbbd2ad448a106fa58e06ddd0) | fix: align Cmd+Tab app-group actions and resolution | Fix | 4 |
| [`1720afa`](https://github.com/hexcrete/DockFork/commit/1720afa8187c077ce1e1965e71db763536522e60) | fix: filter live preview control proxy windows | Fix | 3 |
| [`4f703ed`](https://github.com/hexcrete/DockFork/commit/4f703ed4dc305cea284db6be2bed6accc0db5be8) | fix: stabilize native tab grouping with current geometry<br>Native-tab work retained and revised; current cross-app grouping is in 6fb1946. | Evolved | 1 |
| [`804d85a`](https://github.com/hexcrete/DockFork/commit/804d85a89de651ec32a910ad6f24e10691bba413) | fix: recognize actionable nonstandard windows | Fix | 5 |
| [`288262b`](https://github.com/hexcrete/DockFork/commit/288262b641145f48c04713a6bc4610fc11d17e1d) | fix: limit controls for nonstandard windows | Fix | 2 |
| [`e2e4c45`](https://github.com/hexcrete/DockFork/commit/e2e4c4578ab20ff42b7af911e61f0632afc92540) | fix: reconcile fullscreen and Space metadata safely | Fix | 5 |
| [`a94bb4d`](https://github.com/hexcrete/DockFork/commit/a94bb4d241792f9ae37da1f30ed89c52b41e4665) | fix: improve startup and cross-Space window discovery | Fix | 6 |
| [`1a5a978`](https://github.com/hexcrete/DockFork/commit/1a5a9780d20476ad9d88a601d8a721f086dcba8d) | fix: refresh Space numbers for new fullscreen Spaces | Fix | 2 |
| [`7d5ac4a`](https://github.com/hexcrete/DockFork/commit/7d5ac4a6285f06c16b66e35fe3ad79648afc9b2c) | fix: filter unspaced fullscreen window aliases | Fix | 3 |
| [`abdc4ec`](https://github.com/hexcrete/DockFork/commit/abdc4ec41a8169d72d998985d621b1acff917747) | fix: preserve native tab groups across visibility changes<br>Finder-specific visibility snapshots generalized across apps by 6fb1946. | Evolved | 5 |
| [`b8c0aa4`](https://github.com/hexcrete/DockFork/commit/b8c0aa440d5f550444a5c43d063bf15b34938c36) | perf: coalesce Dock preview discovery | Support | 1 |
| [`6fb1946`](https://github.com/hexcrete/DockFork/commit/6fb1946f22ebb25be200099903b3ff2b14bec9f8) | fix: preserve native tab grouping across Spaces for all apps | Fix | 3 |
| [`6fe02cc`](https://github.com/hexcrete/DockFork/commit/6fe02ccbcc881dba0e2d64a51ca0897532675ede) | fix: recover missing window previews after Space transitions | Fix | 2 |

<a id="polish"></a>

## Shared appearance, controls, widgets, and settings

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`c116f4e`](https://github.com/hexcrete/DockFork/commit/c116f4e478f3405a81adc5f4ac4b6fe8e20f15ab) | fix: keep dock popover header hover tracking aligned with preview highlights | Fix | 1 |
| [`b4baca1`](https://github.com/hexcrete/DockFork/commit/b4baca18c3e5019894452af2ca53619244f15007) | fix: hide traffic light controls until preview hover | Fix | 1 |
| [`b4ce12a`](https://github.com/hexcrete/DockFork/commit/b4ce12ac69cb151a68082736d1b3f1e7b0ad1be4) | feat: add always-visible dimmed traffic light mode | Feature | 2 |
| [`c832c1f`](https://github.com/hexcrete/DockFork/commit/c832c1fdf6110316cb6b2a3d687e785c7755e0d2) | fix: preserve preview layout when hover controls appear | Fix | 1 |
| [`a86d0c7`](https://github.com/hexcrete/DockFork/commit/a86d0c7ba47c13330d8731e6b25358b53b42dbfc) | fix: dynamically size preview titles around hover controls | Fix | 6 |
| [`023bfd2`](https://github.com/hexcrete/DockFork/commit/023bfd2c88ea854769eac5ab1875f491687cfc13) | refactor: move shared preview sizing controls to appearance | Support | 4 |
| [`e786998`](https://github.com/hexcrete/DockFork/commit/e786998865141ef7516f65bb5bebb50bf0dc2186) | fix: route mode appearance search results correctly | Fix | 2 |
| [`a9f400a`](https://github.com/hexcrete/DockFork/commit/a9f400a13cc4d4dcbe160ed39e8c76bb2c946dff) | fix: align widgets with compact preview rows | Fix | 1 |
| [`82a8449`](https://github.com/hexcrete/DockFork/commit/82a8449f617fd2210d66f517c570bbcc577d9e81) | fix: mirror trailing preview title alignment | Fix | 3 |
| [`bdc36e5`](https://github.com/hexcrete/DockFork/commit/bdc36e5f1531fdfef5b59f20ad8b377061443ac6) | fix: respect traffic light styling in compact mode | Fix | 1 |
| [`ba71716`](https://github.com/hexcrete/DockFork/commit/ba717168547f56f93a747602191afb2a7b98f3a7) | fix: unify contrast shadows for embedded preview controls | Fix | 3 |
| [`9ce4a89`](https://github.com/hexcrete/DockFork/commit/9ce4a89e625ccc19993e1600ee1ceba22d8dadb0) | fix: unify preview control edge alignment | Fix | 4 |
| [`1aebbc5`](https://github.com/hexcrete/DockFork/commit/1aebbc5613719cb2eb5920a5d6c99cf76a00caed) | fix: respect hover-only traffic lights in mock previews | Fix | 6 |
| [`1f7ce92`](https://github.com/hexcrete/DockFork/commit/1f7ce92edac53b6008066922c0e05ab4377e7bbe) | feat: unify configurable traffic light transitions | Feature | 10 |

<a id="badges"></a>

## App-icon badges

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`424c16c`](https://github.com/hexcrete/DockFork/commit/424c16cf2283a4a77566cd4b71ed045afed41668) | feat: show app icon badges in window switcher | Feature | 10 |
| [`6f05d62`](https://github.com/hexcrete/DockFork/commit/6f05d6282d64ed5c9c56dd2e53dcff9be87863bf) | fix: avoid initializing badge store during preview cleanup<br>Preview cleanup no longer constructs an unused badge store. | Fix | 2 |

<a id="diagnostics"></a>

## Diagnostics, synchronization, and numeric safety

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`77ee4d3`](https://github.com/hexcrete/DockFork/commit/77ee4d3d47b4ff3980a5e68f01e1c121f91dc7b7) | feat: integrate hang diagnostics with debug logging | Feature | 9 |
| [`d36dbd5`](https://github.com/hexcrete/DockFork/commit/d36dbd58e3eca8c6c9428215a3f2fce945e19f38) | fix: prevent preview refresh stalls | Fix | 2 |
| [`f96dd57`](https://github.com/hexcrete/DockFork/commit/f96dd5720eeca2c61db21b3c191e95d0b3846602) | fix: prevent preview cache deadlocks during window updates | Fix | 3 |
| [`06c9471`](https://github.com/hexcrete/DockFork/commit/06c94713f6a332bbfee7f011e81690d073165e19) | fix: guard modifier double-tap timestamps | Fix | 1 |
| [`8ebbf74`](https://github.com/hexcrete/DockFork/commit/8ebbf7431ca4523a56c8e1e946ba66980b64e00c) | fix: guard live preview keep-alive overflow | Fix | 1 |
| [`b689a62`](https://github.com/hexcrete/DockFork/commit/b689a62f0af5b1b942d09eb9133ad67c20695f7e) | fix: validate persisted operation delays | Fix | 2 |
| [`a9a3df1`](https://github.com/hexcrete/DockFork/commit/a9a3df1bcf2fdda2e057a8160af538d34489172d) | fix: synchronize window observer task lifecycle | Fix | 1 |
| [`a2aa5b5`](https://github.com/hexcrete/DockFork/commit/a2aa5b501d0ac4aa596affc4ac20beb046a606b2) | fix: synchronize preview event state | Fix | 7 |

<a id="integration"></a>

## Build maintenance and upstream integration

| Commit | Historical change | Role | Changed files |
|---|---|---|---:|
| [`e788282`](https://github.com/hexcrete/DockFork/commit/e7882824f2bbd4fce5dc1697fd51ebb4e81c7da4) | Merge origin/main into better_previews | Integration | 113 |
| [`f84ca37`](https://github.com/hexcrete/DockFork/commit/f84ca377ce3ccffeebfc64b729497d619a5f2f27) | build: ignore profraw coverage artifacts | Maintenance | 1 |
| [`4781d80`](https://github.com/hexcrete/DockFork/commit/4781d80f09ad28ad396e0f0a2ac685b769bf143d) | Merge origin/main into better_dd_merged | Integration | 155 |
| [`57f7f45`](https://github.com/hexcrete/DockFork/commit/57f7f450d325a7e72cfd6904fbb98068b15ef44d) | merge: update better_dd_merged with upstream main | Integration | 18 |

## Post-Audit Continuation

Coverage: `9efa1cc..5f773ed9`, extended and verified against Git October 20, 2026. Action feedback, Mouse Follows Focus feedback, app-header wording and their documentation are included. The native-tab discovery/minimization fix and its verification records are included; unsuccessful membership-cache drafts were discarded. Both core explicit Quit/Force Quit and its scripting/documentation follow-up are included. Action-responsiveness Stage 1 and its ordinary-click restoration correction are included. Stage 2 asynchronous native Cmd+Tab highlighted-app Close and its group-Minimize roadmap follow-up are included. Stage 3 frame transactions and its full-size-preview correction are included after user verification. Stage 4 background drag placement and its user verification are included. The separate spring-loading dismissal correction is included. Stage 5 is committed and included. Shared-action ownership Stage 1 replaces the user-tested minimize-only draft and is committed after review as `013762f5`, included here. Stage 2 direct-route migration, including its native-tested scripted Space-list correction, is committed as `bb1c0deb` and included here. The Stage 2 verification/documentation commit `2dfd752c` is included. Stage 3 accounting is committed as `617ad3fb` after final review and user approval, including write-first same-app confirmation with opportunistic progress, fullscreen Auto Tile exclusions, shared outcome delivery and independent geometry progress. Stage 3 records and the approved spinner-only success-symbol plan are included as `62075ddc`. Stage 4 presentation and its Space-transition lifetime correction are committed as `7936b273` after user verification and final review, included here. Stage 4 verification records are included as `5f7ce40e`. Stage 5 gesture results are committed as `b2cb01e9` after user verification and final review, completing the five-stage shared ownership/feedback plan. Its six source/test files are included here. Stage 5 verification records are included as `f04284aa`. Cmd+Tab app-level Minimize is included as `4038decf` after user verification and final review, with four source/test files; its verification records are included as `b23f53cf`. The cursor-feedback setting relocation and hide-when-unavailable rule are included as `c5d64dc6` after user verification and final review October 20, with four source/test files. Its guide/showcase/verification records are included as `7850a6e3`. The popup Space-transition workaround removal is included as `685d1713` after final review and user authorization, with five source/test files. Native visual verification remains unreported. Its verification/resource/showcase records are included as `d084e66a`. Build-output cleanup is included as `715421b3` after final review and user authorization, with two script/test files. Updated default commands and fork records are included as `ae104843`. Windowless preview transition sizing and mode-aware header visibility are included as `1b6cd4b3` after user verification of the initial transition and approval of the final refinement. All thirteen regression suites and signed Debug build/relaunch checks pass; exhaustive native visual coverage remains pending. The documentation commit containing this ledger update receives its exact hash next time. New commits receive their exact hashes in a subsequent ledger update, not in themselves. These commits are recorded once here rather than inserted into the frozen category tables. The fixed audit baseline means this continuation also includes fourteen later-integrated upstream commits, explicitly attributed below; they are not fork-authored features. Fork-only documentation/build assets are excluded from upstream PRs; the application-default change is separate and still requires upstream compatibility review.

| Commit | Category / purpose | Role | Changed files |
|---|---|---|---:|
| [`50a9595`](https://github.com/hexcrete/DockFork/commit/50a9595b117511dccc012bf2a4f17010bd6d0ad5) | Publication: document fork changes, commit history, showcase candidates, roadmap, and contribution/resource review. | Documentation | 7 |
| [`287c38f`](https://github.com/hexcrete/DockFork/commit/287c38f05e612ceaa2cbed2413120b701fea22dc) | Publication: group fork assets and add the privacy-reviewed optional showcase preset. | Documentation / Preset | 9 |
| [`0127698`](https://github.com/hexcrete/DockFork/commit/0127698e0bd5ed1c8b128cc927b735e7b3f229c0) | Appearance defaults: enable state-pill styling and compact-only swapping per mode; show Current badge and unavailable Spaces by default. Saved preferences retain precedence. | Defaults | 2 |
| [`ac90770`](https://github.com/hexcrete/DockFork/commit/ac907708f9dc4e8306141f89208e2a5344b3f0e0) | Packaging: isolated DockFork identity, manual updates, ad-hoc Release build, source/checksum assets, and installation guidance. | Build | 10 |
| [`c8e06ee`](https://github.com/hexcrete/DockFork/commit/c8e06ee59f49a44d9c065f8db2401425014c77ba) | Packaging: certificate-signed Debug builds with tracked-source changes, graceful fixed-path replacement, and relaunch. Not for distribution. | Build | 3 |
| [`b157744`](https://github.com/hexcrete/DockFork/commit/b1577442f1ebf3a2ae05b54cff87fbdddfeaddc7) | Contribution workflow: fork build instructions and explicit final-diff/exclusion gates for focused upstream proposals. | Documentation | 3 |
| [`09a2cc2`](https://github.com/hexcrete/DockFork/commit/09a2cc2ffbf9e9405d4a7ebcb24de94c26315a7f) | Control spacing: remove the empty-slot gap beside hover-hidden traffic lights; retain visible-control spacing and height-based alignment across regular preview modes. Debug build/relaunch and user verification passed. | Fix | 1 |
| [`7e608d1`](https://github.com/hexcrete/DockFork/commit/7e608d1d49116905d06f55185613e08c4b77529b) | Publication maintenance: require ledger/showcase updates, account for post-audit commits, and refresh packaging/defaults/capture documentation. | Documentation | 5 |
| [`6a5599d`](https://github.com/hexcrete/DockFork/commit/6a5599d4eea15c0cd977434c2426652e2db4fa73) | Indicator interaction: give the shared Space picker button a full-label hit shape without changing layout, spacing, or enablement. Debug build/relaunch and user verification passed. | Fix | 1 |
| [`64a4fa4`](https://github.com/hexcrete/DockFork/commit/64a4fa4cdf72e6857a429a80353d908f40e78d13) | Publication maintenance: record Space indicator hit-target verification and extend ledger/showcase coverage. | Documentation | 3 |
| [`bdc62ae`](https://github.com/hexcrete/DockFork/commit/bdc62ae317e5cbe62aedbc752c4fa179f63f6d42) | Shared appearance: size Automatic switcher app icons by title visibility rather than title content; preserve hover-only changes, explicit-size limits, and Compact Mode sizing. Six focused sizing checks, Debug build/relaunch, and user verification passed. | Fix | 2 |
| [`7e13e4b`](https://github.com/hexcrete/DockFork/commit/7e13e4b9a0bc1dc56683d76e34721a5ffacf8329) | Publication maintenance: record shared Automatic icon sizing, hover visibility, and verification in the ledger/showcase records. | Documentation | 3 |
| [`6c51d22`](https://github.com/hexcrete/DockFork/commit/6c51d22ae902887123d6be0f1e9403bf6dd701a2) | Preview lifecycle: dismiss/suspend previews during settings import/export dialogs, pass shortcuts through, and restore launching on exit. Reuse existing dismissal, cancellation, and event snapshots; backup format and import semantics unchanged. Debug build/relaunch and user verification passed. | Fix | 6 |
| [`879178d`](https://github.com/hexcrete/DockFork/commit/879178d987c61a70b194c829be74df0f3e7981f6) | Publication records: document modal preview lifecycle fix and extend ledger coverage. | Documentation | 3 |
| [`0b961e1`](https://github.com/hexcrete/DockFork/commit/0b961e16f4fd190c6c5c616288d98ba3e10de89a) | Windowless presentation: per-mode full-size options for Dock/Cmd+Tab, default On; unify full-size placeholders with real-window card layout and interactions while retaining app-only controls and capture/drag guards. Eight focused presentation checks, signed Debug build/relaunch, and user manual verification passed; full Xcode test suite not run. | Feature / Support | 11 |
| [`13ca167`](https://github.com/hexcrete/DockFork/commit/13ca167b2e81ea88ee53ef84df55d813b4c4a563) | Publication records: document unified full-size windowless presentation, verification, and capture candidates; extend ledger coverage. | Documentation | 3 |
| [`afa75e4`](https://github.com/hexcrete/DockFork/commit/afa75e4858f292490cb52fe1c600941776d6211a) | Traffic lights: dim buttons before pill creation; retain whole-control hiding, hit-testing, and stable layout. Forty focused visibility/dimming checks and signed Debug build/relaunch passed; committed with user approval, manual visual verification not separately reported. | Fix | 1 |
| [`cf7cd4b`](https://github.com/hexcrete/DockFork/commit/cf7cd4b02691d453b174341ec1826812c860268a) | Publication records: document button-only dimming, its verified build/checks and visual-testing boundary; extend ledger coverage. | Documentation | 3 |
| [`07c6793`](https://github.com/hexcrete/DockFork/commit/07c6793bff02b68dcfe0298d32a9068396d00b1b) | Shared pill borders: restore upstream primary-color 10% outline at 1.5 points for search, titles, state/Space indicators, and traffic lights; retain blur/highlighting and remove need for search-specific styling. Source checks, signed Debug build/relaunch, and user visual verification passed; full Xcode test suite not run. | Fix | 1 |
| [`43c9a0a`](https://github.com/hexcrete/DockFork/commit/43c9a0a58e528de33bcf5a5a6759b996acbaeb00) | Publication records: document unified control/search pill borders, user verification, and capture candidates; extend ledger coverage. | Documentation | 3 |
| [`ae79432`](https://github.com/hexcrete/DockFork/commit/ae79432976966d22046c845b1cdce19593503ae7) | Traffic-light motion: app and macOS Reduce Motion override both dimming and visibility transitions through a shared pure policy; keep zero-duration opt-out and existing defaults. Twenty-five focused policy checks, six visibility-gate checks, signed Debug build/relaunch, and user manual verification passed; full Xcode test suite not run. | Fix | 7 |
| [`efc6e8e`](https://github.com/hexcrete/DockFork/commit/efc6e8ebd90e1973df185521ee32021c5203fe06) | Publication records: document Reduce Motion precedence, verification, and showcase regression setup; extend ledger coverage. | Documentation | 3 |

| [`b674d9c`](https://github.com/hexcrete/DockFork/commit/b674d9c7c1d404650cf31336f6d6fcc1d84c0fdf) | Packaging: record separate fork version and incorporated upstream release/base, validate ancestry and tags, embed Support label and build metadata. Nineteen isolated cases, source preparation/override, signed Debug build/relaunch, and user verification passed; committed-source release preparation also passed. No runtime background work. | Feature / Packaging | 5 |

| [`025365b`](https://github.com/hexcrete/DockFork/commit/025365b9a64fa11161dffae5bdd9fa1e30a214cc) | Publication records: document separate fork/upstream versions, maintenance and contribution boundaries, verified preparation/build/manual checks, and remaining release-validation gaps. | Documentation | 8 |

| [`dc5a805`](https://github.com/hexcrete/DockFork/commit/dc5a805c2892a111d73cd8ae41ac9efeb1dcc074) | Dock cycling: defer cycling until click release; restore the original press downstream for native icon dragging. Gate drag/up subscriptions, bound press tracking, and retain weak callback context through event-thread teardown. Seven focused checks, signed Debug build/relaunch, build-source comparison, and user manual verification passed; full Xcode suite not run. | Fix | 1 |

| [`cca35b9`](https://github.com/hexcrete/DockFork/commit/cca35b9ea38f8277ce7fcbf491c47a1253ded77d) | Publication records: document Dock icon drag preservation, exact source/build comparison, manual verification, and gated event-tap lifecycle; extend the ledger through the fix. | Documentation | 4 |

| [`b7faf95`](https://github.com/hexcrete/DockFork/commit/b7faf95ec27bc918cd3553835d02f7166c552fe0) | Dock cycling: default-off same-Space preview retention; share transition validation with restore actions and retain normal Space dismissal. Refresh only changed active borders, reject background-app focus updates, and replace stale hover click gating with actual coordinates. 621 focused checks, signed Debug build/relaunch, exact source comparison, and user manual verification passed; full Xcode suite not run. | Feature / Fix | 11 |
| [`82f0a06`](https://github.com/hexcrete/DockFork/commit/82f0a06600861d1a8fa9cf9fd024e1d61a273952) | Publication: record same-Space Dock cycling behavior, manual/targeted validation, resource-lifecycle boundaries, capture candidate, and ledger coverage. | Documentation | 4 |
| [`1f72ecb`](https://github.com/hexcrete/DockFork/commit/1f72ecbac21ec714c641a5e89cae2fc59c7be8d7) | Settings wording: name the highlighted window rather than the last window in persistent swipe selection; match the search title. Preference key, default, and runtime behavior unchanged. Signed Debug build/relaunch and local Release validation passed; manual UI test not recorded. | UI | 2 |
| [`3d1e761`](https://github.com/hexcrete/DockFork/commit/3d1e7614ca030a4d00bd5f1a985722214e756e57) | Showcase preset: refresh 237 recognized preferences from the supplied export; remove four private/system entries and export timestamp, verify nested shortcut records and generic IDs, and keep debug logging off. Optional asset only, no import or app-default change. | Preset | 1 |
| [`eeef787`](https://github.com/hexcrete/DockFork/commit/eeef787b123aa1a628f16d6b365e8ae54049ca99) | Publication records: document preset privacy, label clarification, Release candidate checks and unperformed installation tests; simplify intermediate build notes and extend ledger coverage through the preset commit. | Documentation | 4 |
| [`e2667b3`](https://github.com/hexcrete/DockFork/commit/e2667b30c98aeb7ee57df9eefb6123ad2c5777b0) | Preview layout: center shared regular-card images independently of padded toolbar width, including missing-image and full-size windowless cards; retain toolbar alignment and sizing. Reduced native-renderer checks and signed Debug build/relaunch passed; full Xcode suite and mode-by-mode manual verification not recorded. | Fix | 1 |
| [`b7ea008`](https://github.com/hexcrete/DockFork/commit/b7ea0087b31b19922042ed7e41cabeaa9ea6b51f) | Publication records: explain the fork-specific fixed-toolbar-width interaction behind preview misalignment, record structural validation and manual-testing gaps, extend ledger coverage through the fix, and update the existing capture candidate. | Documentation | 3 |
| [`295ef75`](https://github.com/hexcrete/DockFork/commit/295ef75e137db923df11b2d48df51cae70cedb3b) | Scroll geometry: commit clamped content-size offsets to the AppKit view origin so pointer hit targets follow visible cards after removal/filtering. Shared both-axis fix for an inherited upstream omission, with regression tests. Native harness, signed Debug build/relaunch, source correspondence, and user manual verification passed; full Xcode suite not run. | Fix | 2 |
| [`fdc4cf0`](https://github.com/hexcrete/DockFork/commit/fdc4cf036c910c102526c8b1fc8fea288fd89ce5) | Publication records: document inherited scroll geometry omission, shared both-axis correction, regression/manual validation, resource boundaries, and capture setup; extend ledger coverage through the fix. | Documentation | 4 |
| [`9fcf28d`](https://github.com/hexcrete/DockFork/commit/9fcf28dbb82334e40ff7141d2b16e3661f9755b2) | Showcase preset: privacy-review the supplied 241-key export, omit four private/system entries and timestamp, retain 237 settings and generic shortcut IDs with logging off; change only app-header style to Popover and switcher icon size to Automatic. Optional asset, no import or app-default change. | Preset | 1 |
| [`0f67711`](https://github.com/hexcrete/DockFork/commit/0f677114abffc2360b1a38eae824b4865cb2ddc9) | Publication records: describe the sanitized two-setting preset refresh and committed-source Release candidate, nine checksums, signatures, archive/preset correspondence and testing gaps; extend ledger coverage through the preset commit. | Documentation | 4 |
| [`8ede8d0`](https://github.com/ejbills/DockDoor/commit/8ede8d0a9fa74fffe87c09657503872c7ad2be22) | Upstream: cache newly focused native-tab identities, retain AX geometry, and avoid background-app focus events canceling active-app MRU updates. Existing fork grouping and discovery safeguards preserved. | Upstream fix | 2 |
| [`7358716`](https://github.com/ejbills/DockDoor/commit/7358716142ca37adb8149bb0d4c2ae1dd838e4f5) | Upstream: use the resting Dock edge for active-app indicator placement while an icon bounces. | Upstream fix | 1 |
| [`4f5aeb9`](https://github.com/ejbills/DockDoor/commit/4f5aeb91f89db34bb74fa9295871196c8f0115c1) | Upstream: add DockDoor 1.40.8b1 beta appcast metadata. Does not enable upstream updates in DockFork. | Upstream metadata | 1 |
| [`7be384b`](https://github.com/ejbills/DockDoor/commit/7be384b46da66f380bf3a9bb24ee6c6476bbd0dc) | Upstream: add DockDoor 1.40.8b2 beta appcast metadata. The latest incorporated stable release remains 1.40.7. | Upstream metadata | 1 |
| [`325ef3f`](https://github.com/hexcrete/DockFork/commit/325ef3fbd5af4e863cf96a458ec6f91b1af569ce) | Integration: conflict-free merge of upstream 7be384b, preserving local focus/tab behavior; record exact upstream base and stable release separately. Pre-commit signed Debug build/relaunch, metadata/scroll checks, and user manual verification passed; full Xcode suite not run. Changed-file count is against the first parent. | Merge | 5 |

| [`1515921`](https://github.com/hexcrete/DockFork/commit/1515921b956aa6c1dfdb36d9b78f2d3813023b02) | Publication records: document upstream integration, post-commit signed Debug build and exact-path launch, metadata and isolated tests, and unchanged Release validation gaps. | Documentation | 4 |

| [`1b73971`](https://github.com/hexcrete/DockFork/commit/1b7397125b1d89e72ef694014127ab5f12d910e9) | Space navigation: reject unrelated/ineligible cached windows before AX reads, bypass presentation sorting, check remaining candidates off-main, and revalidate latest request/membership before activation. Signed Debug build and user manual verification passed; no measured performance claim. | Safety / Spaces | 1 |
| [`221265f`](https://github.com/hexcrete/DockFork/commit/221265f55cd0243a8517cd2cd63bc7ed9747545d) | Numeric safety: centralize resize-delay conversion, bound stored/imported delays and log limits before integer arithmetic, and add extreme/fractional/non-finite regression cases. Defaults, live preferences and import format unchanged. | Safety / Diagnostics | 5 |

| [`0cabb33`](https://github.com/hexcrete/DockFork/commit/0cabb33081550df578d6ca39569d3a65ae6d0bb8) | Publication records: update upstream-base wording, record approved safety repairs and manual verification, extend ledger through the two fixes, and retain testing/capture boundaries. Source for the October 12 committed Release candidate. | Documentation | 5 |

| [`c8d51ff`](https://github.com/hexcrete/DockFork/commit/c8d51fffc632e5af0ff3b48ff43742e314146a64) | Release records: document the verified October 12 committed candidate, source/asset/signature/checksum correspondence and unchanged installation/publication gaps; extend ledger through its source commit. | Documentation | 4 |

| [`077d584`](https://github.com/hexcrete/DockFork/commit/077d5845d5ada6ce7c3b09f0b70fd192b63bbf7d) | Publication records: prepare the public testing fork, distinguish upstream examples from pending fork media, and record repository/default-branch setup without publishing a Release. | Documentation | 6 |

| [`4fdaa56`](https://github.com/hexcrete/DockFork/commit/4fdaa5626dbc10a70c83df88a2b3cb444c851c43) | Settings dialogs: defer Import/Export file-panel creation until the SwiftUI button callback returns and prevent overlapping backup operations; preserve confirmation and preview-suspension cleanup. Signed Debug build/relaunch, extracted gate checks, and user verification passed. | Fix | 1 |

| [`36e635e`](https://github.com/hexcrete/DockFork/commit/36e635e8f0ad35cdd90fb390b3aa0195cefdd8b2) | Publication records: document the reviewed settings file-dialog fix, user verification, unchanged Release artifact, and ledger coverage through the fix. Source for the rebuilt October 12 candidate. | Documentation | 5 |

| [`969ad32`](https://github.com/hexcrete/DockFork/commit/969ad327c727ff410dedc7281201da097e1f3ba7) | Release preparation: record rebuilt candidate checks, privacy review, macOS 27 testing by local transfer, and explicit Gatekeeper/testing gaps; extend ledger through the candidate source. No app or asset changes. | Documentation | 4 |

| [`49cd13d`](https://github.com/hexcrete/DockFork/commit/49cd13db37499fcb3187e0da6d2cff8e5035a39a) | Release records: document tagged source, ten verified draft assets, unchanged app/settings, and paused publication; extend ledger through release preparation. | Documentation | 4 |

| [`d783512`](https://github.com/hexcrete/DockFork/commit/d78351215a1532b6f66cf043beb6cdb75e8895de) | Publication records: record the published 0.1.0 prerelease URL, verified assets, unchanged tested source, and pending downloaded-installation validation. | Documentation | 6 |
| [`fa76e57`](https://github.com/hexcrete/DockFork/commit/fa76e579c1a6b464b336a3eb115d8686e972bdbf) | Ordered preview selection: shared checkbox controls, optional header-style summary, session lifecycle, keyboard selection and cache-only cleanup. User manual verification passed; final cleanup review build passed. | Feature | 23 |
| [`a4150a5`](https://github.com/hexcrete/DockFork/commit/a4150a58b915660eda70fade1a87ecd5cd3edfac) | Keyboard completion respects selection release suppression; separate one-line source guard with publication-record updates. | Fix | 3 |

| [`c827932`](https://github.com/hexcrete/DockFork/commit/c82793295f6a56d6f1650d68a9f250b599b55b64) | Ordered checked-group window actions and confirmed Space moves; shared mixed-state policy, exit-only group fullscreen, failure reporting and cancellation cleanup. User manual verification passed. | Feature | 17 |

| [`313e213`](https://github.com/hexcrete/DockFork/commit/313e21331c5f9ca219369a6fb4b2a5b6f5b99393) | Stable checked-group dragging, ordered bounded icon ghost, confirmed relative placement and whole-group Aero Shake protection through reconciliation. User manual verification passed. | Feature | 9 |

| [`6ae187c`](https://github.com/hexcrete/DockFork/commit/6ae187c438167dcc4320627cceec43ff8cc91f53) | Configurable automatic/directional ordered-group tiling, repeated overflow layouts, single-window Auto Tile, foreground raising, shared placement worker and native tiling/selection scripting. User manual verification and final source review passed. | Feature | 18 |

| [`d5bdb48`](https://github.com/hexcrete/DockFork/commit/d5bdb48d588a2b3cdd0714dc33f9091d8fbc7924) | Existing AppleScript window actions accept ordered ID lists using shared batch/tiling/confirmed-move operations; preserve text-ID paths and event codes. Shared bounded reply handler, input/result tests and authorized live verification with exact window restoration. | Feature | 8 |

| [`7a6ec7d`](https://github.com/hexcrete/DockFork/commit/7a6ec7d53095a2c683672523f54224a2e410d041) | Optional drop-to-tile using stable target-first ordering, confirmed placement, shared file/preview highlighting and cancellation-safe grid targeting. Manual verification and focused regression checks passed. | Feature | 18 |

| [`ed767aa`](https://github.com/hexcrete/DockFork/commit/ed767aaf0ff8671e4fc2fccb775b5ad0f646b175) | Compact preview/file drag highlights match horizontal row bounds and remain undimmed while preserving existing row dimming. User verification passed. Spaces Bar deferred to a later release. | Fix | 6 |

| [`4ef5a08`](https://github.com/hexcrete/DockFork/commit/4ef5a084541c6228db03f5021a7bd7e4a4de5b0a) | Select All button and assignable action share filtered real-window selection, preserving existing order and outside-view checks. No-highlight shortcut routing, settings helper/search coverage and idempotence tests. User verification passed. | Feature | 13 |

| [`4a76bfd`](https://github.com/hexcrete/DockFork/commit/4a76bfd4ed075af98dc29def5ca8017834bcbdb1) | Default-Off selection keep-open option gates pinning, release suppression and retention while preserving session ownership when disabled. Search/helper coverage and user verification in held-modifier/swipe modes. | Feature | 12 |

| [`5f0435a`](https://github.com/hexcrete/DockFork/commit/5f0435a3fab872ea59b2f43fcce5ea97350e4892) | Extend traffic-light transition duration to 0.5 seconds through one shared settings/runtime maximum; preserve defaults and Reduce Motion. Updated cap regression checks, build and relaunch passed. | Feature | 6 |

| [`be91733`](https://github.com/hexcrete/DockFork/commit/be91733dd70de93998a39fa6ff82a7c1bc6fe904) | Acknowledge the one-time Cmd+Tab focus hint through visible mouse/keyboard preview focus instead of only the cycle shortcut; exclude mock/invalid/other-mode focus. User verification and source review passed. | Fix | 5 |

| [`f4259c0`](https://github.com/hexcrete/DockFork/commit/f4259c0bb1d3658254b50baa1ba6149b6e0699ed) | Hide shared Dock/Cmd+Tab Close All and Minimize All buttons for windowless/terminated rows; reuse eligibility in execution guard, retaining real hidden/minimized/fullscreen window handling. User verification passed. | Fix | 4 |

| [`d21b0a4`](https://github.com/hexcrete/DockFork/commit/d21b0a401de6912f93e93e531020f16a75245883) | Embedded switcher app/window titles reuse shared two-layer App Header shadows with light/dark contrast inversion; preserve other header rendering and geometry. Native rendering checks and user approval passed. | Fix | 8 |

| [`d0740c3`](https://github.com/hexcrete/DockFork/commit/d0740c3b9b747d7d8800ab191dd09b741384a8bb) | Native search-field clear button with shared query delivery, AppKit editor bounds and safe panel reuse; native hit-target/reuse checks and user verification passed. | Feature | 5 |

| [`2f9d492`](https://github.com/hexcrete/DockFork/commit/2f9d49239061cc1b2c29a724a891c91a82c3b53f) | Limit cycling to active visible multi-window apps; native inactive/single/windowless clicks dismiss Dock previews and cancel stale discovery. Click-time Minimize/Hide eligibility replaces hover snapshots while preserving restore exceptions and icon dragging. Policy tests and user verification passed. | Fix | 6 |

| [`a308aed`](https://github.com/hexcrete/DockFork/commit/a308aedb8e993dd7ef20f75114f5664f3b47adbe) | Share measured-time AX observer backoff and preserve explicitly identified window focus through cache insertion; remove canceled delayed focus queries and inferred app fallback. Bounded timestamp lifecycle, 64 isolated tests, signed Debug build, fresh-launch checks and user verification passed. | Fix | 8 |

| [`4ff8ddd`](https://github.com/hexcrete/DockFork/commit/4ff8ddda88767838978cd3b2bdbc891213e328a1) | Shadowed app headers and selection summaries share visual overflow and native keep-open bounds. Move the existing tracker to the outer container and use its rectangle for inactivity checks; preserve timers, clicks, styles and mock/drag exclusions. 66 combined tests and user verification passed. | Fix | 7 |

| [`272f6e4`](https://github.com/hexcrete/DockFork/commit/272f6e4078b3b3171512bf9d6a55e50cf61e45c1) | Outside-click dismissal shares the native hover-tracker bounds, protecting protruding Shadowed header/summary controls. Weak, attached-view ownership; ignore empty/foreign views and skip unchanged geometry. Widget fallback, real outside clicks, search and menu exemptions preserved. Seventeen native/snapshot cases, signed Debug build/relaunch and user verification passed; full Xcode/all-style testing not claimed. | Fix | 7 |

| [`dc77296`](https://github.com/hexcrete/DockFork/commit/dc77296d9b0da762620323d348519895cad7d5a7) | App Header Close All/Minimize All resolve all cached real windows of their app, ignoring checked selection; route directly through the shared cancellable batch path. Per-window selection scope, fullscreen minimization exclusion and mock guards remain intact. Fake-adapter/native regression checks, signed Debug build and user reports passed. | Fix | 2 |

| [`d89cbc5`](https://github.com/hexcrete/DockFork/commit/d89cbc547a2ce4ca5999d2974545a46c22f7adf6) | Adaptive selection summaries share Tile Windows and ordered glyph/scroll fallbacks across Dock, Cmd+Tab and Window Switcher. One icon per checked window, width-based +N, shared Space-menu attachment formatting and native accessibility; cached per-app lookup, no polling. Matching settings/search help; 510 native layouts, 401 icon widths, duplicate/order/overflow checks, signed Debug build and user reports passed. | Feature | 5 |

| [`ec1e9fa`](https://github.com/hexcrete/DockFork/commit/ec1e9fa2fd1676bad00ae519a175b2f4a6ab0943) | Enable the selection summary by default and set maximum tiling columns to 3; rows remain 2. Existing preference names and saved values are preserved. Selection and selection-driven keep-open remain default Off. Fork defaults require separate upstream compatibility review. | Defaults | 1 |

| [`dd28db3`](https://github.com/hexcrete/DockFork/commit/dd28db3f3c016b9afeee616088a612f06eefbec8) | Align five pre-existing dismissal-padding lines with the repository SwiftFormat rules. Whitespace-only; no functional change. All six touched Swift files pass formatter lint. | Maintenance | 1 |

| [`59c40ba`](https://github.com/hexcrete/DockFork/commit/59c40ba9698e9cb13fdeb19606987e37dcfe0001) | Prepare 0.2.0 prerelease version metadata, draft notes, README/installation guidance, showcase priorities and contribution/resource records. Account for prior application commits through dd28db3; no Release package, tag, upload or publication. | Documentation / Build | 11 |

| [`e95d706`](https://github.com/hexcrete/DockFork/commit/e95d70641ef548c3da951db5bde65cc4a7ec650f) | Add native title/glyph/scroll fallbacks for Dock/Cmd+Tab App Header actions and reuse button/scroll rendering with selection summaries. Preserve app-wide routing and hover behavior. | Feature / UI | 6 |

| [`bbb5478`](https://github.com/hexcrete/DockFork/commit/bbb54789c8e3fd28d4c32a88c7b9eadad1834a03) | Center Popover selection summaries and stabilize app-header centering when hover actions change width; preserve Default/Shadowed layout. | Fix / UI | 4 |

| [`c119eb9`](https://github.com/hexcrete/DockFork/commit/c119eb9994f853ccfcca1cce21328ae7c11fa7f9) | Honor configured app-header title overflow and fall back to icon-only at narrow widths, preserving hover/action behavior and adding full-name icon help. | Fix / UI | 6 |

| [`68d8391`](https://github.com/hexcrete/DockFork/commit/68d83912aac1a60e2ec50befe24bb2f024913d9f) | Key pending AX cache validation by application PID so multi-app close/focus bursts cannot cancel another app's stale-window cleanup. Preserve same-app coalescing, token cleanup and weak lifetime. | Fix / Reliability | 6 |

| [`223ea2a`](https://github.com/hexcrete/DockFork/commit/223ea2a695e5f20c7aae7a0454d464d325438de4) | Reuse the Shadowed header mouse-safe inset as its top screen boundary across initial placement and anchored resizing, without changing other styles or widget placement. | Fix / UI | 7 |

| [`48b7f64`](https://github.com/hexcrete/DockFork/commit/48b7f64e7d8b46059370707c1af51e34fb39bc30) | Fit narrow preview toolbars through title omission and native More menus across modes; share action/Space builders, stable reveal animation and spacing while retaining selection access and icon size. | Feature / UI | 9 |

| [`e264839`](https://github.com/hexcrete/DockFork/commit/e26483931ae811679102a8d47a125b97960f66c1) | Reuse the overflow Space/state information section in preview and menu-bar action menus, placing Move to Space before Arrange while retaining action handlers, hint policy and lazy menu construction. | Feature / UI | 6 |

| [`ce9ef95`](https://github.com/hexcrete/DockFork/commit/ce9ef9530c313318e9fddb8fcfd37f39f909d2e1) | Expose checked multi-selection through native accessibility traits on shared checkboxes and combined More controls, with an explicit More label. Dock VoiceOver verified by the user; search-field navigation blocked Window Switcher validation. | Accessibility / UI | 6 |

| [`4d6c4c2`](https://github.com/hexcrete/DockFork/commit/4d6c4c2eb29a239584ab1da7c0057f5ee84a7528) | Progressively retain leftmost traffic-light actions and overflow rightmost actions into More using shared scaled/styled geometry, native width fitting and exact action partitioning. | Feature / UI | 8 |

| [`c15292f`](https://github.com/hexcrete/DockFork/commit/c15292feaf7105c711a8e9e767e11ffe9da60f1a) | Confirm actual tiled frames, complete old-position-constrained resizing, preserve partial-write refresh, restore scoped accessibility state and use AXMain. Avoid macOS 27 focus-triggered expansion with a far off-content mouse-down only. Signed Debug, source/model checks and authorized scripted group/Space tests passed within the documented limits. | Fix / Reliability | 7 |

| [`5819ee4`](https://github.com/hexcrete/DockFork/commit/5819ee492adfc194c406da104e367136817ea4f4) | Apply four formatter-only corrections to Dock click guards and preview-selection declarations. Non-whitespace source content is unchanged; changed-source lint and the signed Debug rebuild/relaunch passed. | Maintenance | 2 |

| [`766b77e`](https://github.com/hexcrete/DockFork/commit/766b77e55cfa6a7f5b70f894bd53f4b98e3973c2) | Refresh 0.2.0 release preparation, preserve historical candidate records, clarify the pending configuration/build gate and document the reviewed tiling/activation work. No Release package or publication. | Documentation | 10 |

| [`993182b`](https://github.com/ejbills/DockDoor/commit/993182bb60fbd08383f5743b9966c5cfb2d4af17) | Add trackpad switcher swipe sensitivity with settings and detector tests. | Upstream feature | 6 |
| [`4e7d18d`](https://github.com/ejbills/DockDoor/commit/4e7d18df12a9dc52658c7e697dee72c82341a975) | Introduce optional title-bar, Dock and menu-bar trackpad window gestures and their recognition/resolution tests. | Upstream feature | 28 |
| [`2541cf9`](https://github.com/ejbills/DockDoor/commit/2541cf9c4d5691dadad49c58b7d268eae4b4d2d2) | Refine window gestures, add custom-dock screen reservations and scripting, and split Gestures from Keybinds. | Upstream feature / Settings | 33 |
| [`d24faab`](https://github.com/ejbills/DockDoor/commit/d24faab5a0857dd1fbb6a863b153460dc70caa95) | Reuse shared window operations, snapping, gesture-zone and observer infrastructure. | Upstream refactor | 25 |
| [`306aa35`](https://github.com/ejbills/DockDoor/commit/306aa350c4fd9f70cdd8a24f8aa97e9cdb835a80) | Require the pointer to remain within the expected Dock icon before delayed previews are presented. | Upstream fix | 2 |
| [`0d43f6b`](https://github.com/ejbills/DockDoor/commit/0d43f6b6d49c3cb08e56d448e15f9a0329bcc448) | Add the window-gesture section and demonstration media to the upstream website. | Upstream website | 3 |
| [`4a41290`](https://github.com/ejbills/DockDoor/commit/4a412904fcfc16b2bf0c04a150402fe8dc21c84d) | Emphasize that window gestures are opt-in. | Upstream website | 1 |
| [`3d6a3cb`](https://github.com/ejbills/DockDoor/commit/3d6a3cbaa9bbee17959122da7f0a349ca43056d0) | Synchronize macOS translations from Crowdin; tagged source of stable DockDoor 1.41.0. | Upstream localization | 1 |
| [`985d3f7`](https://github.com/ejbills/DockDoor/commit/985d3f70d909cad73708a69ad83fd28135eb25c4) | Update the upstream appcast for 1.41.0; DockFork continues using manual fork updates. | Upstream metadata | 1 |
| [`3e08721`](https://github.com/ejbills/DockDoor/commit/3e08721ec56c6747dba04561ab57b03ec254d785) | Record the 1.41.0 upstream changelog. | Upstream documentation | 1 |
| [`229d38a`](https://github.com/hexcrete/DockFork/commit/229d38a2d4c4f6e96e3ed6c9581922277f599894) | Integrate upstream 1.41.0 through 3e08721, retain confirmed placement/activation and selection/session ownership, adapt gesture snapping and settings search, and pin the upstream version record. Changed-file count is against the first parent. Validation details are in the integration record. | Merge | 52 |

| [`a004a6f`](https://github.com/hexcrete/DockFork/commit/a004a6fe55cde8654426cc2b92fdef07152b86ad) | fix: reuse confirmed minimization for window gestures. Validation and scope are recorded in the related guide entry. | Fix / Integration | 7 |

| [`9d2eeea`](https://github.com/hexcrete/DockFork/commit/9d2eeeaedd8212eedfacb8adc314013cfd66c09b) | fix: confirm gesture restoration and serialize window actions. Validation and scope are recorded in the related guide entry. | Fix / Integration | 6 |

| [`43ba166`](https://github.com/hexcrete/DockFork/commit/43ba1666f73976f0773ce9cb1b0af06bdda05c04) | fix: constrain linked resizing to valid neighboring windows. Validation and scope are recorded in the related guide entry. | Fix / Integration | 10 |

| [`58107a1`](https://github.com/hexcrete/DockFork/commit/58107a148fd6c7c9892aaa70bf8158bccd9b2c77) | fix: bound snap registry lifetime and release stale records. Validation and scope are recorded in the related guide entry. | Fix / Integration | 8 |

| [`5d74df1`](https://github.com/hexcrete/DockFork/commit/5d74df19d1bed46a52b19e113db753b612832ece) | feat: link windows arranged in confirmed tiling batches. Validation and scope are recorded in the related guide entry. | Feature / Tiling | 20 |

| [`ce9b672`](https://github.com/hexcrete/DockFork/commit/ce9b6725185bd365eff7846cb90a6b6439606017) | docs: record linked tiling implementation and validation. Validation and scope are recorded in the related guide entry. | Documentation | 3 |

| [`dc077d1`](https://github.com/hexcrete/DockFork/commit/dc077d15294ef2f6a852f853dbfca38836959c64) | fix: preserve snap notifications across record replacement. Validation and scope are recorded in the related guide entry. | Fix / Integration | 6 |

| [`c73e11b`](https://github.com/hexcrete/DockFork/commit/c73e11b862710784170efc1f42b82a393775457f) | perf: skip unused tiling restore-frame bookkeeping. Validation and scope are recorded in the related guide entry. | Support / Performance | 6 |

| [`8dac615`](https://github.com/hexcrete/DockFork/commit/8dac615f9c6178d171f5d993aa927ed38b930614) | fix: preserve native resize intent across queued notifications. Capture native pointer state before asynchronous processing and preserve coalesced resize intent. | Fix / Gestures | 3 |
| [`a23c0d6`](https://github.com/hexcrete/DockFork/commit/a23c0d65dba367670fbedd3531e86ba2bfef6c6d) | fix: foreground size-constrained tiled windows. Distinguish accepted constrained geometry from failed writes; foreground accepted windows without false confirmation or linked enrollment. | Fix / Tiling | 4 |
| [`86c3306`](https://github.com/hexcrete/DockFork/commit/86c33061b7267fcb41d05117d8afa93c7aa4e7b3) | fix: let released preview drops finish after dismissal. Coordinator-owned latest-wins drops survive preview teardown; remove duplicate single-window placement and verify cancellation/cleanup. | Fix / Dragging | 4 |

| [`585eb56`](https://github.com/hexcrete/DockFork/commit/585eb560a24a4e358c2fbdbd38cf02d57043eb27) | docs: record tiling and drag reliability fixes. Records the three focused fixes, verification evidence and remaining native coverage gaps. | Documentation | 6 |

| [`3b4d311`](https://github.com/hexcrete/DockFork/commit/3b4d3112ae01f2b652b21cdc52ff3aaff2be50e6) | feat: configure Auto Tile overflow and grouped Fill actions. Stack overflow in existing cells or leave excess targets untouched; make direction-aware group Fill opt-in, preserve off-Space Fill behavior, split settings and cover the shared routing. | Feature / Tiling | 10 |

| [`ddb9f8c`](https://github.com/hexcrete/DockFork/commit/ddb9f8c07eb6ae7c26fd4bdb33e42ca5d2668273) | docs: record configurable tiling policies and validation. Update release notes, showcase, current settings paths and exact ledger coverage for configurable tiling. | Documentation | 7 |

| [`c27ac27`](https://github.com/hexcrete/DockFork/commit/c27ac279cd61f36d5ef8c792e4d778a48f283ad5) | docs: refresh tiling release records and settings audit. Align current paths, defaults, overflow semantics and validation records; add the source-only settings-wiring check. | Documentation | 9 |

| [`18dbc35`](https://github.com/hexcrete/DockFork/commit/18dbc35b08518a03d2d9d1aeb64f9c9cbc567385) | polish: shorten selection and tiling settings explainers. Apply user-edited fork helper text with matching search descriptions; retain the unchanged upstream appendix and record copy validation. | UI / Copy | 7 |

| [`f83613b`](https://github.com/hexcrete/DockFork/commit/f83613bc6c2249c89df41ea7624c52c5c4775f18) | docs: prepare 0.2.0 release records and sanitized showcase preset. Review 245 preferences and 14 shortcut rows, add repeatable privacy checks and update source/test/publication boundaries. | Documentation / Preset | 11 |

| [`e735dc3`](https://github.com/hexcrete/DockFork/commit/e735dc38fea897154b6fa55930b08258cfa9cd65) | feat: support selection of windowless switcher apps. Default-On suboption, Quit/New-only batch eligibility, real-only operation counts, one-shot placeholder checks and confirmed-termination cleanup; source regressions and eleven-setting audit. | Feature / Selection | 15 |

| [`a8f1a1d`](https://github.com/hexcrete/DockFork/commit/a8f1a1d6637ca48416a458134114c3750aa5ecfe) | Record windowless selection behavior, validation and release boundaries. | Documentation | 7 |

| [`1e55224`](https://github.com/hexcrete/DockFork/commit/1e55224e56e1d6690f34b802db72a14eb5de3582) | Explain move/resize/tiling foregrounding and the unconditional drag exception in settings and search; retain behavior/defaults. Signed Debug build and relaunch passed. | UI / Copy | 4 |

| [`d17f1b5`](https://github.com/hexcrete/DockFork/commit/d17f1b55354dafc3b3d96c66c43f2cf4daf27792) | Route scalar script actions through the shared asynchronous executor, preserve scalar fullscreen toggling and exit-only lists, centralize batch foregrounding and remove legacy helpers. Native Notes/Brave tests and focused regressions passed. | Fix / Scripting | 11 |

| [`383d117`](https://github.com/hexcrete/DockFork/commit/383d1174e3f22ffd6b4a1473bd0acdbb05584eb6) | Prepare 0.2.0 candidate: remove the temporary copy worksheet, refresh the privacy-reviewed optional preset to 246 settings/15 shortcut rows, and align release records. Focused regressions and documentation checks passed. | Documentation / Preset | 8 |

| [`56192c3`](https://github.com/hexcrete/DockFork/commit/56192c32fc239a1a482ea46e96d16d571b962910) | Add Release-only coverage exclusion after the binary privacy scan rejected profiling paths. Xcode rejected the test-only command-line flag before compilation; the following packaging correction retains the build-setting override only. No distribution artifact was produced by this revision. | Build | 5 |

| [`28ed59b`](https://github.com/hexcrete/DockFork/commit/28ed59b1f2329f6f9d546c5e88d15ec2c920fb1c) | Remove Xcode's test-only coverage flag from ordinary packaging. The resulting candidate still contained instrumentation because the provisional override was not the controlling setting; the next correction uses the installed SDK specification. Candidate rejected, not distributed. | Build | 3 |

| [`1c27717`](https://github.com/hexcrete/DockFork/commit/1c277173e85e14fd6c0e4fae3ea90eafd7f137bf) | Use Xcode's actual ENABLE_CODE_COVERAGE setting. Replacement binaries contain no profiling counters or profile-output markers; the audit still found debug-map build paths in the main executable, so distribution awaits the final stripping safeguard. | Build | 3 |

| [`c863e62`](https://github.com/hexcrete/DockFork/commit/c863e628d17d8c80985cd77533ff94db03d6444a) | Strip private debug-map paths from Release Mach-O files before signing; preserve instructions/exports and Debug mode. Source of the final audited 0.2.0 candidate, with 19 passing package checks and no launch/import/upload. | Build / Privacy | 5 |

| [`54d2615`](https://github.com/hexcrete/DockFork/commit/54d261517bded38a12da9f3d442ef0b8b4617492) | Record the final audited 0.2.0 candidate, exact checksums, source/preset and privacy evidence, rejected iterations and remaining runtime/installation gaps; leave publication paused at that stage. | Documentation | 7 |

| [`e751f05`](https://github.com/hexcrete/DockFork/commit/e751f05eb720f353d20365d9e7c8b14338db8921) | Prepare user-authorized 0.2.0 publication, persist the public-facing notes and upgrade-permission warning, verify unchanged upstream/candidate, and record the prior audit-documentation commit. No application rebuild or source change. | Documentation / Publication | 4 |

| [`ef373d4`](https://github.com/hexcrete/DockFork/commit/ef373d43602c236b417546a0f757bc0f7758ba5b) | Record verified 0.2.0 prerelease publication, exact candidate/tag correspondence, ten downloaded-back assets, public download checks and remaining installation/media gaps. | Documentation / Publication | 8 |
| [`29de103a`](https://github.com/hexcrete/DockFork/commit/29de103a7e2beeca09b508c99fc9a54a5cc22ed4) | Close collapsed native tab groups through stable group ownership and refreshed controls; preserve the original tab until last, stop on read failures or refused background Close, and add regression/routing tests plus validation records. | Fix / Discovery / Native Tabs | 7 |

| [`c41e00e`](https://github.com/hexcrete/DockFork/commit/c41e00e0183bdaadb71d43083139569ad23f4c91) | Record native-tab Close behavior, verification and pending cross-app/media coverage; extend the ledger through the preceding code fix. | Documentation | 3 |

| [`70d56b90`](https://github.com/hexcrete/DockFork/commit/70d56b90afff830191ff0cb1cf6350d858dc5530) | Add default-Off shared action feedback with cursor/per-preview progress, fade-only presentation, stable symbol/spinner geometry, crossfade consolidation and cleanup; reuse confirmed operation outcomes and asynchronous native-tab Close, preserving silent scripts and ordinary activation. Include state-machine, native-panel, minimize, close and tiling regressions. | Feature / Actions / Feedback | 21 |

| [`d7832ceb`](https://github.com/hexcrete/DockFork/commit/d7832ceb886ad855a0499d4ceb63a783e3cf015a) | Record shared action-feedback behavior, user verification, automated/native checks, lifecycle and contribution limits, showcase candidates and deferred Quit/responsiveness work; extend exact ledger coverage through the feature commit. | Documentation | 6 |

| [`4ad22fc1`](https://github.com/hexcrete/DockFork/commit/4ad22fc151b0c168753faf2fe4b43255ea918904) | Add default-Off Mouse Follows Focus cursor feedback using the shared presenter, capitalized label, requested pointer symbol and ordinary result timing. Preserve warp/display policy, show only after successful changed-position warps, index/reset the preference and cover disabled/error/no-op/display behavior plus native presentation. | Feature / Actions / Cursor Feedback | 7 |

| [`d8d1a61d`](https://github.com/hexcrete/DockFork/commit/d8d1a61d5de9f70d2152db27f1f331cc0e6fcfc6) | Record Mouse Follows Focus cursor feedback, user verification, native/synthetic checks, lifecycle and showcase candidate; extend exact ledger coverage through the feature commit. | Documentation | 4 |

| [`e7fe0ba9`](https://github.com/hexcrete/DockFork/commit/e7fe0ba991ac332127b18c0db3cdace169e7cc3c) | Reject inactive unassigned/ordered-out native tab rows during minimized/hidden-window discovery when collapsing is enabled; share cache cleanup, retain Space/fullscreen/ordering query failures, preserve legacy Space lookup behavior, remove duplicate Dock grouping and add production-source discovery/cache regressions with 576 baseline comparisons. User reports the original splitting sequence resolved; final conservative guards are build/regression validated. | Fix / Discovery / Native Tabs | 5 |

| [`66a49569`](https://github.com/hexcrete/DockFork/commit/66a4956935c945ddbd416f05c24ca48903cb4dc7) | Record native-tab discovery fix verification, conservative failure handling, lifecycle/contribution boundaries and remaining native test gaps; extend ledger coverage through the preceding source fix. | Documentation | 5 |

| [`ba1c481f`](https://github.com/hexcrete/DockFork/commit/ba1c481f24b509d08e5fe31ed5f45f8c16e093a1) | Shorten Close/Minimize All feedback titles and reflect restore intent/icon through the existing cached batch policy; preserve app-wide scope and execution. Add source-extracted title/icon/progress regressions and record user verification. | Fix / Actions / Feedback | 6 |

| [`987f391d`](https://github.com/hexcrete/DockFork/commit/987f391d51f7e89e3a8bf2ebb8752641335b182f) | Separate normal Quit from explicit Force Quit across shared assignments, menus, feedback, windowless/batch targeting and Cmd+Tab; remove Option overrides from Quit/Close-to-Quit while retaining Dock Quick Quit. Preserve defaults and add inert-app request/refusal/cancellation regressions. | Fix / Actions / Quit | 15 |

| [`74452790`](https://github.com/hexcrete/DockFork/commit/744527905683dfa25b924cbaea849e9a8ce8ba27) | Add explicit normal-Quit/Force-Quit AppleScript commands through the shared asynchronous action adapter, preserve dictionary identities and list handling, update generated help and record verification/contribution boundaries. | Feature / Scripting / Quit | 10 |

| [`78961f59`](https://github.com/hexcrete/DockFork/commit/78961f598914407f6d7f1c330bfbe1e9eb1ff923) | Route single Hide/Unhide, Full Screen, Space-picker fullscreen exit and related restoration through confirmed background workers; preserve single/batch intent, activation, filtering and dismissal; remove bypassed toggles/watchers and cover cancellation, main-actor responsiveness and ordinary-click restore/focus/dismiss order. User verification passed; native fault/display coverage remains limited. | Fix / Actions / Responsiveness | 21 |
| [`d8163ad6`](https://github.com/hexcrete/DockFork/commit/d8163ad63ff8279754cd06c35f325130fff5cd01) | Move native Cmd+Tab highlighted-app Close to the shared asynchronous executor; preserve snapshots, normal-Quit fallback and session lifetime, use real feedback identities, and record unfocused app-level Minimize as a separate follow-up. User verification and regression tests passed. | Fix / Actions / Responsiveness | 11 |
| [`a24c75aa`](https://github.com/hexcrete/DockFork/commit/a24c75aaad6a93b89d4bdcb4c454caa862d43b3c) | Serialize background frame transactions per owning AX app across resize, Auto Tile, gestures, linked resizing and title-bar restore; preserve ordered writes, cleanup and confirmation limits; refresh displayed full-size previews through cache publication. User verification and eleven inert suites passed; exhaustive native fault/display coverage remains pending. | Fix / Actions / Responsiveness | 18 |
| [`611f0204`](https://github.com/hexcrete/DockFork/commit/611f02043e6d02aa07ceaaea9235f32408990697) | Run released drag placement through the shared per-app frame worker; preserve visible-frame fitting/clamping, call counts, Space/reveal/foreground order and drop lifetime; reconcile partial writes and cancellation. User verification and eleven inert regression suites passed; exhaustive native fault/display tests remain unverified. | Fix / Actions / Responsiveness | 10 |

| [`175bf610`](https://github.com/hexcrete/DockFork/commit/175bf6107ae256a4b9892fa29c5986513c3d0153) | Preserve native external-drag targets during app-activation dismissal with token-owned cleanup; leave explicit/normal dismissal unchanged, remove temporary diagnostics and add isolated policy/lifetime regressions. User reports improvement and traces confirm delayed activation; exhaustive native lifecycle coverage remains unverified. | Fix / Spring-loading | 10 |

| [`5734b16e`](https://github.com/hexcrete/DockFork/commit/5734b16efbdcb9e324fdc675370783290d23636a) | Finish action preflight/caller audit with snapshot UI checks, background live validation/status reads, stable identity publication and scoped Space-request cancellation/refusal handling; retire synchronous bypasses. Eleven inert suites and build verification pass; user approved wrapping up while unrelated-action cancellation remains a separate follow-up. | Fix / Actions / Responsiveness | 17 |

| [`013762f5`](https://github.com/hexcrete/DockFork/commit/013762f560b5ab7d199995ce10dbdc3d36170a5a) | Replace minimize-specific admission with shared stable-identity/app-scope ownership, protected batches and destructive requests, independent preview execution, cooperative single replacement and token-scoped cleanup. Preserve frozen toggle intent and existing confirmations. Eleven inert suites, build verification and user testing pass; direct-route migration and feedback cleanup remain later stages. | Fix / Actions / Ownership | 13 |

| [`bb1c0deb`](https://github.com/hexcrete/DockFork/commit/bb1c0debcb67b834efb6f3160258e319ebd8951c) | Extend shared admission through direct mutations, Space/drag, scripts, gestures, Dock, menus and linked/title-bar writers. Retain superseded cleanup before successor writes, atomic coupled/app scopes and latest-action foregrounding; fix scripted Space-list ownership through optional follow. Twelve regression suites and disposable Brave/Finder native overlap tests pass. Script inventory freshness is a separate follow-up; later feedback stages are not started. | Fix / Actions / Ownership | 19 |

| [`2dfd752c`](https://github.com/hexcrete/DockFork/commit/2dfd752c65af6732f29ccf12738060f49c43989b) | Record Stage 2 review, regression/native verification, the scripted Space-list correction, remaining physical-input/display gaps and separate script-inventory follow-up; extend the ledger through its source commit and pause later stages for the success-symbol decision. | Documentation | 6 |

| [`617ad3fb`](https://github.com/hexcrete/DockFork/commit/617ad3fbd0455374aba2895531d3350f05b7840c) | Share cached action targets and buffered settlement across admission, execution and feedback; count Hide by app, preserve write-first Minimize/Restore confirmations with opportunistic outcomes, and exclude fullscreen Auto Tile entries before layout/accounting. | Fix / Accounting | 10 |

| [`62075ddc`](https://github.com/hexcrete/DockFork/commit/62075ddce69927483356b70a23a4d99e647dd289) | Record Stage 3 review, speed-first confirmation/outcome policy, fullscreen Auto Tile exclusions, verified development artifact, remaining native gaps and the approved spinner-only Stage 4 plan; extend exact ledger coverage through its implementation. | Documentation | 6 |

| [`7936b273`](https://github.com/hexcrete/DockFork/commit/7936b2732653a61414ebc8cb4805ebac1c8f9921) | Show success symbols only after presented spinners while preserving accessible outcomes; report explicit invalid single-target attempts and preserve feedback through Space changes with bounded presentation settling, restarted result holds and temporary-resource cleanup. | Fix / Feedback | 3 |

| [`5f7ce40e`](https://github.com/hexcrete/DockFork/commit/5f7ce40e2d156b0bfbe5586ff3e796756b5f05aa) | Record user verification and final review of Stage 4 spinner-conditioned success, invalid-attempt feedback and bounded Space-transition presentation lifetime; retain native coverage limits and extend exact ledger coverage through its implementation. | Documentation | 6 |

| [`b2cb01e9`](https://github.com/hexcrete/DockFork/commit/b2cb01e92e1ee67a3af9c8476c81d17016fbe213) | Report real committed-gesture outcomes through shared feedback and ownership; preserve candidate/flash behavior, independent enablement and fixed placement, retain foreground/enrollment lifetime, and forward existing confirmation progress. Twelve regression suites and user verification pass; exhaustive native coverage remains unverified. | Fix / Gestures / Feedback | 6 |

| [`f04284aa`](https://github.com/hexcrete/DockFork/commit/f04284aa6e686995cd1fdb287f90b6fe2f4a7bc9) | Record verified Stage 5 gesture feedback, passing regression/build correspondence, completion of the shared ownership plan and remaining native coverage gaps; extend exact ledger coverage through its implementation. | Documentation | 6 |

| [`4038decf`](https://github.com/hexcrete/DockFork/commit/4038decf82883c1da28cbe5395eb1df77212138d) | Support app-level Minimize/Restore before focusing a native Cmd+Tab preview through the shared App Header toggle; preserve Command/focused-preview priority, exclusions, ownership and feedback, and share target lookup with Close. Add dispatcher/group-policy regressions; all twelve suites and user verification pass. | Feature / Cmd+Tab | 4 |

| [`b23f53cf`](https://github.com/hexcrete/DockFork/commit/b23f53cfd5374954e0b68347612202ad927e4403) | Record user verification and final review of Cmd+Tab app-level Minimize, shared toggle/resource boundaries, regression/build checks and showcase coverage; clarify completed Stage 5 roadmap status and extend exact ledger coverage through its implementation. | Documentation | 6 |

| [`c5d64dc6`](https://github.com/hexcrete/DockFork/commit/c5d64dc67635114615453a89f8059a954e9c00ea) | Move and rename the cursor-feedback toggle beneath Mouse follows focus, hide unavailable controls without resetting preferences, and relocate matching settings-search metadata. Preserve runtime gates/defaults and add placement/visibility/search regressions; focused checks and user verification pass. | UI / Settings | 4 |

| [`7850a6e3`](https://github.com/hexcrete/DockFork/commit/7850a6e353a222cb0f1e572a3cbd32ca357d4686) | Record user verification and final review of the relocated cursor-feedback toggle and conditional visibility; update showcase setup and extend exact ledger coverage through its implementation. | Documentation | 3 |

| [`685d1713`](https://github.com/hexcrete/DockFork/commit/685d171364d5eadfb8fcaa2015310d4ca6056b72) | Remove unreliable popup Space-transition delays, observer/state and all preparation plumbing; retire unused dismissal/worker arguments while preserving native panel behavior, ordinary timing and actual preview-disappearance handoff. Twelve regression suites and final development-build checks pass; committed after review and user authorization, native visual verification unreported. | Fix / Feedback | 5 |

| [`d084e66a`](https://github.com/hexcrete/DockFork/commit/d084e66ab185c4a1b41157bc48066d8bbf4ca154) | Record removal of the popup transition workaround, supersede historical timing/capture/contribution guidance, retain native visibility limits and extend exact ledger coverage through the reviewed implementation. | Documentation | 6 |

| [`715421b3`](https://github.com/hexcrete/DockFork/commit/715421b39c8768fd5be062ef48cb2f42db9b7aa5) | Add opt-in successful-build cleanup of validated local outputs, preserving Release packages, current/active builds, installed app and unrelated/symlink entries. Add production deletion-safety fixtures, malformed-PID handling and trap-owned marker cleanup. Packaging/version tests, actual custom-output CLI and final automatic Debug build/launch/pruning checks pass. | Build / Maintenance | 2 |
| [`ae104843`](https://github.com/hexcrete/DockFork/commit/ae104843b17f6956abb9d49e38c41eae7bbff427) | Make cleanup part of routine fork rebuild instructions and record packaging verification, preservation rules and ledger coverage. | Documentation / Maintenance | 8 |
| [`1b6cd4b3`](https://github.com/hexcrete/DockFork/commit/1b6cd4b3a98eb104e2608ee109317acb20adaf3f) | Resize same-count placeholder/real-window swaps and coalesce content measurement. Hide compact-style windowless headers while preserving enabled full-size headers with independent Dock/Cmd+Tab settings. Add production-source layout and 32-case header fixtures. Thirteen suites, format/diff, signed Debug build/relaunch and installed/source/running-path verification pass; initial transition user-tested, exhaustive native coverage pending. | Fix / UI | 4 |
| [`098c2cb5`](https://github.com/hexcrete/DockFork/commit/098c2cb51ae3dd69ed2e859d3dbc3684d2be2e74) | Record reviewed windowless transition sizing, independent full-size header behavior, production fixtures and signed development validation. | Documentation / Maintenance | 5 |
| [`91ff4e77`](https://github.com/hexcrete/DockFork/commit/91ff4e77277a5c54db05be22d9349f9e0125ba4d) | Rename Dock/Cmd+Tab full-size windowless preview controls to Show full size placeholders, matching settings search and fork documentation without changing stored keys, defaults or behavior. | UI / Maintenance | 6 |
| [`964d9292`](https://github.com/hexcrete/DockFork/commit/964d9292387578c8dff77395aa43f2d101b08a82) | Restrict window movement gestures to noninteractive regular/Compact preview body surfaces. Compact rows use a background above decorative chrome, covering empty space and padding while excluding controls. Add native helper-panel hit-testing and source-wiring regressions; user verification and final review passed. | Fix / Input | 9 |
| [`f505e2ef`](https://github.com/hexcrete/DockFork/commit/f505e2ef575d5569fb104318ef3696b417c603ea) | Execute eligible preview/menu/Cmd+Tab actions and numbered Space commands once per physical key press; consume repeats through dismissal until release. Preserve navigation/typing, modifier-side resolution and execution ownership. Add production-source key lifecycle/Space matching checks; user verification and review passed. | Fix / Input | 7 |
| [`48c15b13`](https://github.com/hexcrete/DockFork/commit/48c15b138032ac295d111b3d95dee3283b993067) | Add shared additive Shift-checkbox ranges, reversible checkbox sweeps and held-selection-key arrow extension, including focused search. Preserve ordered checks, session ownership, normal navigation and existing scrolling resources; clean up on release, takeover and membership changes. Production-source/native fixtures, all fifteen suites, format/diff, signed development verification and user testing pass; exhaustive native coverage remains unverified. | Feature / Input | 12 |
| [`2a64ca4d`](https://github.com/hexcrete/DockFork/commit/2a64ca4dfc65ea1fd5e468eaeb5c8d452f702ae7) | Record completion of all three preview-input stages, corrected search-focused range selection, fifteen passing suites, signed/running-source verification, user approval and remaining native coverage gaps. Extend the exact-hash ledger and upstream extraction notes. | Documentation / Maintenance | 6 |

| [`b1ad1436`](https://github.com/hexcrete/DockFork/commit/b1ad14363feb4a37ad78e926d8386eac69fe4fbb) | Recover named, screen-sized Wine/CrossOver game windows at Wine fullscreen levels through shared AX, startup and capture admission. Preserve normal-window filtering and native fullscreen state. Add 3,168 compatibility comparisons, fast-path/error fixtures and opt-in read-only native validation; sixteen suites, signed development/source verification and user testing pass. | Fix / Discovery | 4 |

| [`bdb6e266`](https://github.com/hexcrete/DockFork/commit/bdb6e266360e1561d015288cc51b2fcf6c17c886) | Record user verification, final review and committed Wine discovery, read-only native validation, regression/build evidence, resource boundaries and remaining action/media coverage gaps. | Documentation | 6 |

| [`7fab4ad7`](https://github.com/hexcrete/DockFork/commit/7fab4ad78266df4b963a4e1578023fe75b203da0) | Share cached Wine/CrossOver action support across controls, menus, group eligibility, toggle intent and direct executors. Keep unsupported controls absent while hidden, ignore unsupported batch targets and fail direct attempts. Preserve supported actions and normal apps without new AX queries or resources. Sixteen suites, final review, signed development verification and user testing pass; exhaustive native coverage remains unverified. | Fix / Actions | 18 |

| [`a545f318`](https://github.com/hexcrete/DockFork/commit/a545f3188b0069e3b0a801cdbca0c7bf16b5aefd) | Record user verification, final review and committed Wine action support, regression/build evidence, resource/contribution boundaries and remaining native coverage gaps; extend exact ledger coverage through the implementation. | Documentation | 6 |

| [`4db9853d`](https://github.com/hexcrete/DockFork/commit/4db9853dd92497a0b1a210cdef2c9ab9460afa87) | Explain all three range-selection methods below enabled selection, matching localized search text and keywords. Add visibility/search regression and record signed development validation; no selection behavior/default change. | UI / Documentation | 6 |
| [`77e4771d`](https://github.com/ejbills/DockDoor/commit/77e4771d38cf69dc24f2f76c74a73e61fab54571) | Upstream website: list Droppy on Works With, add its icon and partner spacing. No application-source change. | Upstream / Website | 3 |
| [`d50d6882`](https://github.com/hexcrete/DockFork/commit/d50d68825e1eecba636bdb9185492c583d89bbee) | Merge the single upstream website commit without conflicts; pin the incorporated upstream hash while retaining stable base 1.41.0. Changed-file count uses the first-parent merge diff. | Integration | 4 |

| [`6d3eb470`](https://github.com/hexcrete/DockFork/commit/6d3eb4707c7db4446c78786e8df6ceec279be7b2) | Prepare 0.3.0 prerelease notes/version, sanitized October 20 preset and updated publication/install/showcase records. Preserve prior releases, remove four private-state keys and anonymize 15 shortcut rows. Exact source of the audited ad-hoc arm64 Release candidate; no live import or publication. | Release / Preparation | 13 |

| [`266f9701`](https://github.com/hexcrete/DockFork/commit/266f9701fcd606df61a65c000924a1824d1c810d) | Record the audited 0.3.0 candidate, exact artifact checksums and allowlist, privacy-marker results, preserved running development app and pending manual installation/publication gates. No production or package-input changes. | Documentation / Release | 7 |

| [`6b97d2dc`](https://github.com/hexcrete/DockFork/commit/6b97d2dc6891099150730fd46fa2b5240a3b39e2) | Separate the approved public 0.3.0 release body from internal audit/handoff records, record final regression/artifact review and explicit publication authorization, and extend exact ledger coverage. Application and audited assets unchanged. | Documentation / Release | 5 |

| [`b504e944`](https://github.com/hexcrete/DockFork/commit/b504e944909fa0b5aa3e8938bc4c914840bfc0b8) | Record authorized 0.3.0 publication from the unchanged audited candidate, exact tag, approved notes and ten matching public downloads; update fork release links, roadmap, resource/showcase records and ledger coverage. Preserve remaining installation/media testing gaps. | Documentation / Release | 8 |

| [`e70508d0`](https://github.com/hexcrete/DockFork/commit/e70508d01466dab8121fdf385e3b17114ebe65c4) | Remove the unused hidden-state argument and its two call-site entries without changing presentation snapshots or behavior. Record focused regression/format checks, signed Debug rebuild and verified exact-path relaunch; preserve published assets. | Maintenance / Actions | 5 |

| [`5f773ed9`](https://github.com/hexcrete/DockFork/commit/5f773ed996c4f06194276fe0b2b63c8ccfefa1be) | Preserve checkbox and held-shortcut ranges during unchanged background refreshes using passive highlight restoration; reconcile real list changes and align per-app restoration. Add production-source regressions, record user verification, final caller audit and signed/running development validation; update fork maintenance records. | Fix / Input / Selection | 8 |

| [`c353d70f`](https://github.com/hexcrete/DockFork/commit/c353d70f737a036b7776cb8650c62778992de8c7) | Add default-Off interactive title-bar exclusion, complete-ancestry and fallback guards, window-hit cache isolation, search/reset wiring and production-source regressions. User verified the restored broad policy; seventeen suites and signed/running development checks pass. | Feature / Gestures / Input | 13 |

| [`ad8d7614`](https://github.com/hexcrete/DockFork/commit/ad8d7614adb975e17e47ca6652a0200a10b76d3f) | Narrow the optional title-bar filter to scrolling/content ancestry and tab groups/subroles while retaining standard rules for other controls; preserve preference key/default, cache protections and settings wiring. User verified; seventeen suites and signed/running development checks passed. | Fix / Gestures / Input | 11 |

| [`586be06a`](https://github.com/hexcrete/DockFork/commit/586be06ae0de421e73d0ce7ec5d537509c1c3806) | Prepare 0.3.1 patch prerelease for selection-refresh reliability and optional scrolling/tab gesture exclusion; update version, preset export label only, public/detailed notes and fork records. Upstream fetched with no new main changes; seventeen suites and packaging checks passed, with one unchanged native hit-test retry. Exact candidate source; later audit/handoff is recorded separately. | Release / Packaging / Documentation | 13 |

| [`cea73ecb`](https://github.com/hexcrete/DockFork/commit/cea73ecbdca20e9f80eb51563904672992db13b5) | Record the 0.3.1 candidate source/checksum, actual artifact/privacy audit, test gaps and unchanged publication status. The user subsequently clarified that preparation was premature; this candidate is superseded by the October 22 preset refresh and is not eligible for distribution. | Documentation / Release | 7 |

| [`07dfcb7d`](https://github.com/hexcrete/DockFork/commit/07dfcb7de8fc77edbe20b8bc2d9c400b32e12608) | Sanitize the October 22 showcase export, remove four system/private entries, anonymize 14 shortcut IDs, preserve supplied settings and document the enabled gesture filter/custom Persistent shortcut omission. Mark the premature candidate superseded; record explicit refreshed-build authorization and unchanged publication status. Exact refreshed candidate source; later artifact/handoff results are separate. | Release / Preset / Privacy | 12 |

| [`146a7366`](https://github.com/hexcrete/DockFork/commit/146a7366a59c27a519ae0ce6b60c6709a62e57cb) | Record refreshed 0.3.1 candidate checksum, exact source/preset correspondence, artifact/privacy checks and manual-test gaps; preserve unchanged running app and unpublished status. Later held as an interim candidate while Spaces Bar development proceeds. | Documentation / Release | 8 |
| [`61a221cb`](https://github.com/hexcrete/DockFork/commit/61a221cb2dcb498f2c41f9b30df1e3e9c8e42b53) | Share ordered Space presentation metadata across native menus; retain represented-window identities/counts and record the staged Spaces Bar plan and held release. | Spaces / Refactor | 12 |

## Upstream Attribution and Contribution Boundaries

The original three merge entries and the three later continuation merges integrate upstream capabilities and fix merge interactions; they are not ownership claims over upstream's contributions. In particular, the base swipe launcher and latest JSON backup/import support came from upstream. Attribution in the guide distinguishes those from fork refinements.

Preserve this history in the public fork. When proposing upstream contributions, prepare small dependency-aware branches after agreeing scope; do not assume an early commit can be cherry-picked onto current main unchanged. Existing upstream contribution instructions require human review, testing, and AI disclosure.

## Regenerating the Inventory

Use the exact baseline and explicit coverage tip above, not a moving `origin/main..HEAD` range. Read `git log --reverse`, each patch and changed-file list, and compare final code/settings with the baseline. Require exactly one primary category per commit, no omissions, and no duplicate entries. Preserve the frozen inventory and extend the continuation for later development; update its tip and totals explicitly. Record the ledger-maintenance commit itself in the next update, since it cannot contain its own final hash.

| [`2d56788e`](https://github.com/hexcrete/DockFork/commit/2d56788e02f4428a01c5a4d3d93aa9d288de4aa7) | Add optional Spaces Bar cards, shared placement/search reservations and edge scrolling, native pinned display headings, nine calibrated sizes, Appearance controls, live cache/display refresh and accessibility. Preserve stored visual sizes, shared dropdown model, lifecycle gating and held release. Record user testing, eighteen passing suites, final overflow fitting and signed/running binary checks; later interaction stages remain deferred. | Feature / Spaces / UI | 24 |

| [`adeaad3b`](https://github.com/hexcrete/DockFork/commit/adeaad3b660cd44d00270e99262c1fe2fcfb0641) | Record the Stage 2 implementation hash and 24-file count; verify exact, unique Git coverage through that feature commit. | Documentation / Ledger | 1 |

| [`9f608bc4`](https://github.com/hexcrete/DockFork/commit/9f608bc4597a2a442f83cebb8cf82a0775276260) | Add Space/window keyboard navigation, session-aware cycle bindings/conflict warnings, hover filtering with stable clear/re-entry behavior, shared scope restoration/checked membership, recent ordering, optional cycle launch and Space-focused AppleScript launch. Include geometry/animation corrections, production regressions and user verification; signed/running final-source checks pass. Record intermittent native drag-test failures and the successful idle-machine retry. Later drop/swipe/content stages remain paused. | Feature / Spaces / Input | 25 |

| [`b0042164`](https://github.com/hexcrete/DockFork/commit/b00421648f96022e80d36e3060d8399cc1de7515) | Record Stage 3 implementation hash, 25-file count and unique coverage through that commit. | Documentation / Ledger | 1 |

| [`befe4e29`](https://github.com/hexcrete/DockFork/commit/befe4e292d5dc8987a65b3aa59a9bab8933d4fbf) | Add default-On Spaces Bar app icon visibility, remove hidden icon/count/overflow layout, preserve resident metadata and gate activation. Keep dependent activation editable with an exact quoted Appearance-path explanation. Wire reset/search and regression coverage; final signed/running build and user verification pass. | Feature / Spaces / Settings | 12 |

| [`b9a80b11`](https://github.com/hexcrete/DockFork/commit/b9a80b1117cfc6061be98007c48f2265de7d54ad) | Record icon-visibility feature hash, 12-file count and unique ledger coverage through that feature commit. | Documentation / Ledger | 1 |

| [`0d11655b`](https://github.com/hexcrete/DockFork/commit/0d11655be02fd62c5656bc62b036b8ce9dba3f18) | Add Desktop-pill window/selection drops with cached native scroll hit-testing, shared drag highlight/edge scrolling and extracted confirmed group-Space movement; retain ownership/lifetime and follow preference, keep previews open without following. User verified; tests and signed/running checks recorded with unchanged baseline popup-fixture failure and native coverage gaps. | Feature / Spaces / Dragging | 13 |

| [`ec63e90d`](https://github.com/hexcrete/DockFork/commit/ec63e90d302a5595960b6c64d2cf89c34dea3862) | Record Stage 4 implementation hash, 13-file count and unique ledger coverage through that feature commit. | Documentation / Ledger | 1 |

| [`d8ef1995`](https://github.com/hexcrete/DockFork/commit/d8ef1995afd13205dcf26cb911d214b0969c77d2) | Add default-Off opposite-axis Spaces swipes through the existing detector/tap and switcher session lifecycle. Latch axis, preserve direction/reversal including initial Space highlighting, and retain held-initializer/persistent takeover policy. Wire dynamic direction label, conflict guidance, reset/search and deterministic touch/ownership tests; user verified, signed/running build and final review pass. | Feature / Spaces / Gestures | 13 |

| [`1235b321`](https://github.com/hexcrete/DockFork/commit/1235b321441550860588943ee545e4d3b27518ba) | Record Stage 5 implementation hash, 13-file count and unique ledger coverage through that feature commit. | Documentation / Ledger | 1 |

October 24 Stage 6 sign-off: the user reports content operations and whole-pill/target-label polish working well. Final source review and verification pass. The implementation below is included in coverage; this ledger-only update cannot include its own final hash. Group sizing/text changes and synchronized gap animation remain deferred.

| [`1bb51e3b`](https://github.com/hexcrete/DockFork/commit/1bb51e3bbc7d840b96dfa7727d96e994df717605) | Add Desktop-content Move/Swap/Shift with cached membership mappings, shared ownership/confirmed moves and aggregate feedback, bounded scripting, native destination menus and whole-pill drag input. Share group-card chrome for target-aware labels; preserve native Space order and window state. User verified; eighteen suites pass across one Compact fixture retry, format/XML/diff and signed/running source checks pass. Native fault/display/accessibility and live scripting gaps remain explicit. | Feature / Spaces / Dragging / Scripting | 21 |

| [`e530cde1`](https://github.com/hexcrete/DockFork/commit/e530cde1cc7fc13593a78bb7f569c755244a964b) | Record the Stage 6 implementation hash, 21-file count and verified unique ledger coverage through that feature commit. | Documentation / Ledger | 1 |

October 24 animation sign-off: the user verifies the initial feel and authorizes review/commit. Review also synchronizes native container and reflowed-pill widths; eighteen suites and signed/running build checks pass. The implementation below is included; this ledger-only update cannot include its own final hash.

| [`44ef9e3a`](https://github.com/hexcrete/DockFork/commit/44ef9e3a10cc2741e2345bf301a23c42b83f7c80) | Animate Desktop drop-gap expansion/reversal with one SwiftUI progress value shared by native panel sizing, reflowed pills, headings, content extent and drop geometry. Reuse animation/Reduce Motion controls and heading views; no timer/input delay. User verified initial feel; review corrections pass native intermediate-frame/quick-drop checks, all eighteen suites and signed/running build verification. Broader physical/display coverage remains explicit. | Feature / Spaces / Animation | 9 |

| [`d609009a`](https://github.com/hexcrete/DockFork/commit/d609009abf6c23698cb434201bb251cf77ab75e9) | Record the gap-animation implementation hash, nine-file count and verified unique ledger coverage through that feature commit. | Documentation / Ledger | 1 |

October 24 directional-gap sign-off: user verification, caller/side-symmetry review and all eighteen suites pass. The fix below is included; this ledger-only update cannot contain its own final hash.

| [`aa09d4bf`](https://github.com/hexcrete/DockFork/commit/aa09d4bff57d5ad49be71a53706744ea2b96d7e2) | Resolve content-gap destinations from the adjacent slot in drag direction, rejecting fullscreen/unknown slots and no-ops without searching past them. Keep highlights, symbols and execution on the shared resolver; retain fullscreen-skipping shift paths and remove candidate-array copies. User verified; mirrored-order, nonsequential-ID and unknown-slot tests, all eighteen suites and signed/running source checks pass. | Fix / Spaces / Dragging | 8 |

| [`fd46e3c0`](https://github.com/hexcrete/DockFork/commit/fd46e3c05c6b56b8dd71b8cf8bb367728e55002a) | Record the directional-gap fix hash, eight-file count and verified unique ledger coverage through that fix. | Documentation / Ledger | 1 |

October 24 Stage 1 sign-off: shared Space sizes passed user verification and final review; source/signature/running correspondence remains verified. The implementation below is covered. Compact opacity and drag-card stages remain separate.

| [`9b7b2b2f`](https://github.com/hexcrete/DockFork/commit/9b7b2b2f0dd9b4444d786823cf3f1087f00c6a6f) | Match seven Spaces Bar size labels to shared Compact Mode nominal heights/fonts while preserving surviving stored values and default Small. Retain smaller Space-icon proportions; rely on normal fallback for removed values without migration. User verified; all eighteen suites, native height/font and volatile-domain checks, format/diff and signed/running build verification pass. | Fix / Spaces / Sizing | 9 |

October 24 Stage 2 sign-off: the user authorizes review/commit/continuation. The modifier-only production change passes final review, focused input/opacity checks and signed/running source verification; retain the 17-suite result and unrelated popup-fixture failure. The implementation below is covered; drag-card Stage 3 remains separate.

| [`25e13439`](https://github.com/hexcrete/DockFork/commit/25e1343901ce58d2eb5a940ee313a594950f9382) | Apply existing Compact content opacity before shared card chrome, leaving material/borders full strength without adding effects or changing regular-card opacity. User verified; focused native input and 96 deterministic-fill composition checks pass, with 17 passing suites and the unchanged popup timing failure recorded. Signed/running source correspondence and format/diff checks pass. | Fix / Compact / Appearance | 8 |

October 24 working-tree note: source-styled drag-card Stage 3 is implemented pending verification. Coverage ends at `25e13439`; no drag-card commit hash is available yet.

Stage 3 remains uncommitted after the user's Space-pill revision: app grouping/subscripts, shared side padding/spacing, card-only shadow removal and content-only clipping. Coverage remains through `25e13439`. Final handoff stops work for the user's usage-limit request; no new commit is recorded.

Stage 3 completion is authorized without running automated tests in this pass. The working changes also add shared window-drop intent/glyphs and single-window overlays. The ledger boundary remains `25e13439` until the feature's exact commit hash is recorded in the subsequent test-workflow audit update. No release or push is authorized.

| [`6c1f12fe`](https://github.com/hexcrete/DockFork/commit/6c1f12fe4d762bc437482995a2beeb5e5b5f8aa5) | Share source card chrome/metrics, Space-pill padding and app-count subscripts; group drag icons by app without changing payload order. Add shared cached window-drop intent/glyphs and overlay the card on single-window miniatures. Format/diff, signed development build/relaunch and installed source/binary/running-path checks pass. No automated suite was run for the final glyph/overlay revision; native visual verification remains pending. | Refactor / UI / Dragging | 15 |

Test-workflow audit records follow in a separate commit. Coverage ends at `6c1f12fe4d762bc437482995a2beeb5e5b5f8aa5`; the audit commit cannot record its own final hash.

| [`6813aaba`](https://github.com/hexcrete/DockFork/commit/6813aabad92d84611b4cc73bd378500dd88a1ef5) | Audit active regression suites, update obsolete drop-routing/shadow assertions and document focused checks rather than full-suite execution after cosmetic rebuilds. Preserve active coverage and record the exact drag-card commit. Source-only audit; tests not run at user request. | Documentation / Testing | 6 |

Coverage now ends at `6813aabad92d84611b4cc73bd378500dd88a1ef5`. The single-window overlay centering correction is uncommitted and outside this boundary.

| [`4ccfabb6`](https://github.com/hexcrete/DockFork/commit/4ccfabb6e2c5ca0c46fbb1bb374f772577341d29) | Center the shared drag card on single-window miniatures without changing size or drop behavior. User verified; development build, strict signature, source/binary/running-path and format/diff checks pass. Initial macOS launch error -600 resolved by retrying the same installed app. Automated tests skipped by request. | Fix / UI / Dragging | 4 |

Coverage ends at `4ccfabb6e2c5ca0c46fbb1bb374f772577341d29`. The Spaces Bar outer-spacing correction is uncommitted and outside this boundary.

| [`c6a9ec21`](https://github.com/hexcrete/DockFork/commit/c6a9ec21da60ed4426956a30b22a152aeaadebf8) | Reuse Compact Mode container insets and gaps directly in Spaces Bar, removing extra Item Size multiplication. Preserve internal pill proportions and expanded drop gaps. User verified; final layout-caller review, format/diff, signed build and exact installed source/binary/running-path checks pass. Automated suites deliberately skipped; broader native coverage remains pending. | Fix / UI / Spaces | 5 |

Coverage ends at `c6a9ec21da60ed4426956a30b22a152aeaadebf8`. Source-anchored Space drag expansion is uncommitted and outside this boundary.

| [`7e643af7`](https://github.com/hexcrete/DockFork/commit/7e643af749bec10978000b6e5dfed4c0226db1e6) | Keep the dragged Space pill steady as gaps expand/collapse using existing native panel/scroll updates, screen clamping and actual native-frame compensation. Retain anchor through collapse and avoid competing highlight reveal. User verified; final source review, formatter/diff and development build/signature/source/binary/running-path checks pass. Automated suites skipped; exhaustive display/fault coverage unclaimed. | Fix / UI / Spaces / Dragging | 6 |

Coverage ends at `7e643af749bec10978000b6e5dfed4c0226db1e6`. Dock/Cmd+Tab-to-switcher presentation cleanup is uncommitted and outside this boundary.

| [`461909b9`](https://github.com/hexcrete/DockFork/commit/461909b9b968594f38319aab7b98228bd275fb41) | Cancel pending previews and dismiss a visible non-switcher through shared cleanup before fresh Window Switcher initialization; clear Dock/Cmd+Tab selection/layout anchors rather than carrying them over. User accepted the behavior and approved commit; source review, formatter/diff and signed development/source/binary/running-path checks pass. Automated suites skipped and exhaustive native entry-route coverage unclaimed. | Fix / UI / Sessions | 6 |

Coverage ends at `461909b9b968594f38319aab7b98228bd275fb41`. Opening Space-pill hover suppression is uncommitted and outside this boundary.

| [`ca328410`](https://github.com/hexcrete/DockFork/commit/ca328410a46987c3c7f4d07998d4e266febe663a) | Suppress the opening Space pill until native pointer exit; resolve immutable opening coordinates on first hit agreement, and gate visual hover on coordinator acceptance. Remove failed eager layout-time capture. User verified the revision; source review, formatter/diff and signed development/source/binary/running-path checks pass. Automated suites skipped; broader native coverage unclaimed. | Fix / UI / Spaces / Input | 6 |

Coverage ends at `ca328410a46987c3c7f4d07998d4e266febe663a`. Shared native Space-pill menus are uncommitted and outside this boundary.

| [`8ffb3137`](https://github.com/hexcrete/DockFork/commit/8ffb3137b69454f405357e677e0c5b4d71a4f9a3) | Share native destination formatting and right-click-only capture across window and whole Space pills; reuse drag action glyphs and add resident-scoped exit-only fullscreen actions. Preserve original menu validation/hints and execution pipelines. User verified menus; final source review, formatter/diff and signed development/source/binary/running-path checks pass. Automated suites skipped; exhaustive native mutation/accessibility coverage unclaimed. | Feature / UI / Spaces / Menus | 12 |

Coverage ends at `8ffb3137b69454f405357e677e0c5b4d71a4f9a3`. Global cross-display content shifting is uncommitted and outside this boundary.

| [`3aae4e6c`](https://github.com/hexcrete/DockFork/commit/3aae4e6cd98f96df5677ec5c894038fcfcd4950a) | Shift Desktop contents across displays in global sequential order through shared drag gaps/glyphs, menus and AppleScript. Preserve fullscreen/no-op guards; remove obsolete same-display error and menu restriction. Review hardens all content plans to full ordered topology and removes obsolete scope data, catching inserted displays/slots without new queries. User verified global shifting; hardened signed build/source/binary/dictionary/path, formatter/XML/diff checks pass. Automated suites and native fault injection unrun. | Feature / Spaces / Dragging / Scripting | 12 |

Coverage ends at `3aae4e6cd98f96df5677ec5c894038fcfcd4950a`. Search-trigger shortcut conflict/side handling is uncommitted and outside this boundary.

| [`c644c71d`](https://github.com/hexcrete/DockFork/commit/c644c71dd267e6d5c976eef3df28e9ed368ff0f1) | Share dependent conflict checks between Search and Space cycling, warn/disable conflicting Search triggers, and use active side-aware modifiers with retained bare-key focus. Match neighboring modifier glyph styling. User verified the glyph revision; source review, formatter/diff and signed development/source/binary/running-path checks pass. Automated suites and exhaustive input combinations unrun. | Fix / Input / Settings | 9 |

Coverage ends at `c644c71dd267e6d5c976eef3df28e9ed368ff0f1`. Preserving the switcher during Space-pill fullscreen exit is uncommitted and outside this boundary.

| [`b248eaf6`](https://github.com/hexcrete/DockFork/commit/b248eaf6aa844d18afb9f22b433d9b792f9a2d68) | Preserve WS+SB for the fullscreen Space-pill exit command rather than preemptively hiding an unfocused target's presentation and stranding session cleanup. Reuse the existing preserve flag, exit-only worker and real-Space-change lifecycle; add no focus requests or AX work. User verified; final review, formatter/diff and signed development/source/binary/running-path checks pass. Automated suites and exhaustive native combinations unrun. | Fix / Spaces / Sessions | 6 |

Coverage ends at `b248eaf6aa844d18afb9f22b433d9b792f9a2d68`. Shared fullscreen indicator/pill menu construction is uncommitted and outside this boundary.

| [`c03d0409`](https://github.com/hexcrete/DockFork/commit/c03d0409ea440fced5a27b10514981390b3c93d6) | Coalesce fullscreen Space-indicator and Space-pill menus into one native Exit Full Screen builder/glyph/callback dispatch. Remove obsolete title, request wrapper and selector while retaining each caller's target scope and confirmed exit path. User verified; final review, formatter/diff and signed development/source/binary/running-path checks pass. Automated suites and exhaustive scope/fault coverage unrun. | Refactor / UI / Spaces / Menus | 6 |

Coverage ends at `c03d0409ea440fced5a27b10514981390b3c93d6`. Shared indicator intrinsic-width protection is uncommitted and outside this boundary.

| [`d7e5a30a`](https://github.com/hexcrete/DockFork/commit/d7e5a30aeb55ebc3a73e337a1647424ad0e43e6a) | Preserve intrinsic horizontal width in the shared Space/state indicator instead of compressing Compact rows during traffic-light reveal. Reuse adaptive-toolbar measurement/overflow; preserve dynamic content/font width and vertical sizing. User verified; final review, formatter/diff and signed development/source/binary/running-path checks pass. Automated suites and exhaustive state/style combinations unrun. | Fix / UI / Layout | 6 |

Coverage ends at `d7e5a30aeb55ebc3a73e337a1647424ad0e43e6a`. Separate Spaces Bar outside-click bounds are uncommitted and outside this boundary.

| [`62a2f7a2`](https://github.com/hexcrete/DockFork/commit/62a2f7a20fdcee5dde022c48b00a9d24295cc3a7) | Separate Spaces Bar and search click bounds instead of protecting empty gaps and transparent padding. Preserve shared container insets, native menu tracking and existing dismissal lifecycle. User verified; review, formatter/diff, signed build and exact source/binary/running-path checks passed. Automated suites unrun. | Fix / UI / Spaces / Input | 6 |

Coverage ends at `62a2f7a20fdcee5dde022c48b00a9d24295cc3a7`. Search-bar presentation synchronization is uncommitted and outside this boundary.

| [`e85020c2`](https://github.com/hexcrete/DockFork/commit/e85020c2ac2c95c837e8c06a51d89dc6a50d257e) | Remove the search companion's extra main-queue turn and redundant Spaces Bar layout update. Preserve search focus and placement. User approved retaining faster search appearance despite remaining render stagger; further synchronization deferred. Review, formatter/diff and signed development/source/binary/running-path checks passed. Automated suites unrun. | Fix / UI / Search | 6 |

Coverage ends at `e85020c2ac2c95c837e8c06a51d89dc6a50d257e`. Menu-bar toggle click ownership is uncommitted and outside this boundary.

| [`2f6d71ef`](https://github.com/hexcrete/DockFork/commit/2f6d71ef42133c54d1115382b03dcbe6caa44f7e) | Replace the menu-bar toggle's 50 ms timestamp handshake with actual status-button click ownership. Remove obsolete timestamp state and delayed dismissal. Record separate timing assumptions without changing them. User verified; review, formatter/diff and signed development/source/binary/running-path checks passed. Automated suites unrun. | Fix / Input / Menu bar | 8 |

Coverage ends at `2f6d71ef42133c54d1115382b03dcbe6caa44f7e`. Directional display-divider drop-zone deduplication is uncommitted and outside this boundary.

| [`5928725b`](https://github.com/hexcrete/DockFork/commit/5928725b8373dce39f08c97e81ee054eb5c88a83) | Deduplicate insertion zones around display dividers on the dragged Space's source side. Share directional policy across rendering, hit frames, headings and sizing; retain source identity through closing animation. User verified; review, formatter/diff and signed development/source/binary/running-path checks passed. Automated suites unrun. | Fix / UI / Spaces / Dragging | 7 |

Coverage ends at `5928725b8373dce39f08c97e81ee054eb5c88a83`. Larger clear-filter glyph rendering is uncommitted and outside this boundary.

| [`b27fcc99`](https://github.com/hexcrete/DockFork/commit/b27fcc996481c79247ca3c344ce96d7ac35586fb) | Render the Space-filter clear SF Symbol natively at 1.3x while retaining measured slots and icon positions; remove text-height clipping around the symbol. User verified; review, formatter/diff and signed development/source/binary/running-path checks passed. Automated suites unrun. | Fix / UI / Spaces | 5 |

Coverage ends at `b27fcc996481c79247ca3c344ce96d7ac35586fb`. Consistent action scope/dismissal Stage 1 is uncommitted and outside this boundary.

| [`2a0ea222`](https://github.com/hexcrete/DockFork/commit/2a0ea2226cbf4feedeec943d7e4baa010680d259) | End active switcher sessions at terminal panel dismissal through weak existing-owner cancellation, with fallback deactivation. Generalize the dismissal entry point and reject cancelled UI watchers after suspension. Preserve accepted mutations. User verified; review, formatter/diff and signed development/source/binary/running-path checks passed. Automated suites unrun. | Fix / Lifecycle / Actions | 11 |

Coverage ends at `2a0ea2226cbf4feedeec943d7e4baa010680d259`. Shared action scope/eligibility Stage 2 is uncommitted and outside this boundary.

| [`6526da0f`](https://github.com/hexcrete/DockFork/commit/6526da0fbb2f3578517a438abb54d0e1f7439eda) | Centralize initiating-window, selected-window, represented-app and all-app-window action scope. Open acts only on its initiating entry; unchecked Auto Tile cannot borrow another selection. Share cached group eligibility in regular/More menus while preserving explicit scripting targets and existing exclusions. User verified; review, formatter/diff, fixture syntax and signed development/source/binary/running-path checks passed. Automated suites unrun. | Fix / Actions / Selection | 12 |

Coverage ends at `6526da0fbb2f3578517a438abb54d0e1f7439eda`. Scope-aware action wording Stage 3 is uncommitted and outside this boundary.

| [`2b03dcd7`](https://github.com/hexcrete/DockFork/commit/2b03dcd7d64a14927a09a3f3787ee289e47c0f42) | Clarify initiating-window, checked-window and represented-app menu/control titles, rename the displayed Open action to Open Window, and preserve brief feedback names and scripting/stored identifiers. User verified; final review, formatter/diff, fixture syntax and signed development/source/binary/running-path checks passed. Automated suites and exhaustive localization/layout coverage unrun. | Fix / UI / Actions | 16 |

Coverage ends at `2b03dcd7d64a14927a09a3f3787ee289e47c0f42`. Space-pill actions Stage 1 fullscreen eligibility is uncommitted and outside this boundary.

| [`60c22a47`](https://github.com/hexcrete/DockFork/commit/60c22a479cfb450f923a43d2e4b54a0a01db3cad) | Share cached fullscreen action restrictions between regular/More menus and batch targeting. Preserve eligible mixed-selection peers, existing fullscreen exit, cached Hide policy and valid peer Space movement/source badges. User verified; final review, formatter/diff, fixture syntax and signed development/source/binary/running-path checks passed. Automated suites and exhaustive combinations unrun. | Fix / Actions / Fullscreen | 13 |

Coverage ends at `60c22a479cfb450f923a43d2e4b54a0a01db3cad`. Space-pill menu actions Stage 2 is uncommitted and outside this boundary.

| [`1f535008`](https://github.com/hexcrete/DockFork/commit/1f535008e8919e7fe91ac6b7140bcd9eefd9570e) | Add resident-window/app actions to Space-pill menus using shared eligibility, native row rendering/order, confirmed batch ownership/feedback, additive selection and source-Space tiling. Keep Auto Tile joined to the preceding group and preserve the destructive-action divider. User verified; review, fixture syntax, formatter/diff and signed development/source/binary/running-path checks passed. Automated suites and exhaustive native coverage unrun. Record highlighted-fullscreen-app quit collapse as deferred. | Feature / Spaces / Actions | 17 |

Coverage ends at `1f535008e8919e7fe91ac6b7140bcd9eefd9570e`. Space-targeted shortcuts Stage 3 is uncommitted and outside this boundary.

| [`0646272e`](https://github.com/hexcrete/DockFork/commit/0646272e65ce81219092d964abf3d0decdc29bf6) | Route preview-action shortcuts to the highlighted or menu-pinned Space through existing admission/executors. Preserve shortcut-only geometry and original app-wide commands, native menu token cleanup and regular-menu behavior; retain valid Spaces sessions with empty grids. User verified; final review, fixture syntax, formatter/diff and signed source/installed-binary/running-path checks passed. Automated suites and exhaustive native/fault coverage unrun. All three stages complete; fullscreen-app quit collapse deferred. | Feature / Spaces / Shortcuts | 16 |

Coverage ends at `0646272e65ce81219092d964abf3d0decdc29bf6`. The following ledger-only commit cannot record its own final hash; add it at the next ledger update. No uncommitted feature work remains from this plan.

| [`e426e35e`](https://github.com/hexcrete/DockFork/commit/e426e35e4898bef6d388040eb23c00b4a65b2775) | Record the completed Space-targeted shortcut stage's exact commit, purpose and file count; verify unique ledger coverage through the feature commit and disclose the ledger-only boundary. | Documentation / Ledger | 1 |

Coverage ends at `e426e35e4898bef6d388040eb23c00b4a65b2775`. Fullscreen-Space removal preservation is uncommitted and outside this boundary.

| [`55bb4ae4`](https://github.com/hexcrete/DockFork/commit/55bb4ae4c69125ab859191b83683f78b9992217f) | Preserve visible Spaces switcher sessions for topology-only notifications and automatic fallback from removed fullscreen Spaces; reconcile a removed highlight/filter to a valid same-display current Space. Reuse the shared notification/query, remove the redundant observer and retain disabled/inactive query gating. User verified Quit; final review, signed development/source/binary/running-path, fixture syntax and formatter/diff checks passed. Related native removal/display/fault variants and automated suites unrun. | Fix / Spaces / Lifecycle | 10 |

Coverage ends at `55bb4ae4c69125ab859191b83683f78b9992217f`. The following ledger-only commit cannot record its own final hash; include it in the next update. No pending implementation changes remain for this fix.

| [`93a75d69`](https://github.com/hexcrete/DockFork/commit/93a75d69baace3c7d08938ac55c5c79d5fd87cd9) | Record the fullscreen-Space removal fix's exact hash, purpose and file count; verify complete unique coverage through the fix and disclose the ledger-only boundary. | Documentation / Ledger | 1 |

Coverage ends at `93a75d69baace3c7d08938ac55c5c79d5fd87cd9`. Spaces Bar refresh optimization Stage 1 is uncommitted and outside this boundary.

| [`784490d8`](https://github.com/hexcrete/DockFork/commit/784490d8bc86c8f98fe9becc98d514b9003063db) | Coalesce cache/frame Spaces Bar refresh requests on the next main turn with merged strength, weak capture and session/token checks. Invalidate queued work for immediate refresh, teardown and terminal hide. User verified; final review, three focused suites, formatter/diff and signed development/source/binary/running-path checks passed. Deterministic fixture entries reduced 6-to-1; no native wall-clock speedup claimed. | Performance / Spaces / Refresh | 10 |

Coverage ends at `784490d8bc86c8f98fe9becc98d514b9003063db`. Refresh optimization Stage 2 is uncommitted and outside this boundary.

| [`3b187f49`](https://github.com/hexcrete/DockFork/commit/3b187f4914200555d932add5e50e46c9f4463677) | Separate Spaces Bar layout, resident/order and topology refreshes with merged reasons. Retain complete presentation metadata across single-Space hiding, preserve an independent notification baseline and keep real-cache/action-time freshness. Wire appearance/sort/native-tab controls explicitly. User verified; review, four focused suites, formatter/diff and signed development/source/binary/running-path checks passed. Warm UI provider counts are zero queries/reads/model builds; no native latency claim. | Performance / Spaces / Presentation | 13 |

Coverage ends at `3b187f4914200555d932add5e50e46c9f4463677`. Prepared-layout measurement reuse Stage 3 is user-verified and approved after final review. The commit containing this record is outside this boundary; record its exact hash, purpose and changed-file count in the next ledger update. Its validation retains the unresolved unchanged native Compact drag fixture failure, alongside passing Spaces/keyboard/selection-range suites and deterministic geometry checks.

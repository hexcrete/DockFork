# DockFork Complete Commit Ledger

Audit snapshot: fork `9efa1cc188ff3a1f64556360ca18ef2f1d41a857`; upstream `0bd2e46bb2c56d3bdb121883190728103fab3c99`.

The original frozen inventory covers **192 branch-only commits: 189 non-merge and 3 merge commits**, ending October 8, 2026. The continuation below covers thirteen later commits through `6c51d22ae902887123d6be0f1e9403bf6dd701a2`: **205 total, 202 non-merge and 3 merge commits**. Category totals below describe the original snapshot; the continuation is counted separately. Subsequent documentation edits are not yet included in these totals.

The inventory uses each commit's patch, changed-file list, added declarations/settings, and the current implementation for user-facing claims. It is a historical/documentation audit, not a fresh safety or performance certification of every intermediate revision. A Git patch-equivalence check found no exact equivalent among the 189 non-merge commits against the chosen upstream snapshot; that does not mean every broad feature concept is unique to this fork.

Read [Changes and Showcase](CHANGES_AND_SHOWCASE.md) for final behavior and [Capture Checklist](SHOWCASE_CHECKLIST.md) for visual candidates. Commit links target the planned `hexcrete/DockFork` repository and will become usable once this history is published. Locally, inspect any entry with `git show <commit>`.

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

Coverage: `9efa1cc..6c51d22`, reviewed October 9, 2026. These commits are recorded once here rather than inserted into the frozen category tables. Fork-only documentation/build assets are excluded from upstream PRs; the application-default change is separate and still requires upstream compatibility review.

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

## Upstream Attribution and Contribution Boundaries

The three merge entries integrate upstream capabilities and fix merge interactions; they are not ownership claims over upstream's contributions. In particular, the base swipe launcher and latest JSON backup/import support came from upstream. Attribution in the guide distinguishes those from fork refinements.

Preserve this history in the public fork. When proposing upstream contributions, prepare small dependency-aware branches after agreeing scope; do not assume an early commit can be cherry-picked onto current main unchanged. Existing upstream contribution instructions require human review, testing, and AI disclosure.

## Regenerating the Inventory

Use the exact baseline and explicit coverage tip above, not a moving `origin/main..HEAD` range. Read `git log --reverse`, each patch and changed-file list, and compare final code/settings with the baseline. Require exactly one primary category per commit, no omissions, and no duplicate entries. Preserve the frozen inventory and extend the continuation for later development; update its tip and totals explicitly. Record the ledger-maintenance commit itself in the next update, since it cannot contain its own final hash.

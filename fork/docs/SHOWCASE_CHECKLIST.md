# DockFork Showcase Capture Checklist

Current capture plan, reviewed November 4, 2026 against the Settings merge repairs and example interactions through `e21fe4a2`. This is a menu of screenshots and short recordings, not a development/test diary. Implementation history and validation belong in the [commit ledger](COMMIT_LEDGER.md); feature explanations belong in [Changes and Showcase](CHANGES_AND_SHOWCASE.md).

## Capture Status

All existing capture IDs and unchecked states are preserved. Screenshots and recordings remain deferred; no media is marked captured or approved. Selection M01/M02 and menu M01/M02 retain their original IDs; qualify them by section.

Published stable [0.5.0](https://github.com/hexcrete/DockFork/releases/tag/v0.5.0) includes the current Settings. Use that package or a reviewed development build and label the exact source accurately; do not present its Settings as shipped 0.4.0 UI. Use the published package and its attached preset only for release-specific captures. Record the exact version/source used.

The maintained preset is the sanitized November 4 export included with 0.5.0: 270 preferences, 15 generic-ID shortcut rows and no retired keys. Import is optional and replaces settings; export a backup first. Published 0.4.0 retains its attached historical preset. Capture selections and approval states remain unchanged.

## Current Settings Locations

| Capture setup | Current location and structure |
|---|---|
| Primary initializer, Backward/Selection/Search Trigger keys | Keybinds > Window Switcher Shortcuts |
| Alternate, Persistent and last-focused launchers | Keybinds > Alternate Shortcuts: one list with Double-tap, Persistent, No Highlight and Quick Switch; no separate Persistent or Switch to Last Focused Window section |
| Preview action assignments | Keybinds > Window Preview Keyboard Shortcuts: assignment left, action right, Remove per row; Add and Reset to Defaults below |
| Menu-bar click behavior | Keybinds > Menu Bar Icon > Clicks trigger: |
| Selection and summary | Keybinds > Window Selection |
| Auto Tile and linked resizing | Keybinds > Tiling: Auto Tile maximum rows/columns and Auto Tile only what fits share the existing section |
| Space movement, numbering and cycle bindings | Keybinds > Spaces: one section, including the numbered-shortcut explanation and Allow Space-cycle shortcuts to open the switcher |
| General action popups | Appearance > Action Feedback |
| Mouse Followed Focus popup | Window Switcher > Behavior > Mouse follows focus > Show feedback popup; requires action feedback and a non-Never focus mode |
| Spaces Bar behavior | Window Switcher > Spaces Bar |
| Spaces Bar appearance | Appearance > Spaces Bar: Item Size, app icons, Labels, Fixed/Flexible and icon limits or Fixed width |
| Trackpad activation and excluded opening directions | Window Switcher > Trackpad Swipe for Window Switcher |
| Preview mouse actions and drag-to-tile | Gestures > Mouse Actions |
| Title-bar gesture exclusions | Gestures > Options |
| Space/state placement | Each mode's Window State Indicator section, not a global legacy badge toggle |
| Dock locking and spring-loading delay | Advanced |
| Folder widgets | Widgets |

Double-tap currently selects one modifier and its side. Ordinary key shortcuts support combined modifiers. Quick Switch uses the row's scope and disables Persistent/No Highlight without erasing their values. Settings screenshots should show these distinctions, compact clash glyphs with hover help, dependent-row indentation and reset glyphs only where the upstream control type uses them.

Pinned examples are a fork-specific appearance demonstration: hover the cards, titles/icons and traffic lights, then toggle sample checkboxes with selection enabled. Dimming must remain until the buttons themselves are hovered; test their visible edges after scaling. For On title hover, move over the title in Dock/Cmd+Tab or the app icon in Compact Mode. The two sample windows remain unchanged by real window activity; example controls never activate, close, resize or otherwise operate on real windows. Include the settings immediately below the examples in K01 to show their bounded interaction area. No new capture ID or completion state is added.

## Capture Conventions

- Use harmless sample titles, files, browser pages, calendars and music. Hide notifications and redact account, license and private diagnostic details.
- Record appearance, keyboard layout and relevant settings. Label upstream capabilities, fork additions and development-only UI accurately.
- Use PNG for static layout and short MP4 for interactions. Capture light/dark appearance where relevant; choose representative modes rather than duplicating every recording.
- Use disposable targets for Close, Quit, Force Quit, Space/content movement and tiling. Do not rearrange working windows or reset live preferences for media.
- No preset import, temporary mock edit, capture completion or media approval is implied by this checklist.
- Do not claim measured smoothness, signature trust or permissions behavior from screenshots. Keep builds, automated checks and debugging notes out of capture rows.

## Window Selection

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | M01 | Screenshot: selection controls | Enable Keybinds > Window Selection. Show checkboxes in Dock, Cmd+Tab and regular/Compact Window Switcher, including checked-only visibility. Compare Default, Popover and Shadowed headers and selection summaries; include a side Dock near the menu bar and narrow containers. | `fa76e57`, `a4150a5`, `4ff8ddd`, `272f6e4` |
| [ ] | M02 | Video: ordered checks and session pinning | Check windows in order, filter some out, then show Select All, Clear Selection and Tile Windows. Demonstrate Shift-click, checkbox sweeping/reversal and held-selection-key arrows. Narrow the summary: trailing icons disappear, the count shortens, buttons become glyphs, then the row scrolls. Compare keep-open On/Off. | `fa76e57`, `a4150a5`, `4ef5a08`, `4a76bfd`, `d89cbc5`, `ec1e9fa` |
| [ ] | MG01 | Video: checked-group actions | Use disposable windows to compare checked versus unchecked initiators, Minimize/Un-minimize, app-wide Hide/Unhide, Close, Quit and Force Quit. Show mixed-state intent, fullscreen exclusions and selection-aware menu titles. Include a windowless app: only its supported app actions participate. | `c827932` |
| [ ] | MG02 | Video: checked-group dragging | Drag a checked group and contrast an unchecked single window. Show shared Compact/Space-style drag cards, app grouping with subscripts, +N overflow and the target-aware leading symbol. Include the centered label over a single-window miniature, free placement, window tiling and Space destinations. | `86c3306`, `313e213` |
| [ ] | MT01 | Video: automatic and directional tiling | Open Keybinds > Tiling: Auto Tile maximum rows, Auto Tile maximum columns, Auto Tile only what fits, Fill-to-Auto-Tile and linked resizing share this section. Show directional layouts, overflow stacking versus untouched extras, first-selected foreground order and linked edges. Use disposable windows across Spaces. | `3b4d311`, `a23c0d6`, `6ae187c`, `c15292f`, `ff52d9ca` |
| [ ] | MS01 | Video: scripted ordered window lists | Use ordered AppleScript window lists for Minimize/Restore, Hide/Unhide, geometry and Space movement, with duplicate IDs and destination-following On/Off. Show real targets and resulting order; redact identifiers. Scripting does not show interactive feedback popups. | `d5bdb48` |
| [ ] | MT02 | Video: drag previews onto previews to tile | Enable drag-to-tile under Gestures > Mouse Actions. Drop a single window onto another, a checked group onto an unchecked target and an unchecked window onto a checked group. Show target highlighting and the tile glyph; contrast ordinary drag-away placement. | `86c3306`, `7a6ec7d` |

## Search Clear Button

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | SC01 | Video: native search clear control | Filter by typed text and quick filtering, then use the native trailing clear control. Show restored results, retained text focus and typing immediately afterward. Include reopening, long input and both appearances. | `d0740c3` |

## Cmd+Tab First-Use Hint

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | CT01 | Video: one-time preview-focus hint | On an explicitly authorized disposable profile, show the one-time preview-focus hint, then hover/focus a preview and reopen Cmd+Tab. The hint stays dismissed. Do not reset live preferences to recreate onboarding. | `be91733` |

## Compact and Windowless Cards

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | W01 | Screenshot pair: independent compact width | In Appearance > Compact Mode, change compact width while leaving regular preview width unchanged. Capture the same window set in both layouts. | `e3b7a83` |
| [ ] | W02 | Screenshot: compact state/title formatting | Show normal, minimized, hidden and windowless entries. Compare title/state placement, content dimming, readable card material and independent outer/card background visibility. | `2a79e61`, `c95f197`, `628ddde` |
| [ ] | W03 | Screenshot grid: placeholders | Compare Show full size placeholders in Dock and Cmd+Tab, embedding and dynamic sizing. Full-size placeholders keep enabled app headers; compact-style placeholders omit them. Show supported placeholder actions and the transition to a real preview. | `7b2491a`, `7368daf`, `717c1e0`, `0b961e1`, `e2667b3` |

## State and Space Controls

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | I01 | Screenshot: state indicator variants | In each mode's Window State Indicator settings, compare Space placement Off, On Window Previews and Next to Traffic Light Buttons independently of state placement. Show regular/Compact layouts without duplicate numbers. | `411618f`, `20d3b2f`, `356af10` |
| [ ] | I02 | Screenshot: current-Space highlight | Enable a Space indicator and Highlight Current Space in each mode. Compare current and other Spaces, legacy badges and toolbar indicators. Space placement defaults Off; highlighting defaults On. | `6248aab` |
| [ ] | I03 | Screenshot matrix: control ordering | Swap indicator/traffic-light order, including the Compact-only option; compare styled/unstyled and embedded/separate controls. Reveal hover-only traffic lights beside a wide indicator without compressing its contents. | `b435c0a`, `f7b64c9`, `9ce4a89`, `ba71716`, `09a2cc2` |
| [ ] | I04 | Screenshot: font and small rows | Compare indicator font sizes and small Compact rows, current-Space outlines and rounded/unstyled presentations. Keep rings, symbols and labels fully visible. | `f933cd0` |

## Spaces

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | S01 | Screenshot pair: destination menu | Open the shared Space destination menu with empty/populated Desktops and a fullscreen Space. Compare names/numbers, app icons, Current badge, unavailable destinations and window-sort ordering. Show the shared Exit Full Screen menu for a fullscreen source. | `cdd7b82`, `5adb65f`, `381e839` |
| [ ] | S02 | Video: move and optionally follow | Move disposable normal, minimized and hidden windows. Compare Keybinds > Spaces > Switch to the destination Space after moving the window On/Off, including Bring to Current Space. | `cdd7b82`, `30b66fc` |
| [ ] | S03 | Video: physical numbered shortcuts | In Keybinds > Spaces, show cycle bindings, launcher permission and numbered shortcuts in one section. Move highlighted windows and navigate with no window target; show effective modifier hints. Demonstrate physical number keys, including Czech layout if available. | `1c4ce38`, `2898dc6`, `ff52d9ca` |
| [ ] | S04 | Video: exit fullscreen from picker | Use Exit Full Screen from the indicator dropdown and Space-pill context menu. Contrast a focused and unfocused source, retaining the preview session where supported. | `0dce6a7` |
| [ ] | S05 | Screenshot/video: multi-display grouping | With separate Spaces on two displays, show grouped destination menus, current-Space markers and cross-display movement. Coordinate this with SB04 rather than duplicating its bar footage. | `cdd7b82`, `1c4ce38` |

## Spaces Bar

The following dedicated IDs cover bar interactions previously described only in dated notes. They are new candidates, not completed captures. Desktop creation/deletion, native Space reordering and drop-to-create-fullscreen/Split View are not part of this feature.

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | SB01 | Screenshot pairs: layout and sizing | Enable Window Switcher > Spaces Bar. In Appearance > Spaces Bar compare all seven Compact-matched heights, Numbers/Names and Fixed/Flexible. Flexible uses Minimum icons 0-10 and Maximum icons 0-20, default 2/6; a known single-window fullscreen pill omits +1. Show card backgrounds, corners, app subscripts and optional notification badges. | `9b7b2b2f`, `0fbeb3d8`, `ff52d9ca` |
| [ ] | SB02 | Video: navigation and focus | Configure Keybinds > Spaces cycle bindings; compare Start on next Space and Sequential/Recently used. Show Left/Right Space navigation, Down to windows, typing back into search and held-modifier release. Include opposite-axis swipes and app-icon activation versus background Space switching. | `aea03098`, `ff52d9ca` |
| [ ] | SB03 | Video: manual and automatic filtering | Compare Automatically filter windows by highlighted Space Off/On. Show magnifier, x and the shared header's Show All; retain search and outside-view checked windows. Include empty Spaces, clear/re-entry and the six-stage narrow-header fallback. The empty-Space exclusion setting is not present. | `f00f7e0d`, `ff52d9ca` |
| [ ] | SB04 | Video: displays and scrolling | Show display dividers, pinned display headings, overflow fades, inertia, edge zones and keyboard reveal. Compare grid/search/bar spacing with search enabled/disabled. Move a disposable window across Spaces and connect/disconnect an available display to show current contents. | `5928725b`, `cff1ffbd`, `ff52d9ca` |
| [ ] | SB05 | Video: window and Desktop-content drops | Drop selected windows onto Desktop pills without changing their geometry. Drag a Desktop from icons or background: show the shared ghost glyph, animated gaps, move/swap and directional content shifting across display boundaries. Fullscreen slots remain unavailable; contents move, not wallpapers, native order or app assignments. | `0d11655b`, `1bb51e3b`, `44ef9e3a`, `5928725b` |
| [ ] | SB06 | Screenshot/video: Space context actions | Right-click anywhere in a pill, including app icons. Show native symbols, shared destination dropdowns, selection-independent resident actions and shortcut hints. Auto Tile is in the main window-action group, with no Arrange submenu; fullscreen pills offer supported actions and Exit Full Screen. | `8ffb3137`, `ff52d9ca` |

## Shortcut Configuration

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | K01 | Video: configure rows before recording | In Keybinds, show preview-action rows with assignment left, action right and Remove at the end; Add and Reset to Defaults share the footer. Compare Alternate Shortcuts, the Search Trigger Key reset alignment and compact clash glyphs beside assignments. Show controls immediately below pinned previews. | `6b62149`, `94b4361`, `93074e7`, `aea03098`, `e21fe4a2` |
| [ ] | K02 | Screenshot: scope catalog | Show the shared scope picker in Alternate Shortcuts, its trailing alignment and Defaults versus All Windows. Change scope without replacing the row or trigger. | `94b4361`, `d2d063c`, `982c6d0`, `aea03098` |
| [ ] | K03 | Settings screenshot + video: modifier side | Show combined initializer modifiers, Left/Right/Either, inherited-side override and side-aware Backward Key recording. Use harmless bindings; demonstrate exact Shift matching and capture/cancel without executing an app action. | `d013ee1`, `428b2af`, `aea03098` |
| [ ] | K04 | Video: unified alternate shortcut modes | Use the unified Alternate Shortcuts editor: modifier/key/scope on the first row and Double-tap, Persistent, No Highlight and Quick Switch below. Contrast ordinary multi-modifier triggers with the single-modifier/side Double-tap picker. Show tooltips and no activation after a single tap; include the shared explainer covering inheritance, Persistent, Double-tap and Quick Switch. | `19d4888`, `af0bbcd`, `06c9471`, `aea03098` |

## Persistent, Swipe, and MRU Sessions

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | P01 | Video: menu-bar click assignment | In Keybinds > Menu Bar Icon, show Clicks trigger: and assign opposite buttons to the app menu and persistent switcher. Repeat opening/closing through the assigned button. | `c9adbf9`, `c46bfae`, `aea03098` |
| [ ] | P02 | Video: persistent mouse-first session | Enable Persistent on an Alternate Shortcuts row, release its modifiers and continue with search and actions. Compare No Highlight On/Off. No Highlight also applies to nonpersistent rows. | `19d4888`, `2898dc6`, `1571630`, `aea03098` |
| [ ] | P03 | Video: swipe/keyboard ownership | In Window Switcher > Trackpad Swipe for Window Switcher, show activation-direction exclusions, three/four fingers and the opposite-axis Spaces option. Demonstrate permitted opening, unrestricted navigation after opening, keyboard takeover and owning-session release. Respect remaining macOS gesture assignments. | `78bfbf6`, `ae93b49`, `1f72ecb`, `aea03098` |
| [ ] | P04 | Video: reverse selection | Compare horizontal and vertical swipe navigation with reversal On/Off. Show the first backward Space highlight respecting Start on next Space, then continued navigation. | `7797cdf`, `aea03098` |
| [ ] | R01 | Video: scoped Quick Switch | Enable Quick Switch on an Alternate Shortcuts row. Show Persistent and No Highlight greyed while Double-tap and scope remain available. With three harmless windows, demonstrate scoped last-focused switching without opening the switcher; there is no separate last-focused settings section. | `af0bbcd`, `69507bc`, `bfaf5f4`, `aea03098` |

## Window Actions and Menus

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | A01 | Video: Dock window cycling | In Dock Previews, compare repeated active-app window cycling with inactive, single-window and windowless app clicks. Show optional preview retention and active-border changes. Dragging the Dock icon still reorders it rather than cycling windows. | `28075b2`, `dc5a805`, `b7faf95`, `2f9d492` |
| [ ] | A02 | Video: bulk actions and header buttons | Use Dock/Cmd+Tab app-header Close All and Minimize All/restore on disposable windows. Header actions remain app-wide despite checked selection. Narrow the header to show glyph and scroll fallbacks while app names follow Long title overflow and eventually disappear. | `ffa82dd`, `4743b0e`, `df7bf47`, `dc77296` |
| [ ] | A03 | Screenshot/video: post-action choices | In Keybinds > Keep previews open after action, compare dismissal categories and the independent foreground preference. Use one harmless geometry action with keep-open/foreground On and Off. | `bef9786`, `26f33aa` |
| [ ] | M01 | Screenshot: enriched context menu | Show selection-aware action titles, Open Window (This Window), app-wide wording, normal Quit versus explicit Force Quit, symbols and effective shortcut hints. Compare Arrange and Move to Space with the shared More menu. | `16a68eb`, `5ef868b`, `5532376` |
| [ ] | M02 | Video: menu actions in each session | Invoke an action while its native preview menu is open. Compare held Alternate Shortcuts, Persistent sessions and Cmd+Tab modifiers. Menu-bar window actions remain single-target and omit shortcut hints. | `5532376`, `5d50fd8`, `be73708`, `ccfec9d` |

## Layout and Search

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | L01 | Video: horizontal/vertical grids | Compare horizontal and vertical overflowing grids with regular and Compact previews. Show alignment/offsets, all enabled companion elements and narrow/tall screen limits. | `19b3ddd`, `8af3b00`, `f4ccf61` |
| [ ] | L02 | Video: edge auto-scroll | Show edge-scroll zones and fades, then two-finger inertia without edge-scroll interference. Compare Center selection during keyboard navigation out of view On/Off: centered scrolling versus full-card minimal reveal with scaled padding. | `bbb44ad`, `08c52c6`, `f7e5a12`, `295ef75` |
| [ ] | L03 | Screenshot/video: search placement and focus | Show the search field between Spaces Bar and grid with even spacing, then without the bar. Type, clear and change Space filters while the grid shrinks/grows; repeat with search disabled. | `586407f`, `9151f2d` |
| [ ] | L04 | Video: windowless-to-window transition | Hover a windowless Dock/Cmd+Tab app, open a disposable first window and close it again. Show container resizing and the header behavior for compact-style versus full-size placeholders. | `c802975` |

## Full-Size Previews

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | F01 | Screenshot pairs: opacity/blur/border | Use harmless patterned wallpaper to compare full-size preview opacity, backdrop blur and border. Show regular/Compact origins without implying the screenshot itself is blurred. | `97096c7` |
| [ ] | F02 | Video: fade durations | Compare immediate and longer full-size-preview fades with Reduce Motion Off, then show reduced motion. Highlight another target quickly: the old preview hides while fresh geometry is resolved. | `3c0cf89` |
| [ ] | F03 | Optional video: resting fade | Enable resting fade for the intended mode. Rest, then move across neighboring cards: grid, search and Spaces Bar fade/restore together. Compare Off and normal opacity, including title controls and keyboard takeover. Do not label the setting experimental. | `c2fa95d`, `220464d` |

## Dragging

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | D01 | Video: compact and regular preview dragging | Drag from the noninteractive body of regular and Compact previews. Show window placement, target-aware ghost and cleanup. Contrast checkbox sweeping and presses on traffic lights/Space/More controls, which do not start window movement. | `a7d61d1`, `78f65dd` |
| [ ] | D02 | Optional video: cross-display drag | With two displays, drop a large disposable window on the smaller display and show fitting/clamping within its usable area. Show the move-to-current-Desktop symbol outside the switcher. | `78f65dd` |
| [ ] | D03 | Video: external drag spring-loading | Drag a disposable file onto a real Dock preview and wait for spring-loading, then complete the native drop. Show custom delay under Advanced and cancellation by leaving early. Include click-drag or three-finger drag as available. | `1ceb007`, `ba665c2` |

## Action Feedback

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | AF01 | Video: optional action feedback | Enable Appearance > Action Feedback. Compare all four positions, cursor-following and preview/Compact placement, brief action labels and shared native fades. Use a naturally pending action to show its delayed spinner and subsequent success symbol; fast actions retain their original symbol. | `70d56b90`, `aea03098`, `ff52d9ca` |
| [ ] | AF02 | Video: batch progress and consolidation | Act on several disposable windows: show aggregate settled/total progress, per-preview feedback and consolidation at the cursor when previews disappear. Hide/Unhide counts apps, not windows. Include native-tab Close progress and keep action labels concise; do not promise counters animate one item at a time. | `70d56b90`, `aea03098` |
| [ ] | AF03 | Video: Mouse Follows Focus cursor hint | Enable Appearance > Action Feedback, then Window Switcher > Behavior > Mouse follows focus and its Show feedback popup option. Activate a different target and show Mouse Followed Focus at the new pointer location. Compare the hint Off; it remains cursor-positioned regardless of the general popup position. | `4ad22fc1`, `c5d64dc6`, `aea03098`, `ff52d9ca` |

## Reliability and Diagnostics

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | B01 | Video: native tab grouping | Use disposable Finder windows with differently named folder tabs, including a separate same-sized window. Show collapsed tabs staying grouped through Minimize/Restore and Hide/Unhide, activation returning to the selected tab, and Close removing the intended tab stack. | `4f703ed`, `abdc4ec`, `6fb1946`, `8ede8d0`, `29de103a`, `e7fe0ba9` |
| [ ] | B02 | Video: fullscreen metadata | Show ordinary fullscreen and Split View state/Space labels, including a Mission Control-created fullscreen Space. Compare supported preview controls and the Space-pill Exit Full Screen action. | `e2e4c45`, `a94bb4d`, `1a5a978` |
| [ ] | B03 | Screenshot: actionable nonstandard windows | Show a harmless nonstandard window, such as Calendar Info, with supported controls only. Optionally show a Wine/CrossOver window: native macOS fullscreen differs from game fullscreen; unsupported actions remain absent after Hide/Unhide. Use a public game screen with no account details. | `804d85a`, `288262b` |
| [ ] | B04 | Optional temporary fixture: missing image | Optional controlled fixture only: omit one settings mock screenshot, compare regular/Compact layouts, then restore the fixture before any release or ordinary capture. | `6fe02cc`, `717c1e0` |
| [ ] | H01 | Screenshot: diagnostic controls | Show log export and size-cap settings without opening private log contents. Do not include diagnostic output in feature media. | `77ee4d3` |

## Visual Polish and Automation

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | V01 | Screenshot pair: app badges | Use an app with a genuine Dock badge. Compare visibility/size in regular, Compact and Spaces Bar icons while alignment stays unchanged. | `424c16c` |
| [ ] | V02 | Screenshot: compact widgets and clipping | Show calendar/media widgets beside Compact rows with aligned edges and rounded clipping. Folder-widget settings are under Widgets. | `a9f400a`, `9c7ac61`, `ef27fdf` |
| [ ] | V03 | Video: traffic-light visibility animation | Compare traffic-light visibility at zero/positive animation duration, dimmed/hidden modes and Reduce Motion. Include regular/Compact previews in each mode without presenting a mock as a live window. | `b4ce12a`, `1aebbc5`, `1f7ce92`, `ae79432` |
| [ ] | V04 | Screenshot pair: mirrored title cluster | Compare left/right mirrored title clusters, automatic versus explicit icon sizing and windowless/unnamed cards. Use bright/dark screenshots in both appearances for title contrast; do not imply every mode has a title icon. | `82a8449`, `bdc62ae` |
| [ ] | V05 | Video: adaptive preview controls | Narrow regular/Compact previews: titles shorten/disappear, rightmost traffic actions enter More, then Space/state controls consolidate. Show the preserved left prefix, returning titles, reachable checkbox and selected outline. Compare styled/unstyled, hover-only controls and Reduce Motion. | `48b7f64`, `e264839`, `4d6c4c2` |
| [ ] | T01 | Example/video: scripted Spaces | List Spaces, move a disposable window and switch by returned number/ID. Include content move/swap/shift commands where useful; redact IDs and do not imply native Desktop identities are reordered. | `92908e2`, `da9f3f3` |
| [ ] | T02 | Example/video: scripted switcher | Use tell application "DockFork" to open the shared switcher, including optional spaces focused. Show normal filters/windowless choices and require the Spaces Bar to be enabled for Space-focused launch. | `4d38e51`, `ac90770` |

## Title-Bar Gestures

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | G01 | Video: scrolling and title-bar gesture exclusions | In Gestures > Options, enable Disable title bar gestures over scrollable areas and tabs, then compare Use stricter title bar detection Off/On. Show Firefox/Brave tab-strip scrolling and gestures on recognizable title bars. Explain the stricter option's conservative treatment of blank title-bar areas; do not imply app-specific detection. | `20fc4cbb`, `ff52d9ca` |

## Fork Setup and Defaults

| Pick | ID | Capture | Setup and visible result | Commits |
|---|---|---|---|---|
| [ ] | Q01 | Screenshot pair: added-feature defaults | Use an explicitly authorized disposable profile, not a live reset. Distinguish factory defaults from the showcase preset: Space indicators Off with Highlight Current Space On; Spaces Bar Off, Medium, Flexible, 2/6 icons and 160-point Fixed width. | `0127698`, `aea03098` |
| [ ] | Q02 | Optional video: showcase preset | Back up settings before any explicitly approved preset import. Use the export appropriate to the captured version; the published 0.4.0 preset is not a current shortcut configuration template. Recreate current Alternate Shortcuts deliberately; do not silently overwrite the curated preset. | `287c38f`, `9fcf28d`, `aea03098` |
| [ ] | Q03 | Screenshot: fork/upstream version identity | In the captured app's Support > Updates, show distinct DockFork and incorporated DockDoor versions/commits. Current development incorporates 1.42.2; the published 0.4.0 package retains its own embedded base. Read the installed metadata rather than assuming they match. | `b674d9c`, `aea03098`, `ff52d9ca` |

## Capture Review

Before approving selected media, check the displayed settings paths and wording against the captured build, confirm that no private content is visible, and attach the reviewed file to the corresponding feature in [Changes and Showcase](CHANGES_AND_SHOWCASE.md). Keep every unused or unrecorded candidate unchecked. Build/install records and technical regressions do not require new screenshot IDs.

November 4 upstream update adds no visual capture candidate. Existing Settings examples, capture IDs and unchecked states remain unchanged; do not present the upstream beta appcast entry as a new DockFork release.

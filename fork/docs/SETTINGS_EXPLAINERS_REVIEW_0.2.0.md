# Settings explainer review for DockFork 0.2.0

Edit the text inside each `text` block. Leave entry IDs and source references unchanged so the edits can be applied reliably. Unchanged blocks will keep their current wording. To remove an explainer, replace its block contents with `[REMOVE]`.

The fork additions below contain the user-edited wording after grammar review, applied to the settings UI and search catalog. The upstream appendix is unchanged. One block covers each shared UI explainer, even when multiple settings use it. Titles are supplied for context; the editable blocks contain the explainers only.

Compared with published DockFork 0.1.0, tag `v0.1.0`, source `36e635e8f0ad35cdd90fb390b3aa0195cefdd8b2`. Comparison source snapshot: `ddb9f8c07eb6ae7c26fd4bdb33e42ca5d2668273`. Prepared October 16, 2026.

There are 35 text blocks: 10 fork additions and 25 upstream additions or search descriptions. Unchanged explainers moved between tabs are excluded. The upstream appendix is included for completeness; it is not fork-authored text. Existing settings without new or revised helper text are excluded.

Only helper text changed when applying this review. Settings behavior, defaults, and saved preferences are unchanged.

## Fork additions

### E01. Enable dragging windows together to tile them

Location: Keybinds > Mouse Actions

Search IDs: `gestures.enableWindowDragTiling`

Source: [DockDoor/Views/Settings/Gestures/MouseActionsSection.swift:41](../../DockDoor/Views/Settings/Gestures/MouseActionsSection.swift#L41)

```text
Drag a window preview onto another preview to tile them on the target window's Desktop. Checked windows are included in selection order.
```

### E02. Enable multi-window selection

Location: Keybinds > Window Selection

Search IDs: `gestures.enableMultiWindowSelection`

Source: [DockDoor/Views/Settings/KeybindsSettingsView.swift:32](../../DockDoor/Views/Settings/KeybindsSettingsView.swift#L32)

```text
Select windows using checkboxes or the Toggle Window Selection action.
```

### E03. Keep Window Switcher open when windows are selected

Location: Keybinds > Window Selection

Search IDs: `gestures.keepWindowSwitcherOpenWhenSelected`

Source: [DockDoor/Views/Settings/KeybindsSettingsView.swift:39](../../DockDoor/Views/Settings/KeybindsSettingsView.swift#L39)

```text
Keep selected windows available after releasing the initializer modifier or finishing a swipe. When disabled, selecting windows does not change the session's normal dismissal behavior. Dock and Cmd+Tab previews keep their normal dismissal behavior.
```

### E04. Show selection summary

Location: Keybinds > Window Selection

Search IDs: `gestures.showWindowSelectionSummary`

Source: [DockDoor/Views/Settings/KeybindsSettingsView.swift:45](../../DockDoor/Views/Settings/KeybindsSettingsView.swift#L45)

```text
Show the selection count with Select All, Clear Selection, and Tile Windows buttons.
```

### E05. Show unchecked selection checkboxes / Checkbox visibility:

Location: Keybinds > Window Selection

Search IDs: `gestures.showUncheckedSelectionCheckboxes`, `gestures.selectionCheckboxVisibility`

Source: [DockDoor/Views/Settings/KeybindsSettingsView.swift:60](../../DockDoor/Views/Settings/KeybindsSettingsView.swift#L60)

```text
Checkboxes remain visible while checked.
```

### E06. Link tiled windows when resizing

Location: Keybinds > Tiling

Search IDs: `gestures.linkTiledWindowsWhenResizing`

Source: [DockDoor/Views/Settings/KeybindsSettingsView.swift:93](../../DockDoor/Views/Settings/KeybindsSettingsView.swift#L93)

```text
Resize shared edges to resize neighboring windows tiled together. Drag a tiled window's title bar to restore its earlier size. Moving it to another Desktop or display detaches it.
```

### E07. Maximum tiling rows: / Maximum tiling columns:

Location: Keybinds > Tiling > Auto Tile

Search IDs: `gestures.maximumTilingRows`, `gestures.maximumTilingColumns`

Source: [DockDoor/Views/Settings/KeybindsSettingsView.swift:109](../../DockDoor/Views/Settings/KeybindsSettingsView.swift#L109)

```text
Limits apply to Auto Tile. Set both limits to 1 to move windows without resizing.
```

### E08. Tile only what fits

Location: Keybinds > Tiling > Auto Tile

Search IDs: `gestures.tileOnlyWhatFits`

Source: [DockDoor/Views/Settings/KeybindsSettingsView.swift:115](../../DockDoor/Views/Settings/KeybindsSettingsView.swift#L115)

```text
Arrange only the first windows that fit within the row and column limits, leaving extra windows unchanged. When disabled, extra windows stack behind earlier windows in the same cells.
```

### E09. "Fill" actions on multiple selected windows trigger "Auto Tile"

Location: Keybinds > Tiling

Search IDs: `gestures.fillActionsAutoTileSelection`

Source: [DockDoor/Views/Settings/KeybindsSettingsView.swift:87](../../DockDoor/Views/Settings/KeybindsSettingsView.swift#L87)

```text
Use actions such as "Fill Left Half" to arrange selected windows together, starting from that direction. When disabled, each window fills the requested area on its own Space.
```

### E10. Large tiling grid warning

Location: Keybinds > Tiling > Auto Tile

Source: [DockDoor/Views/Settings/KeybindsSettingsView.swift:120](../../DockDoor/Views/Settings/KeybindsSettingsView.swift#L120)

Shown when either maximum exceeds 3. This warning has no separate search entry.

```text
More than 3 rows or columns may not look good on some displays. Apps may enforce minimum window sizes.
```

## Upstream additions

### E11. Window Gestures introduction

Location: Gestures > Window Gestures

Search IDs: `windowGestures.enable`

Source: [DockDoor/Views/Settings/GesturesSettingsView.swift:62](../../DockDoor/Views/Settings/GesturesSettingsView.swift#L62)

```text
Snap, minimize and close windows with two fingers on your trackpad. Swipe or pinch on a window's title bar, a Dock icon or the menu bar.
```

### E12. Window Gestures scrolling note

Location: Gestures > Window Gestures

Source: [DockDoor/Views/Settings/GesturesSettingsView.swift:29](../../DockDoor/Views/Settings/GesturesSettingsView.swift#L29)

```text
While Window Gestures is on, two-finger scrolling on title bars, running Dock icons and the menu bar is used for these gestures.
```

### E13. Pinch requirement

Location: Gestures > Window Gestures

Source: [DockDoor/Views/Settings/GesturesSettingsView.swift:82](../../DockDoor/Views/Settings/GesturesSettingsView.swift#L82)

```text
Pinches need "Zoom in or out" turned on in Trackpad settings.
```

### E14. Double-tap requirement

Location: Gestures > Window Gestures

Source: [DockDoor/Views/Settings/GesturesSettingsView.swift:85](../../DockDoor/Views/Settings/GesturesSettingsView.swift#L85)

```text
Double-taps need "Smart zoom" turned on in Trackpad settings.
```

### E15. Sensitivity

Location: Gestures > Options

Search IDs: `windowGestures.sensitivity`

Source: [DockDoor/Views/Settings/GesturesSettingsView.swift:148](../../DockDoor/Views/Settings/GesturesSettingsView.swift#L148)

```text
Turn this up if gestures need too much finger movement.
```

### E16. More Gestures introduction

Location: Gestures > More Gestures

Source: [DockDoor/Views/Settings/GesturesSettingsView.swift:168](../../DockDoor/Views/Settings/GesturesSettingsView.swift#L168)

```text
Scrolling on Dock icons and title bars, swipes on previews, and a trackpad swipe for the window switcher.
```

### E17. Disabled legacy gesture note

Location: Gestures > More Gestures

Source: [DockDoor/Views/Settings/GesturesSettingsView.swift:178](../../DockDoor/Views/Settings/GesturesSettingsView.swift#L178)

```text
Window Gestures handles scrolling on Dock icons and title bars, so these two are off while it's on.
```

### E18. Space for a Custom Dock

Location: Gestures > Space for a Custom Dock

Search IDs: `windowGestures.dockSpace`

Source: [DockDoor/Views/Settings/GesturesSettingsView.swift:199](../../DockDoor/Views/Settings/GesturesSettingsView.swift#L199)

```text
Using a dock other than the macOS Dock? Keep a strip of the screen free so snapped windows don't cover it.
```

### E19. Swipe Sensitivity

Location: Gestures > Trackpad Swipe for Window Switcher

Search IDs: `gestures.trackpadSwitcherSwipeSensitivity`

Source: [DockDoor/Views/Settings/Gestures/TrackpadSwitcherSwipeSection.swift:69](../../DockDoor/Views/Settings/Gestures/TrackpadSwitcherSwipeSection.swift#L69)

```text
Higher values open the switcher and change the selection with shorter swipes.
```

### E20. Snap Left or Right

Location: Gestures > On a Window's Title Bar

Search IDs: `windowGestures.snapHalves`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:74](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L74)

```text
Swipe left or right on a title bar to fill that half of the screen.
```

### E21. Fill Screen

Location: Gestures > On a Window's Title Bar

Search IDs: `windowGestures.snapMax`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:75](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L75)

```text
Swipe up on a title bar to fill the screen.
```

### E22. Snap to a Corner

Location: Gestures > On a Window's Title Bar

Search IDs: `windowGestures.snapQuarters`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:76](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L76)

```text
Swipe sideways, then up or down, to fill a corner.
```

### E23. Minimize

Location: Gestures > On a Window's Title Bar

Search IDs: `windowGestures.windowMinimize`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:77](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L77)

```text
Swipe down on a title bar.
```

### E24. Close Window

Location: Gestures > On a Window's Title Bar

Search IDs: `windowGestures.windowClose`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:78](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L78)

```text
Pinch in on a title bar.
```

### E25. Close Tab

Location: Gestures > On a Window's Title Bar

Search IDs: `windowGestures.tabClose`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:79](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L79)

```text
Pinch in on a tab to close just that tab.
```

### E26. Full Screen

Location: Gestures > On a Window's Title Bar

Search IDs: `windowGestures.windowFullscreen`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:80](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L80)

```text
Pinch out on a title bar to enter or leave full screen.
```

### E27. Center Window

Location: Gestures > On a Window's Title Bar

Search IDs: `windowGestures.snapCenter`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:81](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L81)

```text
Double-tap a title bar to center the window at its earlier size.
```

### E28. Minimize Windows

Location: Gestures > On a Dock Icon

Search IDs: `windowGestures.appMinimize`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:82](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L82)

```text
Swipe down on a running app's Dock icon to minimize its front window.
```

### E29. Restore Minimized

Location: Gestures > On a Dock Icon

Search IDs: `windowGestures.appUnminimize`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:83](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L83)

```text
Swipe up on a Dock icon to bring back its last minimized window.
```

### E30. Quit App

Location: Gestures > On a Dock Icon

Search IDs: `windowGestures.appQuit`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:84](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L84)

```text
Pinch in on a running app's Dock icon to quit it.
```

### E31. Switch Apps

Location: Gestures > On the Menu Bar

Search IDs: `windowGestures.menubarAppSwitcher`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:85](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L85)

```text
Swipe left or right on an empty part of the menu bar to go to the previous or next app.
```

### E32. Minimize All Windows

Location: Gestures > On the Menu Bar

Search IDs: `windowGestures.menubarMinimize`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:86](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L86)

```text
Swipe down on an empty part of the menu bar to minimize every window on that display.
```

### E33. Restore All Windows

Location: Gestures > On the Menu Bar

Search IDs: `windowGestures.menubarUnminimize`

Source: [DockDoor/Utilities/Window Gestures/WindowGestureTypes.swift:87](../../DockDoor/Utilities/Window%20Gestures/WindowGestureTypes.swift#L87)

```text
Swipe up on an empty part of the menu bar to bring those windows back.
```

## Upstream search descriptions

### E34. Window Gestures

Location: Settings search > Window Gestures

Search IDs: `windowGestures.enable`

Source: [DockDoor/Views/Settings/Search/SettingsSearchCatalog.swift:814](../../DockDoor/Views/Settings/Search/SettingsSearchCatalog.swift#L814)

Search-only wording. The visible helper has its own entry above.

```text
Manage windows and apps with two-finger swipes, pinches and taps on title bars, Dock icons and the menu bar.
```

### E35. Space for a Custom Dock

Location: Settings search > Space for a Custom Dock

Search IDs: `windowGestures.dockSpace`

Source: [DockDoor/Views/Settings/Search/SettingsSearchCatalog.swift:875](../../DockDoor/Views/Settings/Search/SettingsSearchCatalog.swift#L875)

Search-only wording. The visible helper has its own entry above.

```text
Keep a strip of the screen free so snapped windows don't cover a custom dock.
```

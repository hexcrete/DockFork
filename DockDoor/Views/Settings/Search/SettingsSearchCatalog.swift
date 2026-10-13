import Foundation

enum SettingsSearchCatalog {
    static let items: [SettingsSearchItem] = generalItems + dockPreviewItems + windowSwitcherItems
        + cmdTabItems + dockLockingItems + appearanceItems + glassItems + gesturesItems + filtersItems
        + widgetItems + pinningItems + advancedItems + supportItems

    // MARK: - General

    private static let generalItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            id: "general.leaveReview",
            title: String(localized: "Leave a Review"),
            description: String(localized: "Share your experience on Product Hunt"),
            keywords: ["review", "product hunt", "rating", "feedback"],
            tab: "General",
            section: String(localized: "Support & Contributions"),
            icon: "star.bubble.fill"
        ),
        SettingsSearchItem(
            id: "general.launchAtLogin",
            title: String(localized: "Launch DockDoor at login"),
            keywords: ["startup", "boot", "open", "auto"],
            tab: "General",
            section: String(localized: "Application Basics"),
            icon: "power"
        ),
        SettingsSearchItem(
            id: "general.menuBarIcon",
            title: String(localized: "Show menu bar icon"),
            keywords: ["status", "tray", "menu"],
            tab: "General",
            section: String(localized: "Application Basics"),
            icon: "menubar.rectangle"
        ),
        SettingsSearchItem(
            id: "general.reduceMotion",
            title: String(localized: "Reduce motion"),
            keywords: ["animation", "animations", "motion", "accessibility"],
            tab: "General",
            section: String(localized: "Application Basics"),
            icon: "figure.roll"
        ),
        SettingsSearchItem(
            id: "general.sortMinimized",
            title: String(localized: "Sort minimized/hidden windows to end"),
            description: String(localized: "Minimized and hidden windows will appear after all visible windows in previews and switcher."),
            keywords: ["sort", "minimized", "hidden", "order"],
            tab: "General",
            section: String(localized: "Application Basics"),
            icon: "arrow.down.to.line"
        ),
        SettingsSearchItem(
            id: "general.activeAppIndicator",
            title: String(localized: "Show active app indicator below dock icon"),
            description: String(localized: "Displays a colored line below the currently active application's dock icon."),
            keywords: ["indicator", "active", "dot", "highlight", "color"],
            tab: "General",
            section: String(localized: "Active App Indicator"),
            icon: "line.horizontal.star.fill.line.horizontal"
        ),
        SettingsSearchItem(
            id: "general.indicatorColor",
            title: String(localized: "Indicator Color"),
            keywords: ["indicator", "color", "picker"],
            tab: "General",
            section: String(localized: "Active App Indicator"),
            icon: "paintbrush"
        ),
        SettingsSearchItem(
            id: "general.indicatorStyle",
            title: String(localized: "Indicator Style"),
            keywords: ["indicator", "style", "dots", "window", "count", "number"],
            tab: "General",
            section: String(localized: "Active App Indicator"),
            icon: "number.circle"
        ),
        SettingsSearchItem(
            id: "general.indicatorHighlightFrontmost",
            title: String(localized: "Highlight the frontmost app"),
            keywords: ["indicator", "dots", "frontmost", "dim", "gray", "contrast", "two colors"],
            tab: "General",
            section: String(localized: "Active App Indicator"),
            icon: "circle.lefthalf.filled"
        ),
        SettingsSearchItem(
            id: "general.indicatorAutoSize",
            title: String(localized: "Automatically set height and offset"),
            keywords: ["indicator", "auto", "height", "offset"],
            tab: "General",
            section: String(localized: "Active App Indicator"),
            icon: "arrow.up.and.down.text.horizontal"
        ),
        SettingsSearchItem(
            id: "general.indicatorHeight",
            title: String(localized: "Indicator Height"),
            keywords: ["indicator", "height", "thickness"],
            tab: "General",
            section: String(localized: "Active App Indicator"),
            icon: "arrow.up.and.down"
        ),
        SettingsSearchItem(
            id: "general.indicatorOffset",
            title: String(localized: "Position Offset"),
            keywords: ["indicator", "offset", "position"],
            tab: "General",
            section: String(localized: "Active App Indicator"),
            icon: "arrow.up.and.down"
        ),
        SettingsSearchItem(
            id: "general.indicatorAutoLength",
            title: String(localized: "Automatically set length"),
            keywords: ["indicator", "auto", "length", "width"],
            tab: "General",
            section: String(localized: "Active App Indicator"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "general.indicatorLength",
            title: String(localized: "Indicator Length"),
            keywords: ["indicator", "length", "width"],
            tab: "General",
            section: String(localized: "Active App Indicator"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "general.indicatorShift",
            title: String(localized: "Shift Indicator"),
            keywords: ["indicator", "shift", "nudge"],
            tab: "General",
            section: String(localized: "Active App Indicator"),
            icon: "arrow.left.arrow.right"
        ),
        SettingsSearchItem(
            id: "general.exportSettings",
            title: String(localized: "Export Settings…"),
            description: String(localized: "Settings are saved as a JSON file you can keep in iCloud Drive or a dotfiles repository. Importing replaces your current settings and restarts DockDoor."),
            keywords: ["backup", "export", "save", "json", "sync", "dotfiles", "icloud"],
            tab: "General",
            section: String(localized: "Backup & Restore"),
            icon: "square.and.arrow.up"
        ),
        SettingsSearchItem(
            id: "general.importSettings",
            title: String(localized: "Import Settings…"),
            keywords: ["backup", "import", "restore", "load", "json", "migrate", "transfer"],
            tab: "General",
            section: String(localized: "Backup & Restore"),
            icon: "square.and.arrow.down"
        ),
    ]

    // MARK: - Dock Previews

    private static let dockPreviewItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            id: "dockPreviews.enable",
            title: String(localized: "Enable Dock Previews"),
            description: String(localized: "Show window previews for Dock icons."),
            keywords: ["dock", "hover", "preview"],
            tab: "DockPreviews",
            section: "",
            icon: "dock.rectangle"
        ),
        SettingsSearchItem(
            id: "dockPreviews.currentSpaceOnly",
            title: String(localized: "Show windows from current Space only"),
            description: String(localized: "Only display windows that are in the current virtual desktop/Space."),
            keywords: ["space", "desktop", "virtual"],
            tab: "DockPreviews",
            section: String(localized: "Window Display"),
            icon: "rectangle.on.rectangle"
        ),
        SettingsSearchItem(
            id: "dockPreviews.currentMonitorOnly",
            title: String(localized: "Show windows from current monitor only"),
            description: String(localized: "Only display windows that are on the same display as the Dock icon you're hovering."),
            keywords: ["monitor", "display", "screen"],
            tab: "DockPreviews",
            section: String(localized: "Window Display"),
            icon: "display"
        ),
        SettingsSearchItem(
            id: "dockPreviews.sortOrder",
            title: String(localized: "Window sort order"),
            keywords: ["sort", "order", "arrange"],
            tab: "DockPreviews",
            section: String(localized: "Window Display"),
            icon: "arrow.up.arrow.down"
        ),
        SettingsSearchItem(
            id: "dockPreviews.includeHidden",
            title: String(localized: "Include hidden/minimized windows"),
            keywords: ["hidden", "minimized", "include"],
            tab: "DockPreviews",
            section: String(localized: "Window Display"),
            icon: "eye.slash"
        ),
        SettingsSearchItem(
            id: "dockPreviews.fullSizeWindowless",
            title: String(localized: "Show full size previews"),
            keywords: ["windowless", "placeholder", "full", "size", "compact"],
            tab: "DockPreviews",
            section: String(localized: "Window Display"),
            icon: "macwindow"
        ),
        SettingsSearchItem(
            id: "dockPreviews.showWindowless",
            title: String(localized: "Show preview for apps with no open windows"),
            description: String(localized: "Show a placeholder preview when hovering dock apps that have no windows."),
            keywords: ["windowless", "placeholder", "empty"],
            tab: "DockPreviews",
            section: String(localized: "Window Display"),
            icon: "macwindow.badge.plus"
        ),
        SettingsSearchItem(
            id: "dockPreviews.keepOnTerminate",
            title: String(localized: "Keep preview when app terminates"),
            description: String(localized: "Remove only terminated app's windows instead of hiding the entire preview."),
            keywords: ["terminate", "quit", "close", "keep"],
            tab: "DockPreviews",
            section: String(localized: "Window Display"),
            icon: "xmark.app"
        ),
        SettingsSearchItem(
            id: "dockPreviews.groupInstances",
            title: String(localized: "Group multiple app instances together"),
            description: String(localized: "Show windows from all instances of an app when hovering its dock icon."),
            keywords: ["group", "instance", "multiple"],
            tab: "DockPreviews",
            section: String(localized: "Window Display"),
            icon: "square.stack"
        ),
        SettingsSearchItem(
            id: "dockPreviews.collapseNativeTabs",
            title: String(localized: "Collapse native tabs into a single window"),
            description: String(localized: "Show one preview for apps that use native macOS window tabs (e.g. Ghostty, Finder, Terminal) instead of one preview per tab."),
            keywords: ["tab", "tabs", "native", "collapse", "ghostty", "finder", "terminal"],
            tab: "DockPreviews",
            section: String(localized: "Window Display"),
            icon: "square.on.square"
        ),
        SettingsSearchItem(
            id: "dockPreviews.ignoreSingleWindow",
            title: String(localized: "Ignore apps with one window"),
            description: String(localized: "Prevents apps with exactly one open window from appearing in previews."),
            keywords: ["single", "ignore", "one"],
            tab: "DockPreviews",
            section: String(localized: "Window Display"),
            icon: "1.square"
        ),
        SettingsSearchItem(
            id: "dockPreviews.activationTrigger",
            title: String(localized: "Dock Preview Trigger"),
            description: String(localized: "Show previews automatically on hover, or require a click trigger on the Dock icon."),
            keywords: ["trigger", "hover", "middle", "click", "modifier", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "cursorarrow.click"
        ),
        SettingsSearchItem(
            id: "dockPreviews.activationModifier",
            title: String(localized: "Dock Preview Modifier"),
            keywords: ["modifier", "option", "control", "shift", "command", "click"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "keyboard"
        ),
        SettingsSearchItem(
            id: "dockPreviews.hoverAction",
            title: String(localized: "Dock Preview Hover Action"),
            keywords: ["hover", "action", "click", "tap"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "cursorarrow.click"
        ),
        SettingsSearchItem(
            id: "dockPreviews.keepOnHoverActivation",
            title: String(localized: "Keep preview open after hover activation"),
            description: String(localized: "Keep Dock previews visible while the pointer remains over them after a hover brings a window to the front."),
            keywords: ["hover", "activate", "front", "keep", "preview", "windows"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "rectangle.on.rectangle"
        ),
        SettingsSearchItem(
            id: "dockPreviews.hoverDelay",
            title: String(localized: "Preview Hover Action Delay"),
            keywords: ["delay", "tap", "interval"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "timer"
        ),
        SettingsSearchItem(
            id: "dockPreviews.focusFade",
            title: String(localized: "Enable Dock previews fade out when resting on a preview (Experimental)"),
            description: String(localized: "Fade out Dock previews while highlighting a window and pausing all movement. This is useful to fully reveal the currently highlighted window’s full size preview if enabled. Experimental: this feature can intermittently stop mouse-hover highlighting or make preview selection appear unresponsive. The cause has not been resolved. Disabled by default; turn it off if you encounter these issues."),
            keywords: ["fade", "full size", "preview", "opacity", "rest", "idle"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "rectangle.dashed"
        ),
        SettingsSearchItem(
            id: "dockPreviews.focusFadeDelay",
            title: String(localized: "Dock Preview Fade Out Delay"),
            keywords: ["fade", "full size", "preview", "opacity", "rest", "idle"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "timer"
        ),
        SettingsSearchItem(
            id: "dockPreviews.focusFadeDuration",
            title: String(localized: "Fade Out Duration"),
            keywords: ["fade", "full size", "preview", "opacity", "rest", "idle"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "timer"
        ),
        SettingsSearchItem(
            id: "dockPreviews.focusFadeOpacity",
            title: String(localized: "Target Minimum Opacity"),
            keywords: ["fade", "full size", "preview", "opacity", "rest", "idle"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "circle.lefthalf.filled"
        ),
        SettingsSearchItem(
            id: "dockPreviews.edgeAutoScroll",
            title: String(localized: "Enable edge auto-scroll"),
            keywords: ["edge", "hover", "scroll", "automatic", "mouse"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "dockPreviews.edgeAutoScrollSpeed",
            title: String(localized: "Auto-scroll speed:"),
            keywords: ["edge", "hover", "scroll", "speed"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "gauge.with.dots.needle.67percent"
        ),
        SettingsSearchItem(
            id: "dockPreviews.hideOnClick",
            title: String(localized: "Override Dock icon click"),
            keywords: ["dock", "click", "action", "hide", "minimize", "cycle"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "cursorarrow.click.2"
        ),
        SettingsSearchItem(
            id: "dockPreviews.clickAction",
            title: String(localized: "Dock Click Action"),
            description: String(localized: "Choose whether clicking an app in the Dock hides or minimizes its windows, or cycles through its windows."),
            keywords: ["dock", "click", "hide", "minimize", "cycle", "windows"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "cursorarrow.click.2"
        ),
        SettingsSearchItem(
            id: "dockPreviews.keepOpenWhenCycling",
            title: String(localized: "Keep previews open when cycling through windows"),
            keywords: ["dock", "click", "cycle", "windows", "keep", "open", "active"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "arrow.triangle.2.circlepath"
        ),
        SettingsSearchItem(
            id: "dockPreviews.cmdRightClickQuit",
            title: String(localized: "CMD + Right Click on dock icon to quit app"),
            keywords: ["quit", "right click", "command", "force"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "xmark.circle"
        ),
        SettingsSearchItem(
            id: "dockPreviews.quitOnClose",
            title: String(localized: "Quit app when closing its last window"),
            description: String(localized: "When an app has only one window left, closing it will quit the app. Useful as a replacement for Swift Quit."),
            keywords: ["quit", "close", "last window"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "xmark.app.fill"
        ),
        SettingsSearchItem(
            id: "dockPreviews.buffer",
            title: String(localized: "Window Buffer from Dock (pixels)"),
            keywords: ["buffer", "distance", "gap", "offset", "pixels"],
            tab: "DockPreviews",
            section: String(localized: "Dock Interaction"),
            icon: "arrow.up.and.down"
        ),
    ]

    // MARK: - Window Switcher

    private static let windowSwitcherItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            id: "windowSwitcher.enable",
            title: String(localized: "Enable Window Switcher"),
            description: String(localized: "The Window Switcher (often Alt/Cmd-Tab) lets you quickly cycle between open app windows with a keyboard shortcut."),
            keywords: ["switcher", "alt tab", "window"],
            tab: "WindowSwitcher",
            section: "",
            icon: "uiwindow.split.2x1"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.instant",
            title: String(localized: "Show Window Switcher instantly"),
            description: String(localized: "May feel snappier but can cause flickering if you quickly release the key."),
            keywords: ["instant", "fast", "speed", "flicker"],
            tab: "WindowSwitcher",
            section: String(localized: "Behavior"),
            icon: "bolt"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.releaseToSelect",
            title: String(localized: "Release initializer key to select window"),
            keywords: ["release", "select", "key"],
            tab: "WindowSwitcher",
            section: String(localized: "Behavior"),
            icon: "hand.raised"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.startOnSecond",
            title: String(localized: "Start on second window"),
            description: String(localized: "Highlight the second window instead of the first when opening."),
            keywords: ["second", "start", "classic", "ordering"],
            tab: "WindowSwitcher",
            section: String(localized: "Behavior"),
            icon: "2.circle"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.mouseFollowsFocus",
            title: String(localized: "Mouse follows focus", comment: "Mouse follows focus setting label"),
            description: String(localized: "Move the cursor to the center of the selected window."),
            keywords: ["mouse", "cursor", "warp", "teleport", "focus"],
            tab: "WindowSwitcher",
            section: String(localized: "Behavior"),
            icon: "computermouse"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.currentSpaceOnly",
            title: String(localized: "Show windows from current Space only"),
            description: String(localized: "Only display windows that are in the current virtual desktop/Space."),
            keywords: ["space", "desktop", "virtual"],
            tab: "WindowSwitcher",
            section: String(localized: "Window Display"),
            icon: "rectangle.on.rectangle"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.currentMonitorOnly",
            title: String(localized: "Show windows from current monitor only"),
            description: String(localized: "Only display windows that are on the same display as the mouse cursor."),
            keywords: ["monitor", "display", "screen"],
            tab: "WindowSwitcher",
            section: String(localized: "Window Display"),
            icon: "display"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.limitToFrontmost",
            title: String(localized: "Limit to active app only"),
            description: String(localized: "Only show windows from the currently active/frontmost application."),
            keywords: ["frontmost", "active", "limit", "current"],
            tab: "WindowSwitcher",
            section: String(localized: "Window Display"),
            icon: "app.dashed"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.includeHidden",
            title: String(localized: "Include hidden/minimized windows"),
            keywords: ["hidden", "minimized", "include"],
            tab: "WindowSwitcher",
            section: String(localized: "Window Display"),
            icon: "eye.slash"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.showWindowless",
            title: String(localized: "Show running apps with no open windows"),
            description: String(localized: "Dock-visible apps without any windows will appear as icon-only entries at the end."),
            keywords: ["windowless", "running", "empty", "icon"],
            tab: "WindowSwitcher",
            section: String(localized: "Window Display"),
            icon: "macwindow.badge.plus"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.excludeWindowlessFromCurrentMonitor",
            title: String(localized: "Exclude from \"Current Monitor Only\" filter"),
            keywords: ["windowless", "monitor", "display", "filter", "exclude"],
            tab: "WindowSwitcher",
            section: String(localized: "Window Display"),
            icon: "display"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.excludeWindowlessFromCurrentSpace",
            title: String(localized: "Exclude from \"Current Space Only\" filter"),
            keywords: ["windowless", "space", "desktop", "filter", "exclude"],
            tab: "WindowSwitcher",
            section: String(localized: "Window Display"),
            icon: "rectangle.on.rectangle"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.enableSearch",
            title: String(localized: "Enable search"),
            keywords: ["search", "find", "filter", "type"],
            tab: "WindowSwitcher",
            section: String(localized: "Search & Input"),
            icon: "magnifyingglass"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.focusSearch",
            title: String(localized: "Focus search on open"),
            description: String(localized: "Automatically focus the search bar when the window switcher opens."),
            keywords: ["focus", "search", "auto", "bar"],
            tab: "WindowSwitcher",
            section: String(localized: "Search & Input"),
            icon: "text.cursor"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.mouseHover",
            title: String(localized: "Enable mouse hover selection"),
            description: String(localized: "Select windows when hovering with the mouse."),
            keywords: ["mouse", "hover", "select"],
            tab: "WindowSwitcher",
            section: String(localized: "Hover Actions"),
            icon: "cursorarrow"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.edgeAutoScroll",
            title: String(localized: "Enable edge auto-scroll"),
            keywords: ["edge", "hover", "scroll", "automatic", "mouse"],
            tab: "WindowSwitcher",
            section: String(localized: "Hover Actions"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.edgeAutoScrollSpeed",
            title: String(localized: "Auto-scroll speed:"),
            keywords: ["edge", "hover", "scroll", "speed"],
            tab: "WindowSwitcher",
            section: String(localized: "Hover Actions"),
            icon: "gauge.with.dots.needle.67percent"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.hoverAction",
            title: String(localized: "Window Switcher Hover Action"),
            keywords: ["window", "switcher", "hover", "action", "preview", "keyboard"],
            tab: "WindowSwitcher",
            section: String(localized: "Hover Actions"),
            icon: "hand.point.up.left"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.hoverDelay",
            title: String(localized: "Window Switcher Hover Action Delay"),
            keywords: ["window", "switcher", "hover", "delay", "seconds", "timer"],
            tab: "WindowSwitcher",
            section: String(localized: "Hover Actions"),
            icon: "timer"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.focusFade",
            title: String(localized: "Enable Window Switcher fade out when resting on a preview (Experimental)"),
            description: String(localized: "Fade out Window Switcher while highlighting a window and pausing all movement. This is useful to fully reveal the currently highlighted window’s full size preview if enabled. Experimental: this feature can intermittently stop mouse-hover highlighting or make preview selection appear unresponsive. The cause has not been resolved. Disabled by default; turn it off if you encounter these issues."),
            keywords: ["fade", "full size", "preview", "opacity", "rest", "idle"],
            tab: "WindowSwitcher",
            section: String(localized: "Hover Actions"),
            icon: "rectangle.dashed"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.focusFadeDelay",
            title: String(localized: "Window Switcher Fade Out Delay"),
            keywords: ["fade", "full size", "preview", "opacity", "rest", "idle"],
            tab: "WindowSwitcher",
            section: String(localized: "Hover Actions"),
            icon: "timer"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.focusFadeDuration",
            title: String(localized: "Fade Out Duration"),
            keywords: ["fade", "full size", "preview", "opacity", "rest", "idle"],
            tab: "WindowSwitcher",
            section: String(localized: "Hover Actions"),
            icon: "timer"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.focusFadeOpacity",
            title: String(localized: "Target Minimum Opacity"),
            keywords: ["fade", "full size", "preview", "opacity", "rest", "idle"],
            tab: "WindowSwitcher",
            section: String(localized: "Hover Actions"),
            icon: "circle.lefthalf.filled"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.sortOrder",
            title: String(localized: "Window sort order"),
            keywords: ["sort", "order", "arrange"],
            tab: "WindowSwitcher",
            section: String(localized: "Sorting & Grouping"),
            icon: "arrow.up.arrow.down"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.groupByApp",
            title: String(localized: "Group windows by app"),
            description: String(localized: "Selected apps show only their most recent window. All windows shown in active-app-only mode."),
            keywords: ["group", "app", "bundle"],
            tab: "WindowSwitcher",
            section: String(localized: "Sorting & Grouping"),
            icon: "square.stack"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.placement",
            title: String(localized: "Screen"),
            keywords: ["placement", "screen", "position", "where"],
            tab: "WindowSwitcher",
            section: String(localized: "Placement"),
            icon: "rectangle.center.inset.filled"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.anchorVertical",
            title: String(localized: "Vertical anchor"),
            keywords: ["anchor", "vertical", "top", "center", "bottom", "position"],
            tab: "WindowSwitcher",
            section: String(localized: "Placement"),
            icon: "arrow.up.and.down"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.anchorHorizontal",
            title: String(localized: "Horizontal anchor"),
            keywords: ["anchor", "horizontal", "left", "center", "right", "position"],
            tab: "WindowSwitcher",
            section: String(localized: "Placement"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "windowSwitcher.offsetPosition",
            title: String(localized: "Offset position"),
            keywords: ["offset", "shift", "move", "position"],
            tab: "WindowSwitcher",
            section: String(localized: "Placement"),
            icon: "arrow.up.left.and.arrow.down.right"
        ),
    ]

    // MARK: - Cmd+Tab

    private static let cmdTabItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            id: "cmdTab.enable",
            title: String(localized: "Enable Cmd+Tab Enhancements"),
            description: String(localized: "Show previews while holding Cmd+Tab."),
            keywords: ["cmd tab", "command tab", "enhance"],
            tab: "CmdTab",
            section: "",
            icon: "command"
        ),
        SettingsSearchItem(
            id: "cmdTab.cycleKey",
            title: String(localized: "Preview cycle key:"),
            keywords: ["cycle", "key", "forward", "tab"],
            tab: "CmdTab",
            section: String(localized: "Configuration"),
            icon: "arrow.right"
        ),
        SettingsSearchItem(
            id: "cmdTab.backwardKey",
            title: String(localized: "Backward cycle key:"),
            keywords: ["backward", "reverse", "shift"],
            tab: "CmdTab",
            section: String(localized: "Configuration"),
            icon: "arrow.left"
        ),
        SettingsSearchItem(
            id: "cmdTab.autoSelect",
            title: String(localized: "Automatically select first window"),
            description: String(localized: "When Cmd+Tab opens, highlight the first window preview automatically."),
            keywords: ["auto", "select", "first", "highlight"],
            tab: "CmdTab",
            section: String(localized: "Configuration"),
            icon: "1.circle"
        ),
        SettingsSearchItem(
            id: "cmdTab.hoverAction",
            title: String(localized: "Cmd+Tab Hover Action"),
            keywords: ["cmd tab", "command tab", "hover", "action", "preview", "keyboard"],
            tab: "CmdTab",
            section: String(localized: "Hover Actions"),
            icon: "hand.point.up.left"
        ),
        SettingsSearchItem(
            id: "cmdTab.hoverDelay",
            title: String(localized: "Cmd+Tab Hover Action Delay"),
            keywords: ["cmd tab", "command tab", "hover", "delay", "seconds", "timer"],
            tab: "CmdTab",
            section: String(localized: "Hover Actions"),
            icon: "timer"
        ),
        SettingsSearchItem(
            id: "cmdTab.focusFade",
            title: String(localized: "Enable Cmd+Tab previews fade out when resting on a preview (Experimental)"),
            description: String(localized: "Fade out Cmd+Tab previews while highlighting a window and pausing all movement. This is useful to fully reveal the currently highlighted window’s full size preview if enabled. Experimental: this feature can intermittently stop mouse-hover highlighting or make preview selection appear unresponsive. The cause has not been resolved. Disabled by default; turn it off if you encounter these issues."),
            keywords: ["fade", "full size", "preview", "opacity", "rest", "idle"],
            tab: "CmdTab",
            section: String(localized: "Hover Actions"),
            icon: "rectangle.dashed"
        ),
        SettingsSearchItem(
            id: "cmdTab.focusFadeDelay",
            title: String(localized: "Cmd+Tab Fade Out Delay"),
            keywords: ["fade", "full size", "preview", "opacity", "rest", "idle"],
            tab: "CmdTab",
            section: String(localized: "Hover Actions"),
            icon: "timer"
        ),
        SettingsSearchItem(
            id: "cmdTab.focusFadeDuration",
            title: String(localized: "Fade Out Duration"),
            keywords: ["fade", "full size", "preview", "opacity", "rest", "idle"],
            tab: "CmdTab",
            section: String(localized: "Hover Actions"),
            icon: "timer"
        ),
        SettingsSearchItem(
            id: "cmdTab.focusFadeOpacity",
            title: String(localized: "Target Minimum Opacity"),
            keywords: ["fade", "full size", "preview", "opacity", "rest", "idle"],
            tab: "CmdTab",
            section: String(localized: "Hover Actions"),
            icon: "circle.lefthalf.filled"
        ),
        SettingsSearchItem(
            id: "cmdTab.edgeAutoScroll",
            title: String(localized: "Enable edge auto-scroll"),
            keywords: ["cmd tab", "command tab", "edge", "hover", "scroll", "automatic", "mouse"],
            tab: "CmdTab",
            section: String(localized: "Hover Actions"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "cmdTab.edgeAutoScrollSpeed",
            title: String(localized: "Auto-scroll speed:"),
            keywords: ["cmd tab", "command tab", "edge", "hover", "scroll", "speed"],
            tab: "CmdTab",
            section: String(localized: "Hover Actions"),
            icon: "gauge.with.dots.needle.67percent"
        ),
        SettingsSearchItem(
            id: "cmdTab.currentSpaceOnly",
            title: String(localized: "Show windows from current Space only"),
            description: String(localized: "Only display windows that are in the current virtual desktop/Space."),
            keywords: ["space", "desktop"],
            tab: "CmdTab",
            section: String(localized: "Window Display"),
            icon: "rectangle.on.rectangle"
        ),
        SettingsSearchItem(
            id: "cmdTab.currentMonitorOnly",
            title: String(localized: "Show windows from current monitor only"),
            description: String(localized: "Only display windows that are on the same display as the mouse cursor."),
            keywords: ["monitor", "display", "screen"],
            tab: "CmdTab",
            section: String(localized: "Window Display"),
            icon: "display"
        ),
        SettingsSearchItem(
            id: "cmdTab.includeHidden",
            title: String(localized: "Include hidden/minimized windows"),
            keywords: ["hidden", "minimized"],
            tab: "CmdTab",
            section: String(localized: "Window Display"),
            icon: "eye.slash"
        ),
        SettingsSearchItem(
            id: "cmdTab.fullSizeWindowless",
            title: String(localized: "Show full size previews"),
            keywords: ["windowless", "placeholder", "full", "size", "compact"],
            tab: "CmdTab",
            section: String(localized: "Window Display"),
            icon: "macwindow"
        ),
        SettingsSearchItem(
            id: "cmdTab.showWindowless",
            title: String(localized: "Show preview for apps with no open windows"),
            description: String(localized: "Show a placeholder preview when Cmd+Tab lands on an app that has no windows."),
            keywords: ["windowless", "placeholder"],
            tab: "CmdTab",
            section: String(localized: "Window Display"),
            icon: "macwindow.badge.plus"
        ),
        SettingsSearchItem(
            id: "cmdTab.ignoreSingleWindow",
            title: String(localized: "Ignore apps with one window"),
            description: String(localized: "Prevents apps with exactly one open window from appearing in previews."),
            keywords: ["single", "one", "window", "ignore"],
            tab: "CmdTab",
            section: String(localized: "Window Display"),
            icon: "macwindow.badge.minus"
        ),
        SettingsSearchItem(
            id: "cmdTab.sortOrder",
            title: String(localized: "Window sort order"),
            keywords: ["sort", "order"],
            tab: "CmdTab",
            section: String(localized: "Window Display"),
            icon: "arrow.up.arrow.down"
        ),
    ]

    // MARK: - Dock Locking

    private static let dockLockingItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            id: "dockLocking.enable",
            title: String(localized: "Lock Dock to Screen"),
            description: String(localized: "Prevent the Dock from jumping to other monitors when your cursor reaches the screen edge."),
            keywords: ["lock", "pin", "monitor", "screen", "multi"],
            tab: "DockLocking",
            section: "",
            icon: "lock.fill"
        ),
        SettingsSearchItem(
            id: "dockLocking.screen",
            title: String(localized: "Lock Dock to"),
            keywords: ["screen", "display", "which"],
            tab: "DockLocking",
            section: String(localized: "Configuration"),
            icon: "display"
        ),
        SettingsSearchItem(
            id: "dockLocking.bypass",
            title: String(localized: "Bypass modifier key"),
            description: String(localized: "Hold this key to temporarily allow the Dock to move freely."),
            keywords: ["bypass", "override", "modifier", "temporarily"],
            tab: "DockLocking",
            section: String(localized: "Configuration"),
            icon: "key"
        ),
    ]

    // MARK: - Appearance

    private static let appearanceItems: [SettingsSearchItem] = [
        // Window Preview Size
        SettingsSearchItem(
            id: "appearance.lockAspect",
            title: String(localized: "Lock aspect ratio (16:10)"),
            keywords: ["aspect", "ratio", "lock", "16:10"],
            tab: "Appearance",
            section: String(localized: "Window Preview Size"),
            icon: "aspectratio"
        ),
        SettingsSearchItem(
            id: "appearance.dynamicSizing",
            title: String(localized: "Dynamic image sizing"),
            description: String(localized: "Scale previews to match actual window proportions instead of using fixed dimensions."),
            keywords: ["dynamic", "scale", "size", "proportional"],
            tab: "Appearance",
            section: String(localized: "Window Preview Size"),
            icon: "arrow.up.left.and.arrow.down.right"
        ),
        SettingsSearchItem(
            id: "appearance.previewWidth",
            title: String(localized: "Preview Width"),
            keywords: ["width", "size", "preview"],
            tab: "Appearance",
            section: String(localized: "Window Preview Size"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "appearance.previewHeight",
            title: String(localized: "Preview Height"),
            keywords: ["height", "size", "preview"],
            tab: "Appearance",
            section: String(localized: "Window Preview Size"),
            icon: "arrow.up.and.down"
        ),
        // Background
        SettingsSearchItem(
            id: "appearance.backgroundStyle",
            title: String(localized: "Style"),
            keywords: ["background", "style", "glass", "blur", "material"],
            tab: "Appearance",
            section: String(localized: "Background"),
            icon: "rectangle.fill"
        ),
        // General Appearance
        SettingsSearchItem(
            id: "appearance.theme",
            title: String(localized: "Appearance"),
            keywords: ["theme", "dark", "light", "system"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "circle.lefthalf.filled"
        ),
        SettingsSearchItem(
            id: "appearance.roundedCorners",
            title: String(localized: "Rounded corners"),
            description: String(localized: "Round the corners of window preview images for a modern look."),
            keywords: ["rounded", "corners", "radius"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "rectangle.roundedtop"
        ),
        SettingsSearchItem(
            id: "appearance.cornerRadius",
            title: String(localized: "Corner Radius"),
            keywords: ["rounded", "corners", "radius", "roundness"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "rectangle.roundedtop"
        ),
        SettingsSearchItem(
            id: "appearance.marquee",
            title: String(localized: "Long title overflow"),
            description: String(localized: "How to display window titles that are too long to fit."),
            keywords: ["marquee", "scroll", "title", "truncate", "overflow"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "text.badge.star"
        ),
        SettingsSearchItem(
            id: "appearance.dimMinimizedHiddenPreviews",
            title: String(localized: "Dim minimized and hidden previews"),
            description: String(localized: "Dims minimized and hidden window preview images without changing window state indicator visibility."),
            keywords: ["minimized", "hidden", "dim", "preview"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "eye.trianglebadge.exclamationmark"
        ),
        SettingsSearchItem(
            id: "appearance.spaceNumber",
            title: String(localized: "Show Space number on previews (Legacy)"),
            description: String(localized: "Labels each preview with the number of the desktop (Space) its window is on. Only shown when you have more than one desktop."),
            keywords: ["space", "desktop", "number", "badge", "mission control", "legacy"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "rectangle.on.rectangle"
        ),
        SettingsSearchItem(
            id: "appearance.windowlessQuitButton",
            title: String(localized: "Show quit button for apps with no open windows"),
            description: String(localized: "Shows a quit-only control on previews for running apps with no open windows."),
            keywords: ["windowless", "quit", "button", "running", "no windows"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "power"
        ),
        SettingsSearchItem(
            id: "appearance.hidePreviewBackground",
            title: String(localized: "Hide preview card background"),
            description: String(localized: "Removes the background panel from individual window previews."),
            keywords: ["background", "card", "hide", "transparent"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "rectangle.dashed"
        ),
        SettingsSearchItem(
            id: "appearance.hideContainerBackground",
            title: String(localized: "Hide hover container background"),
            description: String(localized: "Removes the container background from window preview panels."),
            keywords: ["container", "background", "hide", "transparent"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "rectangle.dashed.and.arrow.up"
        ),
        SettingsSearchItem(
            id: "appearance.hideWidgetBackground",
            title: String(localized: "Hide widget container background"),
            description: String(localized: "Removes the container background from widget panels (media controls, calendar)."),
            keywords: ["widget", "background", "hide"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "widget.small.badge.minus"
        ),
        SettingsSearchItem(
            id: "appearance.activeBorder",
            title: String(localized: "Show active window border"),
            description: String(localized: "Highlights the currently focused window with a colored border."),
            keywords: ["border", "active", "highlight", "focused"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "rectangle.inset.filled.and.person.filled"
        ),
        SettingsSearchItem(
            id: "appearance.fullSizePreviewOpacity",
            title: String(localized: "Opacity"),
            description: String(localized: "Adjusts the transparency of full size previews."),
            keywords: ["full", "size", "preview", "opacity", "transparency"],
            tab: "Appearance",
            section: String(localized: "Full Size Previews"),
            icon: "circle.lefthalf.filled"
        ),
        SettingsSearchItem(
            id: "appearance.fullSizePreviewFadeIn",
            title: String(localized: "Fade In Duration"),
            description: String(localized: "Set the full size preview fade-in duration. Set to 0 seconds to disable the animation."),
            keywords: ["full", "size", "preview", "fade", "in", "animation", "duration"],
            tab: "Appearance",
            section: String(localized: "Full Size Previews"),
            icon: "circle.righthalf.filled"
        ),
        SettingsSearchItem(
            id: "appearance.fullSizePreviewFadeOut",
            title: String(localized: "Fade Out Duration"),
            description: String(localized: "Set the full size preview fade-out duration. Set to 0 seconds to disable the animation."),
            keywords: ["full", "size", "preview", "fade", "out", "animation", "duration"],
            tab: "Appearance",
            section: String(localized: "Full Size Previews"),
            icon: "circle.lefthalf.filled"
        ),
        SettingsSearchItem(
            id: "appearance.fullSizePreviewBackgroundBlur",
            title: String(localized: "Blur background behind full size previews"),
            description: String(localized: "Blurs the content behind full size previews without blurring the preview itself."),
            keywords: ["full", "size", "preview", "blur", "background", "backdrop"],
            tab: "Appearance",
            section: String(localized: "Full Size Previews"),
            icon: "drop.halffull"
        ),
        SettingsSearchItem(
            id: "appearance.fullSizePreviewBorder",
            title: String(localized: "Show full size preview border"),
            description: String(localized: "Uses the active window border color and stays inside the preview bounds."),
            keywords: ["full", "size", "preview", "border", "active", "highlight"],
            tab: "Appearance",
            section: String(localized: "Full Size Previews"),
            icon: "rectangle.inset.filled"
        ),
        // Compact Mode
        SettingsSearchItem(
            id: "appearance.compactMode",
            title: String(localized: "Always use compact mode"),
            keywords: ["compact", "list", "titles", "minimal"],
            tab: "Appearance",
            section: String(localized: "Compact Mode (Titles Only)"),
            icon: "list.bullet"
        ),
        SettingsSearchItem(
            id: "appearance.compactHoverActions",
            title: String(localized: "Enable hover actions in compact mode"),
            description: String(localized: "Hover actions in compact mode require Screen Recording permission."),
            keywords: ["compact", "hover", "actions", "preview", "keyboard", "screen", "recording"],
            tab: "Appearance",
            section: String(localized: "Compact Mode (Titles Only)"),
            icon: "hand.point.up.left"
        ),
        SettingsSearchItem(
            id: "appearance.hideTrafficLights",
            title: String(localized: "Hide Traffic Lights"),
            description: String(localized: "Hides the close, minimize, and other window control buttons in compact mode to provide more room for window titles."),
            keywords: ["traffic", "lights", "close", "minimize", "buttons"],
            tab: "Appearance",
            section: String(localized: "Compact Mode (Titles Only)"),
            icon: "minus.circle"
        ),
        // Advanced Appearance
        SettingsSearchItem(
            id: "appearance.opaqueBackground",
            title: String(localized: "Use opaque background"),
            description: String(localized: "Replaces the blurred/transparent background with a solid color. Useful for accessibility or readability."),
            keywords: ["opaque", "solid", "transparent", "blur"],
            tab: "Appearance",
            section: String(localized: "Dock Preview Transparency"),
            icon: "square.fill"
        ),
        SettingsSearchItem(
            id: "appearance.dockPreviewOpacity",
            title: String(localized: "Background Opacity"),
            description: String(localized: "Control the transparency of the dock preview background."),
            keywords: ["opacity", "transparency", "background", "dock"],
            tab: "Appearance",
            section: String(localized: "Dock Preview Transparency"),
            icon: "circle.lefthalf.filled"
        ),
        // General Appearance - sliders
        SettingsSearchItem(
            id: "appearance.spacingScale",
            title: String(localized: "Spacing Scale"),
            keywords: ["spacing", "padding", "scale", "gap"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "appearance.trafficLightButtonScale",
            title: String(localized: "Traffic Light Button Scale"),
            description: String(localized: "Controls the size of traffic light buttons in all preview modes."),
            keywords: ["traffic light", "button", "scale", "size", "dock", "switcher", "cmd tab"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "arrow.up.left.and.arrow.down.right"
        ),
        SettingsSearchItem(
            id: "appearance.windowTitleFontSize",
            title: String(localized: "Window Title Font Size"),
            description: String(localized: "Controls the window title font size in all preview modes."),
            keywords: ["font", "size", "title", "dock", "switcher", "cmd tab"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "textformat.size"
        ),
        SettingsSearchItem(
            id: "appearance.windowStateIndicatorFontSize",
            title: String(localized: "Window State / Space Number Indicator Font Size"),
            keywords: ["font", "size", "state", "status", "space", "number", "indicator", "dock", "switcher", "cmd tab"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "textformat.size"
        ),
        SettingsSearchItem(
            id: "appearance.trafficLightTransitionDuration",
            title: String(localized: "Traffic Light Buttons Transition Animation Speed"),
            description: String(localized: "Controls traffic light button transitions in all preview modes. Set to 0 seconds to disable only these transitions. Reduce Motion overrides this setting."),
            keywords: ["traffic light", "animation", "transition", "speed", "duration", "reduce motion", "dock", "switcher", "cmd tab"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "speedometer"
        ),
        SettingsSearchItem(
            id: "appearance.unselectedOpacity",
            title: String(localized: "Unselected Content Opacity"),
            keywords: ["opacity", "unselected", "dim", "fade"],
            tab: "Appearance",
            section: String(localized: "General Appearance"),
            icon: "circle.lefthalf.filled"
        ),
        // Compact Mode - additional
        SettingsSearchItem(
            id: "appearance.compactThresholdSwitcher",
            title: String(localized: "Window Switcher"),
            description: String(localized: "Switch to compact list in window switcher when window count reaches threshold."),
            keywords: ["compact", "threshold", "switcher", "auto"],
            tab: "Appearance",
            section: String(localized: "Compact Mode (Titles Only)"),
            icon: "list.bullet"
        ),
        SettingsSearchItem(
            id: "appearance.compactThresholdDock",
            title: String(localized: "Dock Previews"),
            description: String(localized: "Switch to compact list in dock previews when window count reaches threshold."),
            keywords: ["compact", "threshold", "dock", "auto"],
            tab: "Appearance",
            section: String(localized: "Compact Mode (Titles Only)"),
            icon: "list.bullet"
        ),
        SettingsSearchItem(
            id: "appearance.compactThresholdCmdTab",
            title: String(localized: "Cmd+Tab Enhancement"),
            description: String(localized: "Switch to compact list in Cmd+Tab overlay when window count reaches threshold."),
            keywords: ["compact", "threshold", "cmd tab", "auto"],
            tab: "Appearance",
            section: String(localized: "Compact Mode (Titles Only)"),
            icon: "list.bullet"
        ),
        SettingsSearchItem(
            id: "appearance.compactItemSize",
            title: String(localized: "Item Size"),
            keywords: ["compact", "item", "size", "row"],
            tab: "Appearance",
            section: String(localized: "Compact Mode (Titles Only)"),
            icon: "textformat.size"
        ),
        SettingsSearchItem(
            id: "appearance.compactModeWidth",
            title: String(localized: "Compact Mode Width"),
            description: String(localized: "Controls row width in compact mode so longer titles have more room."),
            keywords: ["compact", "width", "titles", "row", "size"],
            tab: "Appearance",
            section: String(localized: "Compact Mode (Titles Only)"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "appearance.compactTitleFormat",
            title: String(localized: "Title Format"),
            keywords: ["compact", "title", "format", "display"],
            tab: "Appearance",
            section: String(localized: "Compact Mode (Titles Only)"),
            icon: "textformat"
        ),
        // Background - additional
        SettingsSearchItem(
            id: "appearance.material",
            title: String(localized: "Material"),
            keywords: ["material", "frosted", "background"],
            tab: "Appearance",
            section: String(localized: "Background"),
            icon: "rectangle.fill"
        ),
        SettingsSearchItem(
            id: "appearance.previewShadow",
            title: String(localized: "Show shadow beneath previews"),
            description: String(localized: "Casts a soft shadow around preview panels so their edges stay visible over light backgrounds."),
            keywords: ["shadow", "depth", "drop shadow", "edge", "contrast", "size", "opacity"],
            tab: "Appearance",
            section: String(localized: "Background"),
            icon: "shadow"
        ),
        // Window Background
        SettingsSearchItem(
            id: "appearance.hoverHighlightColor",
            title: String(localized: "Custom Hover Highlight Color"),
            keywords: ["hover", "highlight", "color", "accent", "selection"],
            tab: "Appearance",
            section: String(localized: "Window Background"),
            icon: "paintbrush"
        ),
        SettingsSearchItem(
            id: "appearance.selectionOpacity",
            title: String(localized: "Background Opacity"),
            description: String(localized: "Controls the opacity of the selection highlight background."),
            keywords: ["selection", "opacity", "highlight"],
            tab: "Appearance",
            section: String(localized: "Window Background"),
            icon: "circle.lefthalf.filled"
        ),
        SettingsSearchItem(
            id: "appearance.customBackgroundColor",
            title: String(localized: "Custom Background Color"),
            description: String(localized: "Override the default blurred background with a solid custom color."),
            keywords: ["background", "color", "custom", "solid"],
            tab: "Appearance",
            section: String(localized: "Dock Preview Transparency"),
            icon: "paintbrush.fill"
        ),
        // Color Customization
        SettingsSearchItem(
            id: "appearance.gradientColors",
            title: String(localized: "Highlight Gradient Colors"),
            keywords: ["gradient", "color", "palette", "rainbow"],
            tab: "Appearance",
            section: String(localized: "Color Customization"),
            icon: "paintpalette"
        ),
        SettingsSearchItem(
            id: "appearance.gradientSpeed",
            title: String(localized: "Animation speed"),
            keywords: ["gradient", "animation", "speed"],
            tab: "Appearance",
            section: String(localized: "Color Customization"),
            icon: "hare"
        ),
        SettingsSearchItem(
            id: "appearance.gradientBlur",
            title: String(localized: "Blur amount"),
            keywords: ["gradient", "blur", "amount"],
            tab: "Appearance",
            section: String(localized: "Color Customization"),
            icon: "aqi.medium"
        ),
        // Dock Preview Appearance
        SettingsSearchItem(
            id: "appearance.dockShowAppHeader",
            title: String(localized: "Show App Header"),
            keywords: ["app", "header", "name", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "textformat"
        ),
        SettingsSearchItem(
            id: "appearance.dockAppHeaderStyle",
            title: String(localized: "App Header Style"),
            keywords: ["header", "style", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "textformat"
        ),
        SettingsSearchItem(
            id: "appearance.dockShowAppIconOnly",
            title: String(localized: "Show App Icon Only"),
            keywords: ["icon", "only", "header", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "app.badge"
        ),
        SettingsSearchItem(
            id: "appearance.dockControlPosition",
            title: String(localized: "Position Dock Preview Controls"),
            keywords: ["position", "controls", "toolbar", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "rectangle.topthird.inset.filled"
        ),
        SettingsSearchItem(
            id: "appearance.dockShowWindowTitle",
            title: String(localized: "Show Window Title"),
            description: String(localized: "Show window title in dock previews."),
            keywords: ["title", "window", "dock", "show"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "textformat.abc"
        ),
        SettingsSearchItem(
            id: "appearance.dockWindowTitleVisibility",
            title: String(localized: "Window Title Visibility"),
            keywords: ["title", "visibility", "hover", "always", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "eye"
        ),
        SettingsSearchItem(
            id: "appearance.dockDisableTitleStyling",
            title: String(localized: "Disable dock styling on window titles"),
            description: String(localized: "Removes the pill-shaped background styling from window titles in dock previews for a cleaner look."),
            keywords: ["styling", "pill", "title", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "textformat.abc.dottedunderline"
        ),
        SettingsSearchItem(
            id: "appearance.dockDisableTrafficLightStyling",
            title: String(localized: "Disable dock styling on traffic light buttons"),
            description: String(localized: "Removes the pill-shaped background styling from traffic light buttons in dock previews for a cleaner look."),
            keywords: ["traffic light", "styling", "pill", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "minus.circle"
        ),
        SettingsSearchItem(
            id: "appearance.dockSpaceNumberIndicator",
            title: String(localized: "Show Space Number Indicator"),
            description: String(localized: "Shows the Space number for each window in dock previews."),
            keywords: ["space", "desktop", "number", "indicator", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "number.circle"
        ),
        SettingsSearchItem(
            id: "appearance.dockHighlightCurrentSpace",
            title: String(localized: "Highlight Current Space"),
            description: String(localized: "Highlights the Space number indicator for windows on the current Space."),
            keywords: ["space", "current", "highlight", "indicator", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "circle.fill"
        ),
        SettingsSearchItem(
            id: "appearance.dockWindowStateIndicator",
            title: String(localized: "Show Window State Indicator"),
            description: String(localized: "Controls whether Minimized, Hidden, and Full Screen indicators are hidden, shown on window previews, or placed next to traffic light buttons."),
            keywords: ["window", "state", "indicator", "minimized", "hidden", "full screen", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "eye.slash"
        ),
        SettingsSearchItem(
            id: "appearance.dockDisableWindowStateIndicatorStyling",
            title: String(localized: "Disable dock styling on Window State Indicator"),
            description: String(localized: "Removes the pill-shaped background styling from the Window State Indicator in dock previews."),
            keywords: ["window", "state", "space", "indicator", "styling", "pill", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "minus.circle"
        ),
        SettingsSearchItem(
            id: "appearance.dockSwapWindowStateIndicator",
            title: String(localized: "Swap Window State Indicator and Traffic Light Buttons"),
            description: String(localized: "Swaps the order of the Window State Indicator and traffic light buttons in dock previews."),
            keywords: ["window", "state", "indicator", "traffic light", "position", "order", "swap", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "arrow.left.arrow.right"
        ),
        SettingsSearchItem(
            id: "appearance.dockLimitIndicatorSwapToCompactMode",
            title: String(localized: "Limit to Compact Mode only"),
            description: String(localized: "Applies the swapped indicator and traffic light button order only in Compact Mode dock previews."),
            keywords: ["window", "state", "indicator", "traffic light", "swap", "compact", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "rectangle"
        ),
        SettingsSearchItem(
            id: "appearance.dockMassActionButtons",
            title: String(localized: "Show Close All and Minimize All buttons"),
            description: String(localized: "Displays Close All and Minimize All buttons when hovering the app header in dock previews."),
            keywords: ["close all", "minimize all", "mass", "buttons"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "xmark.circle"
        ),
        SettingsSearchItem(
            id: "appearance.dockEmbedControls",
            title: String(localized: "Embed controls in preview frames"),
            description: String(localized: "Places traffic light buttons and window titles directly inside the dock preview frames for a more compact and minimal appearance."),
            keywords: ["embed", "controls", "frame", "dock"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "rectangle.inset.filled"
        ),
        SettingsSearchItem(
            id: "appearance.dockMaxRows",
            title: String(localized: "Max Rows (Bottom Dock)"),
            description: String(localized: "Controls how many rows of windows are shown in dock previews."),
            keywords: ["rows", "layout", "dock", "grid"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "rectangle.grid.1x2"
        ),
        SettingsSearchItem(
            id: "appearance.dockMaxColumns",
            title: String(localized: "Max Columns (Left/Right Dock)"),
            description: String(localized: "Controls how many columns of windows are shown in dock previews."),
            keywords: ["columns", "layout", "dock", "grid"],
            tab: "DockPreviews",
            section: String(localized: "Appearance"),
            icon: "rectangle.grid.2x1"
        ),
        // Window Switcher Appearance
        SettingsSearchItem(
            id: "appearance.switcherShowAppHeader",
            title: String(localized: "Show App Header"),
            description: String(localized: "Show app header in the window switcher."),
            keywords: ["app", "header", "name", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "textformat"
        ),
        SettingsSearchItem(
            id: "appearance.switcherAppIconSize",
            title: String(localized: "App Icon Size"),
            keywords: ["app", "icon", "size", "header", "switcher", "title"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "app"
        ),
        SettingsSearchItem(
            id: "appearance.switcherShowAppIconBadges",
            title: String(localized: "Show App Icon Badges"),
            keywords: ["badge", "notification", "count", "app", "icon", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "app.badge"
        ),
        SettingsSearchItem(
            id: "appearance.switcherShowCompactAppIconBadges",
            title: String(localized: "Show App Icon Badges in Compact Mode"),
            keywords: ["badge", "notification", "count", "app", "icon", "compact", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "app.badge"
        ),
        SettingsSearchItem(
            id: "appearance.switcherAppIconBadgeSize",
            title: String(localized: "Badge Size"),
            keywords: ["badge", "notification", "size", "scale", "app", "icon", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "app.badge"
        ),
        SettingsSearchItem(
            id: "appearance.switcherControlPosition",
            title: String(localized: "Position Window Controls"),
            description: String(localized: "Position of window controls in the switcher."),
            keywords: ["position", "controls", "toolbar", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "rectangle.topthird.inset.filled"
        ),
        SettingsSearchItem(
            id: "appearance.switcherTrafficLightVisibility",
            title: String(localized: "Visibility"),
            description: String(localized: "Controls when traffic light buttons appear in the window switcher."),
            keywords: ["traffic light", "visibility", "switcher", "buttons"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "eye"
        ),
        SettingsSearchItem(
            id: "appearance.switcherMonochrome",
            title: String(localized: "Use Monochrome Colors"),
            keywords: ["monochrome", "gray", "traffic light", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "circle.fill"
        ),
        SettingsSearchItem(
            id: "appearance.switcherDisableTrafficLightStyling",
            title: String(localized: "Disable dock styling on traffic light buttons"),
            description: String(localized: "Removes the pill-shaped background styling from traffic light buttons."),
            keywords: ["traffic light", "styling", "pill", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "minus.circle"
        ),
        SettingsSearchItem(
            id: "appearance.switcherSpaceNumberIndicator",
            title: String(localized: "Show Space Number Indicator"),
            description: String(localized: "Shows the Space number for each window in the window switcher."),
            keywords: ["space", "desktop", "number", "indicator", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "number.circle"
        ),
        SettingsSearchItem(
            id: "appearance.switcherHighlightCurrentSpace",
            title: String(localized: "Highlight Current Space"),
            description: String(localized: "Highlights the Space number indicator for windows on the current Space."),
            keywords: ["space", "current", "highlight", "indicator", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "circle.fill"
        ),
        SettingsSearchItem(
            id: "appearance.switcherWindowStateIndicator",
            title: String(localized: "Show Window State Indicator"),
            description: String(localized: "Controls whether Minimized, Hidden, and Full Screen indicators are hidden, shown on window previews, or placed next to traffic light buttons."),
            keywords: ["window", "state", "indicator", "minimized", "hidden", "full screen", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "eye.slash"
        ),
        SettingsSearchItem(
            id: "appearance.switcherDisableWindowStateIndicatorStyling",
            title: String(localized: "Disable dock styling on Window State Indicator"),
            description: String(localized: "Removes the pill-shaped background styling from the Window State Indicator in the window switcher."),
            keywords: ["window", "state", "space", "indicator", "styling", "pill", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "minus.circle"
        ),
        SettingsSearchItem(
            id: "appearance.switcherSwapWindowStateIndicator",
            title: String(localized: "Swap Window State Indicator and Traffic Light Buttons"),
            description: String(localized: "Swaps the order of the Window State Indicator and traffic light buttons in the window switcher."),
            keywords: ["window", "state", "indicator", "traffic light", "position", "order", "swap", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "arrow.left.arrow.right"
        ),
        SettingsSearchItem(
            id: "appearance.switcherLimitIndicatorSwapToCompactMode",
            title: String(localized: "Limit to Compact Mode only"),
            description: String(localized: "Applies the swapped indicator and traffic light button order only in Compact Mode window switcher previews."),
            keywords: ["window", "state", "indicator", "traffic light", "swap", "compact", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "rectangle"
        ),
        SettingsSearchItem(
            id: "appearance.switcherShowWindowTitle",
            title: String(localized: "Show Window Title"),
            description: String(localized: "Show window title in the window switcher."),
            keywords: ["title", "window", "switcher", "show"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "textformat.abc"
        ),
        SettingsSearchItem(
            id: "appearance.switcherWindowTitleVisibility",
            title: String(localized: "Visibility"),
            description: String(localized: "Controls when window titles appear in the switcher."),
            keywords: ["title", "visibility", "hover", "always", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "eye"
        ),
        SettingsSearchItem(
            id: "appearance.switcherScrollDirection",
            title: String(localized: "Scroll Direction"),
            keywords: ["scroll", "direction", "horizontal", "vertical", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "appearance.switcherEmbedControls",
            title: String(localized: "Embed controls in preview frames"),
            description: String(localized: "Places traffic light buttons and window titles directly inside the window switcher preview frames."),
            keywords: ["embed", "controls", "frame", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "rectangle.inset.filled"
        ),
        SettingsSearchItem(
            id: "appearance.switcherMaxRows",
            title: String(localized: "Max Rows"),
            description: String(localized: "Controls how many rows of windows are shown in the window switcher."),
            keywords: ["rows", "columns", "layout", "grid", "switcher"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "rectangle.grid.1x2"
        ),
        SettingsSearchItem(
            id: "appearance.switcherIgnoreScreenLimit",
            title: String(localized: "Ignore screen size limit"),
            description: String(localized: "Allow columns/rows to exceed what fits on screen."),
            keywords: ["screen", "limit", "overflow", "exceed"],
            tab: "WindowSwitcher",
            section: String(localized: "Appearance"),
            icon: "arrow.up.left.and.arrow.down.right"
        ),
        // Cmd+Tab Appearance
        SettingsSearchItem(
            id: "appearance.cmdTabShowAppHeader",
            title: String(localized: "Show App Header"),
            description: String(localized: "Show app header in Cmd+Tab overlay."),
            keywords: ["app", "header", "name", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "textformat"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabAppHeaderStyle",
            title: String(localized: "App Header Style"),
            keywords: ["header", "style", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "textformat"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabShowAppIconOnly",
            title: String(localized: "Show App Icon Only"),
            keywords: ["icon", "only", "header", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "app.badge"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabControlPosition",
            title: String(localized: "Position Window Controls"),
            description: String(localized: "Position of window controls in Cmd+Tab overlay."),
            keywords: ["position", "controls", "toolbar", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "rectangle.topthird.inset.filled"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabShowWindowTitle",
            title: String(localized: "Show Window Title"),
            description: String(localized: "Show window title in Cmd+Tab overlay."),
            keywords: ["title", "window", "cmd tab", "show"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "textformat.abc"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabWindowTitleVisibility",
            title: String(localized: "Window Title Visibility"),
            keywords: ["title", "visibility", "hover", "always", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "eye"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabDisableTitleStyling",
            title: String(localized: "Disable dock styling on window titles"),
            description: String(localized: "Removes the pill-shaped background styling from window titles."),
            keywords: ["styling", "pill", "title", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "textformat.abc.dottedunderline"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabTrafficLightVisibility",
            title: String(localized: "Visibility"),
            description: String(localized: "Controls when traffic light buttons appear in Cmd+Tab overlay."),
            keywords: ["traffic light", "visibility", "cmd tab", "buttons"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "eye"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabMonochrome",
            title: String(localized: "Use Monochrome Colors"),
            keywords: ["monochrome", "gray", "traffic light", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "circle.fill"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabDisableTrafficLightStyling",
            title: String(localized: "Disable dock styling on traffic light buttons"),
            description: String(localized: "Removes the pill-shaped background styling from traffic light buttons."),
            keywords: ["traffic light", "styling", "pill", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "minus.circle"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabSpaceNumberIndicator",
            title: String(localized: "Show Space Number Indicator"),
            description: String(localized: "Shows the Space number for each window in Cmd+Tab previews."),
            keywords: ["space", "desktop", "number", "indicator", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "number.circle"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabHighlightCurrentSpace",
            title: String(localized: "Highlight Current Space"),
            description: String(localized: "Highlights the Space number indicator for windows on the current Space."),
            keywords: ["space", "current", "highlight", "indicator", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "circle.fill"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabWindowStateIndicator",
            title: String(localized: "Show Window State Indicator"),
            description: String(localized: "Controls whether Minimized, Hidden, and Full Screen indicators are hidden, shown on window previews, or placed next to traffic light buttons."),
            keywords: ["window", "state", "indicator", "minimized", "hidden", "full screen", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "eye.slash"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabDisableWindowStateIndicatorStyling",
            title: String(localized: "Disable dock styling on Window State Indicator"),
            description: String(localized: "Removes the pill-shaped background styling from the Window State Indicator in Cmd+Tab previews."),
            keywords: ["window", "state", "space", "indicator", "styling", "pill", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "minus.circle"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabSwapWindowStateIndicator",
            title: String(localized: "Swap Window State Indicator and Traffic Light Buttons"),
            description: String(localized: "Swaps the order of the Window State Indicator and traffic light buttons in Cmd+Tab previews."),
            keywords: ["window", "state", "indicator", "traffic light", "position", "order", "swap", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "arrow.left.arrow.right"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabLimitIndicatorSwapToCompactMode",
            title: String(localized: "Limit to Compact Mode only"),
            description: String(localized: "Applies the swapped indicator and traffic light button order only in Compact Mode Cmd+Tab previews."),
            keywords: ["window", "state", "indicator", "traffic light", "swap", "compact", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "rectangle"
        ),
        SettingsSearchItem(
            id: "appearance.cmdTabEmbedControls",
            title: String(localized: "Embed controls in preview frames"),
            description: String(localized: "Places traffic light buttons and window titles directly inside the preview frames."),
            keywords: ["embed", "controls", "frame", "cmd tab"],
            tab: "CmdTab",
            section: String(localized: "Appearance"),
            icon: "rectangle.inset.filled"
        ),
    ]

    private static let glassItems: [SettingsSearchItem] = {
        if #available(macOS 26.0, *), LiquidGlass.usesModernPipeline {
            return [
                SettingsSearchItem(
                    id: "appearance.glassOpacity",
                    title: String(localized: "Opacity"),
                    description: String(localized: "Adjusts how much of the screen shows through the Liquid Glass background."),
                    keywords: ["glass", "opacity", "liquid", "clear", "opaque", "transparency"],
                    tab: "Appearance",
                    section: String(localized: "Background"),
                    icon: "circle.lefthalf.filled"
                ),
                SettingsSearchItem(
                    id: "appearance.glassRefraction",
                    title: String(localized: "Refraction"),
                    description: String(localized: "Bends the background at the edges and adds a bright rim. Turn off for softer frosted glass that is easier to read over busy backgrounds."),
                    keywords: ["glass", "refraction", "liquid", "rim", "lens", "frosted"],
                    tab: "Appearance",
                    section: String(localized: "Background"),
                    icon: "sparkles"
                ),
            ]
        }
        return [
            SettingsSearchItem(
                id: "appearance.glassTuning",
                title: String(localized: "Glass Tuning"),
                description: String(localized: "Fine-tune opacity, blur, saturation, tint, and border for glass background style."),
                keywords: ["glass", "opacity", "blur", "saturation", "tint", "border", "tuning", "variant"],
                tab: "Appearance",
                section: String(localized: "Background"),
                icon: "slider.horizontal.3"
            ),
            SettingsSearchItem(
                id: "appearance.glassVariant",
                title: String(localized: "Glass Variant"),
                description: String(localized: "Selects the liquid glass material variant used for the background."),
                keywords: ["glass", "variant", "liquid", "material", "style", "look"],
                tab: "Appearance",
                section: String(localized: "Background"),
                icon: "sparkles"
            ),
        ]
    }()

    // MARK: - Gestures & Keybinds

    private static let gesturesItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            id: "gestures.dockScroll",
            title: String(localized: "Enable scroll gestures on dock icons"),
            description: String(localized: "Choose what happens when scrolling directly on a dock icon."),
            keywords: ["scroll", "dock", "gesture", "hide", "front"],
            tab: "GesturesKeybinds",
            section: String(localized: "Dock Icon Scroll Gesture"),
            icon: "arrow.up.and.down.circle"
        ),
        SettingsSearchItem(
            id: "gestures.titleBarScroll",
            title: String(localized: "Enable scroll gestures on active window title bars"),
            description: String(localized: "Scroll up on a focused window title bar to maximize it, scroll down to center it using the configured window size, and scroll left or right to switch desktop spaces. Repeat the same up/down scroll within the configured restore time to restore the previous window size."),
            keywords: ["title bar", "scroll", "maximize", "center", "spaces"],
            tab: "GesturesKeybinds",
            section: String(localized: "Title Bar Scroll Gesture"),
            icon: "arrow.up.and.down.text.horizontal"
        ),
        SettingsSearchItem(
            id: "gestures.dockPreview",
            title: String(localized: "Enable gestures on dock window previews"),
            description: String(localized: "Swipe on window previews in the dock popup. Direction is relative to dock position — swipe towards the dock (e.g., down when dock is at bottom, left when dock is on left)."),
            keywords: ["swipe", "gesture", "preview", "dock"],
            tab: "GesturesKeybinds",
            section: String(localized: "Dock Preview Gestures"),
            icon: "hand.draw"
        ),
        SettingsSearchItem(
            id: "gestures.sensitivity",
            title: String(localized: "Gesture Sensitivity"),
            description: String(localized: "Lower values make gestures more sensitive. Higher values require longer swipes. Applies to both dock previews and window switcher."),
            keywords: ["sensitivity", "threshold", "swipe"],
            tab: "GesturesKeybinds",
            section: String(localized: "Gesture Settings"),
            icon: "slider.horizontal.3"
        ),
        SettingsSearchItem(
            id: "gestures.middleClick",
            title: String(localized: "Middle Click"),
            description: String(localized: "Action performed when middle-clicking on a window preview."),
            keywords: ["middle", "click", "mouse", "button", "open", "activate", "window", "app"],
            tab: "GesturesKeybinds",
            section: String(localized: "Mouse Actions"),
            icon: "computermouse"
        ),
        SettingsSearchItem(
            id: "gestures.cmdShortcuts",
            title: String(localized: "Window Preview Keyboard Shortcuts"),
            description: String(localized: "Uses the active Window Switcher modifier for preview actions. Cmd+Tab uses Command while the macOS switcher is active."),
            keywords: ["shortcut", "modifier", "command", "option", "control", "keyboard", "hotkey"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Preview Keyboard Shortcuts"),
            icon: "command"
        ),
        SettingsSearchItem(
            id: "gestures.postActionMovingResizing",
            title: String(localized: "Move/Resize"),
            description: String(localized: "Choose what happens after each action type is triggered from shortcuts, gestures, middle-click, and preview buttons."),
            keywords: ["post action", "after action", "move", "resize", "focus", "close previews"],
            tab: "GesturesKeybinds",
            section: String(localized: "Keep previews open after action"),
            icon: "arrow.up.left.and.arrow.down.right"
        ),
        SettingsSearchItem(
            id: "gestures.moveResizeForeground",
            title: String(localized: "Bring moved/resized window to the front"),
            keywords: ["move", "resize", "foreground", "bring to front", "space"],
            tab: "GesturesKeybinds",
            section: String(localized: "Keep previews open after action"),
            icon: "arrow.up.forward.app"
        ),
        SettingsSearchItem(
            id: "gestures.postActionHiding",
            title: String(localized: "Hide/Minimize"),
            description: String(localized: "Choose what happens after each action type is triggered from shortcuts, gestures, middle-click, and preview buttons."),
            keywords: ["post action", "after action", "hide", "minimize", "focus", "close previews"],
            tab: "GesturesKeybinds",
            section: String(localized: "Keep previews open after action"),
            icon: "eye.slash"
        ),
        SettingsSearchItem(
            id: "gestures.postActionUnhiding",
            title: String(localized: "Unhide/Unminimize"),
            description: String(localized: "Choose what happens after each action type is triggered from shortcuts, gestures, middle-click, and preview buttons."),
            keywords: ["post action", "after action", "unhide", "restore", "focus", "close previews"],
            tab: "GesturesKeybinds",
            section: String(localized: "Keep previews open after action"),
            icon: "eye"
        ),
        SettingsSearchItem(
            id: "gestures.postActionClosing",
            title: String(localized: "Close/Quit"),
            description: String(localized: "Choose what happens after each action type is triggered from shortcuts, gestures, middle-click, and preview buttons."),
            keywords: ["post action", "after action", "close", "quit", "focus", "close previews"],
            tab: "GesturesKeybinds",
            section: String(localized: "Keep previews open after action"),
            icon: "xmark.circle"
        ),
        SettingsSearchItem(
            id: "gestures.postActionNewWindow",
            title: String(localized: "New Window"),
            description: String(localized: "Choose what happens after each action type is triggered from shortcuts, gestures, middle-click, and preview buttons."),
            keywords: ["post action", "after action", "new window", "cmd n", "focus", "close previews"],
            tab: "GesturesKeybinds",
            section: String(localized: "Keep previews open after action"),
            icon: "plus.rectangle.on.rectangle"
        ),
        SettingsSearchItem(
            id: "gestures.switcherKeybind",
            title: String(localized: "Window Switcher Shortcuts"),
            keywords: ["keybind", "shortcut", "alt tab", "switcher", "initializer"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "keyboard"
        ),
        SettingsSearchItem(
            id: "gestures.enableSpaceIndicatorWindowMoving",
            title: String(localized: "Use Space Number Indicator to move windows to Spaces"),
            description: String(localized: "Click the Space Number Indicator to list available Spaces. Choosing a Space will move the selected window there."),
            keywords: ["space", "desktop", "move window", "indicator"],
            tab: "GesturesKeybinds",
            section: String(localized: "Spaces"),
            icon: "rectangle.on.rectangle"
        ),
        SettingsSearchItem(
            id: "gestures.spaceMenuDisplayMode",
            title: String(localized: "Display available Spaces as:"),
            keywords: ["space", "desktop", "number", "name", "menu"],
            tab: "GesturesKeybinds",
            section: String(localized: "Spaces"),
            icon: "textformat"
        ),
        SettingsSearchItem(
            id: "gestures.showCurrentSpaceBadgeInMenu",
            title: String(localized: "Show “Current” badge in the Spaces dropdown"),
            description: String(localized: "Labels the currently active Space with a “Current” badge."),
            keywords: ["space", "desktop", "current", "active", "badge", "menu"],
            tab: "GesturesKeybinds",
            section: String(localized: "Spaces"),
            icon: "tag"
        ),
        SettingsSearchItem(
            id: "gestures.switchToDestinationSpaceAfterMoving",
            title: String(localized: "Switch to the destination Space after moving the window"),
            keywords: ["space", "desktop", "switch", "focus", "move window"],
            tab: "GesturesKeybinds",
            section: String(localized: "Spaces"),
            icon: "arrow.right.to.line"
        ),
        SettingsSearchItem(
            id: "gestures.showUnavailableSpacesInMenu",
            title: String(localized: "Show unavailable Spaces in the list"),
            description: String(localized: "Show Spaces the window cannot be moved to in the Spaces dropdown menu."),
            keywords: ["space", "desktop", "fullscreen", "unavailable", "menu"],
            tab: "GesturesKeybinds",
            section: String(localized: "Spaces"),
            icon: "rectangle.slash"
        ),
        SettingsSearchItem(
            id: "gestures.enableMultiWindowSelection",
            title: String(localized: "Enable multi-window selection"),
            description: String(localized: "Check windows using selection controls or the Toggle Window Selection action. Checked windows keep Window Switcher previews open; Dock previews retain normal hover dismissal. Escape or clicking outside closes previews and clears selection. Mixed selections minimize or hide when any applicable target is unminimized or visible; otherwise they restore or unhide. Fullscreen exits all selected fullscreen windows. If none are fullscreen, only the clicked or highlighted window enters fullscreen."),
            keywords: ["selection", "multiple", "check", "batch", "escape"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Selection & Tiling"),
            icon: "checkmark.circle"
        ),
        SettingsSearchItem(
            id: "gestures.showWindowSelectionSummary",
            title: String(localized: "Show selection summary"),
            keywords: ["selection", "count", "clear", "header"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Selection & Tiling"),
            icon: "checkmark.circle"
        ),
        SettingsSearchItem(
            id: "gestures.showUncheckedSelectionCheckboxes",
            title: String(localized: "Show unchecked selection checkboxes"),
            description: String(localized: "Checked controls stay visible. Preview hover includes keyboard highlighting. In Compact Mode, On title hover uses icon hover; other options use preview hover. Hidden titles outside Compact Mode fall back to preview hover."),
            keywords: ["selection", "checkbox", "title", "icon"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Selection & Tiling"),
            icon: "checkmark.circle"
        ),
        SettingsSearchItem(
            id: "gestures.selectionCheckboxVisibility",
            title: String(localized: "Checkbox visibility:"),
            description: String(localized: "Checked controls stay visible. Preview hover includes keyboard highlighting. In Compact Mode, On title hover uses icon hover; other options use preview hover. Hidden titles outside Compact Mode fall back to preview hover."),
            keywords: ["selection", "checkbox", "hover", "title", "visibility"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Selection & Tiling"),
            icon: "checkmark.circle"
        ),
        SettingsSearchItem(
            id: "gestures.maximumTilingRows",
            title: String(localized: "Maximum tiling rows:"),
            description: String(localized: "The first checked window leads. Auto Tile Selected Windows and Half/Quarter actions arrange checked groups on the current Desktop. Set both limits to 1 to move windows without resizing. Overflowing groups repeat the same layout."),
            keywords: ["selection", "tile", "grid", "rows", "capacity"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Selection & Tiling"),
            icon: "rectangle.split.2x2"
        ),
        SettingsSearchItem(
            id: "gestures.maximumTilingColumns",
            title: String(localized: "Maximum tiling columns:"),
            description: String(localized: "The first checked window leads. Auto Tile Selected Windows and Half/Quarter actions arrange checked groups on the current Desktop. Set both limits to 1 to move windows without resizing. Overflowing groups repeat the same layout."),
            keywords: ["selection", "tile", "grid", "columns", "capacity"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Selection & Tiling"),
            icon: "rectangle.split.2x2"
        ),
        SettingsSearchItem(
            id: "gestures.enableSpacesShortcuts",
            title: String(localized: "Enable Spaces Shortcuts"),
            description: String(localized: "When a window preview is focused, press the Window Switcher modifier plus a number to move the window to that numbered Desktop. When Window Switcher is open without a focused preview, the same shortcut switches to that numbered Space."),
            keywords: ["space", "desktop", "number", "shortcut", "move window", "switch space"],
            tab: "GesturesKeybinds",
            section: String(localized: "Spaces"),
            icon: "keyboard.badge.ellipsis"
        ),
        SettingsSearchItem(
            id: "gestures.menuBarIconWindowSwitcher",
            title: String(localized: "Menu bar icon"),
            description: String(localized: "Open Window Switcher when clicking on menu bar icon"),
            keywords: ["menu bar", "status item", "click", "window switcher"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "menubar.rectangle"
        ),
        SettingsSearchItem(
            id: "gestures.menuBarIconClickBehavior",
            title: String(localized: "Left/right clicks trigger:"),
            description: String(localized: "Choose which mouse button opens Window Switcher from the menu bar icon."),
            keywords: ["menu bar", "left click", "right click", "mouse", "window switcher"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "computermouse"
        ),
        SettingsSearchItem(
            id: "gestures.vimMotions",
            title: String(localized: "Enable Vim Motions"),
            description: String(localized: "Use H/J/K/L keys to navigate left/down/up/right in the window switcher. Disabled while search is focused."),
            keywords: ["vim", "hjkl", "navigation"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "character.textbox"
        ),
        SettingsSearchItem(
            id: "gestures.arrowPassthrough",
            title: String(localized: "Pass Arrow Keys Through to System"),
            description: String(localized: "When enabled, Ctrl+Arrow keys will be passed through to the system instead of navigating the switcher. Useful for Spaces switching."),
            keywords: ["arrow", "passthrough", "spaces", "ctrl"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "arrow.left.arrow.right"
        ),
        SettingsSearchItem(
            id: "gestures.switcherGestures",
            title: String(localized: "Enable gestures in window switcher"),
            description: String(localized: "Swipe up or down on window previews in the keyboard-activated window switcher. Only vertical swipes are recognized, unless in compact mode."),
            keywords: ["swipe", "gesture", "switcher"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Gestures"),
            icon: "hand.draw"
        ),
        // Dock Scroll - additional
        SettingsSearchItem(
            id: "gestures.dockIconScroll",
            title: String(localized: "Dock icon scroll:"),
            description: String(localized: "Choose what happens when scrolling directly on a dock icon."),
            keywords: ["scroll", "dock", "space", "desktop", "activate", "hide"],
            tab: "GesturesKeybinds",
            section: String(localized: "Dock Icon Scroll Gesture"),
            icon: "dock.rectangle"
        ),
        SettingsSearchItem(
            id: "gestures.musicScroll",
            title: String(localized: "Music & Spotify dock icon scroll"),
            description: String(localized: "Only applies when scrolling directly on Apple Music or Spotify dock icons."),
            keywords: ["music", "spotify", "scroll", "volume", "track"],
            tab: "GesturesKeybinds",
            section: String(localized: "Dock Icon Scroll Gesture"),
            icon: "music.note"
        ),
        // Title Bar Scroll - additional
        SettingsSearchItem(
            id: "gestures.centeredSizingMode",
            title: String(localized: "Centered Window Sizing"),
            keywords: ["centered", "sizing", "uniform", "separate"],
            tab: "GesturesKeybinds",
            section: String(localized: "Title Bar Scroll Gesture"),
            icon: "rectangle.center.inset.filled"
        ),
        SettingsSearchItem(
            id: "gestures.centeredWindowSize",
            title: String(localized: "Centered Window Size"),
            keywords: ["centered", "size", "scale", "percent"],
            tab: "GesturesKeybinds",
            section: String(localized: "Title Bar Scroll Gesture"),
            icon: "arrow.up.left.and.arrow.down.right"
        ),
        SettingsSearchItem(
            id: "gestures.centeredLockAspect",
            title: String(localized: "Lock aspect ratio (uniform scaling)"),
            keywords: ["aspect", "ratio", "lock", "centered"],
            tab: "GesturesKeybinds",
            section: String(localized: "Title Bar Scroll Gesture"),
            icon: "aspectratio"
        ),
        SettingsSearchItem(
            id: "gestures.centeredWidth",
            title: String(localized: "Centered Window Width"),
            keywords: ["centered", "width", "size"],
            tab: "GesturesKeybinds",
            section: String(localized: "Title Bar Scroll Gesture"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "gestures.centeredHeight",
            title: String(localized: "Centered Window Height"),
            keywords: ["centered", "height", "size"],
            tab: "GesturesKeybinds",
            section: String(localized: "Title Bar Scroll Gesture"),
            icon: "arrow.up.and.down"
        ),
        SettingsSearchItem(
            id: "gestures.restoreTime",
            title: String(localized: "Restore Window Time"),
            description: String(localized: "Repeat the same up/down scroll within this time to restore the previous window size."),
            keywords: ["restore", "time", "interval", "undo"],
            tab: "GesturesKeybinds",
            section: String(localized: "Title Bar Scroll Gesture"),
            icon: "clock.arrow.circlepath"
        ),
        // Dock Preview Gestures - additional
        SettingsSearchItem(
            id: "gestures.swipeTowardsDock",
            title: String(localized: "Towards Dock"),
            description: String(localized: "Swipe toward the dock edge"),
            keywords: ["swipe", "towards", "dock", "action"],
            tab: "GesturesKeybinds",
            section: String(localized: "Dock Preview Gestures"),
            icon: "arrow.down.to.line"
        ),
        SettingsSearchItem(
            id: "gestures.swipeAwayFromDock",
            title: String(localized: "Away from Dock"),
            description: String(localized: "Swipe away from the dock edge"),
            keywords: ["swipe", "away", "dock", "action"],
            tab: "GesturesKeybinds",
            section: String(localized: "Dock Preview Gestures"),
            icon: "arrow.up.to.line"
        ),
        SettingsSearchItem(
            id: "gestures.aeroShake",
            title: String(localized: "Aero Shake"),
            description: String(localized: "Shake a window preview rapidly"),
            keywords: ["aero", "shake", "rapid", "action"],
            tab: "GesturesKeybinds",
            section: String(localized: "Dock Preview Gestures"),
            icon: "hand.point.up.left.and.text"
        ),
        // Window Switcher Shortcuts - additional
        SettingsSearchItem(
            id: "gestures.backwardKey",
            title: String(localized: "Backward Key"),
            description: String(localized: "The key used to navigate backward in the window switcher."),
            keywords: ["backward", "key", "navigate", "back"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "arrow.left"
        ),
        SettingsSearchItem(
            id: "gestures.requireShiftTab",
            title: String(localized: "Require \u{21E7}+Tab to go back in Switcher"),
            keywords: ["shift", "tab", "back", "require"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "arrow.uturn.backward"
        ),
        SettingsSearchItem(
            id: "gestures.ignoreMainModifierSideForDependentShortcuts",
            title: String(localized: "Ignore modifier key side for Window Preview Keyboard Shortcuts"),
            description: String(localized: "Allows either side of the selected modifier to trigger shortcuts that inherit the main Window Switcher modifier. The main Window Switcher shortcut still uses the selected side."),
            keywords: ["modifier", "side", "left", "right", "either", "preview", "spaces", "shortcut"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "arrow.left.arrow.right"
        ),
        SettingsSearchItem(
            id: "gestures.selectionKey",
            title: String(localized: "Selection Key"),
            description: String(localized: "The key used to select and bring to front the highlighted window in the switcher."),
            keywords: ["selection", "key", "enter", "return", "select"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "return"
        ),
        SettingsSearchItem(
            id: "gestures.alternateShortcuts",
            title: String(localized: "Alternate Shortcuts (Inherit Default Window Switcher)"),
            description: String(localized: "Additional trigger keys, each with its own modifier and window filter."),
            keywords: ["alternate", "shortcuts", "trigger", "filter", "mode", "modifier", "multiple", "monitor", "display", "space"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "keyboard"
        ),
        SettingsSearchItem(
            id: "gestures.persistentSwitcherShortcuts",
            title: String(localized: "Alternate Shortcuts (Persistent Window Switcher)"),
            description: String(localized: "Releasing initializer keys will always keep the Window Switcher open. Window preview keyboard shortcuts use the default modifier key."),
            keywords: ["alternate", "shortcut", "persistent", "keep", "open", "double", "tap", "modifier", "monitor", "display", "space"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "keyboard.badge.ellipsis"
        ),
        SettingsSearchItem(
            id: "gestures.persistentSwitcherStartsUnfocused",
            title: String(localized: "Start Persistent Window Switcher with no window highlighted"),
            description: String(localized: "Also applies when opening the Window Switcher from the menu bar icon."),
            keywords: ["persistent", "keep", "open", "selection", "highlight", "unfocused", "menu bar"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "rectangle.dashed"
        ),
        SettingsSearchItem(
            id: "gestures.lastFocusedWindowShortcuts",
            title: String(localized: "Switch to Last Focused Window"),
            description: String(localized: "Instantly switch to the last focused window."),
            keywords: ["last", "focused", "previous", "recent", "window", "shortcut", "mru", "double", "tap", "monitor", "display", "space"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "arrow.uturn.backward"
        ),
        SettingsSearchItem(
            id: "gestures.searchTriggerKey",
            title: String(localized: "Search Trigger Key"),
            description: String(localized: "The key that activates search while the window switcher is open."),
            keywords: ["search", "trigger", "key", "activate"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "magnifyingglass"
        ),
        SettingsSearchItem(
            id: "gestures.fullscreenBlacklist",
            title: String(localized: "Fullscreen App Blacklist"),
            description: String(localized: "Apps in this list will not respond to window switcher shortcuts when in fullscreen mode."),
            keywords: ["fullscreen", "blacklist", "exclude", "app"],
            tab: "GesturesKeybinds",
            section: String(localized: "Window Switcher Shortcuts"),
            icon: "app.badge.checkmark"
        ),
        // Trackpad Swipe for Window Switcher
        SettingsSearchItem(
            id: "gestures.trackpadSwitcherSwipe",
            title: String(localized: "Open window switcher with a trackpad swipe"),
            description: String(localized: "Swipe to open the switcher, keep your fingers down and move left or right to change the selection, then lift your fingers to switch."),
            keywords: ["trackpad", "swipe", "three finger", "four finger", "gesture", "switcher", "alt tab"],
            tab: "GesturesKeybinds",
            section: String(localized: "Trackpad Swipe for Window Switcher"),
            icon: "hand.draw"
        ),
        SettingsSearchItem(
            id: "gestures.trackpadSwitcherSwipeFingers",
            title: String(localized: "Fingers:"),
            keywords: ["trackpad", "fingers", "three", "four", "swipe"],
            tab: "GesturesKeybinds",
            section: String(localized: "Trackpad Swipe for Window Switcher"),
            icon: "hand.raised"
        ),
        SettingsSearchItem(
            id: "gestures.trackpadSwitcherSwipeDirection",
            title: String(localized: "Direction:"),
            keywords: ["trackpad", "direction", "horizontal", "vertical", "swipe"],
            tab: "GesturesKeybinds",
            section: String(localized: "Trackpad Swipe for Window Switcher"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "gestures.reverseTrackpadSwipeSelectionDirection",
            title: String(localized: "Reverse swipe selection direction"),
            keywords: ["trackpad", "swipe", "reverse", "invert", "selection", "direction"],
            tab: "GesturesKeybinds",
            section: String(localized: "Trackpad Swipe for Window Switcher"),
            icon: "arrow.left.arrow.right"
        ),
        SettingsSearchItem(
            id: "gestures.trackpadSwitcherSwipePersistentSelection",
            title: String(localized: "Select highlighted window when swiping in persistent Window Switchers"),
            description: String(localized: "Swiping takes over persistent Window Switchers and unfocuses search. Lift your fingers to activate the selected window. Regular Window Switchers remain controlled by their initializer key while it is held."),
            keywords: ["trackpad", "swipe", "persistent", "keep open", "takeover", "select", "release", "search"],
            tab: "GesturesKeybinds",
            section: String(localized: "Trackpad Swipe for Window Switcher"),
            icon: "hand.draw"
        ),
    ]

    // MARK: - Filters

    private static let filtersItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            id: "filters.appDirectories",
            title: String(localized: "Custom Application Directories"),
            description: String(localized: "Add additional directories to scan for applications. This is useful if you keep apps outside standard locations."),
            keywords: ["directory", "folder", "path", "scan"],
            tab: "Filters",
            section: String(localized: "Custom Application Directories"),
            icon: "folder"
        ),
        SettingsSearchItem(
            id: "filters.appFilters",
            title: String(localized: "Application Filters"),
            description: String(localized: "Hide specific applications from DockDoor previews."),
            keywords: ["blacklist", "hide", "exclude", "app", "block"],
            tab: "Filters",
            section: String(localized: "Application Filters"),
            icon: "app.badge.checkmark"
        ),
        SettingsSearchItem(
            id: "filters.windowTitle",
            title: String(localized: "Window Title Filters"),
            description: String(localized: "Exclude windows from capture by filtering specific text in their titles (case-insensitive)."),
            keywords: ["title", "filter", "exclude", "text"],
            tab: "Filters",
            section: String(localized: "Window Title Filters"),
            icon: "textformat"
        ),
        SettingsSearchItem(
            id: "filters.widgetApps",
            title: String(localized: "Widget App Filters"),
            description: String(localized: "Disable dock hover widgets for selected apps while keeping their regular previews. Useful for browsers that expose media sessions like YouTube."),
            keywords: ["widget", "disable", "media", "youtube"],
            tab: "Filters",
            section: String(localized: "Widget App Filters"),
            icon: "square.grid.2x2"
        ),
    ]

    // MARK: - Widgets

    private static let widgetItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            id: "widgets.enable",
            title: String(localized: "Enable widget controls on Dock hover"),
            keywords: ["widget", "controls", "dock", "hover"],
            tab: "Widgets",
            section: String(localized: "Widget Controls"),
            icon: "square.grid.2x2"
        ),
        SettingsSearchItem(
            id: "widgets.media",
            title: String(localized: "Media controls"),
            description: String(localized: "Show now playing controls when hovering the active media source's Dock icon. Works with any app."),
            keywords: ["media", "music", "now playing", "controls"],
            tab: "Widgets",
            section: String(localized: "Widget Controls"),
            icon: "play.circle"
        ),
        SettingsSearchItem(
            id: "widgets.calendar",
            title: String(localized: "Calendar widget"),
            description: String(localized: "Show today's events when hovering the Calendar Dock icon."),
            keywords: ["calendar", "events", "today", "schedule"],
            tab: "Widgets",
            section: String(localized: "Widget Controls"),
            icon: "calendar"
        ),
        SettingsSearchItem(
            id: "widgets.embedded",
            title: String(localized: "Show widget controls alongside window previews"),
            description: String(localized: "Keeps window previews visible when widget controls are shown."),
            keywords: ["embed", "inline", "alongside", "previews"],
            tab: "Widgets",
            section: String(localized: "Display"),
            icon: "rectangle.on.rectangle"
        ),
        SettingsSearchItem(
            id: "widgets.fullSize",
            title: String(localized: "Use full-size controls when all windows are minimized or hidden"),
            keywords: ["full", "size", "big", "large", "minimized", "hidden"],
            tab: "Widgets",
            section: String(localized: "Display"),
            icon: "rectangle.expand.vertical"
        ),
        SettingsSearchItem(
            id: "widgets.scrollBehavior",
            title: String(localized: "Behavior:"),
            description: String(localized: "Controls what happens when you scroll on the media widget preview."),
            keywords: ["scroll", "media", "volume", "track"],
            tab: "Widgets",
            section: String(localized: "Media Widget Scroll"),
            icon: "arrow.up.and.down"
        ),
        SettingsSearchItem(
            id: "widgets.detectionMode",
            title: String(localized: "Detection mode:"),
            keywords: ["detection", "mode", "media", "source"],
            tab: "Widgets",
            section: String(localized: "Widget Controls"),
            icon: "antenna.radiowaves.left.and.right"
        ),
        SettingsSearchItem(
            id: "widgets.scrollDirection",
            title: String(localized: "Direction:"),
            description: String(localized: "Horizontal scrolling may interfere with dock preview gestures."),
            keywords: ["scroll", "direction", "horizontal", "vertical", "media"],
            tab: "Widgets",
            section: String(localized: "Media Widget Scroll"),
            icon: "arrow.left.and.right"
        ),
        SettingsSearchItem(
            id: "widgets.folder",
            title: String(localized: "Show folder contents on hover"),
            description: String(localized: "Preview a folder's contents when hovering it in the Dock."),
            keywords: ["folder", "directory", "dock", "hover", "files", "widget"],
            tab: "DockPreviews",
            section: String(localized: "Folder Previews"),
            icon: "folder"
        ),
        SettingsSearchItem(
            id: "widgets.folderSort",
            title: String(localized: "Default sort:"),
            keywords: ["folder", "sort", "order", "name", "date", "kind", "size"],
            tab: "DockPreviews",
            section: String(localized: "Folder Previews"),
            icon: "arrow.up.arrow.down"
        ),
        SettingsSearchItem(
            id: "widgets.folderSortDirection",
            title: String(localized: "Sort descending by default"),
            keywords: ["folder", "sort", "descending", "ascending", "direction"],
            tab: "DockPreviews",
            section: String(localized: "Folder Previews"),
            icon: "arrow.down"
        ),
        SettingsSearchItem(
            id: "widgets.folderRememberSort",
            title: String(localized: "Remember sorting per folder"),
            keywords: ["folder", "sort", "remember", "per", "directory"],
            tab: "DockPreviews",
            section: String(localized: "Folder Previews"),
            icon: "folder.badge.gearshape"
        ),
        SettingsSearchItem(
            id: "widgets.folderHiddenFiles",
            title: String(localized: "Show hidden files"),
            keywords: ["folder", "hidden", "dotfiles", "files"],
            tab: "DockPreviews",
            section: String(localized: "Folder Previews"),
            icon: "eye"
        ),
    ]

    private static let pinningItems: [SettingsSearchItem] = {
        guard #available(macOS 15.0, *) else { return [] }
        return [
            SettingsSearchItem(
                id: "widgets.pinning",
                title: String(localized: "Allow pinning controls to screen"),
                description: String(localized: "Right-click a media or calendar widget to pin it."),
                keywords: ["pin", "stick", "float", "always"],
                tab: "Widgets",
                section: String(localized: "Display"),
                icon: "pin"
            ),
        ]
    }()

    // MARK: - Advanced

    private static let advancedItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            id: "advanced.enableSpringLoading",
            title: String(localized: "Enable spring-loading"),
            description: String(localized: "Spring-loading reveals and activates a window after you drag an item over its preview in Dock previews, Window Switcher, or Cmd+Tab."),
            keywords: ["spring", "loading", "drag", "hover", "activate", "window"],
            tab: "Advanced",
            section: String(localized: "Spring-loading"),
            icon: "cursorarrow.motionlines"
        ),
        SettingsSearchItem(
            id: "advanced.useSystemSpringLoadingSpeed",
            title: String(localized: "Use system spring-loading speed"),
            keywords: ["spring", "loading", "system", "speed", "delay"],
            tab: "Advanced",
            section: String(localized: "Spring-loading"),
            icon: "timer"
        ),
        SettingsSearchItem(
            id: "advanced.springLoadingDelay",
            title: String(localized: "Spring-loading delay"),
            keywords: ["spring", "loading", "custom", "speed", "delay", "timer"],
            tab: "Advanced",
            section: String(localized: "Spring-loading"),
            icon: "timer"
        ),
        SettingsSearchItem(
            id: "advanced.openDelay",
            title: String(localized: "Preview Window Open Delay"),
            keywords: ["delay", "open", "hover", "timer"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "timer"
        ),
        SettingsSearchItem(
            id: "advanced.delayOnlyInitial",
            title: String(localized: "Only use delay for initial window opening"),
            description: String(localized: "Switching between dock icons while a preview is already open will show previews instantly."),
            keywords: ["delay", "initial", "instant"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "bolt"
        ),
        SettingsSearchItem(
            id: "advanced.fadeOut",
            title: String(localized: "Preview Window Fade Out Duration"),
            keywords: ["fade", "duration", "close", "animation"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "rectangle.portrait.and.arrow.right"
        ),
        SettingsSearchItem(
            id: "advanced.inactivity",
            title: String(localized: "Preview Window Inactivity Timer"),
            keywords: ["inactivity", "timeout", "idle", "timer"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "clock"
        ),
        SettingsSearchItem(
            id: "advanced.debounce",
            title: String(localized: "Window Processing Debounce Interval"),
            keywords: ["debounce", "processing", "performance"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "gauge.with.dots.needle.bottom.50percent"
        ),
        SettingsSearchItem(
            id: "advanced.programmaticResizeRefreshDelay",
            title: String(localized: "Programmatic Resize Preview Refresh Delay"),
            keywords: ["resize", "preview", "refresh", "programmatic", "delay"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        ),
        SettingsSearchItem(
            id: "advanced.nativeResizeRefreshDelay",
            title: String(localized: "Native Resize Preview Refresh Delay"),
            keywords: ["resize", "preview", "refresh", "native", "ax", "delay"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        ),
        SettingsSearchItem(
            id: "advanced.anchorPosition",
            title: String(localized: "Anchor preview to initial dock icon position"),
            description: String(localized: "Keeps the preview pinned where the dock icon was when first hovered, preventing it from jumping when the dock auto-hides."),
            keywords: ["anchor", "pin", "position", "auto-hide"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "pin.circle"
        ),
        SettingsSearchItem(
            id: "advanced.preventDockHide",
            title: String(localized: "Prevent dock from hiding during previews"),
            keywords: ["dock", "hide", "auto-hide", "prevent"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "dock.rectangle"
        ),
        SettingsSearchItem(
            id: "advanced.raisedLevel",
            title: String(localized: "Show preview above app labels"),
            keywords: ["above", "level", "layer", "z-index", "raised"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "square.3.layers.3d.top.filled"
        ),
        SettingsSearchItem(
            id: "advanced.smallWindows",
            title: String(localized: "Show small windows (under 100px)"),
            description: String(localized: "Includes small windows like Finder's copy progress dialog in previews."),
            keywords: ["small", "tiny", "100px", "filter"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "rectangle.arrowtriangle.2.inward"
        ),
        SettingsSearchItem(
            id: "advanced.preventReentry",
            title: String(localized: "Prevent preview reappearance during fade-out"),
            description: String(localized: "Moving the mouse back over the preview during fade-out will not reactivate it."),
            keywords: ["reentry", "fade", "reappear", "prevent"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "arrow.uturn.backward"
        ),
        SettingsSearchItem(
            id: "advanced.openNewWindow",
            title: String(localized: "Clicking windowless apps"),
            description: String(localized: "Choose whether activating an app with no windows opens a new window, simulates a Dock click, or only activates the app."),
            keywords: ["windowless", "new window", "open", "cmd+n", "simulate", "click", "dock", "activate", "only"],
            tab: "Advanced",
            section: String(localized: "Performance Tuning"),
            icon: "plus.rectangle.on.rectangle"
        ),
        SettingsSearchItem(
            id: "advanced.captureQuality",
            title: String(localized: "Window Image Capture Quality"),
            keywords: ["quality", "capture", "resolution", "image"],
            tab: "Advanced",
            section: String(localized: "Preview Quality"),
            icon: "photo"
        ),
        SettingsSearchItem(
            id: "advanced.cacheLifespan",
            title: String(localized: "Window Image Cache Lifespan"),
            keywords: ["cache", "lifespan", "refresh", "stale"],
            tab: "Advanced",
            section: String(localized: "Preview Quality"),
            icon: "clock.arrow.circlepath"
        ),
        SettingsSearchItem(
            id: "advanced.imageScale",
            title: String(localized: "Window Image Resolution Scale (1=Best)"),
            keywords: ["scale", "resolution", "retina", "quality"],
            tab: "Advanced",
            section: String(localized: "Preview Quality"),
            icon: "arrow.up.left.and.arrow.down.right"
        ),
        SettingsSearchItem(
            id: "advanced.livePreview",
            title: String(localized: "Enable Live Preview (Video)"),
            description: String(localized: "Window previews show live video instead of static screenshots. Uses ScreenCaptureKit for real-time capture."),
            keywords: ["live", "video", "stream", "real-time", "screen capture"],
            tab: "Advanced",
            section: String(localized: "Live Preview"),
            icon: "video"
        ),
        SettingsSearchItem(
            id: "advanced.livePreviewDock",
            title: String(localized: "Enable for Dock Preview"),
            keywords: ["live", "dock", "video"],
            tab: "Advanced",
            section: String(localized: "Dock Live Preview"),
            icon: "video"
        ),
        SettingsSearchItem(
            id: "advanced.livePreviewSwitcher",
            title: String(localized: "Enable for Window Switcher"),
            keywords: ["live", "switcher", "video"],
            tab: "Advanced",
            section: String(localized: "Switcher Live Preview"),
            icon: "video"
        ),
        SettingsSearchItem(
            id: "advanced.streamKeepAlive",
            title: String(localized: "Stream Keep-Alive Duration"),
            description: String(localized: "How long to keep video streams active after closing preview. Longer duration means faster reopening but uses more resources."),
            keywords: ["keep alive", "stream", "duration", "resource"],
            tab: "Advanced",
            section: String(localized: "Stream Management"),
            icon: "waveform.path"
        ),
    ]

    // MARK: - Support

    private static let supportItems: [SettingsSearchItem] = [
        SettingsSearchItem(
            id: "support.accessibility",
            title: String(localized: "Accessibility"),
            description: String(localized: "Required for dock hover detection and window switcher hotkeys"),
            keywords: ["permission", "accessibility", "grant", "axui"],
            tab: "Support",
            section: String(localized: "Permissions"),
            icon: "accessibility"
        ),
        SettingsSearchItem(
            id: "support.screenRecording",
            title: String(localized: "Screen Recording"),
            description: String(localized: "Required for capturing window previews. Without this, only compact list view is available."),
            keywords: ["permission", "screen", "recording", "capture", "grant"],
            tab: "Support",
            section: String(localized: "Permissions"),
            icon: "record.circle"
        ),
        SettingsSearchItem(
            id: "support.updateChannel",
            title: String(localized: "Update Channel"),
            description: String(localized: "Choose between stable releases and beta versions"),
            keywords: ["update", "channel", "beta", "stable", "release"],
            tab: "Support",
            section: String(localized: "Updates"),
            icon: "arrow.triangle.branch"
        ),
        SettingsSearchItem(
            id: "support.checkForUpdates",
            title: String(localized: "Check for Updates"),
            keywords: ["update", "check", "new version"],
            tab: "Support",
            section: String(localized: "Updates"),
            icon: "arrow.triangle.2.circlepath"
        ),
        SettingsSearchItem(
            id: "support.automaticUpdates",
            title: String(localized: "Automatic Updates"),
            description: String(localized: "Automatically check for updates in the background"),
            keywords: ["update", "automatic", "background", "check"],
            tab: "Support",
            section: String(localized: "Updates"),
            icon: "clock.arrow.2.circlepath"
        ),
        SettingsSearchItem(
            id: "support.debugLogging",
            title: String(localized: "Debug Logging"),
            description: String(localized: "Capture performance metrics and app hang diagnostics for troubleshooting"),
            keywords: ["debug", "log", "logging", "performance", "troubleshoot"],
            tab: "Support",
            section: String(localized: "Updates"),
            icon: "ant.fill"
        ),
        SettingsSearchItem(
            id: "support.limitDebugLogFileSize",
            title: String(localized: "Limit debug log file size"),
            keywords: ["debug", "log", "size", "limit", "cap"],
            tab: "Support",
            section: String(localized: "Updates"),
            icon: "externaldrive"
        ),
        SettingsSearchItem(
            id: "support.debugLogMaximumSizeMB",
            title: String(localized: "Maximum debug log size"),
            keywords: ["debug", "log", "size", "megabyte", "storage"],
            tab: "Support",
            section: String(localized: "Updates"),
            icon: "externaldrive"
        ),
    ]
}

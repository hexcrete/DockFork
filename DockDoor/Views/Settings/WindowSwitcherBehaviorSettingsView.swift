import AppKit
import Defaults
import SwiftUI

struct WindowSwitcherBehaviorSettingsView: View {
    @Default(.enableWindowSwitcher) var enableWindowSwitcher
    @Default(.instantWindowSwitcher) var instantWindowSwitcher
    @Default(.enableWindowSwitcherSearch) var enableWindowSwitcherSearch
    @Default(.focusSearchOnWindowSwitcherOpen) var focusSearchOnWindowSwitcherOpen
    @Default(.searchFuzziness) var searchFuzziness
    @Default(.preventSwitcherHide) var preventSwitcherHide
    @Default(.enableMouseHoverInSwitcher) var enableMouseHoverInSwitcher
    @Default(.mouseHoverAutoScrollSpeed) var mouseHoverAutoScrollSpeed
    @Default(.includeHiddenWindowsInSwitcher) var includeHiddenWindowsInSwitcher
    @Default(.useClassicWindowOrdering) var useClassicWindowOrdering
    @Default(.startPersistentSwitcherUnhighlighted) private var startPersistentSwitcherUnhighlighted
    @Default(.limitSwitcherToFrontmostApp) var limitSwitcherToFrontmostApp
    @Default(.showWindowsFromCurrentSpaceOnlyInSwitcher) var showWindowsFromCurrentSpaceOnlyInSwitcher
    @Default(.showWindowsFromCurrentMonitorOnlyInSwitcher) var showWindowsFromCurrentMonitorOnlyInSwitcher
    @Default(.windowSwitcherSortOrder) var windowSwitcherSortOrder
    @Default(.groupedAppsInSwitcher) var groupedAppsInSwitcher
    @Default(.windowSwitcherPlacementStrategy) var placementStrategy
    @Default(.pinnedScreenIdentifier) var pinnedScreenIdentifier
    @Default(.windowSwitcherHorizontalOffsetPercent) var windowSwitcherHorizontalOffsetPercent
    @Default(.windowSwitcherVerticalOffsetPercent) var windowSwitcherVerticalOffsetPercent
    @Default(.enableShiftWindowSwitcherPlacement) var enableShiftWindowSwitcherPlacement
    @Default(.showWindowlessAppsInSwitcher) var showWindowlessAppsInSwitcher
    @Default(.mouseFollowsFocusMode) var mouseFollowsFocusMode

    @Default(.enableWindowSwitcherEdgeAutoScroll) var enableWindowSwitcherEdgeAutoScroll
    @Default(.switcherPreviewHoverAction) var switcherPreviewHoverAction
    @Default(.switcherTapEquivalentInterval) var switcherTapEquivalentInterval
    @Default(.windowSwitcherHorizontalAnchor) var windowSwitcherHorizontalAnchor
    @Default(.windowSwitcherVerticalAnchor) var windowSwitcherVerticalAnchor
    @Default(.excludeWindowlessAppsFromCurrentMonitorSwitcherScopes) var excludeWindowlessAppsFromCurrentMonitorSwitcherScopes
    @Default(.excludeWindowlessAppsFromCurrentSpaceSwitcherScopes) var excludeWindowlessAppsFromCurrentSpaceSwitcherScopes
    @Default(.enableActionFeedback) private var enableActionFeedback
    @Default(.showMouseFollowsFocusFeedback) private var mouseFollowsFocusFeedback
    @Default(.enableSpacesBar) private var enableSpacesBar
    @Default(.spacesBarFilterWindows) private var spacesBarFilterWindows
    @Default(.spacesBarStartOnNext) private var spacesBarStartOnNext
    @Default(.spacesBarRecentlyUsed) private var spacesBarRecentlyUsed
    @Default(.spacesBarSwapContents) private var spacesBarSwapContents
    @Default(.spacesBarShowAppIcons) private var spacesBarShowAppIcons
    @Default(.spacesBarActivateAppIcons) private var spacesBarActivateAppIcons
    @Default(.spacesBarHideWhenSingle) private var spacesBarHideWhenSingle

    @State private var showGroupedAppsSheet: Bool = false

    var body: some View {
        SettingsFormView {
            headerSection

            if enableWindowSwitcher {
                appearanceSection
                behaviorSection
                windowDisplaySection
                searchAndInputSection
                sortingAndGroupingSection
                placementSection
                hoverActionsSection
                spacesBarSection
            }

            if enableWindowSwitcher {
                TrackpadSwitcherSwipeSection()
            }
        } pinnedHeader: {
            if enableWindowSwitcher {
                SettingsMockPreview(context: .windowSwitcher, maxHeight: 170)
            }
        }
        .onChange(of: spacesBarRecentlyUsed) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar(.contents) }
        .onChange(of: spacesBarFilterWindows) { _ in SharedPreviewWindowCoordinator.activeInstance?.resetSpaceFiltering() }
        .onChange(of: enableSpacesBar) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar() }
        .onChange(of: spacesBarHideWhenSingle) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar(.layout) }
        .sheet(isPresented: $showGroupedAppsSheet) {
            AppPickerSheet(
                selectedApps: $groupedAppsInSwitcher,
                title: "Group Windows by App",
                description: "Selected apps will show only their most recent window in the switcher.",
                selectionMode: AppPickerSheet.SelectionMode.include
            )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        SettingsSection("Window Switcher") {
            Toggle(isOn: $enableWindowSwitcher) { Text("Enable Window Switcher") }
                .settingsSearchTarget("windowSwitcher.enable")
                .settingsAnnotation("The Window Switcher (often Alt/Cmd-Tab) lets you quickly cycle between open app windows with a keyboard shortcut.")
                .onChange(of: enableWindowSwitcher) { _ in askUserToRestartApplication() }
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        SettingsSection("Behavior") {
            Toggle(isOn: $instantWindowSwitcher) { Text("Show Window Switcher instantly") }
                .settingsSearchTarget("windowSwitcher.instant")
                .settingsAnnotation("May feel snappier but can cause flickering if you quickly release the key.")

            Toggle(isOn: Binding(
                get: { !preventSwitcherHide },
                set: { preventSwitcherHide = !$0 }
            )) { Text("Release initializer key to select window") }
                .settingsSearchTarget("windowSwitcher.releaseToSelect")

            Toggle(isOn: $useClassicWindowOrdering) { Text("Start on second window") }
                .settingsSearchTarget("windowSwitcher.startOnSecond")
                .settingsAnnotation("Highlight the second window instead of the first when opening.")

            Toggle("Start persistent switchers with no window highlighted", isOn: $startPersistentSwitcherUnhighlighted)
                .settingsSearchTarget("windowSwitcher.startPersistentSwitcherUnhighlighted")
                .settingsAnnotation("Leave windows unhighlighted when opening from the menu bar, AppleScript, a persistent shortcut, or when selection on release is off.")

            Picker(String(localized: "Mouse follows focus", comment: "Mouse follows focus setting label"), selection: $mouseFollowsFocusMode) {
                ForEach(MouseFollowsFocusMode.allCases, id: \.self) {
                    Text($0.localizedName).tag($0)
                }
            }
            .settingsSearchTarget("windowSwitcher.mouseFollowsFocus")
            .settingsAnnotation("Move the cursor to the center of the selected window.")
            if mouseFollowsFocusMode != .never, enableActionFeedback {
                SettingsDependentRows {
                    Toggle("Show feedback popup", isOn: $mouseFollowsFocusFeedback)
                        .settingsSearchTarget("windowSwitcher.showMouseFollowsFocusFeedback")
                        .settingsAnnotation("Show a popup at the cursor's new location. Requires action feedback to be enabled.")
                }
            }
        }
    }

    // MARK: - Window Display

    private var windowDisplaySection: some View {
        SettingsSection("Window Display") {
            SharedWindowDisplayRows(
                currentSpaceOnly: $showWindowsFromCurrentSpaceOnlyInSwitcher,
                currentSpaceOnlyTarget: "windowSwitcher.currentSpaceOnly",
                monitorCaption: "Only display windows that are on the same display as the mouse cursor.",
                currentMonitorOnly: $showWindowsFromCurrentMonitorOnlyInSwitcher,
                currentMonitorOnlyTarget: "windowSwitcher.currentMonitorOnly",
                includeHidden: $includeHiddenWindowsInSwitcher,
                includeHiddenTarget: "windowSwitcher.includeHidden",
                showWindowless: $showWindowlessAppsInSwitcher,
                showWindowlessTarget: "windowSwitcher.showWindowless",
                windowlessTitle: "Show running apps with no open windows",
                windowlessCaption: "Dock-visible apps without any windows will appear as icon-only entries at the end."
            )

            Toggle(isOn: $limitSwitcherToFrontmostApp) { Text("Limit to active app only") }
                .settingsSearchTarget("windowSwitcher.limitToFrontmost")
                .settingsAnnotation("Only show windows from the currently active/frontmost application.")
            if showWindowlessAppsInSwitcher {
                SettingsDependentRows {
                    Toggle("Exclude from \"Current Monitor Only\" filter", isOn: $excludeWindowlessAppsFromCurrentMonitorSwitcherScopes)
                        .settingsSearchTarget("windowSwitcher.excludeWindowlessFromCurrentMonitor")
                    Toggle("Exclude from \"Current Space Only\" filter", isOn: $excludeWindowlessAppsFromCurrentSpaceSwitcherScopes)
                        .settingsSearchTarget("windowSwitcher.excludeWindowlessFromCurrentSpace")
                }
            }
        }
    }

    // MARK: - Search & Input

    private var searchAndInputSection: some View {
        SettingsSection("Search & Input") {
            Toggle(isOn: $enableWindowSwitcherSearch) { Text("Enable search") }
                .settingsSearchTarget("windowSwitcher.enableSearch")
            if enableWindowSwitcherSearch {
                SettingsDependentRows {
                    Toggle(isOn: $focusSearchOnWindowSwitcherOpen) { Text("Focus search on open") }
                        .settingsSearchTarget("windowSwitcher.focusSearch")
                        .settingsAnnotation("Automatically focus the search bar when the window switcher opens.")

                    SettingsSliderRow(
                        title: "Search Fuzziness",
                        value: Binding(get: { Double(searchFuzziness) }, set: { searchFuzziness = Int($0) }),
                        range: 1 ... 5
                    )
                    .settingsAnnotation("Level 1 is exact match, level 5 is most lenient fuzzy matching.")
                }
            }

            Toggle(isOn: $enableMouseHoverInSwitcher) { Text("Enable mouse hover selection") }
                .settingsSearchTarget("windowSwitcher.mouseHover")
                .settingsAnnotation("Select windows when hovering with the mouse.")

            Toggle("Enable edge auto-scroll", isOn: $enableWindowSwitcherEdgeAutoScroll)
                .settingsSearchTarget("windowSwitcher.edgeAutoScroll")
            if enableWindowSwitcherEdgeAutoScroll {
                SettingsDependentRows {
                    SettingsSliderRow(
                        title: "Auto-scroll speed:",
                        value: $mouseHoverAutoScrollSpeed,
                        range: 1 ... 10,
                        step: 0.5
                    )
                    .settingsSearchTarget("windowSwitcher.edgeAutoScrollSpeed")
                }
            }
        }
    }

    // MARK: - Sorting & Grouping

    private var sortingAndGroupingSection: some View {
        SettingsSection("Sorting & Grouping") {
            Picker("Window sort order", selection: $windowSwitcherSortOrder) {
                ForEach(WindowPreviewSortOrder.allCases) { order in
                    Text(order.localizedName).tag(order)
                }
            }
            .settingsSearchTarget("windowSwitcher.sortOrder")
            .onChange(of: windowSwitcherSortOrder) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar(.contents) }

            HStack {
                Text("Group windows by app")
                Spacer()
                if !groupedAppsInSwitcher.isEmpty {
                    Text("\(groupedAppsInSwitcher.count) app\(groupedAppsInSwitcher.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Select...") {
                    showGroupedAppsSheet = true
                }
                .buttonStyle(.settings)
            }
            .settingsAnnotation("Selected apps show only their most recent window. All windows shown in active-app-only mode.")
            .settingsSearchTarget("windowSwitcher.groupByApp")
        }
    }

    // MARK: - Placement

    private var placementSection: some View {
        SettingsSection("Placement") {
            Picker("Screen", selection: $placementStrategy) {
                ForEach(WindowSwitcherPlacementStrategy.allCases, id: \.self) {
                    Text($0.localizedName).tag($0)
                }
            }
            .settingsSearchTarget("windowSwitcher.placement")
            .onChange(of: placementStrategy) { newStrategy in
                if newStrategy == .pinnedToScreen, pinnedScreenIdentifier.isEmpty {
                    pinnedScreenIdentifier = NSScreen.main?.uniqueIdentifier() ?? ""
                }
            }

            if placementStrategy == .pinnedToScreen {
                Picker("Pin to", selection: $pinnedScreenIdentifier) {
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.displayName).tag(screen.uniqueIdentifier())
                    }
                    if !pinnedScreenIdentifier.isEmpty,
                       NSScreen.findScreen(byIdentifier: pinnedScreenIdentifier) == nil
                    {
                        Text("Disconnected Display").tag(pinnedScreenIdentifier)
                    }
                }
                .onAppear { NSScreen.migrateScreenIdentifier(.pinnedScreenIdentifier) }

                if !pinnedScreenIdentifier.isEmpty,
                   NSScreen.findScreen(byIdentifier: pinnedScreenIdentifier) == nil
                {
                    SettingsCallout(message: Text("This display is currently disconnected."))
                }
            }

            Picker("Vertical anchor", selection: $windowSwitcherVerticalAnchor) {
                ForEach(WindowSwitcherVerticalAnchor.allCases, id: \.self) { Text($0.localizedName).tag($0) }
            }

            .settingsSearchTarget("windowSwitcher.anchorVertical")
            Picker("Horizontal anchor", selection: $windowSwitcherHorizontalAnchor) {
                ForEach(WindowSwitcherHorizontalAnchor.allCases, id: \.self) { Text($0.localizedName).tag($0) }
            }

            .settingsSearchTarget("windowSwitcher.anchorHorizontal")
            Toggle(isOn: $enableShiftWindowSwitcherPlacement) {
                Text("Offset position")
            }
            .settingsSearchTarget("windowSwitcher.offsetPosition")

            if enableShiftWindowSwitcherPlacement {
                SettingsDependentRows {
                    SettingsSliderRow(
                        title: "Vertical offset",
                        value: $windowSwitcherVerticalOffsetPercent,
                        range: -80 ... 80,
                        defaultValue: 0,
                        unit: "%"
                    )

                    SettingsSliderRow(
                        title: "Horizontal offset",
                        value: $windowSwitcherHorizontalOffsetPercent,
                        range: -80 ... 80,
                        defaultValue: 0,
                        unit: "%"
                    )
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        WindowSwitcherAppearanceSection()
    }

    private var spacesBarSection: some View {
        SettingsSection("Spaces Bar") {
            Toggle("Enable Spaces Bar", isOn: $enableSpacesBar)
                .settingsSearchTarget("windowSwitcher.enableSpacesBar")
            if enableSpacesBar {
                SettingsDependentRows {
                    Toggle("Automatically filter windows by highlighted Space", isOn: $spacesBarFilterWindows)
                        .settingsSearchTarget("windowSwitcher.spacesBarFilterWindows")
                    Toggle("Start on next Space", isOn: $spacesBarStartOnNext)
                        .settingsSearchTarget("windowSwitcher.spacesBarStartOnNext")
                    Picker("Spaces sort order", selection: $spacesBarRecentlyUsed) {
                        Text("Sequential").tag(false)
                        Text("Recently used").tag(true)
                    }

                    .settingsSearchTarget("windowSwitcher.spacesBarRecentlyUsed")
                    Toggle("Activate apps by clicking their icons", isOn: $spacesBarActivateAppIcons)
                        .settingsSearchTarget("windowSwitcher.spacesBarActivateAppIcons")
                    if !spacesBarShowAppIcons {
                        Text("Enable \"Appearance > Spaces Bar > Show app icons in the Spaces Bar\" to use this.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Dragging a Space onto another Space", selection: $spacesBarSwapContents) {
                        Text("Moves all eligible windows to the target Space").tag(false)
                        Text("Swaps windows between the two Spaces").tag(true)
                    }

                    .settingsSearchTarget("windowSwitcher.spacesBarSwapContents")
                    .settingsAnnotation("Dragging moves Desktop contents, not Spaces, wallpapers or app assignments. Gaps shift contents in Sequential order only.")
                    Toggle("Hide when only one Space exists", isOn: $spacesBarHideWhenSingle)
                        .settingsSearchTarget("windowSwitcher.spacesBarHideWhenSingle")
                }
            }
        }
    }

    private var hoverActionsSection: some View {
        SettingsSection("Hover Actions") {
            Picker("Window Switcher Hover Action", selection: $switcherPreviewHoverAction) {
                ForEach(PreviewHoverAction.allCases, id: \.self) { Text($0.localizedName).tag($0) }
            }

            .settingsSearchTarget("windowSwitcher.hoverAction")
            if switcherPreviewHoverAction != .none {
                SettingsDependentRows {
                    SettingsSliderRow(title: "Window Switcher Hover Action Delay", value: $switcherTapEquivalentInterval, range: 0 ... 2, defaultValue: Defaults.Keys.switcherTapEquivalentInterval.defaultValue, unit: " s", step: 0.1)
                        .settingsSearchTarget("windowSwitcher.hoverDelay")
                }
            }
            PreviewFocusFadeSettings(mode: .windowSwitcher)
        }
    }
}

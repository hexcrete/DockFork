import Defaults
import SwiftUI

struct DockPreviewsSettingsView: View {
    @Default(.enableDockPreviews) var enableDockPreviews
    @Default(.showWindowsFromCurrentSpaceOnly) var showWindowsFromCurrentSpaceOnly
    @Default(.showWindowsFromCurrentMonitorOnly) var showWindowsFromCurrentMonitorOnly
    @Default(.windowPreviewSortOrder) var windowPreviewSortOrder
    @Default(.keepPreviewOnAppTerminate) var keepPreviewOnAppTerminate
    @Default(.groupAppInstancesInDock) var groupAppInstancesInDock
    @Default(.collapseNativeTabsIntoSingleWindow) var collapseNativeTabsIntoSingleWindow
    @Default(.includeHiddenWindowsInDockPreview) var includeHiddenWindowsInDockPreview
    @Default(.showFullSizeWindowlessDockPreviews) var showFullSizeWindowlessDockPreviews
    @Default(.showWindowlessAppsInDockPreview) var showWindowlessAppsInDockPreview
    @Default(.dockPreviewActivationMode) var dockPreviewActivationMode
    @Default(.dockPreviewActivationModifier) var dockPreviewActivationModifier
    @Default(.previewHoverAction) var previewHoverAction
    @Default(.keepPreviewOnHoverActivation) var keepPreviewOnHoverActivation
    @Default(.tapEquivalentInterval) var tapEquivalentInterval
    @Default(.enableDockPreviewEdgeAutoScroll) var enableDockPreviewEdgeAutoScroll
    @Default(.dockPreviewEdgeAutoScrollSpeed) var dockPreviewEdgeAutoScrollSpeed
    @Default(.shouldHideOnDockItemClick) var shouldHideOnDockItemClick
    @Default(.dockClickAction) var dockClickAction
    @Default(.keepDockPreviewsOpenWhenCycling) var keepDockPreviewsOpenWhenCycling
    @Default(.enableCmdRightClickQuit) var enableCmdRightClickQuit
    @Default(.quitAppOnWindowClose) var quitAppOnWindowClose
    @Default(.quitAppOnWindowCloseExcludedApps) var quitAppOnWindowCloseExcludedApps
    @Default(.bufferFromDock) var bufferFromDock
    @Default(.ignoreAppsWithSingleWindow) var ignoreAppsWithSingleWindow
    @Default(.enableFolderWidget) var enableFolderWidget
    @Default(.folderWidgetDefaultSortOrder) var folderWidgetDefaultSortOrder
    @Default(.folderWidgetDefaultSortReversed) var folderWidgetDefaultSortReversed
    @Default(.folderWidgetRememberSortPerFolder) var folderWidgetRememberSortPerFolder
    @Default(.folderWidgetShowHiddenFiles) var folderWidgetShowHiddenFiles

    @State private var showQuitExclusionsSheet = false

    var body: some View {
        SettingsFormView {
            headerSection

            if enableDockPreviews {
                windowDisplaySection
                dockInteractionSection
                folderWidgetSection
                dockAppearanceSection
            }
        } pinnedHeader: {
            if enableDockPreviews { SettingsMockPreview(context: .dock) }
        }
        .sheet(isPresented: $showQuitExclusionsSheet) {
            AppPickerSheet(
                selectedApps: $quitAppOnWindowCloseExcludedApps,
                title: "Never Quit These Apps",
                description: "Selected apps keep running after their last window closes.",
                selectionMode: .include
            )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            SettingsIllustratedToggle(
                isOn: $enableDockPreviews,
                title: "Enable Dock Previews",
                imageName: "DockPreviews"
            ) {
                Text("Show window previews for Dock icons.")
            }
            .settingsSearchTarget("dockPreviews.enable")
            .onChange(of: enableDockPreviews) { _ in askUserToRestartApplication() }
        }
    }

    // MARK: - Window Display

    private var windowDisplaySection: some View {
        SettingsSection("Window Display") {
            Toggle(isOn: $showWindowsFromCurrentSpaceOnly) { Text("Show windows from current Space only") }
                .settingsSearchTarget("dockPreviews.currentSpaceOnly")
            Text("Only display windows that are in the current virtual desktop/Space.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            Toggle(isOn: $showWindowsFromCurrentMonitorOnly) { Text("Show windows from current monitor only") }
                .settingsSearchTarget("dockPreviews.currentMonitorOnly")
            Text("Only display windows that are on the same display as the Dock icon you're hovering.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            Picker("Window sort order", selection: $windowPreviewSortOrder) {
                ForEach(WindowPreviewSortOrder.allCases.filter { !$0.isWindowSwitcherOnly }) { order in
                    Text(order.localizedName).tag(order)
                }
            }
            .pickerStyle(.menu)
            .settingsSearchTarget("dockPreviews.sortOrder")

            Toggle(isOn: $includeHiddenWindowsInDockPreview) { Text("Include hidden/minimized windows") }
                .settingsSearchTarget("dockPreviews.includeHidden")

            Toggle(isOn: $showWindowlessAppsInDockPreview) { Text("Show preview for apps with no open windows") }
                .settingsSearchTarget("dockPreviews.showWindowless")
            Text("Show a placeholder preview when hovering dock apps that have no windows.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            if showWindowlessAppsInDockPreview {
                Toggle("Show full size placeholders", isOn: $showFullSizeWindowlessDockPreviews)
                    .settingsSearchTarget("dockPreviews.fullSizeWindowless")
                    .padding(.leading, 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $ignoreAppsWithSingleWindow) { Text("Ignore apps with one window") }
                    .settingsSearchTarget("dockPreviews.ignoreSingleWindow")
                Text("Prevents apps with exactly one open window from appearing in previews.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }
            .padding(.leading, 20)
            .disabled(showWindowlessAppsInDockPreview)
            .opacity(showWindowlessAppsInDockPreview ? 0.5 : 1)

            Toggle(isOn: $keepPreviewOnAppTerminate) { Text("Keep preview when app terminates") }
                .settingsSearchTarget("dockPreviews.keepOnTerminate")
            Text("Remove only terminated app's windows instead of hiding the entire preview.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            Toggle(isOn: $groupAppInstancesInDock) { Text("Group multiple app instances together") }
                .settingsSearchTarget("dockPreviews.groupInstances")
            Text("Show windows from all instances of an app when hovering its dock icon.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            Toggle(isOn: $collapseNativeTabsIntoSingleWindow) { Text("Collapse native tabs into a single window") }
                .settingsSearchTarget("dockPreviews.collapseNativeTabs")
                .onChange(of: collapseNativeTabsIntoSingleWindow) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar(.contents) }
            Text("Show one preview for apps that use native macOS window tabs (e.g. Ghostty, Finder, Terminal) instead of one preview per tab. Restart the app for this to take effect.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)
        }
    }

    // MARK: - Folder Previews

    private var folderWidgetSection: some View {
        SettingsSection("Folder Previews") {
            Toggle(isOn: $enableFolderWidget) { Text("Show folder contents on hover") }
                .settingsSearchTarget("widgets.folder")
            Text("Preview a folder's contents when hovering it in the Dock.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            if enableFolderWidget {
                Picker("Default sort:", selection: $folderWidgetDefaultSortOrder) {
                    ForEach(FolderWidgetSortOrder.allCases, id: \.self) { order in
                        Text(order.localizedName).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .settingsSearchTarget("widgets.folderSort")
                .padding(.leading, 20)

                Toggle(isOn: $folderWidgetDefaultSortReversed) { Text("Sort descending by default") }
                    .settingsSearchTarget("widgets.folderSortDirection")
                    .padding(.leading, 20)

                Toggle(isOn: $folderWidgetRememberSortPerFolder) { Text("Remember sorting per folder") }
                    .settingsSearchTarget("widgets.folderRememberSort")
                    .padding(.leading, 20)

                Toggle(isOn: $folderWidgetShowHiddenFiles) { Text("Show hidden files") }
                    .settingsSearchTarget("widgets.folderHiddenFiles")
                    .padding(.leading, 20)
            }
        }
    }

    // MARK: - Appearance

    private var dockAppearanceSection: some View {
        SettingsSection("Appearance") {
            DockPreviewAppearanceSection()
        }
    }

    // MARK: - Dock Interaction

    private var dockInteractionSection: some View {
        SettingsSection("Dock Interaction") {
            Picker("Dock Preview Trigger", selection: $dockPreviewActivationMode) {
                ForEach(DockPreviewActivationMode.allCases, id: \.self) {
                    Text($0.localizedName).tag($0)
                }
            }
            .pickerStyle(.menu)
            .settingsSearchTarget("dockPreviews.activationTrigger")

            Text("Show previews automatically on hover, or require a click trigger on the Dock icon.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            Picker("Dock Preview Modifier", selection: $dockPreviewActivationModifier) {
                ForEach(DockPreviewActivationModifier.allCases, id: \.self) {
                    Text($0.localizedName).tag($0)
                }
            }
            .pickerStyle(.menu)
            .settingsSearchTarget("dockPreviews.activationModifier")
            .padding(.leading, 20)
            .disabled(dockPreviewActivationMode != .modifierClick)

            Picker("Dock Preview Hover Action", selection: $previewHoverAction) {
                ForEach(PreviewHoverAction.allCases, id: \.self) { Text($0.localizedName).tag($0) }
            }
            .pickerStyle(.menu)
            .settingsSearchTarget("dockPreviews.hoverAction")

            Toggle(isOn: $keepPreviewOnHoverActivation) {
                Text("Keep preview open after hover activation")
            }
            .disabled(previewHoverAction != .tap)
            .settingsSearchTarget("dockPreviews.keepOnHoverActivation")

            Text("Keep Dock previews visible while the pointer remains over them after a hover brings a window to the front.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            sliderSetting(title: "Preview Hover Action Delay", value: $tapEquivalentInterval, range: 0 ... 2, step: 0.1, unit: "seconds", formatter: NumberFormatter.oneDecimalFormatter)
                .disabled(previewHoverAction == .none)
                .settingsSearchTarget("dockPreviews.hoverDelay")

            PreviewFocusFadeSettings(mode: .dock)

            Toggle(isOn: $enableDockPreviewEdgeAutoScroll) {
                Text("Enable edge auto-scroll")
            }
            .settingsSearchTarget("dockPreviews.edgeAutoScroll")

            if enableDockPreviewEdgeAutoScroll {
                HStack {
                    Text("Auto-scroll speed:")
                    Slider(value: $dockPreviewEdgeAutoScrollSpeed, in: 1 ... 10, step: 0.5)
                    Text(String(format: "%.1f", dockPreviewEdgeAutoScrollSpeed))
                        .frame(width: 30)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 20)
                .settingsSearchTarget("dockPreviews.edgeAutoScrollSpeed")
            }

            Toggle(isOn: $shouldHideOnDockItemClick) { Text("Override Dock icon click") }
                .settingsSearchTarget("dockPreviews.hideOnClick")
            if shouldHideOnDockItemClick {
                Picker("Dock Click Action", selection: $dockClickAction) {
                    ForEach(DockClickAction.allCases, id: \.self) {
                        Text($0.localizedName).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .padding(.leading, 20)
                .settingsSearchTarget("dockPreviews.clickAction")
                if dockClickAction == .cycleWindows {
                    Toggle(isOn: $keepDockPreviewsOpenWhenCycling) {
                        Text("Keep previews open when cycling through windows")
                    }
                    .padding(.leading, 20)
                    .settingsSearchTarget("dockPreviews.keepOpenWhenCycling")
                }
            }

            Toggle(isOn: $enableCmdRightClickQuit) { Text("CMD + Right Click on dock icon to quit app") }
                .settingsSearchTarget("dockPreviews.cmdRightClickQuit")

            Toggle(isOn: $quitAppOnWindowClose) { Text("Quit app when closing its last window") }
                .settingsSearchTarget("dockPreviews.quitOnClose")
            Text("When an app has only one window left, closing it will quit the app. Useful as a replacement for Swift Quit.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)
            if quitAppOnWindowClose {
                HStack {
                    Text("Never quit these apps")
                    Spacer()
                    if !quitAppOnWindowCloseExcludedApps.isEmpty {
                        Text("\(quitAppOnWindowCloseExcludedApps.count) app\(quitAppOnWindowCloseExcludedApps.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button("Select...") {
                        showQuitExclusionsSheet = true
                    }
                    .buttonStyle(.settings)
                }
                .padding(.leading, 20)
                .settingsSearchTarget("dockPreviews.quitOnCloseExclusions")
            }

            sliderSetting(title: "Window Buffer from Dock (pixels)", value: $bufferFromDock, range: -100 ... 100, step: 5, unit: "px", formatter: { let f = NumberFormatter(); f.allowsFloats = false; f.minimumIntegerDigits = 1; f.maximumFractionDigits = 0; return f }())
                .settingsSearchTarget("dockPreviews.buffer")
        }
    }
}

struct DockPreviewAppearanceSection: View {
    @Default(.showAppName) var showAppName
    @Default(.appNameStyle) var appNameStyle
    @Default(.showAppIconOnly) var showAppIconOnly
    @Default(.dockPreviewControlPosition) var dockPreviewControlPosition
    @Default(.showWindowTitle) var showWindowTitle
    @Default(.windowTitleVisibility) var windowTitleVisibility
    @Default(.disableDockStyleTitles) var disableDockStyleTitles
    @Default(.disableDockStyleTrafficLights) var disableDockStyleTrafficLights
    @Default(.showMassActionButtons) var showMassActionButtons
    @Default(.useEmbeddedDockPreviewElements) var useEmbeddedDockPreviewElements
    @Default(.previewMaxColumns) var previewMaxColumns
    @Default(.previewMaxRows) var previewMaxRows
    @Default(.dockPreviewSpaceNumberIndicatorPlacement) var dockPreviewSpaceNumberIndicatorPlacement
    @Default(.highlightDockPreviewCurrentSpaceIndicator) var highlightDockPreviewCurrentSpaceIndicator
    @Default(.dockPreviewWindowStateIndicatorPlacement) var dockPreviewWindowStateIndicatorPlacement
    @Default(.disableDockStyleWindowStateIndicator) var disableDockStyleWindowStateIndicator
    @Default(.swapDockPreviewTrafficLightsAndWindowStateIndicator) var swapTrafficLightsAndWindowStateIndicator
    @Default(.limitDockPreviewIndicatorSwapToCompactMode) var limitIndicatorSwapToCompactMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // App Header section
            Toggle(isOn: $showAppName) {
                Text("Show App Header")
            }
            .settingsSearchTarget("appearance.dockShowAppHeader")

            if showAppName {
                Picker(String(localized: "App Header Style"), selection: $appNameStyle) {
                    ForEach(AppNameStyle.allCases, id: \.self) { style in
                        Text(style.localizedName)
                            .tag(style)
                    }
                }
                .settingsSearchTarget("appearance.dockAppHeaderStyle")

                Toggle(isOn: $showAppIconOnly) {
                    Text("Show App Icon Only")
                }
                .settingsSearchTarget("appearance.dockShowAppIconOnly")
            }

            Divider().padding(.vertical, 2)
            Text("Dock Preview Toolbar").font(.headline).padding(.bottom, -2)

            Picker("Position Dock Preview Controls", selection: $dockPreviewControlPosition) {
                ForEach(WindowSwitcherControlPosition.allCases, id: \.self) { position in
                    Text(position.localizedName)
                        .tag(position)
                }
            }
            .pickerStyle(.menu)
            .settingsSearchTarget("appearance.dockControlPosition")

            Toggle(isOn: $showWindowTitle) {
                Text("Show Window Title")
            }
            .settingsSearchTarget("appearance.dockShowWindowTitle")

            if showWindowTitle {
                Picker("Window Title Visibility", selection: $windowTitleVisibility) {
                    ForEach(WindowTitleVisibility.allCases, id: \.self) { visibility in
                        Text(visibility.localizedName)
                            .tag(visibility)
                    }
                }
                .settingsSearchTarget("appearance.dockWindowTitleVisibility")

                VStack(alignment: .leading) {
                    Toggle(isOn: $disableDockStyleTitles) {
                        Text("Disable dock styling on window titles")
                    }
                    .settingsSearchTarget("appearance.dockDisableTitleStyling")
                    Text("Removes the pill-shaped background styling from window titles in dock previews for a cleaner look.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }
            }

            Divider().padding(.vertical, 2)
            Text("Traffic Light Buttons in Previews").font(.headline).padding(.bottom, -2)
            TrafficLightButtonsSettingsView()

            VStack(alignment: .leading) {
                Toggle(isOn: $disableDockStyleTrafficLights) {
                    Text("Disable dock styling on traffic light buttons")
                }
                .settingsSearchTarget("appearance.dockDisableTrafficLightStyling")
                Text("Removes the pill-shaped background styling from traffic light buttons in dock previews for a cleaner look.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.leading, 20)
            }

            Divider().padding(.vertical, 2)
            Text("Window State Indicator").font(.headline).padding(.bottom, -2)
            Picker("Show Space Number Indicator", selection: $dockPreviewSpaceNumberIndicatorPlacement) {
                ForEach(WindowStateIndicatorPlacement.allCases, id: \.self) { placement in
                    Text(placement.localizedName).tag(placement)
                }
            }
            .pickerStyle(.menu)
            .settingsSearchTarget("appearance.dockSpaceNumberIndicator")

            if dockPreviewSpaceNumberIndicatorPlacement != .off {
                VStack(alignment: .leading) {
                    Toggle("Highlight Current Space", isOn: $highlightDockPreviewCurrentSpaceIndicator)
                        .settingsSearchTarget("appearance.dockHighlightCurrentSpace")
                    Text("Highlights the Space number indicator for windows on the current Space.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }
                .padding(.leading, 20)
            }

            Picker("Show Window State Indicator", selection: $dockPreviewWindowStateIndicatorPlacement) {
                ForEach(WindowStateIndicatorPlacement.allCases, id: \.self) { placement in
                    Text(placement.localizedName).tag(placement)
                }
            }
            .pickerStyle(.menu)
            .settingsSearchTarget("appearance.dockWindowStateIndicator")
            Text("Controls whether Minimized, Hidden, and Full Screen indicators are hidden, shown on window previews, or placed next to traffic light buttons.")
                .font(.footnote)
                .foregroundColor(.gray)

            if dockPreviewSpaceNumberIndicatorPlacement == .nextToTrafficLightButtons || dockPreviewWindowStateIndicatorPlacement == .nextToTrafficLightButtons {
                VStack(alignment: .leading) {
                    Toggle("Disable dock styling on Window State Indicator", isOn: $disableDockStyleWindowStateIndicator)
                        .settingsSearchTarget("appearance.dockDisableWindowStateIndicatorStyling")
                    Text("Removes the pill-shaped background styling from the Window State Indicator in dock previews.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)

                    Toggle("Swap Window State Indicator and Traffic Light Buttons", isOn: $swapTrafficLightsAndWindowStateIndicator)
                        .settingsSearchTarget("appearance.dockSwapWindowStateIndicator")

                    if swapTrafficLightsAndWindowStateIndicator {
                        Toggle("Limit to Compact Mode only", isOn: $limitIndicatorSwapToCompactMode)
                            .padding(.leading, 20)
                            .settingsSearchTarget("appearance.dockLimitIndicatorSwapToCompactMode")
                    }
                }
            }

            Divider().padding(.vertical, 2)
            Text("Mass Action Buttons").font(.headline).padding(.bottom, -2)

            VStack(alignment: .leading) {
                Toggle(isOn: $showMassActionButtons) {
                    Text("Show Close All and Minimize All buttons")
                }
                .settingsSearchTarget("appearance.dockMassActionButtons")
                Text("Displays Close All and Minimize All buttons when hovering the app header in dock previews.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.leading, 20)
            }

            Divider().padding(.vertical, 2)
            Text("Dock Preview Layout").font(.headline).padding(.bottom, -2)

            VStack(alignment: .leading) {
                Toggle(isOn: $useEmbeddedDockPreviewElements) {
                    Text("Embed controls in preview frames")
                }
                .settingsSearchTarget("appearance.dockEmbedControls")
                Text("Places traffic light buttons and window titles directly inside the dock preview frames for a more compact and minimal appearance.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.leading, 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                let previewMaxRowsBinding = Binding<Double>(
                    get: { Double(previewMaxRows) },
                    set: { previewMaxRows = Int($0) }
                )
                sliderSetting(
                    title: "Max Rows (Bottom Dock)",
                    value: previewMaxRowsBinding,
                    range: 1.0 ... 8.0,
                    step: 1.0,
                    unit: "",
                    formatter: {
                        let f = NumberFormatter()
                        f.minimumFractionDigits = 0
                        f.maximumFractionDigits = 0
                        return f
                    }()
                )
                .settingsSearchTarget("appearance.dockMaxRows")

                let previewMaxColumnsBinding = Binding<Double>(
                    get: { Double(previewMaxColumns) },
                    set: { previewMaxColumns = Int($0) }
                )
                sliderSetting(
                    title: "Max Columns (Left/Right Dock)",
                    value: previewMaxColumnsBinding,
                    range: 1.0 ... 8.0,
                    step: 1.0,
                    unit: "",
                    formatter: {
                        let f = NumberFormatter()
                        f.minimumFractionDigits = 0
                        f.maximumFractionDigits = 0
                        return f
                    }()
                )
                .settingsSearchTarget("appearance.dockMaxColumns")

                Text(String(localized: "Controls how many rows/columns of windows are shown in dock previews. Only the relevant setting applies based on dock position."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

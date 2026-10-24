import AppKit
import Defaults
import LaunchAtLogin
import SwiftUI
import UniformTypeIdentifiers

struct MainSettingsView: View {
    @Default(.showMenuBarIcon) var showMenuBarIcon
    @Default(.showAnimations) var showAnimations
    @Default(.sortMinimizedToEnd) var sortMinimizedToEnd

    var body: some View {
        BaseSettingsView {
            VStack(alignment: .leading, spacing: 24) {
                DockDoorProBanner()
                supportAndContributionsSection
                applicationBasicsSection
                activeAppIndicatorSection
                backupAndRestoreSection

                HStack {
                    Spacer()
                    Button("Reset All Settings to Defaults") { showResetConfirmation() }
                    Button("Quit DockDoor") { (NSApplication.shared.delegate as! AppDelegate).quitApp() }
                    Spacer()
                }
                .padding(.top, 5)
            }
        }
    }

    // MARK: - Support & Contributions

    private var supportAndContributionsSection: some View {
        SettingsGroup(header: "Support & Contributions", compact: true) {
            SupportLinksSection()
        }
    }

    // MARK: - Application Basics

    private var applicationBasicsSection: some View {
        SettingsGroup(header: "Application Basics") {
            VStack(alignment: .leading, spacing: 10) {
                LaunchAtLogin.Toggle(String(localized: "Launch DockDoor at login"))
                    .settingsSearchTarget("general.launchAtLogin")

                Toggle(isOn: $showMenuBarIcon, label: { Text("Show menu bar icon") })
                    .settingsSearchTarget("general.menuBarIcon")
                    .onChange(of: showMenuBarIcon) { isOn in
                        let appDelegate = NSApplication.shared.delegate as! AppDelegate
                        if isOn { appDelegate.setupMenuBar() } else { appDelegate.removeMenuBar() }
                    }

                Toggle(isOn: Binding(
                    get: { !showAnimations },
                    set: { showAnimations = !$0 }
                )) {
                    Text("Reduce motion")
                }
                .settingsSearchTarget("general.reduceMotion")

                VStack(alignment: .leading, spacing: 0) {
                    Toggle(isOn: $sortMinimizedToEnd, label: {
                        Text("Sort minimized/hidden windows to end")
                    })
                    Text("Minimized and hidden windows will appear after all visible windows in previews and switcher.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
                .settingsSearchTarget("general.sortMinimized")
            }
        }
    }

    // MARK: - Active App Indicator

    private var activeAppIndicatorSection: some View {
        SettingsGroup(header: "Active App Indicator") {
            ActiveAppIndicatorSettingsView()
        }
    }

    // MARK: - Backup & Restore

    private var backupAndRestoreSection: some View {
        SettingsGroup(header: "Backup & Restore") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button("Export Settings…") { SettingsBackupManager.exportSettings() }
                        .settingsSearchTarget("general.exportSettings")
                    Button("Import Settings…") { SettingsBackupManager.importSettings() }
                        .settingsSearchTarget("general.importSettings")
                }

                SettingsNote(icon: "arrow.up.arrow.down.circle", text: "Settings are saved as a JSON file you can keep in iCloud Drive or a dotfiles repository. Importing replaces your current settings and restarts DockDoor.")
            }
        }
    }

    // MARK: - Helper Functions

    private func showResetConfirmation() {
        MessageUtil.showAlert(title: String(localized: "Reset to Defaults"), message: String(localized: "Are you sure you want to reset all settings to their default values?"), actions: [.ok, .cancel]) { action in
            if action == .ok {
                Defaults.removeAll()
                WindowSnapRegistry.existing?.removeDisabledRecords()
                Defaults[.launched] = true

                Defaults[.hoverWindowOpenDelay] = Defaults.Keys.hoverWindowOpenDelay.defaultValue
                Defaults[.fadeOutDuration] = Defaults.Keys.fadeOutDuration.defaultValue
                Defaults[.tapEquivalentInterval] = Defaults.Keys.tapEquivalentInterval.defaultValue
                Defaults[.switcherTapEquivalentInterval] = Defaults.Keys.switcherTapEquivalentInterval.defaultValue
                Defaults[.cmdTabTapEquivalentInterval] = Defaults.Keys.cmdTabTapEquivalentInterval.defaultValue
                Defaults[.preventDockHide] = Defaults.Keys.preventDockHide.defaultValue
                Defaults[.screenCaptureCacheLifespan] = Defaults.Keys.screenCaptureCacheLifespan.defaultValue
                Defaults[.programmaticResizePreviewRefreshDelay] = Defaults.Keys.programmaticResizePreviewRefreshDelay.defaultValue
                Defaults[.nativeResizePreviewRefreshDelay] = Defaults.Keys.nativeResizePreviewRefreshDelay.defaultValue
                Defaults[.windowPreviewImageScale] = Defaults.Keys.windowPreviewImageScale.defaultValue
                Defaults[.bufferFromDock] = Defaults.Keys.bufferFromDock.defaultValue
                Defaults[.shouldHideOnDockItemClick] = Defaults.Keys.shouldHideOnDockItemClick.defaultValue
                Defaults[.dockClickAction] = Defaults.Keys.dockClickAction.defaultValue
                Defaults[.keepDockPreviewsOpenWhenCycling] = Defaults.Keys.keepDockPreviewsOpenWhenCycling.defaultValue
                Defaults[.enableCmdRightClickQuit] = Defaults.Keys.enableCmdRightClickQuit.defaultValue
                Defaults[.dockPreviewActivationMode] = Defaults.Keys.dockPreviewActivationMode.defaultValue
                Defaults[.dockPreviewActivationModifier] = Defaults.Keys.dockPreviewActivationModifier.defaultValue
                Defaults[.previewHoverAction] = Defaults.Keys.previewHoverAction.defaultValue
                Defaults[.switcherPreviewHoverAction] = Defaults.Keys.switcherPreviewHoverAction.defaultValue
                Defaults[.cmdTabPreviewHoverAction] = Defaults.Keys.cmdTabPreviewHoverAction.defaultValue
                Defaults[.keepPreviewOnHoverActivation] = Defaults.Keys.keepPreviewOnHoverActivation.defaultValue

                showMenuBarIcon = Defaults.Keys.showMenuBarIcon.defaultValue
                Defaults[.openWindowSwitcherFromMenuBarIcon] = Defaults.Keys.openWindowSwitcherFromMenuBarIcon.defaultValue
                Defaults[.menuBarIconWindowSwitcherClick] = Defaults.Keys.menuBarIconWindowSwitcherClick.defaultValue
                Defaults[.enableWindowSwitcher] = Defaults.Keys.enableWindowSwitcher.defaultValue
                Defaults[.instantWindowSwitcher] = Defaults.Keys.instantWindowSwitcher.defaultValue
                Defaults[.includeHiddenWindowsInSwitcher] = Defaults.Keys.includeHiddenWindowsInSwitcher.defaultValue
                Defaults[.includeHiddenWindowsInDockPreview] = Defaults.Keys.includeHiddenWindowsInDockPreview.defaultValue
                Defaults[.includeHiddenWindowsInCmdTab] = Defaults.Keys.includeHiddenWindowsInCmdTab.defaultValue
                Defaults[.showWindowlessAppsInSwitcher] = Defaults.Keys.showWindowlessAppsInSwitcher.defaultValue
                Defaults[.excludeWindowlessAppsFromCurrentMonitorSwitcherScopes] = Defaults.Keys.excludeWindowlessAppsFromCurrentMonitorSwitcherScopes.defaultValue
                Defaults[.excludeWindowlessAppsFromCurrentSpaceSwitcherScopes] = Defaults.Keys.excludeWindowlessAppsFromCurrentSpaceSwitcherScopes.defaultValue
                Defaults[.showFullSizeWindowlessDockPreviews] = Defaults.Keys.showFullSizeWindowlessDockPreviews.defaultValue
                Defaults[.showFullSizeWindowlessCmdTabPreviews] = Defaults.Keys.showFullSizeWindowlessCmdTabPreviews.defaultValue
                Defaults[.showWindowlessAppsInDockPreview] = Defaults.Keys.showWindowlessAppsInDockPreview.defaultValue
                Defaults[.showWindowlessAppsInCmdTab] = Defaults.Keys.showWindowlessAppsInCmdTab.defaultValue
                Defaults[.windowlessAppActivationMode] = Defaults.Keys.windowlessAppActivationMode.defaultValue
                Defaults[.ignoreAppsWithSingleWindow] = Defaults.Keys.ignoreAppsWithSingleWindow.defaultValue
                Defaults[.ignoreAppsWithSingleWindowInCmdTab] = Defaults.Keys.ignoreAppsWithSingleWindowInCmdTab.defaultValue
                Defaults[.useClassicWindowOrdering] = Defaults.Keys.useClassicWindowOrdering.defaultValue
                Defaults[.limitSwitcherToFrontmostApp] = Defaults.Keys.limitSwitcherToFrontmostApp.defaultValue
                Defaults[.fullscreenAppBlacklist] = Defaults.Keys.fullscreenAppBlacklist.defaultValue

                Defaults[.UserKeybind] = Defaults.Keys.UserKeybind.defaultValue
                Defaults[.requireShiftTabToGoBack] = Defaults.Keys.requireShiftTabToGoBack.defaultValue
                Defaults[.ignoreMainModifierSideForDependentShortcuts] = Defaults.Keys.ignoreMainModifierSideForDependentShortcuts.defaultValue
                Defaults[.windowSwitcherPlacementStrategy] = Defaults.Keys.windowSwitcherPlacementStrategy.defaultValue
                Defaults[.pinnedScreenIdentifier] = Defaults.Keys.pinnedScreenIdentifier.defaultValue
                Defaults[.windowSwitcherHorizontalAnchor] = Defaults.Keys.windowSwitcherHorizontalAnchor.defaultValue
                Defaults[.windowSwitcherVerticalAnchor] = Defaults.Keys.windowSwitcherVerticalAnchor.defaultValue
                Defaults[.enableShiftWindowSwitcherPlacement] = Defaults.Keys.enableShiftWindowSwitcherPlacement.defaultValue
                Defaults[.windowSwitcherHorizontalOffsetPercent] = Defaults.Keys.windowSwitcherHorizontalOffsetPercent.defaultValue
                Defaults[.windowSwitcherVerticalOffsetPercent] = Defaults.Keys.windowSwitcherVerticalOffsetPercent.defaultValue

                Defaults[.enableDockPreviewGestures] = Defaults.Keys.enableDockPreviewGestures.defaultValue
                Defaults[.dockSwipeTowardsDockAction] = Defaults.Keys.dockSwipeTowardsDockAction.defaultValue
                Defaults[.dockSwipeAwayFromDockAction] = Defaults.Keys.dockSwipeAwayFromDockAction.defaultValue
                Defaults[.gestureSwipeThreshold] = Defaults.Keys.gestureSwipeThreshold.defaultValue
                Defaults[.middleClickAction] = Defaults.Keys.middleClickAction.defaultValue

                Defaults[.cmdShortcuts] = Defaults.Keys.cmdShortcuts.defaultValue
                Defaults.reset(.enableActionFeedback, .actionFeedbackPosition, .showMouseFollowsFocusFeedback)
                Defaults.reset(.disableTitleBarGesturesOverInteractiveElements)
                Defaults[.movingResizingPostActionBehavior] = Defaults.Keys.movingResizingPostActionBehavior.defaultValue
                Defaults[.hidingPostActionBehavior] = Defaults.Keys.hidingPostActionBehavior.defaultValue
                Defaults[.unhidingPostActionBehavior] = Defaults.Keys.unhidingPostActionBehavior.defaultValue
                Defaults[.closingPostActionBehavior] = Defaults.Keys.closingPostActionBehavior.defaultValue
                Defaults[.newWindowPostActionBehavior] = Defaults.Keys.newWindowPostActionBehavior.defaultValue
                Defaults[.moveResizeBringToForeground] = Defaults.Keys.moveResizeBringToForeground.defaultValue

                Defaults[.alternateSwitcherShortcuts] = Defaults.Keys.alternateSwitcherShortcuts.defaultValue
                Defaults[.persistentSwitcherShortcuts] = Defaults.Keys.persistentSwitcherShortcuts.defaultValue
                Defaults[.persistentSwitcherStartsUnfocused] = Defaults.Keys.persistentSwitcherStartsUnfocused.defaultValue
                Defaults[.lastFocusedWindowShortcuts] = Defaults.Keys.lastFocusedWindowShortcuts.defaultValue

                Defaults[.cmdTabAutoSelectFirstWindow] = Defaults.Keys.cmdTabAutoSelectFirstWindow.defaultValue
                Defaults[.cmdTabCycleKey] = Defaults.Keys.cmdTabCycleKey.defaultValue
                Defaults[.enableSpacesBar] = Defaults.Keys.enableSpacesBar.defaultValue
                Defaults[.spacesBarItemSize] = Defaults.Keys.spacesBarItemSize.defaultValue
                Defaults[.trackpadSwitcherSwipeSpaces] = Defaults.Keys.trackpadSwitcherSwipeSpaces.defaultValue
                Defaults[.spacesBarCycleKey] = Defaults.Keys.spacesBarCycleKey.defaultValue
                Defaults[.spacesBarBackwardCycleKey] = Defaults.Keys.spacesBarBackwardCycleKey.defaultValue
                Defaults[.spacesBarFilterWindows] = Defaults.Keys.spacesBarFilterWindows.defaultValue
                Defaults[.spacesBarStartOnNext] = Defaults.Keys.spacesBarStartOnNext.defaultValue
                Defaults[.spacesBarRecentlyUsed] = Defaults.Keys.spacesBarRecentlyUsed.defaultValue
                Defaults[.spacesBarCycleOpensSwitcher] = Defaults.Keys.spacesBarCycleOpensSwitcher.defaultValue
                Defaults[.spacesBarShowAppIcons] = Defaults.Keys.spacesBarShowAppIcons.defaultValue
                Defaults[.spacesBarActivateAppIcons] = Defaults.Keys.spacesBarActivateAppIcons.defaultValue
                Defaults[.spacesBarLabels] = Defaults.Keys.spacesBarLabels.defaultValue
                Defaults[.spacesBarFixedWidth] = Defaults.Keys.spacesBarFixedWidth.defaultValue
                Defaults[.spacesBarPreferDetails] = Defaults.Keys.spacesBarPreferDetails.defaultValue
                Defaults[.spacesBarMinimumWidth] = Defaults.Keys.spacesBarMinimumWidth.defaultValue
                Defaults[.spacesBarMaximumWidth] = Defaults.Keys.spacesBarMaximumWidth.defaultValue
                Defaults[.spacesBarPillWidth] = Defaults.Keys.spacesBarPillWidth.defaultValue
                Defaults[.spacesBarHideWhenSingle] = Defaults.Keys.spacesBarHideWhenSingle.defaultValue
                Defaults[.searchTriggerKey] = Defaults.Keys.searchTriggerKey.defaultValue

                Defaults[.showSpecialAppControls] = Defaults.Keys.showSpecialAppControls.defaultValue
                Defaults[.enableFolderWidget] = Defaults.Keys.enableFolderWidget.defaultValue
                Defaults[.folderWidgetDefaultSortOrder] = Defaults.Keys.folderWidgetDefaultSortOrder.defaultValue
                Defaults[.folderWidgetDefaultSortReversed] = Defaults.Keys.folderWidgetDefaultSortReversed.defaultValue
                Defaults[.folderWidgetRememberSortPerFolder] = Defaults.Keys.folderWidgetRememberSortPerFolder.defaultValue
                Defaults[.folderWidgetSortOrders] = Defaults.Keys.folderWidgetSortOrders.defaultValue
                Defaults[.folderWidgetSortReversed] = Defaults.Keys.folderWidgetSortReversed.defaultValue
                Defaults[.folderWidgetShowHiddenFiles] = Defaults.Keys.folderWidgetShowHiddenFiles.defaultValue
                Defaults[.showBigControlsWhenNoValidWindows] = Defaults.Keys.showBigControlsWhenNoValidWindows.defaultValue
                Defaults[.showMassActionButtons] = Defaults.Keys.showMassActionButtons.defaultValue
                Defaults[.useEmbeddedMediaControls] = Defaults.Keys.useEmbeddedMediaControls.defaultValue
                Defaults[.enablePinning] = Defaults.Keys.enablePinning.defaultValue

                Defaults[.enableDockLocking] = Defaults.Keys.enableDockLocking.defaultValue
                Defaults[.lockedDockScreenIdentifier] = Defaults.Keys.lockedDockScreenIdentifier.defaultValue
                Defaults[.dockLockOverrideModifier] = Defaults.Keys.dockLockOverrideModifier.defaultValue
                Defaults[.filteredCalendarIdentifiers] = Defaults.Keys.filteredCalendarIdentifiers.defaultValue
                Defaults[.groupAppInstancesInDock] = Defaults.Keys.groupAppInstancesInDock.defaultValue

                Defaults[.disableImagePreview] = Defaults.Keys.disableImagePreview.defaultValue
                Defaults[.enableHoverActionsInCompactMode] = Defaults.Keys.enableHoverActionsInCompactMode.defaultValue

                askUserToRestartApplication()
            }
        }
    }
}

struct AddBlacklistAppSheet: View {
    @Binding var isPresented: Bool
    @Binding var appNameToAdd: String
    var onAdd: (String) -> Void

    @State private var selectedAppInfo: String = ""
    @State private var isLoadingAppInfo: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Add App to Blacklist")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Text("Select an application:")
                    .font(.subheadline)

                Button(action: selectAppFile) {
                    HStack {
                        Image(systemName: "folder")
                        Text("Browse for .app file...")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingAppInfo)

                if isLoadingAppInfo {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Reading app information...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !selectedAppInfo.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected app:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(selectedAppInfo)
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                    }
                }

                Text("This will add the app to the blacklist using its bundle identifier for reliable matching.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    resetState()
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()
            }
        }
        .padding()
        .frame(width: 450, height: 200)
    }

    private func selectAppFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = "Select Application"
        panel.message = "Choose an application to add to the blacklist"

        if panel.runModal() == .OK, let url = panel.url {
            isLoadingAppInfo = true

            DispatchQueue.global(qos: .userInitiated).async {
                let bundle = Bundle(url: url)
                let appName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent

                let bundleIdentifier = bundle?.bundleIdentifier ?? ""

                DispatchQueue.main.async {
                    let appToAdd: String
                    if !bundleIdentifier.isEmpty {
                        appToAdd = bundleIdentifier
                        selectedAppInfo = "\(appName) (\(bundleIdentifier))"
                    } else {
                        appToAdd = appName
                        selectedAppInfo = appName
                    }

                    onAdd(appToAdd)
                    resetState()
                    isPresented = false
                    isLoadingAppInfo = false
                }
            }
        }
    }

    private func resetState() {
        appNameToAdd = ""
        selectedAppInfo = ""
        isLoadingAppInfo = false
    }
}

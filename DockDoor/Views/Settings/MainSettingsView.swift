import AppKit
import Defaults
import LaunchAtLogin
import SwiftUI

struct MainSettingsView: View {
    @Default(.showMenuBarIcon) var showMenuBarIcon
    @Default(.showAnimations) var showAnimations
    @Default(.sortMinimizedToEnd) var sortMinimizedToEnd
    @Default(.showSettingsDescriptions) var showSettingsDescriptions

    var body: some View {
        SettingsFormView {
            DockDoorProBanner()
            supportAndContributionsSection
            applicationBasicsSection
            activeAppIndicatorSection
            backupAndRestoreSection
            resetAndQuitSection
        }
    }

    // MARK: - Support & Contributions

    private var supportAndContributionsSection: some View {
        SettingsSection("Support & Contributions") {
            SupportLinksSection()
        }
    }

    // MARK: - Application Basics

    private var applicationBasicsSection: some View {
        SettingsSection("Application Basics") {
            LaunchAtLogin.Toggle(String(localized: "Launch DockDoor at login"))
                .settingsSearchTarget("general.launchAtLogin")

            Toggle(isOn: $showMenuBarIcon, label: { Text("Show menu bar icon") })
                .settingsSearchTarget("general.menuBarIcon")
                .onChange(of: showMenuBarIcon) { isOn in
                    let appDelegate = NSApplication.shared.delegate as! AppDelegate
                    if isOn {
                        appDelegate.setupMenuBar()
                    } else {
                        appDelegate.removeMenuBar()
                    }
                }

            Toggle(isOn: Binding(
                get: { !showAnimations },
                set: { showAnimations = !$0 }
            )) {
                Text("Reduce motion")
            }
            .settingsSearchTarget("general.reduceMotion")

            Toggle(isOn: $showSettingsDescriptions, label: { Text("Show setting descriptions") })
                .settingsSearchTarget("general.showSettingDescriptions")
                .settingsAnnotation("Explain what each setting does underneath its row.")

            Toggle(isOn: $sortMinimizedToEnd, label: {
                Text("Sort minimized/hidden windows to end")
            })
            .settingsAnnotation("Minimized and hidden windows will appear after all visible windows in previews and switcher.")
            .settingsSearchTarget("general.sortMinimized")
            .onChange(of: sortMinimizedToEnd) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar(.contents) }
        }
    }

    // MARK: - Active App Indicator

    private var activeAppIndicatorSection: some View {
        SettingsSection("Active App Indicator") {
            ActiveAppIndicatorSettingsView()
        }
    }

    // MARK: - Backup & Restore

    private var backupAndRestoreSection: some View {
        SettingsSection("Backup & Restore") {
            LabeledContent("Settings file") {
                HStack(spacing: 8) {
                    Button("Export Settings…") { SettingsBackupManager.exportSettings() }
                        .buttonStyle(.settings)
                        .settingsSearchTarget("general.exportSettings")
                    Button("Import Settings…") { SettingsBackupManager.importSettings() }
                        .buttonStyle(.settings)
                        .settingsSearchTarget("general.importSettings")
                }
            }
            .settingsAnnotation("Settings are saved as a JSON file you can keep in iCloud Drive or a dotfiles repository. Importing replaces your current settings and restarts DockDoor.")
        }
    }

    private var resetAndQuitSection: some View {
        SettingsSection("Reset and quit") {
            LabeledContent("Reset All Settings to Defaults") {
                Button("Reset", role: .destructive) { showResetConfirmation() }
                    .buttonStyle(.settings)
            }
            .settingsAnnotation("Every setting goes back to its default. This can't be undone.")

            LabeledContent("Quit DockDoor") {
                Button("Quit") { (NSApplication.shared.delegate as! AppDelegate).quitApp() }
                    .buttonStyle(.settings)
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

                Defaults.reset(.showSettingsDescriptions)
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
                Defaults.reset(.strictTitleBarGestureDetection)
                Defaults.reset(.centerOutOfViewSelections)
                Defaults.reset(.dockPreviewSpaceNumberIndicatorPlacement, .switcherSpaceNumberIndicatorPlacement, .cmdTabSpaceNumberIndicatorPlacement)
                Defaults[.movingResizingPostActionBehavior] = Defaults.Keys.movingResizingPostActionBehavior.defaultValue
                Defaults[.hidingPostActionBehavior] = Defaults.Keys.hidingPostActionBehavior.defaultValue
                Defaults[.unhidingPostActionBehavior] = Defaults.Keys.unhidingPostActionBehavior.defaultValue
                Defaults[.closingPostActionBehavior] = Defaults.Keys.closingPostActionBehavior.defaultValue
                Defaults[.newWindowPostActionBehavior] = Defaults.Keys.newWindowPostActionBehavior.defaultValue
                Defaults[.moveResizeBringToForeground] = Defaults.Keys.moveResizeBringToForeground.defaultValue

                Defaults[.alternateSwitcherShortcuts] = Defaults.Keys.alternateSwitcherShortcuts.defaultValue

                Defaults[.cmdTabAutoSelectFirstWindow] = Defaults.Keys.cmdTabAutoSelectFirstWindow.defaultValue
                Defaults[.cmdTabCycleKey] = Defaults.Keys.cmdTabCycleKey.defaultValue
                Defaults[.enableSpacesBar] = Defaults.Keys.enableSpacesBar.defaultValue
                Defaults[.spacesBarItemSize] = Defaults.Keys.spacesBarItemSize.defaultValue
                Defaults[.trackpadSwitcherSwipeSpaces] = Defaults.Keys.trackpadSwitcherSwipeSpaces.defaultValue
                Defaults[.trackpadSwitcherSwipeDisabledActivationDirections] = Defaults.Keys.trackpadSwitcherSwipeDisabledActivationDirections.defaultValue
                Defaults[.spacesBarCycleKey] = Defaults.Keys.spacesBarCycleKey.defaultValue
                Defaults[.spacesBarBackwardCycleKey] = Defaults.Keys.spacesBarBackwardCycleKey.defaultValue
                Defaults[.spacesBarFilterWindows] = Defaults.Keys.spacesBarFilterWindows.defaultValue
                Defaults[.spacesBarStartOnNext] = Defaults.Keys.spacesBarStartOnNext.defaultValue
                Defaults[.spacesBarRecentlyUsed] = Defaults.Keys.spacesBarRecentlyUsed.defaultValue
                Defaults[.spacesBarCycleOpensSwitcher] = Defaults.Keys.spacesBarCycleOpensSwitcher.defaultValue
                Defaults[.spacesBarSwapContents] = Defaults.Keys.spacesBarSwapContents.defaultValue
                Defaults[.spacesBarShowAppIcons] = Defaults.Keys.spacesBarShowAppIcons.defaultValue
                Defaults[.spacesBarActivateAppIcons] = Defaults.Keys.spacesBarActivateAppIcons.defaultValue
                Defaults[.spacesBarLabels] = Defaults.Keys.spacesBarLabels.defaultValue
                Defaults[.spacesBarFixedWidth] = Defaults.Keys.spacesBarFixedWidth.defaultValue
                Defaults[.spacesBarMinimumIcons] = Defaults.Keys.spacesBarMinimumIcons.defaultValue
                Defaults[.spacesBarMaximumIcons] = Defaults.Keys.spacesBarMaximumIcons.defaultValue
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

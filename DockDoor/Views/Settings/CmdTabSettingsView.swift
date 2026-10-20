import Defaults
import SwiftUI

struct CmdTabSettingsView: View {
    @Default(.enableCmdTabEnhancements) var enableCmdTabEnhancements
    @Default(.cmdTabCycleKey) var cmdTabCycleKey
    @Default(.cmdTabBackwardCycleKey) var cmdTabBackwardCycleKey
    @Default(.showWindowsFromCurrentSpaceOnlyInCmdTab) var showWindowsFromCurrentSpaceOnlyInCmdTab
    @Default(.showWindowsFromCurrentMonitorOnlyInCmdTab) var showWindowsFromCurrentMonitorOnlyInCmdTab
    @Default(.cmdTabSortOrder) var cmdTabSortOrder
    @Default(.cmdTabAutoSelectFirstWindow) var cmdTabAutoSelectFirstWindow
    @Default(.cmdTabPreviewHoverAction) var cmdTabPreviewHoverAction
    @Default(.cmdTabTapEquivalentInterval) var cmdTabTapEquivalentInterval
    @Default(.enableCmdTabEdgeAutoScroll) var enableCmdTabEdgeAutoScroll
    @Default(.cmdTabEdgeAutoScrollSpeed) var cmdTabEdgeAutoScrollSpeed
    @Default(.includeHiddenWindowsInCmdTab) var includeHiddenWindowsInCmdTab
    @Default(.showFullSizeWindowlessCmdTabPreviews) var showFullSizeWindowlessCmdTabPreviews
    @Default(.showWindowlessAppsInCmdTab) var showWindowlessAppsInCmdTab
    @Default(.ignoreAppsWithSingleWindowInCmdTab) var ignoreAppsWithSingleWindowInCmdTab

    var body: some View {
        BaseSettingsView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                if enableCmdTabEnhancements {
                    configurationSection
                    hoverActionsSection
                    windowDisplaySection

                    SettingsMockPreview(context: .cmdTab)

                    appearanceSection
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        SettingsGroup {
            SettingsIllustratedToggle(
                isOn: $enableCmdTabEnhancements,
                title: "Enable Cmd+Tab Enhancements",
                imageName: "CmdTab"
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show previews while holding Cmd+Tab.")
                    Text("Cmd+\(KeyboardLabel.localizedKey(for: cmdTabCycleKey)) cycles forward, Cmd+\(KeyboardLabel.localizedKey(for: cmdTabBackwardCycleKey)) or Shift+Tab cycles backward, Left/Right navigate, Down clears selection.")
                }
            }
            .settingsSearchTarget("cmdTab.enable")
            .onChange(of: enableCmdTabEnhancements) { _ in askUserToRestartApplication() }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsGroup(header: "Appearance") {
            CmdTabAppearanceSection()
        }
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        SettingsGroup(header: "Configuration") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Preview cycle key:")
                    HStack(spacing: 4) {
                        Text("⌘")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        KeyCaptureButton(keyCode: $cmdTabCycleKey)
                    }
                }
                .settingsSearchTarget("cmdTab.cycleKey")

                HStack(spacing: 8) {
                    Text("Backward cycle key:")
                    HStack(spacing: 4) {
                        Text("⌘")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        KeyCaptureButton(keyCode: $cmdTabBackwardCycleKey)
                    }
                }
                .settingsSearchTarget("cmdTab.backwardKey")

                Toggle(isOn: $cmdTabAutoSelectFirstWindow) { Text("Automatically select first window") }
                    .settingsSearchTarget("cmdTab.autoSelect")
                Text("When Cmd+Tab opens, highlight the first window preview automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }
        }
    }

    // MARK: - Hover Actions

    private var hoverActionsSection: some View {
        SettingsGroup(header: "Hover Actions") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Cmd+Tab Hover Action", selection: $cmdTabPreviewHoverAction) {
                    ForEach(PreviewHoverAction.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                }
                .pickerStyle(.menu)
                .settingsSearchTarget("cmdTab.hoverAction")

                HStack {
                    Text("Cmd+Tab Hover Action Delay")
                    Slider(value: $cmdTabTapEquivalentInterval, in: 0 ... 2, step: 0.1)
                    Text(String(format: "%.1f s", cmdTabTapEquivalentInterval))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
                .disabled(cmdTabPreviewHoverAction == .none)
                .settingsSearchTarget("cmdTab.hoverDelay")

                PreviewFocusFadeSettings(mode: .cmdTab)

                Toggle(isOn: $enableCmdTabEdgeAutoScroll) {
                    Text("Enable edge auto-scroll")
                }
                .settingsSearchTarget("cmdTab.edgeAutoScroll")

                if enableCmdTabEdgeAutoScroll {
                    HStack {
                        Text("Auto-scroll speed:")
                        Slider(value: $cmdTabEdgeAutoScrollSpeed, in: 1 ... 10, step: 0.5)
                        Text(String(format: "%.1f", cmdTabEdgeAutoScrollSpeed))
                            .frame(width: 30)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                    .settingsSearchTarget("cmdTab.edgeAutoScrollSpeed")
                }
            }
        }
    }

    // MARK: - Window Display

    private var windowDisplaySection: some View {
        SettingsGroup(header: "Window Display") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $showWindowsFromCurrentSpaceOnlyInCmdTab) { Text("Show windows from current Space only") }
                    .settingsSearchTarget("cmdTab.currentSpaceOnly")
                Text("Only display windows that are in the current virtual desktop/Space.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)

                Toggle(isOn: $showWindowsFromCurrentMonitorOnlyInCmdTab) { Text("Show windows from current monitor only") }
                    .settingsSearchTarget("cmdTab.currentMonitorOnly")
                Text("Only display windows that are on the same display as the mouse cursor.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)

                Toggle(isOn: $includeHiddenWindowsInCmdTab) { Text("Include hidden/minimized windows") }
                    .settingsSearchTarget("cmdTab.includeHidden")

                Toggle(isOn: $showWindowlessAppsInCmdTab) { Text("Show preview for apps with no open windows") }
                    .settingsSearchTarget("cmdTab.showWindowless")
                Text("Show a placeholder preview when Cmd+Tab lands on an app that has no windows.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)

                if showWindowlessAppsInCmdTab {
                    Toggle("Show full size placeholders", isOn: $showFullSizeWindowlessCmdTabPreviews)
                        .settingsSearchTarget("cmdTab.fullSizeWindowless")
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $ignoreAppsWithSingleWindowInCmdTab) { Text("Ignore apps with one window") }
                        .settingsSearchTarget("cmdTab.ignoreSingleWindow")
                    Text("Prevents apps with exactly one open window from appearing in previews.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
                .padding(.leading, 20)
                .disabled(showWindowlessAppsInCmdTab)
                .opacity(showWindowlessAppsInCmdTab ? 0.5 : 1)

                Picker("Window sort order", selection: $cmdTabSortOrder) {
                    ForEach(WindowPreviewSortOrder.allCases.filter { !$0.isWindowSwitcherOnly }) { order in
                        Text(order.localizedName).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .settingsSearchTarget("cmdTab.sortOrder")
            }
        }
    }
}

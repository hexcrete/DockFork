import Defaults
import SwiftUI

struct AdvancedSettingsView: View {
    @Default(.windowProcessingDebounceInterval) var windowProcessingDebounceInterval
    @Default(.anchorDockPreviewPosition) var anchorDockPreviewPosition
    @Default(.preventDockHide) var preventDockHide
    @Default(.raisedWindowLevel) var raisedWindowLevel
    @Default(.disableMinWindowSizeFilter) var disableMinWindowSizeFilter

    @Default(.windowImageCaptureQuality) var windowImageCaptureQuality
    @Default(.screenCaptureCacheLifespan) var screenCaptureCacheLifespan
    @Default(.windowPreviewImageScale) var windowPreviewImageScale

    @Default(.enableLivePreview) var enableLivePreview
    @Default(.enableLivePreviewForDock) var enableLivePreviewForDock
    @Default(.enableLivePreviewForWindowSwitcher) var enableLivePreviewForWindowSwitcher
    @Default(.dockLivePreviewQuality) var dockLivePreviewQuality
    @Default(.dockLivePreviewFrameRate) var dockLivePreviewFrameRate
    @Default(.windowSwitcherLivePreviewQuality) var windowSwitcherLivePreviewQuality
    @Default(.windowSwitcherLivePreviewFrameRate) var windowSwitcherLivePreviewFrameRate
    @Default(.windowSwitcherLivePreviewScope) var windowSwitcherLivePreviewScope
    @Default(.livePreviewStreamKeepAlive) var livePreviewStreamKeepAlive

    @Default(.enableDockLocking) var enableDockLocking
    @Default(.lockedDockScreenIdentifier) var lockedDockScreenIdentifier
    @Default(.dockLockOverrideModifier) var dockLockOverrideModifier

    @Default(.programmaticResizePreviewRefreshDelay) var programmaticResizePreviewRefreshDelay
    @Default(.nativeResizePreviewRefreshDelay) var nativeResizePreviewRefreshDelay
    @Default(.enableSpringLoading) var enableSpringLoading
    @Default(.useSystemSpringLoadingSpeed) var useSystemSpringLoadingSpeed
    @Default(.springLoadingDelay) var springLoadingDelay
    @Default(.windowlessAppActivationMode) var windowlessAppActivationMode
    @FocusState private var isKeepAliveFieldFocused: Bool
    @State private var lastKeepAliveDuration: Int = 5
    @State private var keepAliveDurationText = "5"

    var body: some View {
        SettingsFormView {
            performanceTuningSection
            springLoadingSection
            previewQualitySection
            livePreviewSection

            if enableLivePreview {
                dockLivePreviewSection
                switcherLivePreviewSection
                streamManagementSection
            }

            dockLockingSection
        }
        .onAppear {
            applyResizeRefreshDebounceDelays()
            if livePreviewStreamKeepAlive > 0 {
                lastKeepAliveDuration = livePreviewStreamKeepAlive
                keepAliveDurationText = "\(livePreviewStreamKeepAlive)"
            }
        }
        .onChange(of: programmaticResizePreviewRefreshDelay) { _ in applyResizeRefreshDebounceDelays() }
        .onChange(of: nativeResizePreviewRefreshDelay) { _ in applyResizeRefreshDebounceDelays() }
    }

    // MARK: - Performance Tuning

    private var performanceTuningSection: some View {
        SettingsSection("Performance Tuning") {
            SettingsSliderRow(
                title: "Window Processing Debounce Interval",
                value: $windowProcessingDebounceInterval,
                range: 0 ... 3,
                unit: " s",
                step: 0.1,
                decimals: 1,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        askUserToRestartApplication()
                    }
                }
            )
            .settingsSearchTarget("advanced.debounce")

            SettingsSliderRow(title: "Programmatic Resize Preview Refresh Delay", value: $programmaticResizePreviewRefreshDelay, range: 0 ... 1, defaultValue: Defaults.Keys.programmaticResizePreviewRefreshDelay.defaultValue, unit: " s", step: 0.01, decimals: 2)
                .settingsSearchTarget("advanced.programmaticResizeRefreshDelay")
            SettingsSliderRow(title: "Native Resize Preview Refresh Delay", value: $nativeResizePreviewRefreshDelay, range: 0 ... 1, defaultValue: Defaults.Keys.nativeResizePreviewRefreshDelay.defaultValue, unit: " s", step: 0.01, decimals: 2)
                .settingsSearchTarget("advanced.nativeResizeRefreshDelay")
            Toggle(isOn: $anchorDockPreviewPosition) {
                Text("Anchor preview to initial dock icon position")
            }
            .settingsSearchTarget("advanced.anchorPosition")
            .settingsAnnotation("Keeps the preview pinned where the dock icon was when first hovered, preventing it from jumping when the dock auto-hides.")

            Toggle(isOn: $preventDockHide) { Text("Prevent dock from hiding during previews") }
                .settingsSearchTarget("advanced.preventDockHide")
            Toggle(isOn: $raisedWindowLevel) { Text("Show preview above app labels") }
                .settingsSearchTarget("advanced.raisedLevel")
                .onChange(of: raisedWindowLevel) { _ in askUserToRestartApplication() }

            Toggle(isOn: $disableMinWindowSizeFilter) {
                Text("Show small windows (under 100px)")
            }
            .settingsSearchTarget("advanced.smallWindows")
            .settingsAnnotation("Includes small windows like Finder's copy progress dialog in previews.")

            Picker(String(localized: "Clicking windowless apps", comment: "Setting label for behavior when activating apps with no windows"), selection: $windowlessAppActivationMode) {
                ForEach(WindowlessAppActivationMode.allCases, id: \.self) { mode in Text(mode.localizedName).tag(mode) }
            }

            .settingsSearchTarget("advanced.openNewWindow")
            .settingsAnnotation(verbatim: windowlessAppActivationMode.localizedDescription)
        }
    }

    // MARK: - Preview Quality

    private var previewQualitySection: some View {
        SettingsSection("Preview Quality") {
            Picker("Window Image Capture Quality", selection: $windowImageCaptureQuality) {
                ForEach(WindowImageCaptureQuality.allCases, id: \.self) { quality in
                    Text(quality.localizedName).tag(quality)
                }
            }
            .settingsSearchTarget("advanced.captureQuality")

            SettingsSliderRow(
                title: "Window Image Cache Lifespan",
                value: $screenCaptureCacheLifespan,
                range: 0 ... 60,
                unit: " s",
                step: 10
            )
            .settingsSearchTarget("advanced.cacheLifespan")
            SettingsSliderRow(
                title: "Window Image Resolution Scale (1=Best)",
                value: $windowPreviewImageScale,
                range: 1 ... 4,
                step: 1
            )
            .settingsSearchTarget("advanced.imageScale")
        }
    }

    // MARK: - Live Preview

    private var livePreviewSection: some View {
        SettingsSection("Live Preview") {
            Toggle(isOn: $enableLivePreview) { Text("Enable Live Preview (Video)") }
                .settingsSearchTarget("advanced.livePreview")
                .onChange(of: enableLivePreview) { newValue in
                    if !newValue {
                        Task { await LiveCaptureManager.shared.stopAllStreams() }
                    }
                }
                .settingsAnnotation(
                    "Window previews show live video instead of static screenshots. Uses ScreenCaptureKit for real-time capture.",
                    more: "Higher quality and frame rate use more CPU/GPU resources. Use lower settings for Window Switcher if you experience lag."
                )
        }
    }

    // MARK: - Dock Live Preview

    private var dockLivePreviewSection: some View {
        SettingsSection("Dock Live Preview") {
            Toggle(isOn: $enableLivePreviewForDock) { Text("Enable for Dock Preview") }
                .settingsSearchTarget("advanced.livePreviewDock")

            if enableLivePreviewForDock {
                SettingsDependentRows {
                    Picker("Quality", selection: $dockLivePreviewQuality) {
                        ForEach(LivePreviewQuality.allCases, id: \.self) { quality in
                            Text(quality.localizedName).tag(quality)
                        }
                    }

                    Picker("Frame Rate", selection: $dockLivePreviewFrameRate) {
                        ForEach(LivePreviewFrameRate.allCases, id: \.self) { fps in
                            Text(fps.localizedName).tag(fps)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Switcher Live Preview

    private var switcherLivePreviewSection: some View {
        SettingsSection("Switcher Live Preview") {
            Toggle(isOn: $enableLivePreviewForWindowSwitcher) { Text("Enable for Window Switcher") }
                .settingsSearchTarget("advanced.livePreviewSwitcher")

            if enableLivePreviewForWindowSwitcher {
                SettingsDependentRows {
                    Picker("Quality", selection: $windowSwitcherLivePreviewQuality) {
                        ForEach(LivePreviewQuality.allCases, id: \.self) { quality in
                            Text(quality.localizedName).tag(quality)
                        }
                    }

                    Picker("Frame Rate", selection: $windowSwitcherLivePreviewFrameRate) {
                        ForEach(LivePreviewFrameRate.allCases, id: \.self) { fps in
                            Text(fps.localizedName).tag(fps)
                        }
                    }

                    Picker("Scope", selection: $windowSwitcherLivePreviewScope) {
                        ForEach(WindowSwitcherLivePreviewScope.allCases, id: \.self) { scope in
                            Text(scope.localizedName).tag(scope)
                        }
                    }

                    Text(windowSwitcherLivePreviewScope.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Stream Management

    private var streamManagementSection: some View {
        SettingsSection("Stream Management") {
            Picker("Stream Keep-Alive Duration", selection: keepAliveModeBinding) {
                Text("Immediately close").tag(0)
                Text("Close after a delay").tag(1)
                Text("Keep Open").tag(-1)
            }
            .onChange(of: livePreviewStreamKeepAlive) { newValue in
                if newValue > 0 {
                    lastKeepAliveDuration = newValue
                    keepAliveDurationText = "\(newValue)"
                }
                if newValue == 0 {
                    Task { await LiveCaptureManager.shared.stopAllStreams() }
                }
            }
            .settingsAnnotation("How long to keep video streams active after closing preview. Longer duration means faster reopening but uses more resources.")
            .settingsSearchTarget("advanced.streamKeepAlive")

            if livePreviewStreamKeepAlive > 0 {
                LabeledContent("Close after") {
                    HStack(spacing: 6) {
                        TextField("", text: $keepAliveDurationText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 48)
                            .multilineTextAlignment(.trailing)
                            .focused($isKeepAliveFieldFocused)
                            .onSubmit {
                                commitKeepAliveDurationText()
                            }
                            .onChange(of: keepAliveDurationText) { _ in
                                updateKeepAliveDurationFromText()
                            }
                            .onChange(of: isKeepAliveFieldFocused) { focused in
                                if !focused {
                                    commitKeepAliveDurationText()
                                }
                            }
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var keepAliveModeBinding: Binding<Int> {
        Binding(
            get: { livePreviewStreamKeepAlive > 0 ? 1 : livePreviewStreamKeepAlive },
            set: { mode in
                setKeepAliveMode(mode == 1 ? lastKeepAliveDuration : mode)
            }
        )
    }

    private func setKeepAliveMode(_ value: Int) {
        livePreviewStreamKeepAlive = value
        isKeepAliveFieldFocused = false

        if value > 0 {
            lastKeepAliveDuration = value
            keepAliveDurationText = "\(value)"
        }
    }

    private func updateKeepAliveDurationFromText() {
        guard let duration = positiveKeepAliveDuration() else { return }

        lastKeepAliveDuration = duration

        if livePreviewStreamKeepAlive > 0 {
            livePreviewStreamKeepAlive = duration
        }
    }

    private func commitKeepAliveDurationText() {
        guard let duration = positiveKeepAliveDuration() else {
            keepAliveDurationText = "\(lastKeepAliveDuration)"
            return
        }

        lastKeepAliveDuration = duration
        keepAliveDurationText = "\(duration)"

        if livePreviewStreamKeepAlive > 0 {
            livePreviewStreamKeepAlive = duration
        }
    }

    private func positiveKeepAliveDuration() -> Int? {
        let text = keepAliveDurationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let duration = Int(text) else { return nil }
        return max(1, duration)
    }

    // MARK: - Dock Locking

    private var isLockedScreenDisconnected: Bool {
        !lockedDockScreenIdentifier.isEmpty
            && NSScreen.findScreen(byIdentifier: lockedDockScreenIdentifier) == nil
    }

    private var isLockedScreenEdgeCovered: Bool {
        guard NSScreen.screens.count > 1,
              let screen = NSScreen.findScreen(byIdentifier: lockedDockScreenIdentifier)
        else { return false }
        let dockPosition = DockUtils.getDockPosition()
        guard dockPosition == .bottom || dockPosition == .left || dockPosition == .right else { return false }
        return DockLockerGeometry.exposedIntervals(
            for: screen.cgFrame,
            dockPosition: dockPosition,
            allFrames: NSScreen.screens.map(\.cgFrame)
        ).isEmpty
    }

    private var dockLockingSection: some View {
        SettingsSection("Dock Locking") {
            Toggle(isOn: $enableDockLocking) { Text("Lock Dock to Screen") }
                .settingsSearchTarget("dockLocking.enable")
                .settingsAnnotation("Prevent the Dock from jumping to other monitors when your cursor reaches the screen edge.")
                .onChange(of: enableDockLocking) { isOn in
                    if isOn, lockedDockScreenIdentifier.isEmpty {
                        lockedDockScreenIdentifier = NSScreen.systemMainDisplayIdentifier
                    }
                    askUserToRestartApplication()
                }

            if enableDockLocking {
                SettingsDependentRows {
                    dockLockingConfiguration
                    SettingsNote(
                        icon: "info.circle",
                        text: "Dock Locking works best with a bottom-positioned Dock in a multi-monitor setup where \"Displays have separate Spaces\" is enabled in System Settings → Desktop & Dock → Mission Control. The Dock won't jump to another monitor while this feature is enabled."
                    )
                }
            }
        }
    }

    private var dockLockingConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Lock Dock to", selection: $lockedDockScreenIdentifier) {
                Text("System Main Display").tag(NSScreen.systemMainDisplayIdentifier)
                ForEach(NSScreen.screens, id: \.self) { screen in
                    Text(screen.displayName).tag(screen.uniqueIdentifier())
                }
                if isLockedScreenDisconnected {
                    Text("Disconnected Display").tag(lockedDockScreenIdentifier)
                }
            }
            .settingsSearchTarget("dockLocking.screen")
            .onAppear { NSScreen.migrateScreenIdentifier(.lockedDockScreenIdentifier) }

            if isLockedScreenDisconnected {
                SettingsCallout(message: Text("This display is currently disconnected. Dock locking will be disabled until it reconnects."))
            } else if isLockedScreenEdgeCovered {
                SettingsWarningBanner(text: "macOS can't place the Dock on this display because another display sits directly against its Dock edge. Rearrange your displays in System Settings → Displays so part of that edge is free.")
            } else {
                SettingsCallout(tone: .info, message: Text("System Main Display follows whichever screen holds the menu bar. DockDoor moves the Dock to the locked screen automatically; you can also push the cursor against that screen's Dock edge."))
            }

            Picker("Bypass modifier key", selection: $dockLockOverrideModifier) {
                ForEach(DockLockModifier.allCases, id: \.rawValue) { modifier in
                    Text(modifier.localizedName).tag(modifier.rawValue)
                }
            }
            .settingsSearchTarget("dockLocking.bypass")
            .settingsAnnotation("Hold this key to temporarily allow the Dock to move freely.")
        }
    }

    private var springLoadingSection: some View {
        SettingsSection("Spring-loading") {
            Toggle(isOn: $enableSpringLoading) {
                Text("Enable spring-loading")
            }
            .settingsSearchTarget("advanced.enableSpringLoading")

            Text("Spring-loading reveals and activates a window after you drag an item over its preview in Dock previews, Window Switcher, or Cmd+Tab.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            if enableSpringLoading {
                SettingsDependentRows {
                    Toggle(isOn: $useSystemSpringLoadingSpeed) {
                        Text("Use system spring-loading speed")
                    }
                    .settingsSearchTarget("advanced.useSystemSpringLoadingSpeed")

                    if !useSystemSpringLoadingSpeed {
                        SettingsDependentRows {
                            SettingsSliderRow(title: "Spring-loading delay", value: $springLoadingDelay, range: 0.5 ... 2, defaultValue: Defaults.Keys.springLoadingDelay.defaultValue, unit: " s", step: 0.05, formatter: NumberFormatter.twoDecimalFormatter)
                                .settingsSearchTarget("advanced.springLoadingDelay")
                        }
                    }
                }
            }
        }
    }

    private func applyResizeRefreshDebounceDelays() {
        WindowUtil.setResizeRefreshDebounceDelays(
            programmaticSeconds: programmaticResizePreviewRefreshDelay,
            axSeconds: nativeResizePreviewRefreshDelay
        )
    }
}

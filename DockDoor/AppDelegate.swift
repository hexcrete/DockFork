import ApplicationServices
import Cocoa
import Defaults
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var dockObserver: DockObserver?
    private var appClosureObserver: WindowManipulationObservers?
    private var windowSeeder: WindowSeeder?
    private var previewCoordinator: SharedPreviewWindowCoordinator?
    private var keybindHelper: KeybindHelper?
    private var windowGestureController: WindowGestureController?
    private var activeAppIndicator: ActiveAppIndicatorCoordinator?
    private var dockLocker: DockLocker?
    private var statusBarItem: NSStatusItem?
    private var statusBarMenu: NSMenu?
    private var menuBarInteractionObserver: Defaults.Observation?
    private var menuBarClickMonitor: Any?
    private var isStatusBarMenuPresented = false
    private var statusBarMenuDismissalEventNumber: Int?
    private var statusBarMenuDismissalTimestamp: TimeInterval?
    private let windowActionsMenu = WindowActionsMenuController()
    private var updaterController: SPUStandardUpdaterController
    @ObservedObject var updaterState: UpdaterState

    var updater: SPUUpdater {
        updaterController.updater
    }

    #if DEBUG
        private var debugHarness: DebugTestHarness?
    #endif
    private var cinematicOverlay: CinematicOverlay?
    private var onboardingWindow: NSWindow?
    private var settingsManager: SettingsManager?

    override init() {
        let state = UpdaterState()
        updaterState = state

        let anUpdaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: state, userDriverDelegate: nil)
        updaterController = anUpdaterController

        state.updater = anUpdaterController.updater

        super.init()

        settingsManager = SettingsManager(updaterState: state)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        applyAppearanceMode(Defaults[.appAppearanceMode])
        WindowUtil.setResizeRefreshDebounceDelays(
            programmaticSeconds: Defaults[.programmaticResizePreviewRefreshDelay],
            axSeconds: Defaults[.nativeResizePreviewRefreshDelay]
        )

        reconcileImagePreviewWithPermission()

        // Set global AX timeout to prevent hangs from unresponsive apps
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(handleSystemWake),
                name: name,
                object: nil
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if Defaults[.showMenuBarIcon] {
            setupMenuBar()
        } else {
            removeMenuBar()
        }
        observeMenuBarInteractionSettings()

        MediaRemoteService.shared.activate()
        ScreenReservations.shared.start()

        if !Defaults[.launched] {
            handleFirstTimeLaunch()
        } else {
            let currentPreviewCoordinator = SharedPreviewWindowCoordinator()
            previewCoordinator = currentPreviewCoordinator

            let dockObs = DockObserver(previewCoordinator: currentPreviewCoordinator)
            dockObserver = dockObs

            if Defaults[.enableWindowSwitcher] || Defaults[.enableCmdTabEnhancements] {
                keybindHelper = KeybindHelper(previewCoordinator: currentPreviewCoordinator)
            }

            appClosureObserver = WindowManipulationObservers(
                previewCoordinator: currentPreviewCoordinator,
                dismissPreviewsForSpaceChange: { [weak self, weak currentPreviewCoordinator] in
                    if let keybindHelper = self?.keybindHelper {
                        keybindHelper.dismissPreviews()
                    } else {
                        currentPreviewCoordinator?.windowSwitcherCoordinator.deactivateKeybindSession()
                        currentPreviewCoordinator?.hideWindow()
                    }
                }
            )
            if Defaults[.enableWindowGestures] {
                windowGestureController = WindowGestureController(previewCoordinator: currentPreviewCoordinator) { [weak self] event in
                    self?.keybindHelper?.handleGestureSwitcher(event)
                }
            }

            if Defaults[.showActiveAppIndicator] {
                activeAppIndicator = ActiveAppIndicatorCoordinator()
            }

            NSScreen.migrateScreenIdentifier(.lockedDockScreenIdentifier)
            NSScreen.migrateScreenIdentifier(.pinnedScreenIdentifier)
            if Defaults[.enableDockLocking] {
                dockLocker = DockLocker()
            }

            if updater.automaticallyChecksForUpdates {
                print("AppDelegate: Automatic updates enabled, checking in background.")
                updater.checkForUpdatesInBackground()
            }
        }

        // Cold-start: discover current and other-Space windows in one coordinated pass.
        let seeder = WindowSeeder()
        seeder.run()
        windowSeeder = seeder

        if Defaults[.reopenSettingsAfterRestart] {
            Defaults[.reopenSettingsAfterRestart] = false
            openSettingsWindow(nil)
        }

        DebugLogger.configure(enabled: Defaults[.debugMode])

        #if DEBUG
            debugHarness = DebugTestHarness(hooks: .init(
                simulateWake: { [weak self] in self?.handleSystemWake() },
                resetKeybind: { [weak self] in self?.keybindHelper?.reset() },
                switcherSessionActive: { [weak self] in self?.previewCoordinator?.windowSwitcherCoordinator.isKeybindSessionActive ?? false },
                previewVisible: { [weak self] in self?.previewCoordinator?.isVisible ?? false },
                previewWindowCount: { [weak self] in self?.previewCoordinator?.windowSwitcherCoordinator.windows.count ?? 0 }
            ))
        #endif
    }

    // Clear the onboarding skip's disableImagePreview only when permission was newly granted since last launch, so skip-then-grant users get previews back without overriding a deliberate "Always use compact mode" choice.
    private func reconcileImagePreviewWithPermission() {
        let hasPermission = WindowUtil.hasScreenRecordingPermission()
        let hadPermission = Defaults[.lastKnownScreenRecordingPermission]
        Defaults[.lastKnownScreenRecordingPermission] = hasPermission

        if hasPermission, !hadPermission, Defaults[.disableImagePreview] {
            Defaults[.disableImagePreview] = false
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if reopenEventIsFromSystemContextDaemon() {
            DebugLogger.log("Reopen", details: "Ignoring reopen event from system context daemon")
            return false
        }
        openSettingsWindow(nil)
        return false
    }

    @MainActor
    func showWindowSwitcherFromAppleScript(spacesFocused: Bool = false) async {
        await keybindHelper?.showWindowSwitcherFromAppleScript(spacesFocused: spacesFocused)
    }

    @MainActor
    func dismissPreviews() {
        if let keybindHelper {
            keybindHelper.dismissPreviews()
        } else {
            previewCoordinator?.windowSwitcherCoordinator.deactivateKeybindSession()
            previewCoordinator?.hideWindow()
        }
    }

    private func reopenEventIsFromSystemContextDaemon() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
              pid > 0
        else { return false }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return String(cString: buffer).hasSuffix("/intelligencecontextd")
    }

    func applicationWillTerminate(_ notification: Notification) {
        wakeRecoveryTask?.cancel()
        WindowUtil.saveWindowOrderFromCache()
        URLCache.shared.removeAllCachedResponses()
    }

    func setupMenuBar() {
        guard statusBarItem == nil else { return }

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusBarItem?.button else {
            print("Failed to create status bar button")
            return
        }

        if let icon = NSImage(named: .logo) {
            let iconSize = NSStatusBar.system.thickness * 0.9
            let resizedIcon = icon.resizedToFit(in: NSSize(width: iconSize, height: iconSize))
            resizedIcon.isTemplate = true
            button.image = resizedIcon
        } else {
            print("Failed to load icon")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: String(localized: "Open Settings"), action: #selector(openSettingsWindow(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let actionsItem = NSMenuItem(title: windowActionsMenu.menu.title, action: nil, keyEquivalent: "")
        actionsItem.submenu = windowActionsMenu.menu
        menu.addItem(actionsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(checkForUpdatesWrapper), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: String(localized: "Support DockDoor"), action: #selector(openDonationPage), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: String(localized: "Get DockDoor Pro…"), action: #selector(openProPage), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: String(localized: "Leave a Review"), action: #selector(openReviewPage), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Restart DockDoor"), action: #selector(restartAppWrapper), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: String(localized: "Quit DockDoor"), action: #selector(quitAppWrapper), keyEquivalent: "q"))
        menu.delegate = self
        statusBarMenu = menu
        updateMenuBarInteraction()
    }

    func removeMenuBar() {
        guard let statusBarItem else { return }
        removeMenuBarClickMonitor()
        statusBarMenu?.cancelTracking()
        NSStatusBar.system.removeStatusItem(statusBarItem)
        self.statusBarItem = nil
        statusBarMenu = nil
        isStatusBarMenuPresented = false
        statusBarMenuDismissalEventNumber = nil
        statusBarMenuDismissalTimestamp = nil
    }

    private func observeMenuBarInteractionSettings() {
        menuBarInteractionObserver = Defaults.observe(
            keys: .openWindowSwitcherFromMenuBarIcon,
            .menuBarIconWindowSwitcherClick
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.updateMenuBarInteraction()
            }
        }
    }

    private func updateMenuBarInteraction() {
        guard let statusBarItem,
              let statusBarMenu,
              let button = statusBarItem.button
        else { return }

        removeMenuBarClickMonitor()
        button.target = nil
        button.action = nil
        button.sendAction(on: .leftMouseUp)

        guard Defaults[.openWindowSwitcherFromMenuBarIcon] else {
            statusBarItem.menu = statusBarMenu
            installMenuBarClickMonitor(leftClickOpensWindowSwitcher: false, rightClickOpensWindowSwitcher: false)
            return
        }

        switch Defaults[.menuBarIconWindowSwitcherClick] {
        case .rightClick:
            statusBarItem.menu = statusBarMenu
            installMenuBarClickMonitor(leftClickOpensWindowSwitcher: false, rightClickOpensWindowSwitcher: true)
        case .leftClick:
            statusBarItem.menu = nil
            installMenuBarClickMonitor(leftClickOpensWindowSwitcher: true, rightClickOpensWindowSwitcher: false)
        }
    }

    func isWindowSwitcherMenuBarClick(at location: NSPoint) -> Bool {
        guard Defaults[.openWindowSwitcherFromMenuBarIcon],
              Defaults[.menuBarIconWindowSwitcherClick] == .leftClick,
              let button = statusBarItem?.button,
              let window = button.window, window.isVisible
        else { return false }

        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(location)
    }

    private func installMenuBarClickMonitor(
        leftClickOpensWindowSwitcher: Bool,
        rightClickOpensWindowSwitcher: Bool
    ) {
        let eventMask: NSEvent.EventTypeMask = leftClickOpensWindowSwitcher
            ? [.leftMouseDown, .rightMouseDown]
            : .rightMouseDown

        menuBarClickMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            guard let self,
                  let button = statusBarItem?.button,
                  event.window === button.window
            else { return event }

            let location = button.convert(event.locationInWindow, from: nil)
            guard button.bounds.contains(location) else { return event }

            let opensWindowSwitcher = event.type == .leftMouseDown
                ? leftClickOpensWindowSwitcher
                : rightClickOpensWindowSwitcher
            if opensWindowSwitcher {
                keybindHelper?.toggleWindowSwitcherFromMenuBar()
            } else if let statusBarMenu {
                let isDismissalEvent = event.eventNumber == statusBarMenuDismissalEventNumber ||
                    statusBarMenuDismissalTimestamp.map { abs(event.timestamp - $0) < 0.01 } == true
                statusBarMenuDismissalEventNumber = nil
                statusBarMenuDismissalTimestamp = nil
                if isDismissalEvent {
                    return nil
                }

                if isStatusBarMenuPresented {
                    statusBarMenu.cancelTracking()
                    return nil
                }

                isStatusBarMenuPresented = true
                button.highlight(true)
                statusBarMenu.popUp(
                    positioning: nil,
                    at: NSPoint(x: button.bounds.minX, y: button.bounds.minY),
                    in: button
                )
                button.highlight(false)
            }
            return nil
        }
    }

    private func removeMenuBarClickMonitor() {
        if let menuBarClickMonitor {
            NSEvent.removeMonitor(menuBarClickMonitor)
            self.menuBarClickMonitor = nil
        }
    }

    @objc private func quitAppWrapper() {
        quitApp()
    }

    @objc private func restartAppWrapper() {
        restartApp()
    }

    @objc private func checkForUpdatesWrapper() {
        updater.checkForUpdates()
    }

    @objc private func openDonationPage() {
        NSWorkspace.shared.open(Links.donate)
    }

    @objc private func openProPage() {
        DockDoorPro.open()
    }

    @objc private func openReviewPage() {
        NSWorkspace.shared.open(Links.review)
    }

    private var wakeRecoveryTask: Task<Void, Never>?
    private var wakeRecoveryGeneration: UInt = 0
    private var screenParametersDebounce: DispatchWorkItem?

    @objc private func handleScreenParametersChanged() {
        screenParametersDebounce?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.handleSystemWake(Notification(name: NSApplication.didChangeScreenParametersNotification))
        }
        screenParametersDebounce = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    @objc private func handleSystemWake(_ notification: Notification? = nil) {
        screenParametersDebounce?.cancel()
        screenParametersDebounce = nil
        wakeRecoveryTask?.cancel()
        wakeRecoveryGeneration &+= 1
        let generation = wakeRecoveryGeneration
        DebugLogger.log("Wake recovery", details: "scheduled source=\(notification?.name.rawValue ?? "manual") generation=\(generation)")

        wakeRecoveryTask = Task { @MainActor [weak self] in
            var delay: UInt64 = 1_000_000_000 // 1s
            var totalWaited: UInt64 = 0
            let maxWait: UInt64 = 15_000_000_000 // 15s

            while !Task.isCancelled, totalWaited < maxWait {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                totalWaited += delay

                let ready = await isAccessibilityReady()
                guard !Task.isCancelled else { return }
                if ready {
                    DebugLogger.log("Wake recovery", details: "AX canary passed after \(totalWaited / 1_000_000)ms")
                    break
                }

                DebugLogger.log("Wake recovery", details: "AX canary failed after \(totalWaited / 1_000_000)ms, backing off")
                delay = min(delay * 2, maxWait - totalWaited)
            }

            guard !Task.isCancelled, let self, wakeRecoveryGeneration == generation else { return }
            wakeRecoveryTask = nil
            recoverObserversAndTaps()
        }
    }

    func recoverObserversAndTaps() {
        wakeRecoveryGeneration &+= 1
        wakeRecoveryTask?.cancel()
        wakeRecoveryTask = nil
        dockObserver?.reset()
        keybindHelper?.recover()
        appClosureObserver?.reset()
        dockLocker?.reset()
        windowGestureController?.reset()
    }

    @objc func openSettingsWindow(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        settingsManager?.showSettings()
    }

    func closeSettingsWindow() {
        settingsManager?.close()
    }

    func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func restartApp() {
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-n", Bundle.main.bundlePath])
        quitApp()
    }

    private func handleFirstTimeLaunch() {
        let currentMouseLocation = CGEvent(source: nil)?.location ?? .zero
        let screen = NSScreen.screenFromQuartzPoint(currentMouseLocation)

        if !animationsEnabled {
            showOnboardingWindow(on: screen)
            return
        }

        let overlay = CinematicOverlay(screen: screen) { [weak self] in
            self?.cinematicOverlay = nil
            self?.showOnboardingWindow(on: screen)
        }
        cinematicOverlay = overlay
        overlay.orderFront(nil)
        overlay.fadeIn()
    }

    private func showOnboardingWindow(on screen: NSScreen) {
        let newWindow = SwiftUIWindow(
            styleMask: [.titled, .closable, .fullSizeContentView],
            content: {
                FirstTimeView()
            }
        )
        newWindow.isReleasedWhenClosed = false

        let customToolbar = NSToolbar()
        customToolbar.showsBaselineSeparator = false
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.toolbarStyle = .unified
        newWindow.styleMask.insert(.titled)
        newWindow.toolbar = customToolbar
        newWindow.isOpaque = false

        newWindow.standardWindowButton(.closeButton)?.isHidden = false
        newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newWindow.standardWindowButton(.zoomButton)?.isHidden = true

        newWindow.level = .floating

        let screenFrame = screen.visibleFrame
        let windowOrigin = NSPoint(
            x: screenFrame.midX - newWindow.frame.width / 2,
            y: screenFrame.midY - newWindow.frame.height / 2
        )

        newWindow.setFrameOrigin(windowOrigin)
        newWindow.isMovableByWindowBackground = true
        onboardingWindow = newWindow

        newWindow.alphaValue = 0
        newWindow.show()
        newWindow.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newWindow.animator().alphaValue = 1
        }
    }
}

extension AppDelegate: NSWindowDelegate, NSMenuDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == onboardingWindow {
            onboardingWindow = nil
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusBarMenu else { return }
        isStatusBarMenuPresented = true
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusBarMenu else { return }
        statusBarMenuDismissalEventNumber = NSApp.currentEvent?.eventNumber
        statusBarMenuDismissalTimestamp = NSApp.currentEvent?.timestamp
        DispatchQueue.main.async { [weak self] in
            self?.isStatusBarMenuPresented = false
        }
    }
}

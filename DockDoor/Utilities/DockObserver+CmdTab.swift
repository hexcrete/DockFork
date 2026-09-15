import ApplicationServices
import Cocoa
import Defaults

// AXObserver callback for Cmd+Tab switcher changes
func handleCmdTabSwitcherNotification(observer _: AXObserver, element _: AXUIElement, notificationName: CFString, context: UnsafeMutableRawPointer?) {
    DispatchQueue.main.async {
        DockObserver.activeInstance?.processCmdTabSwitcherEvent(notificationName)
    }
}

extension DockObserver {
    // MARK: - Cmd+Tab Switcher Monitoring

    func teardownCmdTabObserver() {
        cmdTabDiscoveryTask?.cancel()
        cmdTabDiscoveryTask = nil
        cmdTabSelectionRetryWorkItem?.cancel()
        cmdTabSelectionRetryWorkItem = nil
        cmdTabSelectionGeneration &+= 1
        if let observer = cmdTabObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        cmdTabObserver = nil
        stopCmdTabPolling()
        DockObserver.isCmdTabSwitcherActive = false
    }

    // MARK: - On-Demand Polling (Event-Driven)

    func startCmdTabPolling() {
        guard Defaults[.enableCmdTabEnhancements] else { return }
        guard cmdTabObserver == nil else { return }

        attemptCmdTabSubscription()

        if cmdTabObserver == nil {
            scheduleCmdTabPolling()
        }
    }

    private func scheduleCmdTabPolling() {
        guard Defaults[.enableCmdTabEnhancements], cmdTabObserver == nil, cmdTabPollingTimer == nil else { return }

        cmdTabPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            attemptCmdTabSubscription()

            if cmdTabObserver != nil {
                timer.invalidate()
                cmdTabPollingTimer = nil
            }
        }
    }

    func stopCmdTabPolling() {
        cmdTabPollingTimer?.invalidate()
        cmdTabPollingTimer = nil
    }

    private func attemptCmdTabSubscription() {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return
        }

        let dockAppPID = dockApp.processIdentifier
        let dockAppElement = AXUIElementCreateApplication(dockAppPID)

        guard let processSwitcherList = findCmdTabSwitcherElement(in: dockAppElement) else {
            return
        }

        stopCmdTabPolling()
        subscribeToProcessSwitcher(processSwitcherList: processSwitcherList, dockAppPID: dockAppPID)
        processCmdTabSwitcherChanged()
    }

    private func subscribeToProcessSwitcher(processSwitcherList: AXUIElement, dockAppPID: pid_t) {
        if cmdTabObserver != nil {
            teardownCmdTabObserver()
        }

        guard AXObserverCreate(dockAppPID, handleCmdTabSwitcherNotification, &cmdTabObserver) == .success,
              let cmdTabObserver
        else {
            return
        }

        do {
            try processSwitcherList.subscribeToNotification(cmdTabObserver, kAXSelectedChildrenChangedNotification as String) {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(cmdTabObserver), .commonModes)
            }
            try processSwitcherList.subscribeToNotification(cmdTabObserver, kAXUIElementDestroyedNotification as String)
            DockObserver.isCmdTabSwitcherActive = true
        } catch {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(cmdTabObserver), .commonModes)
            self.cmdTabObserver = nil
            DockObserver.isCmdTabSwitcherActive = false
            scheduleCmdTabPolling()
            DebugLogger.log("DockObserver+CmdTab", details: "Failed to subscribe to Cmd+Tab switcher: \(error)")
        }
    }

    func processCmdTabSwitcherEvent(_ notification: CFString) {
        guard Defaults[.enableCmdTabEnhancements] else { return }

        let notif = notification as String

        if notif == (kAXSelectedChildrenChangedNotification as String) {
            processCmdTabSwitcherChanged()
            return
        }

        if notif == (kAXUIElementDestroyedNotification as String) {
            teardownCmdTabObserver()
            return
        }
    }

    func processCmdTabSwitcherChanged() {
        cmdTabSelectionGeneration &+= 1
        let generation = cmdTabSelectionGeneration
        cmdTabDiscoveryTask?.cancel()
        cmdTabDiscoveryTask = nil
        cmdTabSelectionRetryWorkItem?.cancel()
        cmdTabSelectionRetryWorkItem = nil

        processCmdTabSwitcherChanged(generation: generation, retrySelectionLookup: true)
    }

    private func processCmdTabSwitcherChanged(generation: UInt, retrySelectionLookup: Bool) {
        guard generation == cmdTabSelectionGeneration else { return }
        guard Defaults[.enableCmdTabEnhancements] else { return }
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return
        }

        let dockAppElement = AXUIElementCreateApplication(dockApp.processIdentifier)

        guard let selectedItem = getSelectedCmdTabItem(dockElement: dockAppElement) else {
            if retrySelectionLookup {
                scheduleCmdTabSelectionRetry(generation: generation)
            } else if generation == cmdTabSelectionGeneration {
                previewCoordinator.hideWindow()
            }
            return
        }

        let appCandidates = cmdTabApplicationCandidates(
            resolvedApp: selectedItem.app,
            bundleIdentifier: selectedItem.bundleId ?? selectedItem.app?.bundleIdentifier,
            title: selectedItem.title
        )
        guard let resolvedApp = preferredCmdTabApplication(from: appCandidates) else {
            previewCoordinator.hideWindow()
            return
        }
        let appName = resolvedApp.localizedName ?? selectedItem.title ?? "Unknown"
        let bundleId = resolvedApp.bundleIdentifier ?? selectedItem.bundleId

        let cachedSource = appCandidates.flatMap {
            WindowUtil.readCachedWindows(for: $0.processIdentifier, sortedBy: .cmdTab)
        }
        let cachedWindows = WindowUtil.cmdTabPreviewWindows(
            from: WindowUtil.sortWindows(cachedSource, for: .cmdTab),
            app: resolvedApp
        )

        let elementPos = try? selectedItem.element.position()
        let bestScreen = if let elementPos { NSScreen.screenFromQuartzPoint(elementPos) } else { NSScreen.main! }
        let selectedElement = selectedItem.element

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard generation == cmdTabSelectionGeneration,
                  DockObserver.isCmdTabSwitcherActive,
                  isCurrentCmdTabSelection(selectedElement)
            else { return }

            guard let cachedWindows else {
                previewCoordinator.hideWindow()
                return
            }

            let initialIndex = Defaults[.cmdTabAutoSelectFirstWindow] ? 0 : nil
            previewCoordinator.showWindow(
                appName: appName,
                windows: cachedWindows,
                mouseLocation: DockObserver.getMousePosition(),
                mouseScreen: bestScreen,
                dockItemElement: selectedItem.element,
                overrideDelay: true,
                centeredHoverWindowState: .none,
                onWindowTap: { [weak self] in
                    self?.hideWindowAndResetLastApp()
                },
                bundleIdentifier: bundleId,
                bypassDockMouseValidation: true,
                dockPositionOverride: .cmdTab,
                initialIndex: initialIndex
            )
        }

        if !appCandidates.isEmpty {
            let displayedPID = cachedWindows?.first?.app.processIdentifier ?? resolvedApp.processIdentifier
            let screenOrigin = bestScreen.frame.origin

            cmdTabDiscoveryTask = Task.detached { [weak self] in
                var discoveredWindows: [WindowInfo] = []
                var completedDiscovery = false
                for app in appCandidates {
                    guard !Task.isCancelled else { return }
                    do {
                        let appWindows = try await WindowUtil.getActiveWindows(
                            of: app,
                            context: .cmdTab,
                            ignoreSingleWindowFilter: true
                        )
                        discoveredWindows.append(contentsOf: appWindows)
                        completedDiscovery = true
                    } catch {
                        DebugLogger.log("DockObserver+CmdTab", details: "Failed to fetch windows for \(app.localizedName ?? "Unknown"): \(error)")
                    }
                }
                guard completedDiscovery, !Task.isCancelled else { return }

                let freshWindows = WindowUtil.cmdTabPreviewWindows(
                    from: WindowUtil.sortWindows(discoveredWindows, for: .cmdTab),
                    app: resolvedApp
                )

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard generation == cmdTabSelectionGeneration,
                          DockObserver.isCmdTabSwitcherActive,
                          isCurrentCmdTabSelection(selectedElement)
                    else { return }
                    guard let screen = screenOrigin.screen() else { return }

                    let didMerge = previewCoordinator.mergeWindowsIfNeeded(
                        displayedPID,
                        windows: freshWindows ?? [],
                        dockPosition: .cmdTab,
                        bestGuessMonitor: screen
                    )
                    if let freshWindows, !didMerge {
                        let initialIndex = Defaults[.cmdTabAutoSelectFirstWindow] ? 0 : nil
                        previewCoordinator.showWindow(
                            appName: appName,
                            windows: freshWindows,
                            mouseLocation: DockObserver.getMousePosition(),
                            mouseScreen: screen,
                            dockItemElement: selectedElement,
                            overrideDelay: true,
                            centeredHoverWindowState: .none,
                            onWindowTap: { [weak self] in
                                self?.hideWindowAndResetLastApp()
                            },
                            bundleIdentifier: bundleId,
                            bypassDockMouseValidation: true,
                            dockPositionOverride: .cmdTab,
                            initialIndex: initialIndex
                        )
                    } else if didMerge, freshWindows == nil {
                        previewCoordinator.hideWindow()
                    }
                    if generation == cmdTabSelectionGeneration {
                        cmdTabDiscoveryTask = nil
                    }
                    DebugLogger.log("WindowRefresh", details: "Cmd+Tab final merge, PID: \(displayedPID), windows: \(freshWindows?.count ?? 0), merged: \(didMerge)")
                }
            }
        }
    }

    private func scheduleCmdTabSelectionRetry(generation: UInt) {
        cmdTabSelectionRetryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, generation == cmdTabSelectionGeneration else { return }
            cmdTabSelectionRetryWorkItem = nil
            processCmdTabSwitcherChanged(generation: generation, retrySelectionLookup: false)
        }
        cmdTabSelectionRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func isCurrentCmdTabSelection(_ expectedElement: AXUIElement) -> Bool {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return false
        }
        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        guard let selectedItem = getSelectedCmdTabItem(dockElement: dockElement) else { return false }
        return CFEqual(selectedItem.element, expectedElement)
    }

    func selectedCmdTabApplication() -> NSRunningApplication? {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }

        let dockAppElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        guard let selectedItem = getSelectedCmdTabItem(dockElement: dockAppElement) else {
            return nil
        }

        return preferredCmdTabApplication(from: cmdTabApplicationCandidates(
            resolvedApp: selectedItem.app,
            bundleIdentifier: selectedItem.bundleId ?? selectedItem.app?.bundleIdentifier,
            title: selectedItem.title
        ))
    }

    // MARK: - Cmd+Tab Session State

    /// Cached state tracking whether the Cmd+Tab switcher is currently active.
    /// Updated by the AXObserver when the switcher appears/disappears.
    static var isCmdTabSwitcherActive = false

    private func cmdTabApplicationCandidates(
        resolvedApp: NSRunningApplication?,
        bundleIdentifier: String?,
        title: String?
    ) -> [NSRunningApplication] {
        var candidates: [NSRunningApplication] = []

        if let resolvedApp, !resolvedApp.isTerminated {
            candidates.append(resolvedApp)
        }
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            candidates.append(contentsOf: NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier))
        } else if let title, !title.isEmpty {
            candidates.append(contentsOf: NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && $0.localizedName == title
            })
        }

        var seenPIDs = Set<pid_t>()
        return candidates.filter {
            !$0.isTerminated && $0.activationPolicy == .regular && seenPIDs.insert($0.processIdentifier).inserted
        }
    }

    private func preferredCmdTabApplication(from candidates: [NSRunningApplication]) -> NSRunningApplication? {
        candidates.first {
            !WindowUtil.readCachedWindows(for: $0.processIdentifier, sortedBy: .cmdTab).isEmpty
        } ?? candidates.first
    }

    private func getSelectedCmdTabItem(dockElement: AXUIElement) -> (element: AXUIElement, app: NSRunningApplication?, bundleId: String?, title: String?)? {
        guard let appSwitcherElement = findCmdTabSwitcherElement(in: dockElement) else {
            return nil
        }

        var selectedChildren: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appSwitcherElement, kAXSelectedChildrenAttribute as CFString, &selectedChildren)

        if result == .success,
           let selectedArray = selectedChildren as? [AXUIElement],
           let selectedElement = selectedArray.first
        {
            var resolvedApp: NSRunningApplication?
            var resolvedBundleId: String?
            var resolvedTitle: String?

            if let appURL = try? selectedElement.attribute(kAXURLAttribute as String, NSURL.self)?.absoluteURL,
               let bundle = Bundle(url: appURL),
               let bundleIdentifier = bundle.bundleIdentifier
            {
                resolvedBundleId = bundleIdentifier
                resolvedApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
            }

            if resolvedApp == nil {
                do {
                    if let title = try selectedElement.title(), !title.isEmpty {
                        resolvedTitle = title
                        let namedApps = NSWorkspace.shared.runningApplications.filter {
                            $0.activationPolicy == .regular && !($0.localizedName ?? "").isEmpty
                        }
                        if let app = namedApps.first(where: { $0.localizedName == title }) {
                            resolvedApp = app
                        } else {
                            let lowerTitle = title.lowercased()
                            if let app = namedApps.first(where: {
                                let appName = ($0.localizedName ?? "").lowercased()
                                return appName.contains(lowerTitle) || lowerTitle.contains(appName)
                            }) {
                                resolvedApp = app
                            }
                        }
                        if resolvedBundleId == nil { resolvedBundleId = resolvedApp?.bundleIdentifier }
                    }
                } catch {
                    // ignore
                }
            }

            return (element: selectedElement, app: resolvedApp, bundleId: resolvedBundleId, title: resolvedTitle)
        }

        return nil
    }

    private func findCmdTabSwitcherElement(in dockElement: AXUIElement) -> AXUIElement? {
        do {
            let children = try dockElement.children() ?? []

            for child in children {
                let subrole = try? child.subrole()
                if let subrole, subrole == "AXProcessSwitcherList" {
                    return child
                }

                if let found = findCmdTabSwitcherElement(in: child) {
                    return found
                }
            }
        } catch {
            // Element might not be accessible
        }

        return nil
    }
}

import ApplicationServices
import Cocoa
import Defaults
import ScreenCaptureKit

let filteredBundleIdentifiers: [String] = ["com.apple.notificationcenterui"] // filters desktop widgets

/// Context for fetching windows - determines which settings to use
enum WindowFetchContext {
    case dockPreview
    case cmdTab
}

protocol WindowPropertiesProviding {
    var windowID: CGWindowID { get }
    var frame: CGRect { get }
    var title: String? { get }
    var owningApplicationBundleIdentifier: String? { get }
    var owningApplicationProcessID: pid_t? { get }
    var isOnScreen: Bool { get }
    var windowLayer: Int { get }
}

extension SCWindow: WindowPropertiesProviding {
    var owningApplicationBundleIdentifier: String? { owningApplication?.bundleIdentifier }
    var owningApplicationProcessID: pid_t? { owningApplication?.processID }
}

enum WindowAction: String, Hashable, CaseIterable, Defaults.Serializable {
    static let inPlaceRefreshDelays: [UInt64] = [180_000_000, 420_000_000]
    static let deferredConfirmationPollDelays: [UInt64] = [180_000_000, 420_000_000, 900_000_000]
    static let fullscreenConfirmationDelay: UInt64 = 180_000_000
    static let reconciliationDelays: [UInt64] = [120_000_000, 450_000_000, 900_000_000]

    enum PostActionCategory: String, Hashable, CaseIterable {
        case movingAndResizing
        case hiding
        case unhiding
        case closing
        case newWindow

        var localizedName: String {
            switch self {
            case .movingAndResizing:
                String(localized: "Move/Resize", comment: "Post-action category")
            case .hiding:
                String(localized: "Hide/Minimize", comment: "Post-action category")
            case .unhiding:
                String(localized: "Unhide/Unminimize", comment: "Post-action category")
            case .closing:
                String(localized: "Close/Quit", comment: "Post-action category")
            case .newWindow:
                String(localized: "New Window", comment: "Post-action category")
            }
        }

        var keepPreviewsOpen: Bool {
            switch self {
            case .movingAndResizing:
                Defaults[.movingResizingPostActionBehavior]
            case .hiding:
                Defaults[.hidingPostActionBehavior]
            case .unhiding:
                Defaults[.unhidingPostActionBehavior]
            case .closing:
                Defaults[.closingPostActionBehavior]
            case .newWindow:
                Defaults[.newWindowPostActionBehavior]
            }
        }
    }

    // Existing actions
    case quit
    case close
    case minimize
    case toggleFullScreen
    case hide
    case openNewWindow
    case closeAllWindows
    case minimizeAllWindows
    case maximize

    // Window positioning actions
    case fillLeftHalf
    case fillRightHalf
    case fillTopHalf
    case fillBottomHalf
    case fillTopLeftQuarter
    case fillTopRightQuarter
    case fillBottomLeftQuarter
    case fillBottomRightQuarter
    case center

    // No action
    case none

    var localizedName: String {
        switch self {
        case .quit:
            String(localized: "Quit App", comment: "Window action")
        case .close:
            String(localized: "Close Window", comment: "Window action")
        case .minimize:
            String(localized: "Minimize", comment: "Window action")
        case .toggleFullScreen:
            String(localized: "Toggle Full Screen", comment: "Window action")
        case .hide:
            String(localized: "Hide App", comment: "Window action")
        case .openNewWindow:
            String(localized: "Open New Window", comment: "Window action")
        case .closeAllWindows:
            String(localized: "Close All Windows", comment: "Window action")
        case .minimizeAllWindows:
            String(localized: "Minimize All Windows", comment: "Window action")
        case .maximize:
            String(localized: "Maximize", comment: "Window action")
        case .fillLeftHalf:
            String(localized: "Fill Left Half", comment: "Window action")
        case .fillRightHalf:
            String(localized: "Fill Right Half", comment: "Window action")
        case .fillTopHalf:
            String(localized: "Fill Top Half", comment: "Window action")
        case .fillBottomHalf:
            String(localized: "Fill Bottom Half", comment: "Window action")
        case .fillTopLeftQuarter:
            String(localized: "Fill Top Left", comment: "Window action")
        case .fillTopRightQuarter:
            String(localized: "Fill Top Right", comment: "Window action")
        case .fillBottomLeftQuarter:
            String(localized: "Fill Bottom Left", comment: "Window action")
        case .fillBottomRightQuarter:
            String(localized: "Fill Bottom Right", comment: "Window action")
        case .center:
            String(localized: "Center Window", comment: "Window action")
        case .none:
            String(localized: "No Action", comment: "Window action")
        }
    }

    var iconName: String {
        switch self {
        case .quit: "xmark.circle.fill"
        case .close: "xmark.square"
        case .minimize: "minus.circle"
        case .toggleFullScreen: "arrow.up.left.and.arrow.down.right"
        case .hide: "eye.slash"
        case .openNewWindow: "plus.rectangle.on.rectangle"
        case .closeAllWindows: "xmark.square.fill"
        case .minimizeAllWindows: "minus.circle.fill"
        case .maximize: "arrow.up.backward.and.arrow.down.forward"
        case .fillLeftHalf: "rectangle.lefthalf.filled"
        case .fillRightHalf: "rectangle.righthalf.filled"
        case .fillTopHalf: "rectangle.tophalf.filled"
        case .fillBottomHalf: "rectangle.bottomhalf.filled"
        case .fillTopLeftQuarter: "rectangle.split.2x2.fill"
        case .fillTopRightQuarter: "rectangle.split.2x2.fill"
        case .fillBottomLeftQuarter: "rectangle.split.2x2.fill"
        case .fillBottomRightQuarter: "rectangle.split.2x2.fill"
        case .center: "rectangle.center.inset.filled"
        case .none: "nosign"
        }
    }

    /// Actions that can be assigned to trackpad gestures
    static var gestureActions: [WindowAction] {
        [.none, .close, .minimize, .maximize, .toggleFullScreen, .hide, .openNewWindow,
         .closeAllWindows, .minimizeAllWindows, .quit,
         .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
         .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter, .center]
    }

    func postActionCategory(for window: WindowInfo, preferredWindows: [WindowInfo]? = nil) -> PostActionCategory? {
        switch self {
        case .quit, .close, .closeAllWindows:
            return .closing
        case .openNewWindow:
            return .newWindow
        case .hide:
            return window.isHidden ? .unhiding : .hiding
        case .minimize:
            return window.isMinimized ? .unhiding : .hiding
        case .minimizeAllWindows:
            let pid = window.app.processIdentifier
            let preferredAppWindows = preferredWindows?.filter {
                $0.app.processIdentifier == pid && !$0.isWindowlessApp
            } ?? []
            let appWindows: [WindowInfo] = if !preferredAppWindows.isEmpty {
                preferredAppWindows
            } else {
                // Fallback to cache when the in-context list only has a windowless row.
                WindowUtil.readCachedWindows(for: pid).filter { !$0.isWindowlessApp }
            }
            guard !appWindows.isEmpty else { return .hiding }
            let nonFullscreenWindows = appWindows.filter { (try? $0.axElement.isFullscreen()) != true }
            if nonFullscreenWindows.isEmpty {
                return .unhiding
            }
            return nonFullscreenWindows.allSatisfy(\.isMinimized) ? .unhiding : .hiding
        case .maximize, .toggleFullScreen,
             .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center:
            return .movingAndResizing
        case .none:
            return nil
        }
    }

    func closePreviewsOnlyAfterSuccess(for window: WindowInfo, category: PostActionCategory?) -> Bool {
        switch self {
        case .openNewWindow, .toggleFullScreen,
             .maximize, .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center:
            true
        case .minimize:
            !window.isMinimized
        case .minimizeAllWindows:
            category == .hiding
        case .hide, .close, .quit, .closeAllWindows, .none:
            false
        }
    }

    func shouldForcePreviewCloseForFullscreenTransition(on window: WindowInfo, preferredWindows: [WindowInfo]? = nil) -> Bool {
        func shouldForceCloseForCrossSpaceWindow(_ candidate: WindowInfo, activeSpaceIDs: Set<Int>) -> Bool {
            let windowSpaces = Set(candidate.id.cgsSpaces().map { Int($0) })
            if !windowSpaces.isEmpty {
                return windowSpaces.isDisjoint(with: activeSpaceIDs)
            }
            if let cachedSpaceID = candidate.spaceID {
                return !activeSpaceIDs.contains(cachedSpaceID)
            }
            // Unknown Space membership: only keep-open when we can prove same-space.
            return true
        }

        switch self {
        case .toggleFullScreen:
            guard let isFullscreen = try? window.axElement.isFullscreen() else { return false }
            if !isFullscreen {
                return true
            }

            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.app.processIdentifier else {
                return false
            }
            guard let focusedWindow = try? window.appAxElement.focusedWindow(),
                  let focusedWindowID = try? focusedWindow.cgWindowId()
            else {
                return false
            }
            return focusedWindowID == window.id

        case .hide:
            // Unhiding can force a Space jump for fullscreen windows or windows on another Space.
            guard window.isHidden else { return false }
            let isFullscreen = (try? window.axElement.isFullscreen()) == true || window.isFullscreen == true
            if isFullscreen {
                return true
            }

            let activeSpaceIDs = currentActiveSpaceIDs()
            guard !activeSpaceIDs.isEmpty else {
                // If we cannot resolve the current Space set, prefer pre-close to avoid cross-space preview artifacts.
                return true
            }

            return shouldForceCloseForCrossSpaceWindow(window, activeSpaceIDs: activeSpaceIDs)

        case .minimize:
            // Unminimizing can jump Spaces when restoring a window located elsewhere.
            guard window.isMinimized else { return false }

            let activeSpaceIDs = currentActiveSpaceIDs()
            guard !activeSpaceIDs.isEmpty else {
                return true
            }

            return shouldForceCloseForCrossSpaceWindow(window, activeSpaceIDs: activeSpaceIDs)

        case .minimizeAllWindows:
            // Keep previews open for unminimize-all even when some windows may restore on another Space.
            // This avoids hard-closing the container in the common edge case of mixed-space minimized sets.
            return false

        case .quit, .close, .openNewWindow, .closeAllWindows,
             .maximize, .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center, .none:
            return false
        }
    }

    func shouldForcePreviewCloseAfterAction(
        predictedTransition: Bool,
        hiddenStateBeforeAction: Bool?,
        result: ActionResult
    ) -> Bool {
        guard predictedTransition else { return false }

        if self == .hide {
            guard hiddenStateBeforeAction == true,
                  case let .windowUpdated(updatedWindow) = result
            else { return false }
            return !updatedWindow.isHidden
        }

        if case .noChange = result { return false }
        return true
    }

    var shouldScheduleAppRefresh: Bool {
        switch self {
        case .openNewWindow, .close, .quit, .closeAllWindows,
             .minimize, .hide, .minimizeAllWindows,
             .maximize, .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center:
            true
        case .toggleFullScreen:
            true
        case .none:
            false
        }
    }

    var shouldScheduleDockReconciliation: Bool {
        switch self {
        case .openNewWindow, .close, .quit, .closeAllWindows, .toggleFullScreen:
            true
        case .minimize, .hide, .minimizeAllWindows, .maximize,
             .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center, .none:
            false
        }
    }

    var requiresDeferredSuccessWatcher: Bool {
        switch self {
        case .toggleFullScreen, .openNewWindow, .close, .quit, .closeAllWindows:
            true
        case .minimize, .hide, .minimizeAllWindows, .maximize,
             .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center, .none:
            false
        }
    }

    /// Result of performing a window action
    enum ActionResult {
        case dismissed
        case windowUpdated(WindowInfo)
        case windowRemoved
        case appWindowsRemoved(pid: pid_t)
        case noChange
    }

    /// Performs the action on the given window
    /// - Parameters:
    ///   - window: The window to perform the action on
    ///   - keepPreviewOnQuit: Whether to keep the preview open after quitting
    ///   - preferredWindows: Optional in-context windows for app-wide actions to avoid stale cache reads
    ///   - hiddenStateBeforeAction: Optional resolved app hidden state for consistent hide/unhide handling
    /// - Returns: The result indicating what happened
    func perform(
        on window: WindowInfo,
        keepPreviewOnQuit: Bool = false,
        preferredWindows: [WindowInfo]? = nil,
        hiddenStateBeforeAction: Bool? = nil
    ) -> ActionResult {
        switch self {
        case .quit:
            window.quit(force: NSEvent.modifierFlags.contains(.option))
            if keepPreviewOnQuit {
                return .noChange
            } else {
                return .dismissed
            }

        case .close:
            let pid = window.app.processIdentifier
            if window.isWindowlessApp {
                let closedCount = WindowUtil.closeAllWindows(for: window.app, preferredWindows: preferredWindows)
                if closedCount == 0, WindowUtil.shouldQuitAppOnWindowClose(processIdentifier: pid) {
                    window.quit(force: NSEvent.modifierFlags.contains(.option))
                    if keepPreviewOnQuit {
                        return .noChange
                    } else {
                        return .dismissed
                    }
                }
                return .noChange
            }

            if WindowUtil.shouldQuitAppOnWindowClose(processIdentifier: pid) {
                window.quit(force: NSEvent.modifierFlags.contains(.option))
                if keepPreviewOnQuit {
                    return .noChange
                } else {
                    return .dismissed
                }
            } else {
                _ = window.close()
                return .noChange
            }

        case .minimize:
            var updatedWindow = window
            if updatedWindow.toggleMinimize() != nil {
                return .windowUpdated(updatedWindow)
            }
            return .noChange

        case .toggleFullScreen:
            var updatedWindow = window
            if updatedWindow.toggleFullScreen() {
                return .dismissed
            }
            return .noChange

        case .hide:
            let currentHiddenState = hiddenStateBeforeAction ??
                ((try? window.appAxElement.attribute(kAXHiddenAttribute, Bool.self)) ?? window.isHidden)
            let attemptingHide = !currentHiddenState
            if attemptingHide,
               WindowUtil.hasOnlyFullscreenWindows(for: window.app, preferredWindows: preferredWindows)
            {
                return .noChange
            }
            var updatedWindow = window
            if updatedWindow.toggleHidden(from: currentHiddenState) != nil {
                return .windowUpdated(updatedWindow)
            }
            return .noChange

        case .openNewWindow:
            WindowUtil.openNewWindow(app: window.app)
            return .dismissed

        case .closeAllWindows:
            let closedCount = WindowUtil.closeAllWindows(for: window.app, preferredWindows: preferredWindows)
            return closedCount > 0 ? .dismissed : .noChange

        case .minimizeAllWindows:
            let changedCount = WindowUtil.minimizeAllWindows(for: window.app, preferredWindows: preferredWindows)
            return changedCount > 0 ? .dismissed : .noChange

        case .maximize:
            guard (try? window.axElement.isFullscreen()) != true else { return .noChange }
            window.zoom()
            return .dismissed

        case .fillLeftHalf:
            guard (try? window.axElement.isFullscreen()) != true else { return .noChange }
            window.fillLeftHalf()
            return .dismissed

        case .fillRightHalf:
            guard (try? window.axElement.isFullscreen()) != true else { return .noChange }
            window.fillRightHalf()
            return .dismissed

        case .fillTopHalf:
            guard (try? window.axElement.isFullscreen()) != true else { return .noChange }
            window.fillTopHalf()
            return .dismissed

        case .fillBottomHalf:
            guard (try? window.axElement.isFullscreen()) != true else { return .noChange }
            window.fillBottomHalf()
            return .dismissed

        case .fillTopLeftQuarter:
            guard (try? window.axElement.isFullscreen()) != true else { return .noChange }
            window.fillTopLeftQuarter()
            return .dismissed

        case .fillTopRightQuarter:
            guard (try? window.axElement.isFullscreen()) != true else { return .noChange }
            window.fillTopRightQuarter()
            return .dismissed

        case .fillBottomLeftQuarter:
            guard (try? window.axElement.isFullscreen()) != true else { return .noChange }
            window.fillBottomLeftQuarter()
            return .dismissed

        case .fillBottomRightQuarter:
            guard (try? window.axElement.isFullscreen()) != true else { return .noChange }
            window.fillBottomRightQuarter()
            return .dismissed

        case .center:
            guard (try? window.axElement.isFullscreen()) != true else { return .noChange }
            window.centerWindow()
            return .dismissed

        case .none:
            return .noChange
        }
    }
}

enum WindowUtil {
    private static let desktopSpaceWindowCacheManager = SpaceWindowCacheManager()
    private static let operationTimeout: UInt64 = 10_000_000_000

    /// Runs an async operation with a timeout, returning nil if it exceeds the limit
    private static func withTimeout<T>(_ operation: @escaping () async -> T) async -> T? {
        let result = await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: operationTimeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
        if result == nil {
            DebugLogger.log("WindowUtil", details: "Operation timed out after 10 seconds")
        }
        return result
    }

    /// Fetches SCShareableContent with built-in timeout protection
    static func getShareableContent(onScreenWindowsOnly: Bool) async -> SCShareableContent? {
        await withTimeout { try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: onScreenWindowsOnly) }.flatMap { $0 }
    }

    static func hasScreenRecordingPermission() -> Bool {
        PermissionsChecker.hasScreenRecordingPermission()
    }

    static func matchesAppFilters(bundleIdentifier: String?, appName: String, filters: [String]) -> Bool {
        guard !filters.isEmpty else { return false }

        if let bundleIdentifier, filters.contains(bundleIdentifier) {
            return true
        }

        return filters.contains(where: { $0.caseInsensitiveCompare(appName) == .orderedSame })
    }

    static func isAppFiltered(_ app: NSRunningApplication) -> Bool {
        matchesAppFilters(
            bundleIdentifier: app.bundleIdentifier,
            appName: app.localizedName ?? "",
            filters: Defaults[.appNameFilters]
        )
    }

    /// Returns window IDs that are cached with fresh images (within cache lifespan)
    static func freshCachedWindowIDs(for pid: pid_t, from cachedWindows: Set<WindowInfo>? = nil) -> Set<CGWindowID> {
        let cacheLifespan = Defaults[.screenCaptureCacheLifespan]
        let windows = cachedWindows ?? desktopSpaceWindowCacheManager.readCache(pid: pid)
        return Set(windows.compactMap { window -> CGWindowID? in
            guard window.image != nil,
                  Date().timeIntervalSince(window.imageCapturedTime) <= cacheLifespan
            else { return nil }
            return window.id
        })
    }

    // Track windows explicitly updated by bringWindowToFront to prevent observer duplication
    private static var timestampUpdates: [AXUIElement: Date] = [:]
    private static let updateTimestampLock = NSLock()
    private static let windowUpdateTimeWindow: TimeInterval = 1.5
    private static var programmaticResizeRefreshDelayMilliseconds: UInt64 = 180
    private static var axResizeRefreshDelayMilliseconds: UInt64 = 360
    private static var programmaticResizeRefreshDelayNanos: UInt64 { programmaticResizeRefreshDelayMilliseconds * 1_000_000 }
    private static var axResizeRefreshDelayNanos: UInt64 { axResizeRefreshDelayMilliseconds * 1_000_000 }
    private static let programmaticResizeRefreshLock = NSLock()
    private static let globalMinimizeReconciliationLock = NSLock()
    private struct PendingProgrammaticResizeRefresh {
        let token: UUID
        let task: Task<Void, Never>
    }

    private static var pendingProgrammaticResizeRefreshes: [String: PendingProgrammaticResizeRefresh] = [:]
    private static var pendingGlobalMinimizeReconciliation: Task<Void, Never>?

    private static let captureError = NSError(
        domain: "WindowCaptureError",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Error encountered during image capture"]
    )
}

// MARK: - Cache Management

extension WindowUtil {
    static func setResizeRefreshDebounceDelays(programmaticMilliseconds: UInt64, axMilliseconds: UInt64) {
        programmaticResizeRefreshDelayMilliseconds = programmaticMilliseconds
        axResizeRefreshDelayMilliseconds = axMilliseconds
    }

    /// Reads cached windows for an app without triggering any SCK/AX fetches.
    /// Returns immediately with whatever is in cache, sorted by the given context.
    static func readCachedWindows(for pid: pid_t, sortedBy context: WindowFetchContext = .dockPreview) -> [WindowInfo] {
        let cached = desktopSpaceWindowCacheManager.readCache(pid: pid)
        return sortWindows(cached, for: context)
    }

    static func saveWindowOrderFromCache() {
        let allWindows = desktopSpaceWindowCacheManager.getAllWindows()
        WindowOrderPersistence.saveOrder(from: allWindows)
    }

    static func clearWindowCache(for app: NSRunningApplication) {
        desktopSpaceWindowCacheManager.writeCache(pid: app.processIdentifier, windowSet: [])
    }

    static func updateWindowCache(for app: NSRunningApplication, update: @escaping (inout Set<WindowInfo>) -> Void) {
        desktopSpaceWindowCacheManager.updateCache(pid: app.processIdentifier, update: update)
    }

    static func updateWindowDateTime(element: AXUIElement, app: NSRunningApplication) {
        updateTimestampLock.lock()
        defer { updateTimestampLock.unlock() }

        // Check if this window was recently updated
        let now = Date()
        if let lastUpdate = timestampUpdates[element],
           now.timeIntervalSince(lastUpdate) < windowUpdateTimeWindow
        {
            // Clean up expired timestamp entries
            cleanupExpiredUpdates(currentTime: now)
            return // Skip update
        }

        desktopSpaceWindowCacheManager.updateCache(pid: app.processIdentifier) { windowSet in
            if let index = windowSet.firstIndex(where: { $0.axElement == element }) {
                var updatedWindow = windowSet[index]
                updatedWindow.lastAccessedTime = now
                windowSet.remove(at: index)
                windowSet.insert(updatedWindow)
            }
        }

        timestampUpdates[element] = now
    }

    /// Updates window timestamp optimistically and records breadcrumb for observer deduplication
    static func updateTimestampOptimistically(for windowInfo: WindowInfo) {
        let now = Date()
        desktopSpaceWindowCacheManager.updateCache(pid: windowInfo.app.processIdentifier) { windowSet in
            if let index = windowSet.firstIndex(where: { $0.axElement == windowInfo.axElement }) {
                var updatedWindow = windowSet[index]
                updatedWindow.lastAccessedTime = now
                windowSet.remove(at: index)
                windowSet.insert(updatedWindow)
            }
        }
    }

    /// Removes expired entries from timestamp tracking (must be called with lock held)
    static func cleanupExpiredUpdates(currentTime: Date) {
        timestampUpdates = timestampUpdates.filter { _, date in
            currentTime.timeIntervalSince(date) < windowUpdateTimeWindow
        }
    }

    static func updateCachedWindowState(
        _ windowInfo: WindowInfo,
        isMinimized: Bool? = nil,
        isHidden: Bool? = nil,
        isFullscreen: Bool? = nil,
        spaceID: Int?? = nil,
        screenIdentifier: String?? = nil
    ) {
        desktopSpaceWindowCacheManager.updateCache(pid: windowInfo.app.processIdentifier) { windowSet in
            if let existingIndex = windowSet.firstIndex(where: {
                $0.id == windowInfo.id &&
                    $0.app.processIdentifier == windowInfo.app.processIdentifier
            }) {
                var updatedWindow = windowSet[existingIndex]
                if let isMinimized {
                    updatedWindow.isMinimized = isMinimized
                }
                if let isHidden {
                    updatedWindow.isHidden = isHidden
                }
                if let isFullscreen {
                    updatedWindow.isFullscreen = isFullscreen
                }
                if let spaceID {
                    updatedWindow.spaceID = spaceID
                }
                if let screenIdentifier {
                    updatedWindow.screenIdentifier = screenIdentifier
                }
                windowSet.remove(at: existingIndex)
                windowSet.insert(updatedWindow)
            }
        }
    }

    private static func scheduleForcedPreviewRecapture(
        pid: pid_t,
        windowID: CGWindowID,
        fallbackWindowInfo: WindowInfo? = nil,
        targetScreenIdentifier: String? = nil,
        delayNanos: UInt64
    ) {
        let refreshKey = "\(pid)-\(windowID)"

        programmaticResizeRefreshLock.lock()
        pendingProgrammaticResizeRefreshes[refreshKey]?.task.cancel()
        let token = UUID()
        let refreshTask = Task(priority: .utility) {
            func forceCaptureAndCacheUpdate() async {
                guard !Task.isCancelled else { return }
                let cachedWindowInfo = desktopSpaceWindowCacheManager.readCache(pid: pid).first(where: { $0.id == windowID })
                guard var refreshedWindowInfo = cachedWindowInfo ?? fallbackWindowInfo else {
                    return
                }

                guard let image = try? await captureWindowImage(
                    windowID: windowID,
                    pid: pid,
                    windowTitle: refreshedWindowInfo.windowName,
                    forceRefresh: true
                ) else {
                    return
                }

                refreshedWindowInfo.image = image
                refreshedWindowInfo.imageCapturedTime = Date()
                refreshedWindowInfo.spaceID = windowID.cgsSpaces().first.map { Int($0) } ?? refreshedWindowInfo.spaceID
                if let targetScreenIdentifier {
                    refreshedWindowInfo.screenIdentifier = targetScreenIdentifier
                } else if let pos = try? refreshedWindowInfo.axElement.position() {
                    refreshedWindowInfo.screenIdentifier = screenIdentifier(forWindowAt: pos)
                }
                updateDesktopSpaceWindowCache(with: refreshedWindowInfo)
            }

            defer {
                programmaticResizeRefreshLock.lock()
                if pendingProgrammaticResizeRefreshes[refreshKey]?.token == token {
                    pendingProgrammaticResizeRefreshes.removeValue(forKey: refreshKey)
                }
                programmaticResizeRefreshLock.unlock()
            }

            do {
                try await Task.sleep(nanoseconds: delayNanos)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await forceCaptureAndCacheUpdate()
        }
        pendingProgrammaticResizeRefreshes[refreshKey] = PendingProgrammaticResizeRefresh(token: token, task: refreshTask)
        programmaticResizeRefreshLock.unlock()
    }

    static func refreshCachedPreviewAfterProgrammaticResize(_ windowInfo: WindowInfo, targetScreenIdentifier: String?) {
        let newSpaceID = windowInfo.id.cgsSpaces().first.map { Int($0) } ?? windowInfo.spaceID

        // Apply geometry metadata immediately so filtering and ordering stay accurate.
        updateCachedWindowState(windowInfo, spaceID: newSpaceID, screenIdentifier: targetScreenIdentifier)

        scheduleForcedPreviewRecapture(
            pid: windowInfo.app.processIdentifier,
            windowID: windowInfo.id,
            fallbackWindowInfo: windowInfo,
            targetScreenIdentifier: targetScreenIdentifier,
            delayNanos: programmaticResizeRefreshDelayNanos
        )
    }

    static func refreshCachedPreviewAfterResizeNotification(pid: pid_t, windowID: CGWindowID) {
        if let cachedWindowInfo = desktopSpaceWindowCacheManager.readCache(pid: pid).first(where: { $0.id == windowID }),
           let isFullscreen = try? cachedWindowInfo.axElement.isFullscreen(),
           isFullscreen
        {
            return
        }

        scheduleForcedPreviewRecapture(
            pid: pid,
            windowID: windowID,
            delayNanos: axResizeRefreshDelayNanos
        )
    }
}

// MARK: - Window Capture

extension WindowUtil {
    static func captureWindowImage(window: SCWindow, forceRefresh: Bool = false) async throws -> CGImage {
        guard let pid = window.owningApplication?.processID else {
            throw captureError
        }

        return try await captureWindowImage(
            windowID: window.windowID,
            pid: pid,
            windowTitle: window.title,
            forceRefresh: forceRefresh
        )
    }

    static func captureWindowImage(windowID: CGWindowID, pid: pid_t, windowTitle: String? = nil, forceRefresh: Bool = false) async throws -> CGImage {
        // CGSHWCaptureWindowList requires screen recording permission
        guard hasScreenRecordingPermission() else {
            throw captureError
        }

        // Check cache first if not forcing refresh
        if !forceRefresh {
            if let cachedWindow = desktopSpaceWindowCacheManager.readCache(pid: pid)
                .first(where: { $0.id == windowID && (windowTitle == nil || $0.windowName == windowTitle) }),
                let cachedImage = cachedWindow.image
            {
                let cacheLifespan = Defaults[.screenCaptureCacheLifespan]
                if Date().timeIntervalSince(cachedWindow.imageCapturedTime) <= cacheLifespan {
                    return cachedImage
                }
            }
        }

        var cgImage: CGImage
        let connectionID = CGSMainConnectionID()
        var windowIDUInt32 = UInt32(windowID)
        let qualityOption: CGSWindowCaptureOptions = (Defaults[.windowImageCaptureQuality] == .best) ? .bestResolution : .nominalResolution
        guard let capturedWindows = CGSHWCaptureWindowList(
            connectionID,
            &windowIDUInt32,
            1,
            [.ignoreGlobalClipShape, qualityOption]
        ) as? [CGImage],
            let capturedImage = capturedWindows.first
        else {
            throw captureError
        }
        cgImage = capturedImage

        // Only scale down if previewScale is greater than 1
        let previewScale = Int(Defaults[.windowPreviewImageScale])
        if previewScale > 1 {
            let newWidth = Int(cgImage.width) / previewScale
            let newHeight = Int(cgImage.height) / previewScale
            let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = cgImage.bitmapInfo
            guard let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: cgImage.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                throw captureError
            }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
            if let resizedImage = context.makeImage() {
                cgImage = resizedImage
            }
        }

        return cgImage
    }

    static func isValidElement(_ element: AXUIElement) -> Bool {
        DebugLogger.measureSlow("isValidElement", thresholdMs: 50) {
            // Fast path: check geometry
            do {
                let position = try element.position()
                let size = try element.size()
                if position != nil, size != nil {
                    return true
                }
            } catch AxError.runtimeError {
                return false
            } catch {
                // Geometry check failed, fall through to AX windows list validation
            }

            // Slow path: enumerate windows
            do {
                if let pid = try element.pid() {
                    let appElement = AXUIElementCreateApplication(pid)
                    if let windows = try? appElement.windows() {
                        if let elementWindowId = try? element.cgWindowId() {
                            for window in windows {
                                if let windowId = try? window.cgWindowId(), windowId == elementWindowId {
                                    return true
                                }
                            }
                        }
                        for window in windows {
                            if CFEqual(element, window) {
                                return true
                            }
                        }
                    }
                }
            } catch {
                // Both checks failed
            }

            return false
        }
    }

    static func findWindow(matchingWindow window: SCWindow, in axWindows: [AXUIElement]) -> AXUIElement? {
        if let matchedWindow = axWindows.first(where: { axWindow in
            (try? axWindow.cgWindowId()) == window.windowID
        }) {
            return matchedWindow
        }

        // Fallback metohd
        for axWindow in axWindows {
            if let windowTitle = window.title, let axTitle = try? axWindow.title(), isFuzzyMatch(windowTitle: windowTitle, axTitleString: axTitle) {
                return axWindow
            }

            if let axPosition = try? axWindow.position(), let axSize = try? axWindow.size(), axPosition != .zero, axSize != .zero {
                let positionThreshold: CGFloat = 10
                let sizeThreshold: CGFloat = 10

                let positionMatch = abs(axPosition.x - window.frame.origin.x) <= positionThreshold &&
                    abs(axPosition.y - window.frame.origin.y) <= positionThreshold

                let sizeMatch = abs(axSize.width - window.frame.size.width) <= sizeThreshold &&
                    abs(axSize.height - window.frame.size.height) <= sizeThreshold

                if positionMatch, sizeMatch {
                    return axWindow
                }
            }
        }

        return nil
    }

    static func isFuzzyMatch(windowTitle: String, axTitleString: String) -> Bool {
        let axTitleWords = axTitleString.lowercased().split(separator: " ")
        let windowTitleWords = windowTitle.lowercased().split(separator: " ")

        let matchingWords = axTitleWords.filter { windowTitleWords.contains($0) }
        let matchPercentage = Double(matchingWords.count) / Double(windowTitleWords.count)

        return matchPercentage >= 0.90 || matchPercentage.isNaN || axTitleString.lowercased().contains(windowTitle.lowercased())
    }

    static func findRunningApplicationByName(named applicationName: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.localizedName == applicationName }
    }
}

// MARK: - Window Discovery

extension WindowUtil {
    static func windowlessEntryIfEligible(for app: NSRunningApplication, existingWindows: [WindowInfo]) -> WindowInfo? {
        let pidsWithWindows = Set(existingWindows.map(\.app.processIdentifier))
        let ownBundleId = Bundle.main.bundleIdentifier

        guard app.activationPolicy == .regular,
              !pidsWithWindows.contains(app.processIdentifier),
              !filteredBundleIdentifiers.contains(app.bundleIdentifier ?? ""),
              !isAppFiltered(app),
              app.bundleIdentifier != ownBundleId
        else {
            return nil
        }

        return WindowInfo.windowlessEntry(for: app)
    }

    static func getAllWindowsOfAllApps() -> [WindowInfo] {
        let windows = desktopSpaceWindowCacheManager.getAllWindows()
        var filteredWindows = !Defaults[.includeHiddenWindowsInSwitcher]
            ? windows.filter { !$0.isEffectivelyHiddenForUI && !$0.isMinimized }
            : windows

        // Filter by frontmost app if enabled
        if Defaults[.limitSwitcherToFrontmostApp] {
            filteredWindows = getWindowsForFrontmostApp(from: filteredWindows)
        }

        return sortWindowsForSwitcher(filteredWindows)
    }

    static func getWindowsForFrontmostApp(from windows: [WindowInfo]) -> [WindowInfo] {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return windows
        }

        return windows.filter { windowInfo in
            windowInfo.app.processIdentifier == frontmostApp.processIdentifier
        }
    }

    static func getWindowlessRunningApps(existingWindows: [WindowInfo]) -> [WindowInfo] {
        NSWorkspace.shared.runningApplications
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            .compactMap { windowlessEntryIfEligible(for: $0, existingWindows: existingWindows) }
    }

    static func getFocusedWindowForFrontmostApp() -> WindowInfo? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        let focusedWindow = (try? appElement.focusedWindow()) ?? nil
        let focusedWindowId = focusedWindow.flatMap { try? $0.cgWindowId() }

        let cachedWindows = readCachedWindows(for: frontmostApp.processIdentifier)
        if let focusedWindowId,
           let cachedMatch = cachedWindows.first(where: { $0.id == focusedWindowId })
        {
            return cachedMatch
        }

        let allWindows = getAllWindowsOfAllApps()
        if let focusedWindowId,
           let anyMatch = allWindows.first(where: { $0.id == focusedWindowId })
        {
            return anyMatch
        }

        return getWindowsForFrontmostApp(from: allWindows)
            .sorted { $0.lastAccessedTime > $1.lastAccessedTime }
            .first
    }

    /// Returns whether a single window belongs to one of the given active Spaces.
    static func windowBelongsToActiveSpace(_ windowInfo: WindowInfo, activeSpaceIDs: Set<Int>) -> Bool {
        let windowSpaces = Set(windowInfo.id.cgsSpaces().map { Int($0) })

        if !windowSpaces.isEmpty {
            return !windowSpaces.isDisjoint(with: activeSpaceIDs)
        }

        if let spaceID = windowInfo.spaceID {
            return activeSpaceIDs.contains(spaceID)
        }

        return windowInfo.isMinimized || windowInfo.isEffectivelyHiddenForUI
    }

    /// Filters windows to only include those in the current Space.
    static func filterWindowsByCurrentSpace(_ windows: [WindowInfo]) -> [WindowInfo] {
        let activeSpaceIDs = currentActiveSpaceIDs()
        return windows.filter { windowBelongsToActiveSpace($0, activeSpaceIDs: activeSpaceIDs) }
    }

    static func screenIdentifier(forWindowAt cgPosition: CGPoint) -> String? {
        NSScreen.screenFromQuartzPoint(cgPosition).uniqueIdentifier()
    }

    static func windowBelongsToScreen(_ windowInfo: WindowInfo, screenIdentifier: String) -> Bool {
        if let winScreen = windowInfo.screenIdentifier {
            return winScreen == screenIdentifier
        }
        return windowInfo.isMinimized || windowInfo.isEffectivelyHiddenForUI
    }

    static func filterWindowsByCurrentMonitor(_ windows: [WindowInfo], mouseLocation: CGPoint? = nil) -> [WindowInfo] {
        let mouse = mouseLocation ?? CGEvent(source: nil)?.location ?? .zero
        let currentScreen = NSScreen.screenFromQuartzPoint(mouse)
        let id = currentScreen.uniqueIdentifier()
        return windows.filter { windowBelongsToScreen($0, screenIdentifier: id) }
    }

    static func getActiveWindows(of app: NSRunningApplication, context: WindowFetchContext = .dockPreview, ignoreSingleWindowFilter: Bool = false) async throws -> [WindowInfo] {
        if isAppFiltered(app) {
            purgeAppCache(with: app.processIdentifier)
            return []
        }

        var sckWindowIDs = Set<CGWindowID>()

        // Skip SCK if user has disabled image previews (compact mode only) or screen recording permission not granted
        if !Defaults[.disableImagePreview], hasScreenRecordingPermission() {
            if let content = await getShareableContent(onScreenWindowsOnly: true) {
                // Build set of SCK window IDs
                let appWindows = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier }
                sckWindowIDs = Set(appWindows.map(\.windowID))

                // Pre-compute fresh cached IDs to avoid repeated cache reads
                let freshCachedIDs = freshCachedWindowIDs(for: app.processIdentifier)

                // Process SCK windows with limited concurrency
                await LimitedConcurrency.forEachNonThrowing(appWindows, maxConcurrent: 4, timeout: 10) { window in
                    try await captureAndCacheWindowInfo(window: window, app: app, skipWindowIDs: freshCachedIDs)
                }
            }
        }

        // Discover windows via AX (minimized, hidden, other spaces, SCK-missed, or all when compact mode)
        await discoverNonSCKWindowsViaAX(app: app, sckWindowIDs: sckWindowIDs)

        // Purify cache and return
        if let finalWindows = await WindowUtil.purifyAppCache(with: app.processIdentifier, removeAll: false) {
            guard ignoreSingleWindowFilter || !Defaults[.ignoreAppsWithSingleWindow] || finalWindows.count > 1 else { return [] }
            return sortWindows(finalWindows, for: context)
        }

        return []
    }

    private static func discoverNonSCKWindowsViaAX(app: NSRunningApplication, sckWindowIDs: Set<CGWindowID>) async {
        _ = await discoverWindowsViaAX(app: app, excludeWindowIDs: sckWindowIDs)
    }

    static func discoverWindowsViaAX(
        app: NSRunningApplication,
        excludeWindowIDs: Set<CGWindowID> = []
    ) async -> Int {
        let pid = app.processIdentifier

        guard let bundleId = app.bundleIdentifier, !filteredBundleIdentifiers.contains(bundleId) else {
            purgeAppCache(with: pid)
            return 0
        }

        if isAppFiltered(app) {
            purgeAppCache(with: pid)
            return 0
        }

        let appAX = AXUIElementCreateApplication(pid)
        let axWindows = AXUIElement.allWindows(pid, appElement: appAX)
        guard !axWindows.isEmpty else { return 0 }

        // Read cache once and compute sets to skip redundant processing
        let cachedWindows = desktopSpaceWindowCacheManager.readCache(pid: pid)
        let allCachedIDs = Set(cachedWindows.map(\.id))
        let freshCachedIDs = freshCachedWindowIDs(for: pid, from: cachedWindows)

        // Process AX windows with limited concurrency
        await LimitedConcurrency.forEachNonThrowing(axWindows, maxConcurrent: 4, timeout: 10) { axWin in
            try await captureAndCacheAXWindowInfo(
                axWindow: axWin,
                appAxElement: appAX,
                app: app,
                excludeWindowIDs: excludeWindowIDs,
                skipWindowIDs: freshCachedIDs,
                existingCachedIDs: allCachedIDs
            )
        }

        return axWindows.count
    }

    static func updateNewWindowsForApp(_ app: NSRunningApplication) async {
        if hasScreenRecordingPermission() {
            if let content = await getShareableContent(onScreenWindowsOnly: false) {
                let appWindows = content.windows.filter { window in
                    guard let scApp = window.owningApplication else { return false }
                    return scApp.processID == app.processIdentifier
                }

                // Pre-compute fresh cached IDs to avoid repeated cache reads
                let freshCachedIDs = freshCachedWindowIDs(for: app.processIdentifier)

                await LimitedConcurrency.forEachNonThrowing(appWindows, maxConcurrent: 4, timeout: 10) { window in
                    try await captureAndCacheWindowInfo(window: window, app: app, skipWindowIDs: freshCachedIDs)
                }
            }
        }

        // AX fallback
        await discoverNewWindowsViaAXFallback(app: app)
        await refreshAXFallbackWindowImages(for: app.processIdentifier)
    }

    static func removeNoninteractiveUntitledDialogs(
        for app: NSRunningApplication,
        candidateWindowIDs: Set<CGWindowID>
    ) {
        guard !candidateWindowIDs.isEmpty else { return }

        let pid = app.processIdentifier
        let candidates = desktopSpaceWindowCacheManager.readCache(pid: pid).filter {
            candidateWindowIDs.contains($0.id) && $0.scWindow == nil
        }

        for window in candidates where isNoninteractiveUntitledDialog(window.axElement) {
            desktopSpaceWindowCacheManager.removeFromCache(pid: pid, windowId: window.id)
        }
    }

    // MARK: - AX Fallback Discovery

    /// Discovers and caches windows via AX + CGS when SCK misses them (e.g., certain Adobe apps)
    private static func discoverNewWindowsViaAXFallback(app: NSRunningApplication) async {
        _ = await discoverWindowsViaAX(app: app)
    }

    static func updateAllWindowsInCurrentSpace() async {
        var processedPIDs = Set<pid_t>()

        if hasScreenRecordingPermission() {
            if let content = await getShareableContent(onScreenWindowsOnly: false) {
                let windowAppPairs: [(window: SCWindow, app: NSRunningApplication)] = content.windows.compactMap { window in
                    guard let scApp = window.owningApplication,
                          !filteredBundleIdentifiers.contains(scApp.bundleIdentifier),
                          let nsApp = NSRunningApplication(processIdentifier: scApp.processID)
                    else { return nil }
                    return (window, nsApp)
                }

                for pair in windowAppPairs {
                    processedPIDs.insert(pair.app.processIdentifier)
                }

                // Pre-compute fresh cached IDs per app to avoid repeated cache reads
                let freshCachedIDsByPID: [pid_t: Set<CGWindowID>] = {
                    var result: [pid_t: Set<CGWindowID>] = [:]
                    for pid in processedPIDs {
                        result[pid] = freshCachedWindowIDs(for: pid)
                    }
                    return result
                }()

                await LimitedConcurrency.forEachNonThrowing(windowAppPairs, maxConcurrent: 4, timeout: 10) { pair in
                    let skipIDs = freshCachedIDsByPID[pair.app.processIdentifier] ?? []
                    try await captureAndCacheWindowInfo(window: pair.window, app: pair.app, skipWindowIDs: skipIDs)
                }
            }
        }

        // AX fallback
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
                !filteredBundleIdentifiers.contains($0.bundleIdentifier ?? "") &&
                !isAppFiltered($0)
        }

        for app in runningApps {
            let pid = app.processIdentifier
            await discoverNewWindowsViaAXFallback(app: app)
            processedPIDs.insert(pid)
        }

        // Purify cache and refresh images
        for pid in processedPIDs {
            _ = await purifyAppCache(with: pid, removeAll: false)
            await refreshAXFallbackWindowImages(for: pid)
        }
    }

    /// Refresh images for windows discovered via AX fallback (no SCWindow available)
    private static func refreshAXFallbackWindowImages(for pid: pid_t) async {
        let windows = desktopSpaceWindowCacheManager.readCache(pid: pid)
        guard !windows.isEmpty else { return }

        // Pre-compute fresh cached IDs to skip - use already-fetched windows
        let freshCachedIDs = freshCachedWindowIDs(for: pid, from: windows)

        // Filter to AX-only windows with valid elements, removing invalid ones from cache
        let axOnlyWindows = windows.filter { $0.scWindow == nil }
        var validWindows: [WindowInfo] = []
        for window in axOnlyWindows {
            // Skip windows with fresh cache
            if freshCachedIDs.contains(window.id) { continue }
            if !isValidElement(window.axElement) {
                desktopSpaceWindowCacheManager.removeFromCache(pid: pid, windowId: window.id)
            } else {
                validWindows.append(window)
            }
        }

        // Process valid windows with limited concurrency
        await LimitedConcurrency.forEachNonThrowing(validWindows, maxConcurrent: 4, timeout: 10) { window in
            let image = try await captureWindowImage(windowID: window.id, pid: pid, windowTitle: window.windowName, forceRefresh: true)
            var updated = window
            updated.image = image
            updated.spaceID = window.id.cgsSpaces().first.map { Int($0) } ?? updated.spaceID
            updateDesktopSpaceWindowCache(with: updated)
        }
    }

    static func captureAndCacheWindowInfo(window: SCWindow, app: NSRunningApplication, skipWindowIDs: Set<CGWindowID> = []) async throws {
        let windowID = window.windowID
        let pid = app.processIdentifier

        // Fast path: skip if pre-computed by caller as fresh cached
        if skipWindowIDs.contains(windowID) { return }

        guard window.owningApplication != nil,
              window.isOnScreen,
              window.windowLayer == 0,
              Defaults[.disableMinWindowSizeFilter] || (window.frame.size.width >= AXMinWindowSize.width && window.frame.size.height >= AXMinWindowSize.height)
        else { return }

        guard let bundleId = app.bundleIdentifier else {
            purgeAppCache(with: pid)
            return
        }

        if filteredBundleIdentifiers.contains(bundleId) {
            purgeAppCache(with: pid)
            return
        }

        if isAppFiltered(app) {
            purgeAppCache(with: pid)
            return
        }

        if let windowTitle = window.title {
            let windowTitleFilters = Defaults[.windowTitleFilters]
            if !windowTitleFilters.isEmpty {
                for filter in windowTitleFilters {
                    if windowTitle.lowercased().contains(filter.lowercased()) {
                        removeWindowFromDesktopSpaceCache(with: windowID, in: pid)
                        return
                    }
                }
            }
        }

        desktopSpaceWindowCacheManager.updateCache(pid: pid) { windowSet in
            windowSet = windowSet.filter { cachedWindow in
                if let cachedTitle = cachedWindow.windowName {
                    for filter in Defaults[.windowTitleFilters] {
                        if cachedTitle.lowercased().contains(filter.lowercased()) {
                            return false
                        }
                    }
                }
                return true
            }
        }

        let appElement = AXUIElementCreateApplication(pid)

        guard let axWindows = try? appElement.windows(), !axWindows.isEmpty else {
            return
        }

        guard let windowRef = findWindow(matchingWindow: window, in: axWindows) else {
            return
        }

        let closeButton = try? windowRef.closeButton()
        let minimizeButton = try? windowRef.minimizeButton()
        let minimizedState = (try? windowRef.isMinimized()) ?? false
        let hiddenState = app.isHidden
        let fullscreenState = try? windowRef.isFullscreen()
        let shouldWindowBeCaptured = (closeButton != nil) || (minimizeButton != nil)

        if shouldWindowBeCaptured {
            let persistedData = WindowOrderPersistence.getPersistedTimestamp(
                bundleIdentifier: bundleId,
                windowTitle: window.title
            )
            let lastAccessedTime = persistedData?.lastAccessedTime ?? Date.now
            let creationTime = persistedData?.creationTime

            var windowInfo = WindowInfo(
                windowProvider: window,
                app: app,
                image: nil,
                axElement: windowRef,
                appAxElement: appElement,
                closeButton: closeButton,
                lastAccessedTime: lastAccessedTime,
                creationTime: creationTime,
                spaceID: window.windowID.cgsSpaces().first.map { Int($0) },
                screenIdentifier: screenIdentifier(forWindowAt: window.frame.origin),
                isMinimized: minimizedState,
                isHidden: hiddenState,
                isFullscreen: fullscreenState
            )

            if let image = try? await captureWindowImage(window: window) {
                windowInfo.image = image
                windowInfo.imageCapturedTime = Date()
            }
            updateDesktopSpaceWindowCache(with: windowInfo)
        }
    }

    static func captureAndCacheAXWindowInfo(
        axWindow: AXUIElement,
        appAxElement: AXUIElement,
        app: NSRunningApplication,
        excludeWindowIDs: Set<CGWindowID>,
        skipWindowIDs: Set<CGWindowID> = [],
        existingCachedIDs: Set<CGWindowID> = []
    ) async throws {
        let pid = app.processIdentifier

        // Quick window ID check first (fast path)
        var cgID: CGWindowID = 0
        if _AXUIElementGetWindow(axWindow, &cgID) == .success, cgID != 0 {
            // Skip if already cached with fresh image (pre-computed by caller)
            if skipWindowIDs.contains(cgID) { return }
            guard !excludeWindowIDs.contains(cgID) else { return }
        }

        guard isValidAXWindowCandidate(axWindow) else { return }

        let cgCandidates = getCGWindowCandidates(for: pid)
        // Use pre-computed cached IDs if provided, otherwise read from cache
        let usedIDs = existingCachedIDs.isEmpty
            ? Set<CGWindowID>(desktopSpaceWindowCacheManager.readCache(pid: pid).map(\.id))
            : existingCachedIDs

        if cgID == 0 {
            if let mapped = mapAXToCG(axWindow: axWindow, candidates: cgCandidates, excluding: usedIDs) {
                cgID = mapped
            } else {
                return
            }
        }

        guard !excludeWindowIDs.contains(cgID), !usedIDs.contains(cgID) else { return }
        guard isAtLeastNormalLevel(cgID) else { return }

        let titleFilters = Defaults[.windowTitleFilters]
        if !titleFilters.isEmpty {
            let cgTitle = cgID.cgsTitle() ?? ""
            if titleFilters.contains(where: { cgTitle.lowercased().contains($0.lowercased()) }) {
                return
            }
        }

        guard let cgEntry = findCGEntry(for: cgID, in: cgCandidates) ?? findCGEntry(for: cgID, ownerPID: pid) else { return }
        guard isValidCGWindowEntry(cgEntry) else { return }

        let activeSpaceIDs = currentActiveSpaceIDs()
        guard shouldAcceptWindow(
            axWindow: axWindow,
            windowID: cgID,
            cgEntry: cgEntry,
            app: app,
            activeSpaceIDs: activeSpaceIDs,
            scBacked: false
        ) else { return }

        let windowTitle = (try? axWindow.title()) ?? cgID.cgsTitle()
        let minimizedState = (try? axWindow.isMinimized()) ?? false
        let hiddenState = app.isHidden
        let fullscreenState = try? axWindow.isFullscreen()

        let persistedData: WindowOrderPersistence.PersistedWindowEntry? = if let bundleId = app.bundleIdentifier {
            WindowOrderPersistence.getPersistedTimestamp(bundleIdentifier: bundleId, windowTitle: windowTitle)
        } else {
            nil
        }

        var info = WindowInfo(
            windowProvider: AXFallbackProvider(cgID: cgID),
            app: app,
            image: nil,
            axElement: axWindow,
            appAxElement: appAxElement,
            closeButton: try? axWindow.closeButton(),
            lastAccessedTime: persistedData?.lastAccessedTime ?? Date(),
            creationTime: persistedData?.creationTime,
            spaceID: cgID.cgsSpaces().first.map { Int($0) },
            screenIdentifier: (try? axWindow.position()).flatMap { screenIdentifier(forWindowAt: $0) },
            isMinimized: minimizedState,
            isHidden: hiddenState,
            isFullscreen: fullscreenState
        )
        info.windowName = windowTitle

        if let image = try? await captureWindowImage(windowID: cgID, pid: pid, windowTitle: windowTitle) {
            info.image = image
            info.imageCapturedTime = Date()
        }

        updateDesktopSpaceWindowCache(with: info)
    }

    private static let minUsableImageDimension = 10
    private static let maxImageAspectMismatchFactor: CGFloat = 4.0

    private static func expectedAspectRatio(for windowInfo: WindowInfo) -> CGFloat? {
        let providerSize = windowInfo.frame.size
        if providerSize.width > 0, providerSize.height > 0 {
            return providerSize.width / providerSize.height
        }
        if let axSize = try? windowInfo.axElement.size(), axSize.width > 0, axSize.height > 0 {
            return axSize.width / axSize.height
        }
        return nil
    }

    private static func shouldRejectCapturedImage(_ image: CGImage?, for windowInfo: WindowInfo) -> Bool {
        guard let image else { return true }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let minUsableDimension = CGFloat(minUsableImageDimension)
        guard width >= minUsableDimension, height >= minUsableDimension else { return true }

        guard let expectedAspect = expectedAspectRatio(for: windowInfo), expectedAspect > 0 else {
            return false
        }

        let capturedAspect = width / height
        guard capturedAspect > 0 else { return true }

        let mismatchFactor = max(capturedAspect, expectedAspect) / min(capturedAspect, expectedAspect)
        return mismatchFactor > maxImageAspectMismatchFactor
    }

    static func updateDesktopSpaceWindowCache(with windowInfo: WindowInfo) {
        desktopSpaceWindowCacheManager.updateCache(pid: windowInfo.app.processIdentifier) { windowSet in
            if let matchingWindow = windowSet.first(where: { $0.axElement == windowInfo.axElement }) {
                var matchingWindowCopy = matchingWindow
                matchingWindowCopy.windowName = windowInfo.windowName
                if let newSpaceID = windowInfo.spaceID {
                    matchingWindowCopy.spaceID = newSpaceID
                }
                if let newScreen = windowInfo.screenIdentifier {
                    matchingWindowCopy.screenIdentifier = newScreen
                }
                matchingWindowCopy.isMinimized = windowInfo.isMinimized
                matchingWindowCopy.isHidden = windowInfo.isHidden

                let shouldRejectImage = shouldRejectCapturedImage(windowInfo.image, for: windowInfo)
                if shouldRejectImage, matchingWindow.image != nil {
                    DebugLogger.log(
                        "Window image cache",
                        details: "Rejected suspicious capture for pid=\(windowInfo.app.processIdentifier) window=\(windowInfo.id)"
                    )
                } else {
                    matchingWindowCopy.image = windowInfo.image
                    matchingWindowCopy.imageCapturedTime = windowInfo.imageCapturedTime
                }

                windowSet.remove(matchingWindow)
                windowSet.insert(matchingWindowCopy)
            } else {
                if shouldRejectCapturedImage(windowInfo.image, for: windowInfo) {
                    var sanitizedWindowInfo = windowInfo
                    sanitizedWindowInfo.image = nil
                    windowSet.insert(sanitizedWindowInfo)
                } else {
                    windowSet.insert(windowInfo)
                }
            }
        }
    }

    static func removeWindowFromDesktopSpaceCache(with windowId: CGWindowID, in pid: pid_t) {
        desktopSpaceWindowCacheManager.removeFromCache(pid: pid, windowId: windowId)
    }

    static func removeWindowFromCache(with element: AXUIElement, in pid: pid_t) {
        if let windowId = try? element.cgWindowId() {
            removeWindowFromDesktopSpaceCache(with: windowId, in: pid)
        }
    }

    static func purifyAppCache(with pid: pid_t, removeAll: Bool) async -> Set<WindowInfo>? {
        if removeAll {
            desktopSpaceWindowCacheManager.writeCache(pid: pid, windowSet: [])
            return nil
        } else {
            let existingWindowsSet = desktopSpaceWindowCacheManager.readCache(pid: pid)
            if existingWindowsSet.isEmpty {
                return nil
            }

            var purifiedSet = existingWindowsSet
            for window in existingWindowsSet {
                if !isValidElement(window.axElement) {
                    purifiedSet.remove(window)
                    desktopSpaceWindowCacheManager.removeFromCache(pid: pid, windowId: window.id)
                }
            }
            return purifiedSet
        }
    }

    static func purgeAppCache(with pid: pid_t) {
        desktopSpaceWindowCacheManager.writeCache(pid: pid, windowSet: [])
    }

    /// Checks if the frontmost application is fullscreen and in the blacklist
    static func shouldIgnoreKeybindForFrontmostApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        // Check if the app is in fullscreen mode
        let isFullscreen = isAppInFullscreen(frontmostApp)

        // Check if the app is in the blacklist
        let appName = frontmostApp.localizedName ?? ""
        let bundleIdentifier = frontmostApp.bundleIdentifier ?? ""
        let blacklist = Defaults[.fullscreenAppBlacklist]

        let isInBlacklist = blacklist.contains { blacklistEntry in
            appName.lowercased().contains(blacklistEntry.lowercased()) ||
                bundleIdentifier.lowercased().contains(blacklistEntry.lowercased())
        }

        return isFullscreen && isInBlacklist
    }

    /// Checks if the given application is currently in fullscreen mode
    static func isAppInFullscreen(_ app: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Try to get the app's windows
        guard let windows = try? appElement.windows() else {
            return false
        }

        // Check if any window is in fullscreen mode
        for window in windows {
            if let isFullscreen = try? window.isFullscreen(), isFullscreen {
                return true
            }
        }

        return false
    }
}

// MARK: - Window Sorting

extension WindowUtil {
    /// Centralized sorting for dock preview and cmd+tab contexts (single app windows)
    static func sortWindows(_ windows: Set<WindowInfo>, for context: WindowFetchContext) -> [WindowInfo] {
        let sortOrder: WindowPreviewSortOrder = switch context {
        case .dockPreview:
            Defaults[.windowPreviewSortOrder]
        case .cmdTab:
            Defaults[.cmdTabSortOrder]
        }

        return sortWindowsWithOptions(Array(windows), sortOrder: sortOrder)
    }

    /// Centralized sorting for window switcher context (all apps windows)
    static func sortWindowsForSwitcher(_ windows: [WindowInfo]) -> [WindowInfo] {
        sortWindowsWithOptions(windows, sortOrder: Defaults[.windowSwitcherSortOrder])
    }

    /// Core sorting logic with configurable options
    private static func sortWindowsWithOptions(
        _ windows: [WindowInfo],
        sortOrder: WindowPreviewSortOrder
    ) -> [WindowInfo] {
        var sortedWindows: [WindowInfo]

            // Apply primary sort order
            = switch sortOrder
        {
        case .recentlyUsed:
            windows.sorted { $0.lastAccessedTime > $1.lastAccessedTime }
        case .creationOrder:
            windows.sorted { $0.creationTime < $1.creationTime }
        case .alphabeticalByTitle:
            windows.sorted { ($0.windowName ?? "").localizedCaseInsensitiveCompare($1.windowName ?? "") == .orderedAscending }
        case .alphabeticalByAppName:
            // Group by app name, then sort within groups by recently used
            windows.sorted { first, second in
                let firstName = first.app.localizedName ?? ""
                let secondName = second.app.localizedName ?? ""
                if firstName != secondName {
                    return firstName.localizedCaseInsensitiveCompare(secondName) == .orderedAscending
                }
                // Within same app, sort by recently used
                return first.lastAccessedTime > second.lastAccessedTime
            }
        }

        // Optionally move minimized/hidden windows to the end (global setting)
        if Defaults[.sortMinimizedToEnd] {
            let (visible, minimizedOrHidden) = sortedWindows.reduce(into: ([WindowInfo](), [WindowInfo]())) { result, window in
                if window.isMinimized || window.isEffectivelyHiddenForUI {
                    result.1.append(window)
                } else {
                    result.0.append(window)
                }
            }
            sortedWindows = visible + minimizedOrHidden
        }

        return sortedWindows
    }

    /// Groups windows by app for selected apps, keeping only the most recently used window for each grouped app.
    /// This maintains the original order based on the first appearance of each app in the sorted list.
    static func groupWindowsByApp(_ windows: [WindowInfo]) -> [WindowInfo] {
        let groupedApps = Set(Defaults[.groupedAppsInSwitcher])
        guard !groupedApps.isEmpty else { return windows }

        // Track which grouped apps we've already seen (to keep only first window)
        var seenGroupedApps = Set<String>()
        var result: [WindowInfo] = []

        for window in windows {
            let bundleId = window.app.bundleIdentifier ?? ""

            if groupedApps.contains(bundleId) {
                // This is a grouped app - only keep the first window we see
                if !seenGroupedApps.contains(bundleId) {
                    seenGroupedApps.insert(bundleId)
                    result.append(window)
                }
                // Skip subsequent windows of this grouped app
            } else {
                // Not a grouped app - keep all windows in their original position
                result.append(window)
            }
        }
        return result
    }
}

// MARK: - Window Actions

extension WindowUtil {
    static func canBringWindowToFrontWithoutSpaceSwitch(_ window: WindowInfo) -> Bool {
        let activeSpaceIDs = currentActiveSpaceIDs()
        guard !activeSpaceIDs.isEmpty else { return false }
        return windowBelongsToActiveSpace(window, activeSpaceIDs: activeSpaceIDs)
    }

    static func hasOnlyFullscreenWindows(for app: NSRunningApplication, preferredWindows: [WindowInfo]? = nil) -> Bool {
        let pid = app.processIdentifier
        let sourceWindows: [WindowInfo] = if let preferredWindows {
            preferredWindows.filter { $0.app.processIdentifier == pid }
        } else {
            readCachedWindows(for: pid)
        }

        let appWindows = sourceWindows.filter { !$0.isWindowlessApp }
        guard !appWindows.isEmpty else { return false }
        return appWindows.allSatisfy { (try? $0.axElement.isFullscreen()) == true }
    }

    static func shouldQuitAppOnWindowClose(processIdentifier pid: pid_t) -> Bool {
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
        return Defaults[.quitAppOnWindowClose] &&
            readCachedWindows(for: pid).count <= 1 &&
            finder.first?.processIdentifier != pid
    }

    @discardableResult
    static func closeAllWindows(for app: NSRunningApplication, preferredWindows: [WindowInfo]? = nil) -> Int {
        let pid = app.processIdentifier
        let sourceWindows: [WindowInfo] = if let preferredWindows {
            preferredWindows.filter { $0.app.processIdentifier == pid }
        } else {
            readCachedWindows(for: pid)
        }

        let windowsToClose = sourceWindows.filter { !$0.isWindowlessApp }
        guard !windowsToClose.isEmpty else { return 0 }

        var closeCount = 0
        for window in windowsToClose {
            if window.close() {
                closeCount += 1
            }
        }
        return closeCount
    }

    @discardableResult
    static func minimizeAllWindows(for app: NSRunningApplication, preferredWindows: [WindowInfo]? = nil) -> Int {
        let pid = app.processIdentifier
        let preferredAppWindows = preferredWindows?.filter {
            $0.app.processIdentifier == pid && !$0.isWindowlessApp
        } ?? []
        let sourceWindows: [WindowInfo] = if !preferredAppWindows.isEmpty {
            preferredAppWindows
        } else {
            // Fallback to cache when invoked from a windowless-only filtered view.
            readCachedWindows(for: pid)
        }

        let ownBundleId = Bundle.main.bundleIdentifier
        let appWindows = sourceWindows.filter {
            !$0.isWindowlessApp &&
                $0.app.bundleIdentifier != ownBundleId
        }
        guard !appWindows.isEmpty else { return 0 }

        let nonFullscreenWindows = appWindows.filter { (try? $0.axElement.isFullscreen()) != true }
        guard !nonFullscreenWindows.isEmpty else { return 0 }

        if nonFullscreenWindows.allSatisfy(\.isMinimized) {
            unminimizeWindowsAsync(nonFullscreenWindows)
            return nonFullscreenWindows.count
        }

        let windowsToMinimize = nonFullscreenWindows.filter { !$0.isMinimized }
        guard !windowsToMinimize.isEmpty else { return 0 }

        minimizeWindowsAsync(windowsToMinimize)
        return windowsToMinimize.count
    }

    @discardableResult
    static func minimizeAllWindowsGlobally() -> Int {
        minimizeAllWindowsGlobally(excludingWindowID: nil, excludingElement: nil)
    }

    @discardableResult
    static func minimizeAllWindowsExcept(_ keptWindow: WindowInfo) -> Int {
        minimizeAllWindowsGlobally(excludingWindowID: keptWindow.id, excludingElement: keptWindow.axElement)
    }

    @discardableResult
    private static func minimizeAllWindowsGlobally(
        excludingWindowID: CGWindowID?,
        excludingElement: AXUIElement?
    ) -> Int {
        let targets = collectGlobalMinimizeTargetsFast(
            excludingWindowID: excludingWindowID,
            excludingElement: excludingElement
        )
        guard !targets.isEmpty else { return 0 }
        minimizeAXWindowsAsync(targets.map(\.element))
        scheduleGlobalMinimizeReconciliation(
            for: targets,
            excludingWindowID: excludingWindowID,
            excludingElement: excludingElement
        )
        return targets.count
    }

    private static func minimizeAXWindowsAsync(_ windows: [AXUIElement]) {
        guard !windows.isEmpty else { return }

        Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for window in windows {
                    group.addTask {
                        try? window.setAttribute(kAXMinimizedAttribute, true)
                    }
                }
            }
        }
    }

    private struct GlobalMinimizeReconciliationSnapshot {
        let pid: pid_t
        let windowID: CGWindowID?
        let element: AXUIElement
    }

    private struct GlobalMinimizeReconciliationResult {
        let windowID: CGWindowID?
        let element: AXUIElement
        let isMinimized: Bool
    }

    private static func appEligibleForGlobalMinimize(_ app: NSRunningApplication, ownBundleId: String?) -> Bool {
        app.activationPolicy == .regular &&
            app.bundleIdentifier != ownBundleId &&
            !isAppFiltered(app)
    }

    private static func shouldExcludeGlobalMinimizeTarget(
        windowID: CGWindowID?,
        element: AXUIElement,
        excludingWindowID: CGWindowID?,
        excludingElement: AXUIElement?
    ) -> Bool {
        if let excludingElement, CFEqual(element, excludingElement) {
            return true
        }
        if let excludingWindowID, let windowID, windowID == excludingWindowID {
            return true
        }
        return false
    }

    private static func appendGlobalMinimizeTarget(
        pid: pid_t,
        windowID: CGWindowID?,
        element: AXUIElement,
        into targets: inout [GlobalMinimizeReconciliationSnapshot],
        seenWindowIDs: inout Set<CGWindowID>,
        seenElements: inout [AXUIElement]
    ) {
        if seenElements.contains(where: { CFEqual($0, element) }) {
            return
        }

        if let windowID {
            guard seenWindowIDs.insert(windowID).inserted else { return }
        }

        seenElements.append(element)
        targets.append(GlobalMinimizeReconciliationSnapshot(pid: pid, windowID: windowID, element: element))
    }

    private static func collectGlobalMinimizeTargetsFast(
        excludingWindowID: CGWindowID?,
        excludingElement: AXUIElement?
    ) -> [GlobalMinimizeReconciliationSnapshot] {
        let ownBundleId = Bundle.main.bundleIdentifier
        var targets: [GlobalMinimizeReconciliationSnapshot] = []
        var seenWindowIDs = Set<CGWindowID>()
        var seenElements: [AXUIElement] = []

        let cachedWindows = desktopSpaceWindowCacheManager.getAllWindows()
        for window in cachedWindows {
            guard !window.isWindowlessApp,
                  !window.isMinimized,
                  window.isFullscreen != true,
                  appEligibleForGlobalMinimize(window.app, ownBundleId: ownBundleId),
                  !shouldExcludeGlobalMinimizeTarget(
                      windowID: window.id,
                      element: window.axElement,
                      excludingWindowID: excludingWindowID,
                      excludingElement: excludingElement
                  )
            else {
                continue
            }

            appendGlobalMinimizeTarget(
                pid: window.app.processIdentifier,
                windowID: window.id,
                element: window.axElement,
                into: &targets,
                seenWindowIDs: &seenWindowIDs,
                seenElements: &seenElements
            )
        }

        for app in NSWorkspace.shared.runningApplications {
            guard appEligibleForGlobalMinimize(app, ownBundleId: ownBundleId) else { continue }
            let appAX = AXUIElementCreateApplication(app.processIdentifier)
            guard let axWindows = try? appAX.windows(), !axWindows.isEmpty else { continue }

            for axWindow in axWindows {
                let windowID = try? axWindow.cgWindowId()
                guard !shouldExcludeGlobalMinimizeTarget(
                    windowID: windowID,
                    element: axWindow,
                    excludingWindowID: excludingWindowID,
                    excludingElement: excludingElement
                ) else {
                    continue
                }
                if (try? axWindow.isMinimized()) == true {
                    continue
                }
                if (try? axWindow.isFullscreen()) == true {
                    continue
                }

                appendGlobalMinimizeTarget(
                    pid: app.processIdentifier,
                    windowID: windowID,
                    element: axWindow,
                    into: &targets,
                    seenWindowIDs: &seenWindowIDs,
                    seenElements: &seenElements
                )
            }
        }

        return targets
    }

    private static func collectGlobalMinimizeTargetsHeavy(
        for pids: Set<pid_t>,
        excludingWindowID: CGWindowID?,
        excludingElement: AXUIElement?
    ) -> [GlobalMinimizeReconciliationSnapshot] {
        guard !pids.isEmpty else { return [] }

        let ownBundleId = Bundle.main.bundleIdentifier
        var targets: [GlobalMinimizeReconciliationSnapshot] = []
        var seenWindowIDs = Set<CGWindowID>()
        var seenElements: [AXUIElement] = []

        for pid in pids {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  appEligibleForGlobalMinimize(app, ownBundleId: ownBundleId)
            else {
                continue
            }

            let appAX = AXUIElementCreateApplication(pid)
            let axWindows = AXUIElement.allWindows(pid, appElement: appAX)
            guard !axWindows.isEmpty else { continue }

            for axWindow in axWindows {
                let windowID = try? axWindow.cgWindowId()
                guard !shouldExcludeGlobalMinimizeTarget(
                    windowID: windowID,
                    element: axWindow,
                    excludingWindowID: excludingWindowID,
                    excludingElement: excludingElement
                ) else {
                    continue
                }
                if (try? axWindow.isMinimized()) == true {
                    continue
                }
                if (try? axWindow.isFullscreen()) == true {
                    continue
                }

                appendGlobalMinimizeTarget(
                    pid: pid,
                    windowID: windowID,
                    element: axWindow,
                    into: &targets,
                    seenWindowIDs: &seenWindowIDs,
                    seenElements: &seenElements
                )
            }
        }

        return targets
    }

    private static func applyGlobalMinimizeReconciliationResults(
        _ resultsByPID: [pid_t: [GlobalMinimizeReconciliationResult]]
    ) {
        guard !resultsByPID.isEmpty else { return }

        for (pid, results) in resultsByPID {
            desktopSpaceWindowCacheManager.updateCache(pid: pid) { windowSet in
                for result in results {
                    if let windowID = result.windowID,
                       let existingWindow = windowSet.first(where: { $0.id == windowID })
                    {
                        var updatedWindow = existingWindow
                        updatedWindow.isMinimized = result.isMinimized
                        windowSet.remove(existingWindow)
                        windowSet.insert(updatedWindow)
                        continue
                    }

                    if let existingWindow = windowSet.first(where: { $0.axElement == result.element }) {
                        var updatedWindow = existingWindow
                        updatedWindow.isMinimized = result.isMinimized
                        windowSet.remove(existingWindow)
                        windowSet.insert(updatedWindow)
                    }
                }
            }
        }
    }

    private static func readGlobalMinimizeStates(
        for targets: [GlobalMinimizeReconciliationSnapshot]
    ) -> (resultsByPID: [pid_t: [GlobalMinimizeReconciliationResult]], unresolvedPIDs: Set<pid_t>) {
        var perPIDResults: [pid_t: [GlobalMinimizeReconciliationResult]] = [:]
        var unresolvedPIDs = Set<pid_t>()

        for target in targets {
            guard let isMinimized = try? target.element.isMinimized() else {
                unresolvedPIDs.insert(target.pid)
                continue
            }

            perPIDResults[target.pid, default: []].append(
                GlobalMinimizeReconciliationResult(
                    windowID: target.windowID,
                    element: target.element,
                    isMinimized: isMinimized
                )
            )

            if !isMinimized {
                unresolvedPIDs.insert(target.pid)
            }
        }

        return (perPIDResults, unresolvedPIDs)
    }

    private static func cacheHasPendingGlobalMinimizeWindows(
        pid: pid_t,
        excludingWindowID: CGWindowID?,
        excludingElement: AXUIElement?
    ) -> Bool {
        let ownBundleId = Bundle.main.bundleIdentifier
        let cachedWindows = desktopSpaceWindowCacheManager.readCache(pid: pid)
        return cachedWindows.contains { window in
            guard !window.isWindowlessApp,
                  !window.isMinimized,
                  window.isFullscreen != true,
                  window.app.bundleIdentifier != ownBundleId
            else {
                return false
            }

            if let excludingWindowID, window.id == excludingWindowID {
                return false
            }
            if let excludingElement, CFEqual(window.axElement, excludingElement) {
                return false
            }
            return true
        }
    }

    private static func scheduleGlobalMinimizeReconciliation(
        for targets: [GlobalMinimizeReconciliationSnapshot],
        excludingWindowID: CGWindowID?,
        excludingElement: AXUIElement?
    ) {
        guard !targets.isEmpty else { return }

        globalMinimizeReconciliationLock.lock()
        pendingGlobalMinimizeReconciliation?.cancel()
        let task = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }

            let trackedPIDs = Set(targets.map(\.pid))
            let (firstResults, firstUnresolved) = readGlobalMinimizeStates(for: targets)
            applyGlobalMinimizeReconciliationResults(firstResults)
            guard !Task.isCancelled else { return }

            var unresolvedPIDs = firstUnresolved
            for pid in trackedPIDs {
                if cacheHasPendingGlobalMinimizeWindows(
                    pid: pid,
                    excludingWindowID: excludingWindowID,
                    excludingElement: excludingElement
                ) {
                    unresolvedPIDs.insert(pid)
                }
            }

            guard !unresolvedPIDs.isEmpty else { return }

            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }

            let unresolvedTargets = targets.filter { unresolvedPIDs.contains($0.pid) }
            let (retryResults, retryUnresolved) = readGlobalMinimizeStates(for: unresolvedTargets)
            applyGlobalMinimizeReconciliationResults(retryResults)
            guard !Task.isCancelled else { return }

            unresolvedPIDs = retryUnresolved
            for pid in trackedPIDs where unresolvedPIDs.contains(pid) {
                if !cacheHasPendingGlobalMinimizeWindows(
                    pid: pid,
                    excludingWindowID: excludingWindowID,
                    excludingElement: excludingElement
                ) {
                    unresolvedPIDs.remove(pid)
                }
            }

            guard !unresolvedPIDs.isEmpty else { return }

            let heavyTargets = collectGlobalMinimizeTargetsHeavy(
                for: unresolvedPIDs,
                excludingWindowID: excludingWindowID,
                excludingElement: excludingElement
            )
            guard !heavyTargets.isEmpty else { return }

            minimizeAXWindowsAsync(heavyTargets.map(\.element))
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }

            let (fallbackResults, _) = readGlobalMinimizeStates(for: heavyTargets)
            applyGlobalMinimizeReconciliationResults(fallbackResults)
        }
        pendingGlobalMinimizeReconciliation = task
        globalMinimizeReconciliationLock.unlock()
    }

    static func forceRefreshCachedWindowImages(for pid: pid_t) async {
        let windows = Array(desktopSpaceWindowCacheManager.readCache(pid: pid).filter { !$0.isWindowlessApp })
        guard !windows.isEmpty else { return }

        await LimitedConcurrency.forEachNonThrowing(windows, maxConcurrent: 4, timeout: 10) { window in
            let image = try await captureWindowImage(
                windowID: window.id,
                pid: pid,
                windowTitle: window.windowName,
                forceRefresh: true
            )
            var updated = window
            updated.image = image
            updated.imageCapturedTime = Date()
            updateDesktopSpaceWindowCache(with: updated)
        }
    }

    static func refreshCachedWindowImagesAfterOpenNewWindow(
        for pid: pid_t,
        previousWindowIDs: Set<CGWindowID>,
        sourceWindowID: CGWindowID?
    ) async {
        let windows = Array(desktopSpaceWindowCacheManager.readCache(pid: pid).filter { !$0.isWindowlessApp })
        guard !windows.isEmpty else { return }

        var refreshIDs = Set(windows.compactMap { window -> CGWindowID? in
            previousWindowIDs.contains(window.id) ? nil : window.id
        })

        if let sourceWindowID,
           windows.contains(where: { $0.id == sourceWindowID })
        {
            refreshIDs.insert(sourceWindowID)
        }

        if refreshIDs.isEmpty {
            // Some apps reuse the same window ID for "new tab/new document" flows.
            // Fall back to refreshing a visible candidate so the thumbnail can catch title/content changes.
            if let fallback = windows.first(where: { !$0.isMinimized && !$0.isEffectivelyHiddenForUI }) {
                refreshIDs.insert(fallback.id)
            } else if let firstWindow = windows.first {
                refreshIDs.insert(firstWindow.id)
            }
        }

        guard !refreshIDs.isEmpty else { return }

        let windowsToRefresh = windows.filter { refreshIDs.contains($0.id) }
        await LimitedConcurrency.forEachNonThrowing(windowsToRefresh, maxConcurrent: 4, timeout: 10) { window in
            let image = try await captureWindowImage(
                windowID: window.id,
                pid: pid,
                windowTitle: window.windowName,
                forceRefresh: true
            )
            var updated = window
            updated.image = image
            updated.imageCapturedTime = Date()
            updateDesktopSpaceWindowCache(with: updated)
        }
    }

    /// Minimizes multiple windows concurrently off the main thread to avoid UI blocking.
    static func minimizeWindowsAsync(_ windows: [WindowInfo]) {
        guard !windows.isEmpty else { return }

        let ownBundleId = Bundle.main.bundleIdentifier
        let windowsToMinimize = windows.filter { !$0.isMinimized && $0.app.bundleIdentifier != ownBundleId }
        guard !windowsToMinimize.isEmpty else { return }

        // Perform AX operations concurrently in background
        Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for window in windowsToMinimize {
                    group.addTask {
                        try? window.axElement.setAttribute(kAXMinimizedAttribute, true)
                    }
                }
            }
        }
    }

    /// Restores minimized windows concurrently off the main thread to avoid UI blocking.
    static func unminimizeWindowsAsync(_ windows: [WindowInfo]) {
        guard !windows.isEmpty else { return }

        let ownBundleId = Bundle.main.bundleIdentifier
        let windowsToRestore = windows.filter { $0.isMinimized && $0.app.bundleIdentifier != ownBundleId }
        guard !windowsToRestore.isEmpty else { return }

        if let app = windowsToRestore.first?.app, app.isHidden {
            app.unhide()
        }

        // Unminimize is treated as effectively reliable in practice; update cache eagerly
        // so cross-space rows clear the "Minimized" tag immediately.
        for window in windowsToRestore {
            updateCachedWindowState(window, isMinimized: false)
        }

        Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for window in windowsToRestore {
                    group.addTask {
                        try? window.axElement.setAttribute(kAXMinimizedAttribute, false)
                    }
                }
            }
        }
    }

    static func openNewWindow(app: NSRunningApplication) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x2D, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.postToPid(app.processIdentifier)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x2D, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.postToPid(app.processIdentifier)
    }

    static func activateAndOpenNewWindow(app: NSRunningApplication) {
        app.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            openNewWindow(app: app)
            reactivateAfterWindowRequest(app)
        }
    }

    static func activateWindowlessApp(app: NSRunningApplication) {
        switch Defaults[.windowlessAppActivationMode] {
        case .openNewWindow:
            activateAndOpenNewWindow(app: app)
        case .simulateDockClick:
            simulateDockClickForWindowlessApp(app: app)
        case .activateOnly:
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    static func simulateDockClickForWindowlessApp(app: NSRunningApplication) {
        app.activate(options: [.activateIgnoringOtherApps])
        defer { reactivateAfterWindowRequest(app) }

        let targetDescriptor = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
        let reopenEvent = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: targetDescriptor,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )

        guard let eventDesc = reopenEvent.aeDesc else {
            return
        }

        let status = AESendMessage(eventDesc, nil, AESendMode(kAENoReply), kAEDefaultTimeout)
        if status != noErr {
            DebugLogger.log("WindowlessApp", details: "Failed to send reopen event to \(app.localizedName ?? "Unknown"): \(status)")
        }
    }

    private static func reactivateAfterWindowRequest(_ app: NSRunningApplication) {
        DispatchQueue.main.async {
            guard !app.isTerminated else { return }
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}

// MARK: - Private Helper Methods

extension WindowUtil {
    static func focusAppBestEffort(_ app: NSRunningApplication) {
        app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

        let pid = app.processIdentifier
        let appAX = AXUIElementCreateApplication(pid)

        if let focusedWindow = try? appAX.focusedWindow(),
           let focusedWindowID = try? focusedWindow.cgWindowId(),
           let cachedFocused = readCachedWindows(for: pid).first(where: { $0.id == focusedWindowID && !$0.isWindowlessApp })
        {
            cachedFocused.bringToFront()
            return
        }

        if let bestCandidate = readCachedWindows(for: pid)
            .first(where: { !$0.isWindowlessApp && !$0.isMinimized && !$0.isEffectivelyHiddenForUI })
        {
            bestCandidate.bringToFront()
        }
    }

    /// Makes a window key by posting raw event bytes to the Window Server
    /// Ported from https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
    static func makeKeyWindow(_ psn: inout ProcessSerialNumber, windowID: CGWindowID) {
        var bytes = [UInt8](repeating: 0, count: 0xF8)
        bytes[0x04] = 0xF8
        bytes[0x3A] = 0x10
        var wid = UInt32(windowID)
        memcpy(&bytes[0x3C], &wid, MemoryLayout<UInt32>.size)
        memset(&bytes[0x20], 0xFF, 0x10)
        bytes[0x08] = 0x01
        _ = SLPSPostEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = SLPSPostEventRecordTo(&psn, &bytes)
    }
}

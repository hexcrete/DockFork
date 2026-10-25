import ApplicationServices
import Cocoa
import Defaults
import ScreenCaptureKit

let filteredBundleIdentifiers: [String] = ["com.apple.notificationcenterui"] // filters desktop widgets

struct PendingWindowFocusUpdates {
    private var timestamps: [PreviewWindowIdentity: Date] = [:]
    private static let lifespan: TimeInterval = 30
    private static let capacity = 128

    mutating func record(_ identity: PreviewWindowIdentity, at timestamp: Date) {
        timestamps = timestamps.filter { timestamp.timeIntervalSince($0.value) < Self.lifespan }
        timestamps[identity] = max(timestamps[identity] ?? .distantPast, timestamp)
        if timestamps.count > Self.capacity, let oldest = timestamps.min(by: { $0.value < $1.value })?.key {
            timestamps.removeValue(forKey: oldest)
        }
    }

    mutating func take(_ identity: PreviewWindowIdentity, now: Date = Date()) -> Date? {
        guard let timestamp = timestamps.removeValue(forKey: identity),
              now.timeIntervalSince(timestamp) < Self.lifespan else { return nil }
        return timestamp
    }

    mutating func removeAll(for pid: pid_t) {
        timestamps = timestamps.filter { $0.key.pid != pid }
    }
}

private actor GlobalWindowRefreshGate {
    private var isRunning = false
    private var isRunningFollowUp = false
    private var followUpRequested = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func perform(_ operation: @Sendable @escaping () async -> Void) async {
        if isRunning {
            if !isRunningFollowUp {
                followUpRequested = true
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            return
        }

        isRunning = true
        await Task.detached(priority: .utility, operation: operation).value

        if followUpRequested {
            followUpRequested = false
            isRunningFollowUp = true
            await Task.detached(priority: .utility, operation: operation).value
            isRunningFollowUp = false
        }

        isRunning = false
        let completedWaiters = waiters
        waiters.removeAll(keepingCapacity: true)
        completedWaiters.forEach { $0.resume() }
    }
}

private let globalWindowRefreshGate = GlobalWindowRefreshGate()

/// Context for fetching windows - determines which settings to use
enum WindowFetchContext {
    case dockPreview
    case cmdTab

    var shouldIgnoreAppsWithSingleWindow: Bool {
        switch self {
        case .dockPreview:
            Defaults[.ignoreAppsWithSingleWindow] && !Defaults[.showWindowlessAppsInDockPreview]
        case .cmdTab:
            Defaults[.ignoreAppsWithSingleWindowInCmdTab] && !Defaults[.showWindowlessAppsInCmdTab]
        }
    }
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
    var owningApplicationBundleIdentifier: String? {
        owningApplication?.bundleIdentifier
    }

    var owningApplicationProcessID: pid_t? {
        owningApplication?.processID
    }
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
    case forceQuit
    case close
    case minimize
    case toggleFullScreen
    case hide
    case openAppWindow
    case openNewWindow
    case closeAllWindows
    case minimizeAllWindows
    case maximize
    case bringToCurrentSpace

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
    case toggleWindowSelection
    case selectAllWindows
    case autoTileSelectedWindows

    /// No action
    case none

    var localizedName: String {
        switch self {
        case .quit:
            String(localized: "Quit App", comment: "Window action")
        case .forceQuit:
            String(localized: "Force Quit App", comment: "Window action; may discard unsaved changes")
        case .close:
            String(localized: "Close Window", comment: "Window action")
        case .minimize:
            String(localized: "Minimize", comment: "Window action")
        case .toggleFullScreen:
            String(localized: "Toggle Full Screen", comment: "Window action")
        case .hide:
            String(localized: "Hide App", comment: "Window action")
        case .openAppWindow:
            String(localized: "Open Window", comment: "Reveal and focus an existing window; does not create a window")
        case .openNewWindow:
            String(localized: "Open New Window", comment: "Window action")
        case .closeAllWindows:
            String(localized: "Close All Windows", comment: "Window action")
        case .minimizeAllWindows:
            String(localized: "Minimize All Windows", comment: "Window action")
        case .maximize:
            String(localized: "Maximize", comment: "Window action")
        case .bringToCurrentSpace:
            String(localized: "Bring to Current Space", comment: "Window action")
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
        case .toggleWindowSelection:
            String(localized: "Toggle Window Selection", comment: "Window action")
        case .selectAllWindows:
            String(localized: "Select All", comment: "Window selection action")
        case .autoTileSelectedWindows:
            String(localized: "Auto Tile Selected Windows", comment: "Window action")
        case .none:
            String(localized: "No Action", comment: "Window action")
        }
    }

    var iconName: String {
        switch self {
        case .quit: "xmark.circle.fill"
        case .forceQuit: "exclamationmark.octagon.fill"
        case .close: "xmark.square"
        case .minimize: "minus.circle"
        case .toggleFullScreen: "arrow.up.left.and.arrow.down.right"
        case .hide: "eye.slash"
        case .openAppWindow: "macwindow"
        case .openNewWindow: "plus.rectangle.on.rectangle"
        case .closeAllWindows: "xmark.square.fill"
        case .minimizeAllWindows: "minus.circle.fill"
        case .maximize: "arrow.up.backward.and.arrow.down.forward"
        case .bringToCurrentSpace: "arrow.right.to.line"
        case .fillLeftHalf: "rectangle.lefthalf.filled"
        case .fillRightHalf: "rectangle.righthalf.filled"
        case .fillTopHalf: "rectangle.tophalf.filled"
        case .fillBottomHalf: "rectangle.bottomhalf.filled"
        case .fillTopLeftQuarter: "rectangle.split.2x2.fill"
        case .fillTopRightQuarter: "rectangle.split.2x2.fill"
        case .fillBottomLeftQuarter: "rectangle.split.2x2.fill"
        case .fillBottomRightQuarter: "rectangle.split.2x2.fill"
        case .center: "rectangle.center.inset.filled"
        case .toggleWindowSelection: "checkmark.circle"
        case .selectAllWindows: "checkmark.circle.fill"
        case .autoTileSelectedWindows: "rectangle.split.2x2"
        case .none: "nosign"
        }
    }

    /// Actions that can be assigned to preview shortcuts, gestures, and mouse interactions.
    static let assignablePreviewActions: [WindowAction] = [
        .none, .toggleWindowSelection, .selectAllWindows, .autoTileSelectedWindows, .openAppWindow, .openNewWindow, .close, .closeAllWindows,
        .minimize, .minimizeAllWindows, .maximize, .toggleFullScreen, .bringToCurrentSpace, .hide, .quit, .forceQuit,
        .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
        .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter, .center,
    ]

    func postActionCategory(for window: WindowInfo, preferredWindows: [WindowInfo]? = nil) -> PostActionCategory? {
        switch self {
        case .quit, .forceQuit, .close, .closeAllWindows:
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
            let nonFullscreenWindows = appWindows.filter { $0.isFullscreen != true }
            if nonFullscreenWindows.isEmpty {
                return .unhiding
            }
            return nonFullscreenWindows.allSatisfy(\.isMinimized) ? .unhiding : .hiding
        case .autoTileSelectedWindows, .maximize, .toggleFullScreen, .bringToCurrentSpace,
             .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center:
            return .movingAndResizing
        case .openAppWindow, .toggleWindowSelection, .selectAllWindows, .none:
            return nil
        }
    }

    func closePreviewsOnlyAfterSuccess(for window: WindowInfo, category: PostActionCategory?) -> Bool {
        switch self {
        case .autoTileSelectedWindows, .openNewWindow, .toggleFullScreen, .bringToCurrentSpace,
             .maximize, .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center:
            true
        case .minimize:
            !window.isMinimized
        case .minimizeAllWindows:
            category == .hiding
        case .openAppWindow, .hide, .close, .quit, .forceQuit, .closeAllWindows, .toggleWindowSelection, .selectAllWindows, .none:
            false
        }
    }

    func shouldForcePreviewCloseForFullscreenTransition(on window: WindowInfo, preferredWindows: [WindowInfo]? = nil) -> Bool {
        switch self {
        case .minimize:
            // Unminimizing can jump Spaces when restoring a window located elsewhere.
            guard window.isMinimized else { return false }

            return WindowUtil.activationMaySwitchSpaces(for: window)

        case .minimizeAllWindows:
            // Keep previews open for unminimize-all even when some windows may restore on another Space.
            // This avoids hard-closing the container in the common edge case of mixed-space minimized sets.
            return false

        case .autoTileSelectedWindows, .toggleFullScreen, .hide, .quit, .forceQuit, .close, .openAppWindow, .openNewWindow, .closeAllWindows, .bringToCurrentSpace,
             .maximize, .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center, .toggleWindowSelection, .selectAllWindows, .none:
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
        case .openAppWindow, .openNewWindow, .close, .quit, .forceQuit, .closeAllWindows, .bringToCurrentSpace,
             .minimize, .hide, .minimizeAllWindows,
             .maximize, .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center:
            true
        case .toggleFullScreen:
            true
        case .autoTileSelectedWindows, .toggleWindowSelection, .selectAllWindows, .none:
            false
        }
    }

    var shouldScheduleDockReconciliation: Bool {
        switch self {
        case .openNewWindow, .close, .quit, .forceQuit, .closeAllWindows, .toggleFullScreen:
            true
        case .autoTileSelectedWindows, .openAppWindow, .minimize, .hide, .minimizeAllWindows, .maximize, .bringToCurrentSpace,
             .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center, .toggleWindowSelection, .selectAllWindows, .none:
            false
        }
    }

    var requiresDeferredSuccessWatcher: Bool {
        switch self {
        case .toggleFullScreen, .openNewWindow, .close, .quit, .forceQuit, .closeAllWindows:
            true
        case .autoTileSelectedWindows, .openAppWindow, .minimize, .hide, .minimizeAllWindows, .maximize, .bringToCurrentSpace,
             .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center, .toggleWindowSelection, .selectAllWindows, .none:
            false
        }
    }

    /// Result of performing a window action
    enum ActionResult {
        case dismissed
        case windowUpdated(WindowInfo)
        case noChange
    }

    /// Performs the action on the given window
    /// - Parameters:
    ///   - window: The window to perform the action on
    ///   - keepPreviewOnQuit: Whether to keep the preview open after quitting
    ///   - preferredWindows: Optional in-context windows for app-wide actions to avoid stale cache reads
    /// - Returns: The result indicating what happened
    func perform(
        on window: WindowInfo,
        keepPreviewOnQuit: Bool = false,
        preferredWindows: [WindowInfo]? = nil,
        feedback: ActionFeedbackHandle? = nil
    ) -> ActionResult {
        defer { if self != .autoTileSelectedWindows, self != .minimizeAllWindows { feedback?.finishRemaining(.requested) } }
        guard isSupported(for: window) else { feedback?.finishRemaining(.failed); return .noChange }
        func accepted(_ success: Bool) -> Bool {
            if !success { feedback?.finishRemaining(.failed) }
            return success
        }
        switch self {
        case .quit, .forceQuit:
            guard accepted(window.quit(force: self == .forceQuit)) else { return .noChange }
            if keepPreviewOnQuit {
                return .noChange
            } else {
                return .dismissed
            }

        case .close:
            let pid = window.app.processIdentifier
            if window.isWindowlessApp {
                let closedCount = WindowUtil.closeAllWindows(for: window.app, preferredWindows: preferredWindows, feedback: feedback)
                if closedCount == 0, WindowUtil.shouldQuitAppOnWindowClose(processIdentifier: pid) {
                    guard accepted(window.quit(force: false)) else { return .noChange }
                    if keepPreviewOnQuit {
                        return .noChange
                    } else {
                        return .dismissed
                    }
                }
                return .noChange
            }

            if WindowUtil.shouldQuitAppOnWindowClose(processIdentifier: pid) {
                guard accepted(window.quit(force: false)) else { return .noChange }
                if keepPreviewOnQuit {
                    return .noChange
                } else {
                    return .dismissed
                }
            } else {
                let closed = window.close()
                feedback?.finishRemaining(closed ? .requested : .failed)
                return .noChange
            }

        case .minimize, .toggleFullScreen, .hide:
            // These actions require the asynchronous confirmed executor.
            return .noChange

        case .openAppWindow:
            if window.isWindowlessApp {
                window.app.activate(options: [.activateIgnoringOtherApps])
                return .dismissed
            }

            return .noChange

        case .openNewWindow:
            guard accepted(WindowUtil.openNewWindow(app: window.app)) else { return .noChange }
            return .dismissed

        case .closeAllWindows:
            let closedCount = WindowUtil.closeAllWindows(for: window.app, preferredWindows: preferredWindows, feedback: feedback)
            return accepted(closedCount > 0) ? .dismissed : .noChange

        case .minimizeAllWindows:
            let changedCount = WindowUtil.minimizeAllWindows(for: window.app, preferredWindows: preferredWindows, feedback: feedback)
            return accepted(changedCount > 0) ? .dismissed : .noChange

        case .maximize:
            return .noChange

        case .bringToCurrentSpace:
            if accepted(WindowUtil.moveWindowToCurrentManagedSpace(window)) {
                return .dismissed
            }
            return .noChange

        case .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter, .center:
            // Frame actions require the asynchronous shared executor.
            return .noChange

        case .autoTileSelectedWindows:
            Task { @MainActor in
                let result = await WindowUtil.tilePreviewWindows([window], direction: .neutral, feedback: feedback)
                if !result.failed.isEmpty {
                    DebugLogger.log("AutoTileWindow", details: "Failed window \(window.id)")
                    NSSound.beep()
                }
            }
            return .noChange

        case .toggleWindowSelection, .selectAllWindows, .none:
            return .noChange
        }
    }
}

enum WindowUtil {
    private static let desktopSpaceWindowCacheManager = SpaceWindowCacheManager()
    private static let operationTimeout: UInt64 = 10_000_000_000
    private static let internalWindowLock = NSLock()
    private static var internalWindowIDs: Set<CGWindowID> = []

    static func isInternalWindow(_ windowID: CGWindowID) -> Bool {
        internalWindowLock.lock()
        defer { internalWindowLock.unlock() }
        return internalWindowIDs.contains(windowID)
    }

    static func registerInternalWindow(_ windowID: CGWindowID) {
        internalWindowLock.lock()
        internalWindowIDs.insert(windowID)
        internalWindowLock.unlock()
    }

    static func unregisterInternalWindow(_ windowID: CGWindowID) {
        internalWindowLock.lock()
        internalWindowIDs.remove(windowID)
        internalWindowLock.unlock()
    }

    private struct NativeTabSnapshotKey: Hashable {
        let pid: pid_t
        let spaceID: Int
    }

    private static let nativeTabSnapshotLock = NSLock()
    private static var nativeTabSnapshots: [NativeTabSnapshotKey: NativeTabGrouping.VisibilitySnapshot] = [:]

    private static func nativeTabSnapshot(for key: NativeTabSnapshotKey) -> NativeTabGrouping.VisibilitySnapshot? {
        nativeTabSnapshotLock.lock()
        defer { nativeTabSnapshotLock.unlock() }
        return nativeTabSnapshots[key]
    }

    private static func setNativeTabSnapshot(_ snapshot: NativeTabGrouping.VisibilitySnapshot, for key: NativeTabSnapshotKey) {
        nativeTabSnapshotLock.lock()
        nativeTabSnapshots[key] = snapshot
        nativeTabSnapshotLock.unlock()
    }

    private static func purgeNativeTabSnapshots(for pid: pid_t? = nil) {
        nativeTabSnapshotLock.lock()
        defer { nativeTabSnapshotLock.unlock() }
        if let pid {
            nativeTabSnapshots = nativeTabSnapshots.filter { $0.key.pid != pid }
        } else {
            nativeTabSnapshots.removeAll()
        }
    }

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

    static func shouldCaptureWindowImages() -> Bool {
        !Defaults[.disableImagePreview] && hasScreenRecordingPermission()
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

    static func shouldRefreshCachedWindowImage(hasImage: Bool, hasSCWindow: Bool, isFresh: Bool, missingOnly: Bool) -> Bool {
        !isFresh && (!hasImage || (!missingOnly && !hasSCWindow))
    }

    // Track windows explicitly updated by bringWindowToFront to prevent observer duplication
    private static var timestampUpdates: [AXUIElement: Date] = [:]
    private static let updateTimestampLock = NSLock()
    private static let pendingFocusLock = NSLock()
    private static var pendingFocusUpdates = PendingWindowFocusUpdates()
    private static let windowUpdateTimeWindow: TimeInterval = 1.5
    private static var programmaticResizeRefreshDelayMilliseconds: UInt64 = 180
    private static var axResizeRefreshDelayMilliseconds: UInt64 = 360
    private static let fullscreenExitMetadataReconciliationDelayNanos: UInt64 = 450_000_000
    private static var programmaticResizeRefreshDelayNanos: UInt64 { programmaticResizeRefreshDelayMilliseconds * 1_000_000 }
    private static var axResizeRefreshDelayNanos: UInt64 { axResizeRefreshDelayMilliseconds * 1_000_000 }
    private static let programmaticResizeRefreshLock = NSLock()
    private static let metadataReconciliationLock = NSLock()
    private static let globalMinimizeReconciliationLock = NSLock()
    private static let managedSpaceMoveLock = NSLock()
    private struct PendingWindowRefresh {
        let token: UUID
        let task: Task<Void, Never>
    }

    private static var pendingProgrammaticResizeRefreshes: [String: PendingWindowRefresh] = [:]
    private static var pendingMetadataReconciliations: [String: PendingWindowRefresh] = [:]
    private static var pendingGlobalMinimizeReconciliation: [UUID: Task<Void, Never>] = [:]
    private static var pendingManagedSpaceMoves: [String: PendingWindowRefresh] = [:]
    @MainActor private static var pendingManagedSpaceSwitch: PendingWindowRefresh?
    @MainActor private static var pendingManagedSpaceFollows: [String: PendingWindowRefresh] = [:]

    private static let captureError = NSError(
        domain: "WindowCaptureError",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Error encountered during image capture"]
    )
}

// MARK: - Cache Management

extension WindowUtil {
    struct PreviewBatchResult {
        var succeeded: [WindowInfo] = []
        var failed: [PreviewWindowIdentity] = []
    }

    static func beginPreviewActionRequest(_ action: WindowAction, windows: [WindowInfo], resolvedTargets: [WindowInfo]? = nil) -> WindowActionRequest {
        let targets = resolvedTargets ?? action.previewTargets(from: windows)
        let apps = Set(targets.filter {
            action.isAppWidePreviewAction || (action == .close && shouldQuitAppOnWindowClose(processIdentifier: $0.app.processIdentifier))
        }.map(\.app.processIdentifier))
        return WindowActionOwnership.shared.begin(targets.map(PreviewWindowIdentity.init), apps: apps,
                                                  protect: action == .close || action.isQuitAction)
    }

    @MainActor
    static func performPreviewBatchAction(_ action: WindowAction, on windows: [WindowInfo],
                                          allowFullscreenEntry: Bool = false, feedback: ActionFeedbackHandle? = nil,
                                          request: WindowActionRequest? = nil, targetState: Bool? = nil, resolvedTargets: [WindowInfo]? = nil,
                                          tilingDestination: ManagedSpaceDestination? = nil,
                                          beforeActionChange: (@MainActor (Bool) -> Bool)? = nil) async -> PreviewBatchResult
    {
        defer { feedback?.finishRemaining(.cancelled) }
        guard !Task.isCancelled else { return PreviewBatchResult() }
        let requested = windows
        let autoTile = action.autoTilingDirection(windowCount: requested.filter { action.appliesToSelectedWindow($0) }.count,
                                                  fillActionsAutoTile: Defaults[.fillActionsAutoTileSelection]) != nil
        let windows = resolvedTargets ?? action.previewTargets(from: requested, allowFullscreenEntry: allowFullscreenEntry)
        guard !windows.isEmpty else {
            let result = PreviewBatchResult(failed: autoTile ? [] : requested.filter {
                action.appliesToSelectedWindow($0) && (requested.count == 1 || action.isSupported(for: $0))
            }.map(PreviewWindowIdentity.init))
            feedback?.finish(result)
            return result
        }
        let resolvedState = targetState ?? action.batchTargetState(for: windows)
        let suppliedRequest = request ?? WindowActionRequest.current
        let ownsRequest = suppliedRequest == nil
        let request = suppliedRequest ?? beginPreviewActionRequest(action, windows: windows, resolvedTargets: windows)
        defer { if ownsRequest { request.finish() } }
        guard !request.admitted.isEmpty else {
            let result = PreviewBatchResult(failed: request.rejected)
            feedback?.finish(result)
            return result
        }
        if !ownsRequest {
            await request.waitForPredecessors()
            guard !Task.isCancelled else { return PreviewBatchResult() }
            return await executePreviewAction(action, windows: windows, allowFullscreenEntry: allowFullscreenEntry,
                                              feedback: feedback, request: request, targetState: resolvedState, autoTile: autoTile, tilingDestination: tilingDestination, beforeActionChange: beforeActionChange)
        }
        let task = Task { @MainActor in
            await executePreviewAction(action, windows: windows, allowFullscreenEntry: allowFullscreenEntry,
                                       feedback: feedback, request: request, targetState: resolvedState, autoTile: autoTile, tilingDestination: tilingDestination, beforeActionChange: beforeActionChange)
        }
        request.onSuperseded { task.cancel() }
        var result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if task.isCancelled || Task.isCancelled {
            let succeeded = Set(result.succeeded.map(PreviewWindowIdentity.init))
            result.failed += request.admitted.filter { !succeeded.contains($0) && !result.failed.contains($0) }
        }
        return result
    }

    @MainActor
    private static func executePreviewAction(_ action: WindowAction, windows: [WindowInfo], allowFullscreenEntry: Bool,
                                             feedback: ActionFeedbackHandle?, request: WindowActionRequest, targetState: Bool?, autoTile: Bool,
                                             tilingDestination: ManagedSpaceDestination?,
                                             beforeActionChange: (@MainActor (Bool) -> Bool)?) async -> PreviewBatchResult
    {
        if WindowActionRequest.current?.token != request.token {
            await request.waitForPredecessors()
            guard !Task.isCancelled else { return PreviewBatchResult() }
            return await WindowActionRequest.$current.withValue(request) {
                await executePreviewAction(action, windows: windows, allowFullscreenEntry: allowFullscreenEntry,
                                           feedback: feedback, request: request, targetState: targetState, autoTile: autoTile, tilingDestination: tilingDestination, beforeActionChange: beforeActionChange)
            }
        }
        guard !Task.isCancelled else { return PreviewBatchResult() }
        var result = PreviewBatchResult(failed: request.rejected)
        if let feedback {
            for identity in request.rejected {
                feedback.finish(identity, .failed)
            }
        }
        let windows = windows.filter { request.contains(PreviewWindowIdentity($0)) }
        guard !windows.isEmpty else { feedback?.finish(result); return result }
        if autoTile, let direction = action.tilingDirection {
            let tiled = await tilePreviewWindows(windows, direction: direction, destination: tilingDestination, feedback: feedback)
            result.succeeded = tiled.succeeded
            result.failed += tiled.failed
            return result
        }
        let togglesFullscreen = action == .toggleFullScreen && allowFullscreenEntry && windows.count == 1
        let targets = togglesFullscreen ? windows : action.batchTargets(from: windows)
        guard !targets.isEmpty else { result.failed += windows.map(PreviewWindowIdentity.init); feedback?.finish(result); return result }
        let hiddenTarget = targetState ?? false

        if action == .openAppWindow {
            for window in targets {
                guard !Task.isCancelled else { return result }
                guard request.contains(PreviewWindowIdentity(window)) else { continue }
                let revealed = await revealWindowConfirmed(window)
                guard !Task.isCancelled else { return result }
                if revealed { result.succeeded.append(window) }
                else { result.failed.append(PreviewWindowIdentity(window)) }
                feedback?.finish(PreviewWindowIdentity(window), revealed ? .completed : .failed)
            }
            return result
        }

        if action == .minimize || action == .minimizeAllWindows {
            let minimizedTarget = targetState ?? false
            let candidates = windows
            guard !candidates.isEmpty else {
                result.failed += targets.map(PreviewWindowIdentity.init)
                feedback?.finish(result)
                return result
            }
            var unrevealedApps = Set<pid_t>()
            if !minimizedTarget {
                var revealedApps = Set<pid_t>()
                for window in candidates where request.contains(PreviewWindowIdentity(window)) && window.app.isHidden && revealedApps.insert(window.app.processIdentifier).inserted {
                    guard !Task.isCancelled else { return result }
                    if await !setHiddenStateConfirmed(for: window.app, isHidden: false) {
                        unrevealedApps.insert(window.app.processIdentifier)
                    }
                }
            }
            result.succeeded = await setMinimizedWindowsConfirmed(candidates.filter { !unrevealedApps.contains($0.app.processIdentifier) }, isMinimized: minimizedTarget, isTargetActive: { request.contains($0) }, progress: feedback?.confirmedProgress)
            let confirmed = Set(result.succeeded.map(PreviewWindowIdentity.init))
            result.failed += candidates.map(PreviewWindowIdentity.init).filter { !confirmed.contains($0) }
            feedback?.finish(result)
            return result
        }

        let isGeometryAction = action.tilingDirection != nil || action == .maximize || action == .center || action == .bringToCurrentSpace
        let foregroundGeometry = isGeometryAction && Defaults[.moveResizeBringToForeground]
        let requestOnly = feedback != nil && [WindowAction.close, .closeAllWindows, .quit, .forceQuit, .openNewWindow, .bringToCurrentSpace].contains(action)
        var quitApps = Set<pid_t>()
        for window in targets {
            guard !Task.isCancelled else { return result }
            guard request.contains(PreviewWindowIdentity(window)) else { continue }
            let pid = window.app.processIdentifier
            var succeeded = false
            if !window.app.isTerminated, action == .toggleFullScreen || action.isAvailable(for: window) {
                switch action {
                case .hide:
                    let candidates = readCachedWindows(for: pid).filter { !$0.isWindowlessApp }.map(\.axElement)
                    succeeded = await setHiddenStateConfirmed(for: window.app, isHidden: hiddenTarget, fullscreenCandidates: candidates, beforeChange: beforeActionChange)
                case .toggleFullScreen:
                    succeeded = await changeFullscreenConfirmed(window, toggle: togglesFullscreen, beforeChange: beforeActionChange)
                case .quit, .forceQuit:
                    succeeded = window.quit(force: action == .forceQuit)
                case .close where shouldQuitAppOnWindowClose(processIdentifier: pid):
                    if quitApps.insert(pid).inserted {
                        succeeded = window.quit(force: false)
                    } else { succeeded = true }
                case .close:
                    succeeded = await !closeWindows([window], feedback: feedback).succeeded.isEmpty
                case .closeAllWindows:
                    let appWindows = windows.filter { $0.app.processIdentifier == pid }
                    succeeded = await !closeWindows(appWindows, feedback: feedback).succeeded.isEmpty
                case .openNewWindow:
                    succeeded = openNewWindow(app: window.app)
                case .bringToCurrentSpace:
                    succeeded = moveWindowToCurrentManagedSpace(window)
                default:
                    if let rect = action.positionRect {
                        succeeded = await window.positionWindow(rect)
                    } else {
                        let fullscreen = await window.readFullscreenState()
                        guard !Task.isCancelled else { return result }
                        if fullscreen != true, case .dismissed = action.perform(on: window, preferredWindows: windows) { succeeded = true }
                    }
                }
            }
            guard !Task.isCancelled else { return result }
            if succeeded { result.succeeded.append(window) }
            else { result.failed.append(PreviewWindowIdentity(window)) }
            if let feedback {
                if isGeometryAction {
                    if !succeeded || !foregroundGeometry {
                        feedback.finish(PreviewWindowIdentity(window), succeeded ? (requestOnly ? .requested : .completed) : .failed)
                    }
                } else {
                    let affected = windows.filter { $0.app.processIdentifier == pid }
                    for target in affected where action.isAppWidePreviewAction || target.id == window.id {
                        feedback.finish(PreviewWindowIdentity(target), succeeded ? (requestOnly ? .requested : .completed) : .failed)
                    }
                }
            }
            await Task.yield()
        }
        if foregroundGeometry {
            for window in result.succeeded.reversed() {
                guard !Task.isCancelled else { return result }
                guard request.contains(PreviewWindowIdentity(window)) else { continue }
                if canBringWindowToFrontWithoutSpaceSwitch(window), request.mayForeground,
                   await !window.bringToFrontConfirmed() { result.failed.append(PreviewWindowIdentity(window)) }
                guard !Task.isCancelled else { return result }
                let identity = PreviewWindowIdentity(window)
                feedback?.finish(identity, result.failed.contains(identity) ? .failed : (requestOnly ? .requested : .completed))
            }
        }
        feedback?.finish(result, requested: requestOnly)
        return result
    }

    private static func changeFullscreenConfirmed(_ window: WindowInfo, toggle: Bool = false,
                                                  reconciliationDelayNanos: UInt64 = WindowAction.fullscreenConfirmationDelay,
                                                  beforeChange: (@MainActor (Bool) -> Bool)? = nil) async -> Bool
    {
        guard WindowAction.toggleFullScreen.isSupported(for: window) else { return false }
        if WindowActionRequest.current == nil {
            return await WindowActionRequest.run([PreviewWindowIdentity(window)]) { _ in
                await changeFullscreenConfirmed(window, toggle: toggle, reconciliationDelayNanos: reconciliationDelayNanos, beforeChange: beforeChange)
            } ?? false
        }
        guard WindowActionRequest.current?.contains(PreviewWindowIdentity(window)) == true else { return false }
        guard !Task.isCancelled, !window.isWindowlessApp, !window.app.isTerminated else { return false }
        let element = window.axElement
        let appElement = window.appAxElement
        let windowID = window.id
        let isFrontmost = if beforeChange != nil {
            await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier == window.app.processIdentifier }
        } else { false }
        let worker = Task.detached(priority: .userInitiated) {
            var result: (state: Bool?, attempted: Bool) = (nil, false)
            do {
                guard !Task.isCancelled, let current = try? element.isFullscreen() else { return result }
                let target = toggle ? !current : false
                guard !Task.isCancelled else { return result }
                if current != target {
                    if let beforeChange {
                        let focusedID = isFrontmost && !target ? (try? appElement.focusedWindow()).flatMap { try? $0.cgWindowId() } : nil
                        guard !Task.isCancelled,
                              await beforeChange(target || focusedID == windowID), !Task.isCancelled
                        else { return result }
                    }
                    guard !Task.isCancelled else { return result }
                    result.attempted = true
                    try element.setAttribute(kAXFullscreenAttribute, target)
                }
                for delay in [UInt64(0), 100_000_000, 300_000_000, 700_000_000] {
                    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
                    guard !Task.isCancelled else { return result }
                    if (try? element.isFullscreen()) == target {
                        guard !Task.isCancelled else { return result }
                        result.state = target
                        return result
                    }
                }
            } catch { return result }
            return result
        }
        let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        if !Task.isCancelled, let state = result.state { updateCachedWindowState(window, isFullscreen: state) }
        // A cancelled request can still have changed the app during an in-flight AX write.
        if !Task.isCancelled || result.attempted {
            scheduleCachedWindowMetadataReconciliation(pid: window.app.processIdentifier, windowID: window.id, delayNanos: reconciliationDelayNanos)
        }
        return !Task.isCancelled && result.state != nil
    }

    static func resizeRefreshDelayMilliseconds(from seconds: CGFloat, fallback: CGFloat) -> UInt64 {
        let boundedSeconds = seconds.isFinite ? min(1, max(0, seconds)) : fallback
        return UInt64((boundedSeconds * 1000).rounded())
    }

    static func setResizeRefreshDebounceDelays(programmaticSeconds: CGFloat, axSeconds: CGFloat) {
        programmaticResizeRefreshDelayMilliseconds = resizeRefreshDelayMilliseconds(
            from: programmaticSeconds, fallback: Defaults.Keys.programmaticResizePreviewRefreshDelay.defaultValue
        )
        axResizeRefreshDelayMilliseconds = resizeRefreshDelayMilliseconds(
            from: axSeconds, fallback: Defaults.Keys.nativeResizePreviewRefreshDelay.defaultValue
        )
    }

    /// Reads cached windows for an app without triggering any SCK/AX fetches.
    /// Returns immediately with whatever is in cache, sorted by the given context.
    static func readCachedWindows(for pid: pid_t, sortedBy context: WindowFetchContext = .dockPreview) -> [WindowInfo] {
        let cached = deduplicatedByWindowID(desktopSpaceWindowCacheManager.readCache(pid: pid).filter {
            WindowOwnerResolver.ownerBelongsToDisplayApp($0.ownerApp, displayApp: $0.app)
        })
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

    static func updateWindowDateTime(element: AXUIElement, app: NSRunningApplication, at timestamp: Date = Date()) {
        let windowID = try? element.cgWindowId()
        let now = timestamp
        updateTimestampLock.lock()
        if let lastUpdate = timestampUpdates[element],
           now.timeIntervalSince(lastUpdate) < windowUpdateTimeWindow
        {
            cleanupExpiredUpdates(currentTime: now)
            updateTimestampLock.unlock()
            return
        }
        timestampUpdates[element] = now
        updateTimestampLock.unlock()

        desktopSpaceWindowCacheManager.updateCache(pid: app.processIdentifier) { windowSet in
            if let index = windowSet.firstIndex(where: { cachedWindow in
                if cachedWindow.axElement == element {
                    return true
                }
                guard let windowID else { return false }
                return cachedWindow.id == windowID
            }) {
                var updatedWindow = windowSet[index]
                guard now > updatedWindow.lastAccessedTime else { return }
                updatedWindow.lastAccessedTime = now
                windowSet.remove(at: index)
                windowSet.insert(updatedWindow)
            } else if let windowID, windowID != 0 {
                pendingFocusLock.withLock {
                    pendingFocusUpdates.record(PreviewWindowIdentity(pid: app.processIdentifier, windowID: windowID), at: now)
                }
            }
        }
    }

    /// Updates window timestamp optimistically and records breadcrumb for observer deduplication
    static func updateTimestampOptimistically(for windowInfo: WindowInfo) {
        let now = Date()
        desktopSpaceWindowCacheManager.updateCache(pid: windowInfo.app.processIdentifier) { windowSet in
            if let index = windowSet.firstIndex(where: { $0.axElement == windowInfo.axElement || $0.id == windowInfo.id }) {
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
        screenIdentifier: String?? = nil,
        frame: CGRect? = nil
    ) {
        desktopSpaceWindowCacheManager.updateCache(pid: windowInfo.app.processIdentifier) { windowSet in
            if let existingIndex = windowSet.firstIndex(where: {
                $0.id == windowInfo.id || $0.axElement == windowInfo.axElement
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
                if let frame {
                    updatedWindow.frame = frame
                }
                windowSet.remove(at: existingIndex)
                windowSet.insert(updatedWindow)
            }
        }
    }

    static func updateCachedWindowStates(
        for pid: pid_t,
        matchingWindowIDs: Set<CGWindowID>? = nil,
        insertingMissing sourceWindows: [WindowInfo] = [],
        isMinimized: Bool? = nil,
        isHidden: Bool? = nil
    ) {
        desktopSpaceWindowCacheManager.updateCache(pid: pid) { windowSet in
            let matchingWindows = windowSet.filter { matchingWindowIDs?.contains($0.id) ?? true }
            for window in matchingWindows {
                var updatedWindow = window
                var didChange = false
                if let isMinimized, updatedWindow.isMinimized != isMinimized {
                    updatedWindow.isMinimized = isMinimized
                    didChange = true
                }
                if let isHidden, updatedWindow.isHidden != isHidden {
                    updatedWindow.isHidden = isHidden
                    didChange = true
                }
                guard didChange else { continue }
                windowSet.remove(window)
                windowSet.insert(updatedWindow)
            }

            guard let matchingWindowIDs else { return }
            let cachedIDs = Set(windowSet.map(\.id))
            for window in sourceWindows where matchingWindowIDs.contains(window.id) && !cachedIDs.contains(window.id) {
                var updatedWindow = window
                if let isMinimized {
                    updatedWindow.isMinimized = isMinimized
                }
                if let isHidden {
                    updatedWindow.isHidden = isHidden
                }
                windowSet.insert(updatedWindow)
            }
        }
    }

    struct WindowPlacementResult {
        let frame: CGRect
        let screenIdentifier: String
    }

    @MainActor
    static func planSpaceContents(from source: CGSSpaceID, to target: CGSSpaceID, action: SpaceContentsAction) throws -> SpaceContentsPlan {
        let displays = WindowSpaces.managedDisplays()
        let mapping = try SpaceContentsLayout.destinations(from: source, to: target, action: action, displays: displays)
        let windows = collapseNativeTabsIfNeeded(sortWindowsForSwitcher(getAllWindowsIgnoringSwitcherFilters()))
        let sections = ManagedSpacePresentation.snapshot(displays: displays, orderedWindows: windows)
        var memberships: [PreviewWindowIdentity: Set<CGSSpaceID>] = [:]
        for entry in sections.flatMap(\.spaces) where !entry.isFullscreen {
            for identity in entry.apps.flatMap(\.windowIdentities) {
                memberships[identity, default: []].insert(entry.id)
            }
        }
        let moves = WindowAction.bringToCurrentSpace.previewTargets(from: windows).compactMap { window -> SpaceContentsPlan.Move? in
            guard !window.isWindowlessApp, !window.app.isTerminated, window.isFullscreen != true,
                  let ids = memberships[PreviewWindowIdentity(window)], ids.count == 1, let sourceID = ids.first,
                  let destinationID = mapping[sourceID], let destination = WindowSpaces.destination(forSpaceID: destinationID, in: displays) else { return nil }
            return SpaceContentsPlan.Move(window: window, sourceID: sourceID, destination: destination)
        }
        return SpaceContentsPlan(topology: SpaceContentsTopology(displays), moves: moves)
    }

    @MainActor
    static func moveSpaceContents(_ plan: SpaceContentsPlan, feedback: ActionFeedbackHandle? = nil,
                                  isRequestActive: @escaping @MainActor () -> Bool = { true }) async throws -> PreviewBatchResult
    {
        defer { feedback?.finishRemaining(.cancelled) }
        let ids = plan.moves.map { PreviewWindowIdentity($0.window) }
        func validateTopology() -> Bool {
            plan.topology == SpaceContentsTopology(WindowSpaces.managedDisplays())
        }
        guard validateTopology() else { feedback?.finishRemaining(.failed); throw SpaceContentsError.topologyChanged }
        guard let first = plan.moves.first else { return PreviewBatchResult() }
        let outcome = await WindowActionRequest.run(ids) { request -> Result<PreviewBatchResult, SpaceContentsError> in
            guard !Task.isCancelled, isRequestActive() else { return .success(PreviewBatchResult(failed: ids)) }
            guard validateTopology() else { feedback?.finishRemaining(.failed); return .failure(.topologyChanged) }
            let assignments = Dictionary(uniqueKeysWithValues: plan.moves.map { (PreviewWindowIdentity($0.window), $0) })
            return await .success(movePreviewWindows(plan.moves.map(\.window), to: first.destination, request: request,
                                                     followsDestination: false, dismissPreviews: nil, mayFollow: { false },
                                                     isRequestActive: isRequestActive, feedback: feedback, assignments: assignments))
        }
        let result = try outcome?.get() ?? PreviewBatchResult(failed: ids)
        feedback?.finish(result)
        return result
    }

    @MainActor
    static func movePreviewWindows(_ targets: [WindowInfo], to destination: ManagedSpaceDestination,
                                   request: WindowActionRequest, followsDestination: Bool,
                                   dismissPreviews: (() -> Void)?, mayFollow: () -> Bool,
                                   isRequestActive: @escaping @MainActor () -> Bool,
                                   feedback: ActionFeedbackHandle? = nil,
                                   assignments: [PreviewWindowIdentity: SpaceContentsPlan.Move] = [:]) async -> PreviewBatchResult
    {
        defer { feedback?.finishRemaining(.cancelled) }
        var succeeded: [WindowInfo] = []
        var failed: [PreviewWindowIdentity] = []
        var pending = Set<PreviewWindowIdentity>()
        var cancellations: [@MainActor () -> Void] = []
        var requestedMove = false
        defer { for cancel in cancellations {
            cancel()
        } }
        let topology = WindowSpaces.managedDisplays()
        for window in targets {
            guard !Task.isCancelled, isRequestActive() else { return PreviewBatchResult(succeeded: succeeded, failed: failed) }
            let identity = PreviewWindowIdentity(window)
            guard request.contains(identity) else { failed.append(identity); feedback?.finish(identity, .failed); continue }
            let assignment = assignments[identity]
            let targetDestination = assignment?.destination ?? destination
            let sourceError = await WindowSpaces.validateMoveSourceConfirmed(window, in: topology)
            guard !Task.isCancelled, isRequestActive() else { return PreviewBatchResult(succeeded: succeeded, failed: failed) }
            let sources = sourceError == nil ? WindowSpaces.sourceSpaceIDs(for: window) : []
            if let expected = assignment?.sourceID, !sources.contains(expected) {
                failed.append(identity); feedback?.finish(identity, .failed); continue
            }
            if sourceError == nil,
               sources.contains(targetDestination.space.id), targetDestination.space.kind == .desktop
            {
                succeeded.append(window)
                continue
            }
            requestedMove = true
            pending.insert(identity)
            let cancel = WindowUtil.performConfirmedSpaceMove(window, to: targetDestination, dismissPreviews: nil,
                                                              switchToDestination: false,
                                                              isRequestActive: { isRequestActive() && request.contains(identity) })
            { success in
                pending.remove(identity)
                feedback?.finish(identity, success ? .completed : .failed)
                if success { succeeded.append(window) } else { failed.append(identity) }
            }
            if let cancel { cancellations.append(cancel) }
        }
        guard requestedMove else {
            feedback?.finishRemaining(.failed)
            return PreviewBatchResult(failed: targets.map(PreviewWindowIdentity.init))
        }
        for window in succeeded {
            feedback?.finish(PreviewWindowIdentity(window), .completed)
        }
        for _ in 0 ..< 25 where !pending.isEmpty {
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return PreviewBatchResult(succeeded: succeeded, failed: failed) }
        }
        guard !Task.isCancelled, isRequestActive() else { return PreviewBatchResult(succeeded: succeeded, failed: failed) }
        failed.append(contentsOf: pending)
        for identity in pending {
            feedback?.finish(identity, .failed)
        }

        let succeededIdentities = Set(succeeded.map(PreviewWindowIdentity.init))
        if request.mayForeground, followsDestination, !succeeded.isEmpty, mayFollow(),
           let first = targets.first(where: { succeededIdentities.contains(PreviewWindowIdentity($0)) })
        {
            dismissPreviews?()
            var moved = WindowUtil.readCachedWindows(for: first.app.processIdentifier).first { $0.id == first.id } ?? first
            var canFocus = true
            if moved.app.isHidden { canFocus = await WindowUtil.setHiddenStateConfirmed(for: moved.app, isHidden: false) }
            if canFocus, moved.isMinimized {
                canFocus = await !(WindowUtil.setMinimizedWindowsConfirmed([moved], isMinimized: false)).isEmpty
                if canFocus { moved.isMinimized = false }
            }
            guard !Task.isCancelled, isRequestActive() else { return PreviewBatchResult(succeeded: succeeded, failed: failed) }
            if canFocus { canFocus = await moved.bringToFrontConfirmed() }
            if !canFocus { failed.append(PreviewWindowIdentity(first)) }
        }
        guard !Task.isCancelled, isRequestActive() else { return PreviewBatchResult(succeeded: succeeded, failed: failed) }
        return PreviewBatchResult(succeeded: succeeded, failed: failed)
    }

    @MainActor
    static func placeDraggedWindows(_ targets: [PreviewDragTarget], at pointer: CGPoint, on screen: NSScreen,
                                    destination: ManagedSpaceDestination,
                                    isRequestActive: @escaping @MainActor () -> Bool, feedback: ActionFeedbackHandle? = nil) async -> PreviewBatchResult
    {
        guard !Task.isCancelled else { return PreviewBatchResult() }
        if WindowActionRequest.current == nil {
            return await WindowActionRequest.run(targets.map { PreviewWindowIdentity($0.window) }) { request in
                var result = await placeDraggedWindows(targets.filter { request.contains(PreviewWindowIdentity($0.window)) }, at: pointer, on: screen,
                                                       destination: destination, isRequestActive: isRequestActive, feedback: feedback)
                result.failed += request.rejected
                return result
            } ?? PreviewBatchResult(failed: targets.map { PreviewWindowIdentity($0.window) })
        }
        defer { feedback?.finishRemaining(.cancelled) }
        guard let centers = PreviewDragLayout.centers(for: targets.map(\.originalFrame), at: pointer, within: screen.visibleFrame) else {
            feedback?.finishRemaining(.failed)
            return PreviewBatchResult(failed: targets.map { PreviewWindowIdentity($0.window) })
        }
        let centerByIdentity = Dictionary(uniqueKeysWithValues: zip(targets, centers).map { (PreviewWindowIdentity($0.0.window), $0.1) })
        return await performWindowGroupPlacement(targets.map(\.window), destination: destination,
                                                 raiseWindows: true, isRequestActive: isRequestActive, feedback: feedback)
        { window, _, _ in
            guard let center = centerByIdentity[PreviewWindowIdentity(window)] else { return .failed }
            return await placeWindowCentered(window, at: center, on: screen, isRequestActive: isRequestActive) != nil ? .confirmed : .failed
        }
    }

    static func autoTileTargets(from windows: [WindowInfo]) -> [WindowInfo] {
        let eligible = windows.filter { !$0.isWindowlessApp && $0.isFullscreen != true }
        guard Defaults[.tileOnlyWhatFits] else { return eligible }
        let capacity = min(6, max(1, Defaults[.maximumTilingRows])) * min(6, max(1, Defaults[.maximumTilingColumns]))
        return Array(eligible.prefix(capacity))
    }

    @MainActor
    static func tilePreviewWindows(_ windows: [WindowInfo], direction: PreviewTilingLayout.Direction,
                                   bringToFront: Bool? = nil, destination requestedDestination: ManagedSpaceDestination? = nil,
                                   on requestedScreen: NSScreen? = nil,
                                   isRequestActive: @escaping @MainActor () -> Bool = { true }, feedback: ActionFeedbackHandle? = nil) async -> PreviewBatchResult
    {
        guard !Task.isCancelled else { return PreviewBatchResult() }
        let windows = autoTileTargets(from: windows)
        if WindowActionRequest.current == nil {
            let requested = windows
            let result = await WindowActionRequest.run(requested.map(PreviewWindowIdentity.init)) { request in
                if let feedback {
                    for identity in request.rejected {
                        feedback.finish(identity, .failed)
                    }
                }
                let accepted = requested.filter { request.contains(PreviewWindowIdentity($0)) }
                var result = await tilePreviewWindows(accepted, direction: direction, bringToFront: bringToFront,
                                                      destination: requestedDestination, on: requestedScreen, isRequestActive: isRequestActive, feedback: feedback)
                result.failed += request.rejected
                return result
            } ?? PreviewBatchResult(failed: requested.map(PreviewWindowIdentity.init))
            feedback?.finish(result)
            return result
        }
        defer { feedback?.finishRemaining(.cancelled) }
        guard !Task.isCancelled, isRequestActive() else { return PreviewBatchResult() }
        guard !windows.isEmpty else { return PreviewBatchResult() }
        let pointer = NSEvent.mouseLocation
        let topology = WindowSpaces.managedDisplays()
        guard let spaceID = requestedDestination?.space.id ?? WindowSpaces.currentManagedSpaceID(mouseLocation: pointer),
              let destination = WindowSpaces.destination(forSpaceID: spaceID, in: topology),
              destination.space.kind == .desktop,
              let screen = requestedScreen ?? (requestedDestination == nil ? pointer.screen() : WindowSpaces.screen(forDisplayIdentifier: destination.display.identifier))
        else { feedback?.finishRemaining(.failed); return PreviewBatchResult(failed: windows.map(PreviewWindowIdentity.init)) }
        let maximumRows = Defaults[.maximumTilingRows]
        let maximumColumns = Defaults[.maximumTilingColumns]
        let tilingBounds = screen.snappingFrame
        let capacity = min(6, max(1, maximumRows)) * min(6, max(1, maximumColumns))
        let targets = windows
        let linksEnabled = Defaults[.linkTiledWindowsWhenResizing] && capacity > 1
        var restoreFrames: [PreviewWindowIdentity: CGRect] = [:]
        if linksEnabled {
            for window in targets where !window.isWindowlessApp && !window.app.isTerminated {
                guard !Task.isCancelled, isRequestActive() else { return PreviewBatchResult() }
                let record = await WindowSnapRegistry.existing?.liveRecord(for: window)
                let frame = record == nil ? await window.readWindowFrame() : record?.restoreFrame
                restoreFrames[PreviewWindowIdentity(window)] = frame
            }
        }
        var batches: [Int: UUID] = [:]
        var registrations: [(WindowInfo, CGRect, UUID)] = []
        var frames: [CGRect?]?
        let result = await performWindowGroupPlacement(targets, destination: destination,
                                                       raiseWindows: bringToFront ?? Defaults[.moveResizeBringToForeground],
                                                       isRequestActive: isRequestActive, feedback: feedback)
        { window, index, count in
            if frames == nil {
                frames = PreviewTilingLayout.frames(count: count, in: tilingBounds, direction: direction,
                                                    maximumRows: maximumRows, maximumColumns: maximumColumns)
            }
            guard let frame = frames?[index] else { return .confirmed }
            let placement = await window.setWindowFrameResult(frame, on: screen, isRequestActive: isRequestActive)
            if placement == .confirmed, linksEnabled, let restoreFrame = restoreFrames[PreviewWindowIdentity(window)] {
                let batch = index / capacity
                let token = batches[batch] ?? UUID()
                batches[batch] = token
                registrations.append((window, restoreFrame, token))
            }
            return placement
        }
        if !Task.isCancelled, isRequestActive(), Defaults[.linkTiledWindowsWhenResizing], !registrations.isEmpty {
            let registry = WindowSnapRegistry.shared
            for (window, restoreFrame, batch) in registrations {
                guard !Task.isCancelled, isRequestActive() else { break }
                await registry.snapped(window, restoreFrame: restoreFrame, origin: .tiling(batch), confirmedDestination: destination)
            }
        }
        return result
    }

    @MainActor
    private static func performWindowGroupPlacement(_ windows: [WindowInfo], destination: ManagedSpaceDestination,
                                                    raiseWindows: Bool, isRequestActive: @escaping @MainActor () -> Bool, feedback: ActionFeedbackHandle? = nil,
                                                    place: (WindowInfo, Int, Int) async -> WindowFramePlacementResult) async -> PreviewBatchResult
    {
        defer { feedback?.finishRemaining(.cancelled) }
        var result = PreviewBatchResult()
        var raised = 0
        defer {
            if Defaults[.debugMode] {
                DebugLogger.log("WindowGroupPlacement", details: "requested: \(windows.map(\.id)), foreground: \(raiseWindows), raised: \(raised), cancelled: \(Task.isCancelled || !isRequestActive())")
            }
        }
        let topology = WindowSpaces.managedDisplays()
        var ready = Set<PreviewWindowIdentity>()
        var pending = Set<PreviewWindowIdentity>()
        var cancellations: [@MainActor () -> Void] = []
        defer { for cancel in cancellations {
            cancel()
        } }

        for window in windows {
            guard !Task.isCancelled, isRequestActive() else { return result }
            let identity = PreviewWindowIdentity(window)
            let sourceError = await WindowSpaces.validateMoveSourceConfirmed(window, in: topology)
            guard !Task.isCancelled, isRequestActive() else { return result }
            guard !window.app.isTerminated, sourceError == nil else {
                result.failed.append(identity)
                feedback?.finish(identity, .failed)
                continue
            }
            if WindowSpaces.sourceSpaceIDs(for: window).contains(destination.space.id) {
                ready.insert(identity)
                continue
            }
            pending.insert(identity)
            if let cancel = performConfirmedSpaceMove(window, to: destination, dismissPreviews: nil,
                                                      switchToDestination: false, isRequestActive: isRequestActive,
                                                      completion: { success in
                                                          pending.remove(identity)
                                                          if success { ready.insert(identity) } else { result.failed.append(identity); feedback?.finish(identity, .failed) }
                                                      })
            { cancellations.append(cancel) }
        }
        for _ in 0 ..< 25 where !pending.isEmpty {
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return result }
        }
        guard !Task.isCancelled, isRequestActive() else { return result }
        result.failed.append(contentsOf: pending)
        for identity in result.failed {
            feedback?.finish(identity, .failed)
        }
        for cancel in cancellations {
            cancel()
        }
        cancellations.removeAll()

        var revealedWindows: [WindowInfo] = []
        for original in windows where ready.contains(PreviewWindowIdentity(original)) {
            guard !Task.isCancelled, isRequestActive() else { return result }
            var window = original
            var revealed = true
            if window.app.isHidden { revealed = await setHiddenStateConfirmed(for: window.app, isHidden: false) }
            let minimized = revealed && !window.isMinimized ? await window.readMinimizedState() : nil
            guard !Task.isCancelled, isRequestActive() else { return result }
            if revealed, window.isMinimized || minimized == true {
                revealed = await !setMinimizedWindowsConfirmed([window], isMinimized: false).isEmpty
                if revealed { window.isMinimized = false }
            }
            guard !Task.isCancelled, isRequestActive() else { return result }
            if revealed { revealedWindows.append(window) }
            else { result.failed.append(PreviewWindowIdentity(window)); feedback?.finish(PreviewWindowIdentity(window), .failed) }
        }
        var windowsToRaise: [WindowInfo] = []
        for (index, window) in revealedWindows.enumerated() {
            guard !Task.isCancelled, isRequestActive() else { return result }
            let placement = await place(window, index, revealedWindows.count)
            guard !Task.isCancelled, isRequestActive() else { return result }
            if placement == .confirmed { result.succeeded.append(window) }
            else { result.failed.append(PreviewWindowIdentity(window)) }
            if placement == .failed { feedback?.finish(PreviewWindowIdentity(window), .failed) }
            else if !raiseWindows { feedback?.finish(PreviewWindowIdentity(window), placement == .confirmed ? .completed : .failed) }
            if placement != .failed { windowsToRaise.append(window) }
            await Task.yield()
        }
        if raiseWindows {
            // Raise in reverse check order so the leading checked window finishes in front.
            for window in windowsToRaise.reversed() {
                guard !Task.isCancelled, isRequestActive() else { return result }
                guard WindowActionRequest.current?.mayForeground != false else { continue }
                if await !window.bringToFrontConfirmed() {
                    let identity = PreviewWindowIdentity(window)
                    if !result.failed.contains(identity) { result.failed.append(identity) }
                } else { raised += 1 }
                let identity = PreviewWindowIdentity(window)
                feedback?.finish(identity, result.failed.contains(identity) ? .failed : .completed)
            }
        }
        return result
    }

    @MainActor
    static func placeWindowCentered(
        _ windowInfo: WindowInfo,
        at pointerLocation: CGPoint,
        on screen: NSScreen,
        isRequestActive: @escaping @MainActor () -> Bool = { true }
    ) async -> WindowPlacementResult? {
        if WindowActionRequest.current == nil {
            return await WindowActionRequest.run([PreviewWindowIdentity(windowInfo)]) { _ in
                await placeWindowCentered(windowInfo, at: pointerLocation, on: screen, isRequestActive: isRequestActive)
            } ?? nil
        }
        guard WindowActionRequest.current?.contains(PreviewWindowIdentity(windowInfo)) == true else { return nil }
        guard !Task.isCancelled, isRequestActive(), !windowInfo.isWindowlessApp else { return nil }
        let target = windowInfo.frameTarget
        let visibleFrame = screen.visibleFrame
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let screenIdentifier = screen.uniqueIdentifier()
        let result = await WindowFrameTransactions.run(for: target.ownerPID) { cancellation in
            target.placeCentered(at: pointerLocation, within: visibleFrame, primaryMaxY: primaryMaxY, cancellation: cancellation)
        }
        guard !Task.isCancelled, isRequestActive(), result?.applied == true, let frame = result?.frame else {
            if result?.attempted == true {
                scheduleCachedWindowMetadataReconciliation(pid: windowInfo.app.processIdentifier, windowID: windowInfo.id)
                if !Task.isCancelled, isRequestActive(), result?.accepted == true {
                    refreshCachedPreviewAfterProgrammaticResize(windowInfo, targetScreenIdentifier: nil)
                }
            }
            return nil
        }
        let actualFrame = CGRect(x: frame.minX, y: primaryMaxY - frame.maxY, width: frame.width, height: frame.height)
        updateCachedWindowState(
            windowInfo,
            spaceID: windowInfo.id.cgsSpaces().first.map { Int($0) } ?? windowInfo.spaceID,
            screenIdentifier: .some(screenIdentifier),
            frame: actualFrame
        )
        scheduleCachedWindowMetadataReconciliation(pid: windowInfo.app.processIdentifier, windowID: windowInfo.id)
        scheduleForcedPreviewRecapture(
            pid: windowInfo.app.processIdentifier,
            windowID: windowInfo.id,
            fallbackWindowInfo: windowInfo,
            targetScreenIdentifier: screenIdentifier,
            delayNanos: programmaticResizeRefreshDelayNanos
        )
        return WindowPlacementResult(frame: actualFrame, screenIdentifier: screenIdentifier)
    }

    @MainActor
    @discardableResult
    static func springLoadWindow(_ windowInfo: WindowInfo) async -> Bool {
        guard !Task.isCancelled, !windowInfo.isWindowlessApp, !windowInfo.app.isTerminated else { return false }
        guard await revealWindowConfirmed(windowInfo, checkingLiveState: true) else { return false }
        return await windowInfo.bringToFrontConfirmed()
    }

    @discardableResult
    static func exitFullScreenWithoutActivation(_ windowInfo: WindowInfo) async -> Bool {
        await changeFullscreenConfirmed(windowInfo, reconciliationDelayNanos: fullscreenExitMetadataReconciliationDelayNanos)
    }

    private static func reconcileCachedWindowMetadata(pid: pid_t, windowID: CGWindowID) {
        guard let cachedWindow = desktopSpaceWindowCacheManager.readCache(pid: pid).first(where: { $0.id == windowID }),
              isProcessAlive(pid)
        else { return }

        let title = try? cachedWindow.axElement.title()
        let minimized = try? cachedWindow.axElement.isMinimized()
        let fullscreen = try? cachedWindow.axElement.isFullscreen()
        let position = try? cachedWindow.axElement.position()
        let spaceID = windowID.cgsSpaces().first.map { Int($0) }
        SpaceNumberResolver.refreshIfNeeded(for: spaceID)
        let screenIdentifier = position.flatMap { screenIdentifier(forWindowAt: $0) }
        let hidden = cachedWindow.app.isHidden
        guard title != nil || minimized != nil || fullscreen != nil || position != nil || spaceID != nil else { return }

        desktopSpaceWindowCacheManager.updateCache(pid: pid) { windowSet in
            guard let existing = windowSet.first(where: { $0.id == windowID }) else { return }
            var updated = existing

            if let title, !title.isEmpty {
                updated.windowName = title
            }
            if let minimized {
                updated.isMinimized = minimized
            }
            if let fullscreen {
                updated.isFullscreen = fullscreen
            }
            if let spaceID {
                updated.spaceID = spaceID
            }
            if let screenIdentifier {
                updated.screenIdentifier = screenIdentifier
            }
            updated.isHidden = hidden

            guard updated.viewSnapshot != existing.viewSnapshot else { return }
            windowSet.remove(existing)
            windowSet.insert(updated)
        }
    }

    static func scheduleCachedWindowMetadataReconciliation(
        pid: pid_t,
        windowID: CGWindowID,
        delayNanos: UInt64 = WindowAction.fullscreenConfirmationDelay
    ) {
        let key = "\(pid)-\(windowID)"

        metadataReconciliationLock.lock()
        pendingMetadataReconciliations[key]?.task.cancel()
        let token = UUID()
        let task = Task(priority: .utility) {
            defer {
                removePendingMetadataReconciliation(key: key, token: token)
            }

            do {
                try await Task.sleep(nanoseconds: delayNanos)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            reconcileCachedWindowMetadata(pid: pid, windowID: windowID)
        }
        pendingMetadataReconciliations[key] = PendingWindowRefresh(token: token, task: task)
        metadataReconciliationLock.unlock()
    }

    private static func removePendingMetadataReconciliation(key: String, token: UUID) {
        metadataReconciliationLock.lock()
        defer { metadataReconciliationLock.unlock() }
        if pendingMetadataReconciliations[key]?.token == token {
            pendingMetadataReconciliations.removeValue(forKey: key)
        }
    }

    static func scheduleAllCachedWindowMetadataReconciliations() {
        for window in desktopSpaceWindowCacheManager.getAllWindows() where !window.isWindowlessApp {
            scheduleCachedWindowMetadataReconciliation(
                pid: window.app.processIdentifier,
                windowID: window.id
            )
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
        pendingProgrammaticResizeRefreshes[refreshKey] = PendingWindowRefresh(token: token, task: refreshTask)
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

    @discardableResult
    static func moveWindow(_ windowInfo: WindowInfo, toManagedSpace targetSpaceID: CGSSpaceID) -> Bool {
        let parent = WindowActionRequest.current
        let identity = PreviewWindowIdentity(windowInfo)
        let request = parent ?? WindowActionOwnership.shared.begin([identity], replacingSingles: false)
        defer { if parent == nil { request.finish() } }
        guard request.contains(identity) else { return false }
        guard !windowInfo.isWindowlessApp else {
            return false
        }

        let moved = WindowSpaces.move(windowID: windowInfo.id, toManagedSpace: targetSpaceID)
        if moved {
            updateCachedWindowState(windowInfo, spaceID: .some(Int(targetSpaceID)))
        }
        return moved
    }

    @discardableResult
    static func moveWindowToCurrentManagedSpace(_ windowInfo: WindowInfo, mouseLocation: CGPoint = NSEvent.mouseLocation) -> Bool {
        guard let targetSpaceID = WindowSpaces.currentManagedSpaceID(mouseLocation: mouseLocation) else {
            return false
        }
        return moveWindow(windowInfo, toManagedSpace: targetSpaceID)
    }

    @discardableResult
    static func moveWindowConfirmed(
        _ windowInfo: WindowInfo,
        toManagedSpace targetSpaceID: CGSSpaceID,
        feedback: ActionFeedbackHandle? = nil,
        completion: @escaping @MainActor (Bool) -> Void
    ) -> Task<Void, Never>? {
        let parent = WindowActionRequest.current
        let identity = PreviewWindowIdentity(windowInfo)
        let request = parent ?? WindowActionOwnership.shared.begin([identity], replacingSingles: false)
        guard request.contains(identity) else {
            feedback?.finish(identity, .failed)
            Task { @MainActor in completion(false) }
            return nil
        }
        guard !windowInfo.isWindowlessApp else {
            if parent == nil { request.finish() }
            Task { @MainActor in completion(false) }
            return nil
        }

        let key = "\(windowInfo.app.processIdentifier)-\(windowInfo.id)"
        managedSpaceMoveLock.lock()
        pendingManagedSpaceMoves[key]?.task.cancel()
        pendingManagedSpaceMoves.removeValue(forKey: key)
        managedSpaceMoveLock.unlock()

        guard WindowSpaces.move(windowID: windowInfo.id, toManagedSpace: targetSpaceID) else {
            if parent == nil { request.finish() }
            Task { @MainActor in completion(false) }
            return nil
        }

        let token = UUID()
        let task = Task(priority: .utility) {
            defer {
                if parent == nil { request.finish() }
                removePendingManagedSpaceMove(key: key, token: token)
            }

            for delay in [60_000_000, 140_000_000, 300_000_000, 600_000_000] as [UInt64] {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    feedback?.finish(PreviewWindowIdentity(windowInfo), .cancelled)
                    return
                }
                guard !Task.isCancelled, request.contains(identity) else { feedback?.finish(PreviewWindowIdentity(windowInfo), .cancelled); return }

                if windowInfo.id.cgsSpaces().contains(targetSpaceID) {
                    guard !Task.isCancelled, request.contains(identity) else { feedback?.finish(PreviewWindowIdentity(windowInfo), .cancelled); return }
                    updateCachedWindowState(windowInfo, spaceID: .some(Int(targetSpaceID)))
                    scheduleCachedWindowMetadataReconciliation(
                        pid: windowInfo.app.processIdentifier,
                        windowID: windowInfo.id
                    )
                    await completion(true)
                    return
                }
            }

            DebugLogger.log(
                "WindowUtil.moveWindowConfirmed",
                details: "Move confirmation timed out for window \(windowInfo.id), Space \(targetSpaceID)"
            )
            await completion(false)
        }
        managedSpaceMoveLock.lock()
        pendingManagedSpaceMoves[key] = PendingWindowRefresh(token: token, task: task)
        managedSpaceMoveLock.unlock()
        if parent == nil { request.onSuperseded { task.cancel() } }
        return task
    }

    @MainActor
    @discardableResult
    static func performConfirmedSpaceMove(
        _ windowInfo: WindowInfo,
        to destination: ManagedSpaceDestination,
        dismissPreviews: (() -> Void)?,
        switchToDestination: Bool? = nil,
        isRequestActive: @escaping () -> Bool = { true },
        feedback: ActionFeedbackHandle? = nil,
        completion: ((Bool) -> Void)? = nil
    ) -> (@MainActor () -> Void)? {
        guard !Task.isCancelled, isRequestActive() else {
            feedback?.finish(PreviewWindowIdentity(windowInfo), .cancelled)
            return nil
        }
        let parent = WindowActionRequest.current
        let identity = PreviewWindowIdentity(windowInfo)
        let request = parent ?? WindowActionOwnership.shared.begin([identity])
        guard request.contains(identity) else { feedback?.finish(identity, .failed); completion?(false); return nil }
        let callerIsActive = isRequestActive
        let isRequestActive = { callerIsActive() && request.contains(identity) }
        guard !Task.isCancelled, isRequestActive() else {
            if parent == nil { request.finish() }
            feedback?.finish(PreviewWindowIdentity(windowInfo), .cancelled)
            return nil
        }
        let key = "\(windowInfo.app.processIdentifier)-\(windowInfo.id)"
        pendingManagedSpaceFollows.removeValue(forKey: key)?.task.cancel()
        guard WindowSpaces.validateMove(windowInfo, to: destination) == nil else {
            if parent == nil { request.finish() }
            feedback?.finish(PreviewWindowIdentity(windowInfo), .failed); completion?(false)
            return nil
        }

        var awaitingRefusalCallback = false
        var cancelled = false
        var followTask: Task<Void, Never>?
        var moveTask: Task<Void, Never>?
        let requestToken = UUID()
        let validationTask = WindowActionRequest.$current.withValue(request) { Task { @MainActor in
            defer { if parent == nil, !awaitingRefusalCallback { request.finish() } }
            await request.waitForPredecessors()
            defer {
                if Task.isCancelled || !isRequestActive() {
                    if pendingManagedSpaceFollows[key]?.token == requestToken { pendingManagedSpaceFollows.removeValue(forKey: key) }
                    feedback?.finish(PreviewWindowIdentity(windowInfo), .cancelled)
                }
            }
            guard !cancelled, !Task.isCancelled, isRequestActive() else { return }
            let topology = WindowSpaces.managedDisplays()
            let error = await WindowSpaces.validateMoveConfirmed(windowInfo, to: destination, in: topology)
            guard !cancelled, !Task.isCancelled, isRequestActive(), pendingManagedSpaceFollows[key]?.token == requestToken else { return }
            guard error == nil else {
                pendingManagedSpaceFollows.removeValue(forKey: key)
                feedback?.finish(PreviewWindowIdentity(windowInfo), .failed); completion?(false)
                return
            }
            var following = false
            moveTask = moveWindowConfirmed(windowInfo, toManagedSpace: destination.space.id, feedback: feedback) { success in
                guard !cancelled, !Task.isCancelled, isRequestActive(), pendingManagedSpaceFollows[key]?.token == requestToken else {
                    if parent == nil, awaitingRefusalCallback { request.finish() }
                    feedback?.finish(PreviewWindowIdentity(windowInfo), .cancelled); return
                }
                guard success else {
                    if parent == nil { request.finish() }
                    pendingManagedSpaceFollows.removeValue(forKey: key)
                    feedback?.finish(PreviewWindowIdentity(windowInfo), .failed); completion?(false)
                    return
                }

                if switchToDestination ?? Defaults[.switchToDestinationSpaceAfterMoving] {
                    following = true
                    dismissPreviews?()
                    let movedWindow = windowInfo
                    let token = requestToken
                    let task = Task { @MainActor in
                        defer {
                            feedback?.finish(PreviewWindowIdentity(windowInfo), .cancelled)
                            if pendingManagedSpaceFollows[key]?.token == token {
                                pendingManagedSpaceFollows.removeValue(forKey: key)
                            }
                        }
                        guard !cancelled, isRequestActive(), !Task.isCancelled else { return }
                        guard WindowSpaces.sourceSpaceIDs(for: movedWindow).contains(destination.space.id) else {
                            feedback?.finish(PreviewWindowIdentity(windowInfo), .failed); completion?(false)
                            return
                        }
                        guard await revealWindowConfirmed(movedWindow), !cancelled, isRequestActive(), !Task.isCancelled else {
                            feedback?.finish(PreviewWindowIdentity(windowInfo), Task.isCancelled || cancelled ? .cancelled : .failed)
                            if !cancelled, !Task.isCancelled, isRequestActive() { completion?(false) }
                            return
                        }
                        let activated = if request.mayForeground { await movedWindow.bringToFrontConfirmed() } else { true }
                        guard !cancelled, isRequestActive(), !Task.isCancelled else { return }
                        feedback?.finish(PreviewWindowIdentity(windowInfo), activated ? .completed : .failed)
                        completion?(activated)
                    }
                    pendingManagedSpaceFollows[key] = PendingWindowRefresh(token: token, task: task)
                    followTask = task
                    return
                }
                pendingManagedSpaceFollows.removeValue(forKey: key)
                feedback?.finish(PreviewWindowIdentity(windowInfo), .completed)
                completion?(true)
            }
            // A refused native request returns nil and schedules its failure callback separately.
            guard let acceptedMove = moveTask else { awaitingRefusalCallback = true; return }
            await withTaskCancellationHandler {
                await acceptedMove.value
            } onCancel: {
                acceptedMove.cancel()
            }
            if !following, pendingManagedSpaceFollows[key]?.token == requestToken {
                pendingManagedSpaceFollows.removeValue(forKey: key)
                feedback?.finish(PreviewWindowIdentity(windowInfo), .cancelled)
            }
            if following, let followTask { await followTask.value }
        } }
        followTask = validationTask
        pendingManagedSpaceFollows[key] = PendingWindowRefresh(token: requestToken, task: validationTask)
        if parent == nil {
            request.onSuperseded {
                validationTask.cancel()
                Task { @MainActor in moveTask?.cancel(); followTask?.cancel() }
            }
        }
        // Capture this request's tasks, never cancel a newer request by window key.
        return {
            cancelled = true
            feedback?.finish(PreviewWindowIdentity(windowInfo), .cancelled)
            moveTask?.cancel()
            followTask?.cancel()
            if pendingManagedSpaceFollows[key]?.token == requestToken { pendingManagedSpaceFollows.removeValue(forKey: key) }
        }
    }

    @MainActor private static var pendingManagedSpaceSwitchFeedback: ActionFeedbackHandle?

    @MainActor
    @discardableResult
    static func switchToManagedSpace(
        _ destination: ManagedSpaceDestination,
        feedback: ActionFeedbackHandle? = nil,
        completion: @escaping (Bool) -> Void
    ) -> (@MainActor () -> Void)? {
        cancelPendingManagedSpaceSwitch()
        func finish(_ success: Bool) {
            feedback?.finishRemaining(success ? .completed : .failed)
            if pendingManagedSpaceSwitchFeedback?.token == feedback?.token { pendingManagedSpaceSwitchFeedback = nil }
            completion(success)
        }
        guard destination.space.kind == .desktop || destination.space.kind == .fullscreen,
              let targetScreen = WindowSpaces.screen(forDisplayIdentifier: destination.display.identifier)
        else {
            finish(false)
            return nil
        }

        let topology = WindowSpaces.managedDisplays()
        guard let currentDestination = WindowSpaces.destination(forSpaceID: destination.space.id, in: topology),
              currentDestination.space.kind == destination.space.kind,
              currentDestination.display.currentSpaceID != destination.space.id
        else {
            finish(false)
            return nil
        }

        moveCursorToDisplayIfNeeded(targetScreen)

        let ownPID = ProcessInfo.processInfo.processIdentifier
        evictTerminatedApps()
        let candidates = desktopSpaceWindowCacheManager.getAllWindows().filter { window in
            !window.isWindowlessApp &&
                window.id != 0 &&
                window.app.processIdentifier != ownPID &&
                !window.app.isTerminated &&
                !window.app.isHidden &&
                !window.isMinimized &&
                WindowSpaces.sourceSpaceIDs(for: window) == Set([destination.space.id])
        }

        let token = UUID()
        let orderedCandidates = spaceSwitchCandidatesByRecency(candidates)
        pendingManagedSpaceSwitchFeedback = feedback
        let task = Task { @MainActor in
            defer {
                if pendingManagedSpaceSwitch?.token == token {
                    pendingManagedSpaceSwitch = nil
                }
            }
            for candidate in orderedCandidates {
                guard !Task.isCancelled, pendingManagedSpaceSwitch?.token == token else { return }
                let matchesDestinationKind = await Task.detached(priority: .userInitiated) {
                    let isFullscreen = candidate.isFullscreen == true || (try? candidate.axElement.isFullscreen()) == true
                    return !candidate.isEffectivelyHiddenForUI &&
                        (destination.space.kind == .fullscreen ? isFullscreen : !isFullscreen)
                }.value
                guard !Task.isCancelled, pendingManagedSpaceSwitch?.token == token else { return }
                guard matchesDestinationKind, !candidate.app.isTerminated, !candidate.app.isHidden,
                      WindowSpaces.sourceSpaceIDs(for: candidate).contains(destination.space.id)
                else { continue }
                let activation = await candidate.bringToFrontResult()
                guard !Task.isCancelled, pendingManagedSpaceSwitch?.token == token else { return }
                if activation == .cancelled {
                    finish(false)
                    return
                }
                if activation == .succeeded {
                    finish(true)
                    return
                }
            }

            guard !Task.isCancelled, pendingManagedSpaceSwitch?.token == token else { return }
            if destination.space.kind == .desktop {
                TransientSpaceAnchorController.shared.switchTo(destination, on: targetScreen, transitionID: token, completion: finish)
            } else {
                finish(false)
            }
        }
        pendingManagedSpaceSwitch = PendingWindowRefresh(token: token, task: task)
        return {
            feedback?.finishRemaining(.cancelled)
            task.cancel()
            if pendingManagedSpaceSwitch?.token == token {
                pendingManagedSpaceSwitch = nil
            }
            TransientSpaceAnchorController.shared.cancelPending(transitionID: token)
        }
    }

    @MainActor
    static func cancelPendingManagedSpaceSwitch() {
        pendingManagedSpaceSwitchFeedback?.finishRemaining(.cancelled)
        pendingManagedSpaceSwitchFeedback = nil
        pendingManagedSpaceSwitch?.task.cancel()
        pendingManagedSpaceSwitch = nil
        TransientSpaceAnchorController.shared.cancelPending()
    }

    @MainActor
    private static func moveCursorToDisplayIfNeeded(_ targetScreen: NSScreen) {
        guard let mouseLocation = CGEvent(source: nil)?.location else { return }
        let currentScreen = NSScreen.screenFromQuartzPoint(mouseLocation)
        guard currentScreen != targetScreen else { return }
        let target = CGPoint(x: targetScreen.cgFrame.midX, y: targetScreen.cgFrame.midY)
        CGWarpMouseCursorPosition(target)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private static func spaceSwitchCandidatesByRecency(_ windows: [WindowInfo]) -> [WindowInfo] {
        let descriptions = (CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: AnyObject]]) ?? []
        let rankByID: [CGWindowID: Int] = Dictionary(uniqueKeysWithValues: descriptions.enumerated().compactMap { index, entry in
            guard let number = entry[kCGWindowNumber as String] as? NSNumber else { return nil }
            return (CGWindowID(number.uint32Value), index)
        })

        return windows.sorted { first, second in
            if first.lastAccessedTime != second.lastAccessedTime {
                return first.lastAccessedTime > second.lastAccessedTime
            }
            switch (rankByID[first.id], rankByID[second.id]) {
            case let (firstRank?, secondRank?) where firstRank != secondRank:
                return firstRank < secondRank
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if first.app.processIdentifier != second.app.processIdentifier {
                    return first.app.processIdentifier < second.app.processIdentifier
                }
                return first.id < second.id
            }
        }
    }

    private static func removePendingManagedSpaceMove(key: String, token: UUID) {
        managedSpaceMoveLock.lock()
        defer { managedSpaceMoveLock.unlock() }
        if pendingManagedSpaceMoves[key]?.token == token {
            pendingManagedSpaceMoves.removeValue(forKey: key)
        }
    }

    @discardableResult
    static func moveAppWindowsToCurrentManagedSpace(for app: NSRunningApplication, mouseLocation: CGPoint = NSEvent.mouseLocation) -> Bool {
        guard let targetSpaceID = WindowSpaces.currentManagedSpaceID(mouseLocation: mouseLocation) else {
            return false
        }

        let windows = desktopSpaceWindowCacheManager.readCache(pid: app.processIdentifier)
        let appWindows = windows.filter { !$0.isWindowlessApp }
        let mostRecentWindow = appWindows.max { first, second in
            first.lastAccessedTime < second.lastAccessedTime
        }

        var movedAnyWindow = false
        for window in appWindows {
            let moved = WindowSpaces.move(windowID: window.id, toManagedSpace: targetSpaceID)
            if moved {
                updateCachedWindowState(window, spaceID: .some(Int(targetSpaceID)))
                movedAnyWindow = true
            }
        }

        if movedAnyWindow, let mostRecentWindow {
            Task { @MainActor in
                guard await revealWindowConfirmed(mostRecentWindow), !Task.isCancelled else { return }
                _ = await mostRecentWindow.bringToFrontConfirmed()
            }
        }

        return movedAnyWindow
    }
}

@MainActor
private final class TransientSpaceAnchorController {
    static let shared = TransientSpaceAnchorController()

    private final class AnchorWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private var transitionID = UUID()
    private var anchorWindow: AnchorWindow?
    private var registeredWindowID: CGWindowID?
    private var transitionTask: Task<Void, Never>?
    private var spaceObserver: NSObjectProtocol?
    private var destination: ManagedSpaceDestination?
    private var completion: ((Bool) -> Void)?
    private var didActivateAnchor = false

    func switchTo(
        _ destination: ManagedSpaceDestination,
        on screen: NSScreen,
        transitionID: UUID,
        completion: @escaping (Bool) -> Void
    ) {
        cancelPending()

        self.transitionID = transitionID
        self.destination = destination
        self.completion = completion

        let frame = CGRect(x: screen.frame.midX, y: screen.frame.midY, width: 1, height: 1)
        let window = AnchorWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.alphaValue = 0
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.sharingType = .none
        window.collectionBehavior = []
        window.animationBehavior = .none
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.orderFront(nil)

        let windowID = CGWindowID(window.windowNumber)
        guard windowID != 0 else {
            window.close()
            finish(false, transitionID: transitionID)
            return
        }

        anchorWindow = window
        registeredWindowID = windowID
        WindowUtil.registerInternalWindow(windowID)
        window.alphaValue = 0.01

        guard WindowSpaces.move(windowID: windowID, toManagedSpace: destination.space.id) else {
            finish(false, transitionID: transitionID)
            return
        }

        transitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in [60_000_000, 140_000_000, 300_000_000, 600_000_000] as [UInt64] {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                guard self.transitionID == transitionID else { return }
                if windowID.cgsSpaces().contains(destination.space.id) {
                    activateAnchor(transitionID: transitionID)
                    return
                }
            }
            finish(false, transitionID: transitionID)
        }
    }

    func cancelPending() {
        cleanup()
    }

    func cancelPending(transitionID: UUID) {
        guard self.transitionID == transitionID else { return }
        cleanup()
    }

    private func activateAnchor(transitionID: UUID) {
        guard self.transitionID == transitionID, let anchorWindow else { return }
        transitionTask?.cancel()
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.confirmActiveSpace(transitionID: transitionID)
            }
        }

        didActivateAnchor = true
        NSApp.activate(ignoringOtherApps: true)
        anchorWindow.makeKeyAndOrderFront(nil)

        transitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in [100_000_000, 200_000_000, 400_000_000, 800_000_000] as [UInt64] {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                guard self.transitionID == transitionID else { return }
                if confirmActiveSpace(transitionID: transitionID) { return }
            }
            finish(false, transitionID: transitionID)
        }
    }

    @discardableResult
    private func confirmActiveSpace(transitionID: UUID) -> Bool {
        guard self.transitionID == transitionID, let destination else { return false }
        let isActive = WindowSpaces.managedDisplays().contains { display in
            display.identifier == destination.display.identifier && display.currentSpaceID == destination.space.id
        }
        if isActive {
            finish(true, transitionID: transitionID)
        }
        return isActive
    }

    private func finish(_ success: Bool, transitionID: UUID) {
        guard self.transitionID == transitionID else { return }
        let completion = completion
        cleanup()
        completion?(success)
    }

    private func cleanup() {
        let shouldDeactivate = didActivateAnchor
        didActivateAnchor = false
        transitionID = UUID()
        transitionTask?.cancel()
        transitionTask = nil
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        spaceObserver = nil
        anchorWindow?.orderOut(nil)
        anchorWindow?.close()
        anchorWindow = nil
        if let registeredWindowID {
            WindowUtil.unregisterInternalWindow(registeredWindowID)
        }
        registeredWindowID = nil
        destination = nil
        completion = nil
        if shouldDeactivate {
            NSApp.deactivate()
        }
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
        guard shouldCaptureWindowImages() else {
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
        let capturedWindows = CGSHWCaptureWindowList(
            connectionID,
            &windowIDUInt32,
            1,
            [.ignoreGlobalClipShape, .fullSize, qualityOption]
        ) as? [CGImage]
        let capturedImage = capturedWindows?.first
        let entry = (CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: AnyObject]])?.first
        let bounds = (entry?[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
        let transparent = capturedImage.map(isFullyTransparent) ?? false
        let clipped = capturedImage.map { isClippedBySpaceTransition($0, bounds: bounds, windowID: windowID) } ?? false
        logCapture(windowID: windowID, pid: pid, title: windowTitle, image: capturedImage, transparent: transparent, clipped: clipped, entry: entry, quality: qualityOption)
        guard let capturedImage, !transparent, !clipped else {
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

    private static func isClippedBySpaceTransition(_ image: CGImage, bounds: CGRect?, windowID: CGWindowID) -> Bool {
        guard let bounds, bounds.width > 0, bounds.height > 0, image.height > 0 else { return false }
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        let boundsAspect = bounds.width / bounds.height
        guard abs(imageAspect - boundsAspect) / boundsAspect > 0.02 else { return false }
        let spaces = Set(windowID.cgsSpaces().map { Int($0) })
        return !spaces.isEmpty && spaces.isDisjoint(with: currentActiveSpaceIDs())
    }

    private static func logCapture(windowID: CGWindowID, pid: pid_t, title: String?, image: CGImage?, transparent: Bool, clipped: Bool, entry: [String: AnyObject]?, quality: CGSWindowCaptureOptions) {
        guard Defaults[.debugMode] else { return }
        let bounds = (entry?[kCGWindowBounds as String] as? [String: AnyObject]).map {
            "\(($0["Width"] as? NSNumber)?.intValue ?? -1)x\(($0["Height"] as? NSNumber)?.intValue ?? -1)@\(($0["X"] as? NSNumber)?.intValue ?? -1),\(($0["Y"] as? NSNumber)?.intValue ?? -1)"
        } ?? "none"
        let onscreen = (entry?[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        let spaces = windowID.cgsSpaces()
        let active = currentActiveSpaceIDs()
        let result = image.map { "\($0.width)x\($0.height)\(transparent ? " transparent" : "")\(clipped ? " clipped" : "")" } ?? "nil"
        DebugLogger.log("captureWindowImage", details: "PID: \(pid), window: \(windowID), title: \(title ?? ""), image: \(result), bounds: \(bounds), onscreen: \(onscreen), spaces: \(spaces), activeSpaces: \(active.sorted()), quality: \(quality == .bestResolution ? "best" : "nominal")")
    }

    private static func isFullyTransparent(_ image: CGImage) -> Bool {
        let alphaOffset: Int
        switch image.alphaInfo {
        case .premultipliedFirst, .first: alphaOffset = 0
        case .premultipliedLast, .last: alphaOffset = 3
        default: return false
        }
        guard image.bitsPerPixel == 32,
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return false }
        let length = CFDataGetLength(data)
        let stepX = max(image.width / 16, 1)
        let stepY = max(image.height / 16, 1)
        var y = 0
        while y < image.height {
            var x = 0
            while x < image.width {
                let offset = y * image.bytesPerRow + x * 4 + alphaOffset
                if offset < length, bytes[offset] != 0 { return false }
                x += stepX
            }
            y += stepY
        }
        return true
    }

    static func cachedWindowElements(for pid: pid_t) -> [AXUIElement] {
        desktopSpaceWindowCacheManager.readCache(pid: pid).map(\.axElement)
    }

    static func isValidElement(_ element: AXUIElement) -> Bool {
        DebugLogger.measureSlow("isValidElement", thresholdMs: 50) {
            var pid = pid_t(0)
            if AXUIElementGetPid(element, &pid) == .success, AXResponsiveness.isUnresponsive(pid) {
                return true
            }

            // Fast path: check geometry
            do {
                let position = try element.position()
                let size = try element.size()
                if position != nil, size != nil {
                    return true
                }
            } catch AxError.runtimeError {
                return true
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

        let windowTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for axWindow in axWindows {
            if !windowTitle.isEmpty, let axTitle = try? axWindow.title(), isFuzzyMatch(windowTitle: windowTitle, axTitleString: axTitle) {
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
        guard !windowTitleWords.isEmpty else { return false }

        let matchingWords = axTitleWords.filter { windowTitleWords.contains($0) }
        let matchPercentage = Double(matchingWords.count) / Double(windowTitleWords.count)

        return matchPercentage >= 0.90 || axTitleString.lowercased().contains(windowTitle.lowercased())
    }

    static func findRunningApplicationByName(named applicationName: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.localizedName == applicationName }
    }
}

// MARK: - Window Discovery

extension WindowUtil {
    private static func isWindowlessAppEligible(
        _ app: NSRunningApplication,
        pidsWithWindows: Set<pid_t>,
        ownBundleId: String?
    ) -> Bool {
        app.activationPolicy == .regular &&
            !pidsWithWindows.contains(app.processIdentifier) &&
            !WindowOwnerResolver.isAuxiliaryOwner(app) &&
            !filteredBundleIdentifiers.contains(app.bundleIdentifier ?? "") &&
            !isAppFiltered(app) &&
            app.bundleIdentifier != ownBundleId
    }

    static func windowlessEntryIfEligible(for app: NSRunningApplication, existingWindows: [WindowInfo]) -> WindowInfo? {
        let pidsWithWindows = Set(existingWindows.map(\.app.processIdentifier))
        let ownBundleId = Bundle.main.bundleIdentifier

        guard isWindowlessAppEligible(app, pidsWithWindows: pidsWithWindows, ownBundleId: ownBundleId) else {
            return nil
        }

        return WindowInfo.windowlessEntry(for: app)
    }

    // Keep genuinely windowless apps distinct from apps whose windows are filtered out.
    static func cmdTabPreviewWindows(
        from sourceWindows: [WindowInfo],
        app: NSRunningApplication,
        allowWindowlessPlaceholder: Bool = true
    ) -> [WindowInfo]? {
        let realWindows = sourceWindows.filter { !$0.isWindowlessApp }
        var visibleWindows = realWindows

        if Defaults[.showWindowsFromCurrentSpaceOnlyInCmdTab] {
            visibleWindows = filterWindowsByCurrentSpace(visibleWindows)
        }
        if Defaults[.showWindowsFromCurrentMonitorOnlyInCmdTab] {
            visibleWindows = filterWindowsByCurrentMonitor(visibleWindows)
        }
        if !Defaults[.includeHiddenWindowsInCmdTab] {
            visibleWindows = visibleWindows.filter { !$0.isEffectivelyHiddenForUI && !$0.isMinimized }
        }

        if WindowFetchContext.cmdTab.shouldIgnoreAppsWithSingleWindow, visibleWindows.count == 1 {
            return nil
        }
        if !visibleWindows.isEmpty {
            return visibleWindows
        }

        guard realWindows.isEmpty,
              !app.isTerminated,
              allowWindowlessPlaceholder,
              Defaults[.showWindowlessAppsInCmdTab]
        else { return nil }
        return [WindowInfo.windowlessEntry(for: app)]
    }

    static func isProcessAlive(_ pid: pid_t) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    static func evictTerminatedApps() {
        let dead = desktopSpaceWindowCacheManager.cachedPIDs().filter { !isProcessAlive($0) }
        guard !dead.isEmpty else { return }
        for pid in dead {
            DebugLogger.log("evictTerminatedApp", details: "PID: \(pid)")
            purgeAppCache(with: pid)
        }
        Task { @MainActor in WindowManipulationObservers.didEvictTerminatedApps(dead) }
    }

    static func getAllWindowsOfAllApps() -> [WindowInfo] {
        evictTerminatedApps()
        let windows = desktopSpaceWindowCacheManager.getAllWindows()
        var filteredWindows = !Defaults[.includeHiddenWindowsInSwitcher]
            ? windows.filter { !$0.isEffectivelyHiddenForUI && !$0.isMinimized }
            : windows

        // Filter by frontmost app if enabled
        if Defaults[.limitSwitcherToFrontmostApp] {
            filteredWindows = getWindowsForFrontmostApp(from: filteredWindows)
        }

        return sortWindowsForSwitcher(collapseNativeTabsIfNeeded(filteredWindows))
    }

    static func getAllWindowsIgnoringSwitcherFilters() -> [WindowInfo] {
        evictTerminatedApps()
        return sortWindowsForSwitcher(desktopSpaceWindowCacheManager.getAllWindows())
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
        let pidsWithWindows = Set(existingWindows.map(\.app.processIdentifier))
        let ownBundleId = Bundle.main.bundleIdentifier

        return LauncherShortcutResolver.resolvingInPlaceReexecs(NSWorkspace.shared.runningApplications)
            .filter {
                isWindowlessAppEligible($0, pidsWithWindows: pidsWithWindows, ownBundleId: ownBundleId)
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            .map { WindowInfo.windowlessEntry(for: $0) }
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

    static func focusedWindowID(processIdentifier: pid_t) -> CGWindowID? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        guard let focusedWindow = (try? appElement.focusedWindow()) ?? nil else { return nil }
        return try? focusedWindow.cgWindowId()
    }

    static func activationMaySwitchSpaces(for window: WindowInfo) -> Bool {
        let activeSpaceIDs = currentActiveSpaceIDs()
        guard !activeSpaceIDs.isEmpty else { return true }
        let windowSpaces = Set(window.id.cgsSpaces().map { Int($0) })
        if !windowSpaces.isEmpty {
            return windowSpaces.isDisjoint(with: activeSpaceIDs)
        }
        if let cachedSpaceID = window.spaceID {
            return !activeSpaceIDs.contains(cachedSpaceID)
        }
        // Unknown membership: only keep previews open when same-Space activation is known.
        return true
    }

    static func windowInfo(for axWindow: AXUIElement, app: NSRunningApplication, windowID: CGWindowID? = nil) -> WindowInfo? {
        guard let windowID = windowID ?? (try? axWindow.cgWindowId()) else { return nil }
        if let cached = readCachedWindows(for: app.processIdentifier).first(where: { $0.id == windowID }) {
            return cached
        }
        return WindowInfo(
            windowProvider: AXFallbackProvider(cgID: windowID),
            app: app,
            image: nil,
            axElement: axWindow,
            appAxElement: AXUIElementCreateApplication(app.processIdentifier),
            closeButton: try? axWindow.closeButton(),
            lastAccessedTime: Date(),
            isMinimized: (try? axWindow.isMinimized()) ?? false,
            isHidden: app.isHidden,
            readsAXTitle: false
        )
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

    /// Collapses native macOS window-tab groups (e.g. Ghostty, Finder, Terminal) so a tabbed
    /// window appears as a single entry instead of one per tab. Grouping is keyed by process,
    /// Space, and frame, so distinct windows on different Spaces are never merged. Off-screen
    /// windows reuse the last visible grouping; without reliable evidence, all rows are kept.
    static func collapseNativeTabsIfNeeded(_ windows: [WindowInfo]) -> [WindowInfo] {
        guard Defaults[.collapseNativeTabsIntoSingleWindow], windows.count > 1 else { return windows }

        var candidatePIDs = Set<pid_t>()
        let mayContainTabs = windows.contains { window in
            guard !window.isWindowlessApp, !window.isMinimized else { return false }
            return !candidatePIDs.insert(window.app.processIdentifier).inserted
        }
        guard mayContainTabs else { return windows }

        // AX-only tab rows can retain zero or stale cached frames during rapid tab changes.
        let windowIDs = Set(windows.map(\.id))
        let currentWindowEntries =
            (CGWindowListCopyWindowInfo(.excludeDesktopElements, kCGNullWindowID) as? [[String: Any]]) ?? []
        var onScreenIDs = Set<CGWindowID>()
        var currentFramesByID: [CGWindowID: CGRect] = [:]

        for entry in currentWindowEntries {
            guard let number = entry[kCGWindowNumber as String] as? NSNumber else { continue }
            let windowID = CGWindowID(number.uint32Value)
            guard windowIDs.contains(windowID) else { continue }

            if (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true {
                onScreenIDs.insert(windowID)
            }

            if let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
               let frame = CGRect(dictionaryRepresentation: bounds),
               frame.width > 0,
               frame.height > 0
            {
                currentFramesByID[windowID] = frame
            }
        }

        let candidates = windows.map { window in
            let currentFrame = currentFramesByID[window.id] ?? window.frame
            let spaceID = window.spaceID ?? window.id.cgsSpaces().first.map { Int($0) }
            return NativeTabGrouping.Candidate(
                id: window.id,
                pid: window.app.processIdentifier,
                spaceID: spaceID,
                frame: currentFrame,
                recency: window.lastAccessedTime,
                groupable: !window.isMinimized
                    && spaceID != nil
                    && !window.isWindowlessApp
                    && currentFrame.width > 0
                    && currentFrame.height > 0,
                isOnScreen: onScreenIDs.contains(window.id)
            )
        }

        var keptIDs = Set(candidates.lazy.filter { $0.spaceID == nil }.map(\.id))
        let candidatesBySpace = Dictionary(grouping: candidates.compactMap { candidate -> (NativeTabSnapshotKey, NativeTabGrouping.Candidate)? in
            guard let spaceID = candidate.spaceID else { return nil }
            return (NativeTabSnapshotKey(pid: candidate.pid, spaceID: spaceID), candidate)
        }, by: \.0)

        for (key, keyedCandidates) in candidatesBySpace {
            let spaceCandidates = keyedCandidates.map(\.1)
            let hasVisibleWindow = spaceCandidates.contains(where: \.isOnScreen)
            let retainedIDs = NativeTabGrouping.retainedIDs(
                from: spaceCandidates,
                previousSnapshot: hasVisibleWindow ? nil : nativeTabSnapshot(for: key)
            )
            keptIDs.formUnion(retainedIDs)
            if hasVisibleWindow {
                setNativeTabSnapshot(
                    NativeTabGrouping.VisibilitySnapshot(observedIDs: Set(spaceCandidates.map(\.id)), keptIDs: retainedIDs),
                    for: key
                )
            }
        }

        guard keptIDs.count < windows.count else { return windows }
        return windows.filter { keptIDs.contains($0.id) }
    }

    static func getActiveWindows(of app: NSRunningApplication, context: WindowFetchContext = .dockPreview, ignoreSingleWindowFilter: Bool = false) async throws -> [WindowInfo] {
        if isAppFiltered(app) {
            purgeAppCache(with: app.processIdentifier)
            return []
        }

        let contextName = switch context {
        case .dockPreview: "dockPreview"
        case .cmdTab: "cmdTab"
        }

        DebugLogger.log("WindowRefresh", details: "begin, context: \(contextName), app: \(app.localizedName ?? "Unknown"), PID: \(app.processIdentifier)")
        do {
            let windows = try await desktopSpaceWindowCacheManager.withCoordinatorNotificationsSuppressed(for: app.processIdentifier) {
                try await getActiveWindowsUpdatingCache(
                    of: app,
                    context: context,
                    ignoreSingleWindowFilter: ignoreSingleWindowFilter
                )
            }
            DebugLogger.log("WindowRefresh", details: "end, context: \(contextName), app: \(app.localizedName ?? "Unknown"), PID: \(app.processIdentifier), windows: \(windows.count)")
            return windows
        } catch {
            DebugLogger.log("WindowRefresh", details: "failed, context: \(contextName), app: \(app.localizedName ?? "Unknown"), PID: \(app.processIdentifier), error: \(error)")
            throw error
        }
    }

    private static func getActiveWindowsUpdatingCache(of app: NSRunningApplication, context: WindowFetchContext, ignoreSingleWindowFilter: Bool) async throws -> [WindowInfo] {
        var sckWindowIDs = Set<CGWindowID>()

        // Skip SCK if user has disabled image previews (compact mode only) or screen recording permission not granted
        if shouldCaptureWindowImages() {
            if let content = await getShareableContent(onScreenWindowsOnly: true) {
                // Build set of SCK window IDs
                let appWindows = content.windows.filter {
                    WindowOwnerResolver.windowBelongsToDisplayApp($0, displayApp: app)
                }
                sckWindowIDs = Set(appWindows.map(\.windowID))

                // Pre-compute fresh cached IDs to avoid repeated cache reads
                let freshCachedIDs = freshCachedWindowIDs(for: app.processIdentifier)

                // Process SCK windows with limited concurrency
                await LimitedConcurrency.forEachNonThrowing(appWindows, maxConcurrent: 4, timeout: 10) { window in
                    try await captureAndCacheWindowInfo(window: window, displayApp: app, skipWindowIDs: freshCachedIDs)
                }
            }
        }

        // Discover windows via AX (minimized, hidden, other spaces, SCK-missed, or all when compact mode)
        await discoverNonSCKWindowsViaAX(app: app, sckWindowIDs: sckWindowIDs)

        await refreshFallbackOrMissingWindowImages(for: app.processIdentifier, missingOnly: true)

        // Purify cache and return
        if let finalWindows = await WindowUtil.purifyAppCache(with: app.processIdentifier, removeAll: false) {
            guard ignoreSingleWindowFilter || !context.shouldIgnoreAppsWithSingleWindow || finalWindows.count > 1 else { return [] }
            return sortWindows(collapseNativeTabsIfNeeded(Array(finalWindows)), for: context)
        }

        return []
    }

    private static func discoverNonSCKWindowsViaAX(app: NSRunningApplication, sckWindowIDs: Set<CGWindowID>) async {
        _ = await discoverWindowsViaAX(app: app, excludeWindowIDs: sckWindowIDs)
    }

    static func discoverWindowsViaAX(
        app: NSRunningApplication,
        excludeWindowIDs: Set<CGWindowID> = [],
        restorePersistedOrder: Bool = true
    ) async -> Int {
        let pid = app.processIdentifier

        if let bundleId = app.bundleIdentifier, filteredBundleIdentifiers.contains(bundleId) {
            purgeAppCache(with: pid)
            return 0
        }

        if isAppFiltered(app) {
            purgeAppCache(with: pid)
            return 0
        }

        if AXResponsiveness.isUnresponsive(pid) {
            return 0
        }

        let appAX = AXUIElementCreateApplication(pid)
        let cgCandidates = getCGWindowCandidates(for: pid)
        let geometryAliasWindowIDs = unspacedGeometryAliasWindowIDs(in: cgCandidates)
        let axWindows = AXUIElement.allWindows(
            pid,
            appElement: appAX,
            app: app,
            cgCandidates: cgCandidates,
            excludingWindowIDs: geometryAliasWindowIDs
        )
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
                excludeWindowIDs: excludeWindowIDs.union(geometryAliasWindowIDs),
                skipWindowIDs: freshCachedIDs,
                existingCachedIDs: allCachedIDs,
                cgCandidates: cgCandidates,
                restorePersistedOrder: restorePersistedOrder
            )
        }

        return axWindows.count
    }

    static func shouldRetryStartupDiscovery(for app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        guard isProcessAlive(pid), !isAppFiltered(app) else { return false }
        if AXResponsiveness.isUnresponsive(pid) { return true }

        let cachedIDs = Set(desktopSpaceWindowCacheManager.readCache(pid: pid).map(\.id))
        let cgCandidates = getCGWindowCandidates(for: pid)
        let ignoredIDs = unspacedGeometryAliasWindowIDs(in: cgCandidates)
        return !unreachedCGWindowIDs(in: cgCandidates, excluding: cachedIDs.union(ignoredIDs), app: app).isEmpty
    }

    static func updateNewWindowsForApp(_ app: NSRunningApplication, restorePersistedOrder: Bool = true) async {
        WindowManipulationObservers.ensureObserver(for: app)
        if shouldCaptureWindowImages() {
            if let content = await getShareableContent(onScreenWindowsOnly: false) {
                let appWindows = content.windows.filter { window in
                    WindowOwnerResolver.windowBelongsToDisplayApp(window, displayApp: app)
                }

                // Pre-compute fresh cached IDs to avoid repeated cache reads
                let freshCachedIDs = freshCachedWindowIDs(for: app.processIdentifier)

                await LimitedConcurrency.forEachNonThrowing(appWindows, maxConcurrent: 4, timeout: 10) { window in
                    try await captureAndCacheWindowInfo(window: window, displayApp: app, skipWindowIDs: freshCachedIDs, restorePersistedOrder: restorePersistedOrder)
                }
            }
        }

        // AX fallback
        _ = await discoverWindowsViaAX(app: app, restorePersistedOrder: restorePersistedOrder)
        await refreshFallbackOrMissingWindowImages(for: app.processIdentifier)
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
        await globalWindowRefreshGate.perform {
            await performGlobalWindowRefresh()
        }
    }

    private static func performGlobalWindowRefresh() async {
        HangDiagnostics.record("global window refresh started")
        defer { HangDiagnostics.record("global window refresh finished") }
        var processedPIDs = Set<pid_t>()

        if shouldCaptureWindowImages() {
            if let content = await getShareableContent(onScreenWindowsOnly: false) {
                var displayAppsByOwner: [pid_t: NSRunningApplication] = [:]
                let windowAppPairs: [(window: SCWindow, displayApp: NSRunningApplication, ownerApp: NSRunningApplication)] = content.windows.compactMap { window in
                    guard let scApp = window.owningApplication,
                          !filteredBundleIdentifiers.contains(scApp.bundleIdentifier),
                          let ownerApp = LauncherShortcutResolver.application(forProcessIdentifier: scApp.processID)
                    else { return nil }
                    let displayApp = displayAppsByOwner[ownerApp.processIdentifier] ?? WindowOwnerResolver.displayApp(forOwner: ownerApp)
                    displayAppsByOwner[ownerApp.processIdentifier] = displayApp
                    return (window, displayApp, ownerApp)
                }

                for pair in windowAppPairs {
                    processedPIDs.insert(pair.displayApp.processIdentifier)
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
                    let skipIDs = freshCachedIDsByPID[pair.displayApp.processIdentifier] ?? []
                    try await captureAndCacheWindowInfo(
                        window: pair.window,
                        displayApp: pair.displayApp,
                        ownerApp: pair.ownerApp,
                        skipWindowIDs: skipIDs
                    )
                }
            }
        }

        // AX fallback
        let runningApps = LauncherShortcutResolver.resolvingInPlaceReexecs(NSWorkspace.shared.runningApplications).filter {
            $0.activationPolicy == .regular &&
                !WindowOwnerResolver.isAuxiliaryOwner($0) &&
                !filteredBundleIdentifiers.contains($0.bundleIdentifier ?? "") &&
                !isAppFiltered($0)
        }

        for app in runningApps {
            let pid = app.processIdentifier
            WindowManipulationObservers.ensureObserver(for: app)
            await discoverNewWindowsViaAXFallback(app: app)
            processedPIDs.insert(pid)
        }

        // Purify cache and refresh images
        for pid in processedPIDs {
            _ = await purifyAppCache(with: pid, removeAll: false)
            await refreshFallbackOrMissingWindowImages(for: pid)
        }
    }

    private static func refreshFallbackOrMissingWindowImages(for pid: pid_t, missingOnly: Bool = false) async {
        let windows = desktopSpaceWindowCacheManager.readCache(pid: pid)
        guard !windows.isEmpty else { return }
        guard shouldCaptureWindowImages() else { return }

        // Pre-compute fresh cached IDs to skip - use already-fetched windows
        let freshCachedIDs = freshCachedWindowIDs(for: pid, from: windows)

        var validWindows: [WindowInfo] = []
        for window in windows where !window.isWindowlessApp {
            guard shouldRefreshCachedWindowImage(
                hasImage: window.image != nil,
                hasSCWindow: window.scWindow != nil,
                isFresh: freshCachedIDs.contains(window.id),
                missingOnly: missingOnly
            ) else { continue }
            if !isValidElement(window.axElement) {
                desktopSpaceWindowCacheManager.removeFromCache(pid: pid, windowId: window.id)
            } else {
                validWindows.append(window)
            }
        }

        // Process valid windows with limited concurrency
        await LimitedConcurrency.forEachNonThrowing(validWindows, maxConcurrent: 4, timeout: 10) { window in
            let image = try await captureWindowImage(windowID: window.id, pid: pid, windowTitle: window.windowName, forceRefresh: true)
            guard !shouldRejectCapturedImage(image, for: window) else { return }
            let capturedAt = Date()
            // Update only the image; a capture must not restore stale window metadata or a removed row.
            desktopSpaceWindowCacheManager.updateCache(pid: pid) { windowSet in
                guard let cached = windowSet.first(where: { $0.id == window.id }),
                      !missingOnly || cached.image == nil
                else { return }
                var updated = cached
                updated.image = image
                updated.imageCapturedTime = capturedAt
                windowSet.remove(cached)
                windowSet.insert(updated)
            }
        }
    }

    static func captureAndCacheWindowInfo(
        window: SCWindow,
        displayApp: NSRunningApplication,
        ownerApp: NSRunningApplication? = nil,
        skipWindowIDs: Set<CGWindowID> = [],
        restorePersistedOrder: Bool = true
    ) async throws {
        let windowID = window.windowID
        guard let ownerApp = ownerApp ?? WindowOwnerResolver.ownerApp(for: window) else {
            return
        }
        let displayPid = displayApp.processIdentifier
        let ownerPid = ownerApp.processIdentifier

        if WindowCandidateDiscriminator.isLiveCaptureControlProxy(
            title: window.title,
            size: window.frame.size,
            level: Int32(window.windowLayer)
        ) {
            removeWindowFromDesktopSpaceCache(with: windowID, in: displayPid)
            return
        }

        // Fast path: skip if pre-computed by caller as fresh cached
        if skipWindowIDs.contains(windowID) {
            return
        }

        guard window.owningApplication != nil else {
            return
        }
        guard window.isOnScreen else {
            return
        }
        guard WindowCandidateDiscriminator.acceptsWindowLayer(app: ownerApp, level: Int32(window.windowLayer), frame: window.frame) else {
            return
        }
        guard Defaults[.disableMinWindowSizeFilter] || (window.frame.size.width >= AXMinWindowSize.width && window.frame.size.height >= AXMinWindowSize.height) else {
            return
        }

        let bundleId = displayApp.bundleIdentifier
        if let bundleId, filteredBundleIdentifiers.contains(bundleId) {
            purgeAppCache(with: displayPid)
            return
        }

        if isAppFiltered(displayApp) {
            purgeAppCache(with: displayPid)
            return
        }

        if let windowTitle = window.title {
            let windowTitleFilters = Defaults[.windowTitleFilters]
            if !windowTitleFilters.isEmpty {
                for filter in windowTitleFilters {
                    if windowTitle.lowercased().contains(filter.lowercased()) {
                        removeWindowFromDesktopSpaceCache(with: windowID, in: displayPid)
                        return
                    }
                }
            }
        }

        desktopSpaceWindowCacheManager.updateCache(pid: displayPid) { windowSet in
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

        guard ownerApp.activationPolicy != .prohibited, !AXResponsiveness.isUnresponsive(ownerPid) else {
            return
        }

        let ownerAppElement = AXUIElementCreateApplication(ownerPid)

        let windowRef: AXUIElement
        if let cached = desktopSpaceWindowCacheManager.readCache(pid: displayPid).first(where: { $0.id == windowID }),
           isValidElement(cached.axElement)
        {
            windowRef = cached.axElement
        } else {
            let axWindows = AXUIElement.allWindows(ownerPid, appElement: ownerAppElement, app: displayApp)
            guard let matched = findWindow(matchingWindow: window, in: axWindows) else {
                return
            }
            windowRef = matched
        }

        let closeButtonResolution = windowRef.closeButtonResolution()
        let closeButton = closeButtonResolution.button
        let minimizeButton = try? windowRef.minimizeButton()
        let minimizedState = (try? windowRef.isMinimized()) ?? false
        let hiddenState = displayApp.isHidden
        let fullscreenState = try? windowRef.isFullscreen()
        let attributes = WindowCandidateAttributes(axWindow: windowRef, hasCloseButton: closeButton != nil)
        let shouldWindowBeCaptured = (window.windowLayer == 0 && (closeButton != nil || minimizeButton != nil)) ||
            WindowCandidateDiscriminator.isActualWindow(
                app: displayApp,
                windowID: windowID,
                level: windowID.cgsLevel(),
                attributes: attributes
            )

        if shouldWindowBeCaptured {
            let persistedData = restorePersistedOrder ? bundleId.flatMap {
                WindowOrderPersistence.getPersistedTimestamp(
                    bundleIdentifier: $0,
                    windowTitle: window.title
                )
            } : nil
            let lastAccessedTime = persistedData?.lastAccessedTime ?? Date.now
            let creationTime = persistedData?.creationTime

            var windowInfo = WindowInfo(
                windowProvider: window,
                app: displayApp,
                ownerApp: ownerApp,
                image: nil,
                axElement: windowRef,
                appAxElement: ownerAppElement,
                closeButton: closeButton,
                hasLimitedWindowControls: closeButtonResolution.usesSemanticFallback,
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
        existingCachedIDs: Set<CGWindowID> = [],
        cgCandidates: [[String: AnyObject]]? = nil,
        restorePersistedOrder: Bool = true
    ) async throws {
        guard var info = buildAXWindowInfo(
            axWindow: axWindow,
            appAxElement: appAxElement,
            app: app,
            excludeWindowIDs: excludeWindowIDs,
            skipWindowIDs: skipWindowIDs,
            existingCachedIDs: existingCachedIDs,
            cgCandidates: cgCandidates,
            restorePersistedOrder: restorePersistedOrder
        ) else { return }

        if let image = try? await captureWindowImage(windowID: info.id, pid: app.processIdentifier, windowTitle: info.windowName) {
            info.image = image
            info.imageCapturedTime = Date()
        }

        updateDesktopSpaceWindowCache(with: info)
    }

    private static let createdWindowRetryDelays: [UInt64] = [0, 100_000_000, 250_000_000, 500_000_000, 1_000_000_000]
    private static let createdWindowsInFlightLock = NSLock()
    private static var createdWindowsInFlight = Set<AXUIElement>()

    static func cacheCreatedWindow(axWindow: AXUIElement, app: NSRunningApplication) async {
        let pid = app.processIdentifier
        guard app.activationPolicy != .prohibited, !AXResponsiveness.isUnresponsive(pid) else { return }
        if let bundleId = app.bundleIdentifier, filteredBundleIdentifiers.contains(bundleId) { return }
        guard !isAppFiltered(app) else { return }

        var cgID: CGWindowID = 0
        guard _AXUIElementGetWindow(axWindow, &cgID) == .success, cgID != 0 else { return }

        let alreadyInFlight = createdWindowsInFlightLock.withLock {
            !createdWindowsInFlight.insert(axWindow).inserted
        }
        guard !alreadyInFlight else { return }
        defer {
            _ = createdWindowsInFlightLock.withLock {
                createdWindowsInFlight.remove(axWindow)
            }
        }

        let appAxElement = AXUIElementCreateApplication(pid)
        for delay in createdWindowRetryDelays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            if desktopSpaceWindowCacheManager.readCache(pid: pid).contains(where: { $0.id == cgID }) { return }
            let cgCandidates = getCGWindowCandidates(for: pid)
            let geometryAliasWindowIDs = unspacedGeometryAliasWindowIDs(in: cgCandidates)
            guard !geometryAliasWindowIDs.contains(cgID) else { return }
            guard isValidCGWindowCandidate(cgID, in: cgCandidates) else { continue }
            try? await captureAndCacheAXWindowInfo(
                axWindow: axWindow,
                appAxElement: appAxElement,
                app: app,
                excludeWindowIDs: geometryAliasWindowIDs,
                cgCandidates: cgCandidates,
                restorePersistedOrder: false
            )
        }
    }

    private static func buildAXWindowInfo(
        axWindow: AXUIElement,
        appAxElement: AXUIElement,
        app: NSRunningApplication,
        excludeWindowIDs: Set<CGWindowID>,
        skipWindowIDs: Set<CGWindowID> = [],
        existingCachedIDs: Set<CGWindowID> = [],
        cgCandidates: [[String: AnyObject]]? = nil,
        restorePersistedOrder: Bool = true
    ) -> WindowInfo? {
        let pid = app.processIdentifier

        // Quick window ID check first (fast path)
        var cgID: CGWindowID = 0
        if _AXUIElementGetWindow(axWindow, &cgID) == .success, cgID != 0 {
            // Skip if already cached with fresh image (pre-computed by caller)
            if skipWindowIDs.contains(cgID) {
                return nil
            }
            guard !excludeWindowIDs.contains(cgID) else {
                return nil
            }
        }

        let closeButtonResolution = axWindow.closeButtonResolution()
        let closeButton = closeButtonResolution.button
        let attributes = WindowCandidateAttributes(axWindow: axWindow, hasCloseButton: closeButton != nil)

        let cgCandidates = cgCandidates ?? getCGWindowCandidates(for: pid)
        // Use pre-computed cached IDs if provided, otherwise read from cache
        let usedIDs = existingCachedIDs.isEmpty
            ? Set<CGWindowID>(desktopSpaceWindowCacheManager.readCache(pid: pid).map(\.id))
            : existingCachedIDs

        if cgID == 0 {
            if let mapped = mapAXToCG(attributes: attributes, candidates: cgCandidates, excluding: usedIDs) {
                cgID = mapped
            } else {
                return nil
            }
        }

        guard !excludeWindowIDs.contains(cgID) else {
            return nil
        }
        guard !usedIDs.contains(cgID) else {
            return nil
        }
        guard WindowCandidateDiscriminator.isActualWindow(
            app: app,
            windowID: cgID,
            level: cgID.cgsLevel(),
            attributes: attributes
        ) else {
            return nil
        }

        let titleFilters = Defaults[.windowTitleFilters]
        if !titleFilters.isEmpty {
            let title = attributes.title ?? cgID.cgsTitle() ?? ""
            if titleFilters.contains(where: { title.lowercased().contains($0.lowercased()) }) {
                return nil
            }
        }

        guard let cgEntry = findCGEntry(for: cgID, in: cgCandidates) ?? findCGEntry(for: cgID, ownerPID: pid) else {
            return nil
        }
        guard isValidCGWindowEntry(cgEntry) else { return nil }

        let activeSpaceIDs = currentActiveSpaceIDs()
        guard shouldAcceptWindow(
            axWindow: axWindow,
            windowID: cgID,
            cgEntry: cgEntry,
            app: app,
            activeSpaceIDs: activeSpaceIDs,
            scBacked: false
        ) else {
            return nil
        }

        let windowTitle = attributes.title ?? cgID.cgsTitle()
        let minimizedState = (try? axWindow.isMinimized()) ?? false
        let hiddenState = app.isHidden
        let fullscreenState = try? axWindow.isFullscreen()

        let persistedData: WindowOrderPersistence.PersistedWindowEntry? = if restorePersistedOrder, let bundleId = app.bundleIdentifier {
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
            closeButton: closeButton,
            hasLimitedWindowControls: closeButtonResolution.usesSemanticFallback,
            lastAccessedTime: persistedData?.lastAccessedTime ?? Date(),
            creationTime: persistedData?.creationTime,
            spaceID: cgID.cgsSpaces().first.map { Int($0) },
            screenIdentifier: attributes.position.flatMap { screenIdentifier(forWindowAt: $0) },
            isMinimized: minimizedState,
            isHidden: hiddenState,
            isFullscreen: fullscreenState
        )
        info.windowName = windowTitle
        if let position = attributes.position, let size = attributes.size {
            info.frame = CGRect(origin: position, size: size)
        }
        return info
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

    private static func preferredCachedWindow(_ first: WindowInfo, _ second: WindowInfo) -> WindowInfo {
        if first.scWindow == nil, second.scWindow != nil { return second }
        if first.scWindow != nil, second.scWindow == nil { return first }
        if first.image == nil, second.image != nil { return second }
        if first.image != nil, second.image == nil { return first }
        return first.lastAccessedTime >= second.lastAccessedTime ? first : second
    }

    private static func deduplicatedByWindowID(_ windows: Set<WindowInfo>) -> Set<WindowInfo> {
        var windowsByID: [CGWindowID: WindowInfo] = [:]
        for window in windows {
            if let existing = windowsByID[window.id] {
                windowsByID[window.id] = preferredCachedWindow(existing, window)
            } else {
                windowsByID[window.id] = window
            }
        }
        return Set(windowsByID.values)
    }

    static func updateDesktopSpaceWindowCache(with windowInfo: WindowInfo) {
        // Image validation may query AX. Keep it outside the cache lock because
        // DockDoor-owned AX elements synchronously marshal reads to the main thread.
        let shouldRejectImage = shouldRejectCapturedImage(windowInfo.image, for: windowInfo)
        desktopSpaceWindowCacheManager.updateCache(pid: windowInfo.app.processIdentifier) { windowSet in
            var windowInfo = windowInfo
            let pendingFocus = pendingFocusLock.withLock { pendingFocusUpdates.take(PreviewWindowIdentity(windowInfo)) }
            if let pendingFocus {
                windowInfo.lastAccessedTime = pendingFocus
            }
            let matchingWindows = windowSet.filter { $0.id == windowInfo.id || $0.axElement == windowInfo.axElement }
            let bestMatch = matchingWindows.reduce(nil as WindowInfo?) { best, window in
                guard let best else { return window }
                return preferredCachedWindow(best, window)
            }
            if let matchingWindow = bestMatch {
                var matchingWindowCopy = matchingWindow
                if let pendingFocus {
                    matchingWindowCopy.lastAccessedTime = max(matchingWindow.lastAccessedTime, pendingFocus)
                }
                matchingWindowCopy.windowName = windowInfo.windowName
                if let newSpaceID = windowInfo.spaceID {
                    matchingWindowCopy.spaceID = newSpaceID
                }
                if let newScreen = windowInfo.screenIdentifier {
                    matchingWindowCopy.screenIdentifier = newScreen
                }
                matchingWindowCopy.isMinimized = windowInfo.isMinimized
                matchingWindowCopy.isHidden = windowInfo.isHidden
                if let isFullscreen = windowInfo.isFullscreen {
                    matchingWindowCopy.isFullscreen = isFullscreen
                }

                if shouldRejectImage, matchingWindow.image != nil {
                    DebugLogger.log(
                        "Window image cache",
                        details: "Rejected suspicious capture for pid=\(windowInfo.app.processIdentifier) window=\(windowInfo.id)"
                    )
                } else {
                    matchingWindowCopy.image = windowInfo.image
                    matchingWindowCopy.imageCapturedTime = windowInfo.imageCapturedTime
                }

                for duplicate in matchingWindows {
                    windowSet.remove(duplicate)
                }
                windowSet.insert(matchingWindowCopy)
            } else {
                if shouldRejectImage {
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

            if !isProcessAlive(pid) {
                evictTerminatedApps()
                return nil
            }

            if AXResponsiveness.isUnresponsive(pid) {
                return existingWindowsSet
            }

            var purifiedSet = existingWindowsSet
            let cgCandidates = getCGWindowCandidates(for: pid)
            let geometryAliasWindowIDs = unspacedGeometryAliasWindowIDs(in: cgCandidates)
            let activeSpaceIDs = currentActiveSpaceIDs()
            lazy var managedSpaceIDs = WindowSpaces.allManagedSpaceIDs()
            for window in existingWindowsSet {
                var shouldRemove = geometryAliasWindowIDs.contains(window.id) ||
                    !isValidElement(window.axElement) ||
                    !WindowOwnerResolver.ownerBelongsToDisplayApp(window.ownerApp, displayApp: window.app)

                if !shouldRemove {
                    let cgEntry = findCGEntry(for: window.id, in: cgCandidates)
                    let hasValidCGWindow = cgEntry.map(isValidCGWindowEntry) ?? false
                    if let cgEntry {
                        if !hasValidCGWindow,
                           !window.isMinimized,
                           !window.isHidden
                        {
                            let isFullscreen = window.isFullscreen == true || (try? window.axElement.isFullscreen()) == true
                            shouldRemove = !isFullscreen
                        } else if hasValidCGWindow {
                            shouldRemove = !shouldAcceptWindow(
                                axWindow: window.axElement,
                                windowID: window.id,
                                cgEntry: cgEntry,
                                app: window.app,
                                activeSpaceIDs: activeSpaceIDs,
                                scBacked: window.scWindow != nil
                            )
                        }
                    } else if !window.isMinimized, !window.isHidden {
                        let isFullscreen = window.isFullscreen == true || (try? window.axElement.isFullscreen()) == true
                        let liveSpaceIDs = Set(window.id.cgsSpaces().map { Int($0) })
                        shouldRemove = !isFullscreen && (liveSpaceIDs.isEmpty || liveSpaceIDs.isDisjoint(with: managedSpaceIDs))
                    }

                    if !shouldRemove, Defaults[.collapseNativeTabsIntoSingleWindow],
                       window.isMinimized || window.isHidden, window.isFullscreen == false,
                       !hasValidCGWindow
                    {
                        shouldRemove = shouldExcludeInactiveNativeTab(
                            windowID: window.id,
                            isFullscreen: false,
                            isOnscreen: (cgEntry?[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
                            windowSpaces: window.id.cgsSpacesIfAvailable().map { Set($0.map { Int($0) }) }
                        )
                    }
                }

                if shouldRemove {
                    purifiedSet.remove(window)
                    desktopSpaceWindowCacheManager.removeFromCache(pid: pid, windowId: window.id)
                }
            }

            let deduplicatedSet = deduplicatedByWindowID(purifiedSet)
            if deduplicatedSet.count != purifiedSet.count {
                desktopSpaceWindowCacheManager.writeCache(pid: pid, windowSet: deduplicatedSet)
            }
            return deduplicatedSet
        }
    }

    static func purgeAppCache(with pid: pid_t) {
        AXUIElement.resetWindowScan(for: pid)
        purgeNativeTabSnapshots(for: pid)
        desktopSpaceWindowCacheManager.writeCache(pid: pid, windowSet: [])
        WindowSnapRegistry.existing?.removeAll(for: pid)
        pendingFocusLock.withLock { pendingFocusUpdates.removeAll(for: pid) }
    }

    static func purgeAllCaches() {
        purgeNativeTabSnapshots()
        desktopSpaceWindowCacheManager.purgeAll()
        pendingFocusLock.withLock { pendingFocusUpdates = PendingWindowFocusUpdates() }
    }

    static func cachedWindowCount() -> Int {
        desktopSpaceWindowCacheManager.getAllWindows().count
    }

    static func cachedAppCount() -> Int {
        desktopSpaceWindowCacheManager.cachedPIDs().count
    }

    private static let pendingQuitChecksLock = NSLock()
    private static var pendingQuitChecks = Set<pid_t>()

    static func cachedWindowWasDestroyed(_ element: AXUIElement, pid: pid_t) -> Bool {
        let cached = desktopSpaceWindowCacheManager.readCache(pid: pid)
        guard !cached.isEmpty else { return false }
        if cached.contains(where: { $0.axElement == element }) { return true }
        guard let windowID = try? element.cgWindowId() else { return false }
        return cached.contains { $0.id == windowID }
    }

    @discardableResult
    static func quitAppOnLastWindowCloseIfNeeded(app: NSRunningApplication) -> Bool {
        guard Defaults[.quitAppOnWindowClose],
              app.bundleIdentifier != "com.apple.finder",
              !app.isTerminated
        else {
            return false
        }

        let pid = app.processIdentifier
        pendingQuitChecksLock.lock()
        let scheduled = pendingQuitChecks.insert(pid).inserted
        pendingQuitChecksLock.unlock()
        guard scheduled else { return true }

        DebugLogger.log("quitAppOnLastWindowClose", details: "Scheduled: \(app.localizedName ?? "Unknown") (PID: \(pid))")
        verifyNoWindowsRemain(app: app, attempt: 0, confirmed: false)
        return true
    }

    /// Live AX windows are the source of truth, and an AX failure from a busy app is never treated as "no windows".
    private static func verifyNoWindowsRemain(app: NSRunningApplication, attempt: Int, confirmed: Bool) {
        let pid = app.processIdentifier
        let delay: TimeInterval = attempt == 0 ? 0.5 : 1.0
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
            func finish(_ reason: String) {
                pendingQuitChecksLock.lock()
                pendingQuitChecks.remove(pid)
                pendingQuitChecksLock.unlock()
                DebugLogger.log("quitAppOnLastWindowClose", details: "\(reason): \(app.localizedName ?? "Unknown") (PID: \(pid))")
            }

            guard !app.isTerminated else { return finish("Already terminated") }

            switch liveAXWindowCount(pid: pid) {
            case nil:
                if attempt < 3 {
                    verifyNoWindowsRemain(app: app, attempt: attempt + 1, confirmed: confirmed)
                } else {
                    finish("Aborted, AX unavailable")
                }
            case let count? where count > 0:
                finish("Aborted, \(count) live window(s)")
            default:
                if confirmed {
                    DispatchQueue.main.async {
                        guard WindowInfo.windowlessEntry(for: app).quit(force: false) else { finish("Quit busy or refused"); return }
                        purgeAppCache(with: pid)
                        finish("Terminated")
                    }
                } else {
                    verifyNoWindowsRemain(app: app, attempt: attempt + 1, confirmed: true)
                }
            }
        }
    }

    private static func liveAXWindowCount(pid: pid_t) -> Int? {
        var value: AnyObject?
        switch AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) {
        case .success:
            return (value as? [AXUIElement])?.count ?? 0
        case .noValue:
            return 0
        case .cannotComplete:
            AXResponsiveness.markUnresponsive(pid)
            return nil
        default:
            return nil
        }
    }

    /// Checks if the frontmost application is fullscreen and in the blacklist.
    /// Runs on every switcher keypress inside the event tap, so the expensive AX
    /// fullscreen probe only happens when the frontmost app actually matches the blacklist.
    static func shouldIgnoreKeybindForFrontmostApp() -> Bool {
        let blacklist = Defaults[.fullscreenAppBlacklist]
        guard !blacklist.isEmpty else { return false }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let appName = frontmostApp.localizedName ?? ""
        let bundleIdentifier = frontmostApp.bundleIdentifier ?? ""

        let isInBlacklist = blacklist.contains { blacklistEntry in
            appName.lowercased().contains(blacklistEntry.lowercased()) ||
                bundleIdentifier.lowercased().contains(blacklistEntry.lowercased())
        }
        guard isInBlacklist else { return false }

        return isAppInFullscreen(frontmostApp)
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
    static func sortWindowsForSwitcherByRecency(_ windows: [WindowInfo]) -> [WindowInfo] {
        sortWindowsWithOptions(windows, sortOrder: .recentlyUsed)
    }

    /// Centralized sorting for dock preview and cmd+tab contexts (single app windows)
    static func sortWindows(_ windows: Set<WindowInfo>, for context: WindowFetchContext) -> [WindowInfo] {
        sortWindows(Array(windows), for: context)
    }

    static func sortWindows(_ windows: [WindowInfo], for context: WindowFetchContext) -> [WindowInfo] {
        let sortOrder: WindowPreviewSortOrder = switch context {
        case .dockPreview:
            Defaults[.windowPreviewSortOrder]
        case .cmdTab:
            Defaults[.cmdTabSortOrder]
        }

        return sortWindowsWithOptions(windows, sortOrder: sortOrder)
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
            windows.sorted { $0.lastAccessedTime != $1.lastAccessedTime ? $0.lastAccessedTime > $1.lastAccessedTime : $0.id > $1.id }
        case .creationOrder:
            windows.sorted { $0.creationTime != $1.creationTime ? $0.creationTime < $1.creationTime : $0.id < $1.id }
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
            let bundleIds = groupingBundleIdentifiers(for: window)

            if let groupedBundleId = bundleIds.first(where: { groupedApps.contains($0) }) {
                // This is a grouped app - only keep the first window we see
                if !seenGroupedApps.contains(groupedBundleId) {
                    seenGroupedApps.insert(groupedBundleId)
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

    private static func groupingBundleIdentifiers(for window: WindowInfo) -> [String] {
        [
            window.app.bundleIdentifier,
            window.ownerApp.bundleIdentifier,
            WindowOwnerResolver.displayApp(forOwner: window.ownerApp).bundleIdentifier,
        ].compactMap { $0 }
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
        return appWindows.allSatisfy { $0.isFullscreen == true }
    }

    static func shouldQuitAppOnWindowClose(processIdentifier pid: pid_t) -> Bool {
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
        return Defaults[.quitAppOnWindowClose] &&
            readCachedWindows(for: pid).count <= 1 &&
            finder.first?.processIdentifier != pid
    }

    @discardableResult
    static func closeAllWindows(for app: NSRunningApplication, preferredWindows: [WindowInfo]? = nil, feedback: ActionFeedbackHandle? = nil) -> Int {
        if WindowActionRequest.current == nil {
            let windows = preferredWindows ?? readCachedWindows(for: app.processIdentifier)
            let targets = windows.filter { $0.app.processIdentifier == app.processIdentifier && !$0.isWindowlessApp && WindowAction.close.isSupported(for: $0) }
            let request = WindowActionOwnership.shared.begin(targets.map(PreviewWindowIdentity.init), apps: [app.processIdentifier], protect: true, replacingSingles: false)
            defer { request.finish() }
            guard !request.admitted.isEmpty else { feedback?.finishRemaining(.failed); return 0 }
            return WindowActionRequest.$current.withValue(request) {
                closeAllWindows(for: app, preferredWindows: preferredWindows, feedback: feedback)
            }
        }
        let pid = app.processIdentifier
        let sourceWindows: [WindowInfo] = if let preferredWindows {
            preferredWindows.filter { $0.app.processIdentifier == pid }
        } else {
            readCachedWindows(for: pid)
        }

        let windowsToClose = sourceWindows.filter { !$0.isWindowlessApp && WindowAction.close.isSupported(for: $0) }
        guard !windowsToClose.isEmpty else { return 0 }

        return requestWindowClosures(windowsToClose, feedback: feedback).succeeded.count
    }

    private actor CloseExecutor {
        func close(_ windows: [WindowInfo], feedback: ActionFeedbackHandle?, settleFailures: Bool) -> PreviewBatchResult {
            WindowUtil.requestWindowClosures(windows, feedback: feedback, settleFailures: settleFailures)
        }
    }

    private static let closeExecutor = CloseExecutor()

    static func closeWindows(_ windows: [WindowInfo], feedback: ActionFeedbackHandle? = nil, settleFailures: Bool = true) async -> PreviewBatchResult {
        guard !Task.isCancelled else { return PreviewBatchResult() }
        let eligible = windows.filter { WindowAction.close.isSupported(for: $0) }
        guard !eligible.isEmpty else {
            let result = PreviewBatchResult(failed: windows.count == 1 ? windows.map(PreviewWindowIdentity.init) : [])
            if settleFailures {
                for identity in result.failed {
                    feedback?.finish(identity, .failed)
                }
            }
            return result
        }
        let windows = eligible
        if WindowActionRequest.current == nil {
            return await WindowActionRequest.run(windows.filter { !$0.isWindowlessApp }.map(PreviewWindowIdentity.init), protect: true) { request in
                var result = await closeWindows(windows.filter { request.contains(PreviewWindowIdentity($0)) }, feedback: feedback, settleFailures: settleFailures)
                result.failed += request.rejected
                return result
            } ?? PreviewBatchResult(failed: windows.map(PreviewWindowIdentity.init))
        }
        return await closeExecutor.close(windows, feedback: feedback, settleFailures: settleFailures)
    }

    private static func requestWindowClosures(_ windows: [WindowInfo], feedback: ActionFeedbackHandle?, settleFailures: Bool = true) -> PreviewBatchResult {
        var result = PreviewBatchResult()
        for window in windows where !window.isWindowlessApp {
            guard !Task.isCancelled else { break }
            let identity = PreviewWindowIdentity(window)
            let accepted = window.close(progress: feedback?.closeProgress(for: identity))
            if accepted {
                result.succeeded.append(window)
                feedback?.finish(identity, .requested)
            } else if Task.isCancelled {
                break
            } else {
                result.failed.append(identity)
                if settleFailures { feedback?.finish(identity, .failed) }
            }
        }
        return result
    }

    @discardableResult
    static func minimizeAllWindows(for app: NSRunningApplication, preferredWindows: [WindowInfo]? = nil, feedback: ActionFeedbackHandle? = nil) -> Int {
        let pid = app.processIdentifier
        let preferredAppWindows = preferredWindows?.filter {
            $0.app.processIdentifier == pid && !$0.isWindowlessApp && $0.isFullscreen != true && WindowAction.minimize.isSupported(for: $0)
        } ?? []
        let cachedAppWindows = readCachedWindows(for: pid).filter {
            !$0.isWindowlessApp && $0.isFullscreen != true && WindowAction.minimize.isSupported(for: $0)
        }
        let estimatedCount = max(preferredAppWindows.count, cachedAppWindows.count)
        guard estimatedCount > 0 else { return 0 }

        let parent = WindowActionRequest.current
        let request = parent ?? WindowActionOwnership.shared.begin((preferredAppWindows + cachedAppWindows).map(PreviewWindowIdentity.init), apps: [pid])
        guard request.containsApp(pid) else { feedback?.finishRemaining(.failed); return 0 }
        let task = WindowActionRequest.$current.withValue(request) { Task {
            defer { if parent == nil { request.finish() } }
            await request.waitForPredecessors()
            guard !Task.isCancelled else { return }
            _ = await toggleAllMinimizableWindows(for: app, preferredWindows: preferredWindows, feedback: feedback)
        } }
        if parent == nil { request.onSuperseded { task.cancel() } }
        return estimatedCount
    }

    enum MinimizeAllWindowsOutcome: Equatable {
        case noEligibleWindows
        case revealedHiddenApp
        case minimized
        case restored
    }

    struct MinimizeAllWindowsResult {
        let outcome: MinimizeAllWindowsOutcome
        let confirmedCount: Int
        let eligibleCount: Int

        var shouldActivateApp: Bool {
            outcome == .revealedHiddenApp || (outcome == .restored && confirmedCount > 0)
        }
    }

    static func toggleAllMinimizableWindows(
        for app: NSRunningApplication,
        preferredWindows: [WindowInfo]? = nil,
        restoreHiddenAppIfNeeded: Bool = false,
        feedback: ActionFeedbackHandle? = nil
    ) async -> MinimizeAllWindowsResult {
        if WindowActionRequest.current == nil {
            let identity = PreviewWindowIdentity(pid: app.processIdentifier, windowID: 0)
            return await WindowActionRequest.run([identity], apps: [app.processIdentifier]) { _ in
                await toggleAllMinimizableWindows(for: app, preferredWindows: preferredWindows, restoreHiddenAppIfNeeded: restoreHiddenAppIfNeeded, feedback: feedback)
            } ?? MinimizeAllWindowsResult(outcome: .noEligibleWindows, confirmedCount: 0, eligibleCount: 0)
        }
        defer { feedback?.finishRemaining(Task.isCancelled ? .cancelled : .failed) }
        let pid = app.processIdentifier
        let cachedWindows = readCachedWindows(for: pid)
        let refreshedWindows: [WindowInfo]
        do {
            refreshedWindows = try await getActiveWindows(of: app, ignoreSingleWindowFilter: true)
        } catch {
            DebugLogger.log(
                "MinimizeAll",
                details: "\(app.localizedName ?? "Unknown"): refresh failed, using cached inventory: \(error)"
            )
            refreshedWindows = []
        }
        guard !Task.isCancelled else {
            return MinimizeAllWindowsResult(outcome: .noEligibleWindows, confirmedCount: 0, eligibleCount: 0)
        }

        var windowsByID: [CGWindowID: WindowInfo] = [:]
        let preferredAppWindows = preferredWindows?.filter { $0.app.processIdentifier == pid } ?? []
        windowsByID.reserveCapacity(preferredAppWindows.count + cachedWindows.count + refreshedWindows.count)
        for window in preferredAppWindows {
            windowsByID[window.id] = window
        }
        for window in cachedWindows {
            windowsByID[window.id] = window
        }
        for window in refreshedWindows {
            windowsByID[window.id] = window
        }

        let snapshot = await minimizableWindowSnapshot(Array(windowsByID.values))
        guard !Task.isCancelled, !snapshot.isEmpty else {
            return MinimizeAllWindowsResult(outcome: .noEligibleWindows, confirmedCount: 0, eligibleCount: 0)
        }
        feedback?.setTargets(snapshot.map(\.window))

        let allWindowsMinimized = snapshot.allSatisfy(\.isMinimized)
        if restoreHiddenAppIfNeeded, app.isHidden, !allWindowsMinimized {
            let revealed = await setHiddenStateConfirmed(for: app, isHidden: false)
            feedback?.finishRemaining(revealed ? .completed : .failed)
            return MinimizeAllWindowsResult(
                outcome: revealed ? .revealedHiddenApp : .noEligibleWindows,
                confirmedCount: 0,
                eligibleCount: snapshot.count
            )
        }

        let targetMinimizedState = !allWindowsMinimized
        if !targetMinimizedState, app.isHidden {
            guard await setHiddenStateConfirmed(for: app, isHidden: false) else {
                return MinimizeAllWindowsResult(
                    outcome: .restored,
                    confirmedCount: 0,
                    eligibleCount: snapshot.count
                )
            }
        }
        guard !Task.isCancelled else {
            return MinimizeAllWindowsResult(outcome: .noEligibleWindows, confirmedCount: 0, eligibleCount: snapshot.count)
        }

        let confirmed = await setMinimizedWindowsConfirmed(
            snapshot.map(\.window),
            isMinimized: targetMinimizedState,
            progress: feedback?.confirmedProgress
        )
        if let feedback {
            let confirmedIDs = Set(confirmed.map(PreviewWindowIdentity.init))
            feedback.finish(PreviewBatchResult(succeeded: confirmed, failed: snapshot.map { PreviewWindowIdentity($0.window) }.filter { !confirmedIDs.contains($0) }))
        }
        let confirmedCount = confirmed.count
        let outcome: MinimizeAllWindowsOutcome = targetMinimizedState ? .minimized : .restored
        DebugLogger.log(
            "MinimizeAll",
            details: "\(app.localizedName ?? "Unknown"): minimized=\(targetMinimizedState), confirmed=\(confirmedCount)/\(snapshot.count)"
        )
        return MinimizeAllWindowsResult(
            outcome: outcome,
            confirmedCount: confirmedCount,
            eligibleCount: snapshot.count
        )
    }

    @discardableResult
    static func minimizeAllWindowsGlobally() -> Int {
        minimizeAllWindowsGlobally(exclusions: GlobalMinimizeExclusions([]))
    }

    @discardableResult
    static func minimizeAllWindowsExcept(_ keptWindow: WindowInfo) -> Int {
        minimizeAllWindowsExcept([keptWindow])
    }

    @discardableResult
    static func minimizeAllWindowsExcept(_ keptWindows: [WindowInfo]) -> Int {
        minimizeAllWindowsGlobally(exclusions: GlobalMinimizeExclusions(keptWindows))
    }

    private struct GlobalMinimizeExclusions {
        let ids: Set<CGWindowID>
        let elements: [AXUIElement]

        init(_ windows: [WindowInfo]) {
            ids = Set(windows.map(\.id))
            elements = windows.map(\.axElement)
        }

        func contains(windowID: CGWindowID?, element: AXUIElement) -> Bool {
            if let windowID, ids.contains(windowID) { return true }
            return elements.contains { CFEqual($0, element) }
        }
    }

    @discardableResult
    private static func minimizeAllWindowsGlobally(
        exclusions: GlobalMinimizeExclusions
    ) -> Int {
        let targets = collectGlobalMinimizeTargetsFast(exclusions: exclusions)
        let identities = targets.map { PreviewWindowIdentity(pid: $0.pid, windowID: $0.windowID ?? 0) }
        let unknownApps = Set(targets.filter { $0.windowID == nil }.map(\.pid))
        let request = WindowActionOwnership.shared.begin(identities, apps: unknownApps)
        let admitted = targets.filter { request.contains(PreviewWindowIdentity(pid: $0.pid, windowID: $0.windowID ?? 0)) }
        guard !admitted.isEmpty else { request.finish(); return 0 }
        let initialWrite = minimizeAXWindowsAsync(admitted, request: request)
        scheduleGlobalMinimizeReconciliation(for: admitted, exclusions: exclusions, request: request, initialWrite: initialWrite)
        return admitted.count
    }

    private static func minimizeAXWindowsAsync(_ windows: [GlobalMinimizeReconciliationSnapshot], request: WindowActionRequest) -> Task<Void, Never>? {
        guard !windows.isEmpty else { return nil }
        return Task.detached(priority: .userInitiated) {
            await request.waitForPredecessors()
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: Void.self) { group in
                for window in windows {
                    group.addTask {
                        _ = await WindowFrameTransactions.run(for: window.pid) { cancellation in
                            guard !cancellation.isCancelled,
                                  request.contains(PreviewWindowIdentity(pid: window.pid, windowID: window.windowID ?? 0)) else { return }
                            try? window.element.setAttribute(kAXMinimizedAttribute, true)
                        }
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
            !WindowCandidateDiscriminator.isWineApplication(app) &&
            !isAppFiltered(app)
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
        exclusions: GlobalMinimizeExclusions
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
                  !exclusions.contains(windowID: window.id, element: window.axElement)
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
                guard !exclusions.contains(windowID: windowID, element: axWindow) else {
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
        exclusions: GlobalMinimizeExclusions
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
                guard !exclusions.contains(windowID: windowID, element: axWindow) else {
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
        exclusions: GlobalMinimizeExclusions
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

            return !exclusions.contains(windowID: window.id, element: window.axElement)
        }
    }

    private static func scheduleGlobalMinimizeReconciliation(
        for targets: [GlobalMinimizeReconciliationSnapshot],
        exclusions: GlobalMinimizeExclusions, request: WindowActionRequest, initialWrite: Task<Void, Never>?
    ) {
        guard !targets.isEmpty else { return }

        globalMinimizeReconciliationLock.lock()
        let token = request.token
        let task = Task.detached(priority: .utility) {
            defer {
                request.finish()
                _ = globalMinimizeReconciliationLock.withLock { pendingGlobalMinimizeReconciliation.removeValue(forKey: token) }
            }
            await initialWrite?.value
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
                    exclusions: exclusions
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
                    exclusions: exclusions
                ) {
                    unresolvedPIDs.remove(pid)
                }
            }

            guard !unresolvedPIDs.isEmpty else { return }

            let heavyTargets = collectGlobalMinimizeTargetsHeavy(
                for: unresolvedPIDs,
                exclusions: exclusions
            ).filter { request.contains(PreviewWindowIdentity(pid: $0.pid, windowID: $0.windowID ?? 0)) }
            guard !heavyTargets.isEmpty else { return }

            let retry = minimizeAXWindowsAsync(heavyTargets, request: request)
            await retry?.value
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }

            let (fallbackResults, _) = readGlobalMinimizeStates(for: heavyTargets)
            applyGlobalMinimizeReconciliationResults(fallbackResults)
        }
        pendingGlobalMinimizeReconciliation[token] = task
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

    static func minimizableWindowSnapshot(_ windows: [WindowInfo]) async -> [(window: WindowInfo, isMinimized: Bool)] {
        let ownBundleId = Bundle.main.bundleIdentifier
        let candidates = windows.filter {
            !$0.isWindowlessApp && $0.app.bundleIdentifier != ownBundleId && WindowAction.minimize.isSupported(for: $0)
        }
        guard !candidates.isEmpty else { return [] }

        let worker = Task.detached(priority: .userInitiated) {
            var snapshot: [(window: WindowInfo, isMinimized: Bool)] = []
            snapshot.reserveCapacity(candidates.count)
            for window in candidates {
                guard !Task.isCancelled else { return [(window: WindowInfo, isMinimized: Bool)]() }
                let isFullscreen = (try? window.axElement.isFullscreen()) ?? (window.isFullscreen == true)
                guard !isFullscreen else { continue }
                let isMinimized = (try? window.axElement.isMinimized()) ?? window.isMinimized
                snapshot.append((window, isMinimized))
            }
            return snapshot
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func minimizeWindowExitingFullscreen(_ window: WindowInfo) async -> Bool {
        if WindowActionRequest.current == nil {
            return await WindowActionRequest.run([PreviewWindowIdentity(window)]) { _ in await minimizeWindowExitingFullscreen(window) } ?? false
        }
        guard !window.isWindowlessApp, !window.app.isTerminated, !Task.isCancelled,
              WindowAction.minimize.isSupported(for: window) else { return false }
        if await window.readFullscreenState() == true {
            if await !changeFullscreenConfirmed(window) { return false }
        }
        guard !Task.isCancelled else { return false }
        return await setMinimizedStateConfirmed([window], isMinimized: true) == 1
    }

    static func restoreWindowsConfirmed(_ windows: [WindowInfo], progress: (@Sendable (PreviewWindowIdentity, Bool) -> Void)? = nil) async -> [WindowInfo] {
        if WindowActionRequest.current == nil {
            return await WindowActionRequest.run(windows.map(PreviewWindowIdentity.init)) { _ in await restoreWindowsConfirmed(windows, progress: progress) } ?? []
        }
        let candidates = windows.filter { !$0.isWindowlessApp && !$0.app.isTerminated }
        var failedApps = Set<pid_t>()
        var checkedApps = Set<pid_t>()
        for window in candidates where checkedApps.insert(window.app.processIdentifier).inserted {
            guard !Task.isCancelled else { return [] }
            if window.app.isHidden, await !setHiddenStateConfirmed(for: window.app, isHidden: false) {
                failedApps.insert(window.app.processIdentifier)
            }
        }
        guard !Task.isCancelled else { return [] }
        for window in candidates where failedApps.contains(window.app.processIdentifier) {
            progress?(PreviewWindowIdentity(window), false)
        }
        return await setMinimizedWindowsConfirmed(candidates.filter { !failedApps.contains($0.app.processIdentifier) }, isMinimized: false, progress: progress)
    }

    static func revealWindowConfirmed(_ window: WindowInfo, checkingLiveState: Bool = false) async -> Bool {
        guard !window.isWindowlessApp, !window.app.isTerminated, !Task.isCancelled else { return false }
        if window.app.isHidden || window.isHidden,
           await !setHiddenStateConfirmed(for: window.app, isHidden: false) { return false }
        guard !Task.isCancelled else { return false }
        let minimized = checkingLiveState && !window.isMinimized ? await window.readMinimizedState() : nil
        guard !Task.isCancelled else { return false }
        if window.isMinimized || minimized == true { return await setMinimizedStateConfirmed([window], isMinimized: false) == 1 }
        return true
    }

    // Publish minimized state only after AX reports the requested value.
    static func setMinimizedStateConfirmed(_ windows: [WindowInfo], isMinimized: Bool) async -> Int {
        await setMinimizedWindowsConfirmed(windows, isMinimized: isMinimized).count
    }

    static func setMinimizedWindowsConfirmed(_ windows: [WindowInfo], isMinimized: Bool,
                                             isTargetActive: @escaping @Sendable (PreviewWindowIdentity) -> Bool = { _ in true },
                                             progress: (@Sendable (PreviewWindowIdentity, Bool) -> Void)? = nil) async -> [WindowInfo]
    {
        if WindowActionRequest.current == nil {
            return await WindowActionRequest.run(windows.filter { !$0.isWindowlessApp }.map(PreviewWindowIdentity.init)) { request in
                await setMinimizedWindowsConfirmed(windows, isMinimized: isMinimized,
                                                   isTargetActive: { request.contains($0) && isTargetActive($0) }, progress: progress)
            } ?? []
        }
        let ownership = WindowActionRequest.current
        let targetIsActive: @Sendable (PreviewWindowIdentity) -> Bool = { ownership?.contains($0) == true && isTargetActive($0) }
        let ownBundleId = Bundle.main.bundleIdentifier
        let candidates = windows.filter {
            !$0.isWindowlessApp &&
                $0.app.bundleIdentifier != ownBundleId && WindowAction.minimize.isSupported(for: $0)
        }
        guard !candidates.isEmpty else { return [] }

        let worker = Task.detached(priority: .userInitiated) {
            func write(_ window: WindowInfo) async -> Bool {
                let element = window.axElement, identity = PreviewWindowIdentity(window)
                return await WindowFrameTransactions.run(for: window.ownerApp.processIdentifier) { cancellation in
                    guard !cancellation.isCancelled, targetIsActive(identity) else { return false }
                    try? element.setAttribute(kAXMinimizedAttribute, isMinimized)
                    return true
                } ?? false
            }
            var targets: [WindowInfo] = []
            for window in candidates {
                guard !Task.isCancelled else { break }
                guard targetIsActive(PreviewWindowIdentity(window)) else { continue }
                let isFullscreen = (try? window.axElement.isFullscreen()) ?? (window.isFullscreen == true)
                if !isFullscreen { targets.append(window) }
            }
            var attempted: [WindowInfo] = []
            for window in targets {
                guard !Task.isCancelled else { break }
                if await write(window) {
                    attempted.append(window)
                    try? await Task.sleep(nanoseconds: 12_000_000)
                }
            }

            var unresolved = attempted
            var confirmed: [WindowInfo] = []
            // Progress observes the existing checks; it never changes mutation scheduling.
            for (pass, delay) in [UInt64(0), 90_000_000, 220_000_000].enumerated() {
                guard !unresolved.isEmpty else { break }
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                guard !Task.isCancelled else { break }

                var stillUnresolved: [WindowInfo] = []
                for window in unresolved {
                    let identity = PreviewWindowIdentity(window)
                    guard !Task.isCancelled else { break }
                    guard targetIsActive(identity) else { continue }
                    let matches = (try? window.axElement.isMinimized()) == isMinimized
                    guard !Task.isCancelled, targetIsActive(identity) else { continue }
                    if matches {
                        confirmed.append(window)
                        progress?(identity, true)
                    } else {
                        stillUnresolved.append(window)
                    }
                }
                unresolved = stillUnresolved
                if pass == 0 {
                    for window in unresolved {
                        guard !Task.isCancelled else { break }
                        if await write(window) { try? await Task.sleep(nanoseconds: 12_000_000) }
                    }
                }
            }
            for window in unresolved where !Task.isCancelled && targetIsActive(PreviewWindowIdentity(window)) {
                progress?(PreviewWindowIdentity(window), false)
            }
            return (confirmed: confirmed, attempted: attempted)
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }

        let cancelled = Task.isCancelled
        return await MainActor.run {
            let confirmedIDs = Set(result.confirmed.map(PreviewWindowIdentity.init).filter { targetIsActive($0) })
            let confirmed = candidates.filter { confirmedIDs.contains(PreviewWindowIdentity($0)) }
            for (pid, appWindows) in Dictionary(grouping: confirmed, by: { $0.app.processIdentifier }) {
                updateCachedWindowStates(
                    for: pid,
                    matchingWindowIDs: Set(appWindows.map(\.id)),
                    insertingMissing: appWindows,
                    isMinimized: isMinimized
                )
            }
            for window in result.attempted where !confirmedIDs.contains(PreviewWindowIdentity(window)) &&
                (cancelled || !targetIsActive(PreviewWindowIdentity(window)))
            {
                scheduleCachedWindowMetadataReconciliation(pid: window.app.processIdentifier, windowID: window.id)
            }
            return cancelled ? [] : confirmed
        }
    }

    // Publish app visibility only after AX reports the requested value.
    static func setHiddenStateConfirmed(
        for app: NSRunningApplication,
        isHidden: Bool,
        fullscreenCandidates: [AXUIElement] = [],
        beforeChange: (@MainActor (Bool) -> Bool)? = nil
    ) async -> Bool {
        if WindowActionRequest.current == nil {
            let identity = PreviewWindowIdentity(pid: app.processIdentifier, windowID: 0)
            return await WindowActionRequest.run([identity], apps: [app.processIdentifier]) { _ in
                await setHiddenStateConfirmed(for: app, isHidden: isHidden, fullscreenCandidates: fullscreenCandidates, beforeChange: beforeChange)
            } ?? false
        }
        guard WindowActionRequest.current?.reserveApp(app.processIdentifier) == true else { return false }
        guard !Task.isCancelled, !app.isTerminated else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let worker = Task.detached(priority: .userInitiated) {
            do {
                if isHidden, !fullscreenCandidates.isEmpty {
                    var allFullscreen = true
                    for element in fullscreenCandidates {
                        guard !Task.isCancelled else { return false }
                        if (try? element.isFullscreen()) != true { allFullscreen = false; break }
                    }
                    guard !allFullscreen else { return false }
                }
                guard !Task.isCancelled else { return false }
                if let beforeChange {
                    guard await beforeChange(false), !Task.isCancelled else { return false }
                }
                try appElement.setAttribute(kAXHiddenAttribute, isHidden)
            } catch {
                return false
            }

            for delay in [UInt64(0), 80_000_000, 220_000_000] {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled else { return false }
                if (try? appElement.attribute(kAXHiddenAttribute, Bool.self)) == isHidden {
                    return true
                }
            }
            return false
        }
        let confirmed = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }

        guard confirmed, !Task.isCancelled else { return false }
        updateCachedWindowStates(for: app.processIdentifier, isHidden: isHidden)
        return true
    }

    @discardableResult
    static func openNewWindow(app: NSRunningApplication) -> Bool {
        let parent = WindowActionRequest.current
        let identity = PreviewWindowIdentity(pid: app.processIdentifier, windowID: 0)
        let request = parent ?? WindowActionOwnership.shared.begin([identity], apps: [app.processIdentifier], replacingSingles: false)
        defer { if parent == nil { request.finish() } }
        guard request.reserveApp(app.processIdentifier) else { return false }
        postCommandShortcut(0x2D, to: app.processIdentifier)
        return true
    }

    static func postCommandShortcut(_ keyCode: CGKeyCode, to pid: pid_t) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.postToPid(pid)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.postToPid(pid)
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
    /// Makes a window key by posting a synthetic left-mouse-down to the Window Server.
    /// Ported from https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
    static func makeKeyWindow(_ psn: inout ProcessSerialNumber, windowID: CGWindowID) {
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xF8
        bytes[0x3A] = 0x10
        var wid = UInt32(windowID)
        memcpy(&bytes[0x3C], &wid, MemoryLayout<UInt32>.size)
        // Stay far outside resize grips; a mouse-up could complete an unintended click.
        var point = CGPoint(x: 300_000, y: 300_000)
        memcpy(&bytes[0x20], &point, MemoryLayout<CGPoint>.size)
        bytes[0x08] = 0x01
        _ = SLPSPostEventRecordTo(&psn, &bytes)
    }
}

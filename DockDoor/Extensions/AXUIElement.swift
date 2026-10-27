import ApplicationServices.HIServices.AXActionConstants
import ApplicationServices.HIServices.AXAttributeConstants
import ApplicationServices.HIServices.AXError
import ApplicationServices.HIServices.AXRoleConstants
import ApplicationServices.HIServices.AXUIElement
import ApplicationServices.HIServices.AXValue
import Cocoa

// NOTE: Borrows code from https://github.com/lwouis/alt-tab-macos/blob/master/src/api-wrappers/AXUIElement.swift

private let axWindowScanStateLock = NSLock()
private struct AXWindowScanState {
    let targetWindowIDs: Set<CGWindowID>
    let cursor: AXUIElementID
}

private var axWindowScanStateByPID: [pid_t: AXWindowScanState] = [:]
private var axWindowScansInFlight = Set<pid_t>()
private let axWindowScanBudget: TimeInterval = 0.25

enum AXResponsiveness {
    private static let lock = NSLock()
    private static var unresponsiveUntil: [pid_t: Date] = [:]
    static let backoff: TimeInterval = 5
    static let hangThreshold: TimeInterval = 0.5

    static func shouldBackOff(after error: AXError, elapsed: TimeInterval) -> Bool {
        error == .cannotComplete && elapsed >= hangThreshold
    }

    static func markUnresponsive(_ pid: pid_t) {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return }
        lock.lock()
        unresponsiveUntil[pid] = Date().addingTimeInterval(backoff)
        lock.unlock()
        DebugLogger.log("AXResponsiveness", details: "PID \(pid) unresponsive, backing off \(Int(backoff))s")
    }

    static func isUnresponsive(_ pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let until = unresponsiveUntil[pid] else { return false }
        if until > Date() { return true }
        unresponsiveUntil.removeValue(forKey: pid)
        return false
    }
}

extension AXUIElement {
    func axCallWhichCanThrow<T>(_ result: AXError, _ successValue: inout T, elapsed: TimeInterval = 0) throws -> T? {
        switch result {
        case .success: return successValue
        // An instant .cannotComplete means the element isn't ready yet; only a slow one means the app is hung
        case .cannotComplete:
            var pid = pid_t(0)
            if AXResponsiveness.shouldBackOff(after: result, elapsed: elapsed), AXUIElementGetPid(self, &pid) == .success {
                AXResponsiveness.markUnresponsive(pid)
            }
            throw AxError.runtimeError
        // for other errors it's pointless to retry
        default: return nil
        }
    }

    func cgWindowId() throws -> CGWindowID? {
        var id = CGWindowID(0)
        return try axCallWhichCanThrow(_AXUIElementGetWindow(self, &id), &id)
    }

    func pid() throws -> pid_t? {
        var pid = pid_t(0)
        return try axCallWhichCanThrow(AXUIElementGetPid(self, &pid), &pid)
    }

    func attribute<T>(_ key: String, _ _: T.Type) throws -> T? {
        var value: AnyObject?
        let start = CFAbsoluteTimeGetCurrent()
        let result: AXError = if needsMainThreadAXAccess {
            DispatchQueue.main.sync {
                AXUIElementCopyAttributeValue(self, key as CFString, &value)
            }
        } else {
            AXUIElementCopyAttributeValue(self, key as CFString, &value)
        }
        return try axCallWhichCanThrow(result, &value, elapsed: CFAbsoluteTimeGetCurrent() - start) as? T
    }

    private var needsMainThreadAXAccess: Bool {
        guard !Thread.isMainThread else { return false }

        var pid = pid_t(0)
        guard AXUIElementGetPid(self, &pid) == .success else { return false }
        return pid == ProcessInfo.processInfo.processIdentifier
    }

    private func value<T>(_ key: String, _ target: T, _ type: AXValueType) throws -> T? {
        if let a = try attribute(key, AXValue.self) {
            var value = target
            let success = withUnsafeMutablePointer(to: &value) { ptr in
                AXValueGetValue(a, type, ptr)
            }
            return success ? value : nil
        }
        return nil
    }

    func position() throws -> CGPoint? {
        try value(kAXPositionAttribute, CGPoint.zero, .cgPoint)
    }

    func size() throws -> CGSize? {
        try value(kAXSizeAttribute, CGSize.zero, .cgSize)
    }

    func title() throws -> String? {
        try attribute(kAXTitleAttribute, String.self)
    }

    func parent() throws -> AXUIElement? {
        try attribute(kAXParentAttribute, AXUIElement.self)
    }

    func children() throws -> [AXUIElement]? {
        try attribute(kAXChildrenAttribute, [AXUIElement].self)
    }

    func windows() throws -> [AXUIElement]? {
        try attribute(kAXWindowsAttribute, [AXUIElement].self)
    }

    static func windowsByBruteForce(
        _ pid: pid_t,
        app: NSRunningApplication? = nil,
        targetWindowIDs: Set<CGWindowID>
    ) -> [AXUIElement] {
        guard !targetWindowIDs.isEmpty else { return [] }

        return DebugLogger.measureSlow("windowsByBruteForce", thresholdMs: 100, details: "PID: \(pid)") {
            guard let startID = beginWindowScan(pid: pid, targetWindowIDs: targetWindowIDs) else { return [] }
            defer { endWindowScan(pid: pid) }
            guard let token = CFDataCreateMutable(kCFAllocatorDefault, 20) else { return [] }

            CFDataSetLength(token, 20)
            guard let bytes = CFDataGetMutableBytePtr(token) else { return [] }
            memset(bytes, 0, 20)
            var pidField = pid
            memcpy(bytes, &pidField, 4)
            var magic = Int32(0x636F_636F)
            memcpy(bytes + 8, &magic, 4)

            var results: [AXUIElement] = []
            var remainingWindowIDs = targetWindowIDs
            var nextID = startID
            let startedAt = CFAbsoluteTimeGetCurrent()

            for axId in startID ..< AXUIElementID.max {
                if CFAbsoluteTimeGetCurrent() - startedAt >= axWindowScanBudget ||
                    (axId.isMultiple(of: 256) && AXResponsiveness.isUnresponsive(pid))
                {
                    nextID = axId
                    break
                }
                nextID = axId + 1

                var idField = axId
                memcpy(bytes + 12, &idField, 8)
                guard let el = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else {
                    continue
                }

                var windowID = CGWindowID(0)
                guard _AXUIElementGetWindow(el, &windowID) == .success,
                      remainingWindowIDs.contains(windowID),
                      (try? el.role()) == kAXWindowRole as String
                else { continue }

                if let app {
                    let attributes = WindowCandidateAttributes(axWindow: el)
                    if WindowCandidateDiscriminator.isPotentialAXWindow(
                        app: app,
                        level: windowID.cgsLevel(),
                        attributes: attributes
                    ) {
                        results.append(el)
                        remainingWindowIDs.remove(windowID)
                    }
                } else {
                    results.append(el)
                    remainingWindowIDs.remove(windowID)
                }

                if remainingWindowIDs.isEmpty {
                    nextID = 0
                    break
                }
            }

            updateWindowScanCursor(
                pid: pid,
                targetWindowIDs: remainingWindowIDs,
                nextID: remainingWindowIDs.isEmpty ? 0 : nextID
            )
            return results
        }
    }

    private static func beginWindowScan(pid: pid_t, targetWindowIDs: Set<CGWindowID>) -> AXUIElementID? {
        axWindowScanStateLock.lock()
        defer { axWindowScanStateLock.unlock() }
        guard axWindowScansInFlight.insert(pid).inserted else { return nil }
        guard let state = axWindowScanStateByPID[pid], targetWindowIDs.isSubset(of: state.targetWindowIDs) else {
            return 0
        }
        return state.cursor
    }

    private static func endWindowScan(pid: pid_t) {
        axWindowScanStateLock.lock()
        axWindowScansInFlight.remove(pid)
        axWindowScanStateLock.unlock()
    }

    private static func updateWindowScanCursor(
        pid: pid_t,
        targetWindowIDs: Set<CGWindowID>,
        nextID: AXUIElementID
    ) {
        axWindowScanStateLock.lock()
        if nextID == 0 {
            axWindowScanStateByPID.removeValue(forKey: pid)
        } else {
            axWindowScanStateByPID[pid] = AXWindowScanState(
                targetWindowIDs: targetWindowIDs,
                cursor: nextID
            )
        }
        axWindowScanStateLock.unlock()
    }

    static func resetWindowScan(for pid: pid_t) {
        axWindowScanStateLock.lock()
        axWindowScanStateByPID.removeValue(forKey: pid)
        axWindowScanStateLock.unlock()
    }

    static func allWindows(
        _ pid: pid_t,
        appElement: AXUIElement,
        app: NSRunningApplication? = nil,
        cgCandidates: [[String: AnyObject]]? = nil,
        excludingWindowIDs: Set<CGWindowID> = []
    ) -> [AXUIElement] {
        guard !AXResponsiveness.isUnresponsive(pid) else { return [] }

        return DebugLogger.measureSlow("allWindows", thresholdMs: 200, details: "PID: \(pid)") {
            var set = Set<AXUIElement>()

            do {
                let windows = try DebugLogger.measureSlow("appElement.windows()", thresholdMs: 50, details: "PID: \(pid)") {
                    try appElement.windows()
                }
                if let windows { set.formUnion(windows) }
            } catch {
                if AXResponsiveness.isUnresponsive(pid) { return [] }
            }

            let shouldInclude: (AXUIElement) -> Bool = { window in
                guard let windowID = try? window.cgWindowId() else { return true }
                return !excludingWindowIDs.contains(windowID)
            }
            set = Set(set.filter(shouldInclude))

            let candidates = cgCandidates ?? getCGWindowCandidates(for: pid)
            var knownIDs = Set(set.compactMap { try? $0.cgWindowId() }).union(excludingWindowIDs)
            var unreachedWindowIDs = unreachedCGWindowIDs(in: candidates, excluding: knownIDs, app: app)

            if !unreachedWindowIDs.isEmpty {
                if let focusedWindow = try? appElement.focusedWindow(), shouldInclude(focusedWindow) {
                    set.insert(focusedWindow)
                }
                if let mainWindow = try? appElement.mainWindow(), shouldInclude(mainWindow) {
                    set.insert(mainWindow)
                }
                knownIDs = Set(set.compactMap { try? $0.cgWindowId() }).union(excludingWindowIDs)
                unreachedWindowIDs = unreachedCGWindowIDs(in: candidates, excluding: knownIDs, app: app)
            }

            if unreachedWindowIDs.isEmpty {
                resetWindowScan(for: pid)
            } else {
                set.formUnion(windowsByBruteForce(pid, app: app, targetWindowIDs: unreachedWindowIDs))
            }

            return Array(set)
        }
    }

    func isMinimized() throws -> Bool {
        let result = try attribute(kAXMinimizedAttribute, Bool.self) == true
        return result
    }

    func isFullscreen() throws -> Bool {
        try attribute(kAXFullscreenAttribute, Bool.self) == true
    }

    func focusedWindow() throws -> AXUIElement? {
        try attribute(kAXFocusedWindowAttribute, AXUIElement.self)
    }

    func mainWindow() throws -> AXUIElement? {
        try attribute(kAXMainWindowAttribute, AXUIElement.self)
    }

    func role() throws -> String? {
        try attribute(kAXRoleAttribute, String.self)
    }

    func subrole() throws -> String? {
        try attribute(kAXSubroleAttribute, String.self)
    }

    func appIsRunning() throws -> Bool? {
        try attribute(kAXIsApplicationRunningAttribute, Bool.self)
    }

    func closeButton() throws -> AXUIElement? {
        try attribute(kAXCloseButtonAttribute, AXUIElement.self)
    }

    func nativeTabGroup() throws -> AXUIElement? {
        try children()?.first {
            try $0.role() == kAXTabGroupRole as String && $0.nativeBackgroundTabs() != nil
        }
    }

    func nativeBackgroundTabs() throws -> [AXUIElement]? {
        guard let children = try children() else { return nil }
        let tabs = try children.filter {
            try $0.role() == kAXRadioButtonRole as String && $0.subrole() == "AXTabButton"
        }
        guard !tabs.isEmpty else { return nil }

        var backgroundTabs: [AXUIElement] = []
        var selectedCount = 0
        for tab in tabs {
            switch try tab.attribute(kAXValueAttribute, NSNumber.self)?.intValue {
            case 1: selectedCount += 1
            case 0, nil: backgroundTabs.append(tab)
            default: return nil
            }
        }
        return selectedCount == 1 ? backgroundTabs : nil
    }

    func resolvedCloseButton() -> AXUIElement? {
        closeButtonResolution().button
    }

    func closeButtonResolution() -> (button: AXUIElement?, usesSemanticFallback: Bool) {
        if let standardButton = try? closeButton() {
            return (standardButton, false)
        }

        guard (try? subrole()) == "AXUnknown",
              let directChildren = try? children()
        else { return (nil, false) }

        let semanticButton = directChildren.first { element in
            guard (try? element.role()) == kAXButtonRole,
                  let description = try? element.attribute(kAXDescriptionAttribute, String.self),
                  description.localizedCaseInsensitiveCompare("Close Window") == .orderedSame
            else { return false }

            var actions: CFArray?
            return AXUIElementCopyActionNames(element, &actions) == .success &&
                (actions as? [String])?.contains(kAXPressAction) == true
        }
        return (semanticButton, semanticButton != nil)
    }

    func minimizeButton() throws -> AXUIElement? {
        try attribute(kAXMinimizeButtonAttribute, AXUIElement.self)
    }

    func zoomButton() throws -> AXUIElement? {
        try attribute(kAXZoomButtonAttribute, AXUIElement.self)
    }

    func fullscreenButton() throws -> AXUIElement? {
        try attribute(kAXFullscreenAttribute, AXUIElement.self)
    }

    func subscribeToNotification(_ axObserver: AXObserver, _ notification: String, _ callback: (() -> Void)? = nil) throws {
        let result = AXObserverAddNotification(axObserver, self, notification as CFString, nil)
        if result == .success || result == .notificationAlreadyRegistered {
            callback?()
        } else if result != .notificationUnsupported, result != .notImplemented {
            throw AxError.runtimeError
        }
    }

    func setAttribute(_ key: String, _ value: Any) throws {
        var unused: Void = ()
        let result: AXError = if needsMainThreadAXAccess {
            DispatchQueue.main.sync {
                AXUIElementSetAttributeValue(self, key as CFString, value as CFTypeRef)
            }
        } else {
            AXUIElementSetAttributeValue(self, key as CFString, value as CFTypeRef)
        }
        try axCallWhichCanThrow(result, &unused)
    }

    func performAction(_ action: String) throws {
        var unused: Void = ()
        let result: AXError = if needsMainThreadAXAccess {
            DispatchQueue.main.sync {
                AXUIElementPerformAction(self, action as CFString)
            }
        } else {
            AXUIElementPerformAction(self, action as CFString)
        }
        try axCallWhichCanThrow(result, &unused)
    }
}

enum AxError: Error {
    case runtimeError
}

typealias AXUIElementID = UInt64

// MARK: - AX Readiness Probe

/// Probes Finder's AX tree to detect post-wake AX subsystem degradation.
@MainActor
func isAccessibilityReady() async -> Bool {
    guard let pid = NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == finderAppIdentifier })?.processIdentifier
    else {
        return false
    }

    return await WindowFrameTransactions.run(for: pid) { cancellation in
        guard !cancellation.isCancelled else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)

        guard let role = try? app.role(), role == kAXApplicationRole as String,
              !cancellation.isCancelled, let windows = try? app.windows(), !cancellation.isCancelled
        else { return false }
        if windows.isEmpty { return true }

        // Finder can list its desktop scroll area when no ordinary windows are open.
        return windows.contains { element in
            guard !cancellation.isCancelled, let childRole = try? element.role() else { return false }
            return childRole == kAXWindowRole as String || childRole == kAXScrollAreaRole as String
        } && !cancellation.isCancelled
    } ?? false
}

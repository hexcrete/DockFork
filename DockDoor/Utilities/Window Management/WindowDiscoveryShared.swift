import ApplicationServices
import Cocoa
import Defaults
import ScreenCaptureKit

// Minimal provider used when we only have a CGWindowID (no SCWindow available)
struct AXFallbackProvider: WindowPropertiesProviding {
    let cgID: CGWindowID
    var windowID: CGWindowID { cgID }
    var frame: CGRect { .zero }
    var title: String? { nil }
    var owningApplicationBundleIdentifier: String? { nil }
    var owningApplicationProcessID: pid_t? { nil }
    var isOnScreen: Bool { true }
    var windowLayer: Int { 0 }
}

struct WindowCandidateAttributes {
    let title: String?
    let role: String?
    let subrole: String?
    let size: CGSize?
    let position: CGPoint?
    let hasCloseButton: Bool

    init(axWindow: AXUIElement, hasCloseButton: Bool? = nil) {
        title = try? axWindow.title()
        role = try? axWindow.role()
        subrole = try? axWindow.subrole()
        size = try? axWindow.size()
        position = try? axWindow.position()
        self.hasCloseButton = hasCloseButton ?? (axWindow.resolvedCloseButton() != nil)
    }
}

enum WindowOwnerResolver {
    static func ownerApp(for window: SCWindow) -> NSRunningApplication? {
        guard let pid = window.owningApplication?.processID else { return nil }
        return LauncherShortcutResolver.application(forProcessIdentifier: pid)
    }

    static func windowBelongsToDisplayApp(_ window: SCWindow, displayApp: NSRunningApplication) -> Bool {
        guard let owner = ownerApp(for: window) else { return false }
        return ownerBelongsToDisplayApp(owner, displayApp: displayApp)
    }

    static func ownerBelongsToDisplayApp(_ owner: NSRunningApplication, displayApp: NSRunningApplication) -> Bool {
        if owner.processIdentifier == displayApp.processIdentifier {
            return true
        }

        guard canResolveThroughDisplayApp(owner) else {
            return false
        }

        if helperBundleBelongsToDisplayApp(owner.bundleIdentifier, displayApp.bundleIdentifier) {
            return true
        }

        return executableRootsMatch(owner: owner, displayApp: displayApp)
    }

    static func displayApp(forOwner owner: NSRunningApplication) -> NSRunningApplication {
        guard canResolveThroughDisplayApp(owner) else {
            return owner
        }

        let candidates = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && ownerBelongsToDisplayApp(owner, displayApp: $0)
        }

        if let parentBundleApp = candidates
            .filter({ $0.processIdentifier != owner.processIdentifier && bundleIsParent($0.bundleIdentifier, of: owner.bundleIdentifier) })
            .sorted(by: { displayAppScore($0, forOwner: owner) > displayAppScore($1, forOwner: owner) })
            .first
        {
            return parentBundleApp
        }

        return candidates.sorted { first, second in
            displayAppScore(first, forOwner: owner) > displayAppScore(second, forOwner: owner)
        }.first ?? owner
    }

    static func isAuxiliaryOwner(_ owner: NSRunningApplication) -> Bool {
        guard canResolveThroughDisplayApp(owner) else {
            return false
        }

        return displayApp(forOwner: owner).processIdentifier != owner.processIdentifier
    }

    private static func canResolveThroughDisplayApp(_ owner: NSRunningApplication) -> Bool {
        owner.activationPolicy != .regular || owner.bundleIdentifier == nil
    }

    private static func helperBundleBelongsToDisplayApp(_ ownerBundle: String?, _ displayBundle: String?) -> Bool {
        guard let ownerBundle, let displayBundle else { return false }
        return ownerBundle == displayBundle ||
            ownerBundle.hasPrefix(displayBundle + ".")
    }

    private static func bundleIsParent(_ parentBundle: String?, of childBundle: String?) -> Bool {
        guard let parentBundle, let childBundle else { return false }
        return childBundle.hasPrefix(parentBundle + ".")
    }

    private static func executableRootsMatch(owner: NSRunningApplication, displayApp: NSRunningApplication) -> Bool {
        guard let ownerPath = owner.executableURL?.standardizedFileURL.path,
              let displayPath = displayApp.executableURL?.standardizedFileURL.path
        else { return false }

        let ownerComponents = ownerPath.split(separator: "/")
        let displayComponents = displayPath.split(separator: "/")
        let commonPrefixCount = zip(ownerComponents, displayComponents).prefix { $0 == $1 }.count

        return commonPrefixCount >= 5
    }

    private static func displayAppScore(_ displayApp: NSRunningApplication, forOwner owner: NSRunningApplication) -> Int {
        var score = 0
        if owner.processIdentifier == displayApp.processIdentifier { score += 100 }
        if owner.bundleIdentifier == displayApp.bundleIdentifier { score += 80 }
        if let ownerBundle = owner.bundleIdentifier,
           let displayBundle = displayApp.bundleIdentifier,
           ownerBundle.hasPrefix(displayBundle + ".")
        {
            score += 90
            score += max(0, 30 - (displayBundle.count / 4))
        } else if helperBundleBelongsToDisplayApp(owner.bundleIdentifier, displayApp.bundleIdentifier) {
            score += 50
        }
        if executableRootsMatch(owner: owner, displayApp: displayApp) { score += 10 }
        return score
    }
}

enum WindowCandidateDiscriminator {
    private static let minimumSize = CGSize(width: 100, height: 50)
    private static let normalLevel = CGWindowLevelForKey(.normalWindow)
    private static let floatingLevel = CGWindowLevelForKey(.floatingWindow)
    private static let unknownSubrole = "AXUnknown"
    private static let documentWindowSubrole = "AXDocumentWindow"

    static func isWineApplication(_ app: NSRunningApplication) -> Bool {
        if app.bundleIdentifier?.hasPrefix("com.codeweavers.CrossOverHelper.") == true { return true }
        guard app.bundleIdentifier == nil else { return false }
        return app.executableURL?.lastPathComponent == "wine64-preloader" ||
            (app.executableURL?.path.contains("/winetemp-") ?? false)
    }

    static func acceptsWindowLayer(app: NSRunningApplication?, level: Int32, frame: CGRect) -> Bool {
        if level == normalLevel { return true }
        guard let app, isWineApplication(app) else { return false }
        // Wine fullscreen uses status/shielding + 1, plus another level for topmost windows.
        let statusLevel = CGWindowLevelForKey(.statusWindow) + 1
        let shieldingLevel = CGShieldingWindowLevel() + 1
        guard level == statusLevel || level == statusLevel + 1 || level == shieldingLevel || level == shieldingLevel + 1,
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0
        else { return false }

        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(CGPoint(x: frame.midX, y: frame.midY), 1, &display, &count) == .success,
              count == 1
        else { return false }
        let bounds = CGDisplayBounds(display)
        return abs(frame.minX - bounds.minX) <= 1 && abs(frame.minY - bounds.minY) <= 1 &&
            abs(frame.maxX - bounds.maxX) <= 1 && abs(frame.maxY - bounds.maxY) <= 1
    }

    static func hasUsableSize(_ size: CGSize?) -> Bool {
        guard let size, size.width > 0, size.height > 0 else { return false }
        if Defaults[.disableMinWindowSizeFilter] { return true }
        return size.width >= minimumSize.width && size.height >= minimumSize.height
    }

    static func isLiveCaptureControlProxy(title: String?, size: CGSize?, level: Int32) -> Bool {
        guard Defaults[.enableLivePreview],
              Defaults[.disableMinWindowSizeFilter],
              title?.trimmingCharacters(in: .whitespacesAndNewlines) == "Window",
              level == normalLevel,
              let size
        else { return false }
        return size.width > 0 && size.height > 0 &&
            size.width <= minimumSize.width && size.height <= minimumSize.height
    }

    static func hasUsableGeometry(_ attributes: WindowCandidateAttributes) -> Bool {
        guard hasUsableSize(attributes.size) else { return false }
        if let position = attributes.position {
            return position.x.isFinite && position.y.isFinite
        }
        return true
    }

    static func isActualWindow(app: NSRunningApplication,
                               windowID: CGWindowID,
                               level: Int32,
                               attributes: WindowCandidateAttributes) -> Bool
    {
        rejectionReason(app: app, windowID: windowID, level: level, attributes: attributes) == nil
    }

    static func rejectionReason(app: NSRunningApplication,
                                windowID: CGWindowID,
                                level: Int32,
                                attributes: WindowCandidateAttributes) -> String?
    {
        guard windowID != 0 else { return "missing CGWindowID" }
        return potentialRejectionReason(app: app, level: level, attributes: attributes)
    }

    static func isPotentialAXWindow(app: NSRunningApplication,
                                    level: Int32?,
                                    attributes: WindowCandidateAttributes) -> Bool
    {
        potentialRejectionReason(app: app, level: level, attributes: attributes) == nil
    }

    private static func potentialRejectionReason(app: NSRunningApplication,
                                                 level: Int32?,
                                                 attributes: WindowCandidateAttributes) -> String?
    {
        if let level, isLiveCaptureControlProxy(title: attributes.title, size: attributes.size, level: level) {
            return "live capture control proxy"
        }
        guard hasUsableGeometry(attributes) else { return "unusable geometry" }

        let specialApp = books(app) ||
            keynote(app) ||
            preview(app, attributes.subrole) ||
            openFLStudio(app, attributes.title) ||
            (level.map { actionableFloatingWindow(attributes.role, attributes.subrole, attributes.hasCloseButton, $0) } ?? false) ||
            (level.map { crossoverWindow(app, attributes, $0) } ?? false) ||
            (level.map { alwaysOnTopScrcpy(app, $0, attributes.role, attributes.subrole) } ?? false)

        // Floating panels pass the subrole check but are not switchable app windows
        // (e.g. Outlook's meeting-reminder toast is an AXDialog at floating level 3).
        // The SC discovery path already enforces windowLayer == 0; this keeps the AX
        // path consistent. Apps that legitimately float have explicit rules below.
        let isNormalLevel = level == nil || level == normalLevel
        let standardSubrole = isNormalLevel && [kAXStandardWindowSubrole, kAXDialogSubrole].contains(attributes.subrole)
        let appSpecificSubrole = openBoard(app) ||
            adobeAudition(app, attributes.subrole) ||
            adobeAfterEffects(app, attributes.subrole) ||
            steam(app, attributes.title, attributes.role) ||
            worldOfWarcraft(app, attributes.role) ||
            battleNetBootstrapper(app, attributes.role) ||
            firefox(app, attributes.role, attributes.size) ||
            vlcFullscreenVideo(app, attributes.role) ||
            sanGuoShaAirWD(app) ||
            dvdFab(app) ||
            drBetotte(app) ||
            androidEmulator(app, attributes.title, attributes.role, level) ||
            autocad(app, attributes.subrole)

        guard specialApp || standardSubrole || appSpecificSubrole else {
            return "subrole is not standard/dialog at normal level and no app-specific rule matched"
        }

        if !specialApp {
            guard mustHaveIfJetBrainsApp(app, attributes.title, attributes.subrole, attributes.size),
                  mustHaveIfSteam(app, attributes.title, attributes.role),
                  mustHaveIfFusion360(app, attributes.title),
                  mustHaveIfColorSlurp(app, attributes.subrole)
            else { return "app-specific hard requirement failed" }
        }

        return nil
    }

    private static func hasNonEmptyTitle(_ title: String?) -> Bool {
        guard let title else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func mustHaveIfFusion360(_ app: NSRunningApplication, _ title: String?) -> Bool {
        app.bundleIdentifier != "com.autodesk.fusion360" || hasNonEmptyTitle(title)
    }

    private static func mustHaveIfJetBrainsApp(_ app: NSRunningApplication, _ title: String?, _ subrole: String?, _ size: CGSize?) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier,
              bundleIdentifier.hasPrefix("com.jetbrains.") || bundleIdentifier.hasPrefix("com.google.android.studio")
        else { return true }

        return (subrole == kAXStandardWindowSubrole || hasNonEmptyTitle(title)) &&
            (size?.width ?? 0) > 100 &&
            (size?.height ?? 0) > 100
    }

    private static func mustHaveIfColorSlurp(_ app: NSRunningApplication, _ subrole: String?) -> Bool {
        app.bundleIdentifier != "com.IdeaPunch.ColorSlurp" || subrole == kAXStandardWindowSubrole
    }

    private static func keynote(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.apple.iWork.Keynote"
    }

    private static func preview(_ app: NSRunningApplication, _ subrole: String?) -> Bool {
        app.bundleIdentifier == "com.apple.Preview" && [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole)
    }

    private static func openFLStudio(_ app: NSRunningApplication, _ title: String?) -> Bool {
        app.bundleIdentifier == "com.image-line.flstudio" && hasNonEmptyTitle(title)
    }

    private static func openBoard(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "org.oe-f.OpenBoard"
    }

    private static func adobeAudition(_ app: NSRunningApplication, _ subrole: String?) -> Bool {
        app.bundleIdentifier == "com.adobe.Audition" && subrole == kAXFloatingWindowSubrole
    }

    private static func adobeAfterEffects(_ app: NSRunningApplication, _ subrole: String?) -> Bool {
        app.bundleIdentifier == "com.adobe.AfterEffects" && subrole == kAXFloatingWindowSubrole
    }

    private static func books(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.apple.iBooksX"
    }

    private static func worldOfWarcraft(_ app: NSRunningApplication, _ role: String?) -> Bool {
        app.bundleIdentifier == "com.blizzard.worldofwarcraft" && role == kAXWindowRole
    }

    private static func battleNetBootstrapper(_ app: NSRunningApplication, _ role: String?) -> Bool {
        app.bundleIdentifier == "net.battle.bootstrapper" && role == kAXWindowRole
    }

    private static func drBetotte(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.ssworks.drbetotte"
    }

    private static func dvdFab(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.goland.dvdfab.macos"
    }

    private static func sanGuoShaAirWD(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "SanGuoShaAirWD"
    }

    private static func steam(_ app: NSRunningApplication, _ title: String?, _ role: String?) -> Bool {
        app.bundleIdentifier == "com.valvesoftware.steam" && hasNonEmptyTitle(title) && role != nil
    }

    private static func mustHaveIfSteam(_ app: NSRunningApplication, _ title: String?, _ role: String?) -> Bool {
        app.bundleIdentifier != "com.valvesoftware.steam" || (hasNonEmptyTitle(title) && role != nil)
    }

    private static func firefox(_ app: NSRunningApplication, _ role: String?, _ size: CGSize?) -> Bool {
        (app.bundleIdentifier?.hasPrefix("org.mozilla.firefox") ?? false) &&
            role == kAXWindowRole &&
            (size?.height ?? 0) > 400
    }

    private static func vlcFullscreenVideo(_ app: NSRunningApplication, _ role: String?) -> Bool {
        (app.bundleIdentifier?.hasPrefix("org.videolan.vlc") ?? false) && role == kAXWindowRole
    }

    private static func androidEmulator(_ app: NSRunningApplication, _ title: String?, _ role: String?, _ level: Int32?) -> Bool {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard app.bundleIdentifier == nil,
              role == kAXWindowRole,
              let title,
              !title.isEmpty,
              title != "Window",
              level == nil || level == normalLevel
        else { return false }
        return app.executableURL?.lastPathComponent.range(of: "qemu-system[^/]*$", options: .regularExpression) != nil
    }

    private static func crossoverWindow(_ app: NSRunningApplication, _ attributes: WindowCandidateAttributes, _ level: Int32) -> Bool {
        guard attributes.role == kAXWindowRole, attributes.subrole == unknownSubrole,
              isWineApplication(app), app.bundleIdentifier == nil || hasNonEmptyTitle(attributes.title)
        else { return false }
        if level == normalLevel { return true }
        guard hasNonEmptyTitle(attributes.title), let position = attributes.position, let size = attributes.size else { return false }
        return acceptsWindowLayer(app: app, level: level, frame: CGRect(origin: position, size: size))
    }

    private static func actionableFloatingWindow(_ role: String?, _ subrole: String?, _ hasCloseButton: Bool, _ level: Int32) -> Bool {
        role == kAXWindowRole &&
            subrole == unknownSubrole &&
            level == floatingLevel &&
            hasCloseButton
    }

    private static func alwaysOnTopScrcpy(_ app: NSRunningApplication, _ level: Int32, _ role: String?, _ subrole: String?) -> Bool {
        app.executableURL?.lastPathComponent == "scrcpy" &&
            level == floatingLevel &&
            role == kAXWindowRole &&
            subrole == kAXStandardWindowSubrole
    }

    private static func autocad(_ app: NSRunningApplication, _ subrole: String?) -> Bool {
        (app.bundleIdentifier?.hasPrefix("com.autodesk.AutoCAD") ?? false) && subrole == documentWindowSubrole
    }
}

/// Heuristic mapping from AX window to CG window when _AXUIElementGetWindow fails
func mapAXToCG(attributes: WindowCandidateAttributes, candidates: [[String: AnyObject]], excluding: Set<CGWindowID>) -> CGWindowID? {
    let axTitle = attributes.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let axPos = attributes.position
    let axSize = attributes.size

    // 1) Exact title match among unused candidates
    if !axTitle.isEmpty {
        if let match = candidates.first(where: { desc in
            let title = (desc[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let wid = CGWindowID((desc[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            return title == axTitle && !excluding.contains(wid)
        }) {
            return CGWindowID((match[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        }
    }

    // 2) Geometry match within tolerance
    if let p = axPos, let s = axSize, s != .zero {
        let tol: CGFloat = 2.0
        if let match = candidates.first(where: { desc in
            let wid = CGWindowID((desc[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            if excluding.contains(wid) { return false }
            let bounds = desc[kCGWindowBounds as String] as? [String: AnyObject]
            let rx = CGFloat((bounds?["X"] as? NSNumber)?.doubleValue ?? .infinity)
            let ry = CGFloat((bounds?["Y"] as? NSNumber)?.doubleValue ?? .infinity)
            let rw = CGFloat((bounds?["Width"] as? NSNumber)?.doubleValue ?? .infinity)
            let rh = CGFloat((bounds?["Height"] as? NSNumber)?.doubleValue ?? .infinity)
            let r = CGRect(x: rx, y: ry, width: rw, height: rh)
            let posMatch = abs(r.origin.x - p.x) <= tol && abs(r.origin.y - p.y) <= tol
            let sizeMatch = abs(r.size.width - s.width) <= tol && abs(r.size.height - s.height) <= tol
            return posMatch && sizeMatch
        }) {
            return CGWindowID((match[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        }
    }

    // 3) Fuzzy title contains
    if !axTitle.isEmpty {
        if let match = candidates.first(where: { desc in
            let title = ((desc[kCGWindowName as String] as? String) ?? "").lowercased()
            let wid = CGWindowID((desc[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            return !excluding.contains(wid) && title.contains(axTitle.lowercased())
        }) {
            return CGWindowID((match[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        }
    }

    return nil
}

// MARK: - Shared Helper Functions

/// Returns CG window candidates for a given PID.
func getCGWindowCandidates(for pid: pid_t) -> [[String: AnyObject]] {
    let cgAll = (CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: AnyObject]]) ?? []
    return cgAll.filter { desc in
        let owner = (desc[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        return owner == pid
    }.sorted { first, second in
        let firstLayer = (first[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let secondLayer = (second[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        return firstLayer == 0 && secondLayer != 0
    }
}

/// Finds the CG window entry matching a given window ID in the candidates list
func findCGEntry(for windowID: CGWindowID, in candidates: [[String: AnyObject]]) -> [String: AnyObject]? {
    candidates.first { desc in
        let wid = CGWindowID((desc[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        return wid == windowID
    }
}

/// Finds an exact CG window entry by owner PID and window ID across all layers.
func findCGEntry(for windowID: CGWindowID, ownerPID: pid_t) -> [String: AnyObject]? {
    let cgAll = (CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: AnyObject]]) ?? []
    return cgAll.first { desc in
        let wid = CGWindowID((desc[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        let owner = (desc[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        return wid == windowID && owner == ownerPID
    }
}

func unreachedCGWindowIDs(
    in candidates: [[String: AnyObject]],
    excluding knownIDs: Set<CGWindowID>,
    app: NSRunningApplication? = nil
) -> Set<CGWindowID> {
    let activeSpaceIDs = currentActiveSpaceIDs()
    lazy var managedSpaceIDs = WindowSpaces.allManagedSpaceIDs()

    return Set(candidates.compactMap { entry in
        let windowID = CGWindowID((entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        guard windowID != 0,
              !WindowUtil.isInternalWindow(windowID),
              !knownIDs.contains(windowID),
              let level = (entry[kCGWindowLayer as String] as? NSNumber)?.int32Value,
              isValidCGWindowEntry(entry)
        else { return nil }
        if level != 0 {
            guard let bounds = entry[kCGWindowBounds as String] as? [String: AnyObject],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  WindowCandidateDiscriminator.acceptsWindowLayer(app: app, level: level, frame: frame)
            else { return nil }
        }

        let isOnScreen = (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        let spaceIDs = Set(windowID.cgsSpaces().map { Int($0) })
        let isOnManagedSpace = !spaceIDs.isEmpty && !spaceIDs.isDisjoint(with: managedSpaceIDs)
        guard isOnScreen || spaceIDs.isEmpty || (isOnManagedSpace && spaceIDs.isDisjoint(with: activeSpaceIDs)) else {
            return nil
        }
        return windowID
    })
}

// MARK: - Shared Validation

let AXMinWindowSize: CGSize = .init(width: 100, height: 100)

func isValidCGWindowCandidate(_ id: CGWindowID, in candidates: [[String: AnyObject]]) -> Bool {
    guard let match = candidates.first(where: { desc -> Bool in
        let wid = CGWindowID((desc[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        return wid == id
    }) else { return false }

    return isValidCGWindowEntry(match)
}

func isValidCGWindowEntry(_ match: [String: AnyObject]) -> Bool {
    let bounds = match[kCGWindowBounds as String] as? [String: AnyObject]
    let rw = CGFloat((bounds?["Width"] as? NSNumber)?.doubleValue ?? 0)
    let rh = CGFloat((bounds?["Height"] as? NSNumber)?.doubleValue ?? 0)
    let alpha = CGFloat((match[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0)
    if !WindowCandidateDiscriminator.hasUsableSize(CGSize(width: rw, height: rh)) { return false }
    if alpha <= 0.01 { return false }
    return true
}

private struct CGWindowGeometryKey: Hashable {
    let ownerPID: pid_t
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private func geometryKey(for entry: [String: AnyObject]) -> CGWindowGeometryKey? {
    guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
          isValidCGWindowEntry(entry),
          let ownerPID = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
          ownerPID != 0,
          let bounds = entry[kCGWindowBounds as String] as? [String: AnyObject],
          let x = (bounds["X"] as? NSNumber)?.doubleValue,
          let y = (bounds["Y"] as? NSNumber)?.doubleValue,
          let width = (bounds["Width"] as? NSNumber)?.doubleValue,
          let height = (bounds["Height"] as? NSNumber)?.doubleValue
    else { return nil }

    return CGWindowGeometryKey(
        ownerPID: ownerPID,
        x: x,
        y: y,
        width: width,
        height: height
    )
}

func unspacedGeometryAliasWindowIDs(in candidates: [[String: AnyObject]]) -> Set<CGWindowID> {
    let windows = candidates.compactMap { entry -> (id: CGWindowID, geometry: CGWindowGeometryKey, spaces: Set<Int>)? in
        let windowID = CGWindowID((entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        guard windowID != 0, let geometry = geometryKey(for: entry) else { return nil }
        return (windowID, geometry, Set(windowID.cgsSpaces().map { Int($0) }))
    }
    let spaceBackedGeometries = Set(windows.compactMap { window in
        window.spaces.isEmpty ? nil : window.geometry
    })

    return Set(windows.compactMap { window in
        window.spaces.isEmpty && spaceBackedGeometries.contains(window.geometry) ? window.id : nil
    })
}

func isNoninteractiveUntitledDialog(_ axWindow: AXUIElement) -> Bool {
    guard (try? axWindow.subrole()) == kAXDialogSubrole,
          let title = try? axWindow.title(),
          title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          ((try? axWindow.attribute(kAXIdentifierAttribute, String.self)) ?? "").isEmpty,
          (try? axWindow.closeButton()) == nil,
          (try? axWindow.minimizeButton()) == nil,
          (try? axWindow.attribute(kAXMainAttribute, Bool.self)) == false,
          (try? axWindow.attribute(kAXFocusedAttribute, Bool.self)) == false,
          (try? axWindow.attribute(kAXModalAttribute, Bool.self)) == false,
          (try? axWindow.isMinimized()) != true,
          (try? axWindow.isFullscreen()) != true,
          let children = try? axWindow.children(),
          children.isEmpty
    else { return false }

    return true
}

// Returns the set of currently active Space IDs across all displays.
func currentActiveSpaceIDs() -> Set<Int> {
    // Primary: ask macOS directly for the current space per display
    if let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: AnyObject]] {
        var result = Set<Int>()
        for display in displays {
            if let currentSpace = display["Current Space"] as? [String: AnyObject],
               let spaceID = (currentSpace["ManagedSpaceID"] as? NSNumber)?.intValue
            {
                result.insert(spaceID)
            }
        }
        if !result.isEmpty { return result }
    }

    // Fallback: infer from on-screen windows
    var result = Set<Int>()
    guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: AnyObject]] else { return result }
    for desc in list {
        let layer = (desc[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
        let isOnscreen = (desc[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        guard layer == 0, isOnscreen else { continue }
        let wid = CGWindowID((desc[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        for space in wid.cgsSpaces() {
            result.insert(Int(space))
        }
    }
    return result
}

enum ManagedSpaceKind: Int {
    case desktop = 0
    case system = 2
    case fullscreen = 4
}

struct ManagedSpaceDescriptor {
    let id: CGSSpaceID
    let kind: ManagedSpaceKind?
    let number: Int
    let desktopNumber: Int?
    let ownerPIDs: Set<pid_t>
}

struct ManagedDisplayDescriptor {
    let identifier: String
    let currentSpaceID: CGSSpaceID?
    let spaces: [ManagedSpaceDescriptor]
}

struct ManagedSpaceDestination {
    let display: ManagedDisplayDescriptor
    let space: ManagedSpaceDescriptor
}

enum ManagedSpacePresentation {
    struct App {
        let application: NSRunningApplication
        let windowIdentities: [PreviewWindowIdentity]

        var windowCount: Int { windowIdentities.count }
    }

    struct Entry: Identifiable {
        let destination: ManagedSpaceDestination
        let apps: [App]

        var id: CGSSpaceID { destination.space.id }
        var isCurrent: Bool { destination.display.currentSpaceID == id }
        var isFullscreen: Bool { destination.space.kind == .fullscreen }

        func title(mode: SpaceMenuDisplayMode) -> String {
            switch mode {
            case .numberOnly:
                return "\(destination.space.number)"
            case .fullName:
                if destination.space.kind == .desktop {
                    return String(localized: "Desktop \(destination.space.desktopNumber ?? destination.space.number)", comment: "Desktop name in Space destination menu")
                }
                let names = apps.compactMap(\.application.localizedName)
                return names.isEmpty
                    ? String(localized: "Full Screen", comment: "Fallback fullscreen Space name")
                    : names.joined(separator: " + ")
            }
        }
    }

    struct Display: Identifiable {
        let id: String
        let name: String
        let spaces: [Entry]
    }

    @MainActor
    static func snapshot(displays: [ManagedDisplayDescriptor], orderedWindows: [WindowInfo]) -> [Display] {
        var windowsBySpace: [CGSSpaceID: [(NSRunningApplication, PreviewWindowIdentity)]] = [:]
        var applicationsByPID: [pid_t: NSRunningApplication] = [:]
        var applicationOrder: [pid_t: Int] = [:]
        var seenWindows = Set<PreviewWindowIdentity>()
        let visibleSpaces = Set(displays.flatMap(\.spaces).filter { $0.kind == .desktop || $0.kind == .fullscreen }.map(\.id))
        guard !visibleSpaces.isEmpty else { return [] }

        for window in orderedWindows {
            guard !window.isWindowlessApp, window.id != 0, !window.app.isTerminated,
                  !WindowUtil.isInternalWindow(window.id),
                  seenWindows.insert(PreviewWindowIdentity(window)).inserted
            else { continue }
            applicationsByPID[window.app.processIdentifier] = window.app
            applicationsByPID[window.ownerApp.processIdentifier] = window.app
            let pid = window.app.processIdentifier
            if applicationOrder[pid] == nil { applicationOrder[pid] = applicationOrder.count }
            for spaceID in WindowSpaces.sourceSpaceIDs(for: window).intersection(visibleSpaces) {
                windowsBySpace[spaceID, default: []].append((window.app, PreviewWindowIdentity(window)))
            }
        }

        return displays.enumerated().compactMap { displayIndex, display in
            let spaces = display.spaces.filter { $0.kind == .desktop || $0.kind == .fullscreen }.map { space in
                var order: [String] = []
                var applications: [String: NSRunningApplication] = [:]
                var identities: [String: [PreviewWindowIdentity]] = [:]

                func add(_ app: NSRunningApplication, window: PreviewWindowIdentity? = nil) {
                    let key = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
                    if applications[key] == nil {
                        applications[key] = app
                        order.append(key)
                    }
                    if let window { identities[key, default: []].append(window) }
                }

                for (app, identity) in windowsBySpace[space.id] ?? [] {
                    add(app, window: identity)
                }
                // Fullscreen ownership can be available before its window enters the cache.
                if space.kind == .fullscreen {
                    var owners = space.ownerPIDs.sorted().compactMap { pid -> NSRunningApplication? in
                        guard let app = applicationsByPID[pid] ?? NSRunningApplication(processIdentifier: pid),
                              !app.isTerminated, pid != ProcessInfo.processInfo.processIdentifier
                        else { return nil }
                        return app
                    }
                    owners.sort {
                        let first = applicationOrder[$0.processIdentifier, default: Int.max]
                        let second = applicationOrder[$1.processIdentifier, default: Int.max]
                        return first == second ? $0.processIdentifier < $1.processIdentifier : first < second
                    }
                    for app in owners {
                        add(app)
                    }
                }
                let apps = order.compactMap { key -> App? in
                    guard let app = applications[key] else { return nil }
                    return App(application: app, windowIdentities: identities[key] ?? [])
                }
                return Entry(destination: ManagedSpaceDestination(display: display, space: space), apps: apps)
            }
            guard !spaces.isEmpty else { return nil }
            let fallback = String(localized: "Display \(displayIndex + 1)", comment: "Fallback display name in Space destination menu")
            return Display(id: display.identifier, name: WindowSpaces.displayName(for: display.identifier) ?? fallback, spaces: spaces)
        }
    }
}

enum ManagedSpaceMoveValidationError: Equatable {
    case windowless
    case fullscreen
    case multipleDesktopSpaces
    case unavailableDestination
    case alreadyOnDestination
}

enum ManagedSpacesTopology {
    private static func spaceID(from dictionary: [String: AnyObject]?) -> CGSSpaceID? {
        if let managedSpaceID = dictionary?["ManagedSpaceID"] as? NSNumber {
            return managedSpaceID.uint64Value
        }
        if let id64 = dictionary?["id64"] as? NSNumber {
            return id64.uint64Value
        }
        return nil
    }

    private static func ownerPIDs(in value: Any) -> Set<pid_t> {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: Set<pid_t>()) { result, entry in
                if entry.key.caseInsensitiveCompare("pid") == .orderedSame,
                   let pid = entry.value as? NSNumber,
                   pid.int32Value > 0
                {
                    result.insert(pid.int32Value)
                }
                result.formUnion(ownerPIDs(in: entry.value))
            }
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<pid_t>()) { result, child in
                result.formUnion(ownerPIDs(in: child))
            }
        }
        return []
    }

    static func snapshot(includeOwners: Bool = false) -> [ManagedDisplayDescriptor] {
        guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: AnyObject]] else {
            return []
        }

        var spaceNumber = 1
        var desktopNumber = 1

        return displays.compactMap { display in
            guard let identifier = display["Display Identifier"] as? String else { return nil }
            let currentSpace = display["Current Space"] as? [String: AnyObject]
            let rawSpaces = display["Spaces"] as? [[String: AnyObject]] ?? []
            let spaces = rawSpaces.compactMap { space -> ManagedSpaceDescriptor? in
                guard let id = spaceID(from: space) else { return nil }
                let kind = (space["type"] as? NSNumber).flatMap { ManagedSpaceKind(rawValue: $0.intValue) }
                let descriptor = ManagedSpaceDescriptor(
                    id: id,
                    kind: kind,
                    number: spaceNumber,
                    desktopNumber: kind == .desktop ? desktopNumber : nil,
                    ownerPIDs: includeOwners ? ownerPIDs(in: space) : []
                )
                spaceNumber += 1
                if kind == .desktop {
                    desktopNumber += 1
                }
                return descriptor
            }

            return ManagedDisplayDescriptor(
                identifier: identifier,
                currentSpaceID: spaceID(from: currentSpace),
                spaces: spaces
            )
        }
    }
}

enum SpaceNumberResolver {
    private static let lock = NSLock()
    private static let refreshLock = NSLock()
    private static var numbersByID: [Int: Int] = [:]
    private static var hasLoaded = false
    private static var missingSpaceRefreshTimes: [Int: TimeInterval] = [:]
    private static let missingSpaceRefreshInterval: TimeInterval = 0.35

    static func refresh() {
        refreshLock.lock()
        defer { refreshLock.unlock() }

        var refreshed: [Int: Int] = [:]
        for display in ManagedSpacesTopology.snapshot() {
            for space in display.spaces {
                refreshed[Int(space.id)] = space.number
            }
        }

        guard !refreshed.isEmpty else { return }

        lock.lock()
        numbersByID = refreshed
        hasLoaded = true
        let staleRetryCutoff = Date.timeIntervalSinceReferenceDate - missingSpaceRefreshInterval
        missingSpaceRefreshTimes = missingSpaceRefreshTimes.filter {
            refreshed[$0.key] == nil && $0.value >= staleRetryCutoff
        }
        lock.unlock()
    }

    static func refreshIfNeeded(for spaceID: Int?) {
        guard let spaceID else { return }

        let now = Date.timeIntervalSinceReferenceDate
        lock.lock()
        let missingFromLoadedTopology = hasLoaded && numbersByID[spaceID] == nil
        let canRetryMissingSpace = now - (missingSpaceRefreshTimes[spaceID] ?? 0) >= missingSpaceRefreshInterval
        let shouldRefresh = !hasLoaded || (missingFromLoadedTopology && canRetryMissingSpace)
        if missingFromLoadedTopology, canRetryMissingSpace {
            missingSpaceRefreshTimes[spaceID] = now
        }
        lock.unlock()

        if shouldRefresh {
            refresh()
        }
    }

    static func number(for spaceID: Int?) -> Int? {
        guard let spaceID else { return nil }
        refreshIfNeeded(for: spaceID)

        lock.lock()
        defer { lock.unlock() }
        guard numbersByID.count > 1 else { return nil }
        return numbersByID[spaceID]
    }
}

struct SpaceVisitHistory {
    private var current: [String: CGSSpaceID] = [:]
    private var visits: [CGSSpaceID: UInt64] = [:]
    private var sequence: UInt64 = 0

    mutating func update(_ displays: [ManagedDisplayDescriptor]) {
        let valid = Set(displays.flatMap(\.spaces).map(\.id))
        visits = visits.filter { valid.contains($0.key) }
        sequence &+= 1
        var next: [String: CGSSpaceID] = [:]
        for display in displays {
            guard let id = display.currentSpaceID, valid.contains(id) else { continue }
            next[display.identifier] = id
            if current[display.identifier] != id { visits[id] = sequence }
        }
        current = next
    }

    func ordered(_ ids: [CGSSpaceID]) -> [CGSSpaceID] {
        ids.enumerated().sorted {
            let first = visits[$0.element, default: 0], second = visits[$1.element, default: 0]
            return first == second ? $0.offset < $1.offset : first > second
        }.map(\.element)
    }
}

enum SpaceContentsAction {
    case move, swap, shift

    var menuTitle: String {
        switch self {
        case .move: String(localized: "Move Contents")
        case .swap: String(localized: "Swap Contents")
        case .shift: String(localized: "Shift Contents")
        }
    }

    var title: String {
        switch self {
        case .move: String(localized: "Move")
        case .swap: String(localized: "Swap")
        case .shift: String(localized: "Shift")
        }
    }
}

struct SpaceContentsGap: Hashable {
    let displayID: String
    let beforeSpaceID: CGSSpaceID?
}

enum SpaceContentsDropTarget: Equatable {
    case space(CGSSpaceID)
    case gap(SpaceContentsGap)
}

enum SpaceContentsError: LocalizedError {
    case invalidDestination, sameSpace, differentDisplays, topologyChanged

    var errorDescription: String? {
        switch self {
        case .invalidDestination: String(localized: "Only existing Desktop Spaces can exchange contents.")
        case .sameSpace: String(localized: "Choose a different Desktop Space.")
        case .differentDisplays: String(localized: "Content shifting requires Desktops on the same display.")
        case .topologyChanged: String(localized: "Spaces changed before the operation began. Try again.")
        }
    }
}

struct SpaceContentsTopology: Equatable {
    struct Slot: Equatable { let id: CGSSpaceID; let kind: Int? }
    struct Display: Equatable { let id: String; let slots: [Slot] }
    let displays: [Display]

    init(_ displays: [ManagedDisplayDescriptor], involving ids: Set<CGSSpaceID>? = nil) {
        self.displays = displays.filter { display in
            guard let ids else { return true }
            return display.spaces.contains { ids.contains($0.id) }
        }
        .map { Display(id: $0.identifier, slots: $0.spaces.map { Slot(id: $0.id, kind: $0.kind?.rawValue) }) }
        .sorted { $0.id < $1.id }
    }
}

enum SpaceContentsLayout {
    static func destinations(from source: CGSSpaceID, to target: CGSSpaceID, action: SpaceContentsAction,
                             displays: [ManagedDisplayDescriptor]) throws -> [CGSSpaceID: CGSSpaceID]
    {
        guard let first = displays.first(where: { $0.spaces.contains { $0.id == source && $0.kind == .desktop } }),
              let last = displays.first(where: { $0.spaces.contains { $0.id == target && $0.kind == .desktop } }) else { throw SpaceContentsError.invalidDestination }
        guard source != target else { throw SpaceContentsError.sameSpace }
        switch action {
        case .move: return [source: target]
        case .swap: return [source: target, target: source]
        case .shift:
            guard first.identifier == last.identifier else { throw SpaceContentsError.differentDisplays }
            let ids = first.spaces.filter { $0.kind == .desktop }.map(\.id)
            guard let start = ids.firstIndex(of: source), let end = ids.firstIndex(of: target) else { throw SpaceContentsError.invalidDestination }
            var mapping = [source: target]
            if start < end {
                for index in (start + 1) ... end {
                    mapping[ids[index]] = ids[index - 1]
                }
            } else {
                for index in end ..< start {
                    mapping[ids[index]] = ids[index + 1]
                }
            }
            return mapping
        }
    }

    static func dragSymbol(for target: SpaceContentsDropTarget?, source: CGSSpaceID, swapping: Bool, displays: [ManagedDisplayDescriptor]) -> String {
        switch target {
        case let .space(id):
            guard id != source, displays.contains(where: { $0.spaces.contains { $0.id == id && $0.kind == .desktop } }) else { return "nosign" }
            return swapping ? "arrow.left.arrow.right" : "arrow.triangle.merge"
        case let .gap(gap):
            guard let target = destination(for: gap, source: source, displays: displays),
                  let spaces = displays.first(where: { $0.identifier == gap.displayID })?.spaces,
                  let first = spaces.firstIndex(where: { $0.id == source }), let last = spaces.firstIndex(where: { $0.id == target }) else { return "nosign" }
            return first < last ? "arrow.left" : "arrow.right"
        case nil: return "nosign"
        }
    }

    static func destination(for gap: SpaceContentsGap, source: CGSSpaceID, displays: [ManagedDisplayDescriptor]) -> CGSSpaceID? {
        guard let display = displays.first(where: { $0.identifier == gap.displayID }),
              let sourceIndex = display.spaces.firstIndex(where: { $0.id == source && $0.kind == .desktop }) else { return nil }
        let boundary: Int
        if let before = gap.beforeSpaceID {
            guard let index = display.spaces.firstIndex(where: { $0.id == before && $0.kind == .desktop }) else { return nil }
            boundary = index
        } else { boundary = display.spaces.count }
        let candidates = sourceIndex < boundary ? Array(display.spaces[..<boundary]).reversed().map { $0 } : Array(display.spaces[boundary...])
        guard let target = candidates.first(where: { $0.kind == .desktop })?.id, target != source else { return nil }
        return target
    }
}

struct SpaceContentsPlan {
    struct Move {
        let window: WindowInfo
        let sourceID: CGSSpaceID
        let destination: ManagedSpaceDestination
    }

    let topology: SpaceContentsTopology
    let involvedIDs: Set<CGSSpaceID>
    let moves: [Move]
}

enum WindowSpaces {
    @MainActor private static var barVisits = SpaceVisitHistory()

    @MainActor static func recordBarSpaceVisits(_ displays: [ManagedDisplayDescriptor]? = nil) {
        guard Defaults[.enableSpacesBar], Defaults[.spacesBarRecentlyUsed] else { return }
        barVisits.update(displays ?? managedDisplays())
    }

    @MainActor static func barSpaceOrder(_ displays: [ManagedDisplayDescriptor]) -> [CGSSpaceID] {
        displays.flatMap { display in
            let ids = display.spaces.filter { $0.kind == .desktop || $0.kind == .fullscreen }.map(\.id)
            return Defaults[.spacesBarRecentlyUsed] ? barVisits.ordered(ids) : ids
        }
    }

    static func managedDisplays(includeOwners: Bool = false) -> [ManagedDisplayDescriptor] {
        ManagedSpacesTopology.snapshot(includeOwners: includeOwners)
    }

    static func allManagedSpaceIDs() -> Set<Int> {
        Set(managedDisplays().flatMap { display in
            Set(display.spaces.map(\.id)).union(display.currentSpaceID.map { [$0] } ?? []).map { Int($0) }
        })
    }

    static func desktopNumbers() -> [Int: Int] {
        let desktopIDs = managedDisplays()
            .flatMap(\.spaces)
            .filter { $0.kind == .desktop }
            .map { Int($0.id) }
        guard desktopIDs.count > 1 else { return [:] }

        return Dictionary(desktopIDs.enumerated().map { ($1, $0 + 1) }, uniquingKeysWith: { first, _ in first })
    }

    private static func displayIdentifiers(for screen: NSScreen) -> Set<String> {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return []
        }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        var identifiers: Set<String> = [String(displayID)]

        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let uuidString = CFUUIDCreateString(nil, uuid) as String?
        {
            identifiers.insert(uuidString)
        }

        return identifiers
    }

    static func screen(forDisplayIdentifier identifier: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            displayIdentifiers(for: screen).contains { candidate in
                candidate.caseInsensitiveCompare(identifier) == .orderedSame
            }
        }
    }

    static func displayName(for identifier: String) -> String? {
        screen(forDisplayIdentifier: identifier)?.localizedName
    }

    static func destination(
        forSpaceID spaceID: CGSSpaceID,
        in displays: [ManagedDisplayDescriptor]? = nil
    ) -> ManagedSpaceDestination? {
        for display in displays ?? managedDisplays() {
            if let space = display.spaces.first(where: { $0.id == spaceID }) {
                return ManagedSpaceDestination(display: display, space: space)
            }
        }
        return nil
    }

    static func destination(
        forSpaceNumber spaceNumber: Int,
        in displays: [ManagedDisplayDescriptor]? = nil
    ) -> ManagedSpaceDestination? {
        for display in displays ?? managedDisplays() {
            if let space = display.spaces.first(where: { $0.number == spaceNumber }) {
                return ManagedSpaceDestination(display: display, space: space)
            }
        }
        return nil
    }

    static func validateMoveSource(
        _ window: WindowInfo,
        in displays: [ManagedDisplayDescriptor]? = nil
    ) -> ManagedSpaceMoveValidationError? {
        if window.isWindowlessApp {
            return .windowless
        }
        if window.isFullscreen == true {
            return .fullscreen
        }

        let topology = displays ?? managedDisplays()
        let desktopSpaceIDs = Set(topology.flatMap(\.spaces).filter { $0.kind == .desktop }.map(\.id))
        if sourceSpaceIDs(for: window).intersection(desktopSpaceIDs).count > 1 {
            return .multipleDesktopSpaces
        }
        return nil
    }

    static func validateMove(
        _ window: WindowInfo,
        to destination: ManagedSpaceDestination,
        in displays: [ManagedDisplayDescriptor]? = nil
    ) -> ManagedSpaceMoveValidationError? {
        let topology = displays ?? managedDisplays()
        guard destination.space.kind == .desktop,
              topology.contains(where: { display in
                  display.identifier == destination.display.identifier &&
                      display.spaces.contains(where: { $0.id == destination.space.id && $0.kind == .desktop })
              })
        else {
            return .unavailableDestination
        }
        if let sourceError = validateMoveSource(window, in: topology) {
            return sourceError
        }
        if sourceSpaceIDs(for: window).contains(destination.space.id) {
            return .alreadyOnDestination
        }
        return nil
    }

    static func validateMoveSourceConfirmed(
        _ window: WindowInfo,
        in displays: [ManagedDisplayDescriptor]
    ) async -> ManagedSpaceMoveValidationError? {
        if let error = validateMoveSource(window, in: displays) { return error }
        if await window.readFullscreenState() == true { return .fullscreen }
        return nil
    }

    static func validateMoveConfirmed(
        _ window: WindowInfo,
        to destination: ManagedSpaceDestination,
        in displays: [ManagedDisplayDescriptor]
    ) async -> ManagedSpaceMoveValidationError? {
        if let error = validateMove(window, to: destination, in: displays) { return error }
        if await window.readFullscreenState() == true { return .fullscreen }
        return nil
    }

    static func sourceSpaceIDs(for window: WindowInfo) -> Set<CGSSpaceID> {
        let reportedSpaceIDs = Set(window.id.cgsSpaces())
        if !reportedSpaceIDs.isEmpty {
            return reportedSpaceIDs
        }
        return Set(window.spaceID.map { [CGSSpaceID($0)] } ?? [])
    }

    private static func screenContainingMouse(_ mouseLocation: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            NSPointInRect(mouseLocation, screen.frame)
        }
    }

    static func currentManagedSpaceID(mouseLocation: CGPoint = NSEvent.mouseLocation) -> CGSSpaceID? {
        let displays = managedDisplays()
        guard !displays.isEmpty else { return nil }

        if let mouseScreen = screenContainingMouse(mouseLocation) {
            let screenIdentifiers = displayIdentifiers(for: mouseScreen)
                .map { $0.lowercased() }

            if let display = displays.first(where: { display in
                screenIdentifiers.contains(display.identifier.lowercased())
            }) {
                return display.currentSpaceID
            }
        }

        return displays.first?.currentSpaceID
    }

    @discardableResult
    static func move(windowID: CGWindowID, toManagedSpace targetSpaceID: CGSSpaceID) -> Bool {
        let displays = managedDisplays()
        guard displays.contains(where: { display in
            display.currentSpaceID == targetSpaceID || display.spaces.contains(where: { $0.id == targetSpaceID })
        }) else {
            DebugLogger.log("WindowSpaces.move", details: "Target Space \(targetSpaceID) not found")
            return false
        }

        if windowID.cgsSpaces().contains(targetSpaceID) {
            return true
        }

        WindowSnapRegistry.existing?.remove(windowID: windowID)
        return SLSMoveWindowsToManagedSpace([windowID], targetSpaceID)
    }
}

func shouldExcludeInactiveNativeTab(windowID: CGWindowID, isFullscreen: Bool, isOnscreen: Bool, windowSpaces: Set<Int>?) -> Bool {
    guard Defaults[.collapseNativeTabsIntoSingleWindow], !isFullscreen, !isOnscreen, let windowSpaces, windowSpaces.isEmpty else { return false }
    return SLSWindowIsOrderedIn(windowID) == false
}

// Decide if a window should be accepted considering on-screen state,
// ScreenCaptureKit presence, multi-Space, and window/app state.
func shouldAcceptWindow(axWindow: AXUIElement,
                        windowID: CGWindowID,
                        cgEntry: [String: AnyObject],
                        app: NSRunningApplication,
                        activeSpaceIDs: Set<Int>,
                        scBacked: Bool) -> Bool
{
    if WindowUtil.isInternalWindow(windowID) { return false }

    // Base: role/subrole, level, size/alpha checks already enforced by caller
    let isOnscreen = (cgEntry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
    let fullscreenState = try? axWindow.isFullscreen()
    let axIsFullscreen = fullscreenState ?? false
    let axIsMinimized = (try? axWindow.isMinimized()) ?? false
    let knownWindowSpaces = windowID.cgsSpacesIfAvailable().map { Set($0.map { Int($0) }) }
    let windowSpaces = knownWindowSpaces ?? []

    // Keep DockDoor's Settings window, but reject its borderless preview and helper panels.
    if app.processIdentifier == ProcessInfo.processInfo.processIdentifier,
       (try? axWindow.closeButton()) == nil,
       (try? axWindow.minimizeButton()) == nil
    {
        return false
    }

    if isNoninteractiveUntitledDialog(axWindow) { return false }

    let isOnActiveSpace = !windowSpaces.isEmpty && !windowSpaces.isDisjoint(with: activeSpaceIDs)
    let isGhostWindow = !isOnscreen && isOnActiveSpace && !axIsMinimized && !axIsFullscreen && !app.isHidden
    if isGhostWindow { return false }

    if isOnscreen || scBacked { return true }

    if app.isHidden || axIsFullscreen || axIsMinimized {
        // AX marks inactive native tabs as minimized too; that must not bypass native visibility.
        guard fullscreenState != nil else { return true }
        return !shouldExcludeInactiveNativeTab(windowID: windowID, isFullscreen: axIsFullscreen, isOnscreen: isOnscreen, windowSpaces: knownWindowSpaces)
    }

    if windowSpaces.isEmpty, SLSWindowIsOrderedIn(windowID) == false {
        return false
    }

    // Window on a different Space; a window whose only Spaces no longer exist is a ghost with a stale space ID
    if !windowSpaces.isEmpty, windowSpaces.isDisjoint(with: activeSpaceIDs) {
        return !windowSpaces.isDisjoint(with: WindowSpaces.allManagedSpaceIDs())
    }

    // Fallback: if AX marks it as main, consider it significant and include.
    // This helps when CGS space mapping is unreliable or empty for other-Spaces windows.
    if (try? axWindow.attribute(kAXMainAttribute, Bool.self)) == true {
        return true
    }

    return false
}

import AppKit
import Defaults
import SwiftUI

enum WindowGestureOverlays {
    private static let lock = NSLock()
    private static var windowNumbers: Set<Int> = []

    static func register(_ windowNumber: Int) {
        guard windowNumber > 0 else { return }
        lock.lock()
        windowNumbers.insert(windowNumber)
        lock.unlock()
    }

    static func unregister(_ windowNumber: Int) {
        lock.lock()
        windowNumbers.remove(windowNumber)
        lock.unlock()
    }

    static func contains(_ windowNumber: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return windowNumbers.contains(windowNumber)
    }
}

@MainActor
final class WindowGestureHUD {
    struct Content: Equatable {
        var title: String
        let symbolName: String
        var region: WindowInfo.WindowPositionRect?
        var appIcon: NSImage?
        var isDimmed = false
        var isBusy = false
        var isWarning = false
        var isSuccess = false
        var showsSuccessSymbol = true
        var isCancelled = false
        var counter: String?
        var centersContents = false

        var accessibilityTitle: String {
            if isWarning { return String(localized: "\(title) failed") }
            if isCancelled { return String(localized: "\(title) cancelled") }
            return isSuccess ? String(localized: "\(title) completed") : title
        }
    }

    private var tooltipPanel: ActionPopupPanel?

    private var previewPanel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(_ content: Content, cursor: CGPoint, preview: CGRect?) {
        ActionFeedbackController.stopGestureFeedback()
        hideWorkItem?.cancel()
        hideWorkItem = nil
        showTooltip(content, cursor: cursor)
        showPreview(Defaults[.windowGestureLivePreview] ? preview : nil)
    }

    func flash(_ content: Content, cursor: CGPoint) {
        show(content, cursor: cursor, preview: nil)
        scheduleHide(after: ActionPopupTiming.initiated)
    }

    func hide() {
        ActionFeedbackController.stopGestureFeedback()
        hideWorkItem?.cancel()
        hideWorkItem = nil
        tooltipPanel?.hide()
        fadeOut(previewPanel)
    }

    func finish(_ content: Content?, cursor: CGPoint) {
        ActionFeedbackController.stopGestureFeedback()
        guard let content else {
            hide()
            return
        }
        showPreview(nil)
        showTooltip(content, cursor: cursor)
        scheduleHide(after: ActionPopupTiming.resultDuration(failed: content.isWarning))
    }

    static func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard Defaults[.windowGestureHaptics] else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    // MARK: - Tooltip

    private func showTooltip(_ content: Content, cursor: CGPoint) {
        if tooltipPanel == nil { tooltipPanel = ActionPopupPanel() }
        tooltipPanel?.present(content, cursor: DockObserver.nsPointFromCGPoint(cursor, forScreen: NSScreen.screenFromQuartzPoint(cursor)))
    }

    // MARK: - Preview

    private func showPreview(_ frame: CGRect?) {
        guard let frame, frame.width > 1, frame.height > 1 else {
            fadeOut(previewPanel)
            return
        }

        if let panel = previewPanel, panel.isVisible, panel.alphaValue > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Defaults[.showAnimations] ? ActionPopupTiming.resize : 0
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
            return
        }

        let panel = previewPanel ?? makePreviewPanel()
        previewPanel = panel
        panel.setFrame(frame, display: true)
        fadeIn(panel)
    }

    private func makePreviewPanel() -> NSPanel {
        let panel = Self.makePanel(level: .floating)
        panel.hasShadow = false
        panel.contentView = WindowGesturePreviewView()
        return panel
    }

    // MARK: - Visibility

    private static func makePanel(level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = level
        panel.alphaValue = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        return panel
    }

    private func fadeIn(_ panel: NSPanel) {
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            WindowGestureOverlays.register(panel.windowNumber)
        }
        guard panel.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Defaults[.showAnimations] ? ActionPopupTiming.fadeIn : 0
            panel.animator().alphaValue = 1
        }
    }

    private func fadeOut(_ panel: NSPanel?) {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Defaults[.showAnimations] ? ActionPopupTiming.fadeOut : 0
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 {
                    panel.orderOut(nil)
                }
            }
        })
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.hide()
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

private struct WindowGestureTooltip: View {
    let content: WindowGestureHUD.Content?
    let backgroundAppearance: BackgroundAppearance

    var body: some View {
        if let content {
            HStack(spacing: 6) {
                Group {
                    if content.isBusy { ProgressView().controlSize(.small) } else if content.isWarning { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) } else if content.isCancelled {
                        Image(systemName: "nosign")
                            .foregroundStyle(.red)
                    } else if content.isSuccess, content.showsSuccessSymbol {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                    } else if let appIcon = content.appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 18, height: 18)
                    } else if let region = content.region {
                        SnapGlyph(region: region)
                            .frame(width: 22, height: 14)
                    } else {
                        Image(systemName: content.symbolName)
                            .foregroundStyle(content.isDimmed ? Color.secondary : Color.accentColor)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 18)
                Text(content.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(content.isDimmed ? .secondary : .primary)
                    .lineLimit(1)
                    .multilineTextAlignment(content.centersContents ? .center : .leading)
                if let counter = content.counter {
                    Text(counter).monospacedDigit().font(.system(size: 13, weight: .semibold))
                }
            }
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: content.centersContents ? .center : .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(content.accessibilityTitle)
            .accessibilityValue(content.counter ?? "")
            .materialPill(backgroundAppearance: backgroundAppearance)
        }
    }
}

private struct SnapGlyph: View {
    let region: WindowInfo.WindowPositionRect

    var body: some View {
        Canvas { context, size in
            let outer = CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75)
            context.stroke(Path(roundedRect: outer, cornerRadius: 3), with: .color(.secondary), lineWidth: 1.2)
            let inner = outer.insetBy(dx: 2, dy: 2)
            let fill = region.frame(in: CGRect(origin: .zero, size: inner.size))
            let flipped = CGRect(x: inner.minX + fill.minX, y: inner.minY + inner.height - fill.maxY, width: fill.width, height: fill.height)
            context.fill(Path(roundedRect: flipped, cornerRadius: 1.5), with: .color(.accentColor))
        }
    }
}

private final class WindowGesturePreviewView: NSView {
    private let background = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.alphaValue = 0.55
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]
        addSubview(background)

        let border = NSView()
        border.wantsLayer = true
        border.layer?.cornerRadius = 12
        border.layer?.cornerCurve = .continuous
        border.layer?.borderWidth = 2
        border.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
        border.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        border.autoresizingMask = [.width, .height]
        addSubview(border)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = bounds.width > 8 && bounds.height > 8 ? 4 : 0
        for subview in subviews {
            subview.frame = bounds.insetBy(dx: inset, dy: inset)
        }
    }
}

enum ActionPopupTiming {
    static let initiated: TimeInterval = 0.7
    static let result: TimeInterval = 0.35
    static let resize: TimeInterval = 0.16
    static let fadeIn: TimeInterval = 0.1
    static let fadeOut: TimeInterval = 0.14

    static func resultDuration(failed: Bool) -> TimeInterval { failed ? result * 2 : result }
}

enum ActionFeedbackPosition: String, CaseIterable, Defaults.Serializable {
    case cursor, trigger, focus, preview

    var title: String {
        switch self {
        case .cursor: String(localized: "At cursor")
        case .trigger: String(localized: "Based on trigger type")
        case .focus: String(localized: "Based on preview focus")
        case .preview: String(localized: "At preview")
        }
    }

    func usesPreviews(keyboardTrigger: Bool, focus: PreviewStateCoordinator.SelectionInputSource) -> Bool {
        switch self {
        case .cursor: false
        case .preview: true
        case .trigger: keyboardTrigger
        case .focus:
            switch focus {
            case .mouse: false
            case .keyboard: true
            case .programmatic: keyboardTrigger
            }
        }
    }
}

enum ActionFeedbackOutcome: Equatable, Sendable {
    case completed, requested, failed, cancelled
}

struct ActionFeedbackHandle: Sendable {
    private final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [PreviewWindowIdentity: ActionFeedbackOutcome] = [:]
        private var targets: [PreviewWindowIdentity]?
        private var scheduled = false

        func append(_ identity: PreviewWindowIdentity, _ outcome: ActionFeedbackOutcome) -> Bool {
            lock.withLock {
                if pending[identity] == nil { pending[identity] = outcome }
                guard !scheduled else { return false }
                scheduled = true
                return true
            }
        }

        func setTargets(_ identities: [PreviewWindowIdentity]) -> Bool {
            lock.withLock {
                targets = identities
                guard !scheduled else { return false }
                scheduled = true
                return true
            }
        }

        func take() -> (targets: [PreviewWindowIdentity]?, outcomes: [PreviewWindowIdentity: ActionFeedbackOutcome]) {
            lock.withLock {
                let values = (targets, pending)
                targets = nil
                pending.removeAll(keepingCapacity: true)
                scheduled = false
                return values
            }
        }
    }

    let token: UUID
    private let progress = Progress()

    init(token: UUID) { self.token = token }

    var confirmedProgress: @Sendable (PreviewWindowIdentity, Bool) -> Void {
        { identity, success in finish(identity, success ? .completed : .failed) }
    }

    func setTargets(_ windows: [WindowInfo]) {
        let identities = windows.map(PreviewWindowIdentity.init)
        if progress.setTargets(identities) { report { _ in } }
    }

    func closeProgress(for identity: PreviewWindowIdentity) -> @Sendable (Int, Int) -> Void {
        { completed, total in report { $0.updateCloseProgress(identity, completed: completed, total: total) } }
    }

    func prepareForSpaceTransition() {
        // AX can confirm before the Space change; missing notifications must not strand feedback.
        report { $0.deferResultDismissal(for: ActionPopupTiming.initiated * 2) }
    }

    func finish(_ identity: PreviewWindowIdentity, _ outcome: ActionFeedbackOutcome) {
        let needsDelivery = progress.append(identity, outcome)
        if needsDelivery || Thread.isMainThread { report { _ in } }
    }

    func finishRemaining(_ outcome: ActionFeedbackOutcome) {
        report { controller in
            for identity in controller.order where controller.entries[identity]?.outcome == nil {
                controller.finish(identity, outcome)
            }
        }
    }

    func finish(_ result: WindowUtil.PreviewBatchResult, requested: Bool = false) {
        let failed = Set(result.failed)
        let succeeded = Set(result.succeeded.map(PreviewWindowIdentity.init))
        report { controller in
            for identity in controller.order where controller.entries[identity]?.outcome == nil {
                controller.finish(identity, failed.contains(identity) ? .failed : succeeded.contains(identity) ? (requested ? .requested : .completed) : .cancelled)
            }
        }
    }

    private func report(_ update: @escaping @MainActor (ActionFeedbackController) -> Void) {
        let run = { @MainActor in
            guard let controller = ActionFeedbackController.existing, controller.token == token else { return }
            let pending = progress.take()
            if let targets = pending.targets { controller.setTargets(targets) }
            for (identity, outcome) in pending.outcomes {
                controller.finish(identity, outcome)
            }
            update(controller)
        }
        if Thread.isMainThread { MainActor.assumeIsolated { run() } }
        else { DispatchQueue.main.async { run() } }
    }
}

@MainActor
final class ActionPopupPanel: NSPanel {
    private let host = NSHostingView(rootView: WindowGestureTooltip(content: nil, backgroundAppearance: .resolve()))
    private var generation = 0
    private var measuredSize = CGSize.zero
    private var presentedContent: WindowGestureHUD.Content?
    private var isFadingOut = false

    static var fades: Bool { Defaults[.showAnimations] }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        sharingType = .none
        hasShadow = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
    }

    func present(_ content: WindowGestureHUD.Content, center: CGPoint? = nil, cursor: CGPoint? = nil) {
        let needsFadeIn = !isVisible || isFadingOut
        generation += 1
        isFadingOut = false
        let contentChanged = presentedContent != content
        if contentChanged {
            presentedContent = content
            host.rootView = WindowGestureTooltip(content: content, backgroundAppearance: .resolve())
            measuredSize = host.fittingSize
        }
        let target = targetFrame(center: center, cursor: cursor)
        if frame != target { setFrame(target, display: true) }
        if !isVisible {
            alphaValue = 0
            WindowUtil.registerInternalWindow(CGWindowID(windowNumber))
            WindowGestureOverlays.register(windowNumber)
            orderFrontRegardless()
        }
        if needsFadeIn {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fades ? ActionPopupTiming.fadeIn : 0
                animator().alphaValue = 1
            }
        }
        if contentChanged { invalidateShadow() }
    }

    func followCursor() {
        let origin = targetFrame(center: nil).origin
        if frame.origin != origin { setFrameOrigin(origin) }
    }

    private func targetFrame(center: CGPoint?, cursor: CGPoint? = nil) -> CGRect {
        let pointer = cursor ?? NSEvent.mouseLocation
        let screen = (center ?? pointer).screen() ?? NSScreen.main
        let bounds = screen?.visibleFrame.insetBy(dx: 8, dy: 8) ?? CGRect(origin: pointer, size: measuredSize)
        var origin = center.map { CGPoint(x: $0.x - measuredSize.width / 2, y: $0.y - measuredSize.height / 2) }
            ?? CGPoint(x: pointer.x + 18, y: pointer.y - 34 - measuredSize.height / 2)
        origin.x = max(bounds.minX, min(origin.x, bounds.maxX - measuredSize.width))
        origin.y = max(bounds.minY, min(origin.y, bounds.maxY - measuredSize.height))
        return CGRect(origin: origin, size: measuredSize)
    }

    func hide(closeAfter: Bool = false, completion: (() -> Void)? = nil) {
        generation += 1
        isFadingOut = true
        let current = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fades ? ActionPopupTiming.fadeOut : 0
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                if closeAfter { self.close() } else { self.unregisterOverlay(); self.orderOut(nil) }
                completion?()
            }
        })
    }

    private func unregisterOverlay() {
        guard windowNumber > 0 else { return }
        WindowUtil.unregisterInternalWindow(CGWindowID(windowNumber))
        WindowGestureOverlays.unregister(windowNumber)
    }

    override func close() {
        generation += 1
        unregisterOverlay()
        orderOut(nil)
        super.close()
    }
}

@MainActor
final class ActionFeedbackController {
    struct Entry {
        var outcome: ActionFeedbackOutcome?
        var panel: ActionPopupPanel?
        var expired = false
        var hasShownSpinner = false
        var closeProgress: (completed: Int, total: Int)?

        var closeCounter: String? { closeProgress.map { "\($0.completed)/\($0.total)" } }
    }

    private(set) static var existing: ActionFeedbackController?
    private enum Origin { case event, keyboard, activation }
    private static var origin = Origin.event

    static func performKeyboardMenuAction(_ action: () -> Void) { withOrigin(.keyboard, action) }
    static func withoutFeedback(_ action: () -> Void) { withOrigin(.activation, action) }

    private static func withOrigin(_ origin: Origin, _ action: () -> Void) {
        guard Defaults[.enableActionFeedback] else { action(); return }
        let previous = Self.origin
        Self.origin = origin
        defer { Self.origin = previous }
        action()
    }

    let token = UUID()
    private(set) var order: [PreviewWindowIdentity]
    fileprivate var entries: [PreviewWindowIdentity: Entry]
    private let perApp: Bool
    private var operationGroups: [[PreviewWindowIdentity]]
    private let baseContent: WindowGestureHUD.Content
    private let gestureCursor: CGPoint?
    private weak var previews: SharedPreviewWindowCoordinator?
    private var cursorMode: Bool
    private var spinnerVisible = false
    private var aggregateHasShownSpinner = false
    private var handingOff = false
    private var spaceTransitionPending = false
    private var aggregateExpired = false
    private var aggregate: ActionPopupPanel?
    private var outgoing: [ActionPopupPanel] = []
    private var spinnerTask: Task<Void, Never>?
    private var resultTasks: [PreviewWindowIdentity: Task<Void, Never>] = [:]
    private var aggregateTask: Task<Void, Never>?
    private var spaceTransitionTask: Task<Void, Never>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observations: [NSObjectProtocol] = []
    private var settingsObservation: Defaults.Observation?
    private var workspaceObservation: NSObjectProtocol?

    static func gesture(_ content: WindowGestureHUD.Content, identities: [PreviewWindowIdentity], cursor: CGPoint) -> ActionFeedbackHandle? {
        guard Defaults[.enableWindowGestures] else { return nil }
        return start(title: content.title, symbol: content.symbolName, identities: identities, keyboard: false,
                     usePreviews: false, gestureContent: content, gestureCursor: cursor)
    }

    static func stopGestureFeedback() {
        if existing?.gestureCursor != nil { existing?.stop() }
    }

    static func begin(_ action: WindowAction, windows: [WindowInfo], keyboard: Bool = false,
                      usePreviews: Bool = true, title: String? = nil, resolvedTargets: [WindowInfo]? = nil) -> ActionFeedbackHandle?
    {
        guard Defaults[.enableActionFeedback], origin != .activation, ![.none, .toggleWindowSelection, .selectAllWindows, .openAppWindow].contains(action) else { return nil }
        let targets = resolvedTargets ?? action.previewTargets(from: windows)
        let invalidAttempt = targets.isEmpty && windows.count == 1 && action.appliesToSelectedWindow(windows[0]) &&
            action.autoTilingDirection(windowCount: 1, fillActionsAutoTile: Defaults[.fillActionsAutoTileSelection]) == nil
        guard !targets.isEmpty || invalidAttempt else { return nil }
        let feedbackTargets = invalidAttempt ? windows : targets
        let feedback = start(title: title ?? action.feedbackTitle(for: feedbackTargets[0], batchTargets: windows.count > 1 ? windows : nil), symbol: action.menuIcon(for: feedbackTargets[0], batchTargets: feedbackTargets.count > 1 ? feedbackTargets : nil),
                             identities: feedbackTargets.map(PreviewWindowIdentity.init), keyboard: keyboard || origin == .keyboard, usePreviews: usePreviews, perApp: action == .hide)
        if action == .toggleFullScreen, !invalidAttempt { feedback.prepareForSpaceTransition() }
        if invalidAttempt { feedback.finishRemaining(.failed) }
        return feedback
    }

    static func space(_ number: Int, window: WindowInfo? = nil, keyboard: Bool, usePreviews: Bool = true) -> ActionFeedbackHandle? {
        guard Defaults[.enableActionFeedback], origin != .activation else { return nil }
        let feedback = start(title: window == nil ? String(localized: "Switch to Space \(number)") : String(localized: "Move to Space \(number)"),
                             symbol: "square.grid.2x2", identities: [window.map(PreviewWindowIdentity.init) ?? PreviewWindowIdentity(pid: 0, windowID: 0)],
                             keyboard: keyboard || origin == .keyboard, usePreviews: usePreviews && window != nil)
        if window == nil { feedback.prepareForSpaceTransition() }
        return feedback
    }

    static func mouseFollowedFocus() {
        guard Defaults[.enableActionFeedback], Defaults[.showMouseFollowsFocusFeedback] else { return }
        let feedback = start(title: String(localized: "Mouse Followed Focus"), symbol: "pointer.arrow.motionlines",
                             identities: [PreviewWindowIdentity(pid: 0, windowID: 0)], keyboard: false, usePreviews: false)
        feedback.finishRemaining(.requested)
    }

    private static func start(title: String, symbol: String, identities: [PreviewWindowIdentity], keyboard: Bool,
                              usePreviews: Bool, perApp: Bool = false, gestureContent: WindowGestureHUD.Content? = nil,
                              gestureCursor: CGPoint? = nil) -> ActionFeedbackHandle
    {
        existing?.stop()
        let controller = ActionFeedbackController(title: title, symbol: symbol, identities: identities,
                                                  keyboard: keyboard, usePreviews: usePreviews, perApp: perApp,
                                                  gestureContent: gestureContent, gestureCursor: gestureCursor)
        existing = controller
        controller.start()
        return ActionFeedbackHandle(token: controller.token)
    }

    private init(title: String, symbol: String, identities: [PreviewWindowIdentity], keyboard: Bool, usePreviews: Bool, perApp: Bool,
                 gestureContent: WindowGestureHUD.Content?, gestureCursor: CGPoint?)
    {
        baseContent = gestureContent ?? WindowGestureHUD.Content(title: title, symbolName: symbol)
        self.gestureCursor = gestureCursor
        var seen = Set<PreviewWindowIdentity>()
        order = identities.filter { seen.insert($0).inserted }
        entries = Dictionary(order.map { ($0, Entry()) }, uniquingKeysWith: { first, _ in first })
        self.perApp = perApp
        operationGroups = perApp ? Array(Dictionary(grouping: order, by: \.pid).values) : order.map { [$0] }
        previews = usePreviews ? SharedPreviewWindowCoordinator.activeInstance : nil
        cursorMode = !usePreviews || !Defaults[.actionFeedbackPosition].usesPreviews(
            keyboardTrigger: keyboard, focus: previews?.windowSwitcherCoordinator.selectionInputSource ?? .programmatic
        )
    }

    private func start() {
        workspaceObservation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deferResultDismissal(for: ActionPopupTiming.result)
                if self?.spaceTransitionPending == true { self?.consolidate() }
            }
        }
        settingsObservation = Defaults.observe(gestureCursor == nil ? .enableActionFeedback : .enableWindowGestures, options: []) { [weak self] change in
            guard !change.newValue else { return }
            DispatchQueue.main.async { self?.stop() }
        }
        if let previews, !cursorMode {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: previews, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshAnchors() }
                })
            }
        }
        if cursorMode { render() } else { refreshAnchors() }
        spinnerTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(ActionPopupTiming.initiated * 1_000_000_000)) } catch { return }
            guard let self else { return }
            spinnerVisible = true
            render()
        }
    }

    func updateCloseProgress(_ identity: PreviewWindowIdentity, completed: Int, total: Int) {
        guard total > 1, completed >= 0, completed <= total,
              let entry = entries[identity], entry.outcome == nil,
              entry.closeProgress.map({ $0.total == total && $0.completed <= completed }) ?? true
        else { return }
        entries[identity]?.closeProgress = (completed, total)
        render()
    }

    func setTargets(_ identities: [PreviewWindowIdentity]) {
        guard entries.values.allSatisfy({ $0.outcome == nil }) else { return }
        var seen = Set<PreviewWindowIdentity>()
        let identities = identities.filter { seen.insert($0).inserted }
        guard !identities.isEmpty else { stop(); return }
        guard identities != order else { return }
        let retained = Set(identities)
        for identity in order where !retained.contains(identity) {
            entries[identity]?.panel?.close()
        }
        entries = Dictionary(identities.map { ($0, entries[$0] ?? Entry()) }, uniquingKeysWith: { first, _ in first })
        order = identities
        operationGroups = perApp ? Array(Dictionary(grouping: order, by: \.pid).values) : order.map { [$0] }
        render()
    }

    func finish(_ identity: PreviewWindowIdentity, _ outcome: ActionFeedbackOutcome) {
        guard let entry = entries[identity], entry.outcome == nil else { return }
        let affected = perApp ? order.filter { $0.pid == identity.pid && entries[$0]?.outcome == nil } : [identity]
        for target in affected {
            entries[target]?.outcome = outcome
        }
        if entries.values.allSatisfy({ $0.outcome != nil }) { spinnerTask?.cancel(); spinnerTask = nil }
        render()
        scheduleResultDismissal(affected)
    }

    private func scheduleResultDismissal(_ identities: [PreviewWindowIdentity]? = nil) {
        guard !spaceTransitionPending else { return }
        if cursorMode { scheduleAggregateHide() }
        else {
            for identity in identities ?? order where entries[identity]?.expired == false && resultTasks[identity] == nil {
                guard let outcome = entries[identity]?.outcome else { continue }
                let duration = ActionPopupTiming.resultDuration(failed: outcome == .failed)
                resultTasks[identity] = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)) } catch { return }
                    guard let self else { return }
                    entries[identity]?.expired = true
                    resultTasks.removeValue(forKey: identity)
                    entries[identity]?.panel?.hide(closeAfter: true) { [weak self] in
                        guard let self, entries.values.allSatisfy(\.expired) else { return }
                        stop()
                    }
                }
            }
        }
    }

    fileprivate func deferResultDismissal(for duration: TimeInterval) {
        guard Self.existing === self, !aggregateExpired, entries.values.contains(where: { !$0.expired }) else { return }
        spaceTransitionPending = true
        aggregateTask?.cancel()
        aggregateTask = nil
        for task in resultTasks.values {
            task.cancel()
        }
        resultTasks.removeAll()
        spaceTransitionTask?.cancel()
        spaceTransitionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)) } catch { return }
            guard let self, Self.existing === self else { return }
            spaceTransitionTask = nil
            spaceTransitionPending = false
            render()
            scheduleResultDismissal()
        }
        render()
    }

    func refreshAnchors() {
        guard Self.existing === self, !cursorMode else { return }
        if previews?.isVisible != true { consolidate(); return }
        render()
    }

    func previewWillDisappear(_ preview: SharedPreviewWindowCoordinator) {
        if previews === preview, !cursorMode { consolidate() }
    }

    private func consolidate() {
        guard !cursorMode, entries.values.contains(where: { !$0.expired }) else { return }
        cursorMode = true
        aggregateHasShownSpinner = entries.values.contains { !$0.expired && $0.hasShownSpinner }
        for task in resultTasks.values {
            task.cancel()
        }
        resultTasks.removeAll()
        for entry in entries.values where entry.expired {
            entry.panel?.close()
        }
        outgoing = entries.values.compactMap { $0.expired ? nil : $0.panel }
        for identity in order {
            entries[identity]?.panel = nil
        }
        handingOff = !outgoing.isEmpty
        render()
        guard handingOff else { scheduleAggregateHide(); return }
        var remaining = outgoing.count
        for panel in outgoing {
            panel.hide(closeAfter: true) { [weak self] in
                guard let self, Self.existing === self else { return }
                remaining -= 1
                guard remaining == 0 else { return }
                outgoing.removeAll()
                handingOff = false
                scheduleAggregateHide()
            }
        }
    }

    private func content(for outcome: ActionFeedbackOutcome?, counter: String? = nil, hasShownSpinner: Bool) -> WindowGestureHUD.Content {
        var result = baseContent
        result.isBusy = outcome == nil && spinnerVisible
        result.isWarning = outcome == .failed
        result.isSuccess = outcome == .completed
        result.showsSuccessSymbol = hasShownSpinner
        result.isCancelled = outcome == .cancelled
        result.counter = counter
        result.centersContents = !cursorMode
        return result
    }

    private func render() {
        guard Self.existing === self else { return }
        if cursorMode {
            let values = operationGroups.compactMap { group -> ActionFeedbackOutcome? in
                let outcomes = group.compactMap { entries[$0]?.outcome }
                guard outcomes.count == group.count else { return nil }
                return outcomes.contains(.failed) ? .failed : outcomes.contains(.cancelled) ? .cancelled : outcomes.contains(.requested) ? .requested : .completed
            }
            let failures = values.filter { $0 == .failed }.count
            let done = values.count == operationGroups.count
            let outcome: ActionFeedbackOutcome? = done ? (failures > 0 ? .failed : values.contains(.cancelled) ? .cancelled : values.contains(.requested) ? .requested : .completed) : nil
            let count = done ? values.filter { $0 == .completed || $0 == .requested }.count : values.count
            let counter = operationGroups.count > 1 ? "\(count)/\(operationGroups.count)" : order.first.flatMap { entries[$0]?.closeCounter }
            let value = content(for: outcome, counter: counter, hasShownSpinner: aggregateHasShownSpinner)
            if aggregate == nil { aggregate = ActionPopupPanel() }
            aggregate?.present(value, cursor: gestureCursor)
            if value.isBusy { aggregateHasShownSpinner = true }
            installCursorTracking()
        } else {
            guard let grid = previews?.windowSwitcherCoordinator.actionFeedbackGrid else { consolidate(); return }
            let anchors = order.compactMap { identity in grid.feedbackFrame(for: identity).map { (identity, $0) } }
            guard anchors.count == order.count else { consolidate(); return }
            for (identity, frame) in anchors where entries[identity]?.expired == false {
                if entries[identity]?.panel == nil { entries[identity]?.panel = ActionPopupPanel() }
                let value = content(for: entries[identity]?.outcome, counter: entries[identity]?.closeCounter, hasShownSpinner: entries[identity]?.hasShownSpinner == true)
                entries[identity]?.panel?.present(value, center: CGPoint(x: frame.midX, y: frame.midY))
                if value.isBusy { entries[identity]?.hasShownSpinner = true }
            }
        }
    }

    private func scheduleAggregateHide() {
        guard cursorMode, !handingOff, !spaceTransitionPending, entries.values.allSatisfy({ $0.outcome != nil }), aggregateTask == nil else { return }
        let duration = ActionPopupTiming.resultDuration(failed: entries.values.contains { $0.outcome == .failed })
        aggregateTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)) } catch { return }
            guard let self else { return }
            aggregateExpired = true
            aggregate?.hide(closeAfter: true) { [weak self] in self?.stop() }
        }
    }

    private func installCursorTracking() {
        guard gestureCursor == nil, localMonitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.aggregate?.followCursor()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in self?.aggregate?.followCursor() }
    }

    func stop() {
        guard Self.existing === self else { return }
        Self.existing = nil
        spinnerTask?.cancel()
        aggregateTask?.cancel()
        spaceTransitionTask?.cancel()
        for task in resultTasks.values {
            task.cancel()
        }
        resultTasks.removeAll()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        for observer in observations {
            NotificationCenter.default.removeObserver(observer)
        }
        observations.removeAll()
        if let workspaceObservation { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObservation) }
        workspaceObservation = nil
        settingsObservation?.invalidate()
        settingsObservation = nil
        aggregate?.close()
        for entry in entries.values {
            entry.panel?.close()
        }
        for panel in outgoing {
            panel.close()
        }
        outgoing.removeAll()
        entries.removeAll()
    }
}

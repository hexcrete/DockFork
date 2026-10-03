import Cocoa
import Defaults
import SwiftUI

struct TrackpadGestureModifier: ViewModifier {
    let isActive: Bool
    var onSwipeUp: () -> Void
    var onSwipeDown: () -> Void
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void
    var onScrollingChanged: ((Bool) -> Void)?

    func body(content: Content) -> some View {
        content
            .background(
                TrackpadEventMonitor(
                    isActive: isActive,
                    onSwipeUp: onSwipeUp,
                    onSwipeDown: onSwipeDown,
                    onSwipeLeft: onSwipeLeft,
                    onSwipeRight: onSwipeRight,
                    onScrollingChanged: onScrollingChanged
                )
                .frame(width: 0, height: 0)
            )
    }
}

struct TrackpadEventMonitor: NSViewRepresentable {
    let isActive: Bool
    var onSwipeUp: () -> Void
    var onSwipeDown: () -> Void
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void
    var onScrollingChanged: ((Bool) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            isActive: isActive,
            onSwipeUp: onSwipeUp,
            onSwipeDown: onSwipeDown,
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            onScrollingChanged: onScrollingChanged
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSwipeUp: onSwipeUp,
            onSwipeDown: onSwipeDown,
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            onScrollingChanged: onScrollingChanged
        )
    }

    class Coordinator {
        private var isActive = false
        private var onSwipeUp: () -> Void
        private var onSwipeDown: () -> Void
        private var onSwipeLeft: () -> Void
        private var onSwipeRight: () -> Void
        private var onScrollingChanged: ((Bool) -> Void)?

        private var scrollMonitor: Any?
        private var cumulativeScrollX: CGFloat = 0
        private var cumulativeScrollY: CGFloat = 0
        private var isScrolling = false
        private var isNaturalScrolling = false
        private var scrollEndTimer: Timer?
        private var scrollCooldownTimer: Timer?
        private let swipeThreshold: CGFloat = Defaults[.gestureSwipeThreshold]

        init(
            onSwipeUp: @escaping () -> Void,
            onSwipeDown: @escaping () -> Void,
            onSwipeLeft: @escaping () -> Void,
            onSwipeRight: @escaping () -> Void,
            onScrollingChanged: ((Bool) -> Void)?
        ) {
            self.onSwipeUp = onSwipeUp
            self.onSwipeDown = onSwipeDown
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
            self.onScrollingChanged = onScrollingChanged
            setupMonitor()
        }

        deinit {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
            }
            scrollEndTimer?.invalidate()
            scrollCooldownTimer?.invalidate()
        }

        func update(
            isActive: Bool,
            onSwipeUp: @escaping () -> Void,
            onSwipeDown: @escaping () -> Void,
            onSwipeLeft: @escaping () -> Void,
            onSwipeRight: @escaping () -> Void,
            onScrollingChanged: ((Bool) -> Void)?
        ) {
            self.onSwipeUp = onSwipeUp
            self.onSwipeDown = onSwipeDown
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
            self.onScrollingChanged = onScrollingChanged

            guard self.isActive != isActive else { return }
            self.isActive = isActive
            if !isActive {
                cancelScroll()
            }
        }

        private func setupMonitor() {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(event)
                return event
            }
        }

        private func handleScroll(_ event: NSEvent) {
            guard isActive else { return }
            guard event.hasPreciseScrollingDeltas else { return }

            switch event.phase {
            case .began:
                cumulativeScrollX = 0
                cumulativeScrollY = 0
                isScrolling = true
                isNaturalScrolling = event.isDirectionInvertedFromDevice
                scrollEndTimer?.invalidate()
                scrollCooldownTimer?.invalidate()
                onScrollingChanged?(true)

            case .changed:
                cumulativeScrollX += event.scrollingDeltaX
                cumulativeScrollY += event.scrollingDeltaY

            case .ended:
                finishScroll()

            case .cancelled:
                cancelScroll()
                return

            default:
                break
            }

            // Backup timer for end detection
            scrollEndTimer?.invalidate()
            scrollEndTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                self?.finishScroll()
            }
        }

        private func finishScroll() {
            guard isScrolling else { return }
            isScrolling = false

            let normalizedY = isNaturalScrolling ? -cumulativeScrollY : cumulativeScrollY

            if abs(cumulativeScrollY) > abs(cumulativeScrollX), abs(cumulativeScrollY) > swipeThreshold {
                if normalizedY > 0 {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, isActive else { return }
                        onSwipeUp()
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, isActive else { return }
                        onSwipeDown()
                    }
                }
            } else if abs(cumulativeScrollX) > abs(cumulativeScrollY), abs(cumulativeScrollX) > swipeThreshold {
                if cumulativeScrollX < 0 {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, isActive else { return }
                        onSwipeLeft()
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, isActive else { return }
                        onSwipeRight()
                    }
                }
            }

            cumulativeScrollX = 0
            cumulativeScrollY = 0

            scrollCooldownTimer?.invalidate()
            scrollCooldownTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.onScrollingChanged?(false)
            }
        }

        private func cancelScroll() {
            let wasScrolling = isScrolling || scrollCooldownTimer != nil
            scrollEndTimer?.invalidate()
            scrollEndTimer = nil
            scrollCooldownTimer?.invalidate()
            scrollCooldownTimer = nil
            cumulativeScrollX = 0
            cumulativeScrollY = 0
            isScrolling = false
            if wasScrolling {
                onScrollingChanged?(false)
            }
        }
    }
}

extension View {
    func onTrackpadSwipe(
        isActive: Bool,
        onScrollingChanged: ((Bool) -> Void)? = nil,
        onSwipeUp: @escaping () -> Void = {},
        onSwipeDown: @escaping () -> Void = {},
        onSwipeLeft: @escaping () -> Void = {},
        onSwipeRight: @escaping () -> Void = {}
    ) -> some View {
        modifier(TrackpadGestureModifier(
            isActive: isActive,
            onSwipeUp: onSwipeUp,
            onSwipeDown: onSwipeDown,
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            onScrollingChanged: onScrollingChanged
        ))
    }
}

import AppKit
import Defaults
import SwiftUI

enum PreviewControlAnimation {
    static let maximumDuration = 0.5

    static func animation(duration: Double, animationsEnabled: Bool, reduceMotion: Bool) -> Animation? {
        guard animationsEnabled, !reduceMotion, duration > 0 else { return nil }
        return .snappy(duration: min(duration, maximumDuration))
    }
}

private struct PreviewControlVisibilityAnimation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isVisible: Bool
    let duration: Double
    let animationsEnabled: Bool

    func body(content: Content) -> some View {
        content.animation(
            PreviewControlAnimation.animation(duration: duration, animationsEnabled: animationsEnabled, reduceMotion: reduceMotion),
            value: isVisible
        )
    }
}

extension View {
    func previewControlVisibilityAnimation(isVisible: Bool, duration: Double, animationsEnabled: Bool) -> some View {
        modifier(PreviewControlVisibilityAnimation(isVisible: isVisible, duration: duration, animationsEnabled: animationsEnabled))
    }
}

struct ViewSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = value + nextValue()
    }
}

func doAfter(_ seconds: Double = 0, action: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
}

func timer(_ seconds: Double = 0, action: @escaping (Timer) -> Void) -> Timer {
    Timer.scheduledTimer(withTimeInterval: seconds, repeats: false, block: action)
}

// Off when DockDoor animations are off or Reduce Motion is on in System Settings.
var animationsEnabled: Bool {
    Defaults[.showAnimations] && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

@MainActor
@propertyWrapper
struct AnimationsEnabled: @preconcurrency DynamicProperty {
    @Default(.showAnimations) private var showAnimations
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private(set) var wrappedValue = true

    mutating func update() {
        wrappedValue = showAnimations && !reduceMotion
    }
}

/// Runs an animation block respecting the user's showAnimations preference.
/// If animations are disabled, executes the block immediately without animation.
func animateWithUserPreference(
    duration: TimeInterval = 0.2,
    timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut),
    changes: @escaping () -> Void,
    completion: (() -> Void)? = nil
) {
    if animationsEnabled {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timingFunction
            changes()
        } completionHandler: {
            completion?()
        }
    } else {
        changes()
        completion?()
    }
}

func applyAppearanceMode(_ mode: AppAppearanceMode) {
    switch mode {
    case .system:
        NSApp.appearance = nil
    case .light:
        NSApp.appearance = NSAppearance(named: .aqua)
    case .dark:
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

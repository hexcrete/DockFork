import AppKit
import Defaults
import SwiftUI

enum PreviewControlAnimation {
    static func animation(duration: Double) -> Animation? {
        duration > 0 ? .snappy(duration: min(duration, 0.2)) : nil
    }
}

extension View {
    func previewControlVisibilityAnimation(isVisible: Bool, duration: Double) -> some View {
        animation(PreviewControlAnimation.animation(duration: duration), value: isVisible)
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

/// Runs an animation block respecting the user's showAnimations preference.
/// If animations are disabled, executes the block immediately without animation.
func animateWithUserPreference(
    duration: TimeInterval = 0.2,
    timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut),
    changes: @escaping () -> Void,
    completion: (() -> Void)? = nil
) {
    if Defaults[.showAnimations] {
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

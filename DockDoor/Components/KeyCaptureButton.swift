import Carbon.HIToolbox.Events
import SwiftUI

struct KeyCaptureButton: View {
    @Binding var keyCode: UInt16
    var emptyLabel: String? = nil
    var forceEmptyLabel: Bool = false
    var treatKeyCodeZeroAsEmpty: Bool = true
    var captureModifiers: Bool = false
    var allowsEscape: Bool = false
    var autoStartCapture: Bool = false
    var cancelOnOutsideClick: Bool = false
    var modifierFlags: Binding<Int>?

    @State private var isCapturing = false
    @State private var monitors: [Any] = []
    @State private var captureToken: UUID?

    var body: some View {
        Button {
            if isCapturing { stopCapture() } else { startCapture() }
        } label: {
            Group {
                if isCapturing {
                    Text("Press a key…").foregroundStyle(Color.accentColor)
                } else {
                    Text(displayLabel).foregroundStyle(showingEmptyLabel ? .secondary : .primary)
                }
            }
            .frame(minWidth: 36)
        }
        .buttonStyle(.settings)
        .onAppear {
            if autoStartCapture, !isCapturing {
                startCapture()
            }
        }
        .onChange(of: autoStartCapture) { newValue in
            if newValue, !isCapturing {
                startCapture()
            }
        }
        .onDisappear {
            stopCapture()
        }
    }

    private var showingEmptyLabel: Bool {
        (forceEmptyLabel || (treatKeyCodeZeroAsEmpty && keyCode == 0)) && emptyLabel != nil
    }

    private var displayLabel: String {
        if showingEmptyLabel, let emptyLabel {
            return emptyLabel
        }
        return KeyboardLabel.localizedKey(for: keyCode)
    }

    private func stopCapture() {
        isCapturing = false
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        SettingsShortcutCaptureState.shared.end(captureToken)
        captureToken = nil
    }

    private func startCapture() {
        stopCapture()
        isCapturing = true
        captureToken = SettingsShortcutCaptureState.shared.begin { stopCapture() }

        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = WindowSwitcherShortcutResolver.normalizedModifiers(Int(event.modifierFlags.rawValue))
            if event.keyCode == UInt16(kVK_Escape), !allowsEscape, modifierFlags == nil || flags == 0 {
                stopCapture()
                return nil
            }
            guard !event.isARepeat else { return nil }
            if flags != 0 { modifierFlags?.wrappedValue = flags }
            keyCode = event.keyCode
            stopCapture()
            return nil
        }!)

        if cancelOnOutsideClick {
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                stopCapture()
                return event
            }!)
        }

        if captureModifiers {
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
                if modifierKeyCodes.contains(event.keyCode) {
                    keyCode = event.keyCode
                    stopCapture()
                }
                return event
            }!)
        }
    }
}

final class SettingsShortcutCaptureState {
    static let shared = SettingsShortcutCaptureState()
    private let lock = NSLock()
    private var token: UUID?
    private var cancellation: (() -> Void)?
    private var deactivationObserver: Any?

    var isActive: Bool { lock.withLock { token != nil } }

    func begin(cancel: @escaping () -> Void) -> UUID {
        let previous = lock.withLock { token }
        cancellation?()
        end(previous)
        let newToken = UUID()
        lock.withLock { token = newToken }
        cancellation = cancel
        deactivationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancellation?()
        }
        return newToken
    }

    func end(_ owner: UUID?) {
        let ended = lock.withLock {
            guard let owner, token == owner else { return false }
            token = nil
            return true
        }
        guard ended else { return }
        cancellation = nil
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        deactivationObserver = nil
    }
}

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
    var onCaptureFinished: ((Bool) -> Void)? = nil

    @State private var isCapturing = false
    @State private var monitors: [Any] = []

    var body: some View {
        Group {
            if isCapturing {
                Text("Press a key…")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                    .frame(minWidth: 50)
            } else {
                Button(action: startCapture) {
                    Text(displayLabel)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(showingEmptyLabel ? 0.1 : 0.2))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
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

    private func stopCapture(reportAssigned assigned: Bool? = nil) {
        isCapturing = false
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        if let assigned {
            onCaptureFinished?(assigned)
        }
    }

    private func startCapture() {
        stopCapture()
        isCapturing = true

        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape), !allowsEscape {
                stopCapture(reportAssigned: false)
                return nil
            }
            keyCode = event.keyCode
            stopCapture(reportAssigned: true)
            return nil
        }!)

        if cancelOnOutsideClick || onCaptureFinished != nil {
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                stopCapture(reportAssigned: false)
                return event
            }!)
        }

        if captureModifiers {
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
                if modifierKeyCodes.contains(event.keyCode) {
                    keyCode = event.keyCode
                    stopCapture(reportAssigned: true)
                }
                return event
            }!)
        }
    }
}

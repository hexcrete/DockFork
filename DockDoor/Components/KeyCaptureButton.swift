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
        Button {
            if isCapturing { stopCapture(reportAssigned: false) } else { startCapture() }
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

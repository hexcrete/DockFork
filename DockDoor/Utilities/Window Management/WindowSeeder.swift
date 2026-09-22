import ApplicationServices
import Cocoa

final class WindowSeeder {
    private static let retryDelays: [UInt64] = [150_000_000, 350_000_000, 800_000_000]

    func run() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else { return }

        Task(priority: .high) {
            await WindowUtil.updateAllWindowsInCurrentSpace()

            let apps = initialApps()
            for delay in Self.retryDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await retryIncompleteApps(apps, includeUnresponsive: false)
            }

            let unresponsiveApps = apps.filter { AXResponsiveness.isUnresponsive($0.processIdentifier) }
            guard !unresponsiveApps.isEmpty else { return }
            try? await Task.sleep(nanoseconds: UInt64((AXResponsiveness.backoff + 0.1) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await retryIncompleteApps(unresponsiveApps, includeUnresponsive: true)
        }
    }

    private func initialApps() -> [NSRunningApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
                $0.processIdentifier != 0 &&
                $0.processIdentifier != ownPID
        }
    }

    private func retryIncompleteApps(_ apps: [NSRunningApplication], includeUnresponsive: Bool) async {
        for app in apps where WindowUtil.shouldRetryStartupDiscovery(for: app) {
            if !includeUnresponsive, AXResponsiveness.isUnresponsive(app.processIdentifier) {
                continue
            }
            _ = await WindowUtil.discoverWindowsViaAX(app: app)
        }
    }
}

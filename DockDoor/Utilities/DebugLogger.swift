import Defaults
import Foundation
import os.log

/// Debug logger for tracking performance-critical operations
enum DebugLogger {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "DockDoor", category: "Debug")
    private static let queue = DispatchQueue(label: "DebugLogger", qos: .utility)
    private static let diagnosticsDirectoryURL: URL = {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return applicationSupport.appendingPathComponent("DockDoor/Diagnostics", isDirectory: true)
    }()

    private static let logFileURL = diagnosticsDirectoryURL.appendingPathComponent("DockDoor-Debug.log")
    fileprivate static let hangSampleURL = diagnosticsDirectoryURL.appendingPathComponent("DockDoor-Hang.sample.txt")
    private static let exportURL = diagnosticsDirectoryURL.appendingPathComponent("DockDoor-Diagnostics.zip")
    private static let timestampLock = NSLock()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func formattedTimestamp() -> String {
        timestampLock.lock()
        defer { timestampLock.unlock() }
        return timestampFormatter.string(from: Date())
    }

    static func configure(enabled: Bool) {
        if enabled {
            HangDiagnostics.start()
        } else {
            HangDiagnostics.stop()
        }
    }

    static func applySizeLimit() {
        queue.async {
            guard Defaults[.limitDebugLogFileSize],
                  let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
                  let size = attributes[.size] as? NSNumber
            else { return }
            trimLogIfNeeded(fileSize: size.uint64Value)
        }
    }

    private static func prepareDiagnosticsDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(at: diagnosticsDirectoryURL, withIntermediateDirectories: true)
            return true
        } catch {
            os_log("Failed to create diagnostics directory: %{public}@", log: log, type: .error, error.localizedDescription)
            return false
        }
    }

    private static func writeToFile(_ line: String) {
        os_log("%{public}@", log: log, type: .debug, line)

        queue.async {
            guard prepareDiagnosticsDirectory() else { return }
            guard let data = (line + "\n").data(using: .utf8) else { return }

            var fileSize = UInt64(data.count)
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileSize += fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }

            trimLogIfNeeded(fileSize: fileSize)
        }
    }

    static func maximumLogSizeBytes(_ sizeMB: Double) -> UInt64 {
        let boundedSize = sizeMB.isFinite ? min(100, max(1, sizeMB)) : Defaults.Keys.debugLogMaximumSizeMB.defaultValue
        return UInt64(boundedSize) * 1024 * 1024
    }

    private static func trimLogIfNeeded(fileSize: UInt64) {
        guard Defaults[.limitDebugLogFileSize] else { return }

        let maximumBytes = maximumLogSizeBytes(Defaults[.debugLogMaximumSizeMB])
        guard fileSize > maximumBytes else { return }
        guard let handle = try? FileHandle(forReadingFrom: logFileURL) else { return }
        let retainedBytes = maximumBytes * 3 / 4
        handle.seek(toFileOffset: fileSize - retainedBytes)
        let tail = handle.readDataToEndOfFile()
        try? handle.close()

        let trimmed: Data = if let newline = tail.firstIndex(of: 0x0A), newline < tail.endIndex {
            Data(tail[tail.index(after: newline)...])
        } else {
            tail
        }
        try? trimmed.write(to: logFileURL, options: .atomic)
    }

    /// Log an operation with optional details
    static func log(_ operation: String, details: String? = nil) {
        guard Defaults[.debugMode] else { return }

        var logLine = "[\(formattedTimestamp())] \(operation)"
        if let details {
            logLine += " - \(details)"
        }
        writeToFile(logLine)
    }

    /// Log an operation with measured duration
    static func logWithDuration(_ operation: String, details: String? = nil, duration: TimeInterval) {
        guard Defaults[.debugMode] else { return }

        var logLine = "[\(formattedTimestamp())] \(operation)"
        logLine += String(format: " (%.3fms)", duration * 1000)
        if let details {
            logLine += " - \(details)"
        }
        writeToFile(logLine)
    }

    /// Measure and log the execution time of a block
    @discardableResult
    static func measure<T>(_ operation: String, details: String? = nil, block: () throws -> T) rethrows -> T {
        guard Defaults[.debugMode] else {
            return try block()
        }

        let startTime = Date()
        let result = try block()
        let duration = Date().timeIntervalSince(startTime)

        logWithDuration(operation, details: details, duration: duration)
        return result
    }

    /// Measure and log the execution time of an async block
    @discardableResult
    static func measureAsync<T>(_ operation: String, details: String? = nil, block: () async throws -> T) async rethrows -> T {
        guard Defaults[.debugMode] else {
            return try await block()
        }

        let startTime = Date()
        let result = try await block()
        let duration = Date().timeIntervalSince(startTime)

        logWithDuration(operation, details: details, duration: duration)
        return result
    }

    /// Measure and log only if execution time exceeds threshold (in milliseconds)
    @discardableResult
    static func measureSlow<T>(_ operation: String, thresholdMs: Double = 50, details: @autoclosure () -> String? = nil, block: () throws -> T) rethrows -> T {
        guard Defaults[.debugMode] else {
            return try block()
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        if durationMs > thresholdMs {
            logWithDuration(operation, details: details(), duration: durationMs / 1000)
        }
        return result
    }

    /// Measure and log only if async execution time exceeds threshold (in milliseconds)
    @discardableResult
    static func measureSlowAsync<T>(_ operation: String, thresholdMs: Double = 50, details: @autoclosure () -> String? = nil, block: () async throws -> T) async rethrows -> T {
        guard Defaults[.debugMode] else {
            return try await block()
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        if durationMs > thresholdMs {
            logWithDuration(operation, details: details(), duration: durationMs / 1000)
        }
        return result
    }

    /// Export the operation log and latest hang sample as a ZIP archive.
    static func exportLogs() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard prepareDiagnosticsDirectory() else {
                    continuation.resume(returning: nil)
                    return
                }

                let files = [logFileURL, hangSampleURL].filter {
                    FileManager.default.fileExists(atPath: $0.path)
                }
                guard !files.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let temporaryRootURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("DockDoor-Diagnostics-\(UUID().uuidString)", isDirectory: true)
                let stagingURL = temporaryRootURL.appendingPathComponent("DockDoor-Diagnostics", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: temporaryRootURL) }

                    for file in files {
                        try FileManager.default.copyItem(
                            at: file,
                            to: stagingURL.appendingPathComponent(file.lastPathComponent)
                        )
                    }

                    try? FileManager.default.removeItem(at: exportURL)
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", stagingURL.path, exportURL.path]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0 ? exportURL : nil)
                } catch {
                    os_log("Failed to export diagnostics: %{public}@", log: log, type: .error, error.localizedDescription)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Clear all logs
    static func clearLogs() {
        queue.async {
            try? FileManager.default.removeItem(at: logFileURL)
            try? FileManager.default.removeItem(at: hangSampleURL)
            try? FileManager.default.removeItem(at: exportURL)
        }
    }

    /// Get log count
    static func getLogCount() -> Int {
        queue.sync {
            guard FileManager.default.fileExists(atPath: logFileURL.path),
                  let content = try? String(contentsOf: logFileURL, encoding: .utf8)
            else { return 0 }

            return content.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        }
    }
}

enum HangDiagnostics {
    private static let queue = DispatchQueue(label: "HangDiagnostics", qos: .utility)
    private static let sampleQueue = DispatchQueue(label: "HangDiagnostics.sample", qos: .utility)
    private static var timer: DispatchSourceTimer?
    private static var lastHeartbeat = ProcessInfo.processInfo.systemUptime
    private static var heartbeatPending = false
    private static var sampledCurrentStall = false
    private static var generation: UInt = 0

    static func start() {
        queue.async {
            guard timer == nil else { return }
            generation &+= 1
            let activeGeneration = generation
            DebugLogger.log("HangDiagnostics", details: "started, PID: \(ProcessInfo.processInfo.processIdentifier)")
            lastHeartbeat = ProcessInfo.processInfo.systemUptime
            heartbeatPending = false
            sampledCurrentStall = false

            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 1, repeating: 1)
            source.setEventHandler {
                guard generation == activeGeneration else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let stalledFor = now - lastHeartbeat

                if stalledFor >= 4, !sampledCurrentStall {
                    sampledCurrentStall = true
                    DebugLogger.log("HangDiagnostics", details: String(format: "main thread stalled for %.1fs; capturing sample", stalledFor))
                    captureSample()
                }

                guard !heartbeatPending else { return }
                heartbeatPending = true
                DispatchQueue.main.async {
                    queue.async {
                        guard generation == activeGeneration else { return }
                        lastHeartbeat = ProcessInfo.processInfo.systemUptime
                        heartbeatPending = false
                        if sampledCurrentStall {
                            DebugLogger.log("HangDiagnostics", details: "main thread heartbeat resumed")
                            sampledCurrentStall = false
                        }
                    }
                }
            }
            timer = source
            source.resume()
        }
    }

    static func stop() {
        queue.async {
            generation &+= 1
            timer?.cancel()
            timer = nil
            heartbeatPending = false
            sampledCurrentStall = false
        }
    }

    static func record(_ event: String) {
        DebugLogger.log("HangDiagnostics", details: event)
    }

    private static func captureSample() {
        let pid = ProcessInfo.processInfo.processIdentifier
        sampleQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            process.arguments = [String(pid), "5", "-file", DebugLogger.hangSampleURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                DebugLogger.log("HangDiagnostics", details: "sample finished, status: \(process.terminationStatus)")
            } catch {
                DebugLogger.log("HangDiagnostics", details: "sample failed: \(error.localizedDescription)")
            }
        }
    }
}

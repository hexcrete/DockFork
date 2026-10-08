import Cocoa
import Defaults
import ScreenCaptureKit
import SwiftUI
import VideoToolbox

private func keepAliveNanoseconds(for seconds: Int) -> UInt64 {
    let (nanoseconds, overflow) = UInt64(clamping: seconds).multipliedReportingOverflow(by: 1_000_000_000)
    return overflow ? .max : nanoseconds
}

enum LivePreviewContext: Hashable {
    case dock
    case windowSwitcher

    var isEnabled: Bool {
        guard Defaults[.enableLivePreview] else { return false }
        return self == .dock ? Defaults[.enableLivePreviewForDock] : Defaults[.enableLivePreviewForWindowSwitcher]
    }
}

struct LivePreviewImage: View {
    let windowID: CGWindowID
    let fallbackImage: CGImage?
    let quality: LivePreviewQuality
    let frameRate: LivePreviewFrameRate
    let context: LivePreviewContext
    var placeholderIcon: NSImage? = nil

    var body: some View {
        let keepAlive = Defaults[.livePreviewStreamKeepAlive]

        if keepAlive != 0 {
            LivePreviewImageCached(windowID: windowID, fallbackImage: fallbackImage, quality: quality, frameRate: frameRate, context: context, placeholderIcon: placeholderIcon)
        } else {
            LivePreviewImageFresh(windowID: windowID, fallbackImage: fallbackImage, quality: quality, frameRate: frameRate, context: context, placeholderIcon: placeholderIcon)
        }
    }
}

private struct LivePreviewImageCached: View {
    let windowID: CGWindowID
    let fallbackImage: CGImage?
    let quality: LivePreviewQuality
    let frameRate: LivePreviewFrameRate
    let placeholderIcon: NSImage?

    @ObservedObject private var capture: WindowLiveCapture

    init(windowID: CGWindowID, fallbackImage: CGImage?, quality: LivePreviewQuality, frameRate: LivePreviewFrameRate, context: LivePreviewContext, placeholderIcon: NSImage?) {
        self.windowID = windowID
        self.fallbackImage = fallbackImage
        self.quality = quality
        self.frameRate = frameRate
        self.placeholderIcon = placeholderIcon
        capture = LiveCaptureManager.shared.getCapture(windowID: windowID, quality: quality, frameRate: frameRate, context: context)
    }

    var body: some View {
        Group {
            if let image = capture.capturedImage ?? capture.lastFrame ?? fallbackImage {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .scaledToFit()
            } else if let placeholderIcon {
                PreviewPlaceholderImage(appIcon: placeholderIcon)
            }
        }
        .task {
            await capture.startCapture()
        }
    }
}

private struct LivePreviewImageFresh: View {
    let windowID: CGWindowID
    let fallbackImage: CGImage?
    let quality: LivePreviewQuality
    let frameRate: LivePreviewFrameRate
    let placeholderIcon: NSImage?

    @StateObject private var capture: WindowLiveCapture

    init(windowID: CGWindowID, fallbackImage: CGImage?, quality: LivePreviewQuality, frameRate: LivePreviewFrameRate, context: LivePreviewContext, placeholderIcon: NSImage?) {
        self.windowID = windowID
        self.fallbackImage = fallbackImage
        self.quality = quality
        self.frameRate = frameRate
        self.placeholderIcon = placeholderIcon
        _capture = StateObject(wrappedValue: WindowLiveCapture(windowID: windowID, quality: quality, frameRate: frameRate, context: context))
    }

    var body: some View {
        Group {
            if let image = capture.capturedImage ?? fallbackImage {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .scaledToFit()
            } else if let placeholderIcon {
                PreviewPlaceholderImage(appIcon: placeholderIcon)
            }
        }
        .task {
            await capture.startCapture()
        }
        .onDisappear {
            Task { await capture.stopCapture() }
        }
    }
}

@MainActor
final class LiveCaptureManager {
    private static var instance: LiveCaptureManager?

    static var shared: LiveCaptureManager {
        if let instance { return instance }
        let manager = LiveCaptureManager()
        instance = manager
        return manager
    }

    static func stopAllIfInitialized() async {
        await instance?.stopAllStreams()
    }

    static func removeIfInitialized(windowID: CGWindowID, capture: WindowLiveCapture) {
        instance?.remove(windowID: windowID, capture: capture)
    }

    private var captures: [CGWindowID: WindowLiveCapture] = [:]
    private var stopGeneration = 0
    private var settingsObserver: Defaults.Observation?

    private init() {}

    private func observeSettingsIfNeeded() {
        guard settingsObserver == nil else { return }
        settingsObserver = Defaults.observe(keys: .enableLivePreview, .enableLivePreviewForDock, .enableLivePreviewForWindowSwitcher, options: []) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.stopDisabledStreams()
            }
        }
    }

    private func stopDisabledStreams() async {
        let disabled = captures.values.filter { !$0.isEnabled }
        // Invalidate every pending start before the first asynchronous stop.
        let streams = disabled.compactMap { $0.prepareForCleanup() }
        for stream in streams {
            try? await stream.stopCapture()
        }
    }

    func panelOpened() {
        stopGeneration += 1
    }

    func panelClosed() async {
        let keepAlive = Defaults[.livePreviewStreamKeepAlive]

        if keepAlive < 0 {
            return
        }

        if keepAlive == 0 {
            await stopAllStreams()
            return
        }

        stopGeneration += 1
        let generationAtClose = stopGeneration

        try? await Task.sleep(nanoseconds: keepAliveNanoseconds(for: keepAlive))

        guard !Task.isCancelled, stopGeneration == generationAtClose else { return }

        await stopAllStreams()
    }

    func getCapture(windowID: CGWindowID, quality: LivePreviewQuality, frameRate: LivePreviewFrameRate, context: LivePreviewContext) -> WindowLiveCapture {
        stopGeneration += 1
        observeSettingsIfNeeded()
        if let existing = captures[windowID] {
            existing.addContext(context)
            return existing
        }

        let capture = WindowLiveCapture(windowID: windowID, quality: quality, frameRate: frameRate, context: context)
        captures[windowID] = capture
        return capture
    }

    func requestStop(windowID: CGWindowID) async {
        guard let capture = captures[windowID] else { return }
        await capture.requestStop()
    }

    private func remove(windowID: CGWindowID, capture: WindowLiveCapture) {
        guard captures[windowID] === capture else { return }
        captures.removeValue(forKey: windowID)
        if captures.isEmpty {
            settingsObserver?.invalidate()
            settingsObserver = nil
        }
    }

    func stopAllStreams() async {
        stopGeneration += 1
        let previousCaptures = Array(captures.values)
        captures.removeAll()
        settingsObserver?.invalidate()
        settingsObserver = nil
        let streams = previousCaptures.compactMap { $0.prepareForCleanup() }
        for stream in streams {
            try? await stream.stopCapture()
        }
    }
}

@MainActor
final class WindowLiveCapture: ObservableObject {
    @Published var capturedImage: CGImage?

    let windowID: CGWindowID
    private let quality: LivePreviewQuality
    private let frameRate: LivePreviewFrameRate
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var stopGeneration = 0
    private var captureGeneration = 0
    private var contexts: Set<LivePreviewContext>
    private(set) var lastFrame: CGImage?

    init(windowID: CGWindowID, quality: LivePreviewQuality, frameRate: LivePreviewFrameRate, context: LivePreviewContext) {
        self.windowID = windowID
        self.quality = quality
        self.frameRate = frameRate
        contexts = [context]
    }

    var isEnabled: Bool {
        contexts.contains { $0.isEnabled }
    }

    func addContext(_ context: LivePreviewContext) {
        contexts.insert(context)
    }

    func startCapture() async {
        stopGeneration += 1
        guard stream == nil, isEnabled, !Task.isCancelled else { return }
        guard WindowUtil.shouldCaptureWindowImages() else { return }
        captureGeneration += 1
        let generation = captureGeneration

        guard let content = await WindowUtil.getShareableContent(onScreenWindowsOnly: false),
              let scWindow = content.windows.first(where: { $0.windowID == windowID })
        else { return }
        guard generation == captureGeneration, isEnabled, !Task.isCancelled else { return }
        guard WindowCandidateDiscriminator.hasUsableSize(scWindow.frame.size) else { return }
        guard !WindowCandidateDiscriminator.isLiveCaptureControlProxy(
            title: scWindow.title,
            size: scWindow.frame.size,
            level: Int32(scWindow.windowLayer)
        ) else { return }
        await startStream(for: scWindow, generation: generation)
    }

    private func startStream(for window: SCWindow, generation: Int) async {
        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()

        let backingScaleFactor = Int(NSScreen.main?.backingScaleFactor ?? 2.0)
        let windowWidth = Int(window.frame.width)
        let windowHeight = Int(window.frame.height)
        let maxDim = quality.maxDimension

        if quality.useFullResolution {
            let effectiveScale = quality.scaleFactor == 2 ? 2 : backingScaleFactor
            var targetWidth = windowWidth * effectiveScale
            var targetHeight = windowHeight * effectiveScale

            if maxDim > 0 {
                let aspectRatio = Double(targetWidth) / Double(targetHeight)
                if targetWidth > targetHeight {
                    targetWidth = min(targetWidth, maxDim * effectiveScale)
                    targetHeight = Int(Double(targetWidth) / aspectRatio)
                } else {
                    targetHeight = min(targetHeight, maxDim * effectiveScale)
                    targetWidth = Int(Double(targetHeight) * aspectRatio)
                }
            }

            config.width = targetWidth
            config.height = targetHeight
        } else {
            let aspectRatio = Double(windowWidth) / Double(windowHeight)
            let limitDim = maxDim > 0 ? maxDim : 640
            if aspectRatio > 1 {
                config.width = min(limitDim, windowWidth * backingScaleFactor)
                config.height = Int(Double(config.width) / aspectRatio)
            } else {
                config.height = min(limitDim, windowHeight * backingScaleFactor)
                config.width = Int(Double(config.height) * aspectRatio)
            }
        }

        config.minimumFrameInterval = CMTime(value: 1, timescale: frameRate.frameRate)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = quality.scaleFactor == 2 ? 5 : 3
        config.scalesToFit = true

        if #available(macOS 14.0, *) {
            config.captureResolution = .best
        }

        if #available(macOS 15.0, *) {
            config.captureDynamicRange = .hdrLocalDisplay
            config.colorSpaceName = CGColorSpace.displayP3 as CFString
        }

        do {
            let newStream = SCStream(filter: filter, configuration: config, delegate: nil)

            let output = StreamOutput { [weak self] image in
                Task { @MainActor in
                    guard let self, self.captureGeneration == generation else { return }
                    self.lastFrame = image
                    self.capturedImage = image
                }
            }

            try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
            try await newStream.startCapture()

            guard captureGeneration == generation, isEnabled, !Task.isCancelled else {
                try? await newStream.stopCapture()
                return
            }
            stream = newStream
            streamOutput = output
        } catch {
            DebugLogger.log("LiveWindowCapture: Failed to start stream", details: error.localizedDescription)
        }
    }

    func requestStop() async {
        let keepAlive = Defaults[.livePreviewStreamKeepAlive]

        if keepAlive < 0 {
            return
        }

        if keepAlive == 0 {
            await stopAndCleanup()
            return
        }

        stopGeneration += 1
        let generationAtStop = stopGeneration

        try? await Task.sleep(nanoseconds: keepAliveNanoseconds(for: keepAlive))

        guard !Task.isCancelled, stopGeneration == generationAtStop else { return }

        await stopAndCleanup()
    }

    func stopCapture() async {
        captureGeneration += 1
        stopGeneration += 1
        let stream = stream
        self.stream = nil
        streamOutput = nil
        capturedImage = nil
        try? await stream?.stopCapture()
    }

    func stopAndCleanup() async {
        let stream = prepareForCleanup()
        try? await stream?.stopCapture()
    }

    fileprivate func prepareForCleanup() -> SCStream? {
        captureGeneration += 1
        stopGeneration += 1
        let stream = stream
        streamOutput = nil
        self.stream = nil
        capturedImage = nil
        lastFrame = nil
        LiveCaptureManager.removeIfInitialized(windowID: windowID, capture: self)
        return stream
    }

    func forceStopNonBlocking() {
        captureGeneration += 1
        stopGeneration += 1
        guard let stream else { return }
        let streamToStop = stream
        self.stream = nil
        streamOutput = nil
        Task.detached {
            try? await streamToStop.stopCapture()
        }
    }
}

private class StreamOutput: NSObject, SCStreamOutput {
    private let onFrame: (CGImage) -> Void

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)

        if let image = cgImage {
            onFrame(image)
        }
    }
}

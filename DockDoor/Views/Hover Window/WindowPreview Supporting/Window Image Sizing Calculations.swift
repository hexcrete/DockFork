import Cocoa
import Defaults

// Holds logic related to precomputing image thumbnail sizes
extension WindowPreviewHoverContainer {
    struct PreviewLayoutMetrics {
        let itemSpacing: CGFloat
        let contentInset: CGFloat

        var totalPanelInset: CGFloat {
            HoverContainerPadding.container +
                HoverContainerPadding.dockStyleOuter +
                HoverContainerPadding.scrollOuter +
                contentInset
        }

        static func resolve(
            compact: Bool,
            onlyWindowlessDockLikeRows: Bool,
            paddingMultiplier: CGFloat
        ) -> Self {
            let scaledContentInset = HoverContainerPadding.contentInner * paddingMultiplier
            let usesTightInset = compact || onlyWindowlessDockLikeRows
            return Self(
                itemSpacing: compact ? 4 : HoverContainerPadding.itemSpacing,
                contentInset: usesTightInset
                    ? max(0, scaledContentInset - CGFloat(CardRadius.innerPadding))
                    : scaledContentInset
            )
        }

        static func regular(paddingMultiplier: CGFloat) -> Self {
            resolve(
                compact: false,
                onlyWindowlessDockLikeRows: false,
                paddingMultiplier: paddingMultiplier
            )
        }
    }

    enum PreviewCardPresentation: Equatable {
        case regular
        case compact(width: CGFloat)

        static func resolve(
            isWindowlessApp: Bool,
            containerUsesCompactRows: Bool,
            showFullSizeWindowlessPreviews: Bool,
            compactWidth: CGFloat,
            previewWidth: CGFloat
        ) -> Self {
            if containerUsesCompactRows {
                return .compact(width: compactWidth)
            }
            if isWindowlessApp, !showFullSizeWindowlessPreviews {
                return .compact(width: previewWidth)
            }
            return .regular
        }
    }

    static func usesCompactRows(
        isMockPreviewActive: Bool,
        forceCompact: Bool,
        windowCount: Int,
        threshold: Int
    ) -> Bool {
        guard !isMockPreviewActive else { return false }
        return forceCompact || (threshold > 0 && windowCount >= threshold)
    }

    struct GridFlow: Equatable {
        let laysOutItemsInRows: Bool
        let scrollsVertically: Bool
        let fillsLinesToLimit: Bool

        static func resolve(
            compact: Bool,
            windowSwitcherActive: Bool,
            dockPosition: DockPosition
        ) -> Self {
            if compact {
                return Self(laysOutItemsInRows: true, scrollsVertically: true, fillsLinesToLimit: false)
            }

            if windowSwitcherActive {
                let scrollsVertically = Defaults[.windowSwitcherScrollDirection] == .vertical
                return Self(
                    laysOutItemsInRows: scrollsVertically,
                    scrollsVertically: scrollsVertically,
                    fillsLinesToLimit: true
                )
            }

            let laysOutItemsInRows = dockPosition.isHorizontalFlow
            return Self(
                laysOutItemsInRows: laysOutItemsInRows,
                scrollsVertically: !laysOutItemsInRows,
                fillsLinesToLimit: false
            )
        }
    }

    struct WindowDimensions: Equatable {
        let size: CGSize
        let maxDimensions: CGSize
    }

    static func placeholderDimensions(previewSize: CGSize) -> WindowDimensions {
        let size = CGSize(width: max(1, previewSize.width), height: max(1, previewSize.height))
        return WindowDimensions(size: size, maxDimensions: size)
    }

    static let dynamicMaxAspectRatio: CGFloat = 1.5
    static let dynamicSwitcherMinimumImageWidth: CGFloat = 50
    static let dynamicSwitcherMinimumCardWidth: CGFloat = 240

    static func calculateOverallMaxDimensions(
        windows: [WindowInfo],
        dockPosition: DockPosition,
        isWindowSwitcherActive: Bool,
        isMockPreviewActive: Bool,
        sharedPanelWindowSize: CGSize
    ) -> CGPoint {
        if Defaults[.allowDynamicImageSizing] {
            if isWindowSwitcherActive {
                let maxHeight = max(1, Defaults[.previewHeight])
                let maxWidth = max(1, Defaults[.previewWidth])
                let minImageWidth = min(maxWidth, dynamicSwitcherMinimumImageWidth)
                let minCardWidth = min(maxWidth, dynamicSwitcherMinimumCardWidth)

                var widestWindow = minImageWidth
                for window in windows {
                    if window.image == nil {
                        widestWindow = maxWidth
                        continue
                    }
                    guard let cgImage = window.image else { continue }
                    let aspectRatio = CGFloat(cgImage.width) / CGFloat(cgImage.height)
                    let width = min(max(maxHeight * aspectRatio, minImageWidth), maxWidth)
                    widestWindow = max(widestWindow, width)
                }

                return CGPoint(x: max(1, min(max(widestWindow, minCardWidth), maxWidth)), y: maxHeight)
            }

            // Scale preview dimensions to match actual window aspect ratios.
            let orientationIsHorizontal = dockPosition == .bottom || dockPosition == .cmdTab
            let thickness: CGFloat = if isMockPreviewActive {
                200
            } else if orientationIsHorizontal {
                sharedPanelWindowSize.height
            } else {
                sharedPanelWindowSize.width
            }
            var maxWidth: CGFloat = 300
            var maxHeight: CGFloat = 300
            let minAspectRatio: CGFloat = 1.0 / dynamicMaxAspectRatio

            for window in windows {
                if let cgImage = window.image {
                    let cgSize = CGSize(width: cgImage.width, height: cgImage.height)
                    if orientationIsHorizontal {
                        let rawWidthBasedOnHeight = (cgSize.width * thickness) / cgSize.height
                        let widthBasedOnHeight = max(min(rawWidthBasedOnHeight, thickness * dynamicMaxAspectRatio), thickness * minAspectRatio)
                        maxWidth = max(maxWidth, widthBasedOnHeight)
                        maxHeight = thickness
                    } else {
                        let rawHeightBasedOnWidth = (cgSize.height * thickness) / cgSize.width
                        let heightBasedOnWidth = max(min(rawHeightBasedOnWidth, thickness * dynamicMaxAspectRatio), thickness * minAspectRatio)
                        maxHeight = max(maxHeight, heightBasedOnWidth)
                        maxWidth = thickness
                    }
                }
            }
            return CGPoint(x: max(1, maxWidth), y: max(1, maxHeight))
        } else {
            // Use fixed sizing from user settings
            let width = Defaults[.previewWidth]
            let height = Defaults[.previewHeight]
            return CGPoint(x: width, y: height)
        }
    }

    private static func computeRenderedDimension(
        aspectRatio: CGFloat,
        thickness: CGFloat,
        maxDimensions: CGSize,
        isHorizontal: Bool
    ) -> CGSize {
        if isHorizontal {
            let width = min(thickness * aspectRatio, maxDimensions.width)
            return CGSize(width: width, height: thickness)
        } else {
            let height = min(thickness / aspectRatio, maxDimensions.height)
            return CGSize(width: thickness, height: height)
        }
    }

    private static func geometryAspectRatio(for window: WindowInfo) -> CGFloat? {
        if let axSize = try? window.axElement.size(),
           axSize.width > 0,
           axSize.height > 0
        {
            return axSize.width / axSize.height
        }

        let frameSize = window.frame.size
        if frameSize.width > 0, frameSize.height > 0 {
            return frameSize.width / frameSize.height
        }

        return nil
    }

    private static func effectiveAspectRatio(for window: WindowInfo, image: CGImage) -> CGFloat {
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        guard imageAspect > 0 else { return 1 }

        guard let geometryAspect = geometryAspectRatio(for: window), geometryAspect > 0 else {
            return imageAspect
        }

        if (try? window.axElement.isFullscreen()) == true {
            return geometryAspect
        }

        let mismatchFactor = max(imageAspect, geometryAspect) / min(imageAspect, geometryAspect)
        if mismatchFactor > 4 {
            return geometryAspect
        }

        return imageAspect
    }

    static func precomputeWindowDimensions(
        windows: [WindowInfo],
        overallMaxDimensions: CGPoint,
        bestGuessMonitor: NSScreen,
        dockPosition: DockPosition,
        isWindowSwitcherActive: Bool,
        effectiveMaxColumns: Int,
        effectiveMaxRows: Int
    ) -> [Int: WindowDimensions] {
        var dimensionsMap: [Int: WindowDimensions] = [:]

        if Defaults[.allowDynamicImageSizing] {
            let orientationIsHorizontal: Bool = isWindowSwitcherActive ? true : dockPosition == .bottom || dockPosition == .cmdTab
            let maxDims = CGSize(width: overallMaxDimensions.x, height: overallMaxDimensions.y)
            let thickness: CGFloat = orientationIsHorizontal ? overallMaxDimensions.y : overallMaxDimensions.x

            if isWindowSwitcherActive {
                let gridFlow = GridFlow.resolve(
                    compact: false,
                    windowSwitcherActive: true,
                    dockPosition: dockPosition
                )
                let chunks = chunkArray(
                    items: Array(windows.indices),
                    isHorizontal: gridFlow.laysOutItemsInRows,
                    maxColumns: effectiveMaxColumns,
                    maxRows: effectiveMaxRows,
                    fillToLimit: gridFlow.fillsLinesToLimit
                )
                let minImageWidth = min(maxDims.width, dynamicSwitcherMinimumImageWidth)
                let defaultPreviewSize = CGSize(
                    width: max(1, Defaults[.previewWidth]),
                    height: max(1, Defaults[.previewHeight])
                )

                for chunk in chunks {
                    let fittedHeights = chunk.compactMap { index -> CGFloat? in
                        guard index < windows.count, let cgImage = windows[index].image else { return nil }
                        return computeRenderedDimension(
                            aspectRatio: CGFloat(cgImage.width) / CGFloat(cgImage.height),
                            thickness: thickness,
                            maxDimensions: maxDims,
                            isHorizontal: true
                        ).height
                    }
                    let lineItemHeight = min(maxDims.height, max(fittedHeights.max() ?? maxDims.height, 50))

                    for index in chunk {
                        guard index < windows.count else { continue }
                        if let cgImage = windows[index].image {
                            let aspectRatio = CGFloat(cgImage.width) / CGFloat(cgImage.height)
                            let width = min(max(lineItemHeight * aspectRatio, minImageWidth), maxDims.width)
                            dimensionsMap[index] = WindowDimensions(
                                size: CGSize(width: width, height: lineItemHeight),
                                maxDimensions: maxDims
                            )
                        } else {
                            dimensionsMap[index] = placeholderDimensions(previewSize: defaultPreviewSize)
                        }
                    }
                }

                return dimensionsMap
            }

            for (index, window) in windows.enumerated() {
                if let cgImage = window.image {
                    let aspectRatio = effectiveAspectRatio(for: window, image: cgImage)
                    let rendered = computeRenderedDimension(
                        aspectRatio: aspectRatio,
                        thickness: thickness,
                        maxDimensions: maxDims,
                        isHorizontal: orientationIsHorizontal
                    )
                    let windowSize = if orientationIsHorizontal {
                        CGSize(width: rendered.width, height: max(rendered.height, 50))
                    } else {
                        CGSize(width: max(rendered.width, 50), height: rendered.height)
                    }
                    dimensionsMap[index] = WindowDimensions(size: windowSize, maxDimensions: maxDims)
                } else {
                    dimensionsMap[index] = placeholderDimensions(previewSize: CGSize(
                        width: Defaults[.previewWidth], height: Defaults[.previewHeight]
                    ))
                }
            }
        } else {
            let width = Defaults[.previewWidth]
            let height = Defaults[.previewHeight]
            let fixedBoxSize = CGSize(width: width, height: height)
            let maxDims = CGSize(width: width, height: height)

            for (index, _) in windows.enumerated() {
                dimensionsMap[index] = WindowDimensions(size: fixedBoxSize, maxDimensions: maxDims)
            }
        }
        return dimensionsMap
    }

    static func calculateSingleWindowDimensions(
        windowInfo: WindowInfo,
        overallMaxDimensions: CGPoint,
        bestGuessMonitor: NSScreen
    ) -> WindowDimensions {
        let width = Defaults[.previewWidth]
        let height = Defaults[.previewHeight]
        let maxDims = CGSize(width: overallMaxDimensions.x, height: overallMaxDimensions.y)
        return WindowDimensions(size: CGSize(width: width, height: height), maxDimensions: maxDims)
    }

    func resolvedDimensions(for index: Int, dimensionsMap: [Int: WindowDimensions]) -> WindowDimensions {
        let fallback = WindowDimensions(
            size: CGSize(width: 100, height: 100),
            maxDimensions: CGSize(width: 100, height: 100)
        )
        guard index >= 0, index < previewStateCoordinator.windows.count else {
            return fallback
        }
        return dimensionsMap[index] ?? fallback
    }

    // MARK: - Helper Functions

    /// Computes the actual rendered dimension (width for horizontal flow, height for vertical) of a single window card.
    /// Calculates the effective maximum columns and rows based on screen size and user settings
    /// - Parameters:
    ///   - bestGuessMonitor: The screen to calculate for
    ///   - overallMaxDimensions: The maximum preview dimensions (width and height)
    ///   - dockPosition: Current dock position
    ///   - isWindowSwitcherActive: Whether window switcher is active
    ///   - previewMaxColumns: User setting for max columns
    ///   - previewMaxRows: User setting for max rows
    ///   - switcherMaxRows: Max rows for window switcher
    ///   - totalItems: Total number of items to display
    /// - Returns: Tuple of (maxColumns, maxRows)
    static func calculateEffectiveMaxColumnsAndRows(
        bestGuessMonitor: NSScreen,
        overallMaxDimensions: CGPoint,
        dockPosition: DockPosition,
        isWindowSwitcherActive: Bool,
        previewMaxColumns: Int,
        previewMaxRows: Int,
        switcherMaxRows: Int,
        totalItems: Int? = nil
    ) -> (maxColumns: Int, maxRows: Int) {
        let screenWidth = bestGuessMonitor.visibleFrame.width
        let screenHeight = bestGuessMonitor.visibleFrame.height
        let metrics = PreviewLayoutMetrics.regular(paddingMultiplier: Defaults[.globalPaddingMultiplier])
        let itemSpacing = metrics.itemSpacing
        let globalPadding = metrics.totalPanelInset * 2

        let previewWidth = overallMaxDimensions.x
        let previewHeight = overallMaxDimensions.y

        let calculatedMaxColumns = max(1, Int((screenWidth - globalPadding + itemSpacing) / (previewWidth + itemSpacing)))
        let calculatedMaxRows = max(1, Int((screenHeight - globalPadding + itemSpacing) / (previewHeight + itemSpacing)))

        var effectiveMaxColumns: Int
        var effectiveMaxRows: Int

        if isWindowSwitcherActive {
            let isVertical = Defaults[.windowSwitcherScrollDirection] == .vertical
            if isVertical {
                effectiveMaxColumns = Defaults[.switcherIgnoreScreenLimit] ? switcherMaxRows : min(switcherMaxRows, calculatedMaxColumns)
                effectiveMaxRows = calculatedMaxRows
            } else {
                effectiveMaxColumns = calculatedMaxColumns
                if let totalItems, totalItems <= calculatedMaxColumns {
                    effectiveMaxRows = 1
                } else {
                    effectiveMaxRows = Defaults[.switcherIgnoreScreenLimit]
                        ? switcherMaxRows
                        : min(switcherMaxRows, calculatedMaxRows)
                }
            }
        } else if dockPosition == .bottom || dockPosition == .cmdTab {
            effectiveMaxColumns = calculatedMaxColumns
            effectiveMaxRows = (dockPosition == .cmdTab) ? 1 : previewMaxRows
        } else {
            effectiveMaxColumns = previewMaxColumns
            effectiveMaxRows = calculatedMaxRows
        }

        return (effectiveMaxColumns, effectiveMaxRows)
    }

    /// Organizes items into rows/columns based on flow direction
    /// - Parameters:
    ///   - items: Array of items to chunk
    ///   - isHorizontal: If true, fills rows left-to-right; if false, fills columns top-to-bottom
    ///   - maxColumns: Maximum items per row or maximum columns
    ///   - maxRows: Maximum rows or maximum items per column
    ///   - reverse: If true, reverses layout based on direction of window preview
    /// - Returns: Array of chunks (rows or columns)
    static func chunkArray<T>(
        items: [T],
        isHorizontal: Bool,
        maxColumns: Int,
        maxRows: Int,
        reverse: Bool = false,
        fillToLimit: Bool = false
    ) -> [[T]] {
        let totalItems = items.count

        guard totalItems > 0, maxColumns > 0, maxRows > 0 else {
            return []
        }

        var chunks: [[T]]

        if isHorizontal {
            let itemsPerRow: Int
            if fillToLimit {
                itemsPerRow = maxColumns
            } else {
                let actualRowsNeeded = min(maxRows, Int(ceil(Double(totalItems) / Double(maxColumns))))
                itemsPerRow = Int(ceil(Double(totalItems) / Double(actualRowsNeeded)))
            }

            chunks = []
            var startIndex = 0
            while startIndex < totalItems {
                let endIndex = min(startIndex + itemsPerRow, totalItems)
                chunks.append(Array(items[startIndex ..< endIndex]))
                startIndex = endIndex
            }
        } else {
            let itemsPerColumn: Int
            if fillToLimit {
                itemsPerColumn = maxRows
            } else {
                let actualColumnsNeeded = min(maxColumns, Int(ceil(Double(totalItems) / Double(maxRows))))
                itemsPerColumn = Int(ceil(Double(totalItems) / Double(actualColumnsNeeded)))
            }

            chunks = []
            var startIndex = 0
            while startIndex < totalItems {
                let endIndex = min(startIndex + itemsPerColumn, totalItems)
                chunks.append(Array(items[startIndex ..< endIndex]))
                startIndex = endIndex
            }
        }

        if reverse {
            chunks = chunks.reversed()
        }

        return chunks
    }

    /// Creates chunks of window indices organized by rows/columns based on flow direction
    private static func createWindowChunks(
        totalWindows: Int,
        isHorizontal: Bool,
        maxColumns: Int,
        maxRows: Int
    ) -> [[Int]] {
        let windowIndices = Array(0 ..< totalWindows)
        return chunkArray(
            items: windowIndices,
            isHorizontal: isHorizontal,
            maxColumns: maxColumns,
            maxRows: maxRows
        )
    }

    /// Navigates window switcher grid
    /// - Returns: New index after navigation
    static func navigateWindowSwitcher(
        from currentIndex: Int,
        direction: ArrowDirection,
        totalItems: Int,
        dockPosition: DockPosition,
        isWindowSwitcherActive: Bool
    ) -> Int {
        guard let coordinator = SharedPreviewWindowCoordinator.activeInstance?.windowSwitcherCoordinator else {
            let delta = (direction == .right || direction == .down) ? 1 : -1
            return (currentIndex + delta + totalItems) % totalItems
        }

        let gridFlow = GridFlow.resolve(
            compact: false,
            windowSwitcherActive: isWindowSwitcherActive,
            dockPosition: dockPosition
        )

        let maxColumns = coordinator.dimensionState.effectiveGridColumns
        let maxRows = coordinator.dimensionState.effectiveGridRows

        let shouldReverse = (dockPosition == .bottom || dockPosition == .right) && !isWindowSwitcherActive

        return navigateInGrid(
            from: currentIndex,
            direction: direction,
            totalItems: totalItems,
            isHorizontal: gridFlow.laysOutItemsInRows,
            maxColumns: maxColumns,
            maxRows: maxRows,
            reverse: shouldReverse,
            fillToLimit: gridFlow.fillsLinesToLimit
        )
    }

    /// Navigates in a 2D grid
    /// - Returns: New flat index after navigation
    static func navigateInGrid(
        from currentIndex: Int,
        direction: ArrowDirection,
        totalItems: Int,
        isHorizontal: Bool,
        maxColumns: Int,
        maxRows: Int,
        reverse: Bool = false,
        fillToLimit: Bool = false
    ) -> Int {
        guard totalItems > 0, currentIndex >= 0, currentIndex < totalItems else {
            return currentIndex
        }

        let items = Array(0 ..< totalItems)
        let chunks = chunkArray(items: items, isHorizontal: isHorizontal, maxColumns: maxColumns, maxRows: maxRows, reverse: reverse, fillToLimit: fillToLimit)

        var currentChunkIndex = 0
        var currentPositionInChunk = 0

        for (chunkIdx, chunk) in chunks.enumerated() {
            if let posInChunk = chunk.firstIndex(of: currentIndex) {
                currentChunkIndex = chunkIdx
                currentPositionInChunk = posInChunk
                break
            }
        }

        var targetChunkIndex = currentChunkIndex
        var targetPositionInChunk = currentPositionInChunk

        if isHorizontal {
            switch direction {
            case .left:
                targetPositionInChunk -= 1
                if targetPositionInChunk < 0 {
                    targetChunkIndex = (currentChunkIndex - 1 + chunks.count) % chunks.count
                    targetPositionInChunk = chunks[targetChunkIndex].count - 1
                }
            case .right:
                targetPositionInChunk += 1
                if targetPositionInChunk >= chunks[currentChunkIndex].count {
                    targetChunkIndex = (currentChunkIndex + 1) % chunks.count
                    targetPositionInChunk = 0
                }
            case .up:
                targetChunkIndex = (currentChunkIndex - 1 + chunks.count) % chunks.count
                targetPositionInChunk = min(currentPositionInChunk, chunks[targetChunkIndex].count - 1)
            case .down:
                targetChunkIndex = (currentChunkIndex + 1) % chunks.count
                targetPositionInChunk = min(currentPositionInChunk, chunks[targetChunkIndex].count - 1)
            }
        } else {
            switch direction {
            case .up:
                targetPositionInChunk -= 1
                if targetPositionInChunk < 0 {
                    targetChunkIndex = (currentChunkIndex - 1 + chunks.count) % chunks.count
                    targetPositionInChunk = chunks[targetChunkIndex].count - 1
                }
            case .down:
                targetPositionInChunk += 1
                if targetPositionInChunk >= chunks[currentChunkIndex].count {
                    targetChunkIndex = (currentChunkIndex + 1) % chunks.count
                    targetPositionInChunk = 0
                }
            case .left:
                targetChunkIndex = (currentChunkIndex - 1 + chunks.count) % chunks.count
                targetPositionInChunk = min(currentPositionInChunk, chunks[targetChunkIndex].count - 1)
            case .right:
                targetChunkIndex = (currentChunkIndex + 1) % chunks.count
                targetPositionInChunk = min(currentPositionInChunk, chunks[targetChunkIndex].count - 1)
            }
        }

        return chunks[targetChunkIndex][targetPositionInChunk]
    }
}

import Cocoa
import Defaults
import QuartzCore
@testable import DockDoor
import Testing

struct CardGridScrollGeometryTests {
    @MainActor @Test(arguments: [true, false])
    func contentResizeCommitsPointerGeometry(scrollsVertically: Bool) {
        let grid = CardGridScrollView.ContainerView(scrollsVertically: scrollsVertically)
        let host = CardGridScrollView.FlippedView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        host.addSubview(grid)
        grid.setFrameSize(CGSize(width: 200, height: 200))
        grid.contentSize = scrollsVertically
            ? CGSize(width: 200, height: 800)
            : CGSize(width: 800, height: 200)
        grid.scroll(to: 600, animated: false)
        let target = NSView()
        grid.contentView.addSubview(target)

        var expectedOffset: CGFloat = 600
        for extent: CGFloat in [400, 100, 700] {
            grid.contentSize = scrollsVertically
                ? CGSize(width: 200, height: extent)
                : CGSize(width: extent, height: 200)
            expectedOffset = min(expectedOffset, max(0, extent - 200))
            #expect(grid.offset == expectedOffset)
            let point = grid.contentView.convert(CGPoint(x: 60, y: 60), from: grid)
            #expect((scrollsVertically ? point.y : point.x) == 60 + grid.offset)
            #expect(CATransform3DIsIdentity(grid.contentView.layer!.sublayerTransform))
            target.frame = CGRect(
                x: scrollsVertically ? 40 : grid.offset + 40,
                y: scrollsVertically ? grid.offset + 40 : 40,
                width: 40, height: 40
            )
            #expect(grid.hitTest(CGPoint(x: 60, y: 60)) === target)
        }
    }

    @MainActor @Test(arguments: [true, false])
    func viewportResizeAndAxisChangeCommitPointerGeometry(scrollsVertically: Bool) {
        let grid = CardGridScrollView.ContainerView(scrollsVertically: scrollsVertically)
        grid.setFrameSize(CGSize(width: 200, height: 200))
        grid.contentSize = CGSize(width: 800, height: 800)
        grid.scroll(to: 600, animated: false)
        grid.setFrameSize(CGSize(width: 600, height: 600))
        #expect(grid.offset == 200)
        let point = grid.contentView.convert(CGPoint(x: 60, y: 60), from: grid)
        #expect((scrollsVertically ? point.y : point.x) == 260)
        grid.scrollsVertically.toggle()
        #expect(grid.offset == 0)
        #expect(grid.contentView.frame.origin == .zero)
        #expect(CATransform3DIsIdentity(grid.contentView.layer!.sublayerTransform))
    }
}

struct PreviewControlAnimationTests {
    @Test func zeroDurationDisablesControlAnimations() {
        #expect(PreviewControlAnimation.animation(duration: 0, animationsEnabled: true, reduceMotion: false) == nil)
        #expect(PreviewControlAnimation.animation(duration: -0.01, animationsEnabled: true, reduceMotion: false) == nil)
        #expect(PreviewControlAnimation.animation(duration: 0.15, animationsEnabled: true, reduceMotion: false) != nil)
        #expect(PreviewControlAnimation.animation(duration: 0.5, animationsEnabled: true, reduceMotion: false) == PreviewControlAnimation.animation(duration: 0.2, animationsEnabled: true, reduceMotion: false))
        #expect(Defaults.Keys.trafficLightTransitionDuration.defaultValue == 0.1)
    }

    @Test func reduceMotionOverridesPositiveTransitionDurations() {
        for duration in [0.01, 0.1, 0.2, 0.5] {
            for animationsEnabled in [false, true] {
                #expect(PreviewControlAnimation.animation(duration: duration, animationsEnabled: animationsEnabled, reduceMotion: true) == nil)
            }
            #expect(PreviewControlAnimation.animation(duration: duration, animationsEnabled: false, reduceMotion: false) == nil)
            #expect(PreviewControlAnimation.animation(duration: duration, animationsEnabled: true, reduceMotion: false) != nil)
        }
    }
}

struct PreviewOutsideClickTests {
    @Test func nativeMenuOwnsClicksOutsidePreviewUntilTrackingEnds() {
        var snapshot = SharedPreviewWindowCoordinator.TapSnapshot()
        snapshot.isVisible = true
        snapshot.frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let menuLocation = CGPoint(x: 600, y: 200)
        #expect(snapshot.shouldDismissForOutsideClick(at: menuLocation))
        snapshot.isNativeMenuTracking = true
        #expect(!snapshot.shouldDismissForOutsideClick(at: menuLocation))
        snapshot.isNativeMenuTracking = false
        #expect(snapshot.shouldDismissForOutsideClick(at: menuLocation))
    }

    @Test func previewAndSearchClicksDoNotDismiss() {
        var snapshot = SharedPreviewWindowCoordinator.TapSnapshot()
        snapshot.isVisible = true
        snapshot.frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        snapshot.searchFrame = CGRect(x: 100, y: 420, width: 400, height: 40)
        #expect(!snapshot.shouldDismissForOutsideClick(at: CGPoint(x: 200, y: 200)))
        #expect(!snapshot.shouldDismissForOutsideClick(at: CGPoint(x: 200, y: 440)))
        #expect(snapshot.shouldDismissForOutsideClick(at: .zero))
        snapshot.isVisible = false
        #expect(!snapshot.shouldDismissForOutsideClick(at: .zero))
    }
}

struct MissingWindowImageRecoveryTests {
    @Test func fullSizeWindowlessCardsKeepAppOnlyControls() {
        let window = WindowInfo.windowlessEntry(for: NSRunningApplication.current)
        let buttons: Set<WindowAction> = [.quit, .close, .minimize, .hide]
        #expect(resolvedTrafficLightButtons(
            for: window, configuredButtons: buttons, showWindowlessQuitButton: true
        ) == [.quit])
        #expect(resolvedTrafficLightButtons(
            for: window, configuredButtons: buttons, showWindowlessQuitButton: false
        ).isEmpty)
        #expect(Defaults.Keys.showFullSizeWindowlessDockPreviews.defaultValue)
        #expect(Defaults.Keys.showFullSizeWindowlessCmdTabPreviews.defaultValue)
    }

    @Test func cardPresentationRespectsWindowlessSizeAndCompactMode() {
        for showFullSize in [false, true] {
            for isWindowless in [false, true] {
                #expect(WindowPreviewHoverContainer.PreviewCardPresentation.resolve(
                    isWindowlessApp: isWindowless,
                    containerUsesCompactRows: false,
                    showFullSizeWindowlessPreviews: showFullSize,
                    compactWidth: 400,
                    previewWidth: 300
                ) == (isWindowless && !showFullSize ? .compact(width: 300) : .regular))
                #expect(WindowPreviewHoverContainer.PreviewCardPresentation.resolve(
                    isWindowlessApp: isWindowless,
                    containerUsesCompactRows: true,
                    showFullSizeWindowlessPreviews: showFullSize,
                    compactWidth: 400,
                    previewWidth: 300
                ) == .compact(width: 400))
            }
        }
    }

    @Test func placeholderDimensionsKeepDefaultHeightAndAspectRatio() {
        let size = CGSize(width: 300, height: 200)
        let dimensions = WindowPreviewHoverContainer.placeholderDimensions(previewSize: size)
        #expect(dimensions.size == size)
        #expect(dimensions.maxDimensions == size)
    }

    @Test func missingScreenshotsAreRetriedRegardlessOfProvider() {
        for hasSCWindow in [false, true] {
            for missingOnly in [false, true] {
                #expect(WindowUtil.shouldRefreshCachedWindowImage(hasImage: false, hasSCWindow: hasSCWindow, isFresh: false, missingOnly: missingOnly))
            }
        }
    }

    @Test func targetedRecoveryLeavesExistingScreenshotsAlone() {
        for hasSCWindow in [false, true] {
            #expect(!WindowUtil.shouldRefreshCachedWindowImage(hasImage: true, hasSCWindow: hasSCWindow, isFresh: false, missingOnly: true))
            #expect(!WindowUtil.shouldRefreshCachedWindowImage(hasImage: true, hasSCWindow: hasSCWindow, isFresh: true, missingOnly: false))
        }
        #expect(WindowUtil.shouldRefreshCachedWindowImage(hasImage: true, hasSCWindow: false, isFresh: false, missingOnly: false))
        #expect(!WindowUtil.shouldRefreshCachedWindowImage(hasImage: true, hasSCWindow: true, isFresh: false, missingOnly: false))
    }
}

struct PreviewFocusFadePolicyTests {
    @Test func fadingRequiresAnEnabledVisibleFullSizePreview() {
        #expect(PreviewFocusFadePolicy.canFade(enabled: true, hoverAction: .previewFullSize, containerVisible: true,
                                               fullPreviewVisible: true, hasSelection: true, menuTracking: false))
        for condition in 0 ..< 6 {
            #expect(!PreviewFocusFadePolicy.canFade(
                enabled: condition != 0, hoverAction: condition == 1 ? .tap : .previewFullSize,
                containerVisible: condition != 2, fullPreviewVisible: condition != 3,
                hasSelection: condition != 4, menuTracking: condition == 5
            ))
        }
    }

    @Test func timingAndOpacityStayWithinSupportedRanges() {
        #expect(PreviewFocusFadePolicy.bounded(0, fallback: 2, range: 0 ... 5) == 0)
        #expect(PreviewFocusFadePolicy.bounded(-1, fallback: 2, range: 0 ... 5) == 0)
        #expect(PreviewFocusFadePolicy.bounded(9, fallback: 1, range: 0 ... 5) == 5)
        #expect(PreviewFocusFadePolicy.bounded(.nan, fallback: 2, range: 0 ... 5) == 2)
        #expect(PreviewFocusFadePolicy.bounded(.infinity, fallback: 0.25, range: 0 ... 0.5) == 0.25)
        #expect(PreviewFocusFadePolicy.bounded(1, fallback: 0.25, range: 0 ... 0.5) == 0.5)
    }

    @Test func featureDefaultsAreIndependentPerMode() {
        for mode in PreviewFocusFadeMode.allCases {
            #expect(mode.enabledKey.defaultValue == false)
            #expect(mode.delayKey.defaultValue == 1.5)
            #expect(mode.durationKey.defaultValue == 0.5)
            #expect(mode.opacityKey.defaultValue == 0.2)
        }
        #expect(Set(PreviewFocusFadeMode.allCases.map(\.enabledKey.name)).count == 3)
        #expect(Set(PreviewFocusFadeMode.allCases.map(\.delayKey.name)).count == 3)
        #expect(Set(PreviewFocusFadeMode.allCases.map(\.durationKey.name)).count == 3)
        #expect(Set(PreviewFocusFadeMode.allCases.map(\.opacityKey.name)).count == 3)
    }
}

struct AppIconBadgeLayoutTests {
    @Test func badgeSettingsParticipateInLiveAppearanceUpdates() {
        let observedNames = Set(PreviewAppearanceSettings.observedKeys.map(\.name))
        for name in ["switcherShowAppIconBadges", "switcherShowCompactAppIconBadges", "switcherAppIconBadgeScale"] {
            #expect(observedNames.contains(name))
        }
    }

    @Test func emptyDockLabelsDoNotProduceBadges() {
        #expect(AppIconBadgeLayout.normalizedLabel(nil) == nil)
        #expect(AppIconBadgeLayout.normalizedLabel(" \n ") == nil)
        #expect(AppIconBadgeLayout.normalizedLabel(" 12 ") == "12")
        #expect(AppIconBadgeLayout.normalizedLabel("•") == "•")
    }

    @Test func badgesStayInsideEverySupportedIconSize() {
        for size: CGFloat in [16, 24, 28, 35, 48, 64] {
            for scale: CGFloat in [0.75, 1, 1.5] {
                for label in ["1", "12", "999+", "Very long badge label"] {
                    let layout = AppIconBadgeLayout(iconSize: size, scale: scale, label: label)
                    #expect(layout.width <= size)
                    #expect(layout.height <= size)
                    #expect(layout.width >= layout.height)
                    #expect(layout.height > 0)
                }
            }
        }
    }

    @Test func sizeSettingScalesBadgesAndClampsInvalidPreferences() {
        let small = AppIconBadgeLayout(iconSize: 35, scale: 0.75, label: "3")
        let large = AppIconBadgeLayout(iconSize: 35, scale: 1.5, label: "3")
        #expect(large.height == small.height * 2)
        #expect(AppIconBadgeLayout(iconSize: 35, scale: .nan, label: "3").height.isFinite)
        #expect(AppIconBadgeLayout(iconSize: 35, scale: 100, label: "3").height <= 35)
        #expect(AppIconBadgeLayout(iconSize: .infinity, scale: 1, label: "3").width == 0)
    }
}

struct TrafficLightButtonsVisibilityTests {
    @Test func hoverOnlyButtonsFollowTheCardHighlight() {
        for visibility in [TrafficLightButtonsVisibility.dimmedOnPreviewHover, .fullOpacityOnPreviewHover] {
            #expect(!visibility.isVisible(hoveringOverParentWindow: false))
            #expect(visibility.isVisible(hoveringOverParentWindow: true))
        }
    }

    @Test func otherVisibilityModesDoNotDependOnTheCardHighlight() {
        for highlighted in [false, true] {
            #expect(!TrafficLightButtonsVisibility.never.isVisible(hoveringOverParentWindow: highlighted))
            #expect(TrafficLightButtonsVisibility.dimmedUntilButtonHover.isVisible(hoveringOverParentWindow: highlighted))
            #expect(TrafficLightButtonsVisibility.alwaysVisible.isVisible(hoveringOverParentWindow: highlighted))
        }
    }
}

struct WindowStateIndicatorFontSizeTests {
    @Test func defaultFontPreservesExistingIndicatorHeights() {
        #expect(WindowStateIndicator.controlHeight(disableDockStyling: true, fontSize: .system) == 24)
        #expect(WindowStateIndicator.controlHeight(disableDockStyling: false, fontSize: .system) == 22 + 2 * MaterialPillStyle.verticalPadding)
    }

    @Test func largerFontsExpandBothIndicatorStyles() {
        for unstyled in [false, true] {
            let defaultHeight = WindowStateIndicator.controlHeight(disableDockStyling: unstyled, fontSize: .system)
            for size in WindowTitleFontSize.allCases {
                #expect(WindowStateIndicator.controlHeight(disableDockStyling: unstyled, fontSize: size) >= defaultHeight)
            }
            #expect(WindowStateIndicator.controlHeight(disableDockStyling: unstyled, fontSize: .title) > defaultHeight)
        }
    }
}

struct WindowTitlePresentationTests {
    @Test func hoveringTitleReservesSpaceBeforeTheCardIsHighlighted() {
        let presentation = WindowTitlePresentation.resolve(
            title: "Document",
            showWindowTitle: true,
            visibility: .whenHoveringPreview,
            isHighlighted: false
        )

        #expect(!presentation.isVisible)
        #expect(presentation.reservesSpace)
    }

    @Test func alwaysVisibleTitleIsVisibleAndReservesSpace() {
        let presentation = WindowTitlePresentation.resolve(
            title: "Document",
            showWindowTitle: true,
            visibility: .alwaysVisible,
            isHighlighted: false
        )

        #expect(presentation.isVisible)
        #expect(presentation.reservesSpace)
    }

    @Test func hoveringTitleBecomesVisibleWithoutChangingItsReservedSpace() {
        let presentation = WindowTitlePresentation.resolve(
            title: "Document",
            showWindowTitle: true,
            visibility: .whenHoveringPreview,
            isHighlighted: true
        )

        #expect(presentation.isVisible)
        #expect(presentation.reservesSpace)
    }

    @Test func missingOrDisabledTitlesDoNotReserveSpace() {
        let missingTitle = WindowTitlePresentation.resolve(
            title: nil,
            showWindowTitle: true,
            visibility: .whenHoveringPreview,
            isHighlighted: false
        )
        let disabledTitle = WindowTitlePresentation.resolve(
            title: "Document",
            showWindowTitle: false,
            visibility: .whenHoveringPreview,
            isHighlighted: false
        )

        #expect(!missingTitle.reservesSpace)
        #expect(!disabledTitle.reservesSpace)
    }
}

struct WindowActivationRequestTests {
    @Test func concurrentCancellationAndCompletionReplyExactlyOnce() {
        let request = WindowActivationRequest()
        let lock = NSLock()
        var replyCount = 0
        request.onCompletion { _ in
            lock.lock()
            replyCount += 1
            lock.unlock()
        }
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            if index.isMultiple(of: 2) {
                request.finish(true)
            } else {
                request.cancel()
            }
        }
        #expect(replyCount == 1)
    }

    @Test func newerActivationCancelsOnlyThePreviousRequest() {
        let coordinator = WindowActivationCoordinator()
        let previous = WindowActivationRequest()
        let current = WindowActivationRequest()
        var previousResult: WindowActivationResult?
        previous.onCompletion { previousResult = $0 }
        coordinator.begin(previous)
        coordinator.begin(current)
        #expect(previous.isCancelled)
        #expect(previousResult == .cancelled)
        #expect(!current.isCancelled)
        previous.cancel()
        #expect(!current.isCancelled)
    }

    @Test func alreadyCancelledRequestsCannotSupersedeCurrentActivation() {
        let coordinator = WindowActivationCoordinator()
        let current = WindowActivationRequest()
        coordinator.begin(current)
        let cancelled = WindowActivationRequest()
        cancelled.cancel()
        coordinator.begin(cancelled)
        #expect(!current.isCancelled)
    }

    @Test func cancellationBeforeRegistrationCompletesImmediately() {
        let request = WindowActivationRequest()
        request.cancel()
        var results: [WindowActivationResult] = []
        request.onCompletion { results.append($0) }
        request.finish(true)
        #expect(results == [.cancelled])
    }

    @Test func cancellationDoesNotWaitForQueuedWork() {
        let request = WindowActivationRequest()
        var results: [WindowActivationResult] = []
        request.onCompletion { results.append($0) }
        request.cancel()
        #expect(results == [.cancelled])
        request.finish(true)
        request.cancel()
        #expect(results == [.cancelled])
    }

    @Test func successfulCompletionCannotResumeTwice() {
        let request = WindowActivationRequest()
        var results: [WindowActivationResult] = []
        request.onCompletion { results.append($0) }
        request.finish(true)
        request.finish(false)
        request.cancel()
        #expect(results == [.succeeded])
        #expect(request.isCancelled)
    }
}

struct HeldSwitcherConflictTests {
    @Test func everyModifierCanCreateABackwardShortcutConflict() {
        for backward in ShortcutModifierKey.allCases {
            let primary: ShortcutModifierKey = backward == .option ? .command : .option
            let initializer = UserKeyBind(keyCode: 48, modifierFlags: primary.modifierFlags, modifierSide: .left)
            let combination = UserKeyBind(keyCode: 48, modifierFlags: primary.modifierFlags | backward.modifierFlags)
            for backwardCode in [backward.keyCodes.left, backward.keyCodes.right] {
                #expect(WindowSwitcherShortcutResolver.heldShortcutOverlaps(
                    combination, initializer: initializer, backwardKeyCode: backwardCode
                ))
            }
        }
    }

    @Test func unrelatedKeysSidesAndModifiersDoNotConflict() {
        let initializer = UserKeyBind(keyCode: 48, modifierFlags: ShortcutModifierKey.option.modifierFlags, modifierSide: .left)
        let candidates = [
            UserKeyBind(keyCode: 49, modifierFlags: ShortcutModifierKey.option.modifierFlags | ShortcutModifierKey.shift.modifierFlags),
            UserKeyBind(keyCode: 48, modifierFlags: ShortcutModifierKey.option.modifierFlags | ShortcutModifierKey.control.modifierFlags),
            UserKeyBind(keyCode: 48, modifierFlags: ShortcutModifierKey.option.modifierFlags, modifierSide: .right),
        ]
        for candidate in candidates {
            #expect(!WindowSwitcherShortcutResolver.heldShortcutOverlaps(
                candidate, initializer: initializer, backwardKeyCode: ShortcutModifierKey.shift.keyCodes.left
            ))
        }
    }

    @Test func ordinaryBackwardKeysDoNotAddModifierConflicts() {
        let initializer = UserKeyBind(keyCode: 48, modifierFlags: ShortcutModifierKey.option.modifierFlags)
        let combination = UserKeyBind(keyCode: 48, modifierFlags: ShortcutModifierKey.option.modifierFlags | ShortcutModifierKey.shift.modifierFlags)
        #expect(!WindowSwitcherShortcutResolver.heldShortcutOverlaps(combination, initializer: initializer, backwardKeyCode: 49))
    }
}

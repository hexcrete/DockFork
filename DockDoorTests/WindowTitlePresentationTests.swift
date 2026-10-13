import Cocoa
import Defaults
@testable import DockDoor
import QuartzCore
import Testing

struct NumericPreferenceSafetyTests {
    @Test func resizeDelaysStayWithinTheSupportedRange() {
        let cases: [(CGFloat, UInt64)] = [
            (0, 0), (0.18, 180), (0.36, 360), (0.1234, 123), (1, 1000),
            (-1, 0), (2, 1000), (.greatestFiniteMagnitude, 1000),
            (-.greatestFiniteMagnitude, 0), (.infinity, 180), (-.infinity, 180), (.nan, 180),
        ]
        for (seconds, expected) in cases {
            #expect(WindowUtil.resizeRefreshDelayMilliseconds(from: seconds, fallback: 0.18) == expected)
        }
    }

    @Test func invalidResizeDelaysUseTheirOwnDefault() {
        #expect(WindowUtil.resizeRefreshDelayMilliseconds(
            from: .nan, fallback: Defaults.Keys.programmaticResizePreviewRefreshDelay.defaultValue
        ) == 180)
        #expect(WindowUtil.resizeRefreshDelayMilliseconds(
            from: .infinity, fallback: Defaults.Keys.nativeResizePreviewRefreshDelay.defaultValue
        ) == 360)
    }

    @Test func logSizeBoundsPreventArithmeticOverflow() {
        let cases: [(Double, UInt64)] = [
            (-.greatestFiniteMagnitude, 1), (-1, 1), (0, 1), (1, 1), (20.5, 20), (100, 100),
            (.greatestFiniteMagnitude, 100), (.infinity, 10), (-.infinity, 10), (.nan, 10),
        ]
        for (megabytes, expected) in cases {
            let bytes = DebugLogger.maximumLogSizeBytes(megabytes)
            #expect(bytes == expected * 1024 * 1024)
            #expect(bytes * 3 / 4 <= bytes)
        }
    }
}

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

struct OrderedPreviewSelectionTests {
    @Test func checkedWindowsPreventImplicitActivationDismissal() {
        for isKeybindSessionActive in [false, true] {
            #expect(!WindowManipulationObservers.shouldDismissPreviewOnAppActivation(
                isKeybindSessionActive: isKeybindSessionActive,
                keepPreviewOnHoverActivation: false,
                previewHoverAction: .none,
                mouseIsWithinPreviewWindow: false,
                hasCheckedWindows: true
            ))
        }
        #expect(WindowManipulationObservers.shouldDismissPreviewOnAppActivation(
            isKeybindSessionActive: false,
            keepPreviewOnHoverActivation: false,
            previewHoverAction: .none,
            mouseIsWithinPreviewWindow: false,
            hasCheckedWindows: false
        ))
    }

    @Test func selectionRetainsInsertionOrderAndRecheckingAppends() {
        let first = PreviewWindowIdentity(pid: 1, windowID: 10)
        let second = PreviewWindowIdentity(pid: 1, windowID: 11)
        var selection = OrderedPreviewSelection()
        selection.toggle(first)
        selection.toggle(second)
        #expect(selection.identities == [first, second])
        selection.toggle(first)
        selection.toggle(first)
        #expect(selection.identities == [second, first])
        #expect(selection.membership == Set([first, second]))
    }

    @Test func identityIncludesTheOwningProcess() {
        let first = PreviewWindowIdentity(pid: 1, windowID: 10)
        let second = PreviewWindowIdentity(pid: 2, windowID: 10)
        var selection = OrderedPreviewSelection()
        selection.toggle(first)
        selection.toggle(second)
        selection.remove([first])
        #expect(selection.identities == [second])
        #expect(selection.membership == [second])
    }

    @Test func removalPreservesSurvivorOrderAndIgnoresUnrelatedRows() {
        let rows = (1 ... 5).map { PreviewWindowIdentity(pid: 1, windowID: UInt32($0)) }
        var selection = OrderedPreviewSelection()
        for row in rows {
            selection.toggle(row)
        }
        selection.remove([rows[1], rows[3], PreviewWindowIdentity(pid: 2, windowID: 99)])
        #expect(selection.identities == [rows[0], rows[2], rows[4]])
        #expect(selection.membership == Set(selection.identities))
    }
}

struct SelectionCheckboxVisibilityTests {
    @Test func headersShareMirroredAlignmentAndReservation() {
        for style in [AppNameStyle.default, .shadowed, .popover] {
            #expect(PreviewHeaderLayout.alignment(for: style, edge: .top) == (style == .popover ? .top : .topLeading))
            #expect(PreviewHeaderLayout.alignment(for: style, edge: .bottom) == (style == .popover ? .bottom : .bottomLeading))
        }
        #expect(PreviewHeaderLayout.contentReservation(for: .default) == 25)
        #expect(PreviewHeaderLayout.contentReservation(for: .popover) == 30)
        #expect(PreviewHeaderLayout.contentReservation(for: .shadowed) == 0)
    }

    @MainActor @Test func iconCheckboxSizeUsesTheRequestedLinearScale() {
        #expect(PreviewSelectionCheckbox.iconDiameter(for: 16) == 20)
        #expect(PreviewSelectionCheckbox.iconDiameter(for: 20) == 21)
        #expect(PreviewSelectionCheckbox.iconDiameter(for: 35) == 24.75)
        #expect(PreviewSelectionCheckbox.iconDiameter(for: 64) == 32)
    }

    @Test func checkedWindowsAlwaysShowTheControl() {
        for visibility in SelectionCheckboxVisibility.allCases {
            for compact in [false, true] {
                #expect(visibility.showsCheckbox(checked: true, previewHovered: false,
                                                 titleHovered: false, titleAvailable: true, compact: compact))
            }
        }
    }

    @Test func compactTitleHoverUsesOnlyIconHover() {
        #expect(!SelectionCheckboxVisibility.titleHover.showsCheckbox(checked: false, previewHovered: true,
                                                                      titleHovered: false, titleAvailable: false, compact: true))
        #expect(SelectionCheckboxVisibility.titleHover.showsCheckbox(checked: false, previewHovered: true,
                                                                     titleHovered: true, titleAvailable: false, compact: true))
    }

    @Test func otherCompactControlsRequirePreviewHover() {
        for visibility in [SelectionCheckboxVisibility.always, .previewHover] {
            #expect(!visibility.showsCheckbox(checked: false, previewHovered: false,
                                              titleHovered: true, titleAvailable: true, compact: true))
            #expect(visibility.showsCheckbox(checked: false, previewHovered: true,
                                             titleHovered: false, titleAvailable: true, compact: true))
        }
    }

    @Test func titleHoverFallsBackOnlyWhenTheTitleIsUnavailable() {
        #expect(!SelectionCheckboxVisibility.titleHover.showsCheckbox(
            checked: false, previewHovered: true, titleHovered: false, titleAvailable: true, compact: false
        ))
        #expect(SelectionCheckboxVisibility.titleHover.showsCheckbox(
            checked: false, previewHovered: true, titleHovered: false, titleAvailable: false, compact: false
        ))
        #expect(SelectionCheckboxVisibility.titleHover.showsCheckbox(
            checked: false, previewHovered: false, titleHovered: true, titleAvailable: true, compact: false
        ))
    }

    @Test func regularAlwaysAndPreviewHoverRemainDistinct() {
        #expect(SelectionCheckboxVisibility.always.showsCheckbox(
            checked: false, previewHovered: false, titleHovered: false, titleAvailable: true, compact: false
        ))
        #expect(!SelectionCheckboxVisibility.previewHover.showsCheckbox(
            checked: false, previewHovered: false, titleHovered: true, titleAvailable: true, compact: false
        ))
    }
}

struct PreviewBatchSelectionTests {
    @Test func checkedInitiatorsUseCheckingOrderAndUncheckedOnesStaySingle() {
        let first = PreviewWindowIdentity(pid: 1, windowID: 10)
        let second = PreviewWindowIdentity(pid: 2, windowID: 20)
        let unchecked = PreviewWindowIdentity(pid: 1, windowID: 30)
        var selection = OrderedPreviewSelection()
        selection.toggle(first)
        selection.toggle(second)
        #expect(selection.actionIdentities(for: second) == [first, second])
        #expect(selection.actionIdentities(for: unchecked) == nil)
        selection.remove([first])
        #expect(selection.actionIdentities(for: second) == [second])
    }

    @Test func onlyAppWideCommandsAreDeduplicatedByApp() {
        let appWide: Set<WindowAction> = [.hide, .quit, .closeAllWindows, .minimizeAllWindows, .openNewWindow]
        for action in WindowAction.allCases {
            #expect(action.isAppWidePreviewAction == appWide.contains(action))
        }
    }
}

struct PreviewBatchTogglePolicyTests {
    @Test func mixedSelectionsApplyRatherThanUndoState() {
        #expect(PreviewBatchTogglePolicy.targetState([false, true]) == true)
        #expect(PreviewBatchTogglePolicy.targetState([true, false]) == true)
        #expect(PreviewBatchTogglePolicy.targetState([false, false]) == true)
    }

    @Test func onlyUniformlyAppliedStateIsUndone() {
        #expect(PreviewBatchTogglePolicy.targetState([true, true]) == false)
        #expect(PreviewBatchTogglePolicy.targetState([true]) == false)
        #expect(PreviewBatchTogglePolicy.targetState([]) == nil)
    }
}

struct PreviewGroupDragLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func preservesOrderAndConvertsTheVerticalAxis() {
        let frames = [CGRect(x: 100, y: 100, width: 200, height: 100), CGRect(x: 400, y: 300, width: 200, height: 100)]
        #expect(PreviewDragLayout.centers(for: frames, at: CGPoint(x: 500, y: 400), within: screen)
            == [CGPoint(x: 350, y: 500), CGPoint(x: 650, y: 300)])
    }

    @Test func clampsTheFormationRatherThanEachWindowWhenItFits() {
        let frames = [CGRect(x: 0, y: 0, width: 200, height: 100), CGRect(x: 300, y: 0, width: 200, height: 100)]
        #expect(PreviewDragLayout.centers(for: frames, at: .zero, within: screen)
            == [CGPoint(x: 100, y: 50), CGPoint(x: 400, y: 50)])
        #expect(PreviewDragLayout.centers(for: frames, at: CGPoint(x: 1000, y: 800), within: screen)
            == [CGPoint(x: 600, y: 750), CGPoint(x: 900, y: 750)])
    }

    @Test func handlesOtherDisplayOriginsAndOversizedFormations() {
        let display = CGRect(x: -1000, y: 800, width: 1000, height: 800)
        let frames = [CGRect(x: 0, y: 0, width: 200, height: 100), CGRect(x: 1400, y: 0, width: 200, height: 100)]
        #expect(PreviewDragLayout.centers(for: frames, at: CGPoint(x: -900, y: 900), within: display)
            == [CGPoint(x: -1200, y: 900), CGPoint(x: 200, y: 900)])
    }

    @Test func rejectsUnknownGeometryAndAllowsEmptyGroups() {
        #expect(PreviewDragLayout.centers(for: [.zero], at: .zero, within: screen) == nil)
        #expect(PreviewDragLayout.centers(for: [CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100)], at: .zero, within: screen) == nil)
        #expect(PreviewDragLayout.centers(for: [], at: .zero, within: screen) == [])
    }
}

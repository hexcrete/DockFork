import Cocoa
@testable import DockDoor
import Testing

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

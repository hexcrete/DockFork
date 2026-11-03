import Defaults
@testable import DockDoor
import Foundation
import Testing

struct AlternateKeybindTests {
    // Tests run in parallel, so each test that writes defaults uses its own suite
    private let listSuiteName = "com.ethanbills.DockDoorTests.AlternateKeybind.list"
    private let modeSuiteName = "com.ethanbills.DockDoorTests.AlternateKeybind.mode"
    private let primaryModifierFlags = 524_576

    @Test func unsetKeyResolvesToNoShortcut() {
        let alternate = AlternateSwitcherShortcut(keyCode: 0, modifierFlags: 262_401, mode: .currentSpaceOnly, isConfigured: false)

        #expect(alternate.resolvedKeybind(mainKeybind: UserKeyBind(keyCode: 48, modifierFlags: primaryModifierFlags)) == nil)
    }

    @Test func zeroModifierInheritsPrimaryModifier() throws {
        let alternate = AlternateSwitcherShortcut(keyCode: 50, modifierFlags: 0, mode: .activeAppOnly, isConfigured: true)

        let resolved = try #require(alternate.resolvedKeybind(mainKeybind: UserKeyBind(keyCode: 48, modifierFlags: primaryModifierFlags)))
        #expect(resolved.keyCode == 50)
        #expect(resolved.modifierFlags == primaryModifierFlags)
    }

    @Test func explicitModifierIsKept() throws {
        let alternate = AlternateSwitcherShortcut(keyCode: 48, modifierFlags: 262_401, mode: .activeAppOnly, isConfigured: true)

        let resolved = try #require(alternate.resolvedKeybind(mainKeybind: UserKeyBind(keyCode: 48, modifierFlags: primaryModifierFlags)))
        #expect(resolved.keyCode == 48)
        #expect(resolved.modifierFlags == 262_401)
    }

    @Test func alternateListRoundTripsThroughDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: listSuiteName))
        defaults.removePersistentDomain(forName: listSuiteName)
        defer { defaults.removePersistentDomain(forName: listSuiteName) }

        let key = Defaults.Key<[AlternateSwitcherShortcut]>("alternateSwitcherShortcuts", default: [], suite: defaults)
        let alternates = [
            AlternateSwitcherShortcut(keyCode: 50, modifierFlags: 0, mode: .activeAppOnly, isConfigured: true),
            AlternateSwitcherShortcut(keyCode: 48, modifierFlags: 262_401, mode: .activeAppCurrentSpace, isConfigured: true),
        ]

        #expect(Defaults[key].isEmpty)
        Defaults[key] = alternates
        #expect(Defaults[key] == alternates)
    }

    @Test func invocationModeIsStillStoredAsRawString() throws {
        let defaults = try #require(UserDefaults(suiteName: modeSuiteName))
        defaults.removePersistentDomain(forName: modeSuiteName)
        defer { defaults.removePersistentDomain(forName: modeSuiteName) }

        let key = Defaults.Key<SwitcherInvocationMode>("alternateKeybindMode", default: .activeAppOnly, suite: defaults)

        Defaults[key] = .currentSpaceOnly
        #expect(defaults.string(forKey: "alternateKeybindMode") == "currentSpaceOnly")

        defaults.set("activeAppCurrentSpace", forKey: "alternateKeybindMode")
        #expect(Defaults[key] == .activeAppCurrentSpace)
    }
}

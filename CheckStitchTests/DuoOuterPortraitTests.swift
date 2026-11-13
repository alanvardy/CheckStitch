@testable import CheckStitch
import CheckStitchCore
import SwiftUI
import Testing

/// The app target's default actor isolation marks `DuoOuterPortrait`'s members
/// `@MainActor`, so the suite opts in like `OrientationPreferenceTests`.
@MainActor
struct DuoOuterPortraitTests {
    @Test func duoMachineInCompactRegularIsDuoOuter() {
        #expect(
            DuoOuterPortrait.context(
                horizontal: .compact, vertical: .regular, machine: "iPhone19,4")
                == .init(isDuoOuterPortrait: true))
    }

    /// Sad: the Duo inner display (regular/regular) must not change the layout.
    @Test func duoMachineInRegularRegularIsStandard() {
        #expect(
            DuoOuterPortrait.context(
                horizontal: .regular, vertical: .regular, machine: "iPhone19,4") == .standard)
    }

    /// Sad: a non-Duo phone in the same size classes must not change the layout.
    @Test func nonDuoMachineInCompactRegularIsStandard() {
        #expect(
            DuoOuterPortrait.context(
                horizontal: .compact, vertical: .regular, machine: "iPhone17,1") == .standard)
    }

    /// Fail-safe: unknown/missing machine, or missing size classes.
    @Test func emptyMachineIsStandard() {
        #expect(
            DuoOuterPortrait.context(
                horizontal: .compact, vertical: .regular, machine: "") == .standard)
        #expect(
            DuoOuterPortrait.context(horizontal: nil, vertical: nil, machine: "iPhone19,4")
                == .standard)
    }

    /// Happy: the screenshot seam forces the Duo outer context where `uname`
    /// reports the host arch and the size class is regular/regular.
    @Test func forceFlagReturnsDuoContext() {
        #expect(
            DuoOuterPortrait.context(
                horizontal: .regular, vertical: .regular, machine: "arm64", forceDuoOuter: true)
                == .init(isDuoOuterPortrait: true))
    }

    @Test func machineIdentifierIsReadable() {
        #if os(iOS)
            #expect(!DuoOuterPortrait.machineIdentifier.isEmpty)
        #else
            #expect(DuoOuterPortrait.machineIdentifier.isEmpty)
        #endif
    }
}

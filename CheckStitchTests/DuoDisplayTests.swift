@testable import CheckStitchCore
import Testing

struct DuoDisplayTests {
    @Test
    func knownMachineInOuterPortraitIsRecognised() {
        #expect(DuoDisplay.isOuterPortrait(
            machine: "iPhone19,4", isCompactWidth: true, isRegularHeight: true))
    }

    @Test
    func knownMachineWithRegularWidthIsNotOuterPortrait() {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: "iPhone19,4", isCompactWidth: false, isRegularHeight: true))
    }

    @Test
    func knownMachineWithCompactHeightIsNotOuterPortrait() {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: "iPhone19,4", isCompactWidth: true, isRegularHeight: false))
    }

    @Test
    func otherMachinesAreNeverRecognised() {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: "iPhone17,1", isCompactWidth: true, isRegularHeight: true))
        #expect(!DuoDisplay.isOuterPortrait(
            machine: "", isCompactWidth: true, isRegularHeight: true))
    }
}

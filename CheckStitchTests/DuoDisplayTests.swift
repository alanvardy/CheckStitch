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

    /// Exactly one (width, height) combination fires for the known machine.
    @Test(arguments: [("iPhone19,4", true), ("iPhone17,1", false), ("", false), ("iPad13,1", false)])
    func sizeClassMatrixFiresOnlyForKnownMachine(machine: String, expected: Bool) {
        let combinations: [(Bool, Bool)] = [(true, true), (true, false), (false, true), (false, false)]
        for (compactWidth, regularHeight) in combinations {
            let fired = DuoDisplay.isOuterPortrait(
                machine: machine, isCompactWidth: compactWidth, isRegularHeight: regularHeight)
            let isFiringCombination = compactWidth && regularHeight
            #expect(fired == (expected && isFiringCombination))
        }
    }

    /// Malformed identifiers fail safe (feature off), never on.
    @Test(arguments: ["", "iPad13,1", "iPhone19,4 ", "iPhone19,4\n", "iphone19,4"])
    func malformedMachinesAreNotOuterPortrait(machine: String) {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: machine, isCompactWidth: true, isRegularHeight: true))
    }
}

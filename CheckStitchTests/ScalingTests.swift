@testable import CheckStitchCore
import Testing

struct ScalingTests {
    @Test(arguments: [(0, 1), (1, 1), (50, 50), (99, 99), (100, 99)])
    func numberClampsIntoTheSharedRange(_ raw: Int, _ expected: Int) {
        #expect(Scaling.fixed(raw).number == expected)
        #expect(Scaling.prompt(lastFixed: raw).number == expected)
    }

    @Test
    func toggledPreservesTheNumberAcrossModes() {
        #expect(Scaling.fixed(7).toggled() == .prompt(lastFixed: 7))
        #expect(Scaling.prompt(lastFixed: 7).toggled() == .fixed(7))
        #expect(Scaling.fixed(100).toggled() == .prompt(lastFixed: 99))
    }

    @Test
    func clampedNormalisesTheCarriedNumber() {
        #expect(Scaling.fixed(100).clamped() == .fixed(99))
        #expect(Scaling.prompt(lastFixed: 0).clamped() == .prompt(lastFixed: 1))
    }

    @Test
    func displayNumberIsNeutralForPrompt() {
        #expect(Scaling.fixed(7).displayNumber == 7)
        #expect(Scaling.prompt(lastFixed: 7).displayNumber == 1)
        #expect(Scaling.fixed(7).isPrompt == false)
        #expect(Scaling.prompt(lastFixed: 7).isPrompt == true)
    }
}
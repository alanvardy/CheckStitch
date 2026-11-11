@testable import CheckStitchCore
import CoreGraphics
import Testing

struct ChecklistLayoutTests {
    @Test
    func defaultContextKeepsTheStandardGutter() {
        #expect(ChecklistLayout.horizontalInset(.standard) == 32)
    }

    @Test
    func duoOuterContextHalvesTheGutter() {
        #expect(ChecklistLayout.horizontalInset(.init(isDuoOuterPortrait: true)) == 16)
    }

    /// Anti-drift across the whole domain: the default path delegates to
    /// `ChecklistWidth`, never re-deriving the 0.6 fraction.
    @Test(arguments: Array(stride(from: 10.0, through: 1500.0, by: 10.0)) as [CGFloat])
    func defaultWidthMatchesChecklistWidthAcrossTheDomain(width: CGFloat) {
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: width, context: .standard)
            == ChecklistWidth.maxContentWidth(viewportWidth: width))
    }

    @Test
    func duoOuterWidthUsesTheLargerFractionBelowTheCeiling() {
        #expect(ChecklistLayout.maxContentWidth(
            viewportWidth: 200, context: .init(isDuoOuterPortrait: true)) == 160)
    }

    @Test
    func duoOuterWidthClampsAtCeiling() {
        #expect(ChecklistLayout.maxContentWidth(
            viewportWidth: 466, context: .init(isDuoOuterPortrait: true)) == 340)
    }

    @Test
    func duoOuterWidthHitsCeilingAtBoundary() {
        #expect(ChecklistLayout.maxContentWidth(
            viewportWidth: 340 / 0.8, context: .init(isDuoOuterPortrait: true)) == 340)
    }

    /// 425 is the exact 340/0.8 crossover; below it the fraction is active.
    @Test
    func duoOuterWidthBoundaryIs425() {
        let duo = ChecklistLayout.Context(isDuoOuterPortrait: true)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 425, context: duo) == 340)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 424.9, context: duo) < 340)
    }

    /// A ~382 pt safe-area-adjusted read (design risk) yields 0.8 × 382 = 305.6.
    @Test
    func duoOuterWidthAtSafeAreaAdjusted382() {
        let duo = ChecklistLayout.Context(isDuoOuterPortrait: true)
        let actual = ChecklistLayout.maxContentWidth(viewportWidth: 382, context: duo)
        #expect(abs(actual - 305.6) < 0.0001)
    }
}

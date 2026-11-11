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

    /// Anti-drift: the default path delegates to `ChecklistWidth`, never
    /// re-deriving the 0.6 fraction.
    @Test(arguments: [10.0, 200.0, 340.0, 566.0, 567.0, 1000.0, 1500.0] as [CGFloat])
    func defaultWidthMatchesChecklistWidth(width: CGFloat) {
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
}

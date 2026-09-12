@testable import CheckStitchCore
import CoreGraphics
import Testing

struct ChecklistWidthTests {
    @Test
    func maxContentWidthScalesBelowCeiling() {
        #expect(ChecklistWidth.maxContentWidth(viewportWidth: 200) == 120)
    }

    @Test
    func maxContentWidthClampsAtCeiling() {
        #expect(ChecklistWidth.maxContentWidth(viewportWidth: 1000) == 340)
    }

    @Test
    func maxContentWidthHitsCeilingAtBoundary() {
        #expect(ChecklistWidth.maxContentWidth(viewportWidth: 340 / 0.6) == 340)
    }
}

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

    /// A phone-width viewport is used whole: the edit form fills the screen
    /// rather than hugging the left 60% like the list card does.
    @Test
    func editFormMaxWidthFillsPhoneWidth() {
        #expect(ChecklistWidth.editFormMaxWidth(viewportWidth: 390) == 390)
    }

    /// A wide (iPad) viewport is capped at double the list card's ceiling so the
    /// edit form reads as a centred column instead of stretching edge to edge.
    @Test
    func editFormMaxWidthClampsAtCeiling() {
        #expect(ChecklistWidth.editFormMaxWidth(viewportWidth: 1366) == 680)
    }
}

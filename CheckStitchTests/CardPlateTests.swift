@testable import CheckStitch
import SwiftUI
import Testing

/// Pins the `CardPlate` decisions headlessly — the rendered paint and shape
/// can't be asserted, so the constants that drive them get the tests instead
/// (mirrors `ChecklistWidthTests`).
struct CardPlateTests {
    /// Off-white plate keeps the dark rows legible over a photo in light mode.
    @Test
    func plateFillIsOffWhiteInLightMode() {
        #expect(CardPlate.plateFill(for: .light) == Color(red: 0.96, green: 0.95, blue: 0.94))
    }

    /// Black plate keeps the light rows legible over a photo in dark mode.
    @Test
    func plateFillIsBlackInDarkMode() {
        #expect(CardPlate.plateFill(for: .dark) == Color.black)
    }

    /// The checklist plate radius matches the app's other rounded chrome
    /// (the Settings gear, the create plate). The rendered shape can't be
    /// asserted headlessly — tests assert this decision instead.
    @Test
    func plateCornerRadiusIsFourteenPoints() {
        #expect(CardPlate.cornerRadius == 14)
    }
}
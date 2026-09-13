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

    /// The checklist pane starts 100pt down on iOS, clearing the 52pt
    /// floating chrome plates with headroom below them.
    @Test
    func checklistTopMarginClearsThePlateRow() {
        #expect(CardPlate.checklistTopMargin == 100)
    }

    /// The chrome icon plates are solid white in light mode so the icons
    /// read as chips over the wallpaper or photo.
    @Test
    func iconPlateFillIsWhiteInLightMode() {
        #expect(CardPlate.iconPlateFill(for: .light) == Color.white)
    }

    /// Dark mode gives the chrome icons a solid black plate so the blue
    /// glyph and tint ring stay crisp over a dark background or photo.
    @Test
    func iconPlateFillIsBlackInDarkMode() {
        #expect(CardPlate.iconPlateFill(for: .dark) == Color.black)
    }

    /// The chrome icons stay black on the clear light plate.
    @Test
    func iconForegroundIsBlackInLightMode() {
        #expect(CardPlate.iconForeground(for: .light) == Color.black)
    }

    /// The chrome icons turn blue on the black dark-mode plate.
    @Test
    func iconForegroundIsBlueInDarkMode() {
        #expect(CardPlate.iconForeground(for: .dark) == Color.blue)
    }
}
import SwiftUI

/// Shared styling decisions for the checklist content plate — the rounded
/// rectangle that keeps the rows readable when a photo is showing behind them
/// (SingleThread's card treatment, ported for the list screen). Extracted so
/// the constants are owned by the namespace that names them and the decisions
/// can be asserted headlessly in tests — the rendered paint can't be.
enum CardPlate {
    /// Corner radius for the checklist plate, matching the app's other rounded
    /// chrome (the Settings gear, the create plate) at 14pt. SingleThread's
    /// plate is 10pt; CheckStitch keeps 14pt for local visual rhythm.
    ///
    /// `nonisolated` (like `ChecklistWidth.maxContentWidth`) so the decision
    /// stays pinnable from nonisolated test contexts.
    nonisolated static let cornerRadius: CGFloat = 14

    /// Top margin for the checklist content on iOS: the first row starts
    /// 100pt down, clearing the 52×52 floating chrome plates (which sit 8pt
    /// from the top edge) with extra breathing room below them. macOS needs
    /// no inset — its buttons live in the window title bar, not over the
    /// content area.
    nonisolated static let checklistTopMargin: CGFloat = 100

    /// Small content-sized high-contrast plate behind the checklist rows:
    /// off-white in light, black in dark, so the rows stay readable over a
    /// photo or wallpaper.
    nonisolated static func plateFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black : Color(red: 0.96, green: 0.95, blue: 0.94)
    }

    /// Fill for the 52×52 plates behind the floating chrome icons (the
    /// Settings gear and the create plus). Solid white in light mode so the
    /// icons read as chips over a wallpaper or photo; solid black in dark
    /// mode so a blue glyph and the tint ring stay crisp over a dark
    /// background or photo.
    nonisolated static func iconPlateFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    /// Glyph color for the floating chrome icons: black over the white plate
    /// in light mode, blue over the black plate in dark mode.
    nonisolated static func iconForeground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.blue : Color.black
    }
}
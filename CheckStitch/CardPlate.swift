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

    /// Small content-sized high-contrast plate behind the checklist rows:
    /// off-white in light, black in dark, so the rows stay readable over a
    /// photo or wallpaper.
    nonisolated static func plateFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black : Color(red: 0.96, green: 0.95, blue: 0.94)
    }
}
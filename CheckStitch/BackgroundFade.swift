import Foundation

// MARK: - BackgroundFade

/// User-selectable background photo fade, expressed as a percentage. Persisted
/// in `UserDefaults` via `@AppStorage` as an `Int` percent so the settings
/// picker can offer fixed 10% increments. Higher values mean a fainter photo:
/// 0% shows the photo at full strength, 90% leaves barely a trace.
enum BackgroundFade {
    // MARK: Internal

    /// Percentage selected before the user changes anything.
    static let defaultValue = 50

    /// Step between selectable percentages.
    static let step = 10

    /// Every selectable percentage, ascending.
    static let allValues = Array(stride(from: Self.minValue, through: Self.maxValue, by: step))

    /// Converts a stored fade percentage into the SwiftUI `opacity` fraction
    /// for the photo layer (full opacity at 0% fade), clamping out-of-range
    /// persisted values so a corrupt default can't produce an invalid opacity.
    static func opacity(for percent: Int) -> Double {
        1 - Double(percent.clamped(to: minValue ... maxValue)) / 100
    }

    // MARK: Private

    private static let minValue = 0
    private static let maxValue = 90
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

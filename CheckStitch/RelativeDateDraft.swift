import Foundation

/// Text ↔ relative-date-offset conversion for the edit screen's typed day count.
///
/// The screen buffers the field's text rather than binding it straight to an
/// `Int?`, so a half-typed `"-"` survives long enough to be completed. Empty
/// text means "no date"; well-formed text is that offset; anything else is
/// in-progress and must not be committed, so an invalid keystroke never clears
/// or rewrites the stored date. The `"0 means today"` helper caption is the
/// localization key, not this type.
enum RelativeDateDraft {
    /// What a field's text currently means for the stored value.
    enum Commit: Equatable {
        /// A complete value: `nil` clears the date, an offset sets it.
        case value(Int?)
        /// In-progress text (e.g. a lone `"-"`): leave the stored value alone.
        case inProgress
    }

    /// Parses field text. Empty (or whitespace) → `.value(nil)`, a whole
    /// integer → `.value(offset)`, anything else → `.inProgress`.
    static func commit(for text: String) -> Commit {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .value(nil) }
        guard let offset = Int(trimmed) else { return .inProgress }
        return .value(offset)
    }

    /// The field text for a stored value; `nil` (no date) renders empty.
    static func text(for relativeDate: Int?) -> String {
        relativeDate.map(String.init) ?? ""
    }

    /// The text to adopt after the stored value changes externally (an iCloud
    /// merge), or `nil` when `current` already represents `newValue` — so a
    /// padded `"05"` or a half-typed `"-"` is never rewritten mid-edit.
    static func text(afterExternalChange newValue: Int?, current: String) -> String? {
        guard Int(current) != newValue else { return nil }
        return text(for: newValue)
    }
}
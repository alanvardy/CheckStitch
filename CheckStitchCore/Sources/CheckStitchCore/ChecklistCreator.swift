import Foundation

/// Outcome of a checklist creation attempt. `permissionDenied` replaces the old
/// silent `return`, so denial is observable rather than a no-op.
public enum ChecklistCreationOutcome: Equatable, Sendable {
    case created(count: Int)
    case permissionDenied
    case failed(String)
}

/// Policy for optional 1-based numbering of created reminder titles.
///
/// Defined here, in the one policy seam that drops blank titles, so the format
/// exists in exactly one place; both `ChecklistCreator` and the app-side
/// `ChecklistReminders` apply it. Numbering is unbounded past 9.
public enum ChecklistTitleNumbering {
    /// `"<position>: <title>"` when `numbered`, otherwise `title` unchanged.
    /// Single-digit positions are zero-padded to two digits (`01:`…`09:`) only
    /// when there are more than 9 non-blank items, so titles sort numerically
    /// under Reminders' lexical ordering instead of putting `10:` ahead of `2:`.
    /// `itemCount` is the caller's effective non-blank item count.
    public static func title(_ title: String, position: Int, numbered: Bool, itemCount: Int) -> String {
        if !numbered { return title }
        let padded = itemCount > 9 && position < 10 ? "0\(position)" : "\(position)"
        return "\(padded): \(title)"
    }
}

/// Replaces every `((n))` marker (literal `((`, one or more ASCII digits, `))`)
/// with the product `n * multiple`, leaving all other text byte-for-byte
/// unchanged. Returns `text` unchanged when `multiple == 1`. A marker whose
/// digits do not parse as `Int`, or whose product overflows `Int`, is left
/// literal. Pure; no model dependency.
public enum ChecklistScaling {
    public static func resolve(_ text: String, multiple: Int) -> String {
        guard multiple != 1, text.contains("((") else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "(", let second = text.index(index, offsetBy: 2, limitedBy: text.endIndex),
               second <= text.endIndex, text[text.index(after: index)] == "(" {
                let digitsStart = second
                var cursor = digitsStart
                while cursor < text.endIndex, isASCIIDigit(text[cursor]) {
                    cursor = text.index(after: cursor)
                }
                if cursor > digitsStart, cursor < text.endIndex, text[cursor] == ")" {
                    let afterClose = text.index(after: cursor)
                    // Closing must be exactly `))`: a third `)` right after makes
                    // the run an over-parenthesised literal, not a marker.
                    if afterClose < text.endIndex, text[afterClose] == ")",
                       text.index(after: afterClose) == text.endIndex
                           || text[text.index(after: afterClose)] != ")",
                       let value = Int(text[digitsStart..<cursor]),
                       value.multipliedReportingOverflow(by: multiple).overflow == false {
                        result += "\(value * multiple)"
                        index = text.index(after: afterClose)
                        continue
                    }
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}

/// Owns the reminder-creation policy: ask permission, drop blank titles, create
/// one reminder per remaining item. Items with a relative date set a
/// date-only `dueDateComponents` on the reminder; the offset-to-date
/// arithmetic lives in `ChecklistItem.dueDateComponents`.
///
/// Declared `Sendable` explicitly — a `public` struct gets no inferred
/// conformance, and callers would otherwise fail to send it across isolation
/// boundaries.
public struct ChecklistCreator: Sendable {
    public init(reminders: ReminderCreating,
                now: @escaping @Sendable () -> Date = Date.init,
                calendar: Calendar = .current,
                prefixNumbers: Bool = false) {
        self.reminders = reminders
        self.now = now
        self.calendar = calendar
        self.prefixNumbers = prefixNumbers
    }

    public func create(from items: [ChecklistItem], multiple: Int = 1) async -> ChecklistCreationOutcome {
        do {
            guard try await reminders.requestAccess() else { return .permissionDenied }
            let itemCount = items.filter { !$0.isBlank }.count
            var created = 0
            var position = 0
            let today = now()
            for item in items where !item.isBlank {
                // Position is assigned after blank items are dropped, so an emptied
                // row never leaves a gap: item one is always 1.
                position += 1
                try await reminders.create(
                    title: ChecklistTitleNumbering.title(
                        ChecklistScaling.resolve(item.title, multiple: multiple),
                        position: position, numbered: prefixNumbers, itemCount: itemCount),
                    dueDateComponents: item.dueDateComponents(today: today, calendar: calendar))
                created += 1
            }
            return .created(count: created)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private let reminders: ReminderCreating
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let prefixNumbers: Bool
}

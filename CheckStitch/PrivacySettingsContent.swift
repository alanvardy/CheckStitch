import Foundation

// MARK: - PrivacySection

/// A single section of the privacy policy: a headline plus explanatory prose.
struct PrivacySection: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
}

// MARK: - PrivacyGuideContent

/// Static disclosure copy — the single source of truth for what CheckStitch
/// claims about its data handling.
///
/// IMPORTANT: this copy hardcodes facts about the app's data flow (Apple
/// Reminders created via EventKit and never touched afterwards, checklist sync
/// through the user's own iCloud via shared app storage, and the
/// `vardy.cc/unsplash` background-image fetch). If any of those data flows
/// change, update this copy in the same change or it becomes misleading.
enum PrivacyGuideContent {
    // MARK: Internal

    /// The disclosure sections, localized through the app catalog.
    static var sections: [PrivacySection] {
        let remindersTitle = localized("Reminders")
        let remindersBody = localized("Reminders are created through Apple Reminders "
            + "and appear in your Reminders inbox. They stay on your device or "
            + "in your own iCloud account, and are never sent to the author or "
            + "any third party. CheckStitch never reads, edits, completes, or "
            + "deletes reminders after creating them.")
        let syncTitle = localized("Checklists & Sync")
        let syncBody = localized("Your checklists are stored on your device in shared "
            + "app storage and synced through your own iCloud account. They are "
            + "never sent to the author or any third party.")
        let backgroundTitle = localized("Background Image")
        let backgroundBody = localized("When the background is enabled, the wallpaper "
            + "and artist information are fetched via a proxy at vardy.cc. "
            + "This is the app's only network traffic, and it never includes any "
            + "reminder, checklist, or preference data.")
        return [
            PrivacySection(id: "reminders", title: remindersTitle, body: remindersBody),
            PrivacySection(id: "sync", title: syncTitle, body: syncBody),
            PrivacySection(id: "background", title: backgroundTitle, body: backgroundBody)
        ]
    }

    static var closingLine: String {
        localized("CheckStitch has no analytics, no tracking, and no advertising.")
    }

    // MARK: Private

    /// Resolves a key from the app catalog. The key may be assembled from
    /// multiple literal pieces (the keys are the full English sentences);
    /// `String.LocalizationValue(stringLiteral:)` keeps the assembled string
    /// as the exact lookup key.
    private static func localized(_ key: String) -> String {
        String(
            localized: String.LocalizationValue(stringLiteral: key),
            table: "Localizable",
            bundle: .main)
    }
}

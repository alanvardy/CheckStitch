import Foundation

// MARK: - PrivacySection

/// A single section of the privacy policy: a headline plus explanatory prose.
///
/// Titles and bodies stay as `LocalizedStringResource`s so SwiftUI resolves
/// them against `\.locale` (the app-language environment value) rather than
/// the process locale.
struct PrivacySection: Identifiable, Equatable {
    let id: String
    let title: LocalizedStringResource
    let body: LocalizedStringResource
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
///
/// IMPORTANT: every value here is returned unresolved. Resolving eagerly with
/// `String(localized:bundle:)` pins the *process* locale and silently renders
/// English under a chosen app language — the exact bug this file used to have.
/// Views render the resources directly; non-View callers use
/// `resolved(in:)`/`resolvedInAppLanguage()`.
enum PrivacyGuideContent {
    // MARK: Internal

    /// The disclosure sections, localized through the app catalog.
    static var sections: [PrivacySection] {
        [
            PrivacySection(
                id: "reminders",
                title: resource("Reminders"),
                body: resource("Reminders are created through Apple Reminders "
                    + "and appear in your Reminders inbox. They stay on your device or "
                    + "in your own iCloud account, and are never sent to the author or "
                    + "any third party. CheckStitch never reads, edits, completes, or "
                    + "deletes reminders after creating them.")),
            PrivacySection(
                id: "sync",
                title: resource("Checklists & Sync"),
                body: resource("Your checklists are stored on your device in shared "
                    + "app storage and synced through your own iCloud account. They are "
                    + "never sent to the author or any third party.")),
            PrivacySection(
                id: "background",
                title: resource("Background Image"),
                body: resource("When the background is enabled, the wallpaper "
                    + "and artist information are fetched via a proxy at vardy.cc. "
                    + "This is the app's only network traffic, and it never includes any "
                    + "reminder, checklist, or preference data."))
        ]
    }

    static var closingLine: LocalizedStringResource {
        resource("CheckStitch has no analytics, no tracking, and no advertising.")
    }

    // MARK: Private

    /// Builds the lookup resource for a key. The key may be assembled from
    /// multiple literal pieces (the keys are the full English sentences), so it
    /// is passed as a plain `String`; `String.LocalizationValue(stringLiteral:)`
    /// keeps the assembled string as the exact lookup key, and `bundle: .main`
    /// is the app catalog.
    private static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(stringLiteral: key),
            table: "Localizable",
            bundle: .main)
    }
}

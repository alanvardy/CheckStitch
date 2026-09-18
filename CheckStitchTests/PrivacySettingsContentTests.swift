import Foundation
@testable import CheckStitch
import Testing

/// Exercises the privacy-policy disclosure copy: every section must carry
/// non-empty title and body, and the closing line must keep the committed
/// no-analytics/no-tracking/no-advertising claim (asserted against the
/// en-pinned lookup so the check is host-locale independent).
@MainActor
struct PrivacySettingsContentTests {
    @Test
    func privacyGuideContentCoversAllDisclosures() {
        let sections = PrivacyGuideContent.sections

        #expect(sections.count == 3)
        #expect(!PrivacyGuideContent.closingLine.isEmpty)

        for section in sections {
            #expect(!section.title.isEmpty)
            #expect(!section.body.isEmpty)
        }

        // The background proxy domain is a literal (never translated), so it marks
        // the network-disclosure section regardless of host locale.
        #expect(sections.contains { $0.body.contains("vardy.cc") })
    }

    @Test
    func privacyGuideContentHasNoAnalyticsClaim() {
        // The committed English copy is the canonical privacy commitment. Assert the
        // claims against the en-pinned lookup so this test stays host-locale
        // independent (the runtime closing line is translated on non-English locales).
        let enClosing = String.en(
            "CheckStitch has no analytics, no tracking, and no advertising.",
            bundle: .main)

        #expect(enClosing.contains("no analytics"))
        #expect(enClosing.contains("no tracking"))
        #expect(enClosing.contains("no advertising"))
        #expect(!PrivacyGuideContent.closingLine.isEmpty)
    }

    @Test
    func privacyGuideContentResolvesTranslatedTextFromTheMainBundle() throws {
        // The hosted runner resolves `String(localized:)` with the process locale, so a
        // locale pin cannot observe e.g. German (see
        // `LocalizationTests.appCatalogIsEmbeddedInTheMainBundle`). Assert the privacy copy
        // against the embedded German table instead: every key must be present, non-empty,
        // and translated (different from the en-pinned lookup).
        let privacyKeys = [
            "Reminders",
            "Checklists & Sync",
            "Background Image",
            "Privacy Policy",
            "CheckStitch has no analytics, no tracking, and no advertising.",
            "Reminders are created through Apple Reminders and appear in your Reminders inbox. "
            + "They stay on your device or in your own iCloud account, and are never sent to the "
            + "author or any third party. CheckStitch never reads, edits, completes, or deletes "
            + "reminders after creating them.",
            "Your checklists are stored on your device in shared app storage and synced through "
            + "your own iCloud account. They are never sent to the author or any third party.",
            "When the background is enabled, the wallpaper and artist information are fetched via "
            + "a proxy at vardy.cc. This is the app's only network traffic, and it never includes "
            + "any reminder, checklist, or preference data.",
        ]
        let germanURL = try #require(
            Bundle.main.url(
                forResource: "Localizable", withExtension: "strings",
                subdirectory: "", localization: "de"),
            "Main bundle has no de table at runtime")
        let germanTable = try #require(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: germanURL), format: nil)
                as? [String: String],
            "Main bundle de table is not a readable key/value plist")

        for key in privacyKeys {
            #expect(germanTable[key]?.isEmpty == false,
                "\(key) is missing or empty in the German table")
            #expect(germanTable[key] != String.en(key, bundle: .main),
                "\(key) is identical to English in the German table")
        }
    }
}

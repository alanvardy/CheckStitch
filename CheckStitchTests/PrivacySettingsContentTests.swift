import CheckStitchCore
import Foundation
@testable import CheckStitch
import Testing

/// Exercises the privacy-policy disclosure copy: every section must carry
/// non-empty title and body, the closing line must keep the committed
/// no-analytics/no-tracking/no-advertising claim, and — the point of the
/// ticket — the copy must follow the *selected app language* rather than the
/// process locale.
///
/// The copy is returned as `LocalizedStringResource`s and resolved at render
/// time, so these tests resolve it through the same seam the view uses:
/// `resolved(in:)`, which sets `resource.locale` *before* looking the key up.
/// (The `String(localized:…, locale:)` parameter form does not pin the language
/// on this toolchain — spike NO-GO.)
@MainActor
struct PrivacySettingsContentTests {
    @Test
    func privacyGuideContentCoversAllDisclosures() {
        let sections = PrivacyGuideContent.sections

        #expect(sections.count == 3)

        for section in sections {
            #expect(!section.title.resolved(in: Self.english).isEmpty)
            #expect(!section.body.resolved(in: Self.english).isEmpty)
        }

        #expect(!PrivacyGuideContent.closingLine.resolved(in: Self.english).isEmpty)

        // The background proxy domain is a literal (never translated), so it marks
        // the network-disclosure section regardless of locale.
        #expect(sections.contains { $0.body.resolved(in: Self.english).contains("vardy.cc") })
    }

    @Test
    func privacyGuideContentHasNoAnalyticsClaim() {
        // The committed English copy is the canonical privacy commitment: assert
        // the *lookup key* still carries all three claims, so the promise cannot
        // be quietly weakened or dropped from the catalog contract.
        let key = PrivacyGuideContent.closingLine.key

        #expect(key == "CheckStitch has no analytics, no tracking, and no advertising.")
        #expect(key.contains("no analytics"))
        #expect(key.contains("no tracking"))
        #expect(key.contains("no advertising"))

        let enClosing = PrivacyGuideContent.closingLine.resolved(in: Self.english)
        #expect(enClosing.contains("no analytics"))
        #expect(enClosing.contains("no tracking"))
        #expect(enClosing.contains("no advertising"))
    }

    /// Regression for the shipped bug: the privacy copy used to be resolved
    /// eagerly with `String(localized:bundle:)`, which pins the *process*
    /// locale. Choosing Spanish in Interface rendered "Política de privacidad"
    /// as the row and navigation title (SwiftUI literals, resolved against
    /// `\.locale`) while every section body and the closing line stayed English.
    ///
    /// Resolving the same content against two locales must therefore produce two
    /// different translations, and the Spanish resolution must match the
    /// compiled Spanish table.
    @Test
    func privacyCopyResolvesInTheSelectedLanguageRatherThanTheProcessLocale() throws {
        let spanish = Locale(identifier: "es")
        let spanishTable = try Self.compiledTable("es")
        let sections = PrivacyGuideContent.sections

        for section in sections {
            let titleES = section.title.resolved(in: spanish)
            let bodyES = section.body.resolved(in: spanish)

            #expect(titleES == spanishTable[section.title.key],
                "\(section.title.key) did not resolve to the compiled es translation")
            #expect(bodyES == spanishTable[section.body.key],
                "section body did not resolve to the compiled es translation")
            #expect(bodyES != section.body.resolved(in: Self.english))
        }

        let closingES = PrivacyGuideContent.closingLine.resolved(in: spanish)
        #expect(closingES == spanishTable[PrivacyGuideContent.closingLine.key])
        #expect(closingES != PrivacyGuideContent.closingLine.resolved(in: Self.english))

        // Spot-check one known translation so the assertion is readable and
        // mirrors the reported reproduction (Spanish, "Reminders").
        #expect(sections.first?.title.resolved(in: spanish) == "Recordatorios")
    }

    @Test
    func privacyGuideContentResolvesTranslatedTextFromTheMainBundle() throws {
        // Assert the privacy copy against the embedded German table: every key
        // must be present, non-empty, and translated (different from the
        // en-pinned lookup).
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
        let germanTable = try Self.compiledTable("de")
        let spanishTable = try Self.compiledTable("es")

        for key in privacyKeys {
            #expect(germanTable[key]?.isEmpty == false,
                "\(key) is missing or empty in the German table")
            #expect(germanTable[key] != String.en(key, bundle: .main),
                "\(key) is identical to English in the German table")
            #expect(spanishTable[key]?.isEmpty == false,
                "\(key) is missing or empty in the Spanish table")
            #expect(spanishTable[key] != String.en(key, bundle: .main),
                "\(key) is identical to English in the Spanish table")
        }
    }

    // MARK: Private

    private static let english = Locale(identifier: "en")

    /// Reads a compiled `Localizable.strings` table out of the host app bundle.
    private static func compiledTable(_ language: String) throws -> [String: String] {
        let url = try #require(
            Bundle.main.url(
                forResource: "Localizable", withExtension: "strings",
                subdirectory: "", localization: language),
            "Main bundle has no \(language) table at runtime")
        return try #require(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url), format: nil)
                as? [String: String],
            "Main bundle \(language) table is not a readable key/value plist")
    }
}

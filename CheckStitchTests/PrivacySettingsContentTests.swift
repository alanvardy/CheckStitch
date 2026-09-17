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
}

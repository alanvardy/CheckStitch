@testable import CheckStitchCore
import Foundation
import Testing

struct AppLanguageTests {
    @Test(arguments: [
        (AppLanguage.english, "en"),
        (.german, "de"),
        (.spanish, "es"),
        (.french, "fr"),
        (.japanese, "ja"),
        (.simplifiedChinese, "zh-Hans"),
    ] as [(AppLanguage, String)])
    func everyCaseMapsToItsCatalogLocale(_ language: AppLanguage, _ identifier: String) {
        #expect(language.locale == Locale(identifier: identifier))
    }

    @Test
    func systemFollowsTheProcessLocale() {
        #expect(AppLanguage.system.locale == Locale.current)
    }

    @Test
    func everyCaseIteratedLanguageIsOneOfTheSixCatalogs() {
        let pinned = Set(AppLanguage.allCases.map(\.rawValue)).subtracting(["system"])
        #expect(pinned == ["en", "de", "es", "fr", "ja", "zh-Hans"])
    }
}
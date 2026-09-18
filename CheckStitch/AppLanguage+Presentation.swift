import CheckStitchCore
import SwiftUI

/// Picker rows for the Language setting. The six endonyms render verbatim in
/// every language (an absent catalog key resolves to its own text, pinned by
/// `LocalizationTests.unknownKeyFallsBackToItsOwnText`); only `System` is a
/// catalog key.
extension AppLanguage {
    var title: LocalizedStringResource {
        switch self {
        case .system: LocalizedStringResource("System", table: "Localizable", bundle: .main)
        case .english: LocalizedStringResource("English", table: "Localizable", bundle: .main)
        case .german: LocalizedStringResource("Deutsch", table: "Localizable", bundle: .main)
        case .spanish: LocalizedStringResource("Español", table: "Localizable", bundle: .main)
        case .french: LocalizedStringResource("Français", table: "Localizable", bundle: .main)
        case .japanese: LocalizedStringResource("日本語", table: "Localizable", bundle: .main)
        case .simplifiedChinese: LocalizedStringResource("简体中文", table: "Localizable", bundle: .main)
        }
    }
}
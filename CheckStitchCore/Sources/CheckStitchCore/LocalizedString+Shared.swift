import Foundation

// MARK: - Explicit-locale resolution

public extension LocalizedStringResource {
    /// Resolves this resource against an explicit locale. Views get this for
    /// free from `\.locale`; non-View callers use this or
    /// `resolvedInAppLanguage()`.
    ///
    /// Setting `locale` *before* evaluating is the seam: the explicit
    /// `String(localized:…, locale:)` parameter form does not pin the language
    /// on this toolchain (spike NO-GO), while this form does.
    func resolved(in locale: Locale) -> String {
        var resource = self
        resource.locale = locale
        return String(localized: resource)
    }

    /// Resolves against the persisted app-language preference.
    func resolvedInAppLanguage() -> String {
        resolved(in: AppLocaleState.storedEffectiveLocale)
    }
}
import CheckStitchCore
import SwiftUI

// MARK: - PrivacySettingsView

/// Read-only, long-form disclosure of what CheckStitch stores, syncs, and sends
/// over the network. Stateless: no bindings, no view model, no init parameters
/// — it renders `PrivacyGuideContent` directly.
///
/// The copy resolves against the *environment* locale, which the app roots bind
/// to the chosen app language (`MyApp` → `\.locale`). Resolving explicitly
/// through `resolved(in:)` (rather than letting SwiftUI resolve the resource)
/// keeps the seam that was verified on this toolchain and makes the dependence
/// on `\.locale` visible here, so a language change re-renders this screen.
struct PrivacySettingsView: View {
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            ForEach(PrivacyGuideContent.sections) { section in
                Section {
                    Text(section.body.resolved(in: locale))
                } header: {
                    Text(section.title.resolved(in: locale))
                }
            }
            Section {} footer: {
                Text(PrivacyGuideContent.closingLine.resolved(in: locale))
            }
        }
        .navigationTitle("Privacy Policy")
        .settingsSubscreenLayout()
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        PrivacySettingsView()
    }
}

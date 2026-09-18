import CheckStitchCore
import SwiftUI

/// Interface preferences: appearance, language, text size, and (on iOS) the
/// orientation lock. Takes only the bindings it needs rather than the whole
/// settings bag, matching `BackgroundSettingsView`.
struct InterfaceSettingsView: View {
    @Binding var appearanceMode: AppearanceMode
    @Binding var appLanguage: AppLanguage
    @Binding var textSize: TextSize
    #if os(iOS)
        @Binding var allowsLandscape: Bool
    #endif

    var body: some View {
        Form {
            Picker(selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("Appearance")
                    caption("Choose between system, light, and dark mode.")
                }
            }
            .accessibilityIdentifier("appearancePicker")

            Picker(selection: $appLanguage) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.title).tag(language)
                }
            } label: {
                Text("Language")
            }
            .accessibilityIdentifier("languagePicker")

            Picker(selection: $textSize) {
                ForEach(TextSize.allCases, id: \.self) { size in
                    Label(size.title, systemImage: size.systemImage)
                        .tag(size)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("Text Size")
                    caption("Adjust the size of text throughout the app.")
                }
            }
            .accessibilityIdentifier("textSizePicker")

            #if os(iOS)
                Toggle(isOn: $allowsLandscape) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Allow landscape")
                            caption("Let the app rotate on iPhone.")
                        }
                    } icon: {
                        Image(systemName: "rectangle.landscape.rotate")
                    }
                }
                .accessibilityIdentifier("allowLandscapeToggle")
            #endif
        }
        .navigationTitle("Interface")
        .settingsSubscreenLayout()
    }

    @ViewBuilder
    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    NavigationStack {
        #if os(iOS)
            InterfaceSettingsView(
                appearanceMode: .constant(AppearanceMode.system),
                appLanguage: .constant(.system),
                textSize: .constant(.system),
                allowsLandscape: .constant(true))
        #else
            InterfaceSettingsView(
                appearanceMode: .constant(AppearanceMode.system),
                appLanguage: .constant(.system),
                textSize: .constant(.system))
        #endif
    }
}

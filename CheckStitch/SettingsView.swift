import SwiftUI

/// Modal settings screen presented from the gear button. Currently holds a
/// single entry — the appearance (theme) picker — bound back to the
/// `@AppStorage`-backed property on `ContentView`.
struct SettingsView: View {
    @Binding var appearanceMode: AppearanceMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Appearance")
                            Text("Choose between system, light, and dark mode.")
                        }
                    }
                    .accessibilityIdentifier("appearancePicker")
                }
            }
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .checkStitchButton()
                }
            }
        }
    }
}

#Preview {
    SettingsView(appearanceMode: .constant(AppearanceMode.system))
}

#Preview("Dark") {
    SettingsView(appearanceMode: .constant(AppearanceMode.dark))
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

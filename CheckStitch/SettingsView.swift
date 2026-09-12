import SwiftUI

/// Modal settings screen presented from the gear button. Holds the
/// appearance (theme) picker, bound back to the `@AppStorage`-backed property
/// on `ContentView`, plus the row that pushes the Background subscreen over a
/// staged `SettingsBindings` bag.
struct SettingsView: View {
    @Binding var appearanceMode: AppearanceMode
    @Bindable var bindings: SettingsBindings
    var backgroundImage: BackgroundImageStore
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

                Section {
                    NavigationLink {
                        BackgroundSettingsView(
                            backgroundEnabled: $bindings.backgroundEnabled,
                            backgroundFadePercent: $bindings.backgroundFadePercent,
                            backgroundPinned: $bindings.backgroundPinned,
                            backgroundImage: backgroundImage)
                    } label: {
                        Label("Background", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("settingsBackgroundRow")
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
        #if os(macOS)
        .preferredColorScheme(appearanceMode.colorScheme)
        #endif
    }
}

#Preview {
    SettingsView(
        appearanceMode: .constant(AppearanceMode.system),
        bindings: SettingsBindings(),
        backgroundImage: BackgroundImageStore())
}

#Preview("Dark") {
    SettingsView(
        appearanceMode: .constant(AppearanceMode.dark),
        bindings: SettingsBindings(),
        backgroundImage: BackgroundImageStore())
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

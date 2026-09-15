import SwiftUI

/// Modal settings screen presented from the gear button. Holds the
/// appearance (theme) picker, bound back to the `@AppStorage`-backed property
/// on `ContentView`, the row that pushes the Background subscreen over a
/// staged `SettingsBindings` bag, and the import/export entry points.
struct SettingsView: View {
    @Binding var appearanceMode: AppearanceMode
    @Bindable var bindings: SettingsBindings
    var backgroundImage: BackgroundImageStore
    /// Both defer to `ContentView`, which owns the file panels. Defaulted so
    /// previews and render suites can build the view without wiring them.
    var onExport: () -> Void = {}
    var onImport: () -> Void = {}
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

                Section {
                    Button(action: onExport) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("settingsExportRow")

                    Button(action: onImport) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("settingsImportRow")
                } header: {
                    Text("Import and Export")
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("settingsAboutRow")
                }
            }
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        // iOS 26 wraps bar items in a system glass container.
                        // `fixedSize()` stops it collapsing that container to
                        // a circle that clips the title, so "Done" keeps its
                        // natural width. Deliberately no `checkStitchButton()`:
                        // that modifier drops form-button chrome, but in a bar
                        // the native styling owns the shape.
                        .fixedSize()
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

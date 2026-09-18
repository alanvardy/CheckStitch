import CheckStitchCore
import SwiftUI

/// Modal settings screen presented from the gear button. Holds the Interface
/// row — which pushes the subscreen owning the appearance (theme), language
/// and text-size pickers, still bound back to the `@AppStorage`-backed
/// properties on `ContentView` — the row that pushes the Background subscreen
/// over a staged `SettingsBindings` bag, and the import/export entry points.
struct SettingsView: View {
    @Binding var appearanceMode: AppearanceMode
    @Binding var appLanguage: AppLanguage
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
                    NavigationLink {
                        #if os(iOS)
                            InterfaceSettingsView(
                                appearanceMode: $appearanceMode,
                                appLanguage: $appLanguage,
                                textSize: $bindings.textSize,
                                allowsLandscape: $bindings.allowsLandscape)
                        #else
                            InterfaceSettingsView(
                                appearanceMode: $appearanceMode,
                                appLanguage: $appLanguage,
                                textSize: $bindings.textSize)
                        #endif
                    } label: {
                        Label("Interface", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("settingsInterfaceRow")
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
                    Toggle(isOn: $bindings.prefixReminderNumbers) {
                        Label("Number Reminders", systemImage: "textformat.123")
                    }
                    .accessibilityIdentifier("settingsPrefixNumbersRow")
                } footer: {
                    Text("Prefix each reminder title with its position, like \"1: Buy milk\".")
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
                        PrivacySettingsView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("settingsPrivacyRow")
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
        appLanguage: .constant(.system),
        bindings: SettingsBindings(),
        backgroundImage: BackgroundImageStore())
}

#Preview("Dark") {
    SettingsView(
        appearanceMode: .constant(AppearanceMode.dark),
        appLanguage: .constant(.system),
        bindings: SettingsBindings(),
        backgroundImage: BackgroundImageStore())
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

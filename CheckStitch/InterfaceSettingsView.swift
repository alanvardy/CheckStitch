import SwiftUI

/// Interface preferences: appearance, text size, and (on iOS) the orientation
/// lock. Takes only the bindings it needs rather than the whole settings bag,
/// matching `BackgroundSettingsView`.
struct InterfaceSettingsView: View {
    @Binding var appearanceMode: AppearanceMode

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
        InterfaceSettingsView(appearanceMode: .constant(AppearanceMode.system))
    }
}
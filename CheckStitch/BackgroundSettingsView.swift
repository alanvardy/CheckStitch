import SwiftUI

struct BackgroundSettingsView: View {
    @Binding var backgroundEnabled: Bool
    @Binding var backgroundFadePercent: Int
    @Binding var backgroundPinned: Bool
    var backgroundImage: BackgroundImageStore

    var body: some View {
        Form {
            Toggle(isOn: $backgroundEnabled) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Background")
                        caption("Show a wallpaper behind the checklist.")
                    }
                } icon: {
                    Image(systemName: "photo")
                }
            }
            .accessibilityIdentifier("backgroundToggle")

            Picker(selection: $backgroundFadePercent) {
                ForEach(BackgroundFade.allValues, id: \.self) { percent in
                    Text("\(percent)%").tag(percent)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("Background Fade")
                    caption("How much the wallpaper fades for readability.")
                }
            }
            .accessibilityIdentifier("backgroundFadePicker")

            Section {
                Toggle(isOn: $backgroundPinned) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Pin wallpaper")
                            caption("Prevents the background from refreshing automatically.")
                        }
                    } icon: {
                        Image(systemName: "pin")
                    }
                }
                .accessibilityIdentifier("pinWallpaperToggle")
            }

            Section {
                Button {
                    Task { await backgroundImage.forceRefresh() }
                } label: {
                    HStack {
                        Label("Refresh wallpaper", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if backgroundImage.isRefreshing {
                            ProgressView()
                        }
                    }
                }
                .disabled(backgroundImage.isRefreshing)
                .accessibilityIdentifier("refreshWallpaperButton")
            }

            Section {} footer: {
                if let photographer = backgroundImage.photographer {
                    let credit = "Photo by \(photographer) on Unsplash"
                    if let url = backgroundImage.photographerURL {
                        Link(credit, destination: url)
                    } else {
                        Text(credit)
                    }
                }
            }
        }
        .navigationTitle("Background")
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
        BackgroundSettingsView(
            backgroundEnabled: .constant(true),
            backgroundFadePercent: .constant(BackgroundFade.defaultValue),
            backgroundPinned: .constant(false),
            backgroundImage: BackgroundImageStore())
    }
}

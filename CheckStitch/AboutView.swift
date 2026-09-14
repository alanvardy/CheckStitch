import CheckStitchCore
import SwiftUI

/// Read-only About screen presenting app identity, author attribution, and a
/// feedback mail link. Pushed from Settings' `NavigationStack`, so it owns its
/// own `.navigationTitle` and never re-presents a sheet.
struct AboutView: View {
    init(
        appInfo: AppInfo = AppInfo(),
        feedbackEmail: String = AppInfo.feedbackEmail) {
        self.appInfo = appInfo
        self.feedbackEmail = feedbackEmail
    }

    var body: some View {
        Form {
            Section {
                Label(appInfo.displayName, systemImage: "checklist")
            }
            Section {
                Text("Copyright 2026 Alan Vardy")
                Text("Made with love by a lone developer")
                Text(appInfo.versionDescription)
            }
            Section {} footer: {
                if let feedbackURL = URL(string: "mailto:\(feedbackEmail)") {
                    Link(feedbackEmail, destination: feedbackURL)
                } else {
                    Text(feedbackEmail)
                }
            }
        }
        .navigationTitle("About")
        .settingsSubscreenLayout()
    }

    private let appInfo: AppInfo
    private let feedbackEmail: String
}

#Preview {
    NavigationStack {
        AboutView()
    }
}

import AppIntents

struct CheckStitchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunChecklistIntent(),
            phrases: [
                "Run \(\.$checklist) in \(.applicationName)",
                "Create reminders from \(\.$checklist) in \(.applicationName)",
            ],
            shortTitle: "Run Checklist",
            systemImageName: "checklist")
    }
}

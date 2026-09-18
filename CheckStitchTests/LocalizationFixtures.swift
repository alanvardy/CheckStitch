import Foundation

/// Shared expectations for the localization suites.
enum LocalizationFixtures {
    /// Catalogs guarded by the non-English-differs canary. Watch is included:
    /// all five of its current translations differ from English, so it needs no
    /// exclusion entries, and the canary then catches an English regression there.
    static let guardedCatalogs: Set<String> = ["App", "Core", "Watch"]

    /// Every key each catalog must carry. Guards against a key being dropped
    /// from the catalog (the UI would then render the raw key at runtime).
    static let requiredKeys: [(catalog: String, keys: [String])] = [
        ("App", [
            "%lld days ago",
            "%lld%%",
            "0 means today, 1 means tomorrow, nothing means no date.",
            "About",
            "Add Item",
            "Adjust the size of text throughout the app.",
            "Allow landscape",
            "Another checklist already uses %@ — choose a different name.",
            "Appearance",
            "Background",
            "Background Fade",
            "Cancel",
            "Checklist name",
            "Checklist not found",
            "Choose between system, light, and dark mode.",
            "Copyright 2026 Alan Vardy",
            "Create a checklist to turn its items into reminders.",
            "Create checklist",
            "Create reminders from checklist",
            "Creates a copy with the same items.",
            "Dark",
            "Description",
            "Done",
            "Due date",
            "Duplicate",
            "Duplicate Checklist",
            "Edit",
            "Edit checklist",
            "Edit item",
            "Extra Large",
            "How much the wallpaper fades for readability.",
            "In %lld days",
            "Interface",
            "Item",
            "Item not found",
            "Items",
            "Language",
            "Large",
            "Let the app rotate on iPhone.",
            "Light",
            "Made with ❤️ by a Canadian developer 🇨🇦",
            "Medium",
            "Move down",
            "Move up",
            "Name",
            "Name already in use",
            "No checklists",
            "OK",
            "Photo by %@ on Unsplash",
            "Pin wallpaper",
            "Prevents the background from refreshing automatically.",
            "Refresh wallpaper",
            "Remove",
            "Remove Checklist",
            "Settings",
            "Show a wallpaper behind the checklist.",
            "Small",
            "System",
            "Text Size",
            "This removes the checklist and all its items.",
            "Export",
            "Import",
            "Export Checklists",
            "Select the checklists to include.",
            "Couldn't import",
            "Couldn't export",
            "Name conflict",
            "“%@” already exists.",
            "Replace",
            "Keep Both",
            "Keep Existing",
            "Import and export",
            "Title",
            "Today",
            "Tomorrow",
            "Yesterday",
            "Created %lld reminders for %@.",
            "Created 1 reminder for %@.",
            "That list no longer exists, so no reminders were created for %@.",
            "Open CheckStitch and allow Reminders access, then ask again.",
            "CheckStitch doesn't have permission to access Reminders. Turn it on in Settings, then ask again.",
            "Couldn't create reminders for %@: %@",
            "That checklist no longer exists.",
            "Created %lld of %lld reminders for %@; the rest were not created. %@",
            "You have %lld checklists: %@.",
            "You have 1 checklist: %@.",
            "You don't have any checklists yet.",
            "That list no longer exists, so some reminders may not have been created.",
            "Reminders",
            "Checklists & Sync",
            "Background Image",
            "Privacy Policy",
            "CheckStitch has no analytics, no tracking, and no advertising.",
            "Reminders are created through Apple Reminders and appear in your Reminders inbox. They stay on your device or in your own iCloud account, and are never sent to the author or any third party. CheckStitch never reads, edits, completes, or deletes reminders after creating them.",
            "Your checklists are stored on your device in shared app storage and synced through your own iCloud account. They are never sent to the author or any third party.",
            "When the background is enabled, the wallpaper and artist information are fetched via a proxy at vardy.cc. This is the app's only network traffic, and it never includes any reminder, checklist, or preference data."
        ]),
        ("Core", ["System", "Light", "Dark", "None", "Low", "Medium", "High", "Version %@ (%@)", "Version %@"]),
        ("Watch", [
            "No checklists",
            "Open CheckStitch on your iPhone.",
            "Checklists",
            "Sent",
            "Create reminders",
        ]),
    ]

    /// Per-target `InfoPlist.strings` files and the keys each must carry.
    ///
    /// The watch target carries no reminders usage description: the watch never
    /// touches EventKit (it forwards run requests to the phone via
    /// `WatchChecklistStore`, `CheckStitchCore/.../ChecklistSync.swift:65-95`),
    /// so its generated Info.plist has no such key.
    static let infoPlistTargets: [(name: String, path: String, keys: [String])] = [
        ("App", "CheckStitch", [
            "NSRemindersFullAccessUsageDescription",
            "NSRemindersUsageDescription",
            "CFBundleDisplayName",
        ]),
        ("Watch", "CheckStitchWatch", [
            "CFBundleDisplayName",
        ]),
    ]

    /// Keys whose non-English value may be byte-identical to the English source.
    static let excludedIdentities: Set<ExclusionEntry> = [
        // de "System" — standard German computing term, same spelling as English
        ExclusionEntry(catalog: "App", key: "System"),
        // fr "Description" — same spelling as English
        ExclusionEntry(catalog: "App", key: "Description"),
        ExclusionEntry(catalog: "Core", key: "System"),
        // de "Name" — same spelling as English
        ExclusionEntry(catalog: "App", key: "Name"),
        // "OK" — same in de/es/fr/ja
        ExclusionEntry(catalog: "App", key: "OK"),
        // fr "Interface" — same spelling as English
        ExclusionEntry(catalog: "App", key: "Interface"),
        // percent format string is locale-invariant
        ExclusionEntry(catalog: "App", key: "%lld%%"),
        // de/fr "Version" — same spelling as English
        ExclusionEntry(catalog: "Core", key: "Version %@"),
    ]

    /// Keys that are absent or empty in `plist`. Extracted so the incomplete-plist
    /// sad path is testable without a crashing fixture.
    static func missingInfoPlistKeys(in plist: [String: String], required: [String]) -> [String] {
        required.filter { plist[$0]?.isEmpty != false }
    }
}

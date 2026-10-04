import Foundation

/// Shared expectations for the localization suites.
enum LocalizationFixtures {
    /// Catalogs guarded by the non-English-differs canary. Watch is included:
    /// all five of its current translations differ from English, so it needs no
    /// exclusion entries, and the canary then catches an English regression there.
    static let guardedCatalogs: Set<String> = ["App", "Core", "Watch", "Widget"]

    /// Every key each catalog must carry. Guards against a key being dropped
    /// from the catalog (the UI would then render the raw key at runtime).
    static let requiredKeys: [(catalog: String, keys: [String])] = [
        ("App", [
            "%lld days ago",
            "%lld%%",
            "×%lld",
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
            "Delete",
            "Delete Folder",
            "Description",
            "Done",
            "Due date",
            "Duplicate",
            "Duplicate Checklist",
            "Edit",
            "Edit checklist",
            "Edit item",
            "Extra Large",
            "Folder Name",
            "Hidden checklists stay on your iPhone but are not shown on the Apple Watch.",
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
            "List",
            "Loose",
            "Made with ❤️ by a Canadian developer 🇨🇦",
            "Medium",
            "Move down",
            "Move to Folder",
            "Move up",
            "Name",
            "Name already in use",
            "New Folder",
            "No checklists",
            "Number Reminders",
            "OK",
            "Photo by %@ on Unsplash",
            "Pin wallpaper",
            "Prevents the background from refreshing automatically.",
            "Refresh wallpaper",
            "Remove",
            "Remove Checklist",
            "Remove Folder",
            "Rename Folder",
            "Settings",
            "Show a wallpaper behind the checklist.",
            "Show on watch",
            "Scaling",
            "Scale item markers by this factor when creating reminders.",
            "Small",
            "System",
            "Text Size",
            "This removes the checklist and all its items.",
            "This removes the folder. Its checklists become loose.",
            "Export",
            "Import",
            "Import and Export",
            "Import Checklists",
            "Export Checklists",
            "Select the checklists to include.",
            "A checklist with this name exists",
            "Couldn't import",
            "Couldn't export",
            "Name conflict",
            "“%@” already exists.",
            "Replace",
            "Keep Both",
            "Keep Existing",
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
            "When the background is enabled, the wallpaper and artist information are fetched via a proxy at vardy.cc. This request never includes any reminder, checklist, or preference data.",
            "Crash Reports",
            "When crash reporting is enabled, CheckStitch sends crash and diagnostic information to Sentry, our crash-reporting provider. This data is processed in the United States and never includes any checklist, item, reminder, or preference content. You can turn crash reporting off at any time in Settings.",
            "Buy",
            "Not now",
            "Unlock CheckStitch",
            "Manage Purchase",
            "You're all set! 🎉",
            "Thank you for your support! You can run as many checklists as you like.",
            "A one-time purchase unlocks unlimited checklist runs forever.",
            "If you've already purchased CheckStitch on another device, restore it here.",
            "Loading…",
            "You've reached the CheckStitch free limit. Open CheckStitch to buy a license.",
            "You've run %lld checklists. Buy once to keep creating reminders.",
            "Purchasing…",
            "Restore Purchases",
            "Couldn't load the store. Check your connection and try again.",
            "Try Again"
        ]),
        ("Core", ["System", "Light", "Dark", "None", "Low", "Medium", "High", "Version %@ (%@)", "Version %@", "Multiple must be between 1 and 99."]),
        ("Watch", [
            "No checklists",
            "Open CheckStitch on your iPhone.",
            "Checklists",
            "Sent",
            "Create reminders",
        ]),
        ("Widget", [
            "CheckStitch Checklist",
            "CheckStitch Checklists",
            "Run a checklist without opening the app.",
            "Run any of your checklists without opening the app.",
            "Checklist",
            "Checklists",
            "Pick the checklist this widget runs.",
            "Pick the checklists this widget runs.",
            "Create reminders",
            "Open CheckStitch to enable",
            "Open CheckStitch to buy a license",
            "No checklists",
            "Edit this widget to pick a checklist",
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
        // percent format strings are locale-invariant
        ExclusionEntry(catalog: "App", key: "%lld%%"),
        ExclusionEntry(catalog: "App", key: "×%lld"),
        // de/fr "Version" — same spelling as English
        ExclusionEntry(catalog: "Core", key: "Version %@"),
    ]

    /// Keys that are absent or empty in `plist`. Extracted so the incomplete-plist
    /// sad path is testable without a crashing fixture.
    static func missingInfoPlistKeys(in plist: [String: String], required: [String]) -> [String] {
        required.filter { plist[$0]?.isEmpty != false }
    }
}

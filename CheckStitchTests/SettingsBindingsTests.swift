import Foundation
@testable import CheckStitch
import Testing

@MainActor
@Suite(.serialized)
struct SettingsBindingsTests {
    @Test
    func defaultsMatchPreferenceDefaults() {
        let bag = SettingsBindings()
        #expect(bag.backgroundEnabled)
        #expect(bag.backgroundFadePercent == BackgroundFade.defaultValue)
        #expect(!bag.backgroundPinned)
        #expect(bag.textSize == .system)
        #expect(bag.allowsLandscape)
    }

    @Test
    func stagedMutationDoesNotTouchUserDefaults() {
        let original = UserDefaults.standard.object(forKey: "backgroundEnabled")
        defer { UserDefaults.standard.set(original, forKey: "backgroundEnabled") }

        let bag = SettingsBindings()
        bag.backgroundEnabled = false
        bag.backgroundFadePercent = 80
        bag.backgroundPinned = true

        #expect(UserDefaults.standard.object(forKey: "backgroundEnabled") as? Bool != false)
    }

    @Test
    func snapshotReadsCurrentUserDefaults() {
        UserDefaults.standard.set(false, forKey: "backgroundEnabled")
        UserDefaults.standard.set(70, forKey: "backgroundFadePercent")
        UserDefaults.standard.set(true, forKey: "backgroundPinned")
        UserDefaults.standard.set("large", forKey: "textSize")
        UserDefaults.standard.set(false, forKey: "allowsLandscape")
        defer { Self.clearPreferences() }

        let snapshot = ContentView().settingsSnapshot()

        #expect(!snapshot.backgroundEnabled)
        #expect(snapshot.backgroundFadePercent == 70)
        #expect(snapshot.backgroundPinned)
        #expect(snapshot.textSize == .large)
        #expect(!snapshot.allowsLandscape)
    }

    @Test
    func writeBackPersistsEachKey() {
        defer { Self.clearPreferences() }
        let bag = SettingsBindings(
            backgroundEnabled: false,
            backgroundFadePercent: 70,
            backgroundPinned: true,
            textSize: .extraLarge,
            allowsLandscape: false)

        // The view owns the `@AppStorage` bridge; the VM owns the writeback
        // projection, so the two meet here exactly as they do in the app.
        ContentView().applySettings(SettingsViewModel().writeBack(bag))

        #expect(UserDefaults.standard.bool(forKey: "backgroundEnabled") == false)
        #expect(UserDefaults.standard.integer(forKey: "backgroundFadePercent") == 70)
        #expect(UserDefaults.standard.bool(forKey: "backgroundPinned") == true)
        #expect(UserDefaults.standard.string(forKey: "textSize") == "extraLarge")
        #expect(UserDefaults.standard.bool(forKey: "allowsLandscape") == false)
    }

    private static func clearPreferences() {
        for key in ["backgroundEnabled", "backgroundFadePercent", "backgroundPinned", "textSize", "allowsLandscape"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

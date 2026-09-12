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
        defer { Self.clearPreferences() }

        let view = ContentView()
        let bag = view.makeSettingsBag()

        #expect(!bag.backgroundEnabled)
        #expect(bag.backgroundFadePercent == 70)
        #expect(bag.backgroundPinned)
    }

    @Test
    func writeBackPersistsEachKey() {
        defer { Self.clearPreferences() }
        let view = ContentView()
        let bag = SettingsBindings(
            backgroundEnabled: false,
            backgroundFadePercent: 70,
            backgroundPinned: true)

        view.writeBack(bag)

        #expect(UserDefaults.standard.bool(forKey: "backgroundEnabled") == false)
        #expect(UserDefaults.standard.integer(forKey: "backgroundFadePercent") == 70)
        #expect(UserDefaults.standard.bool(forKey: "backgroundPinned") == true)
    }

    private static func clearPreferences() {
        for key in ["backgroundEnabled", "backgroundFadePercent", "backgroundPinned"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
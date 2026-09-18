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

        let view = ContentView()
        let bag = view.makeSettingsBag()

        #expect(!bag.backgroundEnabled)
        #expect(bag.backgroundFadePercent == 70)
        #expect(bag.backgroundPinned)
        #expect(bag.textSize == .large)
        #expect(!bag.allowsLandscape)
    }

    @Test
    func writeBackPersistsEachKey() {
        defer { Self.clearPreferences() }
        let view = ContentView()
        let bag = SettingsBindings(
            backgroundEnabled: false,
            backgroundFadePercent: 70,
            backgroundPinned: true,
            textSize: .extraLarge,
            allowsLandscape: false)

        view.writeBack(bag)

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
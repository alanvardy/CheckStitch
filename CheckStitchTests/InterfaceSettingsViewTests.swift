@testable import CheckStitch
import SwiftUI
import Testing

/// The Interface subscreen renders its controls and stays compilable on both
/// platforms (`settingsSubscreenLayout()` is the macOS-only canary).
@MainActor
struct InterfaceSettingsViewTests {
    @Test
    func interfaceSubscreenRendersAppearance() {
        let view = InterfaceSettingsView(appearanceMode: .constant(AppearanceMode.system))
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("Appearance"))
        #expect(bodyDescription.contains("Choose between system, light, and dark mode."))
        #if os(macOS)
            #expect(bodyDescription.contains("SettingsSubscreenLayout"))
        #endif
    }

    @Test
    func interfaceSubscreenRendersAtAllAppearanceModes() {
        for mode in CheckStitch.AppearanceMode.allCases {
            let view = InterfaceSettingsView(appearanceMode: .constant(mode))
            #expect(!String(describing: view.body).isEmpty)
        }
    }
}
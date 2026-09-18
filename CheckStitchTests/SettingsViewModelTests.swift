@testable import CheckStitch
import Testing

@MainActor
struct SettingsViewModelTests {
    @Test
    func beginStagesTheSnapshotAndPresents() {
        let viewModel = SettingsViewModel()
        let bag = viewModel.begin(from: SettingsSnapshot(
            backgroundEnabled: false,
            backgroundFadePercent: 70,
            backgroundPinned: true,
            textSize: .extraLarge,
            allowsLandscape: false))

        #expect(viewModel.showsSettings)
        #expect(viewModel.bag === bag)
        #expect(bag.backgroundEnabled == false)
        #expect(bag.backgroundFadePercent == 70)
        #expect(bag.backgroundPinned)
        #expect(bag.textSize == .extraLarge)
        #expect(bag.allowsLandscape == false)
    }

    @Test
    func writeBackYieldsTheStagedValues() {
        let viewModel = SettingsViewModel()
        let bag = SettingsBindings(
            backgroundEnabled: false, backgroundFadePercent: 10,
            backgroundPinned: true, textSize: .large, allowsLandscape: false)

        let writeback = viewModel.writeBack(bag)

        #expect(writeback == SettingsWriteback(
            backgroundEnabled: false, backgroundFadePercent: 10,
            backgroundPinned: true, textSize: .large, allowsLandscape: false))
    }

    @Test
    func stagedActionIsTakenExactlyOnce() {
        let viewModel = SettingsViewModel()
        viewModel.begin(from: SettingsSnapshot(
            backgroundEnabled: true, backgroundFadePercent: 50,
            backgroundPinned: false, textSize: .system, allowsLandscape: true))

        viewModel.stage(.export)

        #expect(!viewModel.showsSettings)
        #expect(viewModel.takeStaged() == .export)
        #expect(viewModel.takeStaged() == nil, "a dismissal replay must not open a second panel")
    }

    @Test
    func sheetDidDismissClearsTheBag() {
        let viewModel = SettingsViewModel()
        _ = viewModel.begin(from: SettingsSnapshot(
            backgroundEnabled: true, backgroundFadePercent: 50,
            backgroundPinned: false, textSize: .system, allowsLandscape: true))

        viewModel.sheetDidDismiss()

        #expect(viewModel.bag == nil)
    }
}
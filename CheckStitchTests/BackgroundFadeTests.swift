@testable import CheckStitch
import Testing

// MARK: - Background Fade Tests

@MainActor
struct BackgroundFadeTests {
    @Test
    func defaultIsFiftyPercent() {
        #expect(BackgroundFade.defaultValue == 50)
    }

    @Test
    func allValuesAscendInTenPercentStepsUpToNinety() {
        #expect(BackgroundFade.allValues == [0, 10, 20, 30, 40, 50, 60, 70, 80, 90])
    }

    @Test
    func opacityInvertsFadePercent() {
        #expect(BackgroundFade.opacity(for: 0) == 1)
        #expect(abs(BackgroundFade.opacity(for: 50) - 0.5) < 0.000_1)
        #expect(abs(BackgroundFade.opacity(for: 90) - 0.1) < 0.000_1)
    }

    @Test
    func opacityClampsOutOfRangePersistedValues() {
        #expect(BackgroundFade.opacity(for: -30) == 1)
        #expect(abs(BackgroundFade.opacity(for: 130) - 0.1) < 0.000_1)
    }
}

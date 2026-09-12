import Foundation
@testable import CheckStitch
import Testing

// MARK: - BackgroundPhotoLayer Tests

@MainActor
struct BackgroundPhotoLayerTests {
    @Test
    func imageFromValidJPEGDataIsNonNil() {
        #expect(BackgroundPhotoLayer.image(from: BackgroundTestFixtures.jpegData) != nil)
    }

    @Test
    func imageFromInvalidDataIsNil() {
        #expect(BackgroundPhotoLayer.image(from: Data("not an image".utf8)) == nil)
    }

    @Test
    func constructsWithValidAndNilData() {
        let valid = BackgroundPhotoLayer(
            imageData: BackgroundTestFixtures.jpegData,
            isEnabled: true,
            opacity: 1)
        #expect(valid.isEnabled)
        #expect(valid.imageData == BackgroundTestFixtures.jpegData)

        let nilData = BackgroundPhotoLayer(imageData: nil)
        #expect(nilData.imageData == nil)

        let disabled = BackgroundPhotoLayer(
            imageData: BackgroundTestFixtures.jpegData,
            isEnabled: false,
            opacity: BackgroundFade.opacity(for: BackgroundFade.defaultValue))
        #expect(!disabled.isEnabled)
    }
}

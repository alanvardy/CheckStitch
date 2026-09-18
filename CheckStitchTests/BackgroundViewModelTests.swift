@testable import CheckStitch
import Foundation
import Testing

@MainActor
struct BackgroundViewModelTests {
    private static let endpoint = URL(string: "https://vardy.cc/unsplash")!
    private static let imageURL = URL(string: "https://images.unsplash.com/photo-1.jpg")!

    private func makeViewModel(pinned: Bool) -> (BackgroundViewModel, URL) {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = BackgroundImageStore(client: fake, directory: directory)
        return (BackgroundViewModel(image: store), directory)
    }

    private func payloadJSON() -> Data {
        Data(("{\"url\":\"\(Self.imageURL.absoluteString)\",\"photographer\":\"NEOM\","
            + "\"photographer_url\":\"https://unsplash.com/@neom\",\"created_at\":\"2026-01-01\"}").utf8)
    }

    @Test
    func taskPinsThenRefreshes() async {
        let (viewModel, _) = makeViewModel(pinned: true)

        await viewModel.task(pinned: true)

        #expect(viewModel.image.isPinned)
        #expect(viewModel.image.imageData != nil, "a pinned blank store still fetches its first photo")
    }

    @Test
    func setPinnedForwards() async {
        let (viewModel, _) = makeViewModel(pinned: false)

        await viewModel.setPinned(true)
        #expect(viewModel.image.isPinned)

        await viewModel.setPinned(false)
        #expect(!viewModel.image.isPinned)
    }
}

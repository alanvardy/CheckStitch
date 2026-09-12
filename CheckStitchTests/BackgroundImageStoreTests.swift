import Foundation
@testable import CheckStitch
import Testing

// MARK: - BackgroundImageStore Tests

@MainActor
@Suite(.serialized)
struct BackgroundImageStoreTests {
    // MARK: Internal

    @Test
    func successfulFetchStoresBytesAndMetadata() async throws {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let (store, _) = makeStore(client: fake)

        await store.refreshIfNeeded(maxAge: 3600)

        #expect(store.imageData == BackgroundTestFixtures.jpegData)
        #expect(store.photographer == "NEOM")
        #expect(store.photographerURL?.absoluteString == "https://unsplash.com/@neom")
        let savedImage = try Data(contentsOf: store.imageURL)
        #expect(savedImage == BackgroundTestFixtures.jpegData)
        let savedMetadata = try Data(contentsOf: store.metadataURL)
        #expect(!savedMetadata.isEmpty)
        #expect(String(bytes: savedMetadata, encoding: .utf8)?.contains("NEOM") == true)
    }

    @Test
    func nonImagePayloadRejected() async {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(Data("not an image".utf8))
        let (store, _) = makeStore(client: fake)

        await store.refreshIfNeeded(maxAge: 3600)

        #expect(store.imageData == nil)
        #expect(store.photographer == nil)
        #expect(!FileManager.default.fileExists(atPath: store.imageURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.metadataURL.path))
    }

    @Test
    func failedFetchRetainsPriorImage() async {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded(maxAge: 3600)

        struct StubError: Error {}
        fake.stubbedData[Self.imageURL] = .failure(StubError())
        await store.refreshIfNeeded(maxAge: 3600)

        #expect(store.imageData == BackgroundTestFixtures.jpegData)
        #expect(store.photographer == "NEOM")
        #expect(store.photographerURL?.absoluteString == "https://unsplash.com/@neom")
    }

    @Test
    func staleSidecarTriggersRefetchWith24hDefault() async throws {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded()

        // 23h-old sidecar is still within the 24h default → skip.
        try sidecarJSON(fetchedAt: Date().addingTimeInterval(-23 * 3600))
            .write(to: store.metadataURL, options: .atomic)
        await store.refreshIfNeeded()
        let endpointCountWithinDay = fake.requestedURLs.filter { $0 == Self.endpoint }.count

        // 25h-old sidecar is beyond the 24h default → refetch.
        try sidecarJSON(fetchedAt: Date().addingTimeInterval(-25 * 3600))
            .write(to: store.metadataURL, options: .atomic)
        await store.refreshIfNeeded()
        let endpointCountBeyondDay = fake.requestedURLs.filter { $0 == Self.endpoint }.count

        #expect(
            endpointCountBeyondDay > endpointCountWithinDay,
            "only the 25h-old sidecar should trigger a refetch")
    }

    @Test
    func freshSidecarSkipsNetworkWith24hDefault() async {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded()
        #expect(fake.requestedURLs.count == 2)

        await store.refreshIfNeeded()

        #expect(fake.requestedURLs.count == 2, "Fresh sidecar should not trigger refetch")
    }

    @Test
    func corruptOrMissingSidecarTreatedAsNoImage() async throws {
        // Write background.jpg only — no sidecar.
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let (store, directory) = makeStore(client: fake)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try BackgroundTestFixtures.jpegData.write(to: store.imageURL)

        await store.refreshIfNeeded(maxAge: 3600)

        // Sidecar missing ⇒ stored image is discarded and a network fetch runs;
        // here the fetch succeeds so state reflects the fresh payload.
        #expect(store.imageData == BackgroundTestFixtures.jpegData)
        #expect(store.photographer == "NEOM")
        #expect(store.photographerURL?.absoluteString == "https://unsplash.com/@neom")

        // And with the fetch failing, no image surfaces from an orphaned jpg.
        struct StubError: Error {}
        let failingFake = FakeBackgroundFetcher()
        failingFake.stubbedData[Self.endpoint] = .failure(StubError())
        let orphanDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let orphanStore = BackgroundImageStore(client: failingFake, directory: orphanDirectory)
        try FileManager.default.createDirectory(
            at: orphanDirectory, withIntermediateDirectories: true)
        try BackgroundTestFixtures.jpegData.write(to: orphanStore.imageURL)
        await orphanStore.refreshIfNeeded(maxAge: 3600)
        #expect(orphanStore.imageData == nil)
        #expect(orphanStore.photographer == nil)
    }

    /// Pairing invariant: the photographer and URL surfaced to the attribution footer
    /// always come from the same sidecar write as the displayed photo bytes.
    @Test
    func photographerURLMatchesStoredPhotoAfterFetch() async throws {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let (store, _) = makeStore(client: fake)

        await store.refreshIfNeeded(maxAge: 3600)

        let metadataData = try Data(contentsOf: store.metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct SidecarMetadata: Codable {
            let photographer: String
            let photographerURL: String?
            let fetchedAt: Date
        }
        let sidecar = try decoder.decode(SidecarMetadata.self, from: metadataData)
        #expect(sidecar.photographer == store.photographer)
        #expect(sidecar.photographerURL == store.photographerURL?.absoluteString)
    }

    @Test
    func photographerClearedWithoutValidSidecar() async throws {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded(maxAge: 3600)
        #expect(store.photographer != nil)

        // Corrupt the sidecar, then fail the next fetch: state must fall back
        // to "no photo" so the footer renders empty rather than a stale credit.
        try Data("corrupt".utf8).write(to: store.metadataURL, options: .atomic)
        struct StubError: Error {}
        fake.stubbedData[Self.imageURL] = .failure(StubError())
        await store.refreshIfNeeded(maxAge: 3600)

        #expect(store.photographer == nil)
    }

    @Test
    func forceRefreshBypassesFreshSidecar() async {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.randomEndpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded() // seeds a fresh sidecar + photo
        let countAfterInitial = fake.requestedURLs.count
        #expect(countAfterInitial == 2)

        await store.forceRefresh()

        #expect(
            fake.requestedURLs.count > countAfterInitial,
            "forceRefresh should hit the network even with a fresh sidecar")
    }

    @Test
    func forceRefreshRetainsPriorImageOnFailure() async {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.randomEndpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded()

        struct StubError: Error {}
        fake.stubbedData[Self.imageURL] = .failure(StubError())
        await store.forceRefresh()

        #expect(store.imageData == BackgroundTestFixtures.jpegData)
        #expect(store.photographer == "NEOM")
        #expect(store.photographerURL?.absoluteString == "https://unsplash.com/@neom")
        #expect(!store.isRefreshing, "failure path must reset isRefreshing")
    }

    @Test
    func forceRefreshUpdatesAttributionAfterSuccess() async {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded()
        #expect(store.photographer == "NEOM")

        fake.stubbedData[Self.randomEndpoint] = .success(Data(
            ("{\"url\":\"\(Self.imageURL.absoluteString)\",\"photographer\":\"Adele\"," +
                "\"photographer_url\":\"https://unsplash.com/@adele\"}").utf8))
        await store.forceRefresh()

        #expect(store.photographer == "Adele")
        #expect(store.photographerURL?.absoluteString == "https://unsplash.com/@adele")
        #expect(store.imageData == BackgroundTestFixtures.jpegData)
    }

    @Test
    func isRefreshingToggledDuringForceRefresh() async {
        let fetcher = GatedBackgroundFetcher(endpointURL: Self.randomEndpoint)
        fetcher.endpointData = payloadJSON()
        fetcher.imageData = BackgroundTestFixtures.jpegData
        let store = BackgroundImageStore(
            client: fetcher,
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString))

        let task = Task { await store.forceRefresh() }
        await fetcher.gate.waitUntilHit()
        #expect(store.isRefreshing)
        await fetcher.gate.open()
        await task.value
        #expect(!store.isRefreshing)
    }

    // MARK: - Pin gating

    @Test
    func pinBlocksRefreshIfNeeded() async throws {
        let fake = FakeBackgroundFetcher()
        let (store, directory) = makeStore(client: fake)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        // Seed a stale sidecar so refreshIfNeeded would normally fetch.
        let staleDate = Date().addingTimeInterval(-25 * 3600)
        try sidecarJSON(fetchedAt: staleDate)
            .write(to: store.metadataURL, options: .atomic)
        try BackgroundTestFixtures.jpegData
            .write(to: store.imageURL, options: .atomic)
        store.loadStoredImage()

        // Stub the endpoint to confirm it is NOT called.
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)

        await store.setPinned(true)
        await store.refreshIfNeeded()

        #expect(
            fake.requestedURLs.isEmpty,
            "Pinned store should skip network on refreshIfNeeded")
        #expect(store.imageData == BackgroundTestFixtures.jpegData)
        #expect(store.photographer == "Old")
    }

    @Test
    func pinnedStoreWithNoImageStillFetches() async {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let (store, _) = makeStore(client: fake)

        await store.setPinned(true)
        #expect(store.imageData == nil)
        await store.refreshIfNeeded(maxAge: 3600)

        #expect(store.imageData == BackgroundTestFixtures.jpegData)
        #expect(store.photographer == "NEOM")
        #expect(
            fake.requestedURLs.contains(Self.endpoint),
            "A pinned store with no stored image should still fetch")
    }

    @Test
    func repinDuringFetchDoesNotCommit() async throws {
        let fetcher = GatedBackgroundFetcher(endpointURL: Self.endpoint)
        fetcher.endpointData = payloadJSON()
        fetcher.imageData = BackgroundTestFixtures.jpegData
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = BackgroundImageStore(client: fetcher, directory: directory)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        // Seed a stale sidecar so the unpin-triggered refresh actually fetches.
        let staleDate = Date().addingTimeInterval(-25 * 3600)
        try sidecarJSON(fetchedAt: staleDate)
            .write(to: store.metadataURL, options: .atomic)
        try BackgroundTestFixtures.jpegData
            .write(to: store.imageURL, options: .atomic)
        store.loadStoredImage()
        #expect(store.photographer == "Old")

        // Pin, then unpin; the unpin fetch is parked at the gate.
        await store.setPinned(true)
        let unpinTask = Task { await store.setPinned(false) }
        await fetcher.gate.waitUntilHit()

        // Re-pin while the fetch is suspended: the commit must be dropped.
        await store.setPinned(true)
        await fetcher.gate.open()
        await unpinTask.value

        #expect(store.isPinned)
        #expect(
            store.photographer == "Old",
            "re-pinning during a fetch must not commit the new photo")
        #expect(store.imageData == BackgroundTestFixtures.jpegData)
    }

    @Test
    func forceRefreshBypassesPin() async {
        let fake = FakeBackgroundFetcher()
        let (store, _) = makeStore(client: fake)

        fake.stubbedData[Self.randomEndpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)

        await store.setPinned(true)
        await store.forceRefresh()

        #expect(
            fake.requestedURLs.contains(Self.randomEndpoint),
            "forceRefresh should fetch randomEndpoint even when pinned")
    }

    @Test
    func unpinTriggersRefreshWhenStale() async throws {
        let fake = FakeBackgroundFetcher()
        let (store, directory) = makeStore(client: fake)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        // Seed a stale sidecar.
        let staleDate = Date().addingTimeInterval(-25 * 3600)
        try sidecarJSON(fetchedAt: staleDate)
            .write(to: store.metadataURL, options: .atomic)
        try BackgroundTestFixtures.jpegData
            .write(to: store.imageURL, options: .atomic)
        store.loadStoredImage()

        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)

        // Pin, then unpin.
        await store.setPinned(true)
        #expect(store.isPinned)
        await store.setPinned(false)

        #expect(!store.isPinned)
        #expect(
            fake.requestedURLs.contains(Self.endpoint),
            "Unpinning a stale store should trigger refreshIfNeeded")
    }

    @Test
    func unpinDoesNotRefreshWhenFresh() async throws {
        let fake = FakeBackgroundFetcher()
        let (store, directory) = makeStore(client: fake)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        // Seed a fresh sidecar.
        let freshDate = Date().addingTimeInterval(-1 * 3600)
        try sidecarJSON(fetchedAt: freshDate)
            .write(to: store.metadataURL, options: .atomic)
        try BackgroundTestFixtures.jpegData
            .write(to: store.imageURL, options: .atomic)
        store.loadStoredImage()

        // Stub to confirm endpoint is NOT called.
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)

        await store.setPinned(true)
        await store.setPinned(false)

        #expect(
            fake.requestedURLs.isEmpty,
            "Unpinning a fresh store should not trigger a fetch")
    }

    @Test
    func unpinOnlyTriggersOnTrueToFalseTransition() async throws {
        let fake = FakeBackgroundFetcher()
        let (store, directory) = makeStore(client: fake)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        // Seed a stale sidecar.
        let staleDate = Date().addingTimeInterval(-25 * 3600)
        try sidecarJSON(fetchedAt: staleDate)
            .write(to: store.metadataURL, options: .atomic)
        try BackgroundTestFixtures.jpegData
            .write(to: store.imageURL, options: .atomic)
        store.loadStoredImage()

        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)

        // Already unpinned (default) — calling setPinned(false) should be a no-op.
        await store.setPinned(false)

        #expect(
            fake.requestedURLs.isEmpty,
            "setPinned(false) on already-unpinned store should not fetch")
    }

    // MARK: Private

    private static let endpoint = URL(string: "https://vardy.cc/unsplash")!
    private static let randomEndpoint = URL(string: "https://vardy.cc/unsplash/random")!
    private static let imageURL = URL(string: "https://images.unsplash.com/photo-1.jpg")!

    private func makeStore(
        client: FakeBackgroundFetcher) -> (BackgroundImageStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return (BackgroundImageStore(client: client, directory: directory), directory)
    }

    /// Builds a realistic `GET /unsplash` JSON payload pointing at the image URL
    /// and including the photographer_url attribution link.
    private func payloadJSON() -> Data {
        let json = "{\"url\":\"\(Self.imageURL.absoluteString)\",\"photographer\":\"NEOM\"," +
            "\"photographer_url\":\"https://unsplash.com/@neom\",\"created_at\":\"2026-01-01\"}"
        return Data(json.utf8)
    }

    /// Builds a minimal sidecar JSON with a `fetchedAt` relative to now.
    private func sidecarJSON(fetchedAt: Date) -> Data {
        let dateString = ISO8601DateFormatter().string(from: fetchedAt)
        return Data("{\"photographer\":\"Old\",\"fetchedAt\":\"\(dateString)\"}".utf8)
    }
}

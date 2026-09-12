import Foundation
@testable import CheckStitch

/// Shared test constants for background-image tests.
/// The JPEG blob is the smallest valid 1×1 pixel image, used by any test that
/// must pass the store's `isDecodableImage` gate without a real network call.
enum BackgroundTestFixtures {
    /// Smallest valid JPEG (1×1 pixel), used to pass the store's decodability gate.
    static let jpegData = Data(
        base64Encoded: "/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEA"
            + "AKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAA"
            + "ABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAAQABAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkK"
            + "C//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYn"
            + "KCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqy"
            + "s7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAAB"
            + "AgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoW"
            + "JDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZ"
            + "mqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwIC"
            + "AwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQE"
            + "BxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQAC"
            + "EQMRAD8A+L6KKK/lM/38P//Z")!
}

// MARK: - Background-fetcher fakes

final class FakeBackgroundFetcher: BackgroundImageFetching, @unchecked Sendable {
    private(set) var requestedURLs: [URL] = []
    var stubbedData: [URL: Result<Data, Error>] = [:]

    func fetchData(from url: URL) async throws -> Data {
        requestedURLs.append(url)
        return try stubbedData[url]!.get()
    }
}

/// One-shot rendezvous that parks a fetch in-flight so a test can observe
/// `isRefreshing` before releasing it.
actor FetchGate {
    // MARK: Internal

    func wait() async {
        if wasHit {
            return
        }
        wasHit = true
        hitSignal?.resume()
        await withCheckedContinuation { parked = $0 }
    }

    func waitUntilHit() async {
        if wasHit {
            return
        }
        await withCheckedContinuation { hitSignal = $0 }
    }

    func open() {
        parked?.resume()
        parked = nil
    }

    // MARK: Private

    private var parked: CheckedContinuation<Void, Never>?
    private var hitSignal: CheckedContinuation<Void, Never>?
    private var wasHit = false
}

/// Parks the first (endpoint) fetch behind a gate, then serves valid data.
final class GatedBackgroundFetcher: BackgroundImageFetching, @unchecked Sendable {
    // MARK: Lifecycle

    init(endpointURL: URL) {
        self.endpointURL = endpointURL
    }

    // MARK: Internal

    let gate = FetchGate()
    var endpointData: Data = .init()
    var imageData: Data = .init()

    func fetchData(from url: URL) async throws -> Data {
        let isEndpoint = url == endpointURL
        if isEndpoint {
            await gate.wait()
        }
        return isEndpoint ? endpointData : imageData
    }

    // MARK: Private

    private let endpointURL: URL
}

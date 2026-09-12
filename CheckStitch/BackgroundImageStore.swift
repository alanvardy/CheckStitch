import Foundation
import SwiftUI
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif
import OSLog

/// Abstraction over the network transport so unit tests can inject a fake.
/// Named `fetchData` (not `data`) so the URLSession conformance below can wrap
/// the built-in `data(from:)` with HTTP-status validation — URLSession's own
/// async `data(from:)` does NOT throw on non-2xx responses.
protocol BackgroundImageFetching: AnyObject {
    func fetchData(from url: URL) async throws -> Data
}

extension URLSession: BackgroundImageFetching {
    func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Sidecar metadata persisted next to the photo bytes. One write covers both
/// the displayed photo and the attribution credit, so they can never disagree.
private struct BackgroundMetadata: Codable {
    let photographer: String
    let photographerURL: String?
    let fetchedAt: Date
}

/// Shape of the `GET https://vardy.cc/unsplash` JSON payload (`created_at` ignored).
private struct UnsplashPayload: Decodable {
    enum CodingKeys: String, CodingKey {
        case url
        case photographer
        case photographerURL = "photographer_url"
    }

    let url: URL
    let photographer: String
    let photographerURL: URL?
}

/// Fetches, persists, and serves the background photograph.
/// Phone-local cosmetic concern: never touches the App Group or sync payloads.
@MainActor
@Observable
final class BackgroundImageStore {
    // MARK: Lifecycle

    /// - Parameters:
    ///   - client: network transport; production default is `URLSession.shared`.
    ///   - directory: persistence location; tests inject a UUID temp directory.
    init(client: any BackgroundImageFetching = URLSession.shared, directory: URL? = nil) {
        self.client = client
        self.directory = directory ?? Self.defaultDirectory
    }

    // MARK: Internal

    /// Bytes of the currently-displayed photo, or nil before first success.
    private(set) var imageData: Data?
    /// Photographer of the currently-displayed photo, or nil.
    private(set) var photographer: String?
    /// Unsplash attribution URL for the currently-displayed photo, or nil.
    private(set) var photographerURL: URL?
    /// `true` while an explicit force-refresh is in-flight; drives the button's
    /// `ProgressView` and disables it to prevent double-fetch.
    private(set) var isRefreshing = false

    /// When true, `refreshIfNeeded` treats the wallpaper as perpetually fresh.
    /// Manual `forceRefresh` is unaffected. Set by the view layer from the
    /// `@AppStorage("backgroundPinned")` preference.
    private(set) var isPinned = false

    var imageURL: URL {
        directory.appendingPathComponent("background.jpg")
    }

    var metadataURL: URL {
        directory.appendingPathComponent("background.json")
    }

    /// Loads stored bytes into observable state, then refetches over the
    /// network when the sidecar is missing/corrupt/stale. Called from
    /// ContentView's `.task`; rendering is never gated on the network result.
    /// A pinned store skips the refetch — except when no image is stored yet,
    /// so pinning a blank state never blocks the first photo from loading.
    /// Failure convention: persist to disk FIRST, then flip observable state;
    /// on any error, log and keep prior state.
    func refreshIfNeeded(maxAge: TimeInterval = BackgroundImageStore.defaultMaxAge) async {
        loadStoredImage()
        guard !isPinned || imageData == nil else { return }
        guard !isFresh(maxAge: maxAge) else { return }
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let wallpaper = try await fetchWallpaper(from: Self.endpoint)
            // Re-check after the network suspension: a re-pin while the fetch was
            // in flight must not commit a new photo over the pinned one.
            guard !isPinned || imageData == nil else { return }
            try commit(wallpaper)
        } catch {
            Self.logger.error("Background refresh failed: \(error.localizedDescription)")
        }
    }

    /// Fetches a fresh wallpaper immediately, ignoring the staleness check.
    /// Unlike `refreshIfNeeded`, which consults the cached `GET /unsplash`,
    /// this hits `GET /unsplash/random` so each explicit refresh can surface a
    /// different photo. Always hits the network and toggles `isRefreshing` so
    /// the button can show progress. On any error it keeps the prior photo and
    /// attribution.
    func forceRefresh() async {
        guard !isRefreshing, !isFetching else { return }
        isRefreshing = true
        isFetching = true
        defer {
            isRefreshing = false
            isFetching = false
        }
        do {
            let wallpaper = try await fetchWallpaper(from: Self.randomEndpoint)
            try commit(wallpaper)
        } catch {
            Self.logger.error("Background force refresh failed: \(error.localizedDescription)")
        }
    }

    /// Updates the pin state. When transitioning from pinned → unpinned,
    /// immediately checks freshness and refetches if the photo is stale.
    func setPinned(_ pinned: Bool) async {
        let wasPinned = isPinned
        isPinned = pinned
        if !pinned, wasPinned {
            await refreshIfNeeded()
        }
    }

    /// Missing/corrupt sidecar ⇒ treated as "no valid stored image".
    func loadStoredImage() {
        guard let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? decodeMetadata(from: metadataData),
              let data = try? Data(contentsOf: imageURL),
              isDecodableImage(data)
        else {
            imageData = nil
            photographer = nil
            photographerURL = nil
            return
        }
        imageData = data
        photographer = metadata.photographer
        photographerURL = metadata.photographerURL.flatMap(URL.init)
    }

    // MARK: Private

    /// A decoded, validated wallpaper ready to persist. Purely a value — no
    /// observable state — so callers can re-check pin state after the fetch.
    private struct FetchedWallpaper {
        let data: Data
        let photographer: String
        let photographerURL: URL?
    }

    /// A stored wallpaper is considered fresh for 24 hours before the network
    /// is consulted again.
    private static let defaultMaxAge: TimeInterval = 86400

    /// `GET /unsplash` — the 6h-cached wallpaper used on cold launch.
    private static let endpoint = URL(string: "https://vardy.cc/unsplash")!
    /// `GET /unsplash/random` — a random photo from the server's pool, served
    /// by the explicit "Refresh wallpaper" action.
    private static let randomEndpoint = URL(string: "https://vardy.cc/unsplash/random")!
    private static let logger = Logger(
        subsystem: "app.alanvardy.CheckStitch", category: "BackgroundImage")

    private static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("CheckStitch", isDirectory: true)
    }

    private let client: any BackgroundImageFetching
    private let directory: URL

    /// Single-flight guard across `refreshIfNeeded` and `forceRefresh` so an
    /// automatic refresh never interleaves with a manual one at their awaits.
    private var isFetching = false

    /// Fetches the Unsplash payload and photo from the given endpoint and
    /// validates it as a decodable image. Mutates nothing: the actual network
    /// I/O suspends off the main thread and returns a plain value.
    private func fetchWallpaper(from endpoint: URL) async throws -> FetchedWallpaper {
        let payloadData = try await client.fetchData(from: endpoint)
        let decoder = JSONDecoder()
        let payload = try decoder.decode(UnsplashPayload.self, from: payloadData)
        let data = try await client.fetchData(from: payload.url)
        guard isDecodableImage(data) else { throw URLError(.cannotDecodeContentData) }
        return FetchedWallpaper(
            data: data,
            photographer: payload.photographer,
            photographerURL: payload.photographerURL)
    }

    /// Persists both files atomically, then flips the observable state.
    /// Disk before state keeps the displayed photo and attribution consistent.
    private func commit(_ wallpaper: FetchedWallpaper) throws {
        let metadata = BackgroundMetadata(
            photographer: wallpaper.photographer,
            photographerURL: wallpaper.photographerURL?.absoluteString,
            fetchedAt: Date())
        try persist(imageData: wallpaper.data, metadata: metadata) // disk before state
        imageData = wallpaper.data
        photographer = wallpaper.photographer
        photographerURL = wallpaper.photographerURL
    }

    private func isFresh(maxAge: TimeInterval) -> Bool {
        guard let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? decodeMetadata(from: metadataData)
        else { return false }
        return Date().timeIntervalSince(metadata.fetchedAt) < maxAge
    }

    private func decodeMetadata(from data: Data) throws -> BackgroundMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackgroundMetadata.self, from: data)
    }

    private nonisolated func isDecodableImage(_ data: Data) -> Bool {
        #if os(iOS)
            UIImage(data: data) != nil
        #elseif os(macOS)
            NSImage(data: data) != nil
        #endif
    }

    /// Creates the directory if needed and writes both files atomically.
    private func persist(imageData: Data, metadata: BackgroundMetadata) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        try imageData.write(to: imageURL, options: .atomic)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
    }
}

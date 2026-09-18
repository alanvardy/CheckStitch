import Foundation
import Observation

/// A file handed to CheckStitch by the OS (Open In / share / document open).
struct SharedImportFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let displayName: String
}

/// The single funnel for every OS file delivery. Scene delivery (`onOpenURL`)
/// and app-delegate delivery (`application(_:open:)`) both call `receive(url:)`;
/// a cold-start arrival is held in `pending` until the root view consumes it.
///
/// Idempotent per URL: the same URL delivered twice (both hooks firing, or a
/// re-delivery) neither replaces nor duplicates the pending file.
@MainActor
@Observable
final class SharedImportInbox {
    static let shared = SharedImportInbox()

    private(set) var pending: SharedImportFile?
    private var lastReceivedURL: URL?

    private init() {}

    func receive(url: URL) {
        guard url != lastReceivedURL else { return }
        lastReceivedURL = url
        pending = SharedImportFile(id: UUID(), url: url, displayName: url.lastPathComponent)
    }

    /// Returns the pending file once and clears it.
    func consume() -> SharedImportFile? {
        defer { pending = nil }
        return pending
    }
}
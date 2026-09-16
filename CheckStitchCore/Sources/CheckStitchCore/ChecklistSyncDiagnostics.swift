import Foundation
import os

/// The gates a watch-initiated run passes through, on both devices. One
/// correlated `[<gate>]` record per gate makes a single tap's chain greppable
/// in `Console.app` / `idevicessyslog` (`[watchSend] [phoneReceive]
/// [phoneHandle] [snapshotLookup] [createOutcome]`).
public enum SyncGate: String, Sendable, CaseIterable {
    case watchSend
    case watchActivation
    case phoneReceive
    case phoneHandle
    case snapshotLookup
    case createOutcome
}

/// Single logging surface so the phone and the watch agree on subsystem,
/// category and message shape. `notice` level so records persist to disk and
/// are not filtered out of `Console.app`/`devicectl` by default.
///
/// `CheckStitchCore` builds without `SWIFT_DEFAULT_ACTOR_ISOLATION`, so this is
/// nonisolated and callable from the `nonisolated` `WCSessionDelegate` methods.
public enum ChecklistSyncDiagnostics {
    /// The literal matches the phone app's existing `Logger` subsystem so a
    /// single predicate catches both devices' records.
    private static let subsystem = "app.alanvardy.CheckStitch"
    private static let logger = Logger(subsystem: subsystem, category: "ChecklistSync")

    public static func log(_ gate: SyncGate, _ fields: [String: String] = [:]) {
        let detail = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        logger.notice("[\(gate.rawValue, privacy: .public)] \(detail, privacy: .public)")
    }
}

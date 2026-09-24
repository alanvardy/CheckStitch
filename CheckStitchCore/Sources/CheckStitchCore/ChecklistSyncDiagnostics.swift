import Foundation
import os

/// The gates a watch-initiated run passes through, on both devices. One
/// correlated `[<gate>]` record per gate makes a single tap's chain greppable
/// in `Console.app` / `idevicessyslog` (`[watchSend] [watchReceive]
/// [phoneReceive] [phoneSend] [phoneHandle] [snapshotLookup] [createOutcome]`).
public enum SyncGate: String, Sendable, CaseIterable {
    case watchSend
    case watchReceive
    case watchActivation
    case phoneReceive
    case phoneSend
    case phoneHandle
    case snapshotLookup
    case createOutcome
}

/// Single logging surface so the phone and the watch agree on subsystem,
/// category and message shape. `notice` level so records persist to disk and
/// are not filtered out of `Console.app`/`devicectl` by default.
///
/// Each record is also appended to `Documents/checklist-sync.log` in the app's
/// data container: neither device's syslog is pullable from the host via
/// `devicectl` on this machine, so the file is the agent-reachable copy
/// (`devicectl device copy from --domain-type appDataContainer`).
///
/// `CheckStitchCore` builds without `SWIFT_DEFAULT_ACTOR_ISOLATION`, so this is
/// nonisolated and callable from the `nonisolated` `WCSessionDelegate` methods.
public enum ChecklistSyncDiagnostics {
    /// The literal matches the phone app's existing `Logger` subsystem so a
    /// single predicate catches both devices' records.
    private static let subsystem = "app.alanvardy.CheckStitch"
    private static let logger = Logger(subsystem: subsystem, category: "ChecklistSync")

    /// Serializes appends: `log` is called from `@MainActor` and `nonisolated`
    /// `WCSessionDelegate` contexts alike.
    private static let diskLock = NSLock()
    /// Cap for `checklist-sync.log`; the file is reset past this so a long
    /// session cannot grow the app container unboundedly.
    private static let diskSizeLimit: UInt64 = 64 * 1024
    private static let diskFileName = "checklist-sync.log"

    public static func log(_ gate: SyncGate, _ fields: [String: String] = [:]) {
        let line = record(gate, fields)
        logger.notice("\(line, privacy: .public)")
        appendToDisk(line)
    }

    /// Single-line record shared by the logger and the disk copy: keys sort
    /// alphabetically so a field's position is stable across records, and a
    /// fieldless record has no trailing space. Internal so tests can pin the
    /// on-device wire shape.
    static func record(_ gate: SyncGate, _ fields: [String: String] = [:]) -> String {
        let detail = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return detail.isEmpty ? "[\(gate.rawValue)]" : "[\(gate.rawValue)] \(detail)"
    }

    /// Whether `checklist-sync.log` has reached the size that resets it. Pure so
    /// the rotation boundary is testable without touching the file system.
    static func shouldResetFile(currentSize: UInt64) -> Bool {
        currentSize >= diskSizeLimit
    }

    private static func appendToDisk(_ line: String) {
        diskLock.lock()
        defer { diskLock.unlock() }

        let fm = FileManager.default
        guard let directory = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.warning("[diagnostics] no Documents directory for \(diskFileName, privacy: .public)")
            return
        }
        let url = directory.appendingPathComponent(diskFileName)
        let data = Data((line + "\n").utf8)

        let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
        if shouldResetFile(currentSize: size) {
            try? fm.removeItem(at: url)
        }

        var handle = try? FileHandle(forWritingTo: url)
        if handle == nil {
            fm.createFile(atPath: url.path, contents: nil)
            handle = try? FileHandle(forWritingTo: url)
        }
        guard let handle else {
            logger.warning("[diagnostics] could not open \(diskFileName, privacy: .public) for append")
            return
        }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
    }
}

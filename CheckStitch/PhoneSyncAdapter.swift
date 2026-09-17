#if os(iOS)
import CheckStitchCore
import Foundation
import os
import WatchConnectivity

/// Phone half of the sync seam. It owns no EventKit store — reminder creation
/// stays on the coordinator's `createReminders` closure, so the process keeps a
/// single `EKEventStore` (EKCADErrorDomain 1021).
@MainActor
final class PhoneSyncAdapter: NSObject, ChecklistSyncTransport {
    var onMessage: ((ChecklistSyncMessage) -> Void)?
    var onActivated: (() -> Void)?

    init(session: WCSession = .default) {
        self.session = session
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    @discardableResult
    func sendContext(_ data: Data) -> Bool {
        guard session.activationState == .activated else { return false }
        do {
            try session.updateApplicationContext(ChecklistSyncMessage.context(data).userInfo)
            return true
        } catch {
            Self.logger.error("Failed to push checklist context: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Phone → watch is a queued command (`transferUserInfo`), so a result
    /// survives the watch app not running. `true` is acceptance, not delivery.
    @discardableResult
    func sendUserInfo(_ message: ChecklistSyncMessage) -> Bool {
        guard session.activationState == .activated else {
            ChecklistSyncDiagnostics.log(.phoneSend, [
                "message": message.diagnosticName,
                "send": "session-not-activated",
            ])
            return false
        }
        session.transferUserInfo(message.userInfo)
        return true
    }

    private let session: WCSession
    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "PhoneSyncAdapter")
}

extension PhoneSyncAdapter: WCSessionDelegate {
    nonisolated func session(_: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        guard activationState == .activated else { return }
        Task { @MainActor [weak self] in self?.onActivated?() }
    }

    nonisolated func sessionDidBecomeInactive(_: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let message = ChecklistSyncMessage(userInfo: userInfo) else {
            // No run id is recoverable, so there is nobody to answer — log and
            // drop. Every decodable message gets a reply below.
            ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "userInfo", "decode": "rejected"])
            return
        }
        ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "userInfo", "message": message.diagnosticName])
        Task { @MainActor [weak self] in
            guard let self else {
                ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "userInfo", "handler": "self-nil"])
                return
            }
            guard let onMessage = self.onMessage else {
                // Arrived before `coordinator.start()` installed the handler:
                // answer with a failure so the watch is not left on `Sending…`.
                ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "userInfo", "handler": "unset"])
                if case .runChecklist(let id, let runID) = message {
                    self.sendUserInfo(.runResult(
                        RunResult(runID: runID, checklistID: id, kind: .failed)))
                }
                return
            }
            onMessage(message)
        }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let message = ChecklistSyncMessage(userInfo: applicationContext) else {
            ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "context", "decode": "rejected"])
            return
        }
        ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "context", "message": message.diagnosticName])
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }
}
#endif
import CheckStitchCore
import Foundation
import WatchConnectivity

/// Watch half of the sync seam. The watch only ever sends run requests; the
/// phone owns the checklist payload, so `sendContext` is deliberately empty.
@MainActor
final class WatchSyncAdapter: NSObject, ChecklistSyncTransport {
    var onMessage: ((ChecklistSyncMessage) -> Void)?
    var onActivated: (() -> Void)?

    init(session: WCSession = .default) {
        self.session = session
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            ChecklistSyncDiagnostics.log(.watchActivation, ["supported": "false"])
            return
        }
        session.delegate = self
        session.activate()
    }

    @discardableResult
    func sendContext(_: Data) -> Bool { false }

    /// `true` means only that `WCSession` was alive and accepted the transfer
    /// for queued delivery — never that the peer received or acted on it. The
    /// watch therefore reports progress from `.runResult`, never from this.
    @discardableResult
    func sendUserInfo(_ message: ChecklistSyncMessage) -> Bool {
        let state = session.activationState
        let accepted = state == .activated
        ChecklistSyncDiagnostics.log(.watchSend, [
            "message": message.diagnosticName,
            "activationState": String(describing: state),
        ])
        guard accepted else { return false }
        session.transferUserInfo(message.userInfo)
        return true
    }

    private let session: WCSession
}

extension WatchSyncAdapter: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        ChecklistSyncDiagnostics.log(.watchActivation, [
            "state": String(describing: activationState),
            "error": error?.localizedDescription ?? "none",
        ])
        guard activationState == .activated else { return }
        // `receivedApplicationContext` is already populated when activation
        // completes, so a cold launch still sees the phone's last push.
        let message = ChecklistSyncMessage(userInfo: session.receivedApplicationContext)
        Task { @MainActor [weak self] in
            if let message { self?.onMessage?(message) }
            self?.onActivated?()
        }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext, source: "context")
    }

    /// The phone's `runResult` arrives here: it is sent with `transferUserInfo`
    /// so it survives this app not running. Without this handler the watch would
    /// stay on `Sending…` forever — the silent-drop class this ticket fixes.
    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        receive(userInfo, source: "userInfo")
    }

    private nonisolated func receive(_ userInfo: [String: Any], source: String) {
        guard let message = ChecklistSyncMessage(userInfo: userInfo) else {
            ChecklistSyncDiagnostics.log(.watchReceive, ["source": source, "decode": "rejected"])
            return
        }
        ChecklistSyncDiagnostics.log(.watchReceive, ["source": source, "message": message.diagnosticName])
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }
}
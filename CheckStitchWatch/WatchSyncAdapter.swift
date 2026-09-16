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
        guard let message = ChecklistSyncMessage(userInfo: applicationContext) else { return }
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }
}
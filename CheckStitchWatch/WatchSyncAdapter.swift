import CheckStitchCore
import Foundation
import WatchConnectivity

/// Watch half of the sync seam. The watch only ever sends run requests; the
/// phone owns the checklist payload, so `sendContext` is deliberately empty.
@MainActor
final class WatchSyncAdapter: NSObject, ChecklistSyncTransport {
    var onMessage: ((ChecklistSyncMessage) -> Void)?

    init(session: WCSession = .default) {
        self.session = session
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func sendContext(_: Data) {}

    func sendUserInfo(_ message: ChecklistSyncMessage) {
        guard session.activationState == .activated else { return }
        session.transferUserInfo(message.userInfo)
    }

    private let session: WCSession
}

extension WatchSyncAdapter: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        // `receivedApplicationContext` is already populated when activation
        // completes, so a cold launch still sees the phone's last push.
        guard let message = ChecklistSyncMessage(userInfo: session.receivedApplicationContext) else { return }
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let message = ChecklistSyncMessage(userInfo: applicationContext) else { return }
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }
}
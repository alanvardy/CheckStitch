#if os(iOS)
import CheckStitchCore
import Foundation
import WatchConnectivity

/// Phone half of the sync seam. It owns no EventKit store — reminder creation
/// stays on the coordinator's `createReminders` closure, so the process keeps a
/// single `EKEventStore` (EKCADErrorDomain 1021).
@MainActor
final class PhoneSyncAdapter: NSObject, ChecklistSyncTransport {
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

    func sendContext(_ data: Data) {
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(ChecklistSyncMessage.context(data).userInfo)
    }

    func sendUserInfo(_ message: ChecklistSyncMessage) {
        guard session.activationState == .activated else { return }
        session.transferUserInfo(message.userInfo)
    }

    private let session: WCSession
}

extension PhoneSyncAdapter: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}

    nonisolated func sessionDidBecomeInactive(_: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let message = ChecklistSyncMessage(userInfo: userInfo) else { return }
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let message = ChecklistSyncMessage(userInfo: applicationContext) else { return }
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }
}
#endif
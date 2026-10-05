//
//  ConnectivityService.swift
//  Shared by the iPhone and Apple Watch apps.
//
//  Settings travel in the application context (newest edit wins, delivered whenever the
//  other app next runs). Session state travels three ways, because a live message only
//  arrives while the other app is reachable — and a watch with the wrist down is not:
//
//  - sendMessage, when the counterpart is reachable, for an immediate pause or end
//  - updateApplicationContext, so the latest snapshot is waiting the next time the
//    other app activates (a later settings push keeps the same snapshot alongside it)
//  - transferUserInfo, which is queued and can wake the counterpart in the background
//
//  Whichever copy arrives, the session reconciler keeps the newest snapshot.
//

import Foundation
import Combine
import WatchConnectivity

final class ConnectivityService: NSObject, ObservableObject {
    static let shared = ConnectivityService()

    nonisolated enum CounterpartState: Equatable, Sendable {
        case unsupported
        case activating
        case notPaired
        case appNotInstalled
        case notReachable
        case reachable

        var label: String {
            #if os(iOS)
            let other = "Watch"
            #else
            let other = "iPhone"
            #endif
            switch self {
            case .unsupported: return "\(other) sync unavailable"
            case .activating: return "Connecting to \(other)…"
            case .notPaired: return "No Apple Watch paired"
            case .appNotInstalled: return "Watch app not installed"
            case .notReachable: return "\(other) app not open"
            case .reachable: return "\(other) connected"
            }
        }
    }

    @Published private(set) var counterpart: CounterpartState = .activating

    var onSnapshot: ((SessionSnapshot) -> Void)?
    var onHistory: ((SessionHistoryState) -> Void)?
    /// Commands from a build that did not yet send session snapshots.
    var onCommand: ((SyncCommand) -> Void)?

    private let settings = SettingsStore.shared
    /// Latest session to include in the next application context. Settings pushes must
    /// not wipe it: updateApplicationContext replaces the whole dictionary.
    private var publishedSession: SessionSnapshot?
    /// Completed-session log sent with the same context and user-info transfers.
    private var publishedHistory: SessionHistoryState?

    func activate() {
        guard WCSession.isSupported() else {
            counterpart = .unsupported
            return
        }
        settings.onLocalChange = { [weak self] _, _ in
            self?.pushContext()
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Remember the session without sending it. Used at launch before activation finishes.
    func remember(_ snapshot: SessionSnapshot?) {
        publishedSession = snapshot
    }

    func rememberHistory(_ state: SessionHistoryState) {
        publishedHistory = state
    }

    /// Sends the history log on the application context and via transferUserInfo so a
    /// session that ended on the watch reaches the phone even if the phone was suspended.
    func publishHistory(_ state: SessionHistoryState) {
        publishedHistory = state
        pushContext()
        sendHistoryIfReachable(state)
        transferHistory(state)
    }

    /// Publish a session the user just changed, or one we kept because it was newer than
    /// a stale payload from the other device.
    func publish(_ snapshot: SessionSnapshot) {
        publishedSession = snapshot
        guard settings.values.mirrorSessions else { return }
        pushContext()
        sendIfReachable(snapshot)
        transfer(snapshot)
    }

    /// Read the application context WatchConnectivity has stored. Called on activation,
    /// when reachability changes, and when the scene becomes active — the moments a
    /// backgrounded watch actually notices that the phone paused.
    func pullRemote() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        ingest(session.receivedApplicationContext)
    }

    /// Send the current snapshot again if the other app can take a live message, and
    /// refresh the application context either way.
    func republishLiveIfReachable() {
        pushContext()
        guard let publishedSession else { return }
        sendIfReachable(publishedSession)
    }

    private func pushContext() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        guard let settingsData = settings.values.encoded() else { return }
        var payload: [String: Any] = [
            "type": "settings",
            "settings": settingsData,
            "updatedAt": settings.updatedAt.timeIntervalSince1970,
        ]
        if settings.values.mirrorSessions,
           let publishedSession,
           let data = publishedSession.encoded() {
            payload["session"] = data
        }
        if let publishedHistory, let data = publishedHistory.encoded() {
            payload["history"] = data
        }
        do {
            try session.updateApplicationContext(payload)
        } catch {
            print("Sync: failed to push context: \(error.localizedDescription)")
        }
    }

    private func sendIfReachable(_ snapshot: SessionSnapshot) {
        guard settings.values.mirrorSessions, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        let message = sessionPayload(snapshot)
        guard message["session"] != nil else { return }
        session.sendMessage(message, replyHandler: nil) { error in
            print("Sync: failed to send session: \(error.localizedDescription)")
        }
    }

    private func sessionPayload(_ snapshot: SessionSnapshot) -> [String: Any] {
        var message = snapshot.connectivityMessage
        if let publishedHistory, let data = publishedHistory.encoded() {
            message["history"] = data
        }
        return message
    }

    private func sendHistoryIfReachable(_ state: SessionHistoryState) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        guard let data = state.encoded() else { return }
        session.sendMessage(["type": "history", "history": data], replyHandler: nil) { error in
            print("Sync: failed to send history: \(error.localizedDescription)")
        }
    }

    private func transfer(_ snapshot: SessionSnapshot) {
        guard settings.values.mirrorSessions, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        let message = sessionPayload(snapshot)
        guard message["session"] != nil else { return }
        for pending in session.outstandingUserInfoTransfers where pending.userInfo["type"] as? String == "session" {
            pending.cancel()
        }
        session.transferUserInfo(message)
    }

    private func transferHistory(_ state: SessionHistoryState) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        guard let data = state.encoded() else { return }
        for pending in session.outstandingUserInfoTransfers where pending.userInfo["type"] as? String == "history" {
            pending.cancel()
        }
        session.transferUserInfo(["type": "history", "history": data])
    }

    private func refreshState() {
        guard WCSession.isSupported() else {
            counterpart = .unsupported
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            counterpart = .activating
            return
        }
        #if os(iOS)
        if !session.isPaired {
            counterpart = .notPaired
            return
        }
        if !session.isWatchAppInstalled {
            counterpart = .appNotInstalled
            return
        }
        #endif
        counterpart = session.isReachable ? .reachable : .notReachable
    }

    private func ingest(_ payload: [String: Any]) {
        if let data = payload["settings"] as? Data, let updatedAt = payload["updatedAt"] as? Double {
            applyRemoteSettings(data: data, updatedAt: updatedAt)
        }
        if let data = payload["session"] as? Data, let snapshot = SessionSnapshot.decode(data) {
            onSnapshot?(snapshot)
        }
        if let history = SessionHistoryState.decodeMessage(payload) {
            onHistory?(history)
        }
    }

    private func applyRemoteSettings(data: Data, updatedAt: TimeInterval) {
        guard let remote = MeditationSettings.decode(data) else { return }
        settings.applyRemote(remote, updatedAt: Date(timeIntervalSince1970: updatedAt))
    }

    private func didActivate() {
        refreshState()
        // Adopt a newer remote snapshot before pushing, so a stale local session
        // does not overwrite the pause or end that is already in the context.
        pullRemote()
        pushContext()
        if let publishedSession {
            sendIfReachable(publishedSession)
            transfer(publishedSession)
        }
        if let publishedHistory {
            transferHistory(publishedHistory)
        }
    }

    private func deliver(_ payload: [String: Any]) {
        var handled = false
        if let snapshot = SessionSnapshot.decodeMessage(payload) {
            onSnapshot?(snapshot)
            handled = true
        }
        if let history = SessionHistoryState.decodeMessage(payload) {
            onHistory?(history)
            handled = true
        }
        if !handled, let command = SyncCommand(message: payload) {
            onCommand?(command)
        }
    }
}

extension ConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("Sync: activation failed: \(error.localizedDescription)")
        }
        Task { @MainActor in self.didActivate() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshState()
            self.pullRemote()
            self.republishLiveIfReachable()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.deliver(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.deliver(userInfo) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.ingest(applicationContext) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Happens when the user switches to a different paired watch.
        session.activate()
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }
    #endif
}

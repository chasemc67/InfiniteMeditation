//
//  ConnectivityService.swift
//  Shared by the iPhone and Apple Watch apps.
//
//  Mirrors settings (application context, delivered whenever possible) and session
//  start/pause/resume/end commands (live messages, only when the other app is reachable).
//  Each device runs its own timer and alerts locally; nothing depends on the other device
//  being awake at mark time.
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

    var onCommand: ((SyncCommand) -> Void)?

    private let settings = SettingsStore.shared

    func activate() {
        guard WCSession.isSupported() else {
            counterpart = .unsupported
            return
        }
        settings.onLocalChange = { [weak self] values, updatedAt in
            self?.pushSettings(values, updatedAt: updatedAt)
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Sends a live command if the other app is reachable. Returns false if it could not be sent.
    @discardableResult
    func send(_ command: SyncCommand) -> Bool {
        guard settings.values.mirrorSessions, WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return false }
        session.sendMessage(command.message, replyHandler: nil) { error in
            print("Sync: failed to send \(command.kind.rawValue): \(error.localizedDescription)")
        }
        return true
    }

    private func pushSettings(_ values: MeditationSettings, updatedAt: Date) {
        guard WCSession.isSupported(), let data = values.encoded() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        do {
            try session.updateApplicationContext([
                "type": "settings",
                "settings": data,
                "updatedAt": updatedAt.timeIntervalSince1970,
            ])
        } catch {
            print("Sync: failed to push settings: \(error.localizedDescription)")
        }
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

    private func applyRemoteSettings(data: Data, updatedAt: TimeInterval) {
        guard let remote = MeditationSettings.decode(data) else { return }
        settings.applyRemote(remote, updatedAt: Date(timeIntervalSince1970: updatedAt))
    }

    private func didActivate() {
        refreshState()
        let context = WCSession.default.receivedApplicationContext
        if let data = context["settings"] as? Data, let updatedAt = context["updatedAt"] as? Double {
            applyRemoteSettings(data: data, updatedAt: updatedAt)
        }
        pushSettings(settings.values, updatedAt: settings.updatedAt)
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
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = SyncCommand(message: message) else { return }
        Task { @MainActor in self.onCommand?(command) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["settings"] as? Data,
              let updatedAt = applicationContext["updatedAt"] as? Double
        else { return }
        Task { @MainActor in self.applyRemoteSettings(data: data, updatedAt: updatedAt) }
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

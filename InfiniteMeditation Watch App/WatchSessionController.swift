//
//  WatchSessionController.swift
//  InfiniteMeditation Watch App
//

import Foundation
import Combine

final class WatchSessionController: ObservableObject {
    static let shared = WatchSessionController()

    let timer = MeditationTimer()
    let runtime = BackgroundRuntime()
    let settings = SettingsStore.shared
    let connectivity = ConnectivityService.shared
    let history = SessionHistoryStore.shared

    @Published private(set) var lastSessionSummary: String?

    private var snapshot: SessionSnapshot?
    private var summarySessionID: UUID?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        snapshot = SessionPersistence.load()
        if let snapshot, snapshot.phase != .ended {
            timer.adopt(snapshot)
        }
        timer.onMark = { [weak self] mark in self?.playMark(mark) }
        connectivity.onSnapshot = { [weak self] remote in self?.ingest(remote) }
        connectivity.onHistory = { [weak self] remote in self?.ingestHistory(remote) }
        connectivity.onCommand = { [weak self] command in self?.ingestLegacy(command) }
        connectivity.remember(snapshot)
        connectivity.rememberHistory(history.state)
        // Re-publish nested objects so views observing the controller refresh.
        timer.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        runtime.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        connectivity.activate()
        if let snapshot, snapshot.phase == .ended {
            writeMindful(snapshot, prompt: false)
        }
    }

    // MARK: User actions

    func start() {
        guard snapshot == nil || snapshot?.phase == .ended else { return }
        let values = settings.values
        commitLocal(SessionEditor.start(
            at: Date(),
            intervalMinutes: values.intervalMinutes,
            majorEvery: values.majorEvery,
            role: .watch
        ))
    }

    func pause() {
        guard let snapshot, snapshot.phase == .running else { return }
        commitLocal(SessionEditor.pause(snapshot, at: Date(), role: .watch))
    }

    func resume() {
        guard let snapshot, snapshot.phase == .paused else { return }
        commitLocal(SessionEditor.resume(snapshot, at: Date(), role: .watch))
    }

    func end() {
        guard let snapshot, snapshot.phase != .ended else { return }
        commitLocal(SessionEditor.end(snapshot, at: Date(), role: .watch))
    }

    func appBecameActive() {
        connectivity.pullRemote()
        guard timer.phase != .idle else { return }
        // Raising the wrist is also when a missed pause or end is applied, above.
        // Renew only if that snapshot is still an open session.
        runtime.renewIfNeeded()
        if timer.phase == .running { timer.resync() }
        connectivity.republishLiveIfReachable()
    }

    func previewHaptic(major: Bool) {
        HapticPlayer.play(major ? settings.values.majorHaptic : settings.values.minorHaptic)
    }

    func deleteHistory(id: UUID) {
        guard let state = history.delete(id: id) else { return }
        connectivity.publishHistory(state)
    }

    // MARK: Internals

    private func commitLocal(_ next: SessionSnapshot) {
        let wasActive = isActive(snapshot)
        snapshot = next
        SessionPersistence.save(next)
        timer.adopt(next)
        engageRuntime(wasActive: wasActive, phase: next.phase)
        if next.phase == .ended {
            lastSessionSummary = next.statusText(endedRemotely: false)
            summarySessionID = next.sessionID
            writeMindful(next, prompt: true)
            noteHistory(next)
        }
        connectivity.publish(next)
    }

    private func ingest(_ remote: SessionSnapshot) {
        guard settings.values.mirrorSessions else { return }
        let decision = SessionReconciler.decide(
            local: snapshot,
            remote: remote,
            localRole: .watch,
            mindfulEnabled: settings.values.recordMindfulMinutes,
            alreadyRecorded: recordedIDs(local: snapshot, remote: remote)
        )
        if decision.adoptedRemote {
            let wasActive = isActive(snapshot)
            snapshot = decision.snapshot
            SessionPersistence.save(decision.snapshot)
            connectivity.remember(decision.snapshot)
            // Stop the haptic scheduler before touching the runtime session so a pause
            // delivered in the background cannot fire another tap.
            timer.adopt(decision.snapshot)
            engageRuntime(wasActive: wasActive, phase: decision.snapshot.phase)
            if decision.snapshot.phase == .ended {
                lastSessionSummary = decision.snapshot.statusText(endedRemotely: true)
                summarySessionID = decision.snapshot.sessionID
                noteHistory(decision.snapshot)
            }
        }
        if decision.writeMindfulMinutes {
            writeMindful(decision.snapshot, prompt: false)
        }
        if decision.republish {
            connectivity.publish(decision.snapshot)
        }
    }

    private func noteHistory(_ snapshot: SessionSnapshot) {
        guard let state = history.record(snapshot) else { return }
        connectivity.publishHistory(state)
    }

    private func ingestHistory(_ remote: SessionHistoryState) {
        guard let state = history.merge(remote) else { return }
        connectivity.publishHistory(state)
    }

    private func ingestLegacy(_ command: SyncCommand) {
        guard let next = SessionEditor.applyingLegacy(command, to: snapshot, role: .phone) else { return }
        ingest(next)
    }

    private func engageRuntime(wasActive: Bool, phase: SessionPhase) {
        let values = settings.values
        switch phase {
        case .running:
            if !wasActive {
                runtime.begin(mode: values.watchMode, saveWorkout: values.saveLongSessionsToHealth, paused: false)
            } else {
                runtime.resumeWorkout()
                runtime.renewIfNeeded()
            }
        case .paused:
            if !wasActive {
                runtime.begin(mode: values.watchMode, saveWorkout: values.saveLongSessionsToHealth, paused: true)
            } else {
                runtime.pauseWorkout()
            }
        case .ended:
            if wasActive || runtime.wantsRuntime {
                runtime.end()
            }
        }
    }

    private func recordedIDs(local: SessionSnapshot?, remote: SessionSnapshot) -> Set<UUID> {
        var ids: Set<UUID> = []
        let writer = MindfulMinutesWriter.shared
        if let local, writer.hasRecorded(local.sessionID) { ids.insert(local.sessionID) }
        if writer.hasRecorded(remote.sessionID) { ids.insert(remote.sessionID) }
        return ids
    }

    private func writeMindful(_ snapshot: SessionSnapshot, prompt: Bool) {
        guard settings.values.recordMindfulMinutes else { return }
        guard SessionReconciler.shouldRecord(
            snapshot,
            role: .watch,
            enabled: true,
            alreadyRecorded: MindfulMinutesWriter.shared.hasRecorded(snapshot.sessionID) ? [snapshot.sessionID] : []
        ) else { return }
        if !prompt && !MindfulMinutesWriter.shared.isAuthorized { return }
        let sessionID = snapshot.sessionID
        Task { [weak self] in
            let result = await MindfulMinutesWriter.shared.record(snapshot)
            self?.applyMindfulResult(result, sessionID: sessionID)
        }
    }

    private func applyMindfulResult(_ result: MindfulSaveResult, sessionID: UUID) {
        guard summarySessionID == sessionID, let summary = lastSessionSummary else { return }
        guard !summary.contains("Mindful"), !summary.contains("Health") else { return }
        let suffix: String?
        switch result {
        case .saved:
            suffix = "Mindful Minutes saved"
        case .denied:
            suffix = "Health access off"
        case .unavailable:
            suffix = "Health isn't available"
        case .failed:
            suffix = "Mindful Minutes not saved"
        case .alreadySaved, .nothingToSave:
            suffix = nil
        }
        if let suffix {
            lastSessionSummary = summary + " · " + suffix
        }
    }

    private func isActive(_ snapshot: SessionSnapshot?) -> Bool {
        snapshot?.phase == .running || snapshot?.phase == .paused
    }

    private func playMark(_ mark: Mark) {
        let values = settings.values
        HapticPlayer.play(mark.isMajor ? values.majorHaptic : values.minorHaptic)
    }
}

#if DEBUG
extension WatchSessionController {
    /// Starts a session already `elapsed` seconds in. Screenshot staging only.
    /// Does not publish to the phone or write Health.
    func startForScreenshots(elapsed: TimeInterval) {
        // Standard mode avoids the Health permission sheet covering the UI.
        settings.values.watchMode = .standard
        let values = settings.values
        lastSessionSummary = nil
        let started = SessionEditor.start(
            at: Date().addingTimeInterval(-elapsed),
            intervalMinutes: values.intervalMinutes,
            majorEvery: values.majorEvery,
            role: .watch
        )
        snapshot = started
        timer.adopt(started)
        runtime.begin(mode: .standard, saveWorkout: false, paused: false)
    }
}
#endif

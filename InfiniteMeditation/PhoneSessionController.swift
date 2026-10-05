//
//  PhoneSessionController.swift
//  InfiniteMeditation
//

import Foundation
import Combine

final class PhoneSessionController: ObservableObject {
    static let shared = PhoneSessionController()

    let timer = MeditationTimer()
    let chimes = ChimePlayer()
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
            if settings.values.chimeEnabled { chimes.beginSession() }
        }
        timer.onMark = { [weak self] mark in self?.playMark(mark) }
        connectivity.onSnapshot = { [weak self] remote in self?.ingest(remote) }
        connectivity.onHistory = { [weak self] remote in self?.ingestHistory(remote) }
        connectivity.onCommand = { [weak self] command in self?.ingestLegacy(command) }
        connectivity.remember(snapshot)
        connectivity.rememberHistory(history.state)
        settings.$values
            .map(\.chimeEnabled)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in self?.chimeSettingChanged(enabled) }
            .store(in: &cancellables)
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
            role: .phone
        ))
    }

    func pause() {
        guard let snapshot, snapshot.phase == .running else { return }
        commitLocal(SessionEditor.pause(snapshot, at: Date(), role: .phone))
    }

    func resume() {
        guard let snapshot, snapshot.phase == .paused else { return }
        commitLocal(SessionEditor.resume(snapshot, at: Date(), role: .phone))
    }

    func end() {
        guard let snapshot, snapshot.phase != .ended else { return }
        commitLocal(SessionEditor.end(snapshot, at: Date(), role: .phone))
    }

    func appBecameActive() {
        connectivity.pullRemote()
        timer.resync()
        connectivity.republishLiveIfReachable()
    }

    func previewChime(major: Bool) {
        chimes.preview(major: major, volume: settings.values.chimeVolume)
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
        syncChimes(wasActive: wasActive, phase: next.phase)
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
            localRole: .phone,
            mindfulEnabled: settings.values.recordMindfulMinutes,
            alreadyRecorded: recordedIDs(local: snapshot, remote: remote)
        )
        if decision.adoptedRemote {
            let wasActive = isActive(snapshot)
            snapshot = decision.snapshot
            SessionPersistence.save(decision.snapshot)
            connectivity.remember(decision.snapshot)
            timer.adopt(decision.snapshot)
            syncChimes(wasActive: wasActive, phase: decision.snapshot.phase)
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
        guard let next = SessionEditor.applyingLegacy(command, to: snapshot, role: .watch) else { return }
        ingest(next)
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
            role: .phone,
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

    private func syncChimes(wasActive: Bool, phase: SessionPhase) {
        switch phase {
        case .running, .paused:
            if !wasActive, settings.values.chimeEnabled { chimes.beginSession() }
        case .ended:
            if wasActive { chimes.endSession() }
        }
    }

    private func isActive(_ snapshot: SessionSnapshot?) -> Bool {
        snapshot?.phase == .running || snapshot?.phase == .paused
    }

    private func playMark(_ mark: Mark) {
        guard settings.values.chimeEnabled else { return }
        chimes.play(major: mark.isMajor, volume: settings.values.chimeVolume)
    }

    private func chimeSettingChanged(_ enabled: Bool) {
        guard timer.phase != .idle else { return }
        if enabled { chimes.beginSession() } else { chimes.endSession() }
    }
}

#if DEBUG
extension PhoneSessionController {
    /// Starts a session already `elapsed` seconds in, without audio or Health. Screenshot staging only.
    func startForScreenshots(elapsed: TimeInterval) {
        let values = settings.values
        lastSessionSummary = nil
        let started = SessionEditor.start(
            at: Date().addingTimeInterval(-elapsed),
            intervalMinutes: values.intervalMinutes,
            majorEvery: values.majorEvery,
            role: .phone
        )
        snapshot = started
        timer.adopt(started)
    }
}
#endif

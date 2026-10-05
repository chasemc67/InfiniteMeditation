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

    @Published private(set) var lastSessionSummary: String?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        timer.onMark = { [weak self] mark in self?.playMark(mark) }
        connectivity.onCommand = { [weak self] command in self?.apply(command) }
        settings.$values
            .map(\.chimeEnabled)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in self?.chimeSettingChanged(enabled) }
            .store(in: &cancellables)
        connectivity.activate()
    }

    // MARK: User actions

    func start() {
        begin(schedule: settings.values.schedule, elapsed: 0)
        connectivity.send(command(.start))
    }

    func pause() {
        timer.pause()
        connectivity.send(command(.pause))
    }

    func resume() {
        timer.resume()
        connectivity.send(command(.resume))
    }

    func end() {
        let total = finish()
        connectivity.send(SyncCommand(kind: .end, elapsed: total, intervalMinutes: settings.values.intervalMinutes, majorEvery: settings.values.majorEvery))
    }

    func appBecameActive() {
        timer.resync()
    }

    func previewChime(major: Bool) {
        chimes.preview(major: major, volume: settings.values.chimeVolume)
    }

    // MARK: Internals

    private func begin(schedule: MarkSchedule, elapsed: TimeInterval) {
        lastSessionSummary = nil
        if settings.values.chimeEnabled {
            chimes.beginSession()
        }
        timer.start(schedule: schedule, elapsed: elapsed)
    }

    @discardableResult
    private func finish(suffix: String? = nil) -> TimeInterval {
        let marks = timer.schedule.marksReached(atElapsed: timer.elapsed())
        let total = timer.end()
        chimes.endSession()
        let detail = suffix ?? "\(marks) mark\(marks == 1 ? "" : "s")"
        lastSessionSummary = "\(TimeFormat.clock(total)) · \(detail)"
        return total
    }

    private func playMark(_ mark: Mark) {
        guard settings.values.chimeEnabled else { return }
        chimes.play(major: mark.isMajor, volume: settings.values.chimeVolume)
    }

    private func chimeSettingChanged(_ enabled: Bool) {
        guard timer.phase != .idle else { return }
        if enabled { chimes.beginSession() } else { chimes.endSession() }
    }

    private func command(_ kind: SyncCommand.Kind) -> SyncCommand {
        SyncCommand(
            kind: kind,
            elapsed: timer.elapsed(),
            intervalMinutes: Int(timer.schedule.intervalSeconds / 60),
            majorEvery: timer.schedule.majorEvery
        )
    }

    /// Applies a command mirrored from the watch.
    private func apply(_ command: SyncCommand) {
        guard settings.values.mirrorSessions else { return }
        let elapsed = command.elapsed(receivedAt: Date())
        switch command.kind {
        case .start:
            begin(schedule: command.schedule, elapsed: elapsed)
        case .pause:
            if timer.phase != .idle { timer.pause(elapsed: elapsed) }
        case .resume:
            if timer.phase == .idle {
                begin(schedule: command.schedule, elapsed: elapsed)
            } else {
                timer.resume(elapsed: elapsed)
            }
        case .end:
            guard timer.phase != .idle else { return }
            finish(suffix: "ended on Watch")
        }
    }
}

#if DEBUG
extension PhoneSessionController {
    /// Starts a session already `elapsed` seconds in, without audio. Screenshot staging only.
    func startForScreenshots(elapsed: TimeInterval) {
        lastSessionSummary = nil
        timer.start(schedule: settings.values.schedule, elapsed: elapsed)
    }
}
#endif

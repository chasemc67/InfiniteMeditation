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

    @Published private(set) var lastSessionSummary: String?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        timer.onMark = { [weak self] mark in self?.playMark(mark) }
        connectivity.onCommand = { [weak self] command in self?.apply(command) }
        // Re-publish nested objects so views observing the controller refresh.
        timer.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        runtime.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        connectivity.activate()
    }

    // MARK: User actions

    func start() {
        let values = settings.values
        lastSessionSummary = nil
        runtime.begin(mode: values.watchMode, saveWorkout: values.saveLongSessionsToHealth)
        timer.start(schedule: values.schedule)
        connectivity.send(command(.start))
    }

    func pause() {
        timer.pause()
        connectivity.send(command(.pause))
    }

    func resume() {
        timer.resume()
        runtime.renewIfNeeded()
        connectivity.send(command(.resume))
    }

    func end() {
        let marks = timer.schedule.marksReached(atElapsed: timer.elapsed())
        let total = timer.end()
        runtime.end()
        connectivity.send(SyncCommand(kind: .end, elapsed: total, intervalMinutes: settings.values.intervalMinutes, majorEvery: settings.values.majorEvery))
        lastSessionSummary = "\(TimeFormat.clock(total)) · \(marks) mark\(marks == 1 ? "" : "s")"
    }

    func appBecameActive() {
        guard timer.phase != .idle else { return }
        runtime.renewIfNeeded()
        timer.resync()
    }

    func previewHaptic(major: Bool) {
        HapticPlayer.play(major ? settings.values.majorHaptic : settings.values.minorHaptic)
    }

    // MARK: Internals

    private func playMark(_ mark: Mark) {
        let values = settings.values
        HapticPlayer.play(mark.isMajor ? values.majorHaptic : values.minorHaptic)
    }

    private func command(_ kind: SyncCommand.Kind) -> SyncCommand {
        SyncCommand(
            kind: kind,
            elapsed: timer.elapsed(),
            intervalMinutes: Int(timer.schedule.intervalSeconds / 60),
            majorEvery: timer.schedule.majorEvery
        )
    }

    /// Applies a command mirrored from the iPhone. Commands only arrive while this app is
    /// reachable (in the foreground), which is also when watchOS lets us start a background session.
    private func apply(_ command: SyncCommand) {
        guard settings.values.mirrorSessions else { return }
        let elapsed = command.elapsed(receivedAt: Date())
        switch command.kind {
        case .start:
            lastSessionSummary = nil
            runtime.begin(mode: settings.values.watchMode, saveWorkout: settings.values.saveLongSessionsToHealth)
            timer.start(schedule: command.schedule, elapsed: elapsed)
        case .pause:
            if timer.phase != .idle { timer.pause(elapsed: elapsed) }
        case .resume:
            if timer.phase == .idle {
                runtime.begin(mode: settings.values.watchMode, saveWorkout: settings.values.saveLongSessionsToHealth)
                timer.start(schedule: command.schedule, elapsed: elapsed)
            } else {
                timer.resume(elapsed: elapsed)
                runtime.renewIfNeeded()
            }
        case .end:
            guard timer.phase != .idle else { return }
            let total = timer.end()
            runtime.end()
            lastSessionSummary = "\(TimeFormat.clock(total)) · ended on iPhone"
        }
    }
}

#if DEBUG
extension WatchSessionController {
    /// Starts a session already `elapsed` seconds in. Screenshot staging only.
    func startForScreenshots(elapsed: TimeInterval) {
        let values = settings.values
        lastSessionSummary = nil
        runtime.begin(mode: values.watchMode, saveWorkout: values.saveLongSessionsToHealth)
        timer.start(schedule: values.schedule, elapsed: elapsed)
    }
}
#endif

//
//  MeditationTimer.swift
//  Shared by the iPhone and Apple Watch apps.
//

import Foundation
import Combine

nonisolated struct Mark: Equatable, Sendable {
    var index: Int
    var isMajor: Bool
}

/// Count-up timer that fires a callback at each interval mark.
///
/// Elapsed time is derived from wall-clock anchors rather than accumulated ticks, and marks are
/// scheduled with a single sleep until the next mark instead of polling, so a late wake-up
/// (or a suspended process) can never drift or double-fire.
final class MeditationTimer: ObservableObject {
    nonisolated enum Phase: Equatable, Sendable {
        case idle
        case running
        case paused
    }

    /// Marks discovered more than this long after they were due are skipped instead of played,
    /// e.g. if the process was suspended and only woke up much later.
    static let staleMarkTolerance: TimeInterval = 45

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var schedule = MeditationSettings().schedule
    @Published private(set) var marksFired = 0
    @Published private(set) var lastMarkAt: Date?

    /// Time accumulated before the current running stretch.
    private(set) var accumulated: TimeInterval = 0
    /// Start of the current running stretch; nil when idle or paused.
    private(set) var runningSince: Date?
    private(set) var pausedAt: Date?

    var onMark: ((Mark) -> Void)?

    private var lastHandledMark = 0
    private var schedulerTask: Task<Void, Never>?

    func elapsed(at date: Date = Date()) -> TimeInterval {
        guard let runningSince else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(runningSince))
    }

    /// The moment the session would have started had it never been paused. Stable while running.
    var displayAnchor: Date {
        if let runningSince { return runningSince.addingTimeInterval(-accumulated) }
        let pause = pausedAt ?? Date()
        return pause.addingTimeInterval(-accumulated)
    }

    var nextMarkElapsed: TimeInterval? {
        guard phase != .idle, schedule.intervalSeconds > 0 else { return nil }
        return schedule.elapsed(ofMark: lastHandledMark + 1)
    }

    func start(schedule: MarkSchedule, elapsed: TimeInterval = 0, now: Date = Date()) {
        stopScheduler()
        self.schedule = schedule
        accumulated = max(0, elapsed)
        runningSince = now
        pausedAt = nil
        lastHandledMark = schedule.marksReached(atElapsed: accumulated)
        marksFired = 0
        lastMarkAt = nil
        phase = .running
        startScheduler()
    }

    /// Pauses. Pass `elapsed` to snap to a value received from the other device.
    func pause(elapsed override: TimeInterval? = nil, now: Date = Date()) {
        guard phase != .idle else { return }
        accumulated = override ?? elapsed(at: now)
        runningSince = nil
        pausedAt = now
        phase = .paused
        stopScheduler()
    }

    func resume(elapsed override: TimeInterval? = nil, now: Date = Date()) {
        guard phase != .idle else { return }
        if let override { accumulated = max(0, override) }
        runningSince = now
        pausedAt = nil
        lastHandledMark = max(lastHandledMark, schedule.marksReached(atElapsed: accumulated))
        phase = .running
        startScheduler()
    }

    /// Snaps the clock and the mark scheduler to a mirrored snapshot.
    /// An ended snapshot returns the timer to idle; the caller reads elapsed from the snapshot.
    func adopt(_ snapshot: SessionSnapshot, now: Date = Date()) {
        let newSchedule = MarkSchedule(
            intervalSeconds: TimeInterval(snapshot.intervalMinutes * 60),
            majorEvery: snapshot.majorEvery
        )
        switch snapshot.phase {
        case .running:
            let since = snapshot.runningSince ?? now
            let sameRun = phase == .running
                && runningSince == since
                && accumulated == snapshot.accumulated
                && schedule == newSchedule
            schedule = newSchedule
            accumulated = snapshot.accumulated
            runningSince = since
            pausedAt = nil
            if !sameRun {
                lastHandledMark = newSchedule.marksReached(atElapsed: elapsed(at: now))
            }
            phase = .running
            startScheduler()
        case .paused:
            schedule = newSchedule
            accumulated = snapshot.accumulated
            runningSince = nil
            pausedAt = snapshot.pausedAt ?? now
            lastHandledMark = newSchedule.marksReached(atElapsed: accumulated)
            phase = .paused
            stopScheduler()
        case .ended:
            schedule = newSchedule
            stopScheduler()
            accumulated = 0
            runningSince = nil
            pausedAt = nil
            lastHandledMark = 0
            phase = .idle
        }
    }

    /// Ends the session and returns the final elapsed time.
    @discardableResult
    func end(now: Date = Date()) -> TimeInterval {
        let total = elapsed(at: now)
        stopScheduler()
        accumulated = 0
        runningSince = nil
        pausedAt = nil
        lastHandledMark = 0
        phase = .idle
        return total
    }

    /// Re-arms the scheduler, e.g. after the app returns to the foreground.
    func resync() {
        guard phase == .running else { return }
        startScheduler()
    }

    private func startScheduler() {
        stopScheduler()
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let wait = self?.secondsUntilNextMark() else { return }
                if wait > 0 {
                    do {
                        try await Task.sleep(for: .seconds(wait), tolerance: .milliseconds(50), clock: .continuous)
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled else { return }
                self?.handleDueMarks()
            }
        }
    }

    private func stopScheduler() {
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    private func secondsUntilNextMark() -> TimeInterval? {
        guard phase == .running, schedule.intervalSeconds > 0 else { return nil }
        let target = schedule.elapsed(ofMark: lastHandledMark + 1)
        return target - elapsed()
    }

    private func handleDueMarks(now: Date = Date()) {
        let current = elapsed(at: now)
        let reached = schedule.marksReached(atElapsed: current)
        guard reached > lastHandledMark else { return }
        lastHandledMark = reached
        let lateness = current - schedule.elapsed(ofMark: reached)
        guard lateness <= Self.staleMarkTolerance else { return }
        marksFired += 1
        lastMarkAt = now
        onMark?(Mark(index: reached, isMajor: schedule.isMajor(reached)))
    }
}

extension SessionSnapshot {
    /// Idle-screen line after a session ends. `endedRemotely` names the other device.
    nonisolated func statusText(endedRemotely: Bool) -> String {
        let clock = TimeFormat.clock(accumulated)
        if endedRemotely {
            let device = updatedBy == .phone ? "iPhone" : "Watch"
            return "\(clock) · ended on \(device)"
        }
        let schedule = MarkSchedule(intervalSeconds: TimeInterval(intervalMinutes * 60), majorEvery: majorEvery)
        let marks = schedule.marksReached(atElapsed: accumulated)
        return "\(clock) · \(marks) mark\(marks == 1 ? "" : "s")"
    }
}

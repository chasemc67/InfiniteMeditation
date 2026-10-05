//
//  TimerDisplay.swift
//  Shared by the iPhone and Apple Watch apps.
//

import SwiftUI

/// Elapsed time rendered by the system from date anchors, so no per-frame timer is needed
/// and it stays correct on the Always On display.
struct ElapsedTimeText: View {
    @ObservedObject var timer: MeditationTimer

    var body: some View {
        switch timer.phase {
        case .idle:
            Text("0:00")
        case .running:
            Text(timerInterval: timer.displayAnchor...Date.distantFuture, countsDown: false)
        case .paused:
            Text(
                timerInterval: timer.displayAnchor...Date.distantFuture,
                pauseTime: timer.pausedAt ?? Date(),
                countsDown: false
            )
        }
    }
}

/// "Next mark in 3:12" while running; static text when paused.
struct NextMarkText: View {
    @ObservedObject var timer: MeditationTimer

    var body: some View {
        if let nextElapsed = timer.nextMarkElapsed {
            let index = Int((nextElapsed / max(timer.schedule.intervalSeconds, 1)).rounded())
            let kind = timer.schedule.isMajor(index) ? "major mark" : "mark"
            if timer.phase == .running {
                let target = timer.displayAnchor.addingTimeInterval(nextElapsed)
                let now = Date()
                HStack(spacing: 4) {
                    Text("Next \(kind) in")
                    Text(timerInterval: min(now, target)...max(now, target), countsDown: true)
                        .monospacedDigit()
                }
            } else {
                Text("Paused · next \(kind) at \(TimeFormat.clock(nextElapsed))")
            }
        }
    }
}

nonisolated enum TimeFormat {
    /// 5:00, 1:02:03
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

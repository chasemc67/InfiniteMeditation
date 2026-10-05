//
//  SyncCommand.swift
//  Shared by the iPhone and Apple Watch apps.
//

import Foundation

/// A session control message mirrored between iPhone and Apple Watch over WatchConnectivity.
nonisolated struct SyncCommand: Equatable, Sendable {
    nonisolated enum Kind: String, Sendable {
        case start
        case pause
        case resume
        case end
    }

    var kind: Kind
    /// Elapsed meditation time on the sender when the message was sent.
    var elapsed: TimeInterval
    var sentAt: Date
    var intervalMinutes: Int
    var majorEvery: Int

    var schedule: MarkSchedule {
        MarkSchedule(intervalSeconds: TimeInterval(intervalMinutes * 60), majorEvery: majorEvery)
    }

    /// Elapsed time adjusted for transit delay. Clamped so a skewed device clock can't jump the timer.
    func elapsed(receivedAt now: Date) -> TimeInterval {
        guard kind == .start || kind == .resume else { return elapsed }
        let transit = min(max(now.timeIntervalSince(sentAt), 0), 5)
        return elapsed + transit
    }

    var message: [String: Any] {
        [
            "type": "command",
            "kind": kind.rawValue,
            "elapsed": elapsed,
            "sentAt": sentAt.timeIntervalSince1970,
            "intervalMinutes": intervalMinutes,
            "majorEvery": majorEvery,
        ]
    }

    init(kind: Kind, elapsed: TimeInterval, sentAt: Date = Date(), intervalMinutes: Int, majorEvery: Int) {
        self.kind = kind
        self.elapsed = elapsed
        self.sentAt = sentAt
        self.intervalMinutes = intervalMinutes
        self.majorEvery = majorEvery
    }

    init?(message: [String: Any]) {
        guard message["type"] as? String == "command",
              let raw = message["kind"] as? String,
              let kind = Kind(rawValue: raw),
              let elapsed = message["elapsed"] as? Double,
              let sentAt = message["sentAt"] as? Double,
              let interval = message["intervalMinutes"] as? Int,
              let major = message["majorEvery"] as? Int,
              interval > 0
        else { return nil }
        self.init(
            kind: kind,
            elapsed: elapsed,
            sentAt: Date(timeIntervalSince1970: sentAt),
            intervalMinutes: interval,
            majorEvery: major
        )
    }
}

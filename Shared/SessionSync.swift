//
//  SessionSync.swift
//  Shared by the iPhone and Apple Watch apps.
//
//  Authoritative meditation session state. Each device keeps its own timer, and whichever
//  side last changed the session (start, pause, resume, end) publishes a snapshot. On
//  reconnect the newer snapshot wins, so a pause made while the watch was unreachable
//  still stops the watch.
//
//  Mindful Minutes are one Health sample per uninterrupted stretch. A pause closes the
//  current stretch and a resume opens a new one, so time spent paused is not counted.
//  The wall-clock span from the first start to the end is intentionally not what we save:
//  Apple Health treats a mindful-session sample's duration as end − start.
//

import Foundation

nonisolated enum DeviceRole: String, Codable, Equatable, Sendable {
    case phone
    case watch
}

#if os(watchOS)
let localDeviceRole = DeviceRole.watch
#else
let localDeviceRole = DeviceRole.phone
#endif

nonisolated enum SessionPhase: String, Codable, Equatable, Sendable {
    case running
    case paused
    case ended
}

/// One uninterrupted stretch of meditation. Pauses are the gaps between segments.
nonisolated struct MindfulSegment: Codable, Equatable, Sendable {
    var start: Date
    var end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Versioned session state mirrored between iPhone and Apple Watch.
///
/// `updatedAt` is the last-writer-wins clock. `revision` only breaks ties when two
/// snapshots share a timestamp (same-millisecond edits, or a legacy command folded in
/// locally). A higher revision does not beat a later timestamp: paired watches take
/// their clock from the iPhone, and a pause minutes after the start is safely newer.
nonisolated struct SessionSnapshot: Codable, Equatable, Sendable {
    var sessionID: UUID
    var phase: SessionPhase
    var updatedAt: Date
    var revision: Int
    /// Device that produced this revision.
    var updatedBy: DeviceRole
    /// Meditation time accumulated before the current running stretch.
    var accumulated: TimeInterval
    /// Wall-clock start of the current running stretch. Nil unless `phase == .running`.
    var runningSince: Date?
    var pausedAt: Date?
    var intervalMinutes: Int
    var majorEvery: Int
    /// Closed stretches. The open stretch is `openSegmentStart` while running.
    var segments: [MindfulSegment]
    var openSegmentStart: Date?

    func elapsed(at date: Date) -> TimeInterval {
        guard phase == .running, let runningSince else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(runningSince))
    }

    func encoded() -> Data? {
        try? SessionCoding.makeEncoder().encode(self)
    }

    static func decode(_ data: Data) -> SessionSnapshot? {
        try? SessionCoding.makeDecoder().decode(SessionSnapshot.self, from: data)
    }

    var connectivityMessage: [String: Any] {
        guard let data = encoded() else { return [:] }
        return ["type": "session", "session": data]
    }

    static func decodeMessage(_ message: [String: Any]) -> SessionSnapshot? {
        guard message["type"] as? String == "session",
              let data = message["session"] as? Data
        else { return nil }
        return decode(data)
    }
}

nonisolated enum SessionCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

nonisolated enum SessionEditor {
    static func start(
        at now: Date,
        intervalMinutes: Int,
        majorEvery: Int,
        role: DeviceRole,
        sessionID: UUID = UUID()
    ) -> SessionSnapshot {
        SessionSnapshot(
            sessionID: sessionID,
            phase: .running,
            updatedAt: now,
            revision: 1,
            updatedBy: role,
            accumulated: 0,
            runningSince: now,
            pausedAt: nil,
            intervalMinutes: max(1, intervalMinutes),
            majorEvery: max(0, majorEvery),
            segments: [],
            openSegmentStart: now
        )
    }

    static func pause(_ snapshot: SessionSnapshot, at now: Date, role: DeviceRole) -> SessionSnapshot {
        guard snapshot.phase == .running else { return snapshot }
        var next = snapshot
        next.segments = snapshot.segments + closedOpenSegment(snapshot, at: now)
        next.accumulated = snapshot.elapsed(at: now)
        next.runningSince = nil
        next.openSegmentStart = nil
        next.pausedAt = now
        next.phase = .paused
        return stamp(next, at: now, role: role, from: snapshot)
    }

    static func resume(_ snapshot: SessionSnapshot, at now: Date, role: DeviceRole) -> SessionSnapshot {
        guard snapshot.phase == .paused else { return snapshot }
        var next = snapshot
        next.phase = .running
        next.runningSince = now
        next.openSegmentStart = now
        next.pausedAt = nil
        return stamp(next, at: now, role: role, from: snapshot)
    }

    static func end(_ snapshot: SessionSnapshot, at now: Date, role: DeviceRole) -> SessionSnapshot {
        guard snapshot.phase != .ended else { return snapshot }
        var next = snapshot
        if snapshot.phase == .running {
            next.segments = snapshot.segments + closedOpenSegment(snapshot, at: now)
            next.accumulated = snapshot.elapsed(at: now)
            next.runningSince = nil
            next.openSegmentStart = nil
        }
        next.pausedAt = nil
        next.phase = .ended
        return stamp(next, at: now, role: role, from: snapshot)
    }

    /// Folds a pre-snapshot live command into local state so a device that has not
    /// updated yet can still pause or end this one. The command's `sentAt` is the edit time.
    static func applyingLegacy(
        _ command: SyncCommand,
        to local: SessionSnapshot?,
        role: DeviceRole
    ) -> SessionSnapshot? {
        switch command.kind {
        case .start, .resume:
            if let local, local.phase == .paused, command.kind == .resume {
                return resume(local, at: command.sentAt, role: role)
            }
            if let local, local.phase == .running { return local }
            if let local, local.phase == .ended { return local }
            var started = start(
                at: command.sentAt,
                intervalMinutes: command.intervalMinutes,
                majorEvery: command.majorEvery,
                role: role
            )
            if command.elapsed > 0 {
                started.accumulated = command.elapsed
                started.runningSince = command.sentAt
                started.openSegmentStart = command.sentAt.addingTimeInterval(-command.elapsed)
            }
            return started
        case .pause:
            guard let local else { return nil }
            return pause(local, at: command.sentAt, role: role)
        case .end:
            guard let local else { return nil }
            return end(local, at: command.sentAt, role: role)
        }
    }

    private static func stamp(
        _ snapshot: SessionSnapshot,
        at now: Date,
        role: DeviceRole,
        from previous: SessionSnapshot
    ) -> SessionSnapshot {
        var next = snapshot
        next.updatedAt = now
        next.revision = previous.revision + 1
        next.updatedBy = role
        return next
    }

    private static func closedOpenSegment(_ snapshot: SessionSnapshot, at end: Date) -> [MindfulSegment] {
        guard let start = snapshot.openSegmentStart else { return [] }
        return [MindfulSegment(start: start, end: max(end, start))]
    }
}

/// A mindful-session sample ready to hand to HealthKit.
///
/// `syncIdentifier` is stable for a session segment so the phone and the watch can both
/// attempt the save (a race where both tap End) and HealthKit keeps a single sample.
/// `syncVersion` is the snapshot's `updatedAt` in milliseconds; a later end replaces an
/// earlier write of the same segment instead of inserting a second one.
nonisolated struct MindfulSampleDraft: Equatable, Sendable {
    var start: Date
    var end: Date
    var syncIdentifier: String
    var syncVersion: Int

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

nonisolated enum MindfulMinutesPlan {
    /// Shorter stretches are not worth a Health prompt or a sample Health would reject.
    static let minimumDuration: TimeInterval = 1

    static func samples(for snapshot: SessionSnapshot) -> [MindfulSampleDraft] {
        let version = max(1, Int((snapshot.updatedAt.timeIntervalSince1970 * 1000).rounded()))
        return snapshot.segments.enumerated().compactMap { index, segment in
            guard segment.duration >= minimumDuration else { return nil }
            return MindfulSampleDraft(
                start: segment.start,
                end: segment.end,
                syncIdentifier: "boundless.mindful.\(snapshot.sessionID.uuidString).\(index)",
                syncVersion: version
            )
        }
    }
}

nonisolated struct SessionSyncDecision: Equatable, Sendable {
    var snapshot: SessionSnapshot
    /// The remote snapshot replaced local state.
    var adoptedRemote: Bool
    /// Local state is newer than what just arrived; publish it again so a stale
    /// application context does not become the newest payload on the wire.
    var republish: Bool
    /// This device should write Mindful Minutes for `snapshot`.
    var writeMindfulMinutes: Bool
}

nonisolated enum SessionReconciler {
    /// Last writer wins by `updatedAt`, then `revision`, then a more terminal phase
    /// (ended beats paused beats running), then the phone when the edit is simultaneous.
    static func decide(
        local: SessionSnapshot?,
        remote: SessionSnapshot,
        localRole: DeviceRole,
        mindfulEnabled: Bool,
        alreadyRecorded: Set<UUID>
    ) -> SessionSyncDecision {
        guard let local else {
            return SessionSyncDecision(
                snapshot: remote,
                adoptedRemote: true,
                republish: false,
                writeMindfulMinutes: shouldRecord(
                    remote,
                    role: localRole,
                    enabled: mindfulEnabled,
                    alreadyRecorded: alreadyRecorded
                )
            )
        }
        if remote == local {
            return SessionSyncDecision(
                snapshot: local,
                adoptedRemote: false,
                republish: false,
                writeMindfulMinutes: shouldRecord(
                    local,
                    role: localRole,
                    enabled: mindfulEnabled,
                    alreadyRecorded: alreadyRecorded
                )
            )
        }
        if remoteWins(remote, over: local) {
            return SessionSyncDecision(
                snapshot: remote,
                adoptedRemote: true,
                republish: false,
                writeMindfulMinutes: shouldRecord(
                    remote,
                    role: localRole,
                    enabled: mindfulEnabled,
                    alreadyRecorded: alreadyRecorded
                )
            )
        }
        return SessionSyncDecision(
            snapshot: local,
            adoptedRemote: false,
            republish: true,
            writeMindfulMinutes: false
        )
    }

    static func shouldRecord(
        _ snapshot: SessionSnapshot,
        role: DeviceRole,
        enabled: Bool,
        alreadyRecorded: Set<UUID>
    ) -> Bool {
        enabled
            && snapshot.phase == .ended
            && snapshot.updatedBy == role
            && !alreadyRecorded.contains(snapshot.sessionID)
            && !MindfulMinutesPlan.samples(for: snapshot).isEmpty
    }

    static func remoteWins(_ remote: SessionSnapshot, over local: SessionSnapshot) -> Bool {
        if remote.updatedAt != local.updatedAt {
            return remote.updatedAt > local.updatedAt
        }
        if remote.revision != local.revision {
            return remote.revision > local.revision
        }
        let remoteRank = phaseRank(remote.phase)
        let localRank = phaseRank(local.phase)
        if remoteRank != localRank { return remoteRank > localRank }
        if remote.updatedBy != local.updatedBy { return remote.updatedBy == .phone }
        return false
    }

    private static func phaseRank(_ phase: SessionPhase) -> Int {
        switch phase {
        case .running: 0
        case .paused: 1
        case .ended: 2
        }
    }
}

nonisolated enum SessionPersistence {
    static let storageKey = "sessionSnapshot.v1"

    static func load() -> SessionSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return SessionSnapshot.decode(data)
    }

    static func save(_ snapshot: SessionSnapshot?) {
        if let snapshot, let data = snapshot.encoded() {
            UserDefaults.standard.set(data, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }
}

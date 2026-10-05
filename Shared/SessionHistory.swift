//
//  SessionHistory.swift
//  Shared by the iPhone and Apple Watch apps.
//
//  A completed meditation is one row: when it started, and how long was actually spent
//  meditating. Pauses are not part of the duration (same stretches as Mindful Minutes).
//  The phone and the watch both record the row for a shared session; merging keeps a
//  single row per session id. Deleting a row stores a tombstone so the other device
//  cannot put it back. Deleting does not remove the Health sample.
//

import Foundation

nonisolated struct SessionHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var startedAt: Date
    var duration: TimeInterval
    var endedAt: Date
}

nonisolated struct SessionHistoryState: Codable, Equatable, Sendable {
    var entries: [SessionHistoryEntry]
    var deletedIDs: [UUID]
    var updatedAt: Date

    static let empty = SessionHistoryState(
        entries: [],
        deletedIDs: [],
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    func encoded() -> Data? {
        try? SessionCoding.makeEncoder().encode(self)
    }

    static func decode(_ data: Data) -> SessionHistoryState? {
        try? SessionCoding.makeDecoder().decode(SessionHistoryState.self, from: data)
    }

    static func decodeMessage(_ message: [String: Any]) -> SessionHistoryState? {
        guard let data = message["history"] as? Data else { return nil }
        return decode(data)
    }
}

nonisolated enum SessionHistoryLog {
    /// Accidental taps shorter than this are not listed.
    static let minimumDuration: TimeInterval = 1
    static let entryLimit = 200
    static let tombstoneLimit = 400

    /// Builds a history row from an ended session. Nil while the session is still open,
    /// or when the meditation was shorter than `minimumDuration`.
    static func entry(from snapshot: SessionSnapshot) -> SessionHistoryEntry? {
        guard snapshot.phase == .ended, snapshot.accumulated >= minimumDuration else { return nil }
        let startedAt = snapshot.segments.map(\.start).min()
            ?? snapshot.updatedAt.addingTimeInterval(-snapshot.accumulated)
        return SessionHistoryEntry(
            id: snapshot.sessionID,
            startedAt: startedAt,
            duration: snapshot.accumulated,
            endedAt: snapshot.updatedAt
        )
    }

    static func record(
        _ entry: SessionHistoryEntry,
        into state: SessionHistoryState,
        at now: Date
    ) -> SessionHistoryState {
        if state.deletedIDs.contains(entry.id) { return state }
        if let existing = state.entries.first(where: { $0.id == entry.id }) {
            guard prefers(entry, over: existing), entry != existing else { return state }
            var next = state
            next.entries.removeAll { $0.id == entry.id }
            next.entries.append(entry)
            next.entries = sorted(next.entries)
            next.updatedAt = now
            return next
        }
        var next = state
        next.entries.append(entry)
        next.entries = Array(sorted(next.entries).prefix(entryLimit))
        next.updatedAt = now
        return next
    }

    static func delete(id: UUID, from state: SessionHistoryState, at now: Date) -> SessionHistoryState {
        let hadEntry = state.entries.contains { $0.id == id }
        let alreadyTombstoned = state.deletedIDs.contains(id)
        guard hadEntry || !alreadyTombstoned else { return state }
        var next = state
        next.entries.removeAll { $0.id == id }
        if !alreadyTombstoned {
            next.deletedIDs.append(id)
            if next.deletedIDs.count > tombstoneLimit {
                next.deletedIDs.removeFirst(next.deletedIDs.count - tombstoneLimit)
            }
        }
        next.updatedAt = now
        return next
    }

    /// Union of both logs, one row per session id. Tombstones on either side win, so a
    /// delete on the phone stays deleted when the watch sends its copy of that session.
    static func merge(local: SessionHistoryState, remote: SessionHistoryState) -> SessionHistoryState {
        let deleted = Set(local.deletedIDs).union(remote.deletedIDs)
        var byID: [UUID: SessionHistoryEntry] = [:]
        for entry in local.entries + remote.entries where !deleted.contains(entry.id) {
            if let existing = byID[entry.id] {
                if prefers(entry, over: existing) {
                    byID[entry.id] = entry
                }
            } else {
                byID[entry.id] = entry
            }
        }
        var tombstones = local.deletedIDs.filter { deleted.contains($0) }
        for id in remote.deletedIDs where !tombstones.contains(id) {
            tombstones.append(id)
        }
        if tombstones.count > tombstoneLimit {
            tombstones.removeFirst(tombstones.count - tombstoneLimit)
        }
        return SessionHistoryState(
            entries: Array(sorted(Array(byID.values)).prefix(entryLimit)),
            deletedIDs: tombstones,
            updatedAt: max(local.updatedAt, remote.updatedAt)
        )
    }

    static func changed(_ updated: SessionHistoryState, from original: SessionHistoryState) -> Bool {
        updated.entries != original.entries || updated.deletedIDs != original.deletedIDs
    }

    /// Later end wins. Same end keeps the longer duration, which is the finished session
    /// rather than a partial row written before the last pause was closed.
    static func prefers(_ candidate: SessionHistoryEntry, over existing: SessionHistoryEntry) -> Bool {
        if candidate.endedAt != existing.endedAt { return candidate.endedAt > existing.endedAt }
        if candidate.duration != existing.duration { return candidate.duration > existing.duration }
        return false
    }

    static func sorted(_ entries: [SessionHistoryEntry]) -> [SessionHistoryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
            if lhs.endedAt != rhs.endedAt { return lhs.endedAt > rhs.endedAt }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }
}

//
//  SessionHistoryTests.swift
//
//  History log, dedupe, and delete tombstones. Compiled by the iOS unit-test target
//  and by `swift test` on the Linux toolchain.
//

import Foundation
import Testing

#if canImport(BoundlessSyncCore)
@testable import BoundlessSyncCore
#else
@testable import HapticMeditation
#endif

struct SessionHistoryTests {
    private let t0 = Date(timeIntervalSince1970: 30_000)
    private let phoneID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let watchID = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    private func ended(
        id: UUID,
        start: Date,
        meditated: TimeInterval,
        role: DeviceRole,
        pause: TimeInterval = 0
    ) -> SessionSnapshot {
        var session = SessionEditor.start(
            at: start,
            intervalMinutes: 1,
            majorEvery: 0,
            role: role,
            sessionID: id
        )
        if pause > 0 {
            session = SessionEditor.pause(session, at: start.addingTimeInterval(meditated / 2), role: role)
            session = SessionEditor.resume(session, at: start.addingTimeInterval(meditated / 2 + pause), role: role)
            session = SessionEditor.end(session, at: start.addingTimeInterval(meditated + pause), role: role)
        } else {
            session = SessionEditor.end(session, at: start.addingTimeInterval(meditated), role: role)
        }
        return session
    }

    @Test func endedSessionRecordsStartAndMeditationDuration() throws {
        let snapshot = ended(id: phoneID, start: t0, meditated: 600, role: .phone, pause: 120)
        let entry = try #require(SessionHistoryLog.entry(from: snapshot))
        #expect(entry.id == phoneID)
        #expect(entry.startedAt == t0)
        #expect(entry.duration == 600)
        #expect(entry.duration != 720)
    }

    @Test func openOrTinySessionsAreNotListed() {
        let running = SessionEditor.start(at: t0, intervalMinutes: 5, majorEvery: 2, role: .phone, sessionID: phoneID)
        #expect(SessionHistoryLog.entry(from: running) == nil)
        let tiny = ended(id: phoneID, start: t0, meditated: 0.4, role: .phone)
        #expect(SessionHistoryLog.entry(from: tiny) == nil)
    }

    @Test func phoneAndWatchCopiesOfOneSessionCollapse() throws {
        let phone = try #require(SessionHistoryLog.entry(from: ended(id: phoneID, start: t0, meditated: 300, role: .phone)))
        let watch = try #require(SessionHistoryLog.entry(from: ended(id: phoneID, start: t0, meditated: 300, role: .watch)))
        let onPhone = SessionHistoryLog.record(phone, into: .empty, at: t0.addingTimeInterval(300))
        let onWatch = SessionHistoryLog.record(watch, into: .empty, at: t0.addingTimeInterval(300))
        let merged = SessionHistoryLog.merge(local: onPhone, remote: onWatch)
        #expect(merged.entries.count == 1)
        #expect(merged.entries[0].id == phoneID)
        #expect(merged.entries[0].duration == 300)
    }

    @Test func distinctSessionsStayAndSortNewestFirst() throws {
        let older = try #require(SessionHistoryLog.entry(from: ended(id: phoneID, start: t0, meditated: 60, role: .phone)))
        let newer = try #require(SessionHistoryLog.entry(from: ended(id: watchID, start: t0.addingTimeInterval(500), meditated: 90, role: .watch)))
        var state = SessionHistoryLog.record(older, into: .empty, at: older.endedAt)
        state = SessionHistoryLog.record(newer, into: state, at: newer.endedAt)
        let watchOnly = SessionHistoryLog.record(newer, into: .empty, at: newer.endedAt)
        let merged = SessionHistoryLog.merge(local: state, remote: watchOnly)
        #expect(merged.entries.map(\.id) == [watchID, phoneID])
        #expect(merged.entries[0].startedAt > merged.entries[1].startedAt)
    }

    @Test func recordingTheSameRowTwiceDoesNotChangeTheLog() throws {
        let entry = try #require(SessionHistoryLog.entry(from: ended(id: phoneID, start: t0, meditated: 30, role: .phone)))
        let once = SessionHistoryLog.record(entry, into: .empty, at: entry.endedAt)
        let twice = SessionHistoryLog.record(entry, into: once, at: entry.endedAt.addingTimeInterval(5))
        #expect(twice == once)
        #expect(!SessionHistoryLog.changed(twice, from: once))
    }

    @Test func deleteTombstoneBlocksTheWatchCopyFromComingBack() throws {
        let entry = try #require(SessionHistoryLog.entry(from: ended(id: watchID, start: t0, meditated: 180, role: .watch)))
        let watchLog = SessionHistoryLog.record(entry, into: .empty, at: entry.endedAt)
        let phoneLog = SessionHistoryLog.record(entry, into: .empty, at: entry.endedAt)
        let deleted = SessionHistoryLog.delete(id: watchID, from: phoneLog, at: entry.endedAt.addingTimeInterval(10))
        #expect(deleted.entries.isEmpty)
        #expect(deleted.deletedIDs == [watchID])
        let resurrected = SessionHistoryLog.merge(local: deleted, remote: watchLog)
        #expect(resurrected.entries.isEmpty)
        #expect(resurrected.deletedIDs.contains(watchID))
        let recordedAgain = SessionHistoryLog.record(entry, into: resurrected, at: entry.endedAt.addingTimeInterval(20))
        #expect(recordedAgain.entries.isEmpty)
    }

    @Test func laterEndReplacesAShorterDuplicate() throws {
        let partial = SessionHistoryEntry(id: phoneID, startedAt: t0, duration: 40, endedAt: t0.addingTimeInterval(40))
        let finished = SessionHistoryEntry(id: phoneID, startedAt: t0, duration: 100, endedAt: t0.addingTimeInterval(100))
        let local = SessionHistoryLog.record(partial, into: .empty, at: partial.endedAt)
        let remote = SessionHistoryLog.record(finished, into: .empty, at: finished.endedAt)
        let merged = SessionHistoryLog.merge(local: local, remote: remote)
        #expect(merged.entries.count == 1)
        #expect(merged.entries[0].duration == 100)
    }

    @Test func historyRoundTripsThroughJSON() throws {
        let entry = try #require(SessionHistoryLog.entry(from: ended(id: phoneID, start: t0, meditated: 45, role: .phone)))
        let state = SessionHistoryLog.record(entry, into: .empty, at: entry.endedAt)
        let data = try #require(state.encoded())
        let decoded = try #require(SessionHistoryState.decode(data))
        #expect(decoded == state)
        let message: [String: Any] = ["type": "history", "history": data]
        #expect(SessionHistoryState.decodeMessage(message) == state)
    }
}
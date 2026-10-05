//
//  SessionSyncTests.swift
//
//  Reconciliation and Mindful Minutes planning. Compiled by the iOS unit-test target
//  and by `swift test` (Package.swift) on the Linux toolchain.
//

import Foundation
import Testing

#if canImport(BoundlessSyncCore)
@testable import BoundlessSyncCore
#else
@testable import HapticMeditation
#endif

struct SessionReconcilerTests {
    private let t0 = Date(timeIntervalSince1970: 10_000)

    private func running(role: DeviceRole = .phone, at start: Date? = nil) -> SessionSnapshot {
        SessionEditor.start(
            at: start ?? t0,
            intervalMinutes: 1,
            majorEvery: 2,
            role: role,
            sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
    }

    @Test func phonePauseStopsAWatchThatKeptRunning() {
        let local = running()
        let paused = SessionEditor.pause(local, at: t0.addingTimeInterval(90), role: .phone)
        let decision = SessionReconciler.decide(
            local: local,
            remote: paused,
            localRole: .watch,
            mindfulEnabled: true,
            alreadyRecorded: []
        )
        #expect(decision.adoptedRemote)
        #expect(!decision.republish)
        #expect(!decision.writeMindfulMinutes)
        #expect(decision.snapshot.phase == .paused)
        #expect(decision.snapshot.accumulated == 90)
        #expect(decision.snapshot.segments.count == 1)
        #expect(decision.snapshot.segments[0].duration == 90)
    }

    @Test func olderPauseDoesNotClobberANewerResume() {
        let started = running()
        let paused = SessionEditor.pause(started, at: t0.addingTimeInterval(90), role: .phone)
        let resumed = SessionEditor.resume(paused, at: t0.addingTimeInterval(120), role: .watch)
        let decision = SessionReconciler.decide(
            local: resumed,
            remote: paused,
            localRole: .watch,
            mindfulEnabled: true,
            alreadyRecorded: []
        )
        #expect(!decision.adoptedRemote)
        #expect(decision.republish)
        #expect(decision.snapshot.phase == .running)
        #expect(decision.snapshot.updatedBy == .watch)
    }

    @Test func endedBeatsRunningWhenTimestampsMatch() {
        let local = running()
        var ended = SessionEditor.end(local, at: t0.addingTimeInterval(30), role: .phone)
        ended.updatedAt = local.updatedAt
        ended.revision = local.revision
        let decision = SessionReconciler.decide(
            local: local,
            remote: ended,
            localRole: .watch,
            mindfulEnabled: true,
            alreadyRecorded: []
        )
        #expect(decision.adoptedRemote)
        #expect(decision.snapshot.phase == .ended)
    }

    @Test func identicalSnapshotDoesNotRepublish() {
        let local = running()
        let decision = SessionReconciler.decide(
            local: local,
            remote: local,
            localRole: .phone,
            mindfulEnabled: true,
            alreadyRecorded: []
        )
        #expect(!decision.adoptedRemote)
        #expect(!decision.republish)
        #expect(!decision.writeMindfulMinutes)
    }

    @Test func onlyTheDeviceThatEndedWritesMindfulMinutes() {
        let ended = SessionEditor.end(running(), at: t0.addingTimeInterval(600), role: .phone)
        let onPhone = SessionReconciler.decide(
            local: nil,
            remote: ended,
            localRole: .phone,
            mindfulEnabled: true,
            alreadyRecorded: []
        )
        let onWatch = SessionReconciler.decide(
            local: nil,
            remote: ended,
            localRole: .watch,
            mindfulEnabled: true,
            alreadyRecorded: []
        )
        let already = SessionReconciler.decide(
            local: nil,
            remote: ended,
            localRole: .phone,
            mindfulEnabled: true,
            alreadyRecorded: [ended.sessionID]
        )
        let disabled = SessionReconciler.decide(
            local: nil,
            remote: ended,
            localRole: .phone,
            mindfulEnabled: false,
            alreadyRecorded: []
        )
        #expect(onPhone.writeMindfulMinutes)
        #expect(onPhone.snapshot.updatedBy == .phone)
        #expect(!onWatch.writeMindfulMinutes)
        #expect(!already.writeMindfulMinutes)
        #expect(!disabled.writeMindfulMinutes)
    }

    @Test func watchEndIsNotWrittenByThePhone() {
        let ended = SessionEditor.end(running(role: .watch), at: t0.addingTimeInterval(120), role: .watch)
        let onPhone = SessionReconciler.decide(
            local: running(role: .watch),
            remote: ended,
            localRole: .phone,
            mindfulEnabled: true,
            alreadyRecorded: []
        )
        #expect(onPhone.adoptedRemote)
        #expect(onPhone.snapshot.phase == .ended)
        #expect(!onPhone.writeMindfulMinutes)
    }
}

struct MindfulSegmentTests {
    private let t0 = Date(timeIntervalSince1970: 20_000)

    @Test func pausesBecomeSeparateSegmentsAndAreOmittedFromSamples() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        var session = SessionEditor.start(at: t0, intervalMinutes: 5, majorEvery: 2, role: .phone, sessionID: id)
        session = SessionEditor.pause(session, at: t0.addingTimeInterval(300), role: .phone)
        session = SessionEditor.resume(session, at: t0.addingTimeInterval(420), role: .phone)
        session = SessionEditor.end(session, at: t0.addingTimeInterval(720), role: .phone)

        #expect(session.phase == .ended)
        #expect(session.segments.count == 2)
        #expect(session.segments[0].start == t0)
        #expect(session.segments[0].end == t0.addingTimeInterval(300))
        #expect(session.segments[1].start == t0.addingTimeInterval(420))
        #expect(session.segments[1].end == t0.addingTimeInterval(720))
        #expect(session.accumulated == 600)
        #expect(session.openSegmentStart == nil)

        let wallSpan = session.segments[1].end.timeIntervalSince(session.segments[0].start)
        #expect(wallSpan == 720)
        let samples = MindfulMinutesPlan.samples(for: session)
        #expect(samples.count == 2)
        #expect(samples.map(\.duration) == [300, 300])
        #expect(samples.map(\.duration).reduce(0, +) == 600)
        #expect(samples[0].syncIdentifier == "boundless.mindful.\(id.uuidString).0")
        #expect(samples[1].syncIdentifier == "boundless.mindful.\(id.uuidString).1")
        #expect(samples[0].syncVersion == samples[1].syncVersion)
        #expect(samples[0].syncVersion == Int((session.updatedAt.timeIntervalSince1970 * 1000).rounded()))
    }

    @Test func uninterruptedSessionIsOneSampleCoveringMeditationTime() {
        var session = SessionEditor.start(at: t0, intervalMinutes: 5, majorEvery: 0, role: .watch)
        session = SessionEditor.end(session, at: t0.addingTimeInterval(600), role: .watch)
        let samples = MindfulMinutesPlan.samples(for: session)
        #expect(samples.count == 1)
        #expect(samples[0].start == t0)
        #expect(samples[0].end == t0.addingTimeInterval(600))
        #expect(SessionReconciler.shouldRecord(session, role: .watch, enabled: true, alreadyRecorded: []))
        #expect(!SessionReconciler.shouldRecord(session, role: .phone, enabled: true, alreadyRecorded: []))
    }

    @Test func subSecondStretchIsNotASample() {
        var session = SessionEditor.start(at: t0, intervalMinutes: 1, majorEvery: 0, role: .phone)
        session = SessionEditor.end(session, at: t0.addingTimeInterval(0.4), role: .phone)
        #expect(MindfulMinutesPlan.samples(for: session).isEmpty)
        #expect(!SessionReconciler.shouldRecord(session, role: .phone, enabled: true, alreadyRecorded: []))
    }

    @Test func endingWhilePausedDoesNotInventASegment() {
        var session = SessionEditor.start(at: t0, intervalMinutes: 1, majorEvery: 0, role: .phone)
        session = SessionEditor.pause(session, at: t0.addingTimeInterval(50), role: .phone)
        let ended = SessionEditor.end(session, at: t0.addingTimeInterval(80), role: .phone)
        #expect(ended.segments == session.segments)
        #expect(ended.accumulated == 50)
        #expect(ended.segments[0].duration == 50)
    }

    @Test func snapshotRoundTripsThroughJSONAndMessage() throws {
        var session = SessionEditor.start(at: t0, intervalMinutes: 5, majorEvery: 2, role: .phone)
        session = SessionEditor.pause(session, at: t0.addingTimeInterval(30), role: .phone)
        let data = try #require(session.encoded())
        let decoded = try #require(SessionSnapshot.decode(data))
        #expect(decoded == session)
        let fromMessage = try #require(SessionSnapshot.decodeMessage(session.connectivityMessage))
        #expect(fromMessage == session)
    }

    @Test func legacyPauseUsesTheSendersTimestamp() throws {
        let local = SessionEditor.start(at: t0, intervalMinutes: 1, majorEvery: 2, role: .watch)
        let sentAt = t0.addingTimeInterval(45)
        let command = SyncCommand(kind: .pause, elapsed: 45, sentAt: sentAt, intervalMinutes: 1, majorEvery: 2)
        let paused = try #require(SessionEditor.applyingLegacy(command, to: local, role: .phone))
        let decision = SessionReconciler.decide(
            local: local,
            remote: paused,
            localRole: .watch,
            mindfulEnabled: true,
            alreadyRecorded: []
        )
        #expect(decision.adoptedRemote)
        #expect(decision.snapshot.phase == .paused)
        #expect(decision.snapshot.updatedAt == sentAt)
        #expect(decision.snapshot.segments[0].end == sentAt)
        #expect(decision.snapshot.accumulated == 45)
    }
}

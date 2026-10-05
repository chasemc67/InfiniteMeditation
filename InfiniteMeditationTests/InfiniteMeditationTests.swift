//
//  InfiniteMeditationTests.swift
//  InfiniteMeditationTests
//

import Foundation
import Testing
@testable import HapticMeditation

struct MarkScheduleTests {
    let schedule = MarkSchedule(intervalSeconds: 300, majorEvery: 2)

    @Test func countsMarksReached() {
        #expect(schedule.marksReached(atElapsed: 0) == 0)
        #expect(schedule.marksReached(atElapsed: 299) == 0)
        #expect(schedule.marksReached(atElapsed: 300) == 1)
        #expect(schedule.marksReached(atElapsed: 299.999) == 1)
        #expect(schedule.marksReached(atElapsed: 601) == 2)
        #expect(schedule.marksReached(atElapsed: 3600) == 12)
    }

    @Test func majorMarksAreMultiples() {
        #expect(!schedule.isMajor(1))
        #expect(schedule.isMajor(2))
        #expect(!schedule.isMajor(3))
        #expect(schedule.isMajor(4))
        #expect(!MarkSchedule(intervalSeconds: 300, majorEvery: 0).isMajor(2))
    }

    @Test func defaultSettingsMatchSpec() {
        let defaults = MeditationSettings()
        #expect(defaults.schedule.intervalSeconds == 300)
        #expect(defaults.schedule.isMajor(2))
        #expect(defaults.chimeEnabled)
        #expect(defaults.watchMode == .standard)
        #expect(defaults.recordMindfulMinutes)
    }
}

struct SyncCommandTests {
    @Test func roundTripsThroughMessageDictionary() throws {
        let sent = SyncCommand(kind: .start, elapsed: 12.5, sentAt: Date(timeIntervalSince1970: 1_000), intervalMinutes: 5, majorEvery: 2)
        let received = try #require(SyncCommand(message: sent.message))
        #expect(received == sent)
    }

    @Test func adjustsRunningElapsedForTransitWithinLimits() {
        let sentAt = Date(timeIntervalSince1970: 1_000)
        let start = SyncCommand(kind: .start, elapsed: 10, sentAt: sentAt, intervalMinutes: 5, majorEvery: 2)
        #expect(start.elapsed(receivedAt: sentAt.addingTimeInterval(1)) == 11)
        #expect(start.elapsed(receivedAt: sentAt.addingTimeInterval(600)) == 15)
        #expect(start.elapsed(receivedAt: sentAt.addingTimeInterval(-3)) == 10)
        let pause = SyncCommand(kind: .pause, elapsed: 10, sentAt: sentAt, intervalMinutes: 5, majorEvery: 2)
        #expect(pause.elapsed(receivedAt: sentAt.addingTimeInterval(1)) == 10)
    }

    @Test func rejectsMalformedMessages() {
        #expect(SyncCommand(message: ["type": "command", "kind": "start"]) == nil)
        #expect(SyncCommand(message: ["type": "settings"]) == nil)
    }
}

struct SettingsDecodingTests {
    @Test func missingFieldsFallBackToDefaults() throws {
        let data = Data(#"{"intervalMinutes": 10}"#.utf8)
        let decoded = try #require(MeditationSettings.decode(data))
        #expect(decoded.intervalMinutes == 10)
        #expect(decoded.majorEvery == 2)
        #expect(decoded.chimeEnabled)
        #expect(decoded.recordMindfulMinutes)
    }

    @Test func invalidIntervalFallsBack() throws {
        let data = Data(#"{"intervalMinutes": 0}"#.utf8)
        let decoded = try #require(MeditationSettings.decode(data))
        #expect(decoded.intervalMinutes == 5)
    }
}

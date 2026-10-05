//
//  InfiniteMeditation_Watch_AppTests.swift
//  InfiniteMeditation Watch AppTests
//

import Testing
@testable import HapticMeditation_Watch_App

struct WatchMarkScheduleTests {
    @Test func tenMinuteMarkIsMajorWithDefaults() {
        let schedule = MeditationSettings().schedule
        #expect(schedule.marksReached(atElapsed: 600) == 2)
        #expect(schedule.isMajor(2))
        #expect(!schedule.isMajor(1))
    }
}

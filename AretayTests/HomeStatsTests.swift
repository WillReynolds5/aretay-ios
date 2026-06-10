//
//  HomeStatsTests.swift
//  AretayTests
//

import Foundation
import Testing
@testable import Aretay

struct HomeStatsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    // A fixed "now" at midday so day arithmetic is unambiguous.
    private let now = Date(timeIntervalSince1970: 1_780_056_000)

    private func log(daysAgo: Double, rating: Int = 3, stateBefore: String = "review") -> StudyAPI.LogRow {
        StudyAPI.LogRow(
            reviewedAt: now.addingTimeInterval(-daysAgo * 86_400),
            rating: rating,
            stateBefore: stateBefore
        )
    }

    private func state(_ state: FSRSState, dueDaysFromNow: Double) -> StudyAPI.StateRow {
        StudyAPI.StateRow(
            courseId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            due: now.addingTimeInterval(dueDaysFromNow * 86_400),
            state: state
        )
    }

    @Test func streakCountsConsecutiveDaysIncludingToday() {
        let stats = HomeStats.compute(
            states: [],
            logs: [log(daysAgo: 0), log(daysAgo: 1), log(daysAgo: 2)],
            now: now,
            calendar: calendar
        )
        #expect(stats.streakDays == 3)
    }

    @Test func streakSurvivesNoActivityYetToday() {
        let stats = HomeStats.compute(
            states: [],
            logs: [log(daysAgo: 1), log(daysAgo: 2)],
            now: now,
            calendar: calendar
        )
        #expect(stats.streakDays == 2)
    }

    @Test func streakBreaksOnGap() {
        let stats = HomeStats.compute(
            states: [],
            logs: [log(daysAgo: 0), log(daysAgo: 2), log(daysAgo: 3)],
            now: now,
            calendar: calendar
        )
        #expect(stats.streakDays == 1)
    }

    @Test func retentionOnlyCountsReviewStateAnswers() {
        let stats = HomeStats.compute(
            states: [],
            logs: [
                log(daysAgo: 1, rating: 3, stateBefore: "review"),
                log(daysAgo: 2, rating: 1, stateBefore: "review"),
                log(daysAgo: 3, rating: 3, stateBefore: "review"),
                log(daysAgo: 4, rating: 3, stateBefore: "review"),
                // First encounters and same-session retries must not count.
                log(daysAgo: 1, rating: 1, stateBefore: "new"),
                log(daysAgo: 1, rating: 1, stateBefore: "learning"),
                log(daysAgo: 1, rating: 1, stateBefore: "relearning"),
                // Out of the 30-day window.
                log(daysAgo: 40, rating: 1, stateBefore: "review"),
            ],
            now: now,
            calendar: calendar
        )
        #expect(stats.retentionPercent == 75)
    }

    @Test func retentionIsNilWithoutRealReviews() {
        let stats = HomeStats.compute(
            states: [],
            logs: [log(daysAgo: 0, stateBefore: "new")],
            now: now,
            calendar: calendar
        )
        #expect(stats.retentionPercent == nil)
    }

    @Test func dueAndMemoryCountsComeFromStates() {
        let stats = HomeStats.compute(
            states: [
                state(.review, dueDaysFromNow: -1),   // due + known
                state(.review, dueDaysFromNow: 5),    // known, not due
                state(.new, dueDaysFromNow: 0),       // due (introduced, unanswered)
                state(.learning, dueDaysFromNow: -0.001), // due
            ],
            logs: [],
            now: now,
            calendar: calendar
        )
        #expect(stats.dueNow == 3)
        #expect(stats.knownCards == 2)
        #expect(stats.trackedCards == 4)
        #expect(stats.dueByCourse.values.reduce(0, +) == 3)
    }

    @Test func emptyInputsProduceEmptyStats() {
        let stats = HomeStats.compute(states: [], logs: [], now: now, calendar: calendar)
        #expect(stats == .empty)
    }
}

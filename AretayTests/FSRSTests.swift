//
//  FSRSTests.swift
//  AretayTests
//

import Foundation
import Testing
@testable import Aretay

struct FSRSTests {
    private let scheduler = FSRSScheduler()
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    @Test func firstCorrectAnswerGraduatesToReview() {
        let outcome = scheduler.review(
            state: .new, stability: nil, difficulty: nil,
            lastReviewedAt: nil, rating: .good, now: now
        )
        #expect(outcome.state == .review)
        // Initial stability for Good is w2 ≈ 3.17 days; at 0.9 retention the interval equals stability.
        #expect(abs(outcome.stability - 3.173) < 0.001)
        let dueDays = outcome.due.timeIntervalSince(now) / 86_400
        #expect(abs(dueDays - 3) < 0.01)
        #expect(outcome.difficulty >= 1 && outcome.difficulty <= 10)
    }

    @Test func firstWrongAnswerEntersLearningWithShortStep() {
        let outcome = scheduler.review(
            state: .new, stability: nil, difficulty: nil,
            lastReviewedAt: nil, rating: .again, now: now
        )
        #expect(outcome.state == .learning)
        let dueMinutes = outcome.due.timeIntervalSince(now) / 60
        #expect(abs(dueMinutes - FSRSScheduler.learningStepMinutes) < 0.01)
        // Wrong first answers are harder than right ones.
        let good = scheduler.review(
            state: .new, stability: nil, difficulty: nil,
            lastReviewedAt: nil, rating: .good, now: now
        )
        #expect(outcome.difficulty > good.difficulty)
    }

    @Test func learningGoodGraduatesToReview() {
        let learning = scheduler.review(
            state: .new, stability: nil, difficulty: nil,
            lastReviewedAt: nil, rating: .again, now: now
        )
        let graduated = scheduler.review(
            state: learning.state, stability: learning.stability, difficulty: learning.difficulty,
            lastReviewedAt: now, rating: .good, now: now.addingTimeInterval(600)
        )
        #expect(graduated.state == .review)
        #expect(graduated.due > now.addingTimeInterval(86_400 - 1)) // at least ~a day out
    }

    @Test func reviewGoodGrowsStabilityAndPushesDueOut() {
        let elapsed: TimeInterval = 3 * 86_400
        let outcome = scheduler.review(
            state: .review, stability: 3.0, difficulty: 5.0,
            lastReviewedAt: now.addingTimeInterval(-elapsed), rating: .good, now: now
        )
        #expect(outcome.state == .review)
        #expect(outcome.stability > 3.0)
        let dueDays = outcome.due.timeIntervalSince(now) / 86_400
        #expect(dueDays > 3)
    }

    @Test func reviewAgainShrinksStabilityAndRelearns() {
        let outcome = scheduler.review(
            state: .review, stability: 10.0, difficulty: 5.0,
            lastReviewedAt: now.addingTimeInterval(-10 * 86_400), rating: .again, now: now
        )
        #expect(outcome.state == .relearning)
        #expect(outcome.stability < 10.0)
        // Lapsed card comes back within the session, not in days.
        let dueMinutes = outcome.due.timeIntervalSince(now) / 60
        #expect(abs(dueMinutes - FSRSScheduler.learningStepMinutes) < 0.01)
        // Failure drives difficulty up.
        #expect(outcome.difficulty > 5.0)
    }

    @Test func retrievabilityDecaysToRetentionAtScheduledInterval() {
        let stability = 7.0
        let interval = scheduler.nextIntervalDays(stability: stability)
        let r = scheduler.retrievability(elapsedDays: interval, stability: stability)
        // Rounded interval, so allow a small tolerance around the 0.9 target.
        #expect(abs(r - 0.9) < 0.02)
    }

    @Test func intervalIsClampedToBounds() {
        let small = scheduler.nextIntervalDays(stability: 0.01)
        #expect(small == 1)
        let big = scheduler.nextIntervalDays(stability: 100_000)
        #expect(big == 365)
    }

    @Test func difficultyStaysInBoundsUnderRepeatedFailure() {
        var stability: Double? = nil
        var difficulty: Double? = nil
        var state = FSRSState.new
        var clock = now
        for _ in 0 ..< 30 {
            let outcome = scheduler.review(
                state: state, stability: stability, difficulty: difficulty,
                lastReviewedAt: clock.addingTimeInterval(-86_400), rating: .again, now: clock
            )
            stability = outcome.stability
            difficulty = outcome.difficulty
            state = outcome.state
            clock = outcome.due
            #expect(outcome.difficulty >= 1 && outcome.difficulty <= 10)
            #expect(outcome.stability > 0)
        }
    }
}

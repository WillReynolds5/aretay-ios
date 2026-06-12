//
//  LearnerStats.swift
//  Aretay
//
//  Real spaced-repetition stats for the learner, derived from the user's
//  card states and review history. Shown on the courses home page and the
//  profile sheet, and used to pick the launch destination (due reviews →
//  straight into a session).
//

import Foundation

struct LearnerStats: Hashable, Sendable {
    /// Consecutive days with at least one answer, counting back from today
    /// (yesterday keeps the streak alive until today's session happens).
    let streakDays: Int
    /// Cards due right now across every course.
    let dueNow: Int
    /// Per-course due counts (feeds the "Review now" card).
    let dueByCourse: [UUID: Int]
    /// Per-course tracked-card counts (used as a rough "progress" proxy
    /// for course list cards until we surface real enrollment cursors).
    let seenByCourse: [UUID: Int]
    /// Percent of review-state answers correct in the last 30 days — a true
    /// memory measure: first encounters and same-session retries excluded.
    /// Nil until there's at least one real review.
    let retentionPercent: Int?
    /// Cards that have graduated to long-term review scheduling.
    let knownCards: Int
    /// All cards the scheduler is tracking for this user.
    let trackedCards: Int

    /// Learner level (1-based) derived from cards in long-term memory.
    var levelNumber: Int {
        Self.levelIndex(for: knownCards) + 1
    }

    /// Display title for the current level (Explorer → … → Master).
    var levelTitle: String {
        Self.levels[Self.levelIndex(for: knownCards)].title
    }

    private static let levels: [(threshold: Int, title: String)] = [
        (0, "Explorer"),
        (10, "Learner"),
        (30, "Scholar"),
        (75, "Adept"),
        (150, "Expert"),
        (300, "Master"),
    ]

    private static func levelIndex(for knownCards: Int) -> Int {
        var index = 0
        for (i, level) in levels.enumerated() where knownCards >= level.threshold {
            index = i
        }
        return index
    }

    static let empty = LearnerStats(
        streakDays: 0, dueNow: 0, dueByCourse: [:], seenByCourse: [:],
        retentionPercent: nil, knownCards: 0, trackedCards: 0
    )

    static func compute(
        states: [StudyAPI.StateRow],
        logs: [StudyAPI.LogRow],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> LearnerStats {
        // Streak
        let activeDays = Set(logs.map { calendar.startOfDay(for: $0.reviewedAt) })
        var streak = 0
        var day = calendar.startOfDay(for: now)
        if !activeDays.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }
        while activeDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        // Retention (30-day window, review-state answers only)
        let windowStart = now.addingTimeInterval(-30 * 86_400)
        let reviewAnswers = logs.filter {
            $0.stateBefore == FSRSState.review.rawValue && $0.reviewedAt >= windowStart
        }
        let retention: Int?
        if reviewAnswers.isEmpty {
            retention = nil
        } else {
            let correct = reviewAnswers.filter { $0.rating == FSRSRating.good.rawValue }.count
            retention = Int((Double(correct) / Double(reviewAnswers.count) * 100).rounded())
        }

        // Due + memory progress
        var dueByCourse: [UUID: Int] = [:]
        var seenByCourse: [UUID: Int] = [:]
        for row in states {
            seenByCourse[row.courseId, default: 0] += 1
            if row.due <= now {
                dueByCourse[row.courseId, default: 0] += 1
            }
        }
        let known = states.filter { $0.state == .review }.count

        return LearnerStats(
            streakDays: streak,
            dueNow: dueByCourse.values.reduce(0, +),
            dueByCourse: dueByCourse,
            seenByCourse: seenByCourse,
            retentionPercent: retention,
            knownCards: known,
            trackedCards: states.count
        )
    }
}

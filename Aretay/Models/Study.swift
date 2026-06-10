//
//  Study.swift
//  Aretay
//
//  Rows for the spaced-repetition tables: course_enrollments, card_states,
//  and review_logs. The FSRS scheduler runs on device; these are its
//  persisted state plus the append-only answer history.
//

import Foundation

struct Enrollment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    let courseId: UUID
    var cursorSegmentKey: String?
    var segmentsCompleted: Int
    var desiredRetention: Double
    var newSegmentsPerSession: Int
    var lastStudiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case courseId = "course_id"
        case cursorSegmentKey = "cursor_segment_key"
        case segmentsCompleted = "segments_completed"
        case desiredRetention = "desired_retention"
        case newSegmentsPerSession = "new_segments_per_session"
        case lastStudiedAt = "last_studied_at"
    }
}

struct CardState: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    let cardId: UUID
    let courseId: UUID
    var state: FSRSState
    var due: Date
    var stability: Double?
    var difficulty: Double?
    var reps: Int
    var lapses: Int
    var lastReviewedAt: Date?
    var scheduler: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case cardId = "card_id"
        case courseId = "course_id"
        case state
        case due
        case stability
        case difficulty
        case reps
        case lapses
        case lastReviewedAt = "last_reviewed_at"
        case scheduler = "scheduler"
    }

    /// A fresh, never-reviewed state for a question card that just entered the pool.
    static func newCard(userId: UUID, cardId: UUID, courseId: UUID, now: Date = .now) -> CardState {
        CardState(
            id: UUID(),
            userId: userId,
            cardId: cardId,
            courseId: courseId,
            state: .new,
            due: now,
            stability: nil,
            difficulty: nil,
            reps: 0,
            lapses: 0,
            lastReviewedAt: nil,
            scheduler: FSRSScheduler.schedulerID
        )
    }
}

/// Insert payload for review_logs (id/reviewed_at are set by the database).
struct ReviewLogInsert: Codable, Sendable {
    let cardStateId: UUID
    let userId: UUID
    let rating: Int
    let chosenAnswer: String?
    let stateBefore: String
    let stabilityBefore: Double?
    let difficultyBefore: Double?
    let elapsedDays: Double
    let stabilityAfter: Double
    let difficultyAfter: Double
    let dueAfter: Date
    let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case cardStateId = "card_state_id"
        case userId = "user_id"
        case rating
        case chosenAnswer = "chosen_answer"
        case stateBefore = "state_before"
        case stabilityBefore = "stability_before"
        case difficultyBefore = "difficulty_before"
        case elapsedDays = "elapsed_days"
        case stabilityAfter = "stability_after"
        case difficultyAfter = "difficulty_after"
        case dueAfter = "due_after"
        case durationMs = "duration_ms"
    }
}

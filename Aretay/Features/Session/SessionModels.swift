//
//  SessionModels.swift
//  Aretay
//
//  Items in a study session queue: segment videos to watch and question
//  videos answered via the multiple-choice overlay.
//

import Foundation

struct SegmentItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let segmentKey: String
    let title: String
    let script: String
    let videoURL: URL?
    let captions: [CaptionWord]
    /// True when this segment is new content (advances the enrollment cursor).
    let advancesCursor: Bool
}

struct QuestionItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let questionKey: String
    let cardId: UUID
    let question: String
    let answer: String
    /// Shuffled multiple-choice options (correct answer + up to 3 alternates).
    let options: [String]
    let videoURL: URL?
    let captions: [CaptionWord]
    /// True when this is an in-session retry after a wrong answer.
    let isRequeue: Bool

    func requeued() -> QuestionItem {
        QuestionItem(
            id: UUID(),
            questionKey: questionKey,
            cardId: cardId,
            question: question,
            answer: answer,
            options: options.shuffled(),
            videoURL: videoURL,
            captions: captions,
            isRequeue: true
        )
    }
}

enum SessionItem: Identifiable, Hashable, Sendable {
    case segment(SegmentItem)
    case question(QuestionItem)

    var id: UUID {
        switch self {
        case .segment(let item): return item.id
        case .question(let item): return item.id
        }
    }
}

struct SessionSummary: Hashable, Sendable {
    var segmentsWatched = 0
    var questionsAnswered = 0
    var correct = 0
    var reviewsCompleted = 0
}

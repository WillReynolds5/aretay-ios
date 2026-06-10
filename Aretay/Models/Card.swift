//
//  Card.swift
//  Aretay
//
//  Mirrors the `cards` table — one row per renderable unit of a course:
//  the intro, each lesson segment, and each spaced-repetition question.
//  Question rows carry alt answers + clip duration in metadata.production.
//

import Foundation

/// Word-level caption token written by Whisper (admin transcribe pipeline).
struct CaptionWord: Codable, Hashable, Sendable {
    let text: String
    let startMs: Double
    let endMs: Double

    enum CodingKeys: String, CodingKey {
        case text
        case startMs
        case endMs
    }
}

struct CardProduction: Codable, Hashable, Sendable {
    /// The script actually narrated — possibly trimmed to fit 15s.
    let finalScript: String?
    let audioDuration: Double?
    /// Question rows only: plausible wrong answers to rotate through.
    let altAnswers: [String]?
    /// Question rows only: clip length in whole seconds.
    let videoDuration: Double?

    enum CodingKeys: String, CodingKey {
        case finalScript = "final_script"
        case audioDuration = "audio_duration"
        case altAnswers = "alt_answers"
        case videoDuration = "video_duration"
    }
}

struct CardMetadata: Codable, Hashable, Sendable {
    let production: CardProduction?
}

struct Card: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let courseId: UUID
    let segmentKey: String?
    let videoR2Key: String?
    let captions: [CaptionWord]?
    let metadata: CardMetadata?

    enum CodingKeys: String, CodingKey {
        case id
        case courseId = "course_id"
        case segmentKey = "segment_key"
        case videoR2Key = "video_r2_key"
        case captions
        case metadata
    }

    var videoURL: URL? {
        guard let videoR2Key else { return nil }
        return MediaConfig.publicURL(forKey: videoR2Key)
    }
}

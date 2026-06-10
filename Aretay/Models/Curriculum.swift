//
//  Curriculum.swift
//  Aretay
//
//  Mirrors the curriculum JSON stored on courses.curriculum (see
//  aretay-admin/lib/curriculum.ts). Decoded straight from the jsonb column,
//  so only generator-written fields appear here — video URLs and captions
//  come from the cards table, joined by segment key.
//

import Foundation

struct CurriculumQuestion: Codable, Hashable, Sendable {
    let question: String
    let answer: String
    let answerWordCount: Int?

    enum CodingKeys: String, CodingKey {
        case question
        case answer
        case answerWordCount = "answer_word_count"
    }
}

struct CurriculumSegment: Codable, Hashable, Sendable {
    let segmentNumber: Int
    let script: String
    let wordCount: Int?
    let questions: [CurriculumQuestion]

    enum CodingKeys: String, CodingKey {
        case segmentNumber = "segment_number"
        case script
        case wordCount = "word_count"
        case questions
    }
}

struct CurriculumLesson: Codable, Hashable, Sendable {
    let unitTitle: String
    let level: Int?
    let parentUnit: String?
    let order: Int
    let segments: [CurriculumSegment]

    enum CodingKeys: String, CodingKey {
        case unitTitle = "unit_title"
        case level
        case parentUnit = "parent_unit"
        case order
        case segments
    }
}

struct CurriculumOutlineUnit: Codable, Hashable, Sendable {
    let level1Unit: String
    let summary: String?
    let childUnits: [String]?

    enum CodingKeys: String, CodingKey {
        case level1Unit = "level_1_unit"
        case summary
        case childUnits = "child_units"
    }
}

struct CurriculumIntro: Codable, Hashable, Sendable {
    let script: String
    let wordCount: Int?

    enum CodingKeys: String, CodingKey {
        case script
        case wordCount = "word_count"
    }
}

struct Curriculum: Codable, Hashable, Sendable {
    let title: String
    let subtitle: String?
    let description: String?
    let intro: CurriculumIntro?
    let outline: [CurriculumOutlineUnit]?
    let lessons: [CurriculumLesson]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        intro = try? container.decodeIfPresent(CurriculumIntro.self, forKey: .intro)
        outline = try? container.decodeIfPresent([CurriculumOutlineUnit].self, forKey: .outline)
        lessons = (try? container.decodeIfPresent([CurriculumLesson].self, forKey: .lessons)) ?? []
    }

    /// Lessons sorted by their authored order.
    var orderedLessons: [CurriculumLesson] {
        lessons.sorted { $0.order < $1.order }
    }

    var questionCount: Int {
        lessons.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.questions.count } }
    }

    var segmentCount: Int {
        lessons.reduce(0) { $0 + $1.segments.count }
    }
}

// MARK: - Segment keys

/// Key conventions shared with the admin/generator (aretay-admin/lib/curriculum.ts):
/// `intro`, `L{lessonOrder}-S{segmentNumber}`, `L{lessonOrder}-S{segmentNumber}-Q{index+1}`.
enum SegmentKey {
    static let intro = "intro"

    static func lessonSegment(lessonOrder: Int, segmentNumber: Int) -> String {
        "L\(lessonOrder)-S\(segmentNumber)"
    }

    static func question(lessonOrder: Int, segmentNumber: Int, questionIndex: Int) -> String {
        "L\(lessonOrder)-S\(segmentNumber)-Q\(questionIndex + 1)"
    }
}

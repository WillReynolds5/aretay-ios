//
//  PreviewData.swift
//  Aretay
//
//  Sample courses and learner stats for SwiftUI Canvas previews.
//

#if DEBUG
import Foundation

enum PreviewData {
    static let previewAccessToken = "preview-access-token"

    static let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
    static let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static let romanHistoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let spanishBasicsID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    static let cellBiologyID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!

    static let romanHistory = Course(
        id: romanHistoryID,
        ownerId: ownerID,
        title: "Roman History",
        description: "From the early Republic through the rise of the Empire.",
        coverImageUrl: nil,
        visibility: .public,
        tags: ["history"],
        curriculum: curriculum(title: "Roman History", subtitle: "Republic to Empire", questions: 24),
        createdAt: .now
    )

    static let spanishBasics = Course(
        id: spanishBasicsID,
        ownerId: ownerID,
        title: "Spanish Basics",
        description: "Essential vocabulary and grammar for everyday conversation.",
        coverImageUrl: nil,
        visibility: .public,
        tags: ["language"],
        curriculum: curriculum(title: "Spanish Basics", subtitle: "Everyday conversation", questions: 18),
        createdAt: .now
    )

    static let cellBiology = Course(
        id: cellBiologyID,
        ownerId: ownerID,
        title: "Cell Biology",
        description: "How cells work — organelles, metabolism, and division.",
        coverImageUrl: nil,
        visibility: .public,
        tags: ["science", "nature"],
        curriculum: curriculum(title: "Cell Biology", subtitle: "Inside the cell", questions: 32),
        createdAt: .now
    )

    static let courses: [Course] = [romanHistory, spanishBasics, cellBiology]

    static let loadedStats = LearnerStats(
        streakDays: 7,
        dueNow: 12,
        dueByCourse: [
            romanHistoryID: 8,
            spanishBasicsID: 4,
        ],
        seenByCourse: [
            romanHistoryID: 18,
            spanishBasicsID: 6,
            cellBiologyID: 2,
        ],
        retentionPercent: 87,
        knownCards: 42,
        trackedCards: 80
    )

    /// Applies seeded preview content when the auth manager carries the preview token.
    @MainActor
    static func applyLoadedPreviewIfNeeded(
        accessToken: String?,
        courseStore: CourseStore? = nil
    ) -> LearnerStats? {
        guard accessToken == previewAccessToken else { return nil }
        courseStore?.configureForPreview(courses: courses)
        return loadedStats
    }

    private static func curriculum(title: String, subtitle: String, questions: Int) -> Curriculum {
        let segmentQuestions = (0..<questions).map { index in
            """
            {"question": "Sample question \(index + 1)", "answer": "Sample answer \(index + 1)"}
            """
        }.joined(separator: ",")

        let json = """
        {
          "title": "\(title)",
          "subtitle": "\(subtitle)",
          "lessons": [
            {
              "unit_title": "Unit 1",
              "order": 1,
              "segments": [
                {
                  "segment_number": 1,
                  "script": "Preview segment script.",
                  "questions": [\(segmentQuestions)]
                }
              ]
            }
          ]
        }
        """
        let data = Data(json.utf8)
        return try! JSONDecoder().decode(Curriculum.self, from: data)
    }
}
#endif

//
//  Course.swift
//  Aretay
//

import Foundation

struct Course: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ownerId: UUID
    let title: String
    let description: String?
    let coverImageUrl: String?
    let visibility: Visibility
    let curriculum: Curriculum?
    let createdAt: Date

    enum Visibility: String, Codable, Hashable, Sendable {
        case `private`
        case unlisted
        case `public`
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case title
        case description
        case coverImageUrl = "cover_image_url"
        case visibility
        case curriculum
        case createdAt = "created_at"
    }

    init(
        id: UUID,
        ownerId: UUID,
        title: String,
        description: String?,
        coverImageUrl: String?,
        visibility: Visibility,
        curriculum: Curriculum?,
        createdAt: Date
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.description = description
        self.coverImageUrl = coverImageUrl
        self.visibility = visibility
        self.curriculum = curriculum
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ownerId = try container.decode(UUID.self, forKey: .ownerId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        coverImageUrl = try container.decodeIfPresent(String.self, forKey: .coverImageUrl)
        visibility = try container.decode(Visibility.self, forKey: .visibility)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Best-effort: old prototype courses carry a different curriculum
        // shape — show them without lessons rather than failing the row.
        curriculum = try? container.decodeIfPresent(Curriculum.self, forKey: .curriculum)
    }

    var lessonCount: Int {
        curriculum?.lessons.count ?? 0
    }

    var questionCount: Int {
        curriculum?.questionCount ?? 0
    }
}

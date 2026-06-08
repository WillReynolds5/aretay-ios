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

    var lessonCount: Int {
        curriculum?.videos.count ?? 0
    }
}

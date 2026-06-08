//
//  Curriculum.swift
//  Aretay
//

import Foundation

struct CurriculumQuestion: Codable, Hashable, Sendable {
    let text: String
    let options: [String]
    let answer: String
}

struct CurriculumVideo: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let title: String
    let date: String
    let era: String
    let prompt: String
    let narration: String
    let question: CurriculumQuestion
}

struct Curriculum: Codable, Hashable, Sendable {
    let title: String
    let videos: [CurriculumVideo]
}

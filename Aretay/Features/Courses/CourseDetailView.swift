//
//  CourseDetailView.swift
//  Aretay
//

import SwiftUI

struct CourseDetailView: View {
    let course: Course

    var body: some View {
        List {
            if let description = course.description, !description.isEmpty {
                Section("About") {
                    Text(description)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Lessons") {
                if let videos = course.curriculum?.videos, !videos.isEmpty {
                    ForEach(videos) { video in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(video.title)
                                .font(.headline)
                            Text("\(video.date) · \(video.era)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    ContentUnavailableView(
                        "No lessons yet",
                        systemImage: "film",
                        description: Text("This course does not have a curriculum.")
                    )
                }
            }
        }
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        CourseDetailView(course: Course(
            id: UUID(),
            ownerId: UUID(),
            title: "Ancient Rome",
            description: "A short survey of the Roman Republic.",
            coverImageUrl: nil,
            visibility: .public,
            curriculum: Curriculum(
                title: "Ancient Rome",
                videos: [
                    CurriculumVideo(
                        id: 1,
                        title: "The Founding Myth",
                        date: "753 BC",
                        era: "Kingdom",
                        prompt: "",
                        narration: "",
                        question: CurriculumQuestion(
                            text: "Who founded Rome?",
                            options: ["Romulus", "Remus", "Aeneas", "Tarquin"],
                            answer: "Romulus"
                        )
                    ),
                ]
            ),
            createdAt: .now
        ))
    }
}

//
//  CourseDetailView.swift
//  Aretay
//

import SwiftUI

struct CourseDetailView: View {
    let course: Course

    @Environment(AuthManager.self) private var auth

    @State private var enrollment: Enrollment?
    @State private var dueCount = 0
    @State private var isStudying = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if let subtitle = course.curriculum?.subtitle {
                        Text(subtitle)
                            .font(.headline)
                    }
                    if let description = course.description ?? course.curriculum?.description,
                       !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Button {
                    isStudying = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text(startButtonTitle)
                            .font(.headline)
                        Spacer()
                        if dueCount > 0 {
                            Text("\(dueCount) due")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .accessibilityIdentifier("startSession")
            }

            if let enrollment, let curriculum = course.curriculum, curriculum.segmentCount > 0 {
                Section("Progress") {
                    let total = curriculum.segmentCount + 1 // + intro
                    ProgressView(value: Double(enrollment.segmentsCompleted), total: Double(total)) {
                        Text("\(enrollment.segmentsCompleted) of \(total) videos watched")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let outline = course.curriculum?.outline, !outline.isEmpty {
                Section("What you'll learn") {
                    ForEach(outline, id: \.level1Unit) { unit in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(unit.level1Unit)
                                .font(.headline)
                            if let summary = unit.summary {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else if course.curriculum == nil {
                Section {
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
        .fullScreenCover(isPresented: $isStudying, onDismiss: {
            Task { await loadStudyState() }
        }) {
            SessionView(course: course)
        }
        .task(id: auth.sessionLoadID) {
            await loadStudyState()
        }
    }

    private var startButtonTitle: String {
        if let enrollment, enrollment.segmentsCompleted > 0 {
            return "Continue learning"
        }
        return "Start learning"
    }

    private func loadStudyState() async {
        guard let token = auth.accessToken else { return }
        enrollment = try? await StudyAPI.fetchEnrollment(courseId: course.id, accessToken: token)
        let states = (try? await StudyAPI.fetchCardStates(courseId: course.id, accessToken: token)) ?? []
        dueCount = states.filter { $0.due <= .now }.count
    }
}

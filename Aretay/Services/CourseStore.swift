//
//  CourseStore.swift
//  Aretay
//

import Foundation
import Observation

@MainActor
@Observable
final class CourseStore {
    private(set) var courses: [Course] = []
    private(set) var isLoading = false
    var errorMessage: String?

    func loadCourses() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await CourseAPI.fetchPublicCourses()
            guard !Task.isCancelled else { return }
            courses = response
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

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

    func loadCourses(
        accessToken: String,
        refreshAccessToken: (() async throws -> String)? = nil
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await fetchCourses(
                accessToken: accessToken,
                refreshAccessToken: refreshAccessToken
            )
            guard !Task.isCancelled else { return }
            courses = response
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func fetchCourses(
        accessToken: String,
        refreshAccessToken: (() async throws -> String)?
    ) async throws -> [Course] {
        do {
            return try await CourseAPI.fetchPublicCourses(accessToken: accessToken)
        } catch let error as CourseAPIError {
            if case .http(401, _) = error, let refreshAccessToken {
                let freshToken = try await refreshAccessToken()
                return try await CourseAPI.fetchPublicCourses(accessToken: freshToken)
            }
            throw error
        }
    }

#if DEBUG
    func configureForPreview(courses: [Course]) {
        self.courses = courses
        isLoading = false
        errorMessage = nil
    }

    static var previewLoaded: CourseStore {
        let store = CourseStore()
        store.configureForPreview(courses: PreviewData.courses)
        return store
    }
#endif
}

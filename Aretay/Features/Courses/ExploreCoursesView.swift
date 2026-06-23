//
//  ExploreCoursesView.swift
//  Aretay
//
//  The full course catalog, pushed from the Explore section's "See all":
//  a pinned category chip row and search over an endlessly scrolling
//  two-column grid of course cards — cover, title, and card count only.
//  This page is for browsing and discovery; progress lives on the home page.
//

import SwiftUI

struct ExploreCoursesView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(CourseStore.self) private var courseStore

    @State private var searchText = ""
    @State private var selectedCategoryID: ExploreCategory.ID = ExploreCategory.forYou.id

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        VStack(spacing: 0) {
            chipsRow

            ScrollView {
                if filteredCourses.isEmpty {
                    emptyState
                        .padding(.top, 48)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredCourses) { course in
                            NavigationLink {
                                CourseDetailView(course: course)
                            } label: {
                                ExploreGridCard(course: course)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search courses"
        )
        .task(id: auth.sessionLoadID) {
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    // MARK: Filtering

    private var availableCategories: [ExploreCategory] {
        ExploreCategory.available(for: courseStore.courses)
    }

    private var selectedCategory: ExploreCategory {
        availableCategories.first { $0.id == selectedCategoryID } ?? .forYou
    }

    private var filteredCourses: [Course] {
        let inCategory = courseStore.courses.filter { selectedCategory.matches($0) }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return inCategory }
        return inCategory.filter { course in
            course.title.localizedCaseInsensitiveContains(query)
                || (course.description?.localizedCaseInsensitiveContains(query) ?? false)
                || (course.curriculum?.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    // MARK: Pieces

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableCategories) { category in
                    ExploreCategoryChip(
                        category: category,
                        isSelected: category.id == selectedCategoryID
                    ) {
                        withAnimation(.snappy) { selectedCategoryID = category.id }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if courseStore.isLoading && courseStore.courses.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let error = courseStore.errorMessage, courseStore.courses.isEmpty {
            ContentUnavailableView(
                "Couldn't load courses",
                systemImage: "wifi.exclamationmark",
                description: Text(error)
            )
        } else if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView(
                "No courses yet",
                systemImage: "books.vertical",
                description: Text(
                    courseStore.courses.isEmpty
                        ? "Courses you publish in the admin studio show up here."
                        : "No \(selectedCategory.title) courses yet."
                )
            )
        }
    }

    private func reload() async {
        #if DEBUG
        if PreviewData.applyLoadedPreviewIfNeeded(
            accessToken: auth.accessToken,
            courseStore: courseStore
        ) != nil {
            return
        }
        #endif
        guard let token = try? await auth.validAccessToken() else { return }
        await courseStore.loadCourses(accessToken: token) {
            try await auth.validAccessToken()
        }
    }
}

// MARK: - Grid card (cover, title, card count)

private struct ExploreGridCard: View {
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CourseArtwork(course: course, cornerRadius: 14)

            Text(course.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2, reservesSpace: true)

            Text(course.questionCount == 1 ? "1 card" : "\(course.questionCount) cards")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

#if DEBUG
#Preview("Loaded") {
    NavigationStack {
        ExploreCoursesView()
            .environment(AuthManager.preview)
            .environment(CourseStore.previewLoaded)
    }
}

#Preview("Empty") {
    NavigationStack {
        ExploreCoursesView()
            .environment(AuthManager.previewSignedInEmpty)
            .environment(CourseStore())
    }
}
#endif

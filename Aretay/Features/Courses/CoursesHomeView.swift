//
//  CoursesHomeView.swift
//  Aretay
//
//  The app's single home page — no tabs. Inline header (profile avatar +
//  greeting), a three-stat bar (Streak / Due / Retention), a "Review Due
//  Now" hero card, an "Explore Courses" section (filter chips + horizontal
//  course cards), and a grouped "My Courses" list.
//
//  Owns launch routing: on a fresh launch, anything due → full-screen-present
//  the top-due review session immediately (TikTok-style "just start
//  playing"); nothing due but a course left unfinished → resume that course;
//  otherwise rest here on the courses page. Closing a session always lands
//  back here.
//

import SwiftUI

struct CoursesHomeView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(CourseStore.self) private var courseStore

    @State private var stats = LearnerStats.empty
    @State private var selectedCategoryID: ExploreCategory.ID = ExploreCategory.forYou.id
    @State private var showExplore = false
    @State private var showProfile = false
    /// Course whose session is presented full screen right now.
    @State private var activeSession: Course?
    /// Launch routing runs once per launch — navigation is the user's after that.
    @State private var hasRoutedOnLaunch = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HomeHeader(displayName: auth.displayName) {
                        showProfile = true
                    }

                    LearnerStatsBar(stats: stats)

                    if let review = topDueCourse {
                        ReviewDueNowCard(
                            course: review.course,
                            dueCount: review.count,
                            onStart: { activeSession = review.course }
                        )
                    }

                    exploreSection

                    myCoursesSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showExplore) {
                ExploreCoursesView()
            }
            .task(id: auth.sessionLoadID) {
                await reload()
                await routeOnLaunch()
            }
            .refreshable {
                await reload()
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .fullScreenCover(item: $activeSession, onDismiss: {
            // Exiting a session always lands back on the courses page.
            Task { await reload() }
        }) { course in
            SessionView(course: course)
        }
    }

    private func reload() async {
        #if DEBUG
        if let previewStats = PreviewData.applyLoadedPreviewIfNeeded(
            accessToken: auth.accessToken,
            courseStore: courseStore
        ) {
            stats = previewStats
            return
        }
        #endif
        guard let token = try? await auth.validAccessToken() else { return }
        await courseStore.loadCourses(accessToken: token) {
            try await auth.validAccessToken()
        }
        async let states = StudyAPI.fetchStateRows(accessToken: token)
        async let logs = StudyAPI.fetchRecentLogs(accessToken: token)
        if let states = try? await states, let logs = try? await logs {
            stats = LearnerStats.compute(states: states, logs: logs)
        }
    }

    // MARK: Launch routing

    /// Fresh launch: due reviews → dive straight into the top-due session;
    /// nothing due but a course in progress → resume it; otherwise stay here.
    private func routeOnLaunch() async {
        guard !hasRoutedOnLaunch, auth.accessToken != nil else { return }
        hasRoutedOnLaunch = true
        #if DEBUG
        // Don't hijack SwiftUI previews into a full-screen session.
        if auth.accessToken == PreviewData.previewAccessToken { return }
        #endif
        guard activeSession == nil else { return }

        if let review = topDueCourse {
            activeSession = review.course
        } else if let resume = await courseInProgress() {
            activeSession = resume
        }
    }

    /// Most recently studied course that's been started but not finished.
    private func courseInProgress() async -> Course? {
        guard let token = try? await auth.validAccessToken(),
              let enrollments = try? await StudyAPI.fetchEnrollments(accessToken: token)
        else { return nil }
        for enrollment in enrollments {
            guard enrollment.segmentsCompleted > 0,
                  let course = courseStore.courses.first(where: { $0.id == enrollment.courseId }),
                  let curriculum = course.curriculum,
                  enrollment.segmentsCompleted < curriculum.segmentCount + 1 // + intro
            else { continue }
            return course
        }
        return nil
    }

    private var topDueCourse: (course: Course, count: Int)? {
        let candidates = courseStore.courses.compactMap { course -> (Course, Int)? in
            guard let count = stats.dueByCourse[course.id], count > 0 else { return nil }
            return (course, count)
        }
        return candidates.max { $0.1 < $1.1 }
    }

    /// "For You" plus one chip per tag present in the loaded catalog.
    private var availableCategories: [ExploreCategory] {
        ExploreCategory.available(for: courseStore.courses)
    }

    private var selectedCategory: ExploreCategory {
        availableCategories.first { $0.id == selectedCategoryID } ?? .forYou
    }

    private var exploreCourses: [Course] {
        courseStore.courses.filter { selectedCategory.matches($0) }
    }

    private func progress(for course: Course) -> Double {
        let total = course.questionCount
        guard total > 0 else { return 0 }
        let seen = stats.seenByCourse[course.id] ?? 0
        return min(1, Double(seen) / Double(total))
    }

    // MARK: Explore

    @ViewBuilder
    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Explore Courses") { showExplore = true }

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
            }
            .padding(.horizontal, -20)

            if exploreCourses.isEmpty {
                Text(courseStore.courses.isEmpty
                     ? "Courses you publish in the admin studio show up here."
                     : "No \(selectedCategory.title) courses yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(exploreCourses) { course in
                            NavigationLink {
                                CourseDetailView(course: course)
                            } label: {
                                ExploreCourseCard(
                                    course: course,
                                    progress: progress(for: course)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
            }
        }
    }

    // MARK: My Courses

    @ViewBuilder
    private var myCoursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "My Courses")

            if courseStore.isLoading && courseStore.courses.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if let error = courseStore.errorMessage, courseStore.courses.isEmpty {
                ContentUnavailableView(
                    "Couldn't load courses",
                    systemImage: "wifi.exclamationmark",
                    description: Text(error)
                )
            } else if courseStore.courses.isEmpty {
                ContentUnavailableView(
                    "No courses yet",
                    systemImage: "books.vertical",
                    description: Text("Courses you publish in the admin studio show up here.")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(courseStore.courses) { course in
                        NavigationLink {
                            CourseDetailView(course: course)
                        } label: {
                            CourseProgressRow(
                                course: course,
                                progress: progress(for: course),
                                dueCount: stats.dueByCourse[course.id] ?? 0
                            )
                            .padding(14)
                        }
                        .buttonStyle(.plain)

                        if course.id != courseStore.courses.last?.id {
                            Divider()
                                .padding(.leading, 84)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

// MARK: - Header (profile avatar + greeting)

private struct HomeHeader: View {
    let displayName: String?
    let onProfileTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onProfileTap) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
            }
            .accessibilityIdentifier("profileButton")
            .accessibilityLabel("Profile")

            Text(titleText)
                .font(.title.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)
        }
    }

    private var titleText: String {
        if let displayName {
            return "\(greetingText), \(displayName)"
        }
        return greetingText
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

// MARK: - Section header with "See all"

private struct SectionHeader: View {
    let title: String
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
            Spacer()
            if let onSeeAll {
                Button("See all", action: onSeeAll)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

// MARK: - Stats (Streak / Due / Retention)

private struct LearnerStatsBar: View {
    let stats: LearnerStats

    var body: some View {
        HStack(spacing: 0) {
            StatColumn(
                icon: "flame.fill",
                label: "Streak",
                value: "\(stats.streakDays)",
                unit: stats.streakDays == 1 ? "day" : "days",
                tint: .orange
            )
            statDivider
            StatColumn(
                icon: "tray.full.fill",
                label: "Due",
                value: "\(stats.dueNow)",
                unit: stats.dueNow == 1 ? "card" : "cards",
                tint: .blue
            )
            statDivider
            StatColumn(
                icon: "target",
                label: "Retention",
                value: stats.retentionPercent.map { "\($0)%" } ?? "—",
                unit: stats.retentionPercent == nil ? "No data" : "30 days",
                tint: .green
            )
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var statDivider: some View {
        Divider().frame(height: 44)
    }
}

private struct StatColumn: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Review Due Now (hero card)

private struct ReviewDueNowCard: View {
    let course: Course
    let dueCount: Int
    let onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 14) {
                CourseArtwork(course: course, size: 64, cornerRadius: 14)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Review due now")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("startReviewCard")
    }

    private var subtitle: String {
        dueCount == 1 ? "1 card waiting" : "\(dueCount) cards waiting"
    }
}

// MARK: - Explore course card (cover, title, card count, progress)

private struct ExploreCourseCard: View {
    let course: Course
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CourseArtwork(course: course, size: 136, cornerRadius: 14)

            Text(course.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2, reservesSpace: true)

            Text(course.questionCount == 1 ? "1 card" : "\(course.questionCount) cards")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ProgressBar(value: progress)
                    .frame(height: 6)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ProgressBar.tint(for: progress))
                    .monospacedDigit()
            }
        }
        .frame(width: 136)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

#if DEBUG
#Preview("Loaded") {
    CoursesHomeView()
        .environment(AuthManager.preview)
        .environment(CourseStore.previewLoaded)
}

#Preview("Empty") {
    CoursesHomeView()
        .environment(AuthManager.previewSignedInEmpty)
        .environment(CourseStore())
}
#endif

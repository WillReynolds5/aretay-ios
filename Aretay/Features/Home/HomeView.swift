//
//  HomeView.swift
//  Aretay
//

import SwiftUI

struct HomeView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(CourseStore.self) private var courseStore

    @State private var selectedCategory = CourseCategory.all.first?.id ?? "all"
    @State private var stats = HomeStats.empty

    private let mockCategories = CourseCategory.all

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GreetingHeader(displayName: auth.displayName)

                    LearnerStatsBar(stats: stats)

                    if let review = topDueCourse {
                        NavigationLink {
                            CourseDetailView(course: review.course)
                        } label: {
                            ReviewNowSection(
                                title: review.course.title,
                                subtitle: review.count == 1 ? "1 card due" : "\(review.count) cards due"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    CategoryFilterBar(
                        categories: mockCategories,
                        selectedID: $selectedCategory
                    )

                    coursesSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Sign Out", role: .destructive) {
                            Task { await auth.signOut() }
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityIdentifier("accountMenu")
                }
            }
            .task(id: auth.sessionLoadID) {
                await reload()
            }
            .refreshable {
                await reload()
            }
        }
    }

    private func reload() async {
        guard let token = auth.accessToken else { return }
        await courseStore.loadCourses(accessToken: token)
        async let states = StudyAPI.fetchStateRows(accessToken: token)
        async let logs = StudyAPI.fetchRecentLogs(accessToken: token)
        if let states = try? await states, let logs = try? await logs {
            stats = HomeStats.compute(states: states, logs: logs)
        }
    }

    private var topDueCourse: (course: Course, count: Int)? {
        let candidates = courseStore.courses.compactMap { course -> (Course, Int)? in
            guard let count = stats.dueByCourse[course.id], count > 0 else { return nil }
            return (course, count)
        }
        return candidates.max { $0.1 < $1.1 }
    }

    @ViewBuilder
    private var coursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Courses")
                .font(.headline)

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
                CoursesGrid(courses: courseStore.courses, dueByCourse: stats.dueByCourse)
            }
        }
    }
}

// MARK: - Greeting

private struct GreetingHeader: View {
    let displayName: String?

    var body: some View {
        Text(titleText)
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: String {
        if let displayName {
            return "\(greetingText), \(displayName)"
        }
        return greetingText
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let timeOfDay: String
        switch hour {
        case 5..<12:
            timeOfDay = "Good morning"
        case 12..<17:
            timeOfDay = "Good afternoon"
        default:
            timeOfDay = "Good evening"
        }
        return timeOfDay
    }
}

// MARK: - Stats

private struct LearnerStatsBar: View {
    let stats: HomeStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                StatPill(
                    icon: "flame.fill",
                    label: "Streak",
                    value: stats.streakDays == 1 ? "1 day" : "\(stats.streakDays) days",
                    tint: .orange
                )
                Spacer()
                StatPill(
                    icon: "tray.full.fill",
                    label: "Due",
                    value: "\(stats.dueNow)",
                    tint: .blue
                )
                Spacer()
                StatPill(
                    icon: "brain.head.profile",
                    label: "Retention",
                    value: stats.retentionPercent.map { "\($0)%" } ?? "—",
                    tint: .mint
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * memoryProgress)
                    }
                }
                .frame(height: 8)

                Text(memoryCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var memoryProgress: Double {
        guard stats.trackedCards > 0 else { return 0 }
        return Double(stats.knownCards) / Double(stats.trackedCards)
    }

    private var memoryCaption: String {
        guard stats.trackedCards > 0 else {
            return "Answer questions to start building memory"
        }
        return "\(stats.knownCards) of \(stats.trackedCards) cards in long-term memory"
    }
}

private struct StatPill: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.headline)
        }
    }
}

// MARK: - Review

private struct ReviewNowSection: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review now")
                .font(.headline)

            HStack(spacing: 14) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Categories

private struct CourseCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String

    static let all: [CourseCategory] = [
        CourseCategory(id: "all", title: "All", icon: "square.grid.2x2"),
        CourseCategory(id: "languages", title: "Languages", icon: "character.bubble"),
        CourseCategory(id: "history", title: "History", icon: "building.columns"),
        CourseCategory(id: "science", title: "Science", icon: "atom"),
        CourseCategory(id: "geography", title: "Geography", icon: "globe.americas"),
        CourseCategory(id: "arts", title: "Arts", icon: "paintpalette"),
        CourseCategory(id: "math", title: "Math", icon: "function"),
    ]
}

private struct CategoryFilterBar: View {
    let categories: [CourseCategory]
    @Binding var selectedID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Explore")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(categories) { category in
                        CategoryChip(
                            category: category,
                            isSelected: category.id == selectedID
                        ) {
                            selectedID = category.id
                        }
                    }
                }
            }
        }
    }
}

private struct CategoryChip: View {
    let category: CourseCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(category.title, systemImage: category.icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Courses grid

private struct CoursesGrid: View {
    let courses: [Course]
    let dueByCourse: [UUID: Int]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(courses) { course in
                NavigationLink {
                    CourseDetailView(course: course)
                } label: {
                    CourseGridCard(course: course, dueCount: dueByCourse[course.id] ?? 0)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CourseGridCard: View {
    let course: Course
    let dueCount: Int

    private static let icons = [
        "building.columns.fill", "globe.europe.africa.fill", "flask.fill",
        "paintpalette.fill", "map.fill", "function", "book.fill",
        "leaf.fill", "atom", "scroll.fill",
    ]
    private static let tints: [Color] = [
        .orange, .red, .blue, .green, .purple, .pink, .teal, .indigo, .brown, .cyan,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                artwork
                Spacer()
                if dueCount > 0 {
                    Text("\(dueCount) due")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            Text(course.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)

            Text(cardCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var artwork: some View {
        if let cover = course.coverImageUrl, let url = URL(string: cover) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                iconTile
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            iconTile
        }
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.18))
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
        }
        .frame(width: 48, height: 48)
    }

    // Deterministic per-course styling until courses carry category art.
    private var styleIndex: Int {
        abs(course.id.uuidString.hashValue)
    }

    private var icon: String {
        Self.icons[styleIndex % Self.icons.count]
    }

    private var tint: Color {
        Self.tints[styleIndex % Self.tints.count]
    }

    private var cardCountLabel: String {
        let count = course.questionCount
        return count == 1 ? "1 card" : "\(count) cards"
    }
}

#Preview {
    HomeView()
        .environment(AuthManager(client: SupabaseManager.shared))
        .environment(CourseStore())
}

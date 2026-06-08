//
//  HomeView.swift
//  Aretay
//

import SwiftUI

struct HomeView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(CourseStore.self) private var courseStore

    var body: some View {
        NavigationStack {
            Group {
                if courseStore.isLoading && courseStore.courses.isEmpty {
                    ProgressView("Loading courses…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = courseStore.errorMessage, courseStore.courses.isEmpty {
                    ContentUnavailableView {
                        Label("Could not load courses", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            Task { await courseStore.loadCourses() }
                        }
                    }
                } else if courseStore.courses.isEmpty {
                    ContentUnavailableView(
                        "No courses yet",
                        systemImage: "books.vertical",
                        description: Text("Only public courses are shown. Sign in with Apple, or ask an admin to publish a course.")
                    )
                } else {
                    List(courseStore.courses) { course in
                        NavigationLink {
                            CourseDetailView(course: course)
                        } label: {
                            CourseRow(course: course)
                        }
                    }
                    .refreshable {
                        await courseStore.loadCourses()
                    }
                }
            }
            .navigationTitle("Courses")
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
                guard auth.sessionLoadID != nil else { return }
                await courseStore.loadCourses()
            }
        }
    }
}

private struct CourseRow: View {
    let course: Course

    var body: some View {
        HStack(spacing: 12) {
            CourseCoverImage(urlString: course.coverImageUrl)

            VStack(alignment: .leading, spacing: 4) {
                Text(course.title)
                    .font(.headline)
                    .lineLimit(2)

                if let description = course.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(lessonLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var lessonLabel: String {
        let count = course.lessonCount
        return count == 1 ? "1 lesson" : "\(count) lessons"
    }
}

private struct CourseCoverImage: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemFill))
            Image(systemName: "book.closed")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    HomeView()
        .environment(AuthManager(client: SupabaseManager.shared))
        .environment(CourseStore())
}

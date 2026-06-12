//
//  ExploreCategories.swift
//  Aretay
//
//  Course category filter chips, shared by the home page's Explore section
//  and the full Explore catalog. Chips are generated from the tags actually
//  present on live courses. Tags come from the curriculum model against a
//  fixed taxonomy owned by the admin (aretay-admin/lib/tags.ts); unknown
//  slugs still render with a fallback title/icon, so new taxonomy entries
//  need no app update.
//

import SwiftUI

struct ExploreCategory: Identifiable, Hashable {
    let id: String   // tag slug, or "forYou"
    let title: String
    let icon: String

    /// Default chip — shows every course.
    static let forYou = ExploreCategory(id: "forYou", title: "For You", icon: "star.fill")

    /// Display metadata for the known taxonomy slugs.
    private static let knownTags: [String: (title: String, icon: String)] = [
        "history": ("History", "building.columns"),
        "science": ("Science", "flask"),
        "math": ("Math", "function"),
        "technology": ("Tech", "display"),
        "language": ("Languages", "globe"),
        "arts": ("Arts", "paintpalette"),
        "literature": ("Literature", "text.book.closed"),
        "philosophy": ("Philosophy", "brain.head.profile"),
        "geography": ("Geography", "map"),
        "space": ("Space", "moon.stars"),
        "nature": ("Nature", "leaf"),
        "health": ("Health", "heart"),
        "psychology": ("Psychology", "brain"),
        "business": ("Business", "briefcase"),
        "economics": ("Economics", "chart.line.uptrend.xyaxis"),
        "politics": ("Politics", "checkmark.seal"),
        "religion": ("Religion", "books.vertical"),
        "music": ("Music", "music.note"),
        "sports": ("Sports", "figure.run"),
        "food": ("Food", "fork.knife"),
    ]

    static func category(forTag slug: String) -> ExploreCategory {
        if let known = knownTags[slug] {
            return ExploreCategory(id: slug, title: known.title, icon: known.icon)
        }
        return ExploreCategory(id: slug, title: slug.capitalized, icon: "tag")
    }

    /// "For You" plus a chip per tag in the catalog, most common first.
    static func available(for courses: [Course]) -> [ExploreCategory] {
        var counts: [String: Int] = [:]
        for course in courses {
            for slug in course.tags {
                counts[slug, default: 0] += 1
            }
        }
        let ordered = counts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }
        return [.forYou] + ordered.map { category(forTag: $0.key) }
    }

    func matches(_ course: Course) -> Bool {
        id == Self.forYou.id || course.tags.contains(id)
    }
}

struct ExploreCategoryChip: View {
    let category: ExploreCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption)
                Text(category.title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.15)
                    : Color(.secondarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exploreCategory_\(category.id)")
    }
}

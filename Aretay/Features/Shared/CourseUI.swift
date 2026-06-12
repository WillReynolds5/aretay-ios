//
//  CourseUI.swift
//  Aretay
//
//  Shared course UI pieces used by the home page and course list:
//  cover artwork (with deterministic icon fallback), the standard
//  progress capsule, and the image-left course progress row.
//

import SwiftUI

// MARK: - Course artwork (cover image with deterministic icon fallback)

struct CourseArtwork: View {
    let course: Course
    /// Fixed square edge; nil = flexible square that fills its container width.
    var size: CGFloat? = nil
    var cornerRadius: CGFloat = 14

    private static let icons = [
        "building.columns.fill", "globe.europe.africa.fill", "flask.fill",
        "paintpalette.fill", "map.fill", "function", "book.fill",
        "leaf.fill", "atom", "scroll.fill",
    ]
    private static let tints: [Color] = [
        .orange, .red, .blue, .green, .purple, .pink, .teal, .indigo, .brown, .cyan,
    ]

    var body: some View {
        container
            .overlay {
                if let cover = course.coverImageUrl, let url = URL(string: cover) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        iconTile
                    }
                } else {
                    iconTile
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    private var container: some View {
        if let size {
            Color.clear.frame(width: size, height: size)
        } else {
            Color.clear.aspectRatio(1, contentMode: .fit)
        }
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(tint.opacity(0.18))
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
        }
    }

    private var styleIndex: Int {
        abs(course.id.uuidString.hashValue)
    }

    private var icon: String {
        Self.icons[styleIndex % Self.icons.count]
    }

    private var tint: Color {
        Self.tints[styleIndex % Self.tints.count]
    }
}

// MARK: - Progress capsule

/// Capsule progress bar. Blue while in progress, green from 60% on
/// (matching the design's "well underway" color shift).
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(ProgressBar.tint(for: value))
                    .frame(width: geometry.size.width * max(0, min(1, value)))
            }
        }
    }

    static func tint(for value: Double) -> Color {
        value >= 0.6 ? .green : .accentColor
    }
}

// MARK: - Course progress row (image left, title + progress, due badge)

struct CourseProgressRow: View {
    let course: Course
    let progress: Double
    let dueCount: Int

    var body: some View {
        HStack(spacing: 14) {
            CourseArtwork(course: course, size: 56, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 8) {
                Text(course.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    ProgressBar(value: progress)
                        .frame(height: 6)
                    Text(progressLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 10) {
                if dueCount > 0 {
                    Text("\(dueCount) due")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var progressLabel: String {
        "\(Int((progress * 100).rounded()))%"
    }
}

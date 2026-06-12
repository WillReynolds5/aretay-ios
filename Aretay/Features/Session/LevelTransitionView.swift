//
//  LevelTransitionView.swift
//  Aretay
//
//  Full-screen black interstitial announcing the next level between
//  lessons. The "LEVEL N" lockup and the lesson title cascade in letter
//  by letter, hold for a beat, then fade back to pure black — at which
//  point the feed switches pages under the cover and fades the next
//  video in from black, so the whole handoff reads as one seamless cut.
//

import SwiftUI

struct LevelTransitionPageView: View {
    let item: LevelTransitionItem
    let isActive: Bool
    let onComplete: () -> Void

    /// Drives the staggered letter intro; never flipped back off —
    /// the outro fades the whole lockup instead.
    @State private var lettersVisible = false
    @State private var contentOpacity: Double = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 22) {
                Text("LEVEL")
                    .font(.subheadline.weight(.semibold))
                    .tracking(lettersVisible ? 8 : 22)
                    .foregroundStyle(.white.opacity(0.55))
                    .opacity(lettersVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.8), value: lettersVisible)

                Text("\(item.levelNumber)")
                    .font(.system(size: 124, weight: .ultraLight, design: .serif))
                    .foregroundStyle(.white)
                    .scaleEffect(lettersVisible ? 1 : 1.35)
                    .blur(radius: lettersVisible ? 0 : 12)
                    .opacity(lettersVisible ? 1 : 0)
                    .animation(.spring(duration: 0.9, bounce: 0.18).delay(0.15), value: lettersVisible)

                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(width: lettersVisible ? 132 : 0, height: 1)
                    .animation(.easeInOut(duration: 0.8).delay(0.45), value: lettersVisible)

                CascadingTitle(text: item.title, visible: lettersVisible, baseDelay: 0.65)
                    .padding(.horizontal, 36)
            }
            .opacity(contentOpacity)
        }
        .task(id: isActive) {
            guard isActive else { return }
            // Beat of pure black while the feed's fade-from-video settles.
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            lettersVisible = true
            // Intro (~1.5s of staggered animation) + hold on the lockup.
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.55)) { contentOpacity = 0 }
            try? await Task.sleep(for: .seconds(0.65))
            guard !Task.isCancelled else { return }
            onComplete()
        }
    }
}

// MARK: - Letter cascade

/// Renders the title with every character animating in individually —
/// rising, unblurring, and fading in with a per-character stagger.
/// Words wrap as units so the cascade survives long titles.
private struct CascadingTitle: View {
    let text: String
    let visible: Bool
    let baseDelay: Double

    private static let characterStagger = 0.035

    var body: some View {
        WrappingWordsLayout(wordSpacing: 9, lineSpacing: 4) {
            ForEach(words) { word in
                HStack(spacing: 0) {
                    ForEach(word.characters) { character in
                        Text(character.value)
                            .opacity(visible ? 1 : 0)
                            .blur(radius: visible ? 0 : 6)
                            .offset(y: visible ? 0 : 18)
                            .animation(
                                .spring(duration: 0.55, bounce: 0.25)
                                    .delay(baseDelay + Double(character.globalIndex) * Self.characterStagger),
                                value: visible
                            )
                    }
                }
            }
        }
        .font(.system(.largeTitle, design: .serif).weight(.semibold))
        .foregroundStyle(.white)
    }

    private struct TitleCharacter: Identifiable {
        let id: Int
        let value: String
        let globalIndex: Int
    }

    private struct TitleWord: Identifiable {
        let id: Int
        let characters: [TitleCharacter]
    }

    private var words: [TitleWord] {
        var globalIndex = 0
        return text.split(separator: " ").enumerated().map { wordIndex, word in
            let characters = word.enumerated().map { characterIndex, character in
                defer { globalIndex += 1 }
                return TitleCharacter(id: characterIndex, value: String(character), globalIndex: globalIndex)
            }
            return TitleWord(id: wordIndex, characters: characters)
        }
    }
}

/// Minimal centered flow layout: lays words out left to right, wraps to a
/// new line when the proposed width runs out, and centers every line.
private struct WrappingWordsLayout: Layout {
    var wordSpacing: CGFloat
    var lineSpacing: CGFloat

    private struct Line {
        var range: Range<Int>
        var width: CGFloat
        var height: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(for: subviews, maxWidth: proposal.width ?? .infinity)
        let height = lines.reduce(0) { $0 + $1.height } + CGFloat(max(0, lines.count - 1)) * lineSpacing
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: min(proposal.width ?? width, width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(for: subviews, maxWidth: bounds.width) {
            var x = bounds.minX + (bounds.width - line.width) / 2
            for index in line.range {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                    proposal: .unspecified
                )
                x += size.width + wordSpacing
            }
            y += line.height + lineSpacing
        }
    }

    private func lines(for subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var start = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let proposed = width == 0 ? size.width : width + wordSpacing + size.width
            if proposed > maxWidth, index > start {
                lines.append(Line(range: start..<index, width: width, height: height))
                start = index
                width = size.width
                height = size.height
            } else {
                width = proposed
                height = max(height, size.height)
            }
        }
        if start < subviews.count {
            lines.append(Line(range: start..<subviews.count, width: width, height: height))
        }
        return lines
    }
}

#Preview {
    LevelTransitionPageView(
        item: LevelTransitionItem(id: UUID(), levelNumber: 1, title: "The Rise of the Greek City-States"),
        isActive: true
    ) {}
}

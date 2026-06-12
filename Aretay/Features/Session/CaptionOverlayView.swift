//
//  CaptionOverlayView.swift
//  Aretay
//
//  TikTok-style word captions over the video, driven by the Whisper
//  word-level tokens on the card.
//
//  Raw Whisper tokens are messy: punctuation arrives as standalone tokens
//  ("," "."), and words can be split into sub-word pieces ("blitz" "k"
//  "rieg"). Whisper's convention is that a token starting with a space
//  begins a new word — anything else continues the previous one. So we
//  merge continuations first, then build short phrase pages that break on
//  sentence ends and long silences. A page stays on screen until the next
//  one starts (no flicker between words), display text is uppercased with
//  terminal commas/periods dropped, and the active word sweeps in yellow.
//

import SwiftUI

struct CaptionOverlayView: View {
    let captions: [CaptionWord]
    let currentTimeMs: Double

    private static let maxWordsPerPage = 4
    /// A silence longer than this starts a fresh page.
    private static let pageGapMs: Double = 800
    /// How long the last page lingers after its final word ends.
    private static let tailMs: Double = 400

    private struct Word {
        var display: String
        var startMs: Double
        var endMs: Double
        var endsSentence: Bool
    }

    private struct Page {
        var words: [Word]
        var startMs: Double
        var endMs: Double
    }

    var body: some View {
        let pages = Self.buildPages(from: captions)
        if let page = pages.first(where: { currentTimeMs >= $0.startMs && currentTimeMs < $0.endMs }) {
            Text(attributedLine(page))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.9), radius: 5, y: 2)
                .padding(.horizontal, 24)
                .transition(.opacity)
        }
    }

    private func attributedLine(_ page: Page) -> AttributedString {
        // The highlight sweeps: the active word is the last one whose start
        // has passed, so it never drops out between words.
        let activeIndex = page.words.lastIndex { currentTimeMs >= $0.startMs }
        var result = AttributedString()
        for (index, word) in page.words.enumerated() {
            var piece = AttributedString(word.display)
            piece.foregroundColor = index == activeIndex ? .yellow : .white
            result += piece
            if index < page.words.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
    }

    // MARK: - Token cleanup + paging

    private static func buildPages(from captions: [CaptionWord]) -> [Page] {
        let words = mergeTokens(captions)
        guard !words.isEmpty else { return [] }

        var groups: [[Word]] = []
        var current: [Word] = []
        for word in words {
            if let last = current.last,
               current.count >= maxWordsPerPage || word.startMs - last.endMs > pageGapMs {
                groups.append(current)
                current = []
            }
            current.append(word)
            if word.endsSentence {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty { groups.append(current) }

        // A page holds until the next one begins — captions never blink off
        // mid-sentence just because there's a beat between words.
        return groups.enumerated().map { index, group in
            let start = group.first!.startMs
            let end = index + 1 < groups.count
                ? groups[index + 1].first!.startMs
                : group.last!.endMs + tailMs
            return Page(words: group, startMs: start, endMs: end)
        }
    }

    /// Collapses raw Whisper tokens into whole words: a token with no
    /// leading space (punctuation, sub-word pieces) joins the previous word.
    private static func mergeTokens(_ captions: [CaptionWord]) -> [Word] {
        var words: [Word] = []

        for token in captions {
            let trimmed = token.text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let continuesPrevious = !token.text.hasPrefix(" ") && !words.isEmpty
            if continuesPrevious {
                words[words.count - 1].display += trimmed
                words[words.count - 1].endMs = max(words[words.count - 1].endMs, token.endMs)
            } else if trimmed.first?.isLetter == true || trimmed.first?.isNumber == true {
                words.append(Word(
                    display: trimmed,
                    startMs: token.startMs,
                    endMs: token.endMs,
                    endsSentence: false
                ))
            }
            // else: orphan punctuation with nothing to attach to — dropped.
        }

        for index in words.indices {
            let text = words[index].display
            words[index].endsSentence =
                text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?")
            // Viral-caption styling: caps, no commas/periods. ? and ! keep
            // their energy.
            words[index].display = text
                .uppercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        }

        return words.filter { !$0.display.isEmpty }
    }
}

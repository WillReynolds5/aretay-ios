//
//  CaptionOverlayView.swift
//  Aretay
//
//  TikTok-style word captions over the video, driven by the Whisper
//  word-level tokens on the card. Words are grouped into short lines; the
//  line whose time window contains the playhead is shown with the active
//  word highlighted.
//

import SwiftUI

struct CaptionOverlayView: View {
    let captions: [CaptionWord]
    let currentTimeMs: Double

    private static let wordsPerLine = 4

    private var lines: [[CaptionWord]] {
        stride(from: 0, to: captions.count, by: Self.wordsPerLine).map {
            Array(captions[$0 ..< min($0 + Self.wordsPerLine, captions.count)])
        }
    }

    private var activeLine: [CaptionWord]? {
        lines.first { line in
            guard let first = line.first, let last = line.last else { return false }
            return currentTimeMs >= first.startMs && currentTimeMs <= last.endMs
        }
    }

    var body: some View {
        if let line = activeLine {
            Text(attributedLine(line))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.8), radius: 4, y: 2)
                .padding(.horizontal, 24)
                .transition(.opacity)
        }
    }

    private func attributedLine(_ line: [CaptionWord]) -> AttributedString {
        var result = AttributedString()
        for (index, word) in line.enumerated() {
            var piece = AttributedString(word.text.trimmingCharacters(in: .whitespaces))
            let isActive = currentTimeMs >= word.startMs && currentTimeMs <= word.endMs
            piece.foregroundColor = isActive ? .yellow : .white
            result += piece
            if index < line.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
    }
}

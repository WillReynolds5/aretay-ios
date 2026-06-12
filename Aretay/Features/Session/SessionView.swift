//
//  SessionView.swift
//  Aretay
//
//  Full-screen study session as a TikTok-style vertical feed: every queue
//  item is a full-screen page. The engine drives the scroll position —
//  segment videos auto-swipe up when they finish; question pages loop their
//  clip and hold until an answer lands, animate the verdict, then advance.
//  SessionFeedPolicy keeps swiping behavior configurable (manual swiping is
//  off for now, but the feed is a real pager underneath).
//

import SwiftUI

/// Knobs for how the feed advances. Defaults = forced linear watch-through.
struct SessionFeedPolicy: Sendable {
    /// Allow the user to swipe between pages themselves (future).
    var allowsManualSwipe = false
    /// Auto-swipe to the next page when a segment video finishes.
    var autoAdvanceSegments = true
    /// Beat after a segment's last frame before the swipe (seconds).
    var segmentEndDelay: Double = 0.6
    /// How long the right/wrong verdict stays on screen before the swipe.
    var answerHoldSeconds: Double = 2.0
}

struct SessionView: View {
    let course: Course

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var engine: SessionEngine?
    @State private var loadError: String?

    private let policy = SessionFeedPolicy()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let engine {
                if engine.isFinished {
                    SessionSummaryView(summary: engine.summary) { dismiss() }
                } else {
                    SessionFeedView(engine: engine, policy: policy)
                }
            } else if let loadError {
                ContentUnavailableView {
                    Label("Couldn't start session", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Close") { dismiss() }
                }
                .foregroundStyle(.white)
            } else {
                ProgressView("Preparing session…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                ZStack {
                    // Which course this session belongs to. Will matter even
                    // more once the default Review feed mixes courses.
                    CourseBadge(title: course.title)

                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                        .accessibilityIdentifier("closeSession")
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)

                if let engine, !engine.isFinished {
                    ProgressView(value: engine.progress)
                        .tint(.white)
                        .padding(.horizontal, 16)
                }
                Spacer()
            }
        }
        .statusBarHidden()
        .task { await load() }
    }

    private func load() async {
        guard engine == nil else { return }
        guard let token = auth.accessToken, let userId = auth.userID else {
            loadError = "You need to be signed in."
            return
        }
        do {
            async let cards = StudyAPI.fetchCards(courseId: course.id, accessToken: token)
            async let enrollment = StudyAPI.fetchEnrollment(courseId: course.id, accessToken: token)
            async let states = StudyAPI.fetchCardStates(courseId: course.id, accessToken: token)
            let built = SessionEngine(
                course: course,
                cards: try await cards,
                enrollment: try await enrollment,
                cardStates: try await states,
                userId: userId,
                accessToken: token
            )
            if built.queue.isEmpty {
                loadError = "Nothing to study yet — this course has no produced videos."
            } else {
                engine = built
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Course badge

/// Small top-center pill naming the course the current session is scoped to.
private struct CourseBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.35), in: Capsule())
            .frame(maxWidth: 220)
            .accessibilityIdentifier("sessionCourseBadge")
    }
}

// MARK: - Vertical paging feed

private struct SessionFeedView: View {
    let engine: SessionEngine
    let policy: SessionFeedPolicy

    @State private var scrolledID: UUID?
    /// Cover used to fade through black around level transitions instead of
    /// the usual scroll animation — page switches happen underneath it.
    @State private var blackout: Double = 0

    var body: some View {
        ZStack {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(engine.queue) { item in
                        SessionPageView(
                            item: item,
                            isActive: item.id == engine.currentItem?.id,
                            engine: engine,
                            policy: policy
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledID)
            .scrollDisabled(!policy.allowsManualSwipe)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()

            Color.black
                .ignoresSafeArea()
                .opacity(blackout)
                .allowsHitTesting(false)
        }
        .onAppear { scrolledID = engine.currentItem?.id }
        .onChange(of: engine.currentIndex) { oldIndex, newIndex in
            advancePage(from: item(at: oldIndex), to: item(at: newIndex))
        }
    }

    private func item(at index: Int) -> SessionItem? {
        engine.queue.indices.contains(index) ? engine.queue[index] : nil
    }

    private func advancePage(from: SessionItem?, to: SessionItem?) {
        if to?.isTransition == true {
            // Fade the finished video down to black, then switch pages under
            // the cover — the interstitial underneath is pure black, so
            // dropping the cover afterwards is invisible.
            withAnimation(.easeInOut(duration: 0.45)) { blackout = 1 }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                scrolledID = engine.currentItem?.id
                try? await Task.sleep(for: .seconds(0.05))
                blackout = 0
            }
        } else if from?.isTransition == true {
            // The interstitial already faded its letters out, so the screen
            // is black: switch instantly and fade the video in from black.
            blackout = 1
            scrolledID = engine.currentItem?.id
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) { blackout = 0 }
        } else {
            withAnimation(.spring(duration: 0.5)) { scrolledID = engine.currentItem?.id }
        }
    }
}

private struct SessionPageView: View {
    let item: SessionItem
    let isActive: Bool
    let engine: SessionEngine
    let policy: SessionFeedPolicy

    var body: some View {
        switch item {
        case .segment(let segment):
            SegmentPageView(item: segment, isActive: isActive, policy: policy) {
                engine.completeCurrentSegment()
            }
        case .question(let question):
            QuestionPageView(item: question, isActive: isActive, policy: policy) { chosen, durationMs in
                engine.answerCurrentQuestion(chosen: chosen, durationMs: durationMs)
            } onAdvance: {
                engine.advance()
            }
        case .transition(let transition):
            LevelTransitionPageView(item: transition, isActive: isActive) {
                engine.advance()
            }
        }
    }
}

// MARK: - Segment page

private struct SegmentPageView: View {
    let item: SegmentItem
    let isActive: Bool
    let policy: SessionFeedPolicy
    let onComplete: () -> Void

    @State private var controller = PlayerController()

    private var showsVideo: Bool {
        item.videoURL != nil && !controller.didFail
    }

    var body: some View {
        ZStack {
            if showsVideo {
                VideoSurface(player: controller.player)
                    .ignoresSafeArea()
            } else {
                ScriptFallbackView(title: item.title, script: item.script)
            }

            VStack {
                Spacer()
                CaptionOverlayView(captions: item.captions, currentTimeMs: controller.currentTimeMs)
                    .padding(.bottom, 110)
            }

            // No video to time the page by — let the user move on themselves.
            if !showsVideo {
                VStack {
                    Spacer()
                    Button {
                        guard isActive else { return }
                        onComplete()
                    } label: {
                        Label("Continue", systemImage: "arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .accessibilityIdentifier("continueSegment")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .onChange(of: isActive, initial: true) { _, active in
            guard let url = item.videoURL else { return }
            if active {
                controller.load(url: url)
            } else {
                controller.pause()
            }
        }
        .task(id: controller.didFinish) {
            // Auto-swipe up once the video has played through.
            guard controller.didFinish, isActive, policy.autoAdvanceSegments else { return }
            try? await Task.sleep(for: .seconds(policy.segmentEndDelay))
            guard !Task.isCancelled else { return }
            onComplete()
        }
        .onDisappear { controller.stop() }
    }
}

/// Shown when a segment has no playable video (not produced, or load failed).
private struct ScriptFallbackView: View {
    let title: String
    let script: String

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title2.bold())
            Text(script)
                .font(.title3)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

// MARK: - Question page

private struct QuestionPageView: View {
    let item: QuestionItem
    let isActive: Bool
    let policy: SessionFeedPolicy
    /// Returns whether the chosen answer was correct.
    let onAnswer: (String, Int?) -> Bool
    let onAdvance: () -> Void

    @State private var controller = PlayerController()
    @State private var chosen: String?
    @State private var wasCorrect = false
    @State private var shownAt = Date.now

    var body: some View {
        ZStack {
            if item.videoURL != nil && !controller.didFail {
                VideoSurface(player: controller.player)
                    .ignoresSafeArea()
            } else {
                LinearGradient(colors: [.teal, .black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }

            // Dim the lower half so the options read over any video frame.
            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                if chosen != nil {
                    VerdictBanner(correct: wasCorrect)
                        .padding(.bottom, 14)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(item.question)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)

                    ForEach(item.options, id: \.self) { option in
                        AnswerOptionButton(
                            text: option,
                            state: optionState(for: option)
                        ) {
                            guard isActive, chosen == nil else { return }
                            let durationMs = Int(Date.now.timeIntervalSince(shownAt) * 1000)
                            withAnimation(.spring(duration: 0.3)) {
                                chosen = option
                                wasCorrect = onAnswer(option, durationMs)
                            }
                            UINotificationFeedbackGenerator()
                                .notificationOccurred(wasCorrect ? .success : .error)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                shownAt = .now
                if let url = item.videoURL {
                    controller.load(url: url, loop: true)
                }
            } else {
                controller.pause()
            }
        }
        .task(id: chosen) {
            // Hold the verdict on screen, then swipe to the next page.
            guard chosen != nil, isActive else { return }
            try? await Task.sleep(for: .seconds(policy.answerHoldSeconds))
            guard !Task.isCancelled else { return }
            onAdvance()
        }
        .onDisappear { controller.stop() }
    }

    private func optionState(for option: String) -> AnswerOptionButton.Status {
        guard let chosen else { return .idle }
        if option == item.answer { return .correct }
        if option == chosen { return .wrong }
        return .dimmed
    }
}

private struct VerdictBanner: View {
    let correct: Bool

    var body: some View {
        Label(
            correct ? "Correct!" : "You'll see this again",
            systemImage: correct ? "checkmark.circle.fill" : "arrow.clockwise.circle.fill"
        )
        .font(.headline)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(correct ? Color.green : Color.red, in: Capsule())
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
    }
}

private struct AnswerOptionButton: View {
    enum Status {
        case idle
        case correct
        case wrong
        case dimmed
    }

    let text: String
    let state: Status
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.title3)
                    .multilineTextAlignment(.leading)
                Spacer()
                switch state {
                case .correct:
                    Image(systemName: "checkmark.circle.fill")
                case .wrong:
                    Image(systemName: "xmark.circle.fill")
                case .idle, .dimmed:
                    EmptyView()
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 18)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16)
                switch state {
                case .idle, .dimmed:
                    // Frosted dark row over the looping video.
                    shape.fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                case .correct:
                    shape.fill(Color.green.opacity(0.85))
                case .wrong:
                    shape.fill(Color.red.opacity(0.85))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            )
            .foregroundStyle(.white)
            .opacity(state == .dimmed ? 0.45 : 1)
            .scaleEffect(state == .correct || state == .wrong ? 1.03 : 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Summary

private struct SessionSummaryView: View {
    let summary: SessionSummary
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Session complete")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            VStack(spacing: 10) {
                SummaryRow(label: "Videos watched", value: summary.segmentsWatched)
                SummaryRow(label: "Questions answered", value: summary.questionsAnswered)
                SummaryRow(label: "Correct", value: summary.correct)
                SummaryRow(label: "Reviews cleared", value: summary.reviewsCompleted)
            }
            .padding(24)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))

            Button {
                onDone()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
                    .foregroundStyle(.black)
            }
            .accessibilityIdentifier("sessionDone")
        }
        .padding(32)
    }
}

private struct SummaryRow: View {
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.white)
            Spacer()
            Text("\(value)")
                .font(.headline)
                .foregroundStyle(.white)
        }
    }
}

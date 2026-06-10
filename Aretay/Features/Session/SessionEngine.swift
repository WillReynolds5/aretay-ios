//
//  SessionEngine.swift
//  Aretay
//
//  Builds and runs one study session for a course:
//
//    1. Due reviews first (cards whose FSRS due ≤ now), capped, oldest first.
//    2. New content: the next `new_segments_per_session` segments past the
//       enrollment cursor — each segment video followed by its questions.
//    3. Due reviews are interleaved around the new-segment blocks so a
//       session feels like review → video → questions → review → …
//
//  Answers run through the binary FSRS scheduler; wrong answers requeue at
//  the end of the session. Every answer is persisted incrementally (card
//  state upsert + review log insert), so quitting mid-session loses nothing.
//

import Foundation
import Observation

@MainActor
@Observable
final class SessionEngine {
    static let maxReviewsPerSession = 20

    private(set) var queue: [SessionItem] = []
    private(set) var currentIndex = 0
    private(set) var summary = SessionSummary()
    private(set) var isFinished = false
    var persistenceError: String?

    private let course: Course
    private let userId: UUID
    private let accessToken: String
    private let scheduler: FSRSScheduler
    private var enrollment: Enrollment
    private var enrollmentPersisted: Bool
    /// Latest known FSRS state per card id, updated as answers land.
    private var stateByCardId: [UUID: CardState]
    /// Position of every segment key in the linear course order.
    private var segmentOrder: [String: Int] = [:]
    private var questionsBySegmentKey: [String: [QuestionItem]] = [:]

    var currentItem: SessionItem? {
        guard currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    var progress: Double {
        guard !queue.isEmpty else { return 0 }
        return Double(currentIndex) / Double(queue.count)
    }

    // MARK: - Setup

    init(
        course: Course,
        cards: [Card],
        enrollment: Enrollment?,
        cardStates: [CardState],
        userId: UUID,
        accessToken: String,
        now: Date = .now
    ) {
        self.course = course
        self.userId = userId
        self.accessToken = accessToken
        self.enrollmentPersisted = enrollment != nil
        let enrollment = enrollment ?? Enrollment(
            id: UUID(),
            userId: userId,
            courseId: course.id,
            cursorSegmentKey: nil,
            segmentsCompleted: 0,
            desiredRetention: 0.9,
            newSegmentsPerSession: 2,
            lastStudiedAt: nil
        )
        self.enrollment = enrollment
        self.scheduler = FSRSScheduler(desiredRetention: enrollment.desiredRetention)
        self.stateByCardId = Dictionary(uniqueKeysWithValues: cardStates.map { ($0.cardId, $0) })
        self.queue = []
        buildQueue(cards: cards, now: now)
        isFinished = queue.isEmpty
    }

    private func buildQueue(cards: [Card], now: Date) {
        guard let curriculum = course.curriculum else { return }
        let cardsByKey = Dictionary(
            uniqueKeysWithValues: cards.compactMap { card in card.segmentKey.map { ($0, card) } }
        )

        // Linear content walk: intro, then every lesson segment in order.
        var segments: [SegmentItem] = []
        var contentOrder: [(key: String, title: String, script: String, questions: [(key: String, question: CurriculumQuestion)])] = []

        if let intro = curriculum.intro {
            contentOrder.append((SegmentKey.intro, "Introduction", intro.script, []))
        }
        for lesson in curriculum.orderedLessons {
            for segment in lesson.segments.sorted(by: { $0.segmentNumber < $1.segmentNumber }) {
                let key = SegmentKey.lessonSegment(lessonOrder: lesson.order, segmentNumber: segment.segmentNumber)
                let questions = segment.questions.enumerated().map { index, question in
                    (SegmentKey.question(
                        lessonOrder: lesson.order,
                        segmentNumber: segment.segmentNumber,
                        questionIndex: index
                    ), question)
                }
                contentOrder.append((key, lesson.unitTitle, segment.script, questions))
            }
        }

        var questionByKey: [String: QuestionItem] = [:]
        var questionKeyByCardId: [UUID: String] = [:]

        for (index, content) in contentOrder.enumerated() {
            segmentOrder[content.key] = index
            let card = cardsByKey[content.key]
            segments.append(SegmentItem(
                id: UUID(),
                segmentKey: content.key,
                title: content.title,
                script: card?.metadata?.production?.finalScript ?? content.script,
                videoURL: card?.videoURL,
                captions: card?.captions ?? [],
                advancesCursor: true
            ))

            var items: [QuestionItem] = []
            for (key, question) in content.questions {
                // A question is only reviewable once the generator made a card
                // row for it — that row's id anchors the per-user FSRS state.
                guard let questionCard = cardsByKey[key] else { continue }
                let alternates = questionCard.metadata?.production?.altAnswers ?? []
                let options = ([question.answer] + Array(alternates.shuffled().prefix(3))).shuffled()
                let item = QuestionItem(
                    id: UUID(),
                    questionKey: key,
                    cardId: questionCard.id,
                    question: question.question,
                    answer: question.answer,
                    options: options,
                    videoURL: questionCard.videoURL,
                    captions: questionCard.captions ?? [],
                    isRequeue: false
                )
                items.append(item)
                questionByKey[key] = item
                questionKeyByCardId[questionCard.id] = key
            }
            questionsBySegmentKey[content.key] = items
        }

        // 1. Due reviews: any tracked card whose due time has arrived,
        //    including 'new' states (segment watched but never answered).
        let dueReviews: [QuestionItem] = stateByCardId.values
            .filter { $0.due <= now }
            .sorted { $0.due < $1.due }
            .prefix(Self.maxReviewsPerSession)
            .compactMap { state in
                questionKeyByCardId[state.cardId].flatMap { questionByKey[$0] }
            }

        // 2. New content: next segments past the cursor that actually have video.
        let cursorIndex = enrollment.cursorSegmentKey.flatMap { segmentOrder[$0] } ?? -1
        var newBlocks: [[SessionItem]] = []
        for segment in segments.dropFirst(cursorIndex + 1) where segment.videoURL != nil {
            guard newBlocks.count < enrollment.newSegmentsPerSession else { break }
            let alreadyDue = Set(dueReviews.map(\.cardId))
            let freshQuestions = (questionsBySegmentKey[segment.segmentKey] ?? [])
                .filter { !alreadyDue.contains($0.cardId) }
            newBlocks.append([.segment(segment)] + freshQuestions.map { .question($0) })
        }

        // 3. Interleave: half the reviews up front, the rest spread between blocks.
        var reviews = dueReviews.map { SessionItem.question($0) }
        var built: [SessionItem] = []
        if newBlocks.isEmpty {
            built = reviews
        } else {
            let upFront = (reviews.count + 1) / 2
            built.append(contentsOf: reviews.prefix(upFront))
            reviews.removeFirst(upFront)
            let perBlock = newBlocks.isEmpty ? 0 : Int(ceil(Double(reviews.count) / Double(newBlocks.count)))
            for block in newBlocks {
                built.append(contentsOf: block)
                let chunk = reviews.prefix(perBlock)
                built.append(contentsOf: chunk)
                reviews.removeFirst(chunk.count)
            }
            built.append(contentsOf: reviews)
        }
        queue = built
    }

    // MARK: - Advancing

    func completeCurrentSegment() {
        guard case .segment(let segment) = currentItem else { return }
        summary.segmentsWatched += 1

        // Advance the cursor only forward — rewatching never moves it back.
        let position = segmentOrder[segment.segmentKey] ?? -1
        let cursorPosition = enrollment.cursorSegmentKey.flatMap { segmentOrder[$0] } ?? -1
        if position > cursorPosition {
            enrollment.cursorSegmentKey = segment.segmentKey
            enrollment.segmentsCompleted += 1
        }
        enrollment.lastStudiedAt = .now
        enrollmentPersisted = true
        let snapshot = enrollment

        // Register the segment's questions as 'new' cards so they survive a
        // quit-before-answering: they'll surface as due in the next session.
        var freshStates: [CardState] = []
        for question in questionsBySegmentKey[segment.segmentKey] ?? [] where stateByCardId[question.cardId] == nil {
            let state = CardState.newCard(userId: userId, cardId: question.cardId, courseId: course.id)
            stateByCardId[question.cardId] = state
            freshStates.append(state)
        }

        let statesSnapshot = freshStates
        persist { token in
            try await StudyAPI.upsertEnrollment(snapshot, accessToken: token)
            try await StudyAPI.upsertCardStates(statesSnapshot, accessToken: token)
        }
        advance()
    }

    /// Records a multiple-choice answer. Returns whether it was correct.
    @discardableResult
    func answerCurrentQuestion(chosen: String, durationMs: Int?) -> Bool {
        guard case .question(let item) = currentItem else { return false }
        let correct = chosen == item.answer
        let rating: FSRSRating = correct ? .good : .again
        let now = Date.now

        let previous = stateByCardId[item.cardId]
            ?? CardState.newCard(userId: userId, cardId: item.cardId, courseId: course.id, now: now)
        let wasReview = previous.state == .review

        let outcome = scheduler.review(
            state: previous.state,
            stability: previous.stability,
            difficulty: previous.difficulty,
            lastReviewedAt: previous.lastReviewedAt,
            rating: rating,
            now: now
        )

        var next = previous
        next.state = outcome.state
        next.due = outcome.due
        next.stability = outcome.stability
        next.difficulty = outcome.difficulty
        next.reps += 1
        if !correct && wasReview { next.lapses += 1 }
        next.lastReviewedAt = now
        next.scheduler = FSRSScheduler.schedulerID
        stateByCardId[item.cardId] = next

        summary.questionsAnswered += 1
        if correct { summary.correct += 1 }
        if wasReview { summary.reviewsCompleted += 1 }

        let log = ReviewLogInsert(
            cardStateId: next.id,
            userId: userId,
            rating: rating.rawValue,
            chosenAnswer: chosen,
            stateBefore: previous.state.rawValue,
            stabilityBefore: previous.stability,
            difficultyBefore: previous.difficulty,
            elapsedDays: outcome.elapsedDays,
            stabilityAfter: outcome.stability,
            difficultyAfter: outcome.difficulty,
            dueAfter: outcome.due,
            durationMs: durationMs
        )
        let stateSnapshot = next
        persist { token in
            try await StudyAPI.upsertCardStates([stateSnapshot], accessToken: token)
            try await StudyAPI.insertReviewLog(log, accessToken: token)
        }

        // Wrong answers get another shot before the session ends.
        if !correct {
            queue.append(.question(item.requeued()))
        }
        return correct
    }

    func advance() {
        guard currentIndex < queue.count else { return }
        currentIndex += 1
        if currentIndex >= queue.count {
            finishSession()
        }
    }

    private func finishSession() {
        isFinished = true
        guard enrollmentPersisted else { return } // nothing studied → don't create a row
        enrollment.lastStudiedAt = .now
        let snapshot = enrollment
        persist { token in
            try await StudyAPI.upsertEnrollment(snapshot, accessToken: token)
        }
    }

    // MARK: - Persistence

    private func persist(_ operation: @escaping @Sendable (String) async throws -> Void) {
        let token = accessToken
        Task { [weak self] in
            do {
                try await operation(token)
            } catch {
                self?.persistenceError = error.localizedDescription
            }
        }
    }
}

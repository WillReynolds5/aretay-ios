//
//  FSRS.swift
//  Aretay
//
//  FSRS-5 scheduler restricted to binary grading: a correct multiple-choice
//  answer maps to Good (3), an incorrect one to Again (1). Hard/Easy are
//  never emitted, which is a supported degenerate case of FSRS — the default
//  weights apply unchanged and the unused grade parameters simply never fire.
//
//  Reference: https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm
//

import Foundation

enum FSRSRating: Int, Sendable {
    case again = 1 // wrong
    case good = 3  // right
}

enum FSRSState: String, Codable, Sendable {
    case new
    case learning
    case review
    case relearning
}

/// The scheduler's verdict for one answer.
struct FSRSOutcome: Sendable {
    let state: FSRSState
    let stability: Double
    let difficulty: Double
    let due: Date
    /// Days since the previous review (0 for the first), logged for parameter fitting.
    let elapsedDays: Double
}

struct FSRSScheduler: Sendable {
    /// Stamped onto card_states.scheduler so a future algorithm can migrate state.
    static let schedulerID = "fsrs5-binary"

    /// FSRS-5 default weights (w0…w18).
    static let defaultWeights: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046,
        1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315,
        2.9898, 0.51655, 0.6621,
    ]

    private static let decay = -0.5
    private static let factor: Double = pow(0.9, 1 / decay) - 1 // 19/81

    /// Wrong answers come back after this many minutes (learning/relearning step).
    static let learningStepMinutes: Double = 10

    let weights: [Double]
    let desiredRetention: Double
    let maximumIntervalDays: Double

    init(
        weights: [Double] = FSRSScheduler.defaultWeights,
        desiredRetention: Double = 0.9,
        maximumIntervalDays: Double = 365
    ) {
        self.weights = weights
        self.desiredRetention = desiredRetention
        self.maximumIntervalDays = maximumIntervalDays
    }

    // MARK: - Public API

    /// Apply one binary answer to a card's current memory state.
    func review(
        state: FSRSState,
        stability: Double?,
        difficulty: Double?,
        lastReviewedAt: Date?,
        rating: FSRSRating,
        now: Date = .now
    ) -> FSRSOutcome {
        let elapsedDays = max(0, lastReviewedAt.map { now.timeIntervalSince($0) / 86_400 } ?? 0)

        switch state {
        case .new:
            return firstReview(rating: rating, now: now)

        case .learning, .relearning:
            // Same-day step: stability moves via the short-term formula.
            let s = shortTermStability(stability: stability ?? initialStability(for: rating), rating: rating)
            let d = clampDifficulty(difficulty ?? initialDifficulty(for: rating))
            switch rating {
            case .good:
                return graduate(stability: s, difficulty: d, state: .review, now: now, elapsedDays: elapsedDays)
            case .again:
                return step(stability: s, difficulty: d, state: state, now: now, elapsedDays: elapsedDays)
            }

        case .review:
            let s = stability ?? initialStability(for: rating)
            let d = clampDifficulty(difficulty ?? initialDifficulty(for: rating))
            let r = retrievability(elapsedDays: elapsedDays, stability: s)
            let nextD = nextDifficulty(d, rating: rating)
            switch rating {
            case .good:
                let nextS = recallStability(difficulty: d, stability: s, retrievability: r)
                return graduate(stability: nextS, difficulty: nextD, state: .review, now: now, elapsedDays: elapsedDays)
            case .again:
                let nextS = forgetStability(difficulty: d, stability: s, retrievability: r)
                return step(stability: nextS, difficulty: nextD, state: .relearning, now: now, elapsedDays: elapsedDays)
            }
        }
    }

    /// Predicted recall probability after `elapsedDays` for a given stability.
    func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + Self.factor * elapsedDays / stability, Self.decay)
    }

    /// Interval (days) at which retrievability decays to the desired retention.
    func nextIntervalDays(stability: Double) -> Double {
        let raw = stability / Self.factor * (pow(desiredRetention, 1 / Self.decay) - 1)
        return min(max(raw.rounded(), 1), maximumIntervalDays)
    }

    // MARK: - Transitions

    private func firstReview(rating: FSRSRating, now: Date) -> FSRSOutcome {
        let s = initialStability(for: rating)
        let d = initialDifficulty(for: rating)
        switch rating {
        case .good:
            return graduate(stability: s, difficulty: d, state: .review, now: now, elapsedDays: 0)
        case .again:
            return step(stability: s, difficulty: d, state: .learning, now: now, elapsedDays: 0)
        }
    }

    private func graduate(
        stability: Double, difficulty: Double, state: FSRSState, now: Date, elapsedDays: Double
    ) -> FSRSOutcome {
        let interval = nextIntervalDays(stability: stability)
        return FSRSOutcome(
            state: state,
            stability: stability,
            difficulty: difficulty,
            due: now.addingTimeInterval(interval * 86_400),
            elapsedDays: elapsedDays
        )
    }

    private func step(
        stability: Double, difficulty: Double, state: FSRSState, now: Date, elapsedDays: Double
    ) -> FSRSOutcome {
        FSRSOutcome(
            state: state,
            stability: stability,
            difficulty: difficulty,
            due: now.addingTimeInterval(Self.learningStepMinutes * 60),
            elapsedDays: elapsedDays
        )
    }

    // MARK: - FSRS-5 formulas

    private func initialStability(for rating: FSRSRating) -> Double {
        max(weights[rating.rawValue - 1], 0.1)
    }

    private func initialDifficulty(for rating: FSRSRating) -> Double {
        clampDifficulty(weights[4] - exp(weights[5] * Double(rating.rawValue - 1)) + 1)
    }

    private func nextDifficulty(_ difficulty: Double, rating: FSRSRating) -> Double {
        let deltaD = -weights[6] * Double(rating.rawValue - 3)
        let damped = difficulty + deltaD * (10 - difficulty) / 9
        // Mean reversion toward the initial difficulty of an Easy first answer.
        let easyD0 = weights[4] - exp(weights[5] * 3) + 1
        return clampDifficulty(weights[7] * easyD0 + (1 - weights[7]) * damped)
    }

    private func recallStability(difficulty: Double, stability: Double, retrievability: Double) -> Double {
        let growth = exp(weights[8])
            * (11 - difficulty)
            * pow(stability, -weights[9])
            * (exp(weights[10] * (1 - retrievability)) - 1)
        return clampStability(stability * (1 + growth))
    }

    private func forgetStability(difficulty: Double, stability: Double, retrievability: Double) -> Double {
        let s = weights[11]
            * pow(difficulty, -weights[12])
            * (pow(stability + 1, weights[13]) - 1)
            * exp(weights[14] * (1 - retrievability))
        // A lapse can't leave the card more stable than it was.
        return clampStability(min(s, stability))
    }

    private func shortTermStability(stability: Double, rating: FSRSRating) -> Double {
        clampStability(stability * exp(weights[17] * (Double(rating.rawValue) - 3 + weights[18])))
    }

    private func clampDifficulty(_ value: Double) -> Double {
        min(max(value, 1), 10)
    }

    private func clampStability(_ value: Double) -> Double {
        min(max(value, 0.01), 36_500)
    }
}

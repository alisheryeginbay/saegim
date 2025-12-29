//
//  Card.swift
//  saegim
//
//  Flashcard model with FSRS v6 spaced repetition scheduling
//

import Foundation
import SwiftData
import FSRSSwift

/// Card learning state
enum CardState: Int, Codable {
    case new = 0        // Never reviewed
    case learning = 1   // In initial learning phase
    case review = 2     // Graduated to review
    case relearning = 3 // Lapsed, relearning
}

@Model
final class Card {
    var id: UUID
    var front: String
    var back: String
    var createdAt: Date
    var modifiedAt: Date

    // FSRS Memory State
    var stability: Double      // Expected days to reach 90% recall
    var difficulty: Double     // Card difficulty (0.0 - 1.0)
    var state: CardState       // Learning state
    var lapses: Int            // Times forgotten
    var nextReviewDate: Date
    var lastReviewDate: Date?

    // Statistics
    var totalReviews: Int
    var correctReviews: Int

    @Relationship(inverse: \Deck.cards)
    var deck: Deck?

    init(
        front: String,
        back: String,
        deck: Deck? = nil
    ) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.createdAt = Date()
        self.modifiedAt = Date()

        // FSRS defaults for new card
        self.stability = 0
        self.difficulty = 0
        self.state = .new
        self.lapses = 0
        self.nextReviewDate = Date()
        self.lastReviewDate = nil

        // Stats
        self.totalReviews = 0
        self.correctReviews = 0

        self.deck = deck
    }

    /// Get memory state for FSRS (nil for new cards)
    var memoryState: MemoryState? {
        guard state != .new else { return nil }
        return MemoryState(
            stability: Float(stability),
            difficulty: Float(difficulty)
        )
    }

    /// Days elapsed since last review
    var daysSinceLastReview: UInt32 {
        guard let lastReview = lastReviewDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: lastReview, to: Date()).day ?? 0
        return UInt32(max(0, days))
    }

    /// FSRS-based review
    /// - Parameters:
    ///   - rating: User's rating (Again, Hard, Good, Easy)
    ///   - desiredRetention: Target retention probability (default 0.9 = 90%)
    func review(rating: Rating, desiredRetention: Float = 0.9) {
        totalReviews += 1
        modifiedAt = Date()

        do {
            let info = try schedule(
                memory: memoryState,
                rating: rating,
                desiredRetention: desiredRetention,
                daysElapsed: daysSinceLastReview
            )

            // Update memory state
            stability = Double(info.memory.stability)
            difficulty = Double(info.memory.difficulty)

            // Update next review date
            nextReviewDate = Calendar.current.date(
                byAdding: .day,
                value: Int(info.interval),
                to: Date()
            ) ?? Date()
            lastReviewDate = Date()

            // Update state and stats based on rating
            switch rating {
            case .again:
                lapses += 1
                state = state == .new ? .learning : .relearning
            case .hard, .good, .easy:
                correctReviews += 1
                state = .review
            }

        } catch {
            print("FSRS scheduling error: \(error)")
        }
    }

    /// Preview next states for all rating options (for showing intervals on buttons)
    func previewNextStates(desiredRetention: Float = 0.9) -> NextStates? {
        try? FSRSSwift.nextStates(
            memory: memoryState,
            desiredRetention: desiredRetention,
            daysElapsed: daysSinceLastReview
        )
    }

    var isDue: Bool {
        nextReviewDate <= Date()
    }

    /// Current recall probability (0.0-1.0)
    var retrievability: Double {
        guard stability > 0 else { return state == .new ? 0 : 1 }
        return Double(currentRetrievability(
            stability: Float(stability),
            daysElapsed: daysSinceLastReview
        ))
    }

    var successRate: Double {
        guard totalReviews > 0 else { return 0 }
        return Double(correctReviews) / Double(totalReviews)
    }

    var statusColor: String {
        switch state {
        case .new:
            return "blue"
        case .learning, .relearning:
            return "orange"
        case .review:
            return isDue ? "orange" : "green"
        }
    }

    /// Reset card to new state (for fresh start migration)
    func resetForFSRS() {
        stability = 0
        difficulty = 0
        nextReviewDate = Date()
        lastReviewDate = nil
        state = .new
        lapses = 0
        totalReviews = 0
        correctReviews = 0
    }
}

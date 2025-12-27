//
//  Card.swift
//  saegim
//
//  Flashcard model with SM-2 spaced repetition data
//

import Foundation
import SwiftData

@Model
final class Card {
    var id: UUID
    var front: String
    var back: String
    var createdAt: Date
    var modifiedAt: Date

    // SM-2 Algorithm Fields
    var easeFactor: Double  // EF: starts at 2.5
    var interval: Int       // Days until next review
    var repetitions: Int    // Number of successful reviews
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

        // SM-2 defaults
        self.easeFactor = 2.5
        self.interval = 0
        self.repetitions = 0
        self.nextReviewDate = Date()
        self.lastReviewDate = nil

        // Stats
        self.totalReviews = 0
        self.correctReviews = 0

        self.deck = deck
    }

    /// SM-2 Algorithm implementation
    /// Quality: 0-5 (0-2 = fail, 3-5 = pass)
    func review(quality: Int) {
        let q = max(0, min(5, quality))

        totalReviews += 1
        lastReviewDate = Date()
        modifiedAt = Date()

        if q >= 3 {
            // Correct response
            correctReviews += 1

            switch repetitions {
            case 0:
                interval = 1
            case 1:
                interval = 6
            default:
                interval = Int(Double(interval) * easeFactor)
            }
            repetitions += 1
        } else {
            // Incorrect - reset
            repetitions = 0
            interval = 1
        }

        // Update ease factor
        // EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        let efDelta = 0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02)
        easeFactor = max(1.3, easeFactor + efDelta)

        // Set next review date
        nextReviewDate = Calendar.current.date(
            byAdding: .day,
            value: interval,
            to: Date()
        ) ?? Date()
    }

    var isDue: Bool {
        nextReviewDate <= Date()
    }

    var successRate: Double {
        guard totalReviews > 0 else { return 0 }
        return Double(correctReviews) / Double(totalReviews)
    }

    var statusColor: String {
        if repetitions == 0 {
            return "blue"     // New
        } else if isDue {
            return "orange"   // Due for review
        } else {
            return "green"    // Learned
        }
    }
}

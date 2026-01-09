//
//  CardModel.swift
//  saegim
//
//  Plain struct model for flashcards with FSRS v6 scheduling (PowerSync compatible)
//

import Foundation
import FSRSSwift

/// Card learning state
enum CardStateModel: Int, Codable, Sendable {
    case new = 0        // Never reviewed
    case learning = 1   // In initial learning phase
    case review = 2     // Graduated to review
    case relearning = 3 // Lapsed, relearning
}

/// Flashcard model with FSRS v6 spaced repetition scheduling
struct CardModel: Identifiable, Hashable, Sendable {
    let id: UUID
    var userId: UUID
    var deckId: UUID?
    var front: String
    var back: String
    var createdAt: Date
    var modifiedAt: Date

    // FSRS Memory State
    var stability: Double      // Expected days to reach 90% recall
    var difficulty: Double     // Card difficulty (0.0 - 1.0)
    var state: CardStateModel  // Learning state
    var lapses: Int            // Times forgotten
    var nextReviewDate: Date
    var lastReviewDate: Date?

    // Statistics
    var totalReviews: Int
    var correctReviews: Int

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        userId: UUID,
        deckId: UUID? = nil,
        front: String,
        back: String
    ) {
        self.id = id
        self.userId = userId
        self.deckId = deckId
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
    }

    /// Initialize from database row
    init(row: [String: Any]) {
        let dateFormatter = ISO8601DateFormatter()

        self.id = UUID(uuidString: row["id"] as? String ?? "") ?? UUID()
        self.userId = UUID(uuidString: row["user_id"] as? String ?? "") ?? UUID()
        self.deckId = (row["deck_id"] as? String).flatMap { UUID(uuidString: $0) }
        self.front = row["front"] as? String ?? ""
        self.back = row["back"] as? String ?? ""

        // FSRS fields
        self.stability = row["stability"] as? Double ?? 0
        self.difficulty = row["difficulty"] as? Double ?? 0
        self.state = CardStateModel(rawValue: row["state"] as? Int ?? 0) ?? .new
        self.lapses = row["lapses"] as? Int ?? 0
        self.nextReviewDate = (row["next_review_date"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
        self.lastReviewDate = (row["last_review_date"] as? String).flatMap { dateFormatter.date(from: $0) }

        // Stats
        self.totalReviews = row["total_reviews"] as? Int ?? 0
        self.correctReviews = row["correct_reviews"] as? Int ?? 0

        // Timestamps
        self.createdAt = (row["created_at"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
        self.modifiedAt = (row["modified_at"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
    }

    /// Convert to dictionary for database insertion
    func toDict() -> [String: Any?] {
        let dateFormatter = ISO8601DateFormatter()
        return [
            "id": id.uuidString,
            "user_id": userId.uuidString,
            "deck_id": deckId?.uuidString,
            "front": front,
            "back": back,
            "stability": stability,
            "difficulty": difficulty,
            "state": state.rawValue,
            "lapses": lapses,
            "next_review_date": dateFormatter.string(from: nextReviewDate),
            "last_review_date": lastReviewDate.map { dateFormatter.string(from: $0) },
            "total_reviews": totalReviews,
            "correct_reviews": correctReviews,
            "created_at": dateFormatter.string(from: createdAt),
            "modified_at": dateFormatter.string(from: modifiedAt)
        ]
    }

    // MARK: - FSRS Methods

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

    /// FSRS-based review (mutating)
    /// - Parameters:
    ///   - rating: User's rating (Again, Hard, Good, Easy)
    ///   - desiredRetention: Target retention probability (default 0.9 = 90%)
    mutating func review(rating: Rating, desiredRetention: Float = 0.9) {
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

    /// Whether card is due for review
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

    /// Success rate across all reviews
    var successRate: Double {
        guard totalReviews > 0 else { return 0 }
        return Double(correctReviews) / Double(totalReviews)
    }

    /// Color name based on card state
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

    /// Reset card to new state (for fresh start)
    mutating func resetForFSRS() {
        stability = 0
        difficulty = 0
        nextReviewDate = Date()
        lastReviewDate = nil
        state = .new
        lapses = 0
        totalReviews = 0
        correctReviews = 0
        modifiedAt = Date()
    }

    // MARK: - Conflict Resolution

    /// Merge local and server versions of a card with field-level resolution
    /// - Content (front/back): Server wins (LWW)
    /// - FSRS fields: Latest review wins (based on lastReviewDate)
    /// - Stats: Max value wins (counter semantics)
    /// - Returns: Merged card and resolution info
    static func merge(local: CardModel, server: CardModel) -> (merged: CardModel, resolution: MergeResolution) {
        var merged = server  // Start with server data
        var resolution = MergeResolution()

        // FSRS fields: Use the version with the later lastReviewDate
        let localHasLaterReview: Bool = {
            guard let localReview = local.lastReviewDate else { return false }
            guard let serverReview = server.lastReviewDate else { return true }
            return localReview > serverReview
        }()

        if localHasLaterReview {
            merged.stability = local.stability
            merged.difficulty = local.difficulty
            merged.state = local.state
            merged.lapses = local.lapses
            merged.nextReviewDate = local.nextReviewDate
            merged.lastReviewDate = local.lastReviewDate
            resolution.fsrsSource = .local
        } else {
            resolution.fsrsSource = .server
        }

        // Stats: Use max values (counter semantics - can only increase)
        merged.totalReviews = max(local.totalReviews, server.totalReviews)
        merged.correctReviews = max(local.correctReviews, server.correctReviews)
        resolution.statsSource = local.totalReviews > server.totalReviews ? .local : .server

        // Content: LWW - server already wins, but track if there was a conflict
        if local.front != server.front || local.back != server.back {
            resolution.contentConflict = true
        }

        return (merged, resolution)
    }
}

/// Resolution details from a card merge operation
struct MergeResolution: Sendable {
    enum Source: String, Sendable {
        case local = "local"
        case server = "server"
    }

    var fsrsSource: Source = .server
    var statsSource: Source = .server
    var contentConflict: Bool = false

    var description: String {
        var parts: [String] = []
        if fsrsSource == .local {
            parts.append("FSRS:local")
        }
        if statsSource == .local {
            parts.append("stats:local")
        }
        if contentConflict {
            parts.append("content:server")
        }
        return parts.isEmpty ? "no_conflict" : parts.joined(separator: ",")
    }
}

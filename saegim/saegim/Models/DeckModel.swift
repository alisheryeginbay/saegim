//
//  DeckModel.swift
//  saegim
//
//  Plain struct model for decks (PowerSync compatible)
//

import Foundation

/// Deck model for organizing flashcards
struct DeckModel: Identifiable, Hashable, Sendable {
    let id: UUID
    var userId: UUID
    var parentId: UUID?
    var name: String
    var deckDescription: String
    var createdAt: Date
    var modifiedAt: Date

    /// Cards in this deck (populated by DataRepository)
    var cards: [CardModel] = []

    /// Subdecks (populated by DataRepository)
    var subdecks: [DeckModel] = []

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        userId: UUID,
        parentId: UUID? = nil,
        name: String,
        description: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.parentId = parentId
        self.name = name
        self.deckDescription = description
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Initialize from database row
    init(row: [String: Any]) {
        let dateFormatter = ISO8601DateFormatter()

        self.id = UUID(uuidString: row["id"] as? String ?? "") ?? UUID()
        self.userId = UUID(uuidString: row["user_id"] as? String ?? "") ?? UUID()
        self.parentId = (row["parent_id"] as? String).flatMap { UUID(uuidString: $0) }
        self.name = row["name"] as? String ?? ""
        self.deckDescription = row["description"] as? String ?? ""
        self.createdAt = (row["created_at"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
        self.modifiedAt = (row["modified_at"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
    }

    /// Convert to dictionary for database insertion
    func toDict() -> [String: Any?] {
        let dateFormatter = ISO8601DateFormatter()
        return [
            "id": id.uuidString,
            "user_id": userId.uuidString,
            "parent_id": parentId?.uuidString,
            "name": name,
            "description": deckDescription,
            "created_at": dateFormatter.string(from: createdAt),
            "modified_at": dateFormatter.string(from: modifiedAt)
        ]
    }

    // MARK: - Hashable (exclude cards and subdecks for performance)

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DeckModel, rhs: DeckModel) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Computed Properties

    /// All cards including from subdecks
    var allCards: [CardModel] {
        var result = cards
        for subdeck in subdecks {
            result.append(contentsOf: subdeck.allCards)
        }
        return result
    }

    /// Total card count including subdecks
    var totalCardCount: Int {
        var count = cards.count
        for subdeck in subdecks {
            count += subdeck.totalCardCount
        }
        return count
    }

    /// Check if this deck has any subdecks
    var hasSubdecks: Bool {
        !subdecks.isEmpty
    }

    /// Get the full path name (e.g., "Parent::Child::Grandchild")
    /// Note: Only works if parent hierarchy is loaded
    var fullName: String {
        // For now, just return name since we don't have parent reference in struct
        // Full name would need to be computed by repository with full hierarchy
        name
    }

    /// Direct card count (not recursive)
    var cardCount: Int {
        cards.count
    }

    /// Due cards
    var dueCards: [CardModel] {
        cards.filter { $0.isDue }
    }

    /// Count of due cards
    var dueCount: Int {
        cards.reduce(0) { $0 + ($1.isDue ? 1 : 0) }
    }

    /// New cards
    var newCards: [CardModel] {
        cards.filter { $0.state == .new }
    }

    /// Count of new cards
    var newCount: Int {
        cards.reduce(0) { $0 + ($1.state == .new ? 1 : 0) }
    }

    /// Learned cards (in review state and not due)
    var learnedCards: [CardModel] {
        cards.filter { $0.state == .review && !$0.isDue }
    }

    /// Count of learned cards
    var learnedCount: Int {
        cards.reduce(0) { $0 + ($1.state == .review && !$1.isDue ? 1 : 0) }
    }

    /// Check if deck is empty
    var isEmpty: Bool {
        cards.isEmpty
    }

    // MARK: - Recursive Counts (including subdecks)

    /// Total due count including subdecks
    var totalDueCount: Int {
        var count = dueCount
        for subdeck in subdecks {
            count += subdeck.totalDueCount
        }
        return count
    }

    /// Total new count including subdecks
    var totalNewCount: Int {
        var count = newCount
        for subdeck in subdecks {
            count += subdeck.totalNewCount
        }
        return count
    }
}

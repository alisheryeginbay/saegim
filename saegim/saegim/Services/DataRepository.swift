//
//  DataRepository.swift
//  saegim
//
//  Data access layer for decks and cards using PowerSync
//

import Foundation
@preconcurrency import PowerSync
import Combine

// MARK: - Cursor Mappers (nonisolated for use in mapper closures)

private func mapDeckFromCursor(_ cursor: any SqlCursor) throws -> DeckModel {
    let dateFormatter = ISO8601DateFormatter()

    let id = UUID(uuidString: try cursor.getString(name: "id")) ?? UUID()
    let userId = UUID(uuidString: try cursor.getString(name: "user_id")) ?? UUID()
    let parentIdStr = try cursor.getStringOptional(name: "parent_id")
    let parentId = parentIdStr.flatMap { UUID(uuidString: $0) }
    let name = try cursor.getString(name: "name")
    let description = try cursor.getStringOptional(name: "description") ?? ""
    let createdAtStr = try cursor.getStringOptional(name: "created_at")
    let createdAt = createdAtStr.flatMap { dateFormatter.date(from: $0) } ?? Date()
    let modifiedAtStr = try cursor.getStringOptional(name: "modified_at")
    let modifiedAt = modifiedAtStr.flatMap { dateFormatter.date(from: $0) } ?? Date()

    return DeckModel(
        id: id,
        userId: userId,
        parentId: parentId,
        name: name,
        description: description,
        createdAt: createdAt,
        modifiedAt: modifiedAt
    )
}

private func mapCardFromCursor(_ cursor: any SqlCursor) throws -> CardModel {
    let dateFormatter = ISO8601DateFormatter()

    let id = UUID(uuidString: try cursor.getString(name: "id")) ?? UUID()
    let userId = UUID(uuidString: try cursor.getString(name: "user_id")) ?? UUID()
    let deckIdStr = try cursor.getStringOptional(name: "deck_id")
    let deckId = deckIdStr.flatMap { UUID(uuidString: $0) }
    let front = try cursor.getString(name: "front")
    let back = try cursor.getString(name: "back")

    // FSRS fields
    let stability = try cursor.getDoubleOptional(name: "stability") ?? 0
    let difficulty = try cursor.getDoubleOptional(name: "difficulty") ?? 0
    let stateRaw = try cursor.getIntOptional(name: "state") ?? 0
    let state = CardStateModel(rawValue: stateRaw) ?? .new
    let lapses = try cursor.getIntOptional(name: "lapses") ?? 0
    let nextReviewStr = try cursor.getStringOptional(name: "next_review_date")
    let nextReviewDate = nextReviewStr.flatMap { dateFormatter.date(from: $0) } ?? Date()
    let lastReviewStr = try cursor.getStringOptional(name: "last_review_date")
    let lastReviewDate = lastReviewStr.flatMap { dateFormatter.date(from: $0) }

    // Stats
    let totalReviews = try cursor.getIntOptional(name: "total_reviews") ?? 0
    let correctReviews = try cursor.getIntOptional(name: "correct_reviews") ?? 0

    // Timestamps
    let createdAtStr = try cursor.getStringOptional(name: "created_at")
    let createdAt = createdAtStr.flatMap { dateFormatter.date(from: $0) } ?? Date()
    let modifiedAtStr = try cursor.getStringOptional(name: "modified_at")
    let modifiedAt = modifiedAtStr.flatMap { dateFormatter.date(from: $0) } ?? Date()

    var card = CardModel(id: id, userId: userId, deckId: deckId, front: front, back: back)
    card.stability = stability
    card.difficulty = difficulty
    card.state = state
    card.lapses = lapses
    card.nextReviewDate = nextReviewDate
    card.lastReviewDate = lastReviewDate
    card.totalReviews = totalReviews
    card.correctReviews = correctReviews
    card.createdAt = createdAt
    card.modifiedAt = modifiedAt

    return card
}

/// Repository for accessing and managing deck and card data
@MainActor
final class DataRepository: ObservableObject {
    static let shared = DataRepository()

    private var database: (any PowerSyncDatabaseProtocol)? { DatabaseManager.shared.database }
    private var userId: UUID? { SupabaseManager.shared.userId }

    /// All root-level decks (with cards and subdecks populated)
    @Published private(set) var decks: [DeckModel] = []

    /// All cards across all decks
    @Published private(set) var allCards: [CardModel] = []

    /// Whether data is currently loading
    @Published private(set) var isLoading = false

    private var watchTask: Task<Void, Never>?

    private init() {}

    // MARK: - Data Loading

    /// Fetch all decks with their cards and build hierarchy
    func fetchDecks() async throws {
        guard let db = database else { return }

        isLoading = true
        defer { isLoading = false }

        // Fetch all decks
        var deckModels: [DeckModel] = try await db.getAll(
            sql: "SELECT * FROM decks ORDER BY name",
            parameters: [],
            mapper: { cursor in try mapDeckFromCursor(cursor) }
        )

        // Fetch all cards
        let cardModels: [CardModel] = try await db.getAll(
            sql: "SELECT * FROM cards ORDER BY created_at DESC",
            parameters: [],
            mapper: { cursor in try mapCardFromCursor(cursor) }
        )

        // Assign cards to decks
        for i in deckModels.indices {
            deckModels[i].cards = cardModels.filter { $0.deckId == deckModels[i].id }
        }

        // Build hierarchy and set root decks
        decks = buildDeckHierarchy(deckModels)
        allCards = cardModels
    }

    /// Build deck hierarchy from flat list
    private func buildDeckHierarchy(_ flatDecks: [DeckModel]) -> [DeckModel] {
        var deckMap = Dictionary(uniqueKeysWithValues: flatDecks.map { ($0.id, $0) })
        var rootDecks: [DeckModel] = []

        // First pass: identify children and assign to parents
        for deck in flatDecks {
            if let parentId = deck.parentId, deckMap[parentId] != nil {
                deckMap[parentId]?.subdecks.append(deck)
            }
        }

        // Second pass: collect root decks (those without parents or orphans)
        for deck in flatDecks {
            if deck.parentId == nil {
                if let updatedDeck = deckMap[deck.id] {
                    rootDecks.append(updatedDeck)
                }
            } else if deckMap[deck.parentId!] == nil {
                if let updatedDeck = deckMap[deck.id] {
                    rootDecks.append(updatedDeck)
                }
            }
        }

        return rootDecks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Start watching for database changes
    func startWatching() {
        watchTask?.cancel()
        watchTask = Task {
            guard let db = database else { return }

            do {
                for try await _ in try db.watch(
                    sql: "SELECT COUNT(*) as cnt FROM decks",
                    parameters: [],
                    mapper: { cursor in try cursor.getInt(name: "cnt") }
                ) {
                    guard !Task.isCancelled else { break }
                    try? await fetchDecks()
                }
            } catch {
                // Watch cancelled or error - silent fail
            }
        }
    }

    /// Stop watching for changes
    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    // MARK: - Deck Operations

    /// Create a new deck
    @discardableResult
    func createDeck(name: String, description: String = "", parentId: UUID? = nil) async throws -> DeckModel {
        guard let db = database, let userId = userId else {
            throw RepositoryError.notAuthenticated
        }

        let deck = DeckModel(userId: userId, parentId: parentId, name: name, description: description)
        let dateFormatter = ISO8601DateFormatter()

        _ = try await db.execute(
            sql: """
            INSERT INTO decks (id, user_id, parent_id, name, description, created_at, modified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                deck.id.uuidString,
                deck.userId.uuidString,
                deck.parentId?.uuidString as Any,
                deck.name,
                deck.deckDescription,
                dateFormatter.string(from: deck.createdAt),
                dateFormatter.string(from: deck.modifiedAt)
            ]
        )

        try await fetchDecks()
        return deck
    }

    /// Update an existing deck
    func updateDeck(_ deck: DeckModel) async throws {
        guard let db = database else {
            throw RepositoryError.notAuthenticated
        }

        let dateFormatter = ISO8601DateFormatter()

        _ = try await db.execute(
            sql: """
            UPDATE decks SET name = ?, description = ?, parent_id = ?, modified_at = ?
            WHERE id = ?
            """,
            parameters: [
                deck.name,
                deck.deckDescription,
                deck.parentId?.uuidString as Any,
                dateFormatter.string(from: Date()),
                deck.id.uuidString
            ]
        )

        try await fetchDecks()
    }

    /// Delete a deck and all its contents
    func deleteDeck(_ deck: DeckModel) async throws {
        guard let db = database else {
            throw RepositoryError.notAuthenticated
        }

        _ = try await db.execute(sql: "DELETE FROM cards WHERE deck_id = ?", parameters: [deck.id.uuidString])

        for subdeck in deck.subdecks {
            try await deleteDeck(subdeck)
        }

        _ = try await db.execute(sql: "DELETE FROM decks WHERE id = ?", parameters: [deck.id.uuidString])

        try await fetchDecks()
    }

    /// Find a deck by ID (searches recursively)
    func findDeck(id: UUID) -> DeckModel? {
        func search(in decks: [DeckModel]) -> DeckModel? {
            for deck in decks {
                if deck.id == id { return deck }
                if let found = search(in: deck.subdecks) { return found }
            }
            return nil
        }
        return search(in: decks)
    }

    // MARK: - Card Operations

    /// Create a new card
    func createCard(front: String, back: String, deckId: UUID) async throws {
        guard let db = database, let userId = userId else {
            throw RepositoryError.notAuthenticated
        }

        let card = CardModel(userId: userId, deckId: deckId, front: front, back: back)
        let dateFormatter = ISO8601DateFormatter()

        _ = try await db.execute(
            sql: """
            INSERT INTO cards (id, user_id, deck_id, front, back, stability, difficulty, state,
                              lapses, next_review_date, total_reviews, correct_reviews,
                              created_at, modified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                card.id.uuidString,
                card.userId.uuidString,
                card.deckId?.uuidString as Any,
                card.front,
                card.back,
                card.stability,
                card.difficulty,
                card.state.rawValue,
                card.lapses,
                dateFormatter.string(from: card.nextReviewDate),
                card.totalReviews,
                card.correctReviews,
                dateFormatter.string(from: card.createdAt),
                dateFormatter.string(from: card.modifiedAt)
            ]
        )

        try await fetchDecks()
    }

    /// Update an existing card
    func updateCard(_ card: CardModel) async throws {
        guard let db = database else {
            throw RepositoryError.notAuthenticated
        }

        let dateFormatter = ISO8601DateFormatter()

        _ = try await db.execute(
            sql: """
            UPDATE cards SET front = ?, back = ?, deck_id = ?, stability = ?, difficulty = ?,
                            state = ?, lapses = ?, next_review_date = ?, last_review_date = ?,
                            total_reviews = ?, correct_reviews = ?, modified_at = ?
            WHERE id = ?
            """,
            parameters: [
                card.front,
                card.back,
                card.deckId?.uuidString as Any,
                card.stability,
                card.difficulty,
                card.state.rawValue,
                card.lapses,
                dateFormatter.string(from: card.nextReviewDate),
                card.lastReviewDate.map { dateFormatter.string(from: $0) } as Any,
                card.totalReviews,
                card.correctReviews,
                dateFormatter.string(from: Date()),
                card.id.uuidString
            ]
        )
    }

    /// Delete a card
    func deleteCard(_ card: CardModel) async throws {
        guard let db = database else {
            throw RepositoryError.notAuthenticated
        }

        _ = try await db.execute(sql: "DELETE FROM cards WHERE id = ?", parameters: [card.id.uuidString])
        try await fetchDecks()
    }

    /// Move a card to a different deck
    func moveCard(_ card: CardModel, toDeckId: UUID) async throws {
        var updatedCard = card
        updatedCard.deckId = toDeckId
        try await updateCard(updatedCard)
        try await fetchDecks()
    }

    // MARK: - Due Cards

    /// Get all cards due for review
    func fetchDueCards() async throws -> [CardModel] {
        guard let db = database else { return [] }

        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())

        return try await db.getAll(
            sql: """
            SELECT * FROM cards
            WHERE next_review_date <= ? OR state = 0
            ORDER BY next_review_date
            """,
            parameters: [now],
            mapper: { cursor in try mapCardFromCursor(cursor) }
        )
    }

    /// Get count of due cards
    func getDueCount() async throws -> Int {
        guard let db = database else { return 0 }

        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())

        let counts: [Int] = try await db.getAll(
            sql: "SELECT COUNT(*) as count FROM cards WHERE next_review_date <= ? OR state = 0",
            parameters: [now],
            mapper: { cursor in try cursor.getInt(name: "count") }
        )

        return counts.first ?? 0
    }

    /// Get due cards for a specific deck (including subdecks)
    func fetchDueCards(for deck: DeckModel) -> [CardModel] {
        var dueCards = deck.cards.filter { $0.isDue || $0.state == .new }
        for subdeck in deck.subdecks {
            dueCards.append(contentsOf: fetchDueCards(for: subdeck))
        }
        return dueCards
    }

    // MARK: - Statistics

    var totalCardCount: Int { allCards.count }
    var newCardCount: Int { allCards.filter { $0.state == .new }.count }
    var learningCardCount: Int { allCards.filter { $0.state == .learning || $0.state == .relearning }.count }
    var reviewCardCount: Int { allCards.filter { $0.state == .review }.count }

    func cardsReviewedToday() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return allCards.filter { card in
            guard let lastReview = card.lastReviewDate else { return false }
            return lastReview >= today
        }.count
    }

    // MARK: - Bulk Operations

    /// Import multiple cards at once
    func importCards(_ cards: [(front: String, back: String)], toDeckId: UUID) async throws {
        guard let db = database, let userId = userId else {
            throw RepositoryError.notAuthenticated
        }

        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())

        for cardData in cards {
            let id = UUID()
            _ = try await db.execute(
                sql: """
                INSERT INTO cards (id, user_id, deck_id, front, back, stability, difficulty, state,
                                  lapses, next_review_date, total_reviews, correct_reviews,
                                  created_at, modified_at)
                VALUES (?, ?, ?, ?, ?, 0, 0, 0, 0, ?, 0, 0, ?, ?)
                """,
                parameters: [
                    id.uuidString,
                    userId.uuidString,
                    toDeckId.uuidString,
                    cardData.front,
                    cardData.back,
                    now,
                    now,
                    now
                ]
            )
        }

        try await fetchDecks()
    }
}

// MARK: - Repository Errors

enum RepositoryError: LocalizedError {
    case notAuthenticated
    case deckNotFound
    case cardNotFound
    case databaseError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action."
        case .deckNotFound:
            return "The deck could not be found."
        case .cardNotFound:
            return "The card could not be found."
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        }
    }
}

//
//  Deck.swift
//  saegim
//
//  Deck model for organizing flashcards
//

import Foundation
import SwiftData
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

@Model
final class Deck {
    var id: UUID
    var name: String
    var deckDescription: String
    var createdAt: Date
    var modifiedAt: Date
    var colorHex: String

    @Attribute(.externalStorage)
    var coverImageData: Data?

    @Relationship(deleteRule: .cascade)
    var cards: [Card] = []

    @Relationship(deleteRule: .cascade, inverse: \Deck.parent)
    var subdecks: [Deck] = []

    var parent: Deck?

    init(name: String, description: String = "", colorHex: String = "007AFF", parent: Deck? = nil) {
        self.id = UUID()
        self.name = name
        self.deckDescription = description
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.colorHex = colorHex
        self.parent = parent

        // Generate cover image
        let coverImage = CoverGenerator.shared.generate(for: name)
        #if canImport(AppKit)
        self.coverImageData = coverImage.tiffRepresentation
        #else
        self.coverImageData = coverImage.pngData()
        #endif
    }

    var coverImage: PlatformImage? {
        #if canImport(AppKit)
        if let data = coverImageData, let image = NSImage(data: data) {
            return image
        }
        #else
        if let data = coverImageData, let image = UIImage(data: data) {
            return image
        }
        #endif
        // Generate on-demand if missing
        return CoverGenerator.shared.generate(for: name)
    }

    func regenerateCover() {
        let coverImage = CoverGenerator.shared.generate(for: name)
        #if canImport(AppKit)
        self.coverImageData = coverImage.tiffRepresentation
        #else
        self.coverImageData = coverImage.pngData()
        #endif
    }

    /// All cards including from subdecks (expensive - use sparingly)
    var allCards: [Card] {
        var result = cards
        for subdeck in subdecks {
            result.append(contentsOf: subdeck.allCards)
        }
        return result
    }

    /// Total card count including subdecks (optimized - counts only, no array creation)
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
    var fullName: String {
        if let parent = parent {
            return "\(parent.fullName)::\(name)"
        }
        return name
    }

    var cardCount: Int {
        cards.count
    }

    /// Due cards (creates array - use dueCount for just counting)
    var dueCards: [Card] {
        cards.filter { $0.isDue }
    }

    /// Count of due cards (optimized - no array creation)
    var dueCount: Int {
        cards.reduce(0) { $0 + ($1.isDue ? 1 : 0) }
    }

    /// New cards (creates array - use newCount for just counting)
    var newCards: [Card] {
        cards.filter { $0.state == .new }
    }

    /// Count of new cards (optimized - no array creation)
    var newCount: Int {
        cards.reduce(0) { $0 + ($1.state == .new ? 1 : 0) }
    }

    /// Learned cards (creates array - use learnedCount for just counting)
    var learnedCards: [Card] {
        cards.filter { $0.state == .review && !$0.isDue }
    }

    /// Count of learned cards (optimized - no array creation)
    var learnedCount: Int {
        cards.reduce(0) { $0 + ($1.state == .review && !$1.isDue ? 1 : 0) }
    }

    /// Check if deck is empty (direct cards only, not recursive)
    var isEmpty: Bool {
        cards.isEmpty
    }
}

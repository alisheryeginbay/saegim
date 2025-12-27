//
//  Deck.swift
//  saegim
//
//  Deck model for organizing flashcards
//

import Foundation
import SwiftData
import AppKit

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
        self.coverImageData = coverImage.tiffRepresentation
    }

    var coverImage: NSImage? {
        if let data = coverImageData, let image = NSImage(data: data) {
            return image
        }
        // Generate on-demand if missing
        return CoverGenerator.shared.generate(for: name)
    }

    func regenerateCover() {
        let coverImage = CoverGenerator.shared.generate(for: name)
        self.coverImageData = coverImage.tiffRepresentation
    }

    /// All cards including from subdecks
    var allCards: [Card] {
        var result = cards
        for subdeck in subdecks {
            result.append(contentsOf: subdeck.allCards)
        }
        return result
    }

    /// Total card count including subdecks
    var totalCardCount: Int {
        allCards.count
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

    var dueCards: [Card] {
        cards.filter { $0.isDue }
    }

    var dueCount: Int {
        dueCards.count
    }

    var newCards: [Card] {
        cards.filter { $0.repetitions == 0 }
    }

    var newCount: Int {
        newCards.count
    }

    var learnedCards: [Card] {
        cards.filter { $0.repetitions > 0 && !$0.isDue }
    }

    var learnedCount: Int {
        learnedCards.count
    }
}

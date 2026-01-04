//
//  DeckListView_iOS.swift
//  saegim
//
//  iOS deck list with navigation
//

import SwiftUI
import SwiftData
import AudioToolbox
import FSRSSwift

struct DeckListView_iOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.name) private var decks: [Deck]

    private var rootDecks: [Deck] {
        decks.filter { $0.parent == nil }
    }

    var body: some View {
        Group {
            if decks.isEmpty {
                ContentUnavailableView(
                    "No Decks",
                    systemImage: "folder",
                    description: Text("Import from Anki or create a new deck to get started.")
                )
            } else {
                List {
                    ForEach(rootDecks) { deck in
                        DeckRow_iOS(deck: deck)
                    }
                    .onDelete(perform: deleteDecks)
                }
            }
        }
    }

    private func deleteDecks(at offsets: IndexSet) {
        for index in offsets {
            let deck = rootDecks[index]
            modelContext.delete(deck)
        }
    }
}

// MARK: - Deck Row

struct DeckRow_iOS: View {
    let deck: Deck

    var body: some View {
        NavigationLink(destination: DeckDetailView_iOS(deck: deck)) {
            HStack(spacing: 12) {
                // Deck color icon
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(Color(hex: deck.colorHex) ?? .blue)
                    .frame(width: 44, height: 44)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.name)
                        .font(.headline)

                    HStack(spacing: 8) {
                        Label("\(deck.cardCount)", systemImage: "rectangle.stack")
                        if deck.dueCount > 0 {
                            Label("\(deck.dueCount) due", systemImage: "clock")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Subdeck indicator
                if deck.hasSubdecks {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Deck Detail View

struct DeckDetailView_iOS: View {
    @Environment(\.modelContext) private var modelContext
    let deck: Deck

    @State private var showingStudySession = false
    @State private var showingNewCard = false
    @State private var searchText = ""

    private var filteredCards: [Card] {
        if searchText.isEmpty {
            return deck.cards
        }
        return deck.cards.filter {
            $0.front.localizedCaseInsensitiveContains(searchText) ||
            $0.back.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            // Stats Section
            Section {
                HStack {
                    StatCard_iOS(title: "Total", value: "\(deck.cardCount)", icon: "rectangle.stack")
                    StatCard_iOS(title: "Due", value: "\(deck.dueCount)", icon: "clock", color: .orange)
                    StatCard_iOS(title: "New", value: "\(deck.newCount)", icon: "sparkles", color: .blue)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Study Button
            if deck.dueCount > 0 || deck.newCount > 0 {
                Section {
                    Button {
                        showingStudySession = true
                    } label: {
                        Label("Study Now", systemImage: "brain.head.profile")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            // Subdecks
            if deck.hasSubdecks {
                Section("Subdecks") {
                    ForEach(deck.subdecks) { subdeck in
                        DeckRow_iOS(deck: subdeck)
                    }
                }
            }

            // Cards
            Section("Cards (\(filteredCards.count))") {
                ForEach(filteredCards) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.front)
                            .font(.subheadline)
                            .lineLimit(2)
                        Text(card.back)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteCards)
            }
        }
        .searchable(text: $searchText, prompt: "Search cards")
        .navigationTitle(deck.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewCard = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingStudySession) {
            NavigationStack {
                StudySessionView_iOS(deck: deck)
            }
        }
        .sheet(isPresented: $showingNewCard) {
            NavigationStack {
                NewCardView_iOS(deck: deck)
            }
        }
    }

    private func deleteCards(at offsets: IndexSet) {
        for index in offsets {
            let card = filteredCards[index]
            modelContext.delete(card)
        }
    }
}

// MARK: - Stat Card

struct StatCard_iOS: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Study Session View

struct StudySessionView_iOS: View {
    @Environment(\.dismiss) private var dismiss
    let deck: Deck

    @State private var cardQueue: [Card] = []
    @State private var showingAnswer = false
    @State private var reviewedCount = 0

    private var currentCard: Card? { cardQueue.first }
    private var totalToReview: Int { cardQueue.count + reviewedCount }

    var body: some View {
        Group {
            if cardQueue.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("Session Complete!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("You reviewed \(reviewedCount) cards")
                        .foregroundStyle(.secondary)
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if let card = currentCard {
                VStack(spacing: 0) {
                    Spacer()

                    CardView_iOS(card: card, showingAnswer: showingAnswer)
                        .onTapGesture {
                            if !showingAnswer {
                                withAnimation(.spring(duration: 0.3)) {
                                    showingAnswer = true
                                }
                            }
                        }

                    Spacer()

                    if showingAnswer {
                        ReviewButtons_iOS(card: card, onReview: reviewCard)
                            .padding(.bottom, 20)
                    } else {
                        Text("Tap to reveal")
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        .navigationTitle("\(reviewedCount)/\(totalToReview)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("End") {
                    dismiss()
                }
            }
        }
        .onAppear {
            cardQueue = deck.cards.filter { $0.isDue || $0.state == .new }.shuffled()
        }
    }

    private func reviewCard(_ card: Card, rating: Rating) {
        card.review(rating: rating)
        AudioServicesPlaySystemSound(rating != .again ? 1057 : 1053)

        showingAnswer = false
        cardQueue.removeFirst()

        if rating == .again && cardQueue.count > 0 {
            cardQueue.insert(card, at: min(2, cardQueue.count))
        } else {
            reviewedCount += 1
        }
    }
}

// MARK: - New Card View

struct NewCardView_iOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let deck: Deck

    @State private var front = ""
    @State private var back = ""

    var body: some View {
        Form {
            Section("Front") {
                TextEditor(text: $front)
                    .frame(minHeight: 100)
            }

            Section("Back") {
                TextEditor(text: $back)
                    .frame(minHeight: 100)
            }
        }
        .navigationTitle("New Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let card = Card(front: front, back: back)
                    card.deck = deck
                    modelContext.insert(card)
                    dismiss()
                }
                .disabled(front.isEmpty || back.isEmpty)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DeckListView_iOS()
            .navigationTitle("Decks")
    }
    .modelContainer(for: [Card.self, Deck.self], inMemory: true)
}

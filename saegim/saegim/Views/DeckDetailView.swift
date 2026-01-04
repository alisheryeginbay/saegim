//
//  DeckDetailView.swift
//  saegim
//

import SwiftUI
import SwiftData

struct DeckDetailView: View {
    let deck: Deck
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: NavigationItem?

    @State private var showingAddCard = false
    @State private var showingAddSubdeck = false
    @State private var selectedCardID: UUID?
    @State private var viewMode: ViewMode = .grid

    enum ViewMode {
        case grid, list
    }

    private var selectedCard: Card? {
        guard let id = selectedCardID else { return nil }
        return deck.cards.first { $0.id == id }
    }

    var body: some View {
        ScrollHeader(title: deck.name) {
            VStack(alignment: .leading, spacing: 24) {
                // Cards section
                if !deck.cards.isEmpty || !deck.hasSubdecks {
                    VStack(alignment: .leading, spacing: 0) {
                        if deck.hasSubdecks || !deck.cards.isEmpty {
                            Text("Cards")
                                .font(.title2.weight(.semibold))
                                .padding(.horizontal, 32)
                        }

                        if deck.cards.isEmpty {
                            EmptyDeckView(onAddCard: { showingAddCard = true })
                                .frame(height: 200)
                        } else {
                            CardListView(
                                cards: deck.cards,
                                viewMode: viewMode,
                                onSelect: { selectedCardID = $0.id },
                                onDelete: deleteCard
                            )
                        }
                    }
                }

                // Subdecks section
                if deck.hasSubdecks {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Decks")
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal, 32)

                        SubdecksGridView(
                            deck: deck,
                            selection: $selection,
                            onAddSubdeck: { showingAddSubdeck = true },
                            onDeleteSubdeck: deleteSubdeck
                        )
                    }
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if let parent = deck.parent {
                    Button {
                        selection = .deck(parent.id)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .help("Back to \(parent.name)")
                } else {
                    Button {
                        selection = .allCards
                    } label: {
                        Image(systemName: "house")
                    }
                    .help("Home")
                }
            }

            ToolbarItemGroup {
                if !deck.hasSubdecks {
                    Picker("View", selection: $viewMode) {
                        Image(systemName: "square.grid.2x2")
                            .tag(ViewMode.grid)
                        Image(systemName: "list.bullet")
                            .tag(ViewMode.list)
                    }
                    .pickerStyle(.segmented)

                    Button(action: { showingAddCard = true }) {
                        Image(systemName: "plus")
                    }
                    .help("Add Card")
                }
            }
        }
        .sheet(isPresented: $showingAddCard) {
            CardEditorSheet(deck: deck)
        }
        .sheet(isPresented: $showingAddSubdeck) {
            NewDeckSheet(parentDeck: deck)
        }
        .sheet(isPresented: Binding(
            get: { selectedCardID != nil },
            set: { if !$0 { selectedCardID = nil } }
        )) {
            if let card = selectedCard {
                CardEditorSheet(deck: deck, card: card)
            }
        }
        .background {
            Button("") {
                showingAddCard = true
            }
            .keyboardShortcut("n", modifiers: [])
            .opacity(0)
        }
    }

    private func deleteCard(_ card: Card) {
        withAnimation {
            modelContext.delete(card)
        }
    }

    private func deleteSubdeck(_ subdeck: Deck) {
        withAnimation {
            modelContext.delete(subdeck)
        }
    }
}

// MARK: - All Decks View

struct AllDecksView: View {
    @Query(filter: #Predicate<Deck> { $0.parent == nil }, sort: \Deck.name) private var rootDecks: [Deck]
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: NavigationItem?
    @State private var showingNewDeck = false

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 5)

    var body: some View {
        ScrollHeader(title: "All Decks") {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(rootDecks) { deck in
                    SubdeckCard(deck: deck)
                        .onTapGesture {
                            selection = .deck(deck.id)
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                deleteDeck(deck)
                            }
                        }
                }

                Button(action: { showingNewDeck = true }) {
                    NewDeckCard()
                }
                .buttonStyle(.plain)
            }
            .padding(32)
            .frame(maxWidth: 1100, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .sheet(isPresented: $showingNewDeck) {
            NewDeckSheet()
        }
    }

    private func deleteDeck(_ deck: Deck) {
        withAnimation {
            modelContext.delete(deck)
        }
    }
}

// MARK: - Subdecks Grid View

struct SubdecksGridView: View {
    let deck: Deck
    @Binding var selection: NavigationItem?
    var onAddSubdeck: () -> Void
    var onDeleteSubdeck: (Deck) -> Void

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 5)

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(deck.subdecks.sorted(by: { $0.name < $1.name })) { subdeck in
                SubdeckCard(deck: subdeck)
                    .onTapGesture {
                        selection = .deck(subdeck.id)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            onDeleteSubdeck(subdeck)
                        }
                    }
            }

            // New Deck card
            Button(action: onAddSubdeck) {
                NewDeckCard()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .frame(maxWidth: 1100, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct SubdeckCard: View {
    let deck: Deck

    var body: some View {
        VStack(alignment: .leading) {
            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .lineLimit(2)

                Text("\(deck.totalCardCount) cards")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .aspectRatio(1, contentMode: .fit)
        .background(Color(white: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

struct NewDeckCard: View {
    var body: some View {
        VStack {
            Image(systemName: "plus")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(.secondary.opacity(0.4))
        )
    }
}

// MARK: - Cards Content View

struct CardsContentView: View {
    let deck: Deck
    let viewMode: DeckDetailView.ViewMode
    var onAddCard: () -> Void
    var onSelectCard: (Card) -> Void
    var onDeleteCard: (Card) -> Void

    var body: some View {
        if deck.cards.isEmpty {
            EmptyDeckView(onAddCard: onAddCard)
        } else {
            CardListView(
                cards: deck.cards,
                viewMode: viewMode,
                onSelect: onSelectCard,
                onDelete: onDeleteCard
            )
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }
}

struct EmptyDeckView: View {
    var onAddCard: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Cards Yet")
                .font(.title2)
                .fontWeight(.medium)

            Text("Add cards to start learning")
                .foregroundStyle(.secondary)

            Button(action: onAddCard) {
                Label("Add Card", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CardListView: View {
    let cards: [Card]
    let viewMode: DeckDetailView.ViewMode
    var onSelect: (Card) -> Void
    var onDelete: (Card) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)
    ]

    var body: some View {
        switch viewMode {
        case .grid:
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(cards) { card in
                    CardGridItem(card: card)
                        .onTapGesture { onSelect(card) }
                        .contextMenu {
                            Button("Edit") { onSelect(card) }
                            Divider()
                            Button("Delete", role: .destructive) {
                                onDelete(card)
                            }
                        }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

        case .list:
            LazyVStack(spacing: 8) {
                ForEach(cards) { card in
                    CardListItem(card: card)
                        .onTapGesture { onSelect(card) }
                        .contextMenu {
                            Button("Edit") { onSelect(card) }
                            Divider()
                            Button("Delete", role: .destructive) {
                                onDelete(card)
                            }
                        }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
        }
    }
}

struct CardGridItem: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.front)
                .font(.headline)
                .lineLimit(3)

            Spacer()

            Text(card.back)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(height: 120)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

struct CardListItem: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.front)
                .lineLimit(1)
            Text(card.back)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Deck.self, Card.self, configurations: config)

    let deck = Deck(name: "Sample Deck", description: "Test deck")
    container.mainContext.insert(deck)

    let card1 = Card(front: "What is SwiftUI?", back: "A declarative UI framework")
    card1.deck = deck
    container.mainContext.insert(card1)

    let card2 = Card(front: "What is SwiftData?", back: "A persistence framework")
    card2.deck = deck
    container.mainContext.insert(card2)

    return NavigationStack {
        DeckDetailView(deck: deck, selection: .constant(.deck(deck.id)))
    }
    .modelContainer(container)
}

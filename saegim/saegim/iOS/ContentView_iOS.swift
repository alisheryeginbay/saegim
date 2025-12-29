//
//  ContentView_iOS.swift
//  saegim
//
//  iOS main content view with tab-based navigation
//

import SwiftUI
import SwiftData

struct ContentView_iOS: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab = 0
    @State private var showingAnkiImport = false
    @State private var showingCSVImport = false
    @State private var showingNewDeck = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // Due Today Tab
            NavigationStack {
                DueTodayView_iOS()
                    .navigationTitle("Due Today")
            }
            .tabItem {
                Label("Study", systemImage: "brain.head.profile")
            }
            .tag(0)

            // Decks Tab
            NavigationStack {
                DeckListView_iOS()
                    .navigationTitle("Decks")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("New Deck", systemImage: "folder.badge.plus") {
                                    showingNewDeck = true
                                }
                                Divider()
                                Button("Import from Anki", systemImage: "square.and.arrow.down") {
                                    showingAnkiImport = true
                                }
                                Button("Import from CSV", systemImage: "doc.text") {
                                    showingCSVImport = true
                                }
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Decks", systemImage: "folder")
            }
            .tag(1)

            // All Cards Tab
            NavigationStack {
                AllCardsView_iOS()
                    .navigationTitle("All Cards")
            }
            .tabItem {
                Label("Cards", systemImage: "rectangle.stack")
            }
            .tag(2)

            // Settings Tab
            NavigationStack {
                SettingsView_iOS()
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(3)
        }
        .sheet(isPresented: $showingAnkiImport) {
            NavigationStack {
                AnkiImportView()
            }
        }
        .sheet(isPresented: $showingCSVImport) {
            NavigationStack {
                CSVImportView()
            }
        }
        .sheet(isPresented: $showingNewDeck) {
            NavigationStack {
                NewDeckView_iOS { name, description in
                    let deck = Deck(name: name, description: description)
                    modelContext.insert(deck)
                }
            }
        }
    }
}

// MARK: - New Deck View

struct NewDeckView_iOS: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deckName = ""
    @State private var deckDescription = ""

    let onSave: (String, String) -> Void

    var body: some View {
        Form {
            Section("Deck Details") {
                TextField("Name", text: $deckName)
                TextField("Description (optional)", text: $deckDescription)
            }
        }
        .navigationTitle("New Deck")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    onSave(deckName, deckDescription)
                    dismiss()
                }
                .disabled(deckName.isEmpty)
            }
        }
    }
}

// MARK: - All Cards View

struct AllCardsView_iOS: View {
    @Query(sort: \Card.createdAt, order: .reverse) private var cards: [Card]
    @State private var searchText = ""

    private var filteredCards: [Card] {
        if searchText.isEmpty {
            return cards
        }
        return cards.filter {
            $0.front.localizedCaseInsensitiveContains(searchText) ||
            $0.back.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView(
                    "No Cards",
                    systemImage: "rectangle.stack",
                    description: Text("Import a deck or create cards to get started.")
                )
            } else {
                List(filteredCards) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.front)
                            .font(.headline)
                            .lineLimit(2)
                        Text(card.back)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if let deck = card.deck {
                            Text(deck.name)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .searchable(text: $searchText, prompt: "Search cards")
            }
        }
    }
}

#Preview {
    ContentView_iOS()
        .modelContainer(for: [Card.self, Deck.self], inMemory: true)
}

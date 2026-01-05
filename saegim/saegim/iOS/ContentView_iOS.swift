//
//  ContentView_iOS.swift
//  saegim
//
//  iOS main content view with tab-based navigation
//

import SwiftUI

struct ContentView_iOS: View {
    @EnvironmentObject private var repository: DataRepository

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
                NewDeckView_iOS()
            }
        }
    }
}

// MARK: - New Deck View

struct NewDeckView_iOS: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repository: DataRepository
    @State private var deckName = ""
    @State private var deckDescription = ""
    @State private var isCreating = false

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
                    createDeck()
                }
                .disabled(deckName.isEmpty || isCreating)
            }
        }
    }

    private func createDeck() {
        isCreating = true
        Task {
            do {
                try await repository.createDeck(name: deckName, description: deckDescription)
                dismiss()
            } catch {
                print("Failed to create deck: \(error)")
                isCreating = false
            }
        }
    }
}

// MARK: - All Cards View

struct AllCardsView_iOS: View {
    @EnvironmentObject private var repository: DataRepository
    @State private var searchText = ""

    private var cards: [CardModel] {
        repository.allCards.sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredCards: [CardModel] {
        if searchText.isEmpty {
            return cards
        }
        return cards.filter {
            $0.front.localizedCaseInsensitiveContains(searchText) ||
            $0.back.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func deckName(for card: CardModel) -> String? {
        guard let deckId = card.deckId else { return nil }
        return repository.findDeck(id: deckId)?.name
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
                        if let deckName = deckName(for: card) {
                            Text(deckName)
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
}

//
//  ContentView.swift
//  saegim
//
//  Created by Alisher on 12/26/25.
//

import SwiftUI
import SwiftData
import AppKit

enum NavigationItem: Hashable {
    case dashboard
    case allCards
    case allDecks
    case dueToday
    case deck(UUID)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.name) private var decks: [Deck]

    @State private var selectedItem: NavigationItem? = .dueToday
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingNewDeck = false
    @State private var showingNewCard = false
    @State private var showingAnkiImport = false
    @State private var showingCSVImport = false
    @State private var parentDeckForNewSubdeck: Deck?

    /// Root decks only (no parent)
    private var rootDecks: [Deck] {
        decks.filter { $0.parent == nil }
    }

    /// Count of all due cards (includes new cards since they're due immediately)
    private var dueCardCount: Int {
        decks.reduce(0) { $0 + $1.dueCount }
    }

    /// Find a deck by ID recursively through all decks
    private func findDeck(by id: UUID) -> Deck? {
        for deck in decks {
            if deck.id == id { return deck }
        }
        return nil
    }

    var body: some View {
        ZStack {
            if selectedItem == .dueToday {
                DottedGridBackground()
                    .padding(-50)
                    .ignoresSafeArea()
            }

            NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedItem) {
                NavigationLink(value: NavigationItem.dueToday) {
                    HStack {
                        Label("Due Today", systemImage: "clock")
                        Spacer()
                        if dueCardCount > 0 {
                            Text("\(dueCardCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                NavigationLink(value: NavigationItem.dashboard) {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }

                NavigationLink(value: NavigationItem.allCards) {
                    Label("All Cards", systemImage: "rectangle.stack")
                }

                Section("Decks") {
                    NavigationLink(value: NavigationItem.allDecks) {
                        Label("All", systemImage: "square.grid.2x2")
                    }

                    ForEach(rootDecks) { deck in
                        DeckSidebarRow(
                            deck: deck,
                            onAddSubdeck: { parentDeckForNewSubdeck = $0 },
                            onDelete: deleteDeck
                        )
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220)
            .background {
                // Hidden button for Cmd+Delete shortcut
                Button("") { deleteSelectedDeck() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .hidden()
            }
            .toolbar {
                ToolbarItem {
                    Button(action: { showingNewDeck = true }) {
                        Image(systemName: "folder.badge.plus")
                    }
                    .help("New Deck")
                }
            }
        } detail: {
            Group {
                switch selectedItem {
                case .dashboard:
                    DashboardView()
                case .allCards:
                    AllCardsView()
                case .allDecks:
                    AllDecksView(selection: $selectedItem)
                case .dueToday:
                    DueTodayView()
                case .deck(let deckId):
                    if let deck = findDeck(by: deckId) {
                        DeckDetailView(deck: deck, selection: $selectedItem)
                    } else {
                        Text("Deck not found")
                            .foregroundStyle(.secondary)
                    }
                case .none:
                    if rootDecks.isEmpty {
                        WelcomeView(onNewDeck: { showingNewDeck = true })
                    } else {
                        DashboardView()
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewDeck) {
            NewDeckSheet()
        }
        .sheet(item: $parentDeckForNewSubdeck) { parent in
            NewDeckSheet(parentDeck: parent)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newDeck)) { _ in
            showingNewDeck = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newCard)) { _ in
            showingNewCard = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .importAnki)) { _ in
            showingAnkiImport = true
        }
        .sheet(isPresented: $showingAnkiImport) {
            AnkiImportView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importCSV)) { _ in
            showingCSVImport = true
        }
        .sheet(isPresented: $showingCSVImport) {
            CSVImportView()
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        }
    }

    private func deleteDeck(_ deck: Deck) {
        withAnimation {
            modelContext.delete(deck)
        }
    }

    private func deleteSelectedDeck() {
        guard case .deck(let deckId) = selectedItem,
              let deck = findDeck(by: deckId) else { return }

        // Find the deck's position to select the previous one
        let sortedDecks = rootDecks.sorted { $0.name < $1.name }
        if let index = sortedDecks.firstIndex(where: { $0.id == deckId }) {
            if index > 0 {
                // Select previous deck
                selectedItem = .deck(sortedDecks[index - 1].id)
            } else if sortedDecks.count > 1 {
                // Was first, select next
                selectedItem = .deck(sortedDecks[1].id)
            } else {
                // No decks left
                selectedItem = .allDecks
            }
        }

        withAnimation {
            modelContext.delete(deck)
        }
    }
}

// MARK: - Deck Sidebar Row

struct DeckSidebarRow: View {
    @Bindable var deck: Deck
    var onAddSubdeck: (Deck) -> Void
    var onDelete: (Deck) -> Void

    @State private var isExpanded = true
    @State private var isRenaming = false
    @State private var editedName = ""
    @FocusState private var isTextFieldFocused: Bool

    private var deckLabel: some View {
        Label {
            if isRenaming {
                TextField("Deck Name", text: $editedName, onCommit: {
                    if !editedName.isEmpty {
                        deck.name = editedName
                    }
                    isRenaming = false
                })
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onChange(of: isTextFieldFocused) { _, focused in
                    if !focused {
                        if !editedName.isEmpty {
                            deck.name = editedName
                        }
                        isRenaming = false
                    }
                }
            } else {
                Text(deck.name)
            }
        } icon: {
            Group {
                if let coverImage = deck.coverImage {
                    Image(nsImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.gray
                }
            }
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .contextMenu {
            Button("Rename") {
                editedName = deck.name
                isRenaming = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTextFieldFocused = true
                }
            }
            Button("Add Subdeck") {
                onAddSubdeck(deck)
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete(deck)
            }
        }
    }

    var body: some View {
        if deck.hasSubdecks {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(deck.subdecks.sorted(by: { $0.name < $1.name })) { subdeck in
                    DeckSidebarRow(
                        deck: subdeck,
                        onAddSubdeck: onAddSubdeck,
                        onDelete: onDelete
                    )
                }
            } label: {
                NavigationLink(value: NavigationItem.deck(deck.id)) {
                    deckLabel
                }
            }
        } else {
            NavigationLink(value: NavigationItem.deck(deck.id)) {
                deckLabel
            }
        }
    }
}

struct WelcomeView: View {
    var onNewDeck: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Welcome to Saegim")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Master anything with spaced repetition")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button(action: onNewDeck) {
                Label("Create Your First Deck", systemImage: "plus")
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Previews disabled - use DueTodayView.swift for component previews
// ContentView uses NavigationSplitView with List which crashes macOS previews

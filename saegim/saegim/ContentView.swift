//
//  ContentView.swift
//  saegim
//
//  Created by Alisher on 12/26/25.
//

import SwiftUI

enum NavigationItem: Hashable {
    case dashboard
    case allDecks
    case dueToday
    case deck(UUID)
}

struct ContentView: View {
    @EnvironmentObject private var repository: DataRepository

    @State private var selectedItem: NavigationItem? = .dueToday
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingNewDeck = false
    @State private var showingNewCard = false
    @State private var showingAnkiImport = false
    @State private var showingCSVImport = false
    @State private var parentDeckForNewSubdeck: DeckModel?
    @State private var newDeckName = ""

    /// Root decks (already filtered by repository)
    private var rootDecks: [DeckModel] {
        repository.decks
    }

    /// Count of all due cards
    private var dueCardCount: Int {
        repository.decks.reduce(0) { $0 + $1.totalDueCount }
    }

    /// Find a deck by ID recursively
    private func findDeck(by id: UUID) -> DeckModel? {
        repository.findDeck(id: id)
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

                Section("Decks") {
                    ForEach(rootDecks) { deck in
                        DeckSidebarRow(
                            deck: deck,
                            onAddSubdeck: { parentDeckForNewSubdeck = $0 },
                            onDelete: deleteDeck,
                            onRename: renameDeck
                        )
                    }
                }
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: NavigationItem.self) { items in
                if items.isEmpty {
                    // Empty area - show New Deck option
                    Button("New Deck", systemImage: "folder.badge.plus") {
                        showingNewDeck = true
                    }
                }
            }
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
        .alert("New Deck", isPresented: $showingNewDeck) {
            TextField("Name", text: $newDeckName)
            Button("Cancel", role: .cancel) { newDeckName = "" }
            Button("Create") {
                createDeck(name: newDeckName, parentId: nil)
                newDeckName = ""
            }
            .disabled(newDeckName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a name for your new deck.")
        }
        .alert("New Subdeck", isPresented: Binding(
            get: { parentDeckForNewSubdeck != nil },
            set: { if !$0 { parentDeckForNewSubdeck = nil } }
        )) {
            TextField("Name", text: $newDeckName)
            Button("Cancel", role: .cancel) {
                newDeckName = ""
                parentDeckForNewSubdeck = nil
            }
            Button("Create") {
                if let parent = parentDeckForNewSubdeck {
                    createDeck(name: newDeckName, parentId: parent.id)
                }
                newDeckName = ""
                parentDeckForNewSubdeck = nil
            }
            .disabled(newDeckName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            if let parent = parentDeckForNewSubdeck {
                Text("Create a subdeck in \"\(parent.name)\".")
            }
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
        #if os(macOS)
        .toolbarBackground(.hidden, for: .windowToolbar)
        #endif
        }
    }

    private func deleteDeck(_ deck: DeckModel) {
        Task {
            try? await repository.deleteDeck(deck)
        }
    }

    private func renameDeck(_ deck: DeckModel, newName: String) {
        var updatedDeck = deck
        updatedDeck.name = newName
        Task {
            try? await repository.updateDeck(updatedDeck)
        }
    }

    private func deleteSelectedDeck() {
        guard case .deck(let deckId) = selectedItem,
              let deck = findDeck(by: deckId) else { return }

        // Find the deck's position to select the previous one
        let sortedDecks = rootDecks
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

        Task {
            try? await repository.deleteDeck(deck)
        }
    }

    private func createDeck(name: String, parentId: UUID?) {
        Task {
            try? await repository.createDeck(name: name, description: "", parentId: parentId)
        }
    }
}

// MARK: - Deck Sidebar Row

struct DeckSidebarRow: View {
    let deck: DeckModel
    var onAddSubdeck: (DeckModel) -> Void
    var onDelete: (DeckModel) -> Void
    var onRename: (DeckModel, String) -> Void

    @State private var isExpanded = true
    @State private var isRenaming = false
    @State private var editedName = ""
    @FocusState private var isTextFieldFocused: Bool

    private var deckLabel: some View {
        Label {
            if isRenaming {
                TextField("Deck Name", text: $editedName, onCommit: {
                    if !editedName.isEmpty {
                        onRename(deck, editedName)
                    }
                    isRenaming = false
                })
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onChange(of: isTextFieldFocused) { _, focused in
                    if !focused {
                        if !editedName.isEmpty {
                            onRename(deck, editedName)
                        }
                        isRenaming = false
                    }
                }
            } else {
                Text(deck.name)
            }
        } icon: {
            Image(systemName: "folder.fill")
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
                        onDelete: onDelete,
                        onRename: onRename
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

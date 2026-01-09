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
        VStack(spacing: 0) {
            OfflineBanner()

            TabView(selection: $selectedTab) {
                // Due Today Tab
                NavigationStack {
                    DueTodayView_iOS()
                        .navigationTitle("Due Today")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                SyncStatusBar()
                            }
                        }
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
                            ToolbarItem(placement: .topBarLeading) {
                                SyncStatusBar()
                            }
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

                // Settings Tab
                NavigationStack {
                    SettingsView_iOS()
                        .navigationTitle("Settings")
                }
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
            }
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

#Preview {
    ContentView_iOS()
}

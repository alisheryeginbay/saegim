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
    @State private var newDeckName = ""

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
        .alert("New Deck", isPresented: $showingNewDeck) {
            TextField("Name", text: $newDeckName)
            Button("Cancel", role: .cancel) { newDeckName = "" }
            Button("Create") {
                createDeck()
                newDeckName = ""
            }
            .disabled(newDeckName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a name for your new deck.")
        }
    }

    private func createDeck() {
        Task {
            try? await repository.createDeck(name: newDeckName, description: "", parentId: nil)
        }
    }
}

#Preview {
    ContentView_iOS()
}

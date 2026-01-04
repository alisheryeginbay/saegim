//
//  NewDeckSheet.swift
//  saegim
//

import SwiftUI
import SwiftData

struct NewDeckSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var parentDeck: Deck?

    @State private var name = ""
    @State private var description = ""

    private var title: String {
        if let parent = parentDeck {
            return "New Subdeck in \(parent.name)"
        }
        return "New Deck"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button("Create") {
                    createDeck()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
            .padding()
            .background(.bar)

            Divider()

            // Form
            Form {
                TextField("Deck Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("Description (optional)", text: $description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 400, height: 220)
    }

    private func createDeck() {
        let deck = Deck(
            name: name,
            description: description,
            parent: parentDeck
        )
        modelContext.insert(deck)

        // Explicitly add to parent's subdecks
        if let parent = parentDeck {
            parent.subdecks.append(deck)
        }

        dismiss()
    }
}

#Preview {
    NewDeckSheet()
        .modelContainer(for: Deck.self, inMemory: true)
}

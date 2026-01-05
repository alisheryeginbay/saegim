//
//  NewDeckSheet.swift
//  saegim
//

import SwiftUI

struct NewDeckSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repository: DataRepository

    var parentDeck: DeckModel?

    @State private var name = ""
    @State private var description = ""
    @State private var isCreating = false

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
                .disabled(name.isEmpty || isCreating)
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
        isCreating = true
        Task {
            do {
                try await repository.createDeck(
                    name: name,
                    description: description,
                    parentId: parentDeck?.id
                )
                dismiss()
            } catch {
                print("Failed to create deck: \(error)")
                isCreating = false
            }
        }
    }
}

#Preview {
    NewDeckSheet()
}

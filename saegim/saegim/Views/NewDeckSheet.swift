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
    @State private var selectedColor = "007AFF"

    private let colors = [
        "007AFF", "34C759", "FF9500", "FF3B30",
        "AF52DE", "5856D6", "FF2D55", "00C7BE"
    ]

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

                LabeledContent("Color") {
                    HStack(spacing: 8) {
                        ForEach(colors, id: \.self) { colorHex in
                            Circle()
                                .fill(Color(hex: colorHex) ?? .blue)
                                .frame(width: 24, height: 24)
                                .overlay {
                                    if selectedColor == colorHex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture {
                                    selectedColor = colorHex
                                }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 400, height: 280)
        .onAppear {
            // Inherit parent's color by default
            if let parent = parentDeck {
                selectedColor = parent.colorHex
            }
        }
    }

    private func createDeck() {
        let deck = Deck(
            name: name,
            description: description,
            colorHex: selectedColor,
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

//
//  CardEditorSheet.swift
//  saegim
//

import SwiftUI
import SwiftData

struct CardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let deck: Deck
    var card: Card?

    @State private var front = ""
    @State private var back = ""
    @FocusState private var focusedField: Field?

    private var isEditing: Bool { card != nil }
    private var canSave: Bool { !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                 !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    enum Field {
        case front, back
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Content
            HStack(spacing: 0) {
                // Front side
                cardSide(
                    title: "Front",
                    placeholder: "Question or term...",
                    text: $front,
                    field: .front
                )

                Divider()

                // Back side
                cardSide(
                    title: "Back",
                    placeholder: "Answer or definition...",
                    text: $back,
                    field: .back
                )
            }

            // Footer
            footer
        }
        .frame(width: 700, height: 400)
        .onAppear {
            if let card = card {
                front = card.front
                back = card.back
            }
            focusedField = .front
        }
        .onSubmit {
            if focusedField == .front {
                focusedField = .back
            } else if canSave {
                saveCard()
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.quaternary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Spacer()

            VStack(spacing: 2) {
                Text(isEditing ? "Edit Card" : "New Card")
                    .font(.headline)
                Text(deck.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Balance the layout
            Color.clear.frame(width: 28, height: 28)
        }
        .padding()
        .background(.bar)
    }

    private func cardSide(title: String, placeholder: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }

                TextEditor(text: text)
                    .font(.title3)
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: field)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .background(focusedField == field ? Color.accentColor.opacity(0.05) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: focusedField)
    }

    private var footer: some View {
        HStack {
            if isEditing {
                Spacer()

                Button("Save") {
                    saveCard()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            } else {
                Text("Press ⌘↵ to save, ⇧⌘↵ to add another")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                HStack(spacing: 12) {
                    Button("Add Another") {
                        saveCard(keepOpen: true)
                    }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(!canSave)

                    Button("Add Card") {
                        saveCard()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                }
            }
        }
        .padding()
        .background(.bar)
    }

    private func saveCard(keepOpen: Bool = false) {
        let trimmedFront = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBack = back.trimmingCharacters(in: .whitespacesAndNewlines)

        if let card = card {
            card.front = trimmedFront
            card.back = trimmedBack
            card.modifiedAt = Date()
        } else {
            let newCard = Card(front: trimmedFront, back: trimmedBack, deck: deck)
            modelContext.insert(newCard)
        }

        if keepOpen {
            front = ""
            back = ""
            focusedField = .front
        } else {
            dismiss()
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Deck.self, Card.self, configurations: config)
    let deck = Deck(name: "Sample")
    container.mainContext.insert(deck)

    return CardEditorSheet(deck: deck)
        .modelContainer(container)
}

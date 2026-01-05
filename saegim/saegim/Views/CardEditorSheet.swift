//
//  CardEditorSheet.swift
//  saegim
//

import SwiftUI

struct CardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repository: DataRepository

    let deck: DeckModel
    var card: CardModel?

    @State private var front = ""
    @State private var back = ""
    @State private var isSaving = false
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
                .disabled(!canSave || isSaving)
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
                    .disabled(!canSave || isSaving)

                    Button("Add Card") {
                        saveCard()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .padding()
        .background(.bar)
    }

    private func saveCard(keepOpen: Bool = false) {
        let trimmedFront = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBack = back.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true

        Task {
            do {
                if var existingCard = card {
                    existingCard.front = trimmedFront
                    existingCard.back = trimmedBack
                    try await repository.updateCard(existingCard)
                } else {
                    try await repository.createCard(
                        front: trimmedFront,
                        back: trimmedBack,
                        deckId: deck.id
                    )
                }

                if keepOpen {
                    front = ""
                    back = ""
                    focusedField = .front
                    isSaving = false
                } else {
                    dismiss()
                }
            } catch {
                print("Failed to save card: \(error)")
                isSaving = false
            }
        }
    }
}

#Preview {
    CardEditorSheet(deck: DeckModel(userId: UUID(), name: "Sample"))
}

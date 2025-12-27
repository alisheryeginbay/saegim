//
//  StudySessionView.swift
//  saegim
//

import SwiftUI
import SwiftData

struct StudySessionView: View {
    @Environment(\.dismiss) private var dismiss
    let deck: Deck

    @State private var cardIDsToStudy: [UUID] = []  // Store IDs, not model objects
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var sessionComplete = false
    @State private var sessionStats = SessionStats()

    struct SessionStats {
        var cardsReviewed = 0
        var correctAnswers = 0
        var startTime = Date()
    }

    private var cardsToStudy: [Card] {
        cardIDsToStudy.compactMap { id in
            deck.cards.first { $0.id == id }
        }
    }

    private var currentCard: Card? {
        guard currentIndex < cardsToStudy.count else { return nil }
        return cardsToStudy[currentIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("End Session") {
                    dismiss()
                }

                Spacer()

                Text("\(currentIndex + 1) / \(cardIDsToStudy.count)")
                    .font(.headline)
                    .monospacedDigit()

                Spacer()

                // Progress
                ProgressView(value: Double(currentIndex), total: Double(max(1, cardIDsToStudy.count)))
                    .frame(width: 100)
            }
            .padding()
            .background(.bar)

            Divider()

            if sessionComplete {
                SessionCompleteView(
                    stats: sessionStats,
                    totalCards: cardIDsToStudy.count,
                    onDone: { dismiss() }
                )
            } else if cardIDsToStudy.isEmpty {
                NoCardsView(onDismiss: { dismiss() })
            } else if let card = currentCard {
                // Card View
                VStack {
                    Spacer()

                    FlashcardView(
                        card: card,
                        isFlipped: isFlipped
                    )
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.4)) {
                            isFlipped.toggle()
                        }
                    }

                    Spacer()

                    // Controls
                    if isFlipped {
                        AnswerButtonsView(onAnswer: handleAnswer)
                    } else {
                        VStack(spacing: 8) {
                            Text("Tap card or press Space to reveal")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            setupSession()
        }
        .onExitCommand {
            dismiss()
        }
        .onKeyPress(.space) {
            if !isFlipped {
                withAnimation(.spring(duration: 0.4)) {
                    isFlipped = true
                }
            }
            return .handled
        }
    }

    private func setupSession() {
        // Get due cards and new cards
        let dueCards = deck.dueCards.shuffled()
        let newCards = deck.newCards.shuffled()

        // Combine: prioritize due cards, then add new cards
        let selectedCards = Array((dueCards + newCards).prefix(20))
        cardIDsToStudy = selectedCards.map { $0.id }

        if cardIDsToStudy.isEmpty {
            sessionComplete = true
        }
    }

    private func handleAnswer(quality: Int) {
        guard let card = currentCard else { return }
        card.review(quality: quality)

        sessionStats.cardsReviewed += 1
        if quality >= 3 {
            sessionStats.correctAnswers += 1
        }

        // Move to next card
        withAnimation {
            isFlipped = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if currentIndex < cardIDsToStudy.count - 1 {
                currentIndex += 1
            } else {
                sessionComplete = true
            }
        }
    }
}

struct FlashcardView: View {
    let card: Card
    let isFlipped: Bool

    var body: some View {
        ZStack {
            // Front
            CardFace(text: card.front, isFront: true)
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(
                    .degrees(isFlipped ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0)
                )

            // Back
            CardFace(text: card.back, isFront: false)
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(
                    .degrees(isFlipped ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0)
                )
        }
        .frame(maxWidth: 500, maxHeight: 300)
    }
}

struct CardFace: View {
    let text: String
    let isFront: Bool

    var body: some View {
        VStack {
            Text(isFront ? "Question" : "Answer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top)

            Spacer()

            Text(text)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding()

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isFront ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isFront ? .blue.opacity(0.3) : .green.opacity(0.3), lineWidth: 2)
        )
    }
}

struct AnswerButtonsView: View {
    var onAnswer: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("How well did you know it?")
                .font(.headline)

            HStack(spacing: 16) {
                AnswerButton(
                    label: "Again",
                    subtitle: "Forgot",
                    color: .red,
                    keyNumber: 1
                ) { onAnswer(1) }

                AnswerButton(
                    label: "Hard",
                    subtitle: "Struggled",
                    color: .orange,
                    keyNumber: 2
                ) { onAnswer(2) }

                AnswerButton(
                    label: "Good",
                    subtitle: "Correct",
                    color: .green,
                    keyNumber: 3
                ) { onAnswer(4) }

                AnswerButton(
                    label: "Easy",
                    subtitle: "Perfect",
                    color: .blue,
                    keyNumber: 4
                ) { onAnswer(5) }
            }

            Text("Press 1-4 to answer")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct AnswerButton: View {
    let label: String
    let subtitle: String
    let color: Color
    let keyNumber: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, height: 60)
        }
        .buttonStyle(.bordered)
        .tint(color)
        .keyboardShortcut(KeyEquivalent(Character("\(keyNumber)")), modifiers: [])
    }
}

struct SessionCompleteView: View {
    let stats: StudySessionView.SessionStats
    let totalCards: Int
    let onDone: () -> Void

    private var accuracy: Double {
        guard stats.cardsReviewed > 0 else { return 0 }
        return Double(stats.correctAnswers) / Double(stats.cardsReviewed) * 100
    }

    private var duration: String {
        let interval = Date().timeIntervalSince(stats.startTime)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Session Complete!")
                .font(.largeTitle.bold())

            VStack(spacing: 16) {
                StatRow(label: "Cards Reviewed", value: "\(stats.cardsReviewed)")
                StatRow(label: "Correct Answers", value: "\(stats.correctAnswers)")
                StatRow(label: "Accuracy", value: String(format: "%.0f%%", accuracy))
                StatRow(label: "Time", value: duration)
            }
            .padding()
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button("Done") {
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct NoCardsView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("All Caught Up!")
                .font(.title.bold())

            Text("No cards are due for review")
                .foregroundStyle(.secondary)

            Button("Close") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Deck.self, Card.self, configurations: config)

    let deck = Deck(name: "Sample")
    container.mainContext.insert(deck)

    let card = Card(front: "What is SwiftUI?", back: "A declarative UI framework")
    card.deck = deck
    container.mainContext.insert(card)

    return StudySessionView(deck: deck)
        .modelContainer(container)
}

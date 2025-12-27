//
//  DueTodayView.swift
//  saegim
//

import SwiftUI
import SwiftData
import AppKit

struct DueTodayView: View {
    @Query private var decks: [Deck]
    @State private var currentIndex = 0
    @State private var showingAnswer = false
    @State private var reviewedCount = 0
    @State private var dueCards: [Card] = []

    private var currentCard: Card? {
        guard currentIndex < dueCards.count else { return nil }
        return dueCards[currentIndex]
    }

    private var totalCards: Int {
        dueCards.count
    }

    private var progress: Double {
        guard totalCards > 0 else { return 0 }
        return Double(reviewedCount) / Double(totalCards)
    }

    private func refreshDueCards() {
        dueCards = decks.flatMap { deck in
            deck.cards.filter { $0.isDue || $0.repetitions == 0 }
        }
    }

    var body: some View {
        Group {
            if dueCards.isEmpty {
                AllCaughtUpView()
            } else {
                VStack(spacing: 0) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.quaternary)
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(.green)
                                .frame(width: geometry.size.width * progress, height: 4)
                                .animation(.spring(response: 0.3), value: progress)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                    Spacer()

                    // Stacked cards
                    CardStackView(
                        dueCards: dueCards,
                        currentIndex: currentIndex,
                        currentCard: currentCard,
                        showingAnswer: $showingAnswer
                    )

                    Spacer()

                    // Bottom buttons
                    if showingAnswer, let card = currentCard {
                        ReviewButtonsRow(card: card, onReview: reviewCard)
                            .padding(.bottom, 40)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Color.clear.frame(height: 80)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DottedGridBackground())
        .navigationTitle("Due Today")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("\(reviewedCount) / \(totalCards)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
        .background {
            // Hidden button for spacebar shortcut
            Button("") {
                if !showingAnswer {
                    withAnimation(.spring(response: 0.3)) {
                        showingAnswer = true
                    }
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
        }
        .onAppear {
            refreshDueCards()
        }
        .onChange(of: decks) { _, _ in
            refreshDueCards()
        }
    }

    private func reviewCard(_ card: Card, quality: Int) {
        card.review(quality: quality)
        reviewedCount += 1

        // Play sound effect
        if quality >= 3 {
            NSSound(named: "Pop")?.play()
        } else {
            NSSound(named: "Basso")?.play()
        }

        withAnimation(.spring(response: 0.4)) {
            showingAnswer = false
            if currentIndex < dueCards.count - 1 {
                currentIndex += 1
            } else {
                currentIndex = 0
            }
        }
    }
}

struct CardStackView: View {
    let dueCards: [Card]
    let currentIndex: Int
    let currentCard: Card?
    @Binding var showingAnswer: Bool

    private var remainingCards: Int {
        max(0, dueCards.count - currentIndex)
    }

    private var stackOffsets: [Int] {
        let count = min(3, remainingCards)
        guard count > 0 else { return [] }
        return Array(0..<count)
    }

    var body: some View {
        ZStack {
            // Background cards (stack effect)
            ForEach(stackOffsets, id: \.self) { offset in
                let reverseOffset = min(2, remainingCards - 1) - offset
                if reverseOffset > 0 {
                    StackedCardBackground(reverseOffset: reverseOffset)
                }
            }

            // Current card
            if let card = currentCard {
                StudyCardView(
                    card: card,
                    showingAnswer: $showingAnswer,
                    onReveal: {
                        withAnimation(.spring(response: 0.3)) {
                            showingAnswer = true
                        }
                    }
                )
                .id(card.id)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
}

struct StackedCardBackground: View {
    let reverseOffset: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.background)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.separator, lineWidth: 1)
            )
            .frame(width: 500, height: 350)
            .offset(y: CGFloat(reverseOffset) * 8)
            .scaleEffect(1 - CGFloat(reverseOffset) * 0.05)
            .opacity(1 - Double(reverseOffset) * 0.2)
    }
}

struct StudyCardView: View {
    let card: Card
    @Binding var showingAnswer: Bool
    var onReveal: () -> Void

    var body: some View {
        VStack {
            // Front content - top left
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.front)
                        .font(.title2)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)

                    if showingAnswer {
                        Divider()
                            .padding(.vertical, 8)

                        Text(card.back)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
            }

            Spacer()

            // Eye button - bottom right
            if !showingAnswer {
                HStack {
                    Spacer()
                    Button(action: onReveal) {
                        Image(systemName: "eye.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(32)
        .frame(width: 500, height: 350)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

struct ReviewButtonsRow: View {
    let card: Card
    let onReview: (Card, Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ReviewButton(title: "Forgot", shortcut: "1") {
                onReview(card, 0)
            }
            ReviewButton(title: "Hard", shortcut: "2") {
                onReview(card, 2)
            }
            ReviewButton(title: "Good", shortcut: "3") {
                onReview(card, 3)
            }
            ReviewButton(title: "Easy", shortcut: "4") {
                onReview(card, 5)
            }
        }
    }
}

struct ReviewButton: View {
    let title: String
    let shortcut: KeyEquivalent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(String(shortcut.character))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: [])
    }
}

struct AllCaughtUpView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("All caught up!")
                .font(.title2)

            Text("No cards due for review")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DottedGridBackground: View {
    let dotSize: CGFloat = 2
    let spacing: CGFloat = 20

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            // Pre-create the dot path once
            let dotPath = Circle().path(in: CGRect(x: -dotSize/2, y: -dotSize/2, width: dotSize, height: dotSize))
            let dotColor = GraphicsContext.Shading.color(.primary.opacity(0.1))

            let columns = Int(size.width / spacing) + 1
            let rows = Int(size.height / spacing) + 1

            for row in 0..<rows {
                for col in 0..<columns {
                    var dotContext = context
                    dotContext.translateBy(x: CGFloat(col) * spacing, y: CGFloat(row) * spacing)
                    dotContext.fill(dotPath, with: dotColor)
                }
            }
        }
        .drawingGroup() // Rasterize for better performance
    }
}

// Preview for individual components
#Preview("Study Card") {
    let card = Card(front: "こんにちは", back: "Hello")
    return StudyCardView(
        card: card,
        showingAnswer: .constant(true),
        onReveal: {}
    )
    .padding()
}

#Preview("Review Buttons") {
    let card = Card(front: "Test", back: "Test")
    return ReviewButtonsRow(card: card, onReview: { _, _ in })
        .padding()
}

#Preview("All Caught Up") {
    AllCaughtUpView()
}

//
//  DueTodayView.swift
//  saegim
//

import SwiftUI
import SwiftData
import AppKit

struct DueTodayView: View {
    @Query private var decks: [Deck]
    @State private var cardQueue: [Card] = []
    @State private var showingAnswer = false
    @State private var reviewedCount = 0
    @State private var totalToReview = 0

    private var currentCard: Card? { cardQueue.first }

    var body: some View {
        Group {
            if cardQueue.isEmpty {
                AllCaughtUpView()
            } else {
                VStack(spacing: 0) {
                    Spacer()

                    CardStackView(cardQueue: cardQueue, showingAnswer: $showingAnswer)

                    Spacer()

                    if showingAnswer, let card = currentCard {
                        ReviewButtonsRow(card: card, onReview: reviewCard)
                            .padding(.bottom, 40)
                    } else {
                        Color.clear.frame(height: 80)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Due Today")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("\(reviewedCount) / \(totalToReview)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .background {
            Button("") {
                if !showingAnswer && currentCard != nil {
                    showingAnswer = true
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
        }
        .onAppear(perform: refreshDueCards)
        .onChange(of: decks) { _, _ in refreshDueCards() }
    }

    private func refreshDueCards() {
        cardQueue = decks.flatMap { $0.cards.filter { $0.isDue || $0.repetitions == 0 } }.shuffled()
        totalToReview = cardQueue.count
        reviewedCount = 0
    }

    private func reviewCard(_ card: Card, quality: Int) {
        card.review(quality: quality)
        NSSound(named: quality >= 3 ? "Pop" : "Basso")?.play()

        showingAnswer = false
        cardQueue.removeFirst()

        if quality < 2 && cardQueue.count > 0 {
            cardQueue.insert(card, at: min(max(2, cardQueue.count), cardQueue.count))
        } else {
            reviewedCount += 1
        }
    }
}

struct CardStackView: View {
    let cardQueue: [Card]
    @Binding var showingAnswer: Bool

    var body: some View {
        ZStack {
            ForEach(Array(cardQueue.prefix(4).enumerated().reversed()), id: \.element.id) { index, card in
                if index > 0 {
                    StackedCardPreview(card: card, stackIndex: index)
                }
            }

            if let card = cardQueue.first {
                StudyCardView(card: card, showingAnswer: $showingAnswer) {
                    showingAnswer = true
                }
            }
        }
    }
}

struct StackedCardPreview: View {
    let card: Card
    let stackIndex: Int

    var body: some View {
        VStack {
            HStack {
                Text(card.front)
                    .font(.title3)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Spacer()
        }
        .padding(32)
        .frame(width: 500, height: 350)
        .background(Color(.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        .offset(y: CGFloat(stackIndex) * 12)
        .scaleEffect(1.0 - CGFloat(stackIndex) * 0.04)
        .opacity(1.0 - Double(stackIndex) * 0.15)
    }
}

struct StudyCardView: View {
    let card: Card
    @Binding var showingAnswer: Bool
    var onReveal: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(card.front)
                            .font(.title2)
                            .fontWeight(.medium)

                        if showingAnswer {
                            Text(card.back)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .padding(.top, 12)
                        }
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(32)
            .frame(width: 500, height: 350)
            .background(Color(.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.separator, lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 6)

            if !showingAnswer {
                Button(action: onReveal) {
                    Image(systemName: "eye.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .background(Color(.controlBackgroundColor), in: Circle())
                        .overlay(Circle().stroke(.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(24)
            }
        }
    }
}

struct ReviewButtonsRow: View {
    let card: Card
    let onReview: (Card, Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ReviewButton(title: "Forgot", shortcut: "1") { onReview(card, 0) }
            ReviewButton(title: "Hard", shortcut: "2") { onReview(card, 2) }
            ReviewButton(title: "Good", shortcut: "3") { onReview(card, 3) }
            ReviewButton(title: "Easy", shortcut: "4") { onReview(card, 5) }
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
                Text(title).font(.body.weight(.medium))
                Text(String(shortcut.character))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 1))
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
            Text("All caught up!").font(.title2)
            Text("No cards due for review").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DottedGridBackground: View {
    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            let dotPath = Circle().path(in: CGRect(x: -1, y: -1, width: 2, height: 2))
            let dotColor = GraphicsContext.Shading.color(.primary.opacity(0.1))

            for row in 0..<Int(size.height / 20) + 1 {
                for col in 0..<Int(size.width / 20) + 1 {
                    var c = context
                    c.translateBy(x: CGFloat(col) * 20, y: CGFloat(row) * 20)
                    c.fill(dotPath, with: dotColor)
                }
            }
        }
        .drawingGroup()
    }
}

#Preview("Study Card") {
    StudyCardView(card: Card(front: "こんにちは", back: "Hello"), showingAnswer: .constant(true), onReveal: {})
}

#Preview("All Caught Up") {
    AllCaughtUpView()
}

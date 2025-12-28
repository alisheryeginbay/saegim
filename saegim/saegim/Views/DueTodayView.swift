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
    @State private var dismissingCard: Card?
    @State private var dismissType: DismissType = .success

    enum DismissType {
        case success  // blur out
        case forgot   // back to stack
    }

    private var currentCard: Card? {
        cardQueue.first
    }

    private var progress: Double {
        guard totalToReview > 0 else { return 0 }
        return Double(reviewedCount) / Double(totalToReview)
    }

    private func refreshDueCards() {
        cardQueue = decks.flatMap { deck in
            deck.cards.filter { $0.isDue || $0.repetitions == 0 }
        }.shuffled()
        totalToReview = cardQueue.count
        reviewedCount = 0
    }

    var body: some View {
        Group {
            if cardQueue.isEmpty && dismissingCard == nil {
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
                        cardQueue: cardQueue,
                        showingAnswer: $showingAnswer,
                        dismissingCard: dismissingCard,
                        dismissType: dismissType
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
                Text("\(reviewedCount) / \(totalToReview)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
        .background {
            // Hidden button for spacebar shortcut
            Button("") {
                if !showingAnswer && currentCard != nil {
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

        // Play sound effect
        if quality >= 3 {
            NSSound(named: "Pop")?.play()
        } else {
            NSSound(named: "Basso")?.play()
        }

        // Set dismiss animation type
        dismissType = quality >= 2 ? .success : .forgot
        dismissingCard = card

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showingAnswer = false
            cardQueue.removeFirst()

            // If forgot, add back to queue (near end but not last)
            if quality < 2 && cardQueue.count > 0 {
                let insertIndex = max(0, cardQueue.count - 1)
                cardQueue.insert(card, at: min(insertIndex, max(2, cardQueue.count)))
            } else {
                reviewedCount += 1
            }
        }

        // Clear dismissing card after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismissingCard = nil
        }
    }
}

struct CardStackView: View {
    let cardQueue: [Card]
    @Binding var showingAnswer: Bool
    let dismissingCard: Card?
    let dismissType: DueTodayView.DismissType

    private let maxVisibleCards = 4

    var body: some View {
        ZStack {
            // Background stacked cards (show up to 4)
            ForEach(Array(cardQueue.prefix(maxVisibleCards).enumerated().reversed()), id: \.element.id) { index, card in
                if index > 0 {
                    StackedCardPreview(
                        card: card,
                        stackIndex: index,
                        totalVisible: min(cardQueue.count, maxVisibleCards)
                    )
                    .zIndex(Double(maxVisibleCards - index))
                }
            }

            // Dismissing card animation
            if let card = dismissingCard {
                DismissingCardView(
                    card: card,
                    dismissType: dismissType
                )
                .zIndex(100)
            }

            // Current card (front)
            if let card = cardQueue.first, dismissingCard?.id != card.id {
                StudyCardView(
                    card: card,
                    showingAnswer: $showingAnswer,
                    onReveal: {
                        withAnimation(.spring(response: 0.3)) {
                            showingAnswer = true
                        }
                    }
                )
                .zIndex(99)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .identity
                ))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: cardQueue.first?.id)
    }
}

struct StackedCardPreview: View {
    let card: Card
    let stackIndex: Int
    let totalVisible: Int

    private var yOffset: CGFloat {
        CGFloat(stackIndex) * 12
    }

    private var scale: CGFloat {
        1.0 - CGFloat(stackIndex) * 0.04
    }

    private var opacity: Double {
        1.0 - Double(stackIndex) * 0.15
    }

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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.separator.opacity(0.5), lineWidth: 1)
        )
        .offset(y: yOffset)
        .scaleEffect(scale)
        .opacity(opacity)
    }
}

struct DismissingCardView: View {
    let card: Card
    let dismissType: DueTodayView.DismissType

    @State private var animationProgress: CGFloat = 0

    private var blurRadius: CGFloat {
        dismissType == .success ? animationProgress * 10 : 0
    }

    private var cardOpacity: Double {
        1 - Double(animationProgress) * 0.5
    }

    private var cardScale: CGFloat {
        dismissType == .success ? 1 + animationProgress * 0.1 : 1 - animationProgress * 0.1
    }

    private var yOffset: CGFloat {
        dismissType == .forgot ? animationProgress * 50 : -animationProgress * 30
    }

    private var rotation: Double {
        dismissType == .forgot ? Double(animationProgress) * 5 : 0
    }

    var body: some View {
        StudyCardContent(card: card, showingAnswer: false)
            .blur(radius: blurRadius)
            .opacity(cardOpacity)
            .scaleEffect(cardScale)
            .offset(y: yOffset)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    animationProgress = 1
                }
            }
    }
}

struct StudyCardContent: View {
    let card: Card
    let showingAnswer: Bool

    var body: some View {
        VStack {
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
        }
        .padding(32)
        .frame(width: 500, height: 350)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

struct StudyCardView: View {
    let card: Card
    @Binding var showingAnswer: Bool
    var onReveal: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            StudyCardContent(card: card, showingAnswer: showingAnswer)

            // Eye button - bottom right
            if !showingAnswer {
                Button(action: onReveal) {
                    Image(systemName: "eye.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .glassEffect(.regular.interactive(), in: .circle)
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

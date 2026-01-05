//
//  DueTodayView_iOS.swift
//  saegim
//
//  iOS-optimized card review view
//

import SwiftUI
import UIKit
import AudioToolbox
import FSRSSwift

struct DueTodayView_iOS: View {
    @EnvironmentObject private var repository: DataRepository
    @State private var cardQueue: [CardModel] = []
    @State private var showingAnswer = false
    @State private var reviewedCount = 0
    @State private var totalToReview = 0

    private var currentCard: CardModel? { cardQueue.first }

    private func deckName(for card: CardModel) -> String? {
        guard let deckId = card.deckId else { return nil }
        return repository.findDeck(id: deckId)?.name
    }

    var body: some View {
        Group {
            if cardQueue.isEmpty {
                AllCaughtUpView_iOS()
            } else {
                VStack(spacing: 0) {
                    // Progress indicator
                    HStack {
                        Text("\(reviewedCount) / \(totalToReview)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let card = currentCard, let deckName = deckName(for: card) {
                            Text(deckName)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Spacer()

                    // Card
                    if let card = currentCard {
                        CardView_iOS(card: card, showingAnswer: showingAnswer)
                            .onTapGesture {
                                if !showingAnswer {
                                    withAnimation(.spring(duration: 0.3)) {
                                        showingAnswer = true
                                    }
                                }
                            }
                    }

                    Spacer()

                    // Review buttons
                    if showingAnswer, let card = currentCard {
                        ReviewButtons_iOS(card: card, onReview: reviewCard)
                            .padding(.bottom, 20)
                    } else {
                        // Tap to reveal hint
                        Text("Tap card to reveal answer")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        .onAppear(perform: refreshDueCards)
        .onChange(of: repository.allCards.count) { _, _ in refreshDueCards() }
    }

    private func refreshDueCards() {
        cardQueue = repository.allCards.filter { $0.isDue || $0.state == .new }.shuffled()
        totalToReview = cardQueue.count
        reviewedCount = 0
    }

    private func reviewCard(_ card: CardModel, rating: Rating) {
        var updatedCard = card
        updatedCard.review(rating: rating)

        Task {
            try? await repository.updateCard(updatedCard)
        }

        AudioServicesPlaySystemSound(rating != .again ? 1057 : 1053)

        showingAnswer = false
        cardQueue.removeFirst()

        if rating == .again && cardQueue.count > 0 {
            cardQueue.insert(updatedCard, at: min(2, cardQueue.count))
        } else {
            reviewedCount += 1
        }
    }
}

// MARK: - Card View

struct CardView_iOS: View {
    let card: CardModel
    let showingAnswer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(card.front)
                .font(.title2)
                .fontWeight(.medium)

            if showingAnswer {
                Divider()
                    .padding(.vertical, 8)

                Text(card.back)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .padding(.horizontal)
    }
}

// MARK: - Review Buttons

struct ReviewButtons_iOS: View {
    let card: CardModel
    let onReview: (CardModel, Rating) -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Top row: Again and Hard
            HStack(spacing: 12) {
                ReviewButton_iOS(
                    title: "Again",
                    subtitle: intervalText(.again),
                    color: .red
                ) {
                    onReview(card, .again)
                }

                ReviewButton_iOS(
                    title: "Hard",
                    subtitle: intervalText(.hard),
                    color: .orange
                ) {
                    onReview(card, .hard)
                }
            }

            // Bottom row: Good and Easy
            HStack(spacing: 12) {
                ReviewButton_iOS(
                    title: "Good",
                    subtitle: intervalText(.good),
                    color: .green
                ) {
                    onReview(card, .good)
                }

                ReviewButton_iOS(
                    title: "Easy",
                    subtitle: intervalText(.easy),
                    color: .blue
                ) {
                    onReview(card, .easy)
                }
            }
        }
        .padding(.horizontal)
    }

    private func intervalText(_ rating: Rating) -> String? {
        guard let states = card.previewNextStates() else { return nil }
        let info: SchedulingInfo = switch rating {
        case .again: states.again
        case .hard: states.hard
        case .good: states.good
        case .easy: states.easy
        }
        return formatInterval(info.interval)
    }

    private func formatInterval(_ days: UInt32) -> String {
        if days == 0 { return "<1d" }
        if days < 30 { return "\(days)d" }
        if days < 365 { return "\(days / 30)mo" }
        return "\(days / 365)y"
    }
}

struct ReviewButton_iOS: View {
    let title: String
    let subtitle: String?
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - All Caught Up View

struct AllCaughtUpView_iOS: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("All Caught Up!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("No cards due for review.\nCheck back later!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        DueTodayView_iOS()
            .navigationTitle("Due Today")
    }
}

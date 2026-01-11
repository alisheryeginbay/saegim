//
//  DueTodayView_iOS.swift
//  saegim
//
//  iOS card review view - Liquid Glass design
//

import SwiftUI
import UIKit
import AudioToolbox
import FSRSSwift

// MARK: - Types

struct SessionStats {
    var cardsReviewed = 0
    var correctAnswers = 0
    var startTime = Date()

    var accuracy: Double {
        guard cardsReviewed > 0 else { return 0 }
        return Double(correctAnswers) / Double(cardsReviewed) * 100
    }

    var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    mutating func record(rating: Rating) {
        cardsReviewed += 1
        if rating != .again { correctAnswers += 1 }
    }
}

// MARK: - Main View

struct DueTodayView_iOS: View {
    @EnvironmentObject private var repository: DataRepository

    @State private var cardQueue: [CardModel] = []
    @State private var reviewedCount = 0
    @State private var totalToReview = 0
    @State private var sessionStats = SessionStats()

    @State private var showingAnswer = false
    @State private var showSessionSummary = false
    @State private var cardId = UUID()

    private var currentCard: CardModel? { cardQueue.first }

    private func deckName(for card: CardModel) -> String? {
        guard let deckId = card.deckId else { return nil }
        return repository.findDeck(id: deckId)?.name
    }

    var body: some View {
        ZStack {
            if showSessionSummary {
                SessionCompleteView(stats: sessionStats) {
                    showSessionSummary = false
                    refreshDueCards()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if cardQueue.isEmpty {
                EmptyStateView()
            } else {
                studyContent
            }
        }
        .onAppear {
            sessionStats = SessionStats()
            refreshDueCards()
        }
        .onChange(of: repository.allCards.count) { _, _ in
            if !showSessionSummary { refreshDueCards() }
        }
    }

    private var studyContent: some View {
        VStack(spacing: 0) {
            // Glass header
            GlassHeader(
                current: reviewedCount,
                total: totalToReview,
                deckName: currentCard.flatMap { deckName(for: $0) }
            )

            // Card
            if let card = currentCard {
                GlassCard(card: card, isFlipped: showingAnswer)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !showingAnswer else { return }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingAnswer = true
                        }
                    }
                    .id(cardId)
            }

            // Button bar
            if showingAnswer, let card = currentCard {
                GlassButtonBar(card: card) { _, rating in
                    processReview(rating: rating)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            } else {
                Text("Tap to reveal")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
            }
        }
    }

    private func processReview(rating: Rating) {
        guard var card = currentCard else { return }

        // Update card scheduling
        card.review(rating: rating)

        // Update queue (use updated card for "again" reinsertion)
        cardQueue.removeFirst()
        if rating == .again && cardQueue.count > 0 {
            cardQueue.insert(card, at: min(2, cardQueue.count))
        } else {
            reviewedCount += 1
        }
        if rating != .again { sessionStats.record(rating: rating) }

        // Update UI state
        showingAnswer = false
        cardId = UUID()

        if cardQueue.isEmpty && totalToReview > 0 {
            showSessionSummary = true
        }

        // Persist to database
        persistCard(card)
    }

    private func persistCard(_ card: CardModel) {
        Task { @MainActor in
            do {
                try await repository.updateCard(card)
            } catch {
                print("Failed to persist card: \(error)")
            }
        }
    }

    private func refreshDueCards() {
        cardQueue = repository.allCards.filter { $0.isDue || $0.state == .new }.shuffled()
        totalToReview = cardQueue.count
        reviewedCount = 0
    }
}

// MARK: - Glass Header

struct GlassHeader: View {
    let current: Int
    let total: Int
    let deckName: String?

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(current)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                +
                Text(" / \(total)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                if let deckName = deckName {
                    Text(deckName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Progress bar
            GeometryReader { geo in
                Capsule()
                    .fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.primary.opacity(0.5))
                            .frame(width: geo.size.width * progress)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                    }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Glass Card

struct GlassCard: View {
    let card: CardModel
    let isFlipped: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if card.state == .new {
                Text("New")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.tertiary, in: Capsule())
                    .padding(.bottom, 16)
            }

            Text(card.front)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .lineSpacing(4)

            if isFlipped {
                Divider()
                    .padding(.vertical, 20)

                Text(card.back)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Flippable Card (compatibility)

struct FlippableCardView: View {
    let card: CardModel
    let isFlipped: Bool

    var body: some View {
        GlassCard(card: card, isFlipped: isFlipped)
    }
}

// MARK: - Glass Button Bar

struct GlassButtonBar: View {
    let card: CardModel
    let onReview: (CardModel, Rating) -> Void

    private var nextStates: NextStates? {
        card.previewNextStates()
    }

    var body: some View {
        let states = nextStates
        HStack(spacing: 8) {
            ForEach([Rating.again, .hard, .good, .easy], id: \.self) { rating in
                Button {
                    onReview(card, rating)
                } label: {
                    VStack(spacing: 3) {
                        Text(label(for: rating))
                            .font(.subheadline.weight(.medium))
                        Text(intervalText(for: rating, states: states))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
    }

    private func label(for rating: Rating) -> String {
        switch rating {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    private func intervalText(for rating: Rating, states: NextStates?) -> String {
        guard let states else { return "" }
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

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(in: .rect(cornerRadius: 22))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// Compatibility alias
struct ReviewButtonsBar: View {
    let card: CardModel
    let onReview: (CardModel, Rating) -> Void

    var body: some View {
        GlassButtonBar(card: card, onReview: onReview)
    }
}

// MARK: - Session Complete

struct SessionCompleteView: View {
    let stats: SessionStats
    let onDismiss: () -> Void

    var body: some View {
        ContentUnavailableView(
            "All Caught Up",
            systemImage: "checkmark.circle",
            description: Text("Great job! Come back later for more reviews.")
        )
        .onTapGesture {
            onDismiss()
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView(
            "All Caught Up",
            systemImage: "checkmark.circle",
            description: Text("No cards due right now.")
        )
    }
}

struct AllCaughtUpView_iOS: View {
    var body: some View { EmptyStateView() }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DueTodayView_iOS()
            .navigationTitle("Review")
    }
}

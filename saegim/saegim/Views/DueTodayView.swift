//
//  DueTodayView.swift
//  saegim
//

import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#else
import UIKit
import AudioToolbox
#endif
import FSRSSwift

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
        cardQueue = decks.flatMap { $0.cards.filter { $0.isDue || $0.state == .new } }.shuffled()
        totalToReview = cardQueue.count
        reviewedCount = 0
    }

    private func reviewCard(_ card: Card, rating: Rating) {
        card.review(rating: rating)
        #if canImport(AppKit)
        NSSound(named: rating != .again ? "Pop" : "Basso")?.play()
        #else
        AudioServicesPlaySystemSound(rating != .again ? 1057 : 1053)
        #endif

        showingAnswer = false
        cardQueue.removeFirst()

        // Re-insert "Again" cards back into queue for another attempt
        if rating == .again && cardQueue.count > 0 {
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
        #if os(macOS)
        .background(Color(.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
        #else
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24))
        #endif
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
            #if os(macOS)
            .background(Color(.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
            #else
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24))
            #endif
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.separator, lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 6)

            if !showingAnswer {
                Button(action: onReveal) {
                    Image(systemName: "eye.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        #if os(macOS)
                        .background(Color(.controlBackgroundColor), in: Circle())
                        #else
                        .background(Color(.secondarySystemBackground), in: Circle())
                        #endif
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
    let onReview: (Card, Rating) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ReviewButton(title: "Forgot", shortcut: "1", interval: intervalText(.again)) { onReview(card, .again) }
            ReviewButton(title: "Hard", shortcut: "2", interval: intervalText(.hard)) { onReview(card, .hard) }
            ReviewButton(title: "Good", shortcut: "3", interval: intervalText(.good)) { onReview(card, .good) }
            ReviewButton(title: "Easy", shortcut: "4", interval: intervalText(.easy)) { onReview(card, .easy) }
        }
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

struct ReviewButton: View {
    let title: String
    let shortcut: KeyEquivalent
    var interval: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.body.weight(.medium))
                    Text(String(shortcut.character))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let interval = interval {
                    Text(interval)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            #if os(macOS)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            #else
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            #endif
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

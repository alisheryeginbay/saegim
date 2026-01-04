//
//  AllCardsView.swift
//  saegim
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MarkdownUI
import AVFoundation
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

struct AllCardsView: View {
    @Query(sort: \Card.createdAt, order: .reverse) private var cards: [Card]
    @Query(sort: \Deck.name) private var decks: [Deck]
    @State private var searchText = ""
    @State private var selectedCard: Card?
    @State private var selectedDeckID: UUID?
    @State private var filteredCards: [Card] = []

    private func updateFilteredCards() {
        var result = cards

        if let deckID = selectedDeckID {
            result = result.filter { $0.deck?.id == deckID }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.front.localizedCaseInsensitiveContains(searchText) ||
                $0.back.localizedCaseInsensitiveContains(searchText)
            }
        }

        filteredCards = result
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                EmptyAllCardsView()
            } else {
                HSplitView {
                    List(filteredCards, selection: $selectedCard) { card in
                        CardRowView(card: card)
                            .tag(card)
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .frame(minWidth: 280, idealWidth: 400, maxHeight: .infinity)

                    if let card = selectedCard {
                        CardEditorPanel(card: card)
                            .frame(minWidth: 300, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("No Card Selected", systemImage: "rectangle.stack", description: Text("Select a card to edit"))
                            .frame(minWidth: 300, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle("All Cards")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search cards")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        selectedDeckID = nil
                    } label: {
                        if selectedDeckID == nil {
                            Label("All Decks", systemImage: "checkmark")
                        } else {
                            Text("All Decks")
                        }
                    }

                    Divider()

                    ForEach(decks) { deck in
                        Button {
                            selectedDeckID = deck.id
                        } label: {
                            if selectedDeckID == deck.id {
                                Label(deck.name, systemImage: "checkmark")
                            } else {
                                Text(deck.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        if let deckID = selectedDeckID,
                           let deck = decks.first(where: { $0.id == deckID }) {
                            Text(deck.name)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .onAppear {
            updateFilteredCards()
            if selectedCard == nil, let firstCard = filteredCards.first {
                selectedCard = firstCard
            }
        }
        .onChange(of: cards.count) { _, _ in
            updateFilteredCards()
        }
        .onChange(of: searchText) { _, _ in
            updateFilteredCards()
        }
        .onChange(of: selectedDeckID) { _, _ in
            updateFilteredCards()
        }
    }
}

struct CardRowView: View {
    let card: Card

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.front)
                    .lineLimit(1)

                Text(card.back)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let deck = card.deck {
                Text(deck.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch card.state {
        case .new:
            return .blue
        case .learning, .relearning:
            return .orange
        case .review:
            return card.isDue ? .orange : .green
        }
    }
}


// MARK: - Card Editor Panel

struct CardEditorPanel: View {
    @Bindable var card: Card
    @State private var showingPreview = false
    @State private var showingInfo = false
    @State private var activeField: CardField = .front

    enum CardField {
        case front, back
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Spacer()

                Button {
                    showingPreview = true
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 14))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                        .glassEffect(.regular.interactive())
                }
                .buttonStyle(.plain)
                .help("Preview")

                Button {
                    showingInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                        .glassEffect(.regular.interactive())
                }
                .buttonStyle(.plain)
                .help("Info")
                .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                    CardInfoPopover(card: card)
                }

                Menu {
                    Button {
                        insertImage(for: .front)
                    } label: {
                        Label("Add Image to Front", systemImage: "photo")
                    }
                    Button {
                        insertImage(for: .back)
                    } label: {
                        Label("Add Image to Back", systemImage: "photo")
                    }
                    Divider()
                    Button {
                        insertAudio(for: .front)
                    } label: {
                        Label("Add Audio to Front", systemImage: "waveform")
                    }
                    Button {
                        insertAudio(for: .back)
                    } label: {
                        Label("Add Audio to Back", systemImage: "waveform")
                    }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                        .glassEffect(.regular.interactive())
                }
                .buttonStyle(.plain)
                .help("Add Media")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Editor content - both take equal height
            VStack(spacing: 0) {
                CardSideEditor(title: "Front", text: $card.front)
                Divider().padding(.horizontal, 16)
                CardSideEditor(title: "Back", text: $card.back)
            }
        }
        .onChange(of: card.front) { _, _ in
            card.modifiedAt = Date()
        }
        .onChange(of: card.back) { _, _ in
            card.modifiedAt = Date()
        }
        .sheet(isPresented: $showingPreview) {
            CardPreviewSheet(card: card)
        }
    }

    private func insertImage(for field: CardField) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let sourceURL = panel.url {
            guard let relativePath = MediaStorage.store(from: sourceURL) else { return }
            let url = MediaStorage.buildURL(relativePath: relativePath)
            let markdown = "![\(sourceURL.lastPathComponent)](\(url))"
            switch field {
            case .front:
                card.front += "\n\(markdown)"
            case .back:
                card.back += "\n\(markdown)"
            }
        }
    }

    private func insertAudio(for field: CardField) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let sourceURL = panel.url {
            guard let relativePath = MediaStorage.store(from: sourceURL) else { return }
            let url = MediaStorage.buildURL(relativePath: relativePath)
            let markdown = "[🔊 \(sourceURL.lastPathComponent)](\(url))"
            switch field {
            case .front:
                card.front += "\n\(markdown)"
            case .back:
                card.back += "\n\(markdown)"
            }
        }
    }
}

// MARK: - Card Info Popover

struct CardInfoPopover: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout)
                }
            } icon: {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(.secondary)
            }

            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout)
                }
            } icon: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }

            if card.state != .new {
                Divider()

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reviews")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(card.totalReviews) total • \(Int(card.successRate * 100))% correct")
                            .font(.callout)
                    }
                } icon: {
                    Image(systemName: "chart.bar")
                        .foregroundStyle(.secondary)
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next Review")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(card.nextReviewDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.callout)
                    }
                } icon: {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
}

// MARK: - Card Preview Sheet

struct CardPreviewSheet: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @State private var showingAnswer = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Card preview
            ScrollView {
                VStack {
                    Spacer(minLength: 40)

                    VStack(spacing: 24) {
                        // Front
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Front")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            MarkdownContentView(content: card.front)
                                .font(.title2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if showingAnswer {
                            Divider()

                            // Back
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Back")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                MarkdownContentView(content: card.back)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(32)
                    .frame(maxWidth: 500)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.secondary)

            // Show answer button
            if !showingAnswer {
                Divider()
                Button("Show Answer") {
                    withAnimation {
                        showingAnswer = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

// MARK: - Media URL Resolver

enum MediaURLResolver {
    static func resolve(_ url: URL?) -> URL? {
        guard let url = url else { return nil }
        return MediaStorage.resolve(url)
    }
}

// MARK: - Local File Image Provider

struct LocalFileImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        LocalImageView(url: url)
    }
}

struct LocalImageView: View {
    let url: URL?
    @State private var loadedImage: PlatformImage?
    @State private var didAttemptLoad = false

    var body: some View {
        Group {
            if let platformImage = loadedImage {
                #if canImport(AppKit)
                Image(nsImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                #else
                Image(uiImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                #endif
            } else if didAttemptLoad {
                Label("Image not found", systemImage: "photo")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(width: 50, height: 50)
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        guard let url = url else {
            didAttemptLoad = true
            return
        }

        guard let resolved = MediaURLResolver.resolve(url) else {
            didAttemptLoad = true
            return
        }

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: resolved.path) {
            didAttemptLoad = true
            return
        }

        #if canImport(AppKit)
        if let image = NSImage(contentsOf: resolved) {
            loadedImage = image
        }
        #else
        if let data = try? Data(contentsOf: resolved), let image = UIImage(data: data) {
            loadedImage = image
        }
        #endif
        didAttemptLoad = true
    }
}

// MARK: - Markdown Content View

struct MarkdownContentView: View {
    let content: String

    /// Content segments in order - text, images, and audio
    private enum ContentSegment: Identifiable {
        case text(String)
        case image(alt: String, path: String)
        case audio(name: String, path: String)

        var id: String {
            switch self {
            case .text(let text): return "text-\(text.hashValue)"
            case .image(_, let path): return "image-\(path)"
            case .audio(_, let path): return "audio-\(path)"
            }
        }
    }

    private var segments: [ContentSegment] {
        var result: [ContentSegment] = []

        // Combined pattern for audio and images
        let audioPattern = #"\[🔊 ([^\]]+)\]\(([^)]+)\)"#
        let imagePattern = #"!\[([^\]]*)\]\((saegim://[^)]+)\)"#
        let combinedPattern = "(\(audioPattern))|(\(imagePattern))"

        guard let regex = try? NSRegularExpression(pattern: combinedPattern) else {
            return [.text(content)]
        }

        var lastEnd = content.startIndex

        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))

        for match in matches {
            guard let matchRange = Range(match.range, in: content) else { continue }

            // Add text before this match
            if lastEnd < matchRange.lowerBound {
                let textBefore = String(content[lastEnd..<matchRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !textBefore.isEmpty {
                    result.append(.text(textBefore))
                }
            }

            // Check if it's audio (group 1) or image (group 4)
            if match.range(at: 1).location != NSNotFound,
               let nameRange = Range(match.range(at: 2), in: content),
               let pathRange = Range(match.range(at: 3), in: content) {
                // Audio match
                let name = String(content[nameRange])
                let path = String(content[pathRange])
                result.append(.audio(name: name, path: path))
            } else if match.range(at: 4).location != NSNotFound,
                      let altRange = Range(match.range(at: 5), in: content),
                      let pathRange = Range(match.range(at: 6), in: content) {
                // Image match
                let alt = String(content[altRange])
                let path = String(content[pathRange])
                result.append(.image(alt: alt, path: path))
            }

            lastEnd = matchRange.upperBound
        }

        // Add remaining text after last match
        if lastEnd < content.endIndex {
            let textAfter = String(content[lastEnd...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !textAfter.isEmpty {
                result.append(.text(textAfter))
            }
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(segments) { segment in
                switch segment {
                case .text(let text):
                    Markdown(text)
                case .image(_, let path):
                    LocalImageView(url: URL(string: path))
                case .audio(let name, let path):
                    AudioPlayerButton(path: path, name: name)
                }
            }
        }
    }
}

// MARK: - Audio Player Button

struct AudioPlayerButton: View {
    let path: String
    let name: String
    @State private var player = AudioPlayerManager()

    var body: some View {
        Button {
            togglePlayback()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                Text(name)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func togglePlayback() {
        if player.isPlaying {
            player.stop()
        } else {
            guard let inputURL = URL(string: path),
                  let resolvedURL = MediaURLResolver.resolve(inputURL) else { return }
            player.play(url: resolvedURL)
        }
    }
}

@Observable
class AudioPlayerManager: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    private var audioPlayer: AVAudioPlayer?

    func play(url: URL) {
        // Stop any existing playback
        audioPlayer?.stop()
        audioPlayer = nil

        // Check if file exists and get size
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            NSLog("Audio file not found: %@", url.path)
            isPlaying = false
            return
        }

        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            NSLog("Audio file: %@, size: %lld bytes", url.lastPathComponent, size)
        }

        // Check first bytes to identify format
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            let header = data.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
            NSLog("Audio header bytes: %@", header)
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()

            // Keep strong reference before playing
            audioPlayer = player

            let success = player.play()
            isPlaying = success
            NSLog("Audio play started: %@, duration: %.2f sec, success: %d", url.lastPathComponent, player.duration, success ? 1 : 0)
        } catch {
            NSLog("Failed to play audio %@: %@", url.lastPathComponent, error.localizedDescription)
            isPlaying = false
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        NSLog("Audio finished playing, success: %d", flag ? 1 : 0)
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
}

struct CardSideEditor: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 5)

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxHeight: .infinity)
    }
}


struct EmptyAllCardsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Cards Yet")
                .font(.title2)
                .fontWeight(.medium)

            Text("Create a deck and add some cards to get started")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        AllCardsView()
    }
    .modelContainer(for: [Card.self, Deck.self], inMemory: true)
}

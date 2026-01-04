//
//  AnkiImportView.swift
//  saegim
//
//  View for importing Anki .apkg files
//  Uses Rust-based AnkiParser for high-performance parsing
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AnkiParser

struct AnkiImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var currentProgress: AnkiProgress = .extracting
    @State private var selectedURL: URL?
    @State private var importResult: ImportResult?
    @State private var isRunning = false

    enum ImportResult {
        case success(deckName: String, cardCount: Int, deckCount: Int)
        case failure(error: String)
    }

    private var progressValue: Double {
        switch currentProgress {
        case .extracting:
            return 0.1
        case .readingDecks:
            return 0.2
        case .readingCards:
            return 0.5
        case .processingMedia:
            return 0.75
        case .complete:
            return 1.0
        }
    }

    private var progressText: String {
        switch currentProgress {
        case .extracting:
            return "Extracting archive..."
        case .readingDecks:
            return "Reading decks..."
        case .readingCards:
            return "Reading cards..."
        case .processingMedia:
            return "Processing media..."
        case .complete:
            return "Complete"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

                Text("Import from Anki")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 28, height: 28)
            }
            .padding()
            .background(.bar)

            Divider()

            // Content
            VStack(spacing: 24) {
                if isRunning {
                    // Importing state
                    VStack(spacing: 16) {
                        ProgressView(value: progressValue)
                            .progressViewStyle(.linear)

                        Text(progressText)
                            .foregroundStyle(.secondary)
                    }
                    .padding(40)
                } else if let result = importResult {
                    // Result state
                    switch result {
                    case .success(let deckName, let cardCount, let deckCount):
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.green)

                            Text("Import Successful")
                                .font(.title2.weight(.semibold))

                            if deckCount > 1 {
                                Text("Imported \(deckCount) decks with \(cardCount) cards")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Created \"\(deckName)\" with \(cardCount) cards")
                                    .foregroundStyle(.secondary)
                            }

                            Button("Done") {
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
                        }
                        .padding(40)

                    case .failure(let error):
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.red)

                            Text("Import Failed")
                                .font(.title2.weight(.semibold))

                            Text(error)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Try Again") {
                                importResult = nil
                                selectedURL = nil
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
                        }
                        .padding(40)
                    }
                } else {
                    // Initial state
                    VStack(spacing: 20) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("Select an Anki file to import")
                            .font(.title3)

                        Text("Supports .apkg and .colpkg files")
                            .foregroundStyle(.secondary)

                        Button("Choose File...") {
                            showingFilePicker = true
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .padding(40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 450, height: 350)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [
                UTType(filenameExtension: "apkg") ?? .data,
                UTType(filenameExtension: "colpkg") ?? .data
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedURL = url
                    startImport(from: url)
                }
            case .failure(let error):
                importResult = .failure(error: error.localizedDescription)
            }
        }
    }

    @State private var showingFilePicker = false

    private func startImport(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importResult = .failure(error: "Cannot access the selected file")
            return
        }

        selectedURL = url
        isRunning = true
        currentProgress = .extracting

        // Create handler - progress updates handled internally
        let handler = ImportProgressHandler()

        // Run parsing AND processing on background thread
        Task.detached(priority: .userInitiated) {
            do {
                let collection = try parseAnkiFile(
                    filePath: url.path,
                    progressCallback: handler
                )

                // Process collection data on background thread
                let processedData = await self.processCollectionInBackground(collection)

                // Only SwiftData operations on main thread
                await MainActor.run {
                    self.insertProcessedData(processedData)
                    url.stopAccessingSecurityScopedResource()
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self.importResult = .failure(error: error.localizedDescription)
                    url.stopAccessingSecurityScopedResource()
                    self.isRunning = false
                }
            }
        }
    }

    /// Processed card data ready for SwiftData insertion
    private struct ProcessedCard {
        let front: String
        let back: String
        let deckId: Int64
    }

    /// Processed deck data
    private struct ProcessedDeck {
        let id: Int64
        let name: String
        let shortName: String
        let parentPath: String?
    }

    /// Result of background processing
    private struct ProcessedData {
        let decks: [ProcessedDeck]
        let cards: [ProcessedCard]
        let mediaMapping: [String: String]
        let primaryDeckName: String
    }

    /// Process collection data on background thread (no SwiftData)
    nonisolated private func processCollectionInBackground(_ collection: AnkiCollection) async -> ProcessedData {
        NSLog("=== Processing collection in background ===")

        // Copy media files and build filename mapping
        var mediaMapping: [String: String] = [:]

        let mediaFilenames = collection.media.filenames()
        NSLog("Total media files: %d", mediaFilenames.count)

        for filename in mediaFilenames {
            let ext = (filename as NSString).pathExtension.lowercased()
            guard let mediaType = MediaType.from(extension: ext) else { continue }
            guard let data = collection.media.dataFor(filename: filename) else { continue }

            if let relativePath = MediaStorage.store(data, extension: ext, type: mediaType) {
                mediaMapping[filename] = MediaStorage.buildURL(relativePath: relativePath, type: mediaType)
            }
        }

        NSLog("Media mapping: %d entries", mediaMapping.count)

        // Process decks (just extract data, no SwiftData)
        var processedDecks: [ProcessedDeck] = []
        let sortedDecks = collection.decks.sorted { a, b in
            a.name.components(separatedBy: "::").count < b.name.components(separatedBy: "::").count
        }

        for ankiDeck in sortedDecks {
            let components = ankiDeck.name.components(separatedBy: "::")
            let shortName = components.last ?? ankiDeck.name
            let parentPath = components.count > 1 ? components.dropLast().joined(separator: "::") : nil

            processedDecks.append(ProcessedDeck(
                id: ankiDeck.id,
                name: ankiDeck.name,
                shortName: shortName,
                parentPath: parentPath
            ))
        }

        // Process cards (string processing only, no SwiftData)
        var processedCards: [ProcessedCard] = []
        let mediaRegex = try? NSRegularExpression(pattern: #"media:([^\s\)\]]+)"#, options: [])

        NSLog("Processing cards from %d decks", collection.cardsByDeck.count)

        for (deckIdStr, ankiCards) in collection.cardsByDeck {
            guard let deckId = Int64(deckIdStr) else { continue }

            for ankiCard in ankiCards {
                let frontFields = ankiCard.fields.prefix(1).map { cleanAndReplaceMediaFast($0, mediaMapping: mediaMapping, regex: mediaRegex) }.joined(separator: "\n")
                let backFields = ankiCard.fields.dropFirst().map { cleanAndReplaceMediaFast($0, mediaMapping: mediaMapping, regex: mediaRegex) }.joined(separator: "\n")

                guard !frontFields.isEmpty || !backFields.isEmpty else { continue }

                processedCards.append(ProcessedCard(front: frontFields, back: backFields, deckId: deckId))
            }
        }

        NSLog("Processed %d cards", processedCards.count)

        let primaryDeckName = collection.rootDecks.first?.shortName ?? "Imported"

        return ProcessedData(
            decks: processedDecks,
            cards: processedCards,
            mediaMapping: mediaMapping,
            primaryDeckName: primaryDeckName
        )
    }

    /// Insert processed data into SwiftData (main thread only)
    private func insertProcessedData(_ data: ProcessedData) {
        NSLog("=== Inserting into SwiftData ===")

        // Build deck hierarchy
        var deckIdMap: [Int64: Deck] = [:]
        var deckPathMap: [String: Deck] = [:]

        for processedDeck in data.decks {
            var parentDeck: Deck? = nil
            if let parentPath = processedDeck.parentPath {
                parentDeck = deckPathMap[parentPath]
            }

            let deck = Deck(name: processedDeck.shortName, description: "Imported from Anki")
            deck.parent = parentDeck
            modelContext.insert(deck)

            if let parent = parentDeck {
                parent.subdecks.append(deck)
            }

            deckIdMap[processedDeck.id] = deck
            deckPathMap[processedDeck.name] = deck
        }

        // Insert cards
        var totalImportedCards = 0
        for processedCard in data.cards {
            guard let deck = deckIdMap[processedCard.deckId] else { continue }

            let card = Card(front: processedCard.front, back: processedCard.back, deck: deck)
            modelContext.insert(card)
            totalImportedCards += 1
        }

        // Delete empty root decks (use cardCount, not recursive totalCardCount)
        var importedDeckCount = data.decks.count
        for (_, deck) in deckIdMap {
            if deck.cardCount == 0 && deck.subdecks.isEmpty && deck.parent == nil {
                modelContext.delete(deck)
                importedDeckCount -= 1
            }
        }

        try? modelContext.save()

        NSLog("=== IMPORT COMPLETE: %d cards, %d decks ===", totalImportedCards, importedDeckCount)

        importResult = .success(
            deckName: data.primaryDeckName,
            cardCount: totalImportedCards,
            deckCount: importedDeckCount
        )
    }

    /// Clean HTML and replace media: prefix with saegim:// URLs
    /// Optimized: uses pre-compiled regex to find media references
    nonisolated private func cleanAndReplaceMediaFast(_ html: String, mediaMapping: [String: String], regex: NSRegularExpression?) -> String {
        // Use Rust to clean HTML (converts [sound:x] to [🔊 x](media:x) etc.)
        let text = cleanHtmlToMarkdown(html: html)

        // Fast path: if no media prefix, return early
        guard text.contains("media:"), let regex = regex else { return text }

        var result = text
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }

            let filenameRange = match.range(at: 1)
            let fullRange = match.range(at: 0)
            let filename = nsText.substring(with: filenameRange)

            // Try to find the URL in mapping (check different normalizations)
            let url = mediaMapping[filename]
                ?? mediaMapping[filename.precomposedStringWithCanonicalMapping]
                ?? mediaMapping[filename.decomposedStringWithCanonicalMapping]

            if let url = url {
                result = (result as NSString).replacingCharacters(in: fullRange, with: url)
            }
        }

        return result
    }
}

/// Progress callback handler for Rust parser
/// Thread-safe wrapper for progress updates from Rust - nonisolated for use across actor boundaries
final class ImportProgressHandler: AnkiProgressCallback, @unchecked Sendable {
    private let lock = NSLock()
    private var _currentProgress: AnkiProgress = .extracting
    private let onUpdate: @Sendable (AnkiProgress) -> Void

    init(onUpdate: @escaping @Sendable (AnkiProgress) -> Void = { _ in }) {
        self.onUpdate = onUpdate
    }

    var currentProgress: AnkiProgress {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _currentProgress
        }
        set {
            lock.lock()
            _currentProgress = newValue
            lock.unlock()
        }
    }

    nonisolated func onProgress(progress: AnkiProgress) {
        lock.lock()
        _currentProgress = progress
        lock.unlock()
        onUpdate(progress)
    }
}

#Preview {
    AnkiImportView()
        .modelContainer(for: [Card.self, Deck.self], inMemory: true)
}

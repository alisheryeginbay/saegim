//
//  AnkiImportView.swift
//  saegim
//
//  View for importing Anki .apkg files
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AnkiToMarkdown
import zstd

struct AnkiImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var operation = AnkiImportOperation()
    @State private var selectedURL: URL?
    @State private var importResult: ImportResult?
    @State private var showingFilePicker = false

    enum ImportResult {
        case success(deckName: String, cardCount: Int, deckCount: Int)
        case failure(error: String)
    }

    private var progressValue: Double {
        switch operation.progress {
        case .extracting:
            return 0.1
        case .readingDecks:
            return 0.2
        case .readingCards(let current, let total):
            return 0.2 + 0.5 * (Double(current) / Double(max(1, total)))
        case .parsingMedia:
            return 0.75
        }
    }

    private var progressText: String {
        switch operation.progress {
        case .extracting:
            return "Extracting archive..."
        case .readingDecks:
            return "Reading decks..."
        case .readingCards(let current, _):
            return "Reading \(current) cards..."
        case .parsingMedia:
            return "Processing media..."
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
                if operation.isRunning {
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
        .onChange(of: operation.isRunning) { wasRunning, isRunning in
            // When operation finishes (was running, now stopped)
            if wasRunning && !isRunning {
                if let collection = operation.collection {
                    processCollection(collection)
                } else if let error = operation.error {
                    importResult = .failure(error: error.localizedDescription)
                }
            }
        }
    }

    private func startImport(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importResult = .failure(error: "Cannot access the selected file")
            return
        }
        selectedURL = url
        operation.start(from: url)
    }

    private func processCollection(_ collection: AnkiCollection) {
        NSLog("=== processCollection CALLED ===")

        defer {
            selectedURL?.stopAccessingSecurityScopedResource()
        }

        let fileManager = FileManager.default

        // Setup media directories in Application Support
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            importResult = .failure(error: "Cannot access Application Support directory")
            return
        }

        let imagesDir = appSupport.appendingPathComponent("Saegim/images", isDirectory: true)
        let audioDir = appSupport.appendingPathComponent("Saegim/audio", isDirectory: true)
        try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)

        // Copy media files and build filename mapping
        var mediaMapping: [String: String] = [:] // original filename -> new saegim:// URL

        NSLog("=== ANKI IMPORT DEBUG ===")
        NSLog("Total media files in collection: %d", collection.media.filenames.count)

        // Dump ALL filenames to see what's actually in the package
        NSLog("=== ALL MEDIA FILENAMES (first 50) ===")
        for (index, filename) in collection.media.filenames.prefix(50).enumerated() {
            NSLog("  [%d] %@", index, filename)
        }

        // Check for .wav files specifically
        let wavFilesInCollection = collection.media.filenames.filter { $0.lowercased().hasSuffix(".wav") }
        NSLog("WAV files in collection.media.filenames: %d", wavFilesInCollection.count)
        for filename in wavFilesInCollection.prefix(20) {
            NSLog("  WAV in collection: %@", filename)
        }

        // Process each media file using data() method to get raw bytes
        for filename in collection.media.filenames {
            let ext = (filename as NSString).pathExtension.lowercased()
            let isAudio = ["mp3", "wav", "m4a", "ogg", "flac", "aac"].contains(ext)
            let isImage = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg"].contains(ext)

            guard isAudio || isImage else { continue }

            // Get raw data from the library
            guard var data = collection.media.data(for: filename) else {
                NSLog("No data for media file: %@", filename)
                continue
            }

            // Log original header bytes for debugging
            let originalHeader = data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")

            // Check if data is zstd-compressed (magic bytes: 28 B5 2F FD)
            if data.count >= 4 && data[0] == 0x28 && data[1] == 0xB5 && data[2] == 0x2F && data[3] == 0xFD {
                let compressedSize = data.count
                do {
                    let inputStream = InputStream(data: data)
                    let outputStream = OutputStream(toMemory: ())
                    inputStream.open()
                    outputStream.open()
                    try ZStd.decompress(src: inputStream, dst: outputStream)
                    inputStream.close()
                    outputStream.close()
                    if let decompressed = outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data {
                        let decompressedHeader = decompressed.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
                        NSLog("Decompressed %@: %d -> %d bytes, header: %@", filename, compressedSize, decompressed.count, decompressedHeader)
                        data = decompressed
                    } else {
                        NSLog("WARNING: Decompression returned nil for %@", filename)
                    }
                } catch {
                    NSLog("Failed to decompress %@: %@", filename, error.localizedDescription)
                }
            } else {
                NSLog("Not zstd-compressed: %@ (header: %@)", filename, originalHeader)
            }

            let uniqueName = "\(UUID().uuidString).\(ext)"
            let destDir = isAudio ? audioDir : imagesDir
            let destURL = destDir.appendingPathComponent(uniqueName)

            do {
                try data.write(to: destURL)

                if isAudio {
                    mediaMapping[filename] = "saegim://audio/\(uniqueName)"
                    NSLog("Audio copied: %@ -> %@ (%d bytes)", filename, uniqueName, data.count)
                } else {
                    // Verify image header bytes for validation
                    let header = data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
                    let isValidJPEG = data.count >= 2 && data[0] == 0xFF && data[1] == 0xD8
                    let isValidPNG = data.count >= 8 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47
                    let isValidGIF = data.count >= 6 && data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46
                    let isValidWebP = data.count >= 12 && data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46

                    if isValidJPEG || isValidPNG || isValidGIF || isValidWebP {
                        NSLog("Image copied: %@ -> %@ (%d bytes, valid)", filename, uniqueName, data.count)
                    } else {
                        NSLog("WARNING: Image copied but header looks invalid: %@ -> %@ (%d bytes, header: %@)", filename, uniqueName, data.count, header)
                    }

                    mediaMapping[filename] = "saegim://images/\(uniqueName)"
                }
            } catch {
                NSLog("Failed to write media %@: %@", filename, error.localizedDescription)
            }
        }

        NSLog("Media mapping created with %d entries", mediaMapping.count)

        // Log media files by extension
        let wavFiles = mediaMapping.filter { $0.key.lowercased().hasSuffix(".wav") }
        let mp3Files = mediaMapping.filter { $0.key.lowercased().hasSuffix(".mp3") }
        let jpgFiles = mediaMapping.filter { $0.key.lowercased().hasSuffix(".jpg") || $0.key.lowercased().hasSuffix(".jpeg") }
        let pngFiles = mediaMapping.filter { $0.key.lowercased().hasSuffix(".png") }
        NSLog("Audio files: %d WAV, %d MP3", wavFiles.count, mp3Files.count)
        NSLog("Image files: %d JPG/JPEG, %d PNG", jpgFiles.count, pngFiles.count)

        // Log first 10 WAV files if any
        if !wavFiles.isEmpty {
            NSLog("WAV files found:")
            for (key, _) in wavFiles.prefix(10) {
                NSLog("  WAV: %@", key)
            }
        }

        // Log first 10 MP3 files
        NSLog("Sample MP3 files:")
        for (key, _) in mp3Files.prefix(10) {
            NSLog("  MP3: %@", key)
        }

        // Check for Korean characters in any media filename
        let koreanFiles = mediaMapping.filter { $0.key.range(of: "\\p{Hangul}", options: .regularExpression) != nil }
        NSLog("Files with Korean characters: %d", koreanFiles.count)
        for (key, _) in koreanFiles.prefix(10) {
            NSLog("  Korean: %@", key)
        }

        // Build deck hierarchy
        var deckIdMap: [Int64: Deck] = [:]
        var deckPathMap: [String: Deck] = [:]
        var importedDeckCount = 0

        let sortedDecks = collection.decks.sorted { a, b in
            a.name.components(separatedBy: "::").count < b.name.components(separatedBy: "::").count
        }

        for ankiDeck in sortedDecks {
            let components = ankiDeck.name.components(separatedBy: "::")
            let shortName = components.last ?? ankiDeck.name
            let parentPath = components.count > 1 ? components.dropLast().joined(separator: "::") : nil

            var parentDeck: Deck? = nil
            if let path = parentPath {
                parentDeck = deckPathMap[path]
            }

            let deck = Deck(name: shortName, description: "Imported from Anki")
            deck.parent = parentDeck
            modelContext.insert(deck)

            if let parent = parentDeck {
                parent.subdecks.append(deck)
            }

            deckIdMap[ankiDeck.id] = deck
            deckPathMap[ankiDeck.name] = deck
            importedDeckCount += 1
        }

        // Import cards
        var totalImportedCards = 0
        var samplePrinted = 0
        var soundCardsFound = 0

        NSLog("=== IMPORTING CARDS ===")
        NSLog("Total decks with cards: %d", collection.cardsByDeck.count)

        for (deckId, ankiCards) in collection.cardsByDeck {
            guard let deck = deckIdMap[deckId] else { continue }

            NSLog("Deck %lld: %d cards", deckId, ankiCards.count)

            for ankiCard in ankiCards {
                // Check ALL fields for sound, not just front/back
                let allContent = ankiCard.fields.joined(separator: " ")
                let hasMedia = !ankiCard.mediaReferences.isEmpty

                if hasMedia || allContent.contains("[sound:") {
                    soundCardsFound += 1
                    if samplePrinted < 5 {
                        NSLog("Card with media #%d:", soundCardsFound)
                        NSLog("  Fields count: %d", ankiCard.fields.count)
                        for (i, field) in ankiCard.fields.enumerated() {
                            NSLog("  Field %d: %@", i, String(field.prefix(200)))
                        }
                        NSLog("  Media refs: %@", ankiCard.mediaReferences.joined(separator: ", "))
                        samplePrinted += 1
                    }
                }

                // Print first 3 cards regardless
                if totalImportedCards < 3 {
                    NSLog("Sample card #%d:", totalImportedCards)
                    NSLog("  Fields count: %d", ankiCard.fields.count)
                    for (i, field) in ankiCard.fields.enumerated() {
                        NSLog("  Field %d: %@", i, String(field.prefix(200)))
                    }
                }

                // Process ALL fields, not just first two
                let frontFields = ankiCard.fields.prefix(1).map { cleanHTML($0, mediaMapping: mediaMapping) }.joined(separator: "\n")
                let backFields = ankiCard.fields.dropFirst().map { cleanHTML($0, mediaMapping: mediaMapping) }.joined(separator: "\n")

                let front = frontFields
                let back = backFields

                guard !front.isEmpty || !back.isEmpty else { continue }

                let card = Card(front: front, back: back, deck: deck)
                modelContext.insert(card)
                totalImportedCards += 1
            }
        }

        // Delete empty decks (no cards and no subdecks with cards)
        var deletedEmptyDecks = 0
        for (_, deck) in deckIdMap {
            if deck.totalCardCount == 0 && deck.parent == nil {
                // Top-level deck with no cards - delete it
                modelContext.delete(deck)
                deletedEmptyDecks += 1
                importedDeckCount -= 1
            }
        }

        if deletedEmptyDecks > 0 {
            NSLog("Deleted %d empty decks", deletedEmptyDecks)
        }

        try? modelContext.save()

        NSLog("=== IMPORT COMPLETE ===")
        NSLog("Total cards imported: %d", totalImportedCards)
        NSLog("Cards with sound tags found: %d", soundCardsFound)
        NSLog("Media files mapped: %d", mediaMapping.count)

        let primaryDeckName = collection.rootDecks.first?.shortName ?? selectedURL?.deletingPathExtension().lastPathComponent ?? "Imported"
        importResult = .success(
            deckName: primaryDeckName,
            cardCount: totalImportedCards,
            deckCount: importedDeckCount
        )
    }

    private func cleanHTML(_ html: String, mediaMapping: [String: String]) -> String {
        var text = html

        // Convert Anki sound references [sound:filename.mp3] to markdown audio
        if let soundRegex = try? NSRegularExpression(pattern: "\\[sound:([^\\]]+)\\]", options: .caseInsensitive) {
            let matches = soundRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                if let filenameRange = Range(match.range(at: 1), in: text),
                   let fullRange = Range(match.range, in: text) {
                    let filename = String(text[filenameRange])
                    // Try multiple matching strategies for the filename
                    let normalizedFilename = filename.precomposedStringWithCanonicalMapping // NFC normalization
                    let decomposedFilename = filename.decomposedStringWithCanonicalMapping // NFD normalization

                    let saegimURL = mediaMapping[filename]
                        ?? mediaMapping[normalizedFilename]
                        ?? mediaMapping[decomposedFilename]
                        ?? mediaMapping.first { $0.key.lowercased() == filename.lowercased() }?.value
                        ?? mediaMapping.first { $0.key.precomposedStringWithCanonicalMapping == normalizedFilename }?.value

                    if let saegimURL = saegimURL {
                        let markdown = "[🔊 \(filename)](\(saegimURL))"
                        text.replaceSubrange(fullRange, with: markdown)
                        NSLog("Found sound tag: %@, converted successfully", filename)
                    } else {
                        NSLog("WARNING: No mapping for sound: %@ (tried NFC/NFD normalization)", filename)
                    }
                }
            }
        }

        // Convert <img src="filename"> to markdown image
        if let imgRegex = try? NSRegularExpression(pattern: "<img[^>]+src=[\"']?([^\"'\\s>]+)[\"']?[^>]*>", options: .caseInsensitive) {
            let matches = imgRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                if let srcRange = Range(match.range(at: 1), in: text),
                   let fullRange = Range(match.range, in: text) {
                    let filename = String(text[srcRange])
                    // Try multiple matching strategies for the filename (same as audio)
                    let normalizedFilename = filename.precomposedStringWithCanonicalMapping
                    let decomposedFilename = filename.decomposedStringWithCanonicalMapping

                    let saegimURL = mediaMapping[filename]
                        ?? mediaMapping[normalizedFilename]
                        ?? mediaMapping[decomposedFilename]
                        ?? mediaMapping.first { $0.key.lowercased() == filename.lowercased() }?.value
                        ?? mediaMapping.first { $0.key.precomposedStringWithCanonicalMapping == normalizedFilename }?.value

                    if let saegimURL = saegimURL {
                        let markdown = "![\(filename)](\(saegimURL))"
                        text.replaceSubrange(fullRange, with: markdown)
                        NSLog("Found img tag: %@, converted successfully", filename)
                    } else {
                        NSLog("WARNING: No mapping for image: %@ (tried NFC/NFD normalization)", filename)
                    }
                }
            }
        }

        let patterns = [
            "<br\\s*/?>": "\n",
            "<div[^>]*>": "",
            "</div>": "\n",
            "<p[^>]*>": "",
            "</p>": "\n",
            "<span[^>]*>": "",
            "</span>": "",
            "<b>|</b>": "",
            "<i>|</i>": "",
            "<u>|</u>": "",
            "<strong>|</strong>": "",
            "<em>|</em>": "",
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
        ]

        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: replacement
                )
            }
        }

        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return text
    }

    enum ImportError: LocalizedError {
        case accessDenied
        case invalidFile

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Cannot access the selected file"
            case .invalidFile:
                return "The file is not a valid Anki package"
            }
        }
    }
}

#Preview {
    AnkiImportView()
        .modelContainer(for: [Card.self, Deck.self], inMemory: true)
}

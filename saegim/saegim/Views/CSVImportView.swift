//
//  CSVImportView.swift
//  saegim
//
//  View for importing CSV files with flashcards
//

import SwiftUI
import UniformTypeIdentifiers

struct CSVImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repository: DataRepository

    @State private var selectedURL: URL?
    @State private var isImporting = false
    @State private var importResult: ImportResult?
    @State private var showingFilePicker = false
    @State private var deckName = "Imported Deck"

    enum ImportResult {
        case success(cardCount: Int)
        case failure(error: String)
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

                Text("Import CSV")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 28, height: 28)
            }
            .padding()
            .background(.bar)

            Divider()

            // Content
            VStack(spacing: 24) {
                if isImporting {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Importing cards...")
                            .foregroundStyle(.secondary)
                    }
                    .padding(40)
                } else if let result = importResult {
                    switch result {
                    case .success(let cardCount):
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.green)

                            Text("Import Successful")
                                .font(.title2.weight(.semibold))

                            Text("Imported \(cardCount) cards into \"\(deckName)\"")
                                .foregroundStyle(.secondary)

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
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("Select a CSV file to import")
                            .font(.title3)

                        Text("Format: front,back (with header row)")
                            .foregroundStyle(.secondary)

                        TextField("Deck Name", text: $deckName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)

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
        .frame(width: 450, height: 380)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "csv") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedURL = url
                    importCSV(from: url)
                }
            case .failure(let error):
                importResult = .failure(error: error.localizedDescription)
            }
        }
    }

    private func importCSV(from url: URL) {
        isImporting = true

        guard url.startAccessingSecurityScopedResource() else {
            importResult = .failure(error: "Cannot access the selected file")
            isImporting = false
            return
        }

        Task {
            defer {
                url.stopAccessingSecurityScopedResource()
            }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let rows = parseCSV(content)

                guard !rows.isEmpty else {
                    await MainActor.run {
                        importResult = .failure(error: "No valid cards found in CSV")
                        isImporting = false
                    }
                    return
                }

                // Create deck
                let deck = try await repository.createDeck(
                    name: deckName.isEmpty ? "Imported Deck" : deckName,
                    description: "Imported from CSV"
                )

                // Create cards
                var cardCount = 0
                for row in rows {
                    guard row.count >= 2 else { continue }
                    let front = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let back = row[1].trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !front.isEmpty && !back.isEmpty else { continue }

                    try await repository.createCard(front: front, back: back, deckId: deck.id)
                    cardCount += 1
                }

                await MainActor.run {
                    importResult = .success(cardCount: cardCount)
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    importResult = .failure(error: error.localizedDescription)
                    isImporting = false
                }
            }
        }
    }

    private func parseCSV(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        let lines = content.components(separatedBy: .newlines)

        var isFirstLine = true
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Skip header row
            if isFirstLine {
                isFirstLine = false
                let lower = trimmed.lowercased()
                if lower.contains("front") || lower.contains("question") || lower.contains("term") {
                    continue
                }
            }

            let columns = parseCSVLine(trimmed)
            if columns.count >= 2 {
                rows.append(columns)
            }
        }

        return rows
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                columns.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        columns.append(current)

        return columns.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }
}

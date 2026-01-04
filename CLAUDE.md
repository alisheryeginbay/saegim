# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Instructions

Always use Context7 MCP when needing library/API documentation, code generation, setup or configuration steps without requiring explicit request.

## Build Commands

### Prerequisites
- macOS 14+, Xcode 16+
- Rust toolchain with targets: `aarch64-apple-darwin`, `x86_64-apple-darwin`, `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`

### Building Rust Dependencies (required before Xcode)
```bash
# Build Anki parser (parses .apkg/.colpkg files)
cd anki-parser && ./build-swift.sh

# Build FSRS scheduler (spaced repetition algorithm)
cd fsrs-swift && ./build-swift.sh
```

### Building the App
Open `saegim/saegim.xcodeproj` in Xcode and build (Cmd+B) or run (Cmd+R).

### Running Rust Tests
```bash
cd anki-parser && cargo test
cd fsrs-swift && cargo test
```

## Architecture Overview

### Dual Platform Structure
The app has separate macOS and iOS targets with shared core logic:
- macOS: `SaegimApp.swift`, `ContentView.swift`, `Views/`
- iOS: `iOS/SaegimApp_iOS.swift`, `iOS/ContentView_iOS.swift`, `iOS/Views/`

### Data Layer (PowerSync + Supabase)
Uses PowerSync for offline-first sync with Supabase backend:
- `Services/SupabaseManager.swift` - Authentication (email/password)
- `Services/DatabaseManager.swift` - PowerSync database lifecycle, schema definition, CRUD sync
- `Services/DataRepository.swift` - Data access layer, deck hierarchy management, card operations

Data flows: UI → DataRepository → PowerSync (local SQLite) ⇄ Supabase (remote)

### Model System
Two parallel model systems exist:
- `Models/Card.swift`, `Models/Deck.swift` - SwiftData @Model classes (legacy, being phased out)
- `Models/CardModel.swift`, `Models/DeckModel.swift` - Plain structs for PowerSync compatibility

CardModel/DeckModel are the active models. They initialize from `[String: Any]` database rows and have `toDict()` for serialization.

### Rust FFI via UniFFI
Two Rust libraries exposed to Swift via UniFFI XCFrameworks:
- **AnkiParser** (`anki-parser/`) - Parses Anki .apkg/.colpkg files, extracts decks/cards/media
- **FSRSSwift** (`fsrs-swift/`) - FSRS v6 spaced repetition scheduler (wraps fsrs-rs)

Swift packages at `AnkiParserSwift/` and `FSRSSwift/` contain the generated bindings.

### Media Storage
`MediaStorage.swift` handles media files:
- Content-addressed storage using SHA256 hashes
- Format detection via magic bytes (supports JPEG, PNG, GIF, WebP, MP3, WAV, M4A, OGG, FLAC)
- Sharded directory structure: `~/Library/Application Support/Saegim/media/{2-char-prefix}/{hash}.{ext}`
- Custom URL scheme `saegim://media/` for referencing stored files
- Cloud sync to Supabase Storage

### Card Scheduling (FSRS v6)
CardModel implements FSRS scheduling:
- `review(rating:)` - Updates stability, difficulty, nextReviewDate
- `previewNextStates()` - Shows intervals for all rating buttons
- `currentRetrievability()` - Recall probability calculation
- States: new → learning → review (or → relearning on lapse)

### Deck Hierarchy
Decks support nesting via `parentId`. DataRepository builds the tree:
- `buildDeckHierarchy()` reconstructs tree from flat database rows
- Anki's `::` notation (e.g., "Parent::Child") is parsed during import
- `findDeck(id:)` searches recursively

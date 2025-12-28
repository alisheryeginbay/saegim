# Saegim

Flashcard app for macOS with Anki import support.

## Requirements

- macOS 14+
- Xcode 16+
- Rust toolchain

## Setup

```bash
# Build Anki parser (required before opening Xcode)
cd anki-parser && ./build-swift.sh
```

Then open `saegim/saegim.xcodeproj` in Xcode and build.

## Features

- Import .apkg/.colpkg files
- Spaced repetition
- Media support (images, audio)

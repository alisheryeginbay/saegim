#!/bin/bash
set -e

echo "Building anki-parser for macOS..."

# Build for both architectures
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin

# Create universal binary
echo "Creating universal binary..."
lipo -create \
  target/aarch64-apple-darwin/release/libanki_parser.a \
  target/x86_64-apple-darwin/release/libanki_parser.a \
  -output target/release/libanki_parser_universal.a

# Generate Swift bindings
echo "Generating Swift bindings..."
mkdir -p generated
cargo run --release --bin uniffi-bindgen generate \
  --library target/release/libanki_parser.dylib \
  --language swift \
  --out-dir generated

# Update Swift Package
echo "Updating Swift Package..."
SWIFT_PKG="../AnkiParserSwift"
mkdir -p "$SWIFT_PKG/Sources/AnkiParser"
mkdir -p "$SWIFT_PKG/AnkiParserFFI.xcframework/macos-arm64_x86_64/Headers/AnkiParserFFI"

cp generated/AnkiParser.swift "$SWIFT_PKG/Sources/AnkiParser/"
# Header at root level, modulemap in subdirectory (prevents conflict with other xcframeworks)
cp generated/AnkiParserFFI.h "$SWIFT_PKG/AnkiParserFFI.xcframework/macos-arm64_x86_64/Headers/"
# Create modulemap that references header with relative path
cat > "$SWIFT_PKG/AnkiParserFFI.xcframework/macos-arm64_x86_64/Headers/AnkiParserFFI/module.modulemap" << 'EOF'
module AnkiParserFFI {
    header "../AnkiParserFFI.h"
    export *
}
EOF
cp target/release/libanki_parser_universal.a "$SWIFT_PKG/AnkiParserFFI.xcframework/macos-arm64_x86_64/libanki_parser.a"

echo "Done! Swift package updated at $SWIFT_PKG"
echo ""
echo "To use in Xcode:"
echo "1. Add AnkiParserSwift as a local Swift Package dependency"
echo "2. Remove AnkiToMarkdown and zstd packages"
echo "3. Build and run!"

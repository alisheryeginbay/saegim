#!/bin/bash
set -e

# Check for required targets
check_targets() {
    local missing=()
    for target in aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
        if ! rustup target list --installed | grep -q "^$target$"; then
            missing+=("$target")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing Rust targets: ${missing[*]}"
        echo "Install with: rustup target add ${missing[*]}"
        exit 1
    fi
}

check_targets

SWIFT_PKG="../AnkiParserSwift"

echo "Building anki-parser for macOS..."
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin

echo "Building anki-parser for iOS..."
cargo build --release --target aarch64-apple-ios

echo "Building anki-parser for iOS Simulator..."
cargo build --release --target aarch64-apple-ios-sim
cargo build --release --target x86_64-apple-ios

# Create universal binaries
echo "Creating universal binaries..."
mkdir -p target/release

# macOS universal
lipo -create \
  target/aarch64-apple-darwin/release/libanki_parser.a \
  target/x86_64-apple-darwin/release/libanki_parser.a \
  -output target/release/libanki_parser_macos.a

# iOS Simulator universal
lipo -create \
  target/aarch64-apple-ios-sim/release/libanki_parser.a \
  target/x86_64-apple-ios/release/libanki_parser.a \
  -output target/release/libanki_parser_ios_sim.a

# Generate Swift bindings
echo "Generating Swift bindings..."
mkdir -p generated
cargo run --release --bin uniffi-bindgen generate \
  --library target/release/libanki_parser.dylib \
  --language swift \
  --out-dir generated

# Remove old xcframework and create new structure
echo "Creating xcframework..."
rm -rf "$SWIFT_PKG/AnkiParserFFI.xcframework"
mkdir -p "$SWIFT_PKG/Sources/AnkiParser"

# Create xcframework directories
MACOS_DIR="$SWIFT_PKG/AnkiParserFFI.xcframework/macos-arm64_x86_64"
IOS_DIR="$SWIFT_PKG/AnkiParserFFI.xcframework/ios-arm64"
IOS_SIM_DIR="$SWIFT_PKG/AnkiParserFFI.xcframework/ios-arm64_x86_64-simulator"

mkdir -p "$MACOS_DIR/Headers/AnkiParserFFI"
mkdir -p "$IOS_DIR/Headers/AnkiParserFFI"
mkdir -p "$IOS_SIM_DIR/Headers/AnkiParserFFI"

# Copy Swift source
cp generated/AnkiParser.swift "$SWIFT_PKG/Sources/AnkiParser/"

# Copy headers and create modulemaps for each platform
for dir in "$MACOS_DIR" "$IOS_DIR" "$IOS_SIM_DIR"; do
    cp generated/AnkiParserFFI.h "$dir/Headers/"
    cat > "$dir/Headers/AnkiParserFFI/module.modulemap" << 'EOF'
module AnkiParserFFI {
    header "../AnkiParserFFI.h"
    export *
}
EOF
done

# Copy libraries
cp target/release/libanki_parser_macos.a "$MACOS_DIR/libanki_parser.a"
cp target/aarch64-apple-ios/release/libanki_parser.a "$IOS_DIR/libanki_parser.a"
cp target/release/libanki_parser_ios_sim.a "$IOS_SIM_DIR/libanki_parser.a"

# Create Info.plist
cat > "$SWIFT_PKG/AnkiParserFFI.xcframework/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AvailableLibraries</key>
    <array>
        <dict>
            <key>HeadersPath</key>
            <string>Headers</string>
            <key>LibraryIdentifier</key>
            <string>macos-arm64_x86_64</string>
            <key>LibraryPath</key>
            <string>libanki_parser.a</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
                <string>x86_64</string>
            </array>
            <key>SupportedPlatform</key>
            <string>macos</string>
        </dict>
        <dict>
            <key>HeadersPath</key>
            <string>Headers</string>
            <key>LibraryIdentifier</key>
            <string>ios-arm64</string>
            <key>LibraryPath</key>
            <string>libanki_parser.a</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
            </array>
            <key>SupportedPlatform</key>
            <string>ios</string>
        </dict>
        <dict>
            <key>HeadersPath</key>
            <string>Headers</string>
            <key>LibraryIdentifier</key>
            <string>ios-arm64_x86_64-simulator</string>
            <key>LibraryPath</key>
            <string>libanki_parser.a</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
                <string>x86_64</string>
            </array>
            <key>SupportedPlatform</key>
            <string>ios</string>
            <key>SupportedPlatformVariant</key>
            <string>simulator</string>
        </dict>
    </array>
    <key>CFBundlePackageType</key>
    <string>XFWK</string>
    <key>XCFrameworkFormatVersion</key>
    <string>1.0</string>
</dict>
</plist>
EOF

echo "Done! Swift package updated at $SWIFT_PKG"
echo ""
echo "To use in Xcode:"
echo "1. Add AnkiParserSwift as a local Swift Package dependency"
echo "2. Build and run!"

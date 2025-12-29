#!/bin/bash
set -e

echo "Building fsrs-swift for macOS..."

# Build for both architectures
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin

# Create universal binary
echo "Creating universal binary..."
lipo -create \
  target/aarch64-apple-darwin/release/libfsrs_swift.a \
  target/x86_64-apple-darwin/release/libfsrs_swift.a \
  -output target/release/libfsrs_swift_universal.a

# Generate Swift bindings
echo "Generating Swift bindings..."
mkdir -p generated
cargo run --release --bin uniffi-bindgen generate \
  --library target/release/libfsrs_swift.dylib \
  --language swift \
  --out-dir generated

# Update Swift Package
echo "Updating Swift Package..."
SWIFT_PKG="../FSRSSwift"
mkdir -p "$SWIFT_PKG/Sources/FSRSSwift"
mkdir -p "$SWIFT_PKG/FSRSSwiftFFI.xcframework/macos-arm64_x86_64/Headers/FSRSSwiftFFI"

cp generated/FSRSSwift.swift "$SWIFT_PKG/Sources/FSRSSwift/"
# Header at root level, modulemap in subdirectory (prevents conflict with other xcframeworks)
cp generated/FSRSSwiftFFI.h "$SWIFT_PKG/FSRSSwiftFFI.xcframework/macos-arm64_x86_64/Headers/"
# Create modulemap that references header with relative path
cat > "$SWIFT_PKG/FSRSSwiftFFI.xcframework/macos-arm64_x86_64/Headers/FSRSSwiftFFI/module.modulemap" << 'EOF'
module FSRSSwiftFFI {
    header "../FSRSSwiftFFI.h"
    export *
}
EOF
cp target/release/libfsrs_swift_universal.a "$SWIFT_PKG/FSRSSwiftFFI.xcframework/macos-arm64_x86_64/libfsrs_swift.a"

echo "Done! Swift package updated at $SWIFT_PKG"
echo ""
echo "To use in Xcode:"
echo "1. Add FSRSSwift as a local Swift Package dependency"
echo "2. Build and run!"

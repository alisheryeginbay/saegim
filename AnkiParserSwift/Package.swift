// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnkiParser",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "AnkiParser",
            targets: ["AnkiParser"]
        ),
    ],
    targets: [
        .target(
            name: "AnkiParser",
            dependencies: ["AnkiParserFFI"],
            path: "Sources/AnkiParser"
        ),
        .binaryTarget(
            name: "AnkiParserFFI",
            path: "AnkiParserFFI.xcframework"
        ),
    ]
)

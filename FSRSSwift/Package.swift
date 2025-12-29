// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FSRSSwift",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "FSRSSwift",
            targets: ["FSRSSwift"]
        ),
    ],
    targets: [
        .target(
            name: "FSRSSwift",
            dependencies: ["FSRSSwiftFFI"],
            path: "Sources/FSRSSwift"
        ),
        .binaryTarget(
            name: "FSRSSwiftFFI",
            path: "FSRSSwiftFFI.xcframework"
        ),
    ]
)

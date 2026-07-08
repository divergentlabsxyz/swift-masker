// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Masker",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "Masker", targets: ["Masker"]),
        .executable(name: "masker-demo", targets: ["MaskerDemo"]),
    ],
    targets: [
        .target(
            name: "Masker",
            resources: [
                // The model and tokenizer are always bundled so the hybrid
                // detector works out of the box with no download.
                .copy("Resources/masker-mini.mlmodelc"),
                .copy("Resources/tokenizer.json"),
                .copy("Resources/config.json"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "MaskerDemo",
            dependencies: ["Masker"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "MaskerTests",
            dependencies: ["Masker"]
        ),
    ]
)

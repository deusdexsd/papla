// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MurmurYouTube",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Parakeet TDT as CoreML on the Neural Engine — the dictation engine.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6"),
    ],
    targets: [
        // The dictionary is its own target so it can be tested directly against the vectors
        // in Tests/MurmurDictionaryTests/dictionary-test-vectors.json.
        .target(
            name: "MurmurDictionary",
            path: "Sources/MurmurDictionary",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "MurmurYouTube",
            dependencies: [
                "MurmurDictionary",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/MurmurYouTube",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "MurmurDictionaryTests",
            dependencies: ["MurmurDictionary"],
            path: "Tests/MurmurDictionaryTests",
            resources: [.copy("dictionary-test-vectors.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

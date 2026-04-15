// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GuitarAICoach",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GuitarAICoachApp", targets: ["App"])
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                "Core",
                "Tuner",
                "Fretboard",
                "Chords",
                "ChordsLive",
                "Theory",
                "ChordChart"
            ],
            path: "Sources/App"
        ),
        .target(
            name: "Core",
            path: "Sources/Core"
        ),
        .target(
            name: "Tuner",
            dependencies: ["Core"],
            path: "Sources/Features/Tuner"
        ),
        .target(
            name: "Fretboard",
            dependencies: ["Core"],
            path: "Sources/Features/Fretboard"
        ),
        .target(
            name: "Chords",
            dependencies: ["Core"],
            path: "Sources/Features/Chords"
        ),
        .target(
            name: "ChordsLive",
            dependencies: ["Core"],
            path: "Sources/Features/ChordsLive"
        ),
        .target(
            name: "Theory",
            dependencies: ["Core"],
            path: "Sources/Features/Theory"
        ),
        .target(
            name: "ChordChart",
            dependencies: ["Core"],
            path: "Sources/Features/ChordChart"
        ),
        .testTarget(
            name: "GuitarAICoachUnitTests",
            dependencies: ["Core", "Tuner", "Fretboard", "Chords", "ChordsLive", "Theory", "ChordChart"],
            path: "Tests/Unit"
        ),
        .testTarget(
            name: "GuitarAICoachIntegrationTests",
            dependencies: ["Core", "Tuner", "Fretboard", "Chords", "ChordsLive", "Theory", "ChordChart"],
            path: "Tests/Integration"
        ),
        .testTarget(
            name: "GuitarAICoachUITests",
            dependencies: ["Core", "Tuner", "Fretboard", "Chords", "ChordsLive", "Theory", "ChordChart"],
            path: "Tests/UI"
        )
    ]
)


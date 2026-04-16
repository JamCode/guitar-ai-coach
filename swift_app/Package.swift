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
        .executable(name: "GuitarAICoachApp", targets: ["App"]),
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Tuner", targets: ["Tuner"]),
        .library(name: "Fretboard", targets: ["Fretboard"]),
        .library(name: "Chords", targets: ["Chords"]),
        .library(name: "ChordsLive", targets: ["ChordsLive"]),
        .library(name: "ChordChart", targets: ["ChordChart"]),
        .library(name: "Profile", targets: ["Profile"]),
        .library(name: "Ear", targets: ["Ear"])
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
                "ChordChart",
                "Ear"
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
            name: "ChordChart",
            dependencies: ["Core", "Chords"],
            path: "Sources/Features/ChordChart"
        ),
        .target(
            name: "Profile",
            dependencies: ["Core"],
            path: "Sources/Features/Profile"
        ),
        .target(
            name: "Ear",
            dependencies: ["Core", "Tuner"],
            path: "Sources/Features/Ear",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GuitarAICoachUnitTests",
            dependencies: ["Core", "Tuner", "Fretboard", "Chords", "ChordsLive", "ChordChart", "Profile", "Ear"],
            path: "Tests/Unit"
        ),
        .testTarget(
            name: "GuitarAICoachIntegrationTests",
            dependencies: ["Core", "Tuner", "Fretboard", "Chords", "ChordsLive", "ChordChart", "Profile", "Ear"],
            path: "Tests/Integration"
        ),
        .testTarget(
            name: "GuitarAICoachUITests",
            dependencies: ["Core", "Tuner", "Fretboard", "Chords", "ChordsLive", "ChordChart", "Profile", "Ear"],
            path: "Tests/UI"
        )
    ]
)


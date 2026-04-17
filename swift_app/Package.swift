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
        .library(name: "Ear", targets: ["Ear"]),
        .library(name: "Practice", targets: ["Practice"])
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
                "Ear",
                "Practice"
            ],
            path: "Sources/App"
        ),
        .target(
            name: "Core",
            path: "Sources/Core",
            resources: [
                .copy("Resources/SteelStringGuitar.sf2"),
                .copy("Resources/SteelStringGuitar.LICENSE.txt"),
                .copy("Resources/SteelStringGuitar.README.txt")
            ]
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
        .target(
            name: "Practice",
            dependencies: ["Core", "Fretboard"],
            path: "Sources/Features/Practice"
        ),
        .testTarget(
            name: "GuitarAICoachUnitTests",
            dependencies: ["Core", "Tuner", "Fretboard", "Chords", "ChordsLive", "ChordChart", "Profile", "Ear", "Practice"],
            path: "Tests/Unit"
        ),
        .testTarget(
            name: "GuitarAICoachIntegrationTests",
            dependencies: ["Core", "Tuner", "Fretboard", "Chords", "ChordsLive", "ChordChart", "Profile", "Ear", "Practice"],
            path: "Tests/Integration"
        ),
        .testTarget(
            name: "GuitarAICoachUITests",
            dependencies: ["Core", "Tuner", "Fretboard", "Chords", "ChordsLive", "ChordChart", "Profile", "Ear", "Practice"],
            path: "Tests/UI"
        )
    ]
)


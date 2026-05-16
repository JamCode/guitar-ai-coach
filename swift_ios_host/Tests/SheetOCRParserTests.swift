import XCTest
@testable import SwiftEarHost

final class SheetOCRParserTests: XCTestCase {
    func testParseSystem_extractsChordLyricAndMelodyTokens() {
        let parser = SheetOCRParser()
        let system = SheetOCRStaffSystem(
            bounds: SheetOCRRect(x: 0, y: 0.20, width: 1, height: 0.30),
            staffBounds: SheetOCRRect(x: 0, y: 0.30, width: 1, height: 0.06),
            chordZone: SheetOCRRect(x: 0, y: 0.22, width: 1, height: 0.07),
            lyricZone: SheetOCRRect(x: 0, y: 0.38, width: 1, height: 0.08)
        )
        let observations = [
            SheetOCRTextObservation(text: "C  G/B  Am  Em  Dm7  Gsus4", confidence: 0.92, rect: SheetOCRRect(x: 0.10, y: 0.23, width: 0.70, height: 0.03), source: .chordZone),
            SheetOCRTextObservation(text: "0 5 1 7 1 2 3 1", confidence: 0.80, rect: SheetOCRRect(x: 0.12, y: 0.37, width: 0.55, height: 0.03), source: .jianpuZone),
            SheetOCRTextObservation(text: "缓缓飘落的枫叶像思念", confidence: 0.88, rect: SheetOCRRect(x: 0.12, y: 0.42, width: 0.55, height: 0.03), source: .lyricZone)
        ]

        let parsed = parser.parseSystem(pageIndex: 0, systemIndex: 0, system: system, observations: observations)

        XCTAssertEqual(parsed.chords.map(\.text), ["C", "G/B", "Am", "Em", "Dm7", "Gsus4"])
        XCTAssertEqual(parsed.melody.map(\.text), ["0 5 1 7 1 2 3 1"])
        XCTAssertEqual(parsed.lyrics.map(\.text), ["缓缓飘落的枫叶像思念"])
        XCTAssertTrue(parsed.chords.allSatisfy { $0.rect.width > 0 && $0.rect.height > 0 })
    }

    func testParsePageMeta_extractsOriginalKeyAndTitle() {
        let parser = SheetOCRParser()
        let observations = [
            SheetOCRTextObservation(text: "枫", confidence: 0.95, rect: SheetOCRRect(x: 0.48, y: 0.04, width: 0.04, height: 0.03)),
            SheetOCRTextObservation(text: "演唱 周杰伦", confidence: 0.88, rect: SheetOCRRect(x: 0.43, y: 0.08, width: 0.16, height: 0.03)),
            SheetOCRTextObservation(text: "1= C  4/4", confidence: 0.90, rect: SheetOCRRect(x: 0.10, y: 0.12, width: 0.14, height: 0.03))
        ]

        let meta = parser.parsePageMeta(observations)

        XCTAssertEqual(meta.title?.text, "枫")
        XCTAssertEqual(meta.key?.text, "1=C")
        XCTAssertEqual(meta.key?.originalText, "1= C  4/4")
    }

    func testParsePageMeta_prefersCandidateKeyWithoutSpuriousAccidental() {
        let parser = SheetOCRParser()
        let observations = [
            SheetOCRTextObservation(
                text: "1=C# 4/4",
                confidence: 0.71,
                rect: SheetOCRRect(x: 0.10, y: 0.12, width: 0.14, height: 0.03),
                candidates: [
                    SheetOCRTextCandidate(text: "1=C# 4/4", confidence: 0.71),
                    SheetOCRTextCandidate(text: "1=C 4/4", confidence: 0.68)
                ]
            )
        ]

        let meta = parser.parsePageMeta(observations)

        XCTAssertEqual(meta.key?.text, "1=C")
    }

    func testParsePageMeta_correctsCommonCSharpKeyFalsePositive() {
        let parser = SheetOCRParser()
        let observations = [
            SheetOCRTextObservation(
                text: "1=C#",
                confidence: 0.82,
                rect: SheetOCRRect(x: 0.10, y: 0.12, width: 0.08, height: 0.03)
            )
        ]

        let meta = parser.parsePageMeta(observations)

        XCTAssertEqual(meta.key?.text, "1=C")
    }

    func testParseSystem_ignoresFullPageChordLikeFragmentsWhenZoneOCRExists() {
        let parser = SheetOCRParser()
        let system = SheetOCRStaffSystem(
            bounds: SheetOCRRect(x: 0, y: 0.20, width: 1, height: 0.30),
            staffBounds: SheetOCRRect(x: 0, y: 0.30, width: 1, height: 0.06),
            chordZone: SheetOCRRect(x: 0, y: 0.22, width: 1, height: 0.07),
            lyricZone: SheetOCRRect(x: 0, y: 0.38, width: 1, height: 0.08)
        )
        let observations = [
            SheetOCRTextObservation(text: "G/B", confidence: 0.92, rect: SheetOCRRect(x: 0.10, y: 0.23, width: 0.06, height: 0.03), source: .chordZone),
            SheetOCRTextObservation(text: "B", confidence: 0.55, rect: SheetOCRRect(x: 0.40, y: 0.35, width: 0.02, height: 0.02), source: .fullPage),
            SheetOCRTextObservation(text: "爱你穿 越时 间", confidence: 0.90, rect: SheetOCRRect(x: 0.12, y: 0.42, width: 0.35, height: 0.03), source: .lyricZone)
        ]

        let parsed = parser.parseSystem(pageIndex: 0, systemIndex: 0, system: system, observations: observations)

        XCTAssertEqual(parsed.chords.map(\.text), ["G/B"])
        XCTAssertEqual(parsed.lyrics.map(\.text), ["爱你穿越时间"])
    }

    func testParseSystem_usesChordCandidateWhenTopTextIsOcrConfusion() {
        let parser = SheetOCRParser()
        let system = SheetOCRStaffSystem(
            bounds: SheetOCRRect(x: 0, y: 0.20, width: 1, height: 0.30),
            staffBounds: SheetOCRRect(x: 0, y: 0.30, width: 1, height: 0.06),
            chordZone: SheetOCRRect(x: 0, y: 0.22, width: 1, height: 0.07),
            lyricZone: SheetOCRRect(x: 0, y: 0.38, width: 1, height: 0.08)
        )
        let observations = [
            SheetOCRTextObservation(
                text: "6/B",
                confidence: 0.61,
                rect: SheetOCRRect(x: 0.10, y: 0.23, width: 0.06, height: 0.03),
                candidates: [
                    SheetOCRTextCandidate(text: "6/B", confidence: 0.61),
                    SheetOCRTextCandidate(text: "G/B", confidence: 0.58)
                ],
                source: .chordZone
            )
        ]

        let parsed = parser.parseSystem(pageIndex: 0, systemIndex: 0, system: system, observations: observations)

        XCTAssertEqual(parsed.chords.map(\.text), ["G/B"])
    }

    func testParseSystem_deduplicatesSameChordFromOverlappingRegions() {
        let parser = SheetOCRParser()
        let system = SheetOCRStaffSystem(
            bounds: SheetOCRRect(x: 0, y: 0.20, width: 1, height: 0.30),
            staffBounds: SheetOCRRect(x: 0, y: 0.30, width: 1, height: 0.06),
            chordZone: SheetOCRRect(x: 0, y: 0.22, width: 1, height: 0.07),
            lyricZone: SheetOCRRect(x: 0, y: 0.38, width: 1, height: 0.08)
        )
        let observations = [
            SheetOCRTextObservation(text: "Am", confidence: 0.84, rect: SheetOCRRect(x: 0.20, y: 0.225, width: 0.04, height: 0.02), source: .chordLabelZone),
            SheetOCRTextObservation(text: "Am", confidence: 0.78, rect: SheetOCRRect(x: 0.205, y: 0.24, width: 0.04, height: 0.02), source: .chordZone),
            SheetOCRTextObservation(text: "Em", confidence: 0.81, rect: SheetOCRRect(x: 0.34, y: 0.23, width: 0.04, height: 0.02), source: .chordZone)
        ]

        let parsed = parser.parseSystem(pageIndex: 0, systemIndex: 0, system: system, observations: observations)

        XCTAssertEqual(parsed.chords.map(\.text), ["Am", "Em"])
    }

    func testParseSystem_mergesAdjacentLyricFragmentsOnSameBaseline() {
        let parser = SheetOCRParser()
        let system = SheetOCRStaffSystem(
            bounds: SheetOCRRect(x: 0, y: 0.20, width: 1, height: 0.30),
            staffBounds: SheetOCRRect(x: 0, y: 0.30, width: 1, height: 0.06),
            chordZone: SheetOCRRect(x: 0, y: 0.22, width: 1, height: 0.07),
            lyricZone: SheetOCRRect(x: 0, y: 0.38, width: 1, height: 0.08)
        )
        let observations = [
            SheetOCRTextObservation(text: "总在回", confidence: 0.88, rect: SheetOCRRect(x: 0.10, y: 0.42, width: 0.12, height: 0.03), source: .lyricZone),
            SheetOCRTextObservation(text: "忆里 才看", confidence: 0.86, rect: SheetOCRRect(x: 0.22, y: 0.421, width: 0.18, height: 0.03), source: .lyricZone),
            SheetOCRTextObservation(text: "得清", confidence: 0.89, rect: SheetOCRRect(x: 0.41, y: 0.419, width: 0.08, height: 0.03), source: .lyricZone)
        ]

        let parsed = parser.parseSystem(pageIndex: 0, systemIndex: 0, system: system, observations: observations)

        XCTAssertEqual(parsed.lyrics.map(\.text), ["总在回忆里才看得清"])
    }

    func testFallbackSystems_groupsTextByVerticalPosition() {
        let parser = SheetOCRParser()
        let observations = [
            SheetOCRTextObservation(text: "C Am", confidence: 0.9, rect: SheetOCRRect(x: 0.10, y: 0.30, width: 0.2, height: 0.02)),
            SheetOCRTextObservation(text: "第一句歌词", confidence: 0.9, rect: SheetOCRRect(x: 0.10, y: 0.34, width: 0.2, height: 0.02)),
            SheetOCRTextObservation(text: "F G", confidence: 0.9, rect: SheetOCRRect(x: 0.10, y: 0.55, width: 0.2, height: 0.02)),
            SheetOCRTextObservation(text: "第二句歌词", confidence: 0.9, rect: SheetOCRRect(x: 0.10, y: 0.59, width: 0.2, height: 0.02))
        ]

        let systems = parser.fallbackSystems(pageIndex: 0, observations: observations)

        XCTAssertEqual(systems.count, 2)
        XCTAssertEqual(systems[0].chords.map(\.text), ["C", "Am"])
        XCTAssertEqual(systems[0].lyrics.map(\.text), ["第一句歌词"])
        XCTAssertEqual(systems[1].chords.map(\.text), ["F", "G"])
        XCTAssertEqual(systems[1].lyrics.map(\.text), ["第二句歌词"])
    }
}

import XCTest
@testable import Ear

final class SightSingingEvaluateAnalysisTests: XCTestCase {
    private func sineMonoPCM(frequencyHz: Double, sampleRate: Double, durationSeconds: Double, gain: Double = 0.32) -> [Float] {
        let n = max(1, Int(sampleRate * durationSeconds))
        var out: [Float] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            out.append(Float(gain * sin(2 * Double.pi * frequencyHz * t)))
        }
        return out
    }

    func testSyntheticA4At44100YieldsModestMeanAbsoluteCents() {
        let sr = 44_100.0
        let pcm = sineMonoPCM(frequencyHz: 440, sampleRate: sr, durationSeconds: 0.95)
        let result = SightSingingEvaluateAnalysis.run(monoPCM: pcm, inputSampleRate: sr, targetNotes: ["A4"])
        XCTAssertNotNil(result)
        guard let result else { return }
        XCTAssertFalse(result.absCentsSamples.isEmpty)
        let meanAbs = result.absCentsSamples.reduce(0, +) / Double(result.absCentsSamples.count)
        XCTAssertLessThan(meanAbs, 85, "clean sine near A4 should average well under a semitone off")
        XCTAssertEqual(result.detectedAnswers.first?.uppercased(), "A4")
        XCTAssertEqual(result.sampleStepMs, SightSingingEvaluateAnalysis.hopMs)
    }

    func testSyntheticA4ResampledFrom48kStillRuns() {
        let srIn = 48_000.0
        let pcm = sineMonoPCM(frequencyHz: 440, sampleRate: srIn, durationSeconds: 0.95)
        let result = SightSingingEvaluateAnalysis.run(monoPCM: pcm, inputSampleRate: srIn, targetNotes: ["A4"])
        XCTAssertNotNil(result)
        guard let result else { return }
        XCTAssertFalse(result.absCentsSamples.isEmpty)
        let meanAbs = result.absCentsSamples.reduce(0, +) / Double(result.absCentsSamples.count)
        XCTAssertLessThan(meanAbs, 120)
    }
}

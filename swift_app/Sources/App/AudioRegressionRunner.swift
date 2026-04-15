import Foundation
import Core

struct AudioRegressionRunner {
    static func runQuickCheck() -> AudioQualitySnapshot {
        let quality = AudioQualityBaseline()
        let audio = AudioEngineService(quality: quality)
        do {
            try audio.start()
            try audio.playSine(frequencyHz: 110.0, durationSec: 0.10)
            try audio.playSine(frequencyHz: 220.0, durationSec: 0.10)
            try audio.playSine(frequencyHz: 329.63, durationSec: 0.10)
            audio.stop()
        } catch {
            quality.markUnderrun()
            audio.stop()
        }
        return quality.snapshot()
    }
}


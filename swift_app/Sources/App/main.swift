import Foundation
import Core
import Tuner
import Fretboard
import Chords
import ChordChart
import Ear
import Practice

let env = AppEnvironment()
let tools = ["练耳", "调音器", "吉他指板", "和弦速查", "常用和弦"]

print("GuitarAICoachApp bootstrap OK (\(env.apiBaseURL))")
print("Tools migrated: \(tools.joined(separator: " / "))")
_ = ToolsHomeView()
_ = EarHomeView()
_ = TraditionalCrawlPracticeView()
_ = ScaleTrainingPracticeView()
_ = ChordSwitchTrainingPracticeView()
_ = TunerView()
_ = FretboardView()
_ = ChordLookupView()
_ = ChordChartView()
let audioSnapshot = AudioRegressionRunner.runQuickCheck()
print(
    "Audio quick check -> start:\(audioSnapshot.startCount) stop:\(audioSnapshot.stopCount) "
    + "callbacks:\(audioSnapshot.callbackCount) underrun:\(audioSnapshot.underrunCount) "
    + "avgRenderMs:\(String(format: "%.3f", audioSnapshot.averageRenderCostMs))"
)


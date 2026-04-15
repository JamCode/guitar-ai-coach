import Foundation
import Core
import Tuner
import Fretboard
import Chords
import ChordsLive
import Theory
import ChordChart

let env = AppEnvironment()
let tools = ["实时和弦建议（Beta）", "调音器", "吉他指板", "和弦字典", "初级乐理", "和弦表"]

print("GuitarAICoachApp bootstrap OK (\(env.apiBaseURL))")
print("Tools migrated: \(tools.joined(separator: " / "))")
_ = ToolsHomeView()
_ = LiveChordView()
_ = TunerView()
_ = FretboardView()
_ = ChordLookupView()
_ = TheoryView()
_ = ChordChartView()
let audioSnapshot = AudioRegressionRunner.runQuickCheck()
print(
    "Audio quick check -> start:\(audioSnapshot.startCount) stop:\(audioSnapshot.stopCount) "
    + "callbacks:\(audioSnapshot.callbackCount) underrun:\(audioSnapshot.underrunCount) "
    + "avgRenderMs:\(String(format: "%.3f", audioSnapshot.averageRenderCostMs))"
)


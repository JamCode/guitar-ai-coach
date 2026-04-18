import Foundation

public extension EarBankItem {
    /// 本题实际发声的 MIDI（和弦或进行里各和弦音的并集）。
    var playbackHighlightMidiSet: Set<Int> {
        if mode == "B" || questionType == "progression_recognition" {
            Set(EarPlaybackMidi.forProgression(self).flatMap { $0 })
        } else {
            Set(EarPlaybackMidi.forSingleChord(self))
        }
    }

    /// 至少一个八度的连续半音条，覆盖本题发声音区（与音程练耳一致算法）。
    var playbackChromaticStripMidis: [Int] {
        let s = playbackHighlightMidiSet
        guard let lo = s.min(), let hi = s.max(), !s.isEmpty else { return [] }
        return IntervalChromaticStrip.midisCoveringOctaveIncluding(lowMidi: lo, highMidi: hi)
    }
}

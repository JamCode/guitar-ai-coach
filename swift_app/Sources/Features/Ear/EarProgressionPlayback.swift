import Foundation
import Chords

/// 和弦进行（bank B）与「常用和弦」一致的指法序列解析。
public enum EarProgressionPlayback {
    /// 本题实际播放进行对应的字母和弦，如 `C → G → Am → F`。
    public static func progressionMarkText(for item: EarBankItem) -> String {
        let key = item.musicKey ?? "C"
        let roman = item.progressionRoman ?? ""
        let parts = EarPlaybackMidi.letterChordSymbols(key: key, progressionRoman: roman)
        return parts.joined(separator: " → ")
    }

    /// 每个和弦一帧 6→1 弦品格，供 `ChordVoicingTonePlayer` 顺序播放；任一和弦无法解析则返回 `nil`。
    public static func playbackFretsSequence(for item: EarBankItem) -> [[Int]]? {
        let key = item.musicKey ?? "C"
        let roman = item.progressionRoman ?? ""
        let symbols = EarPlaybackMidi.letterChordSymbols(key: key, progressionRoman: roman)
        var out: [[Int]] = []
        out.reserveCapacity(symbols.count)
        for sym in symbols {
            guard let payload = OfflineChordBuilder.buildPayload(displaySymbol: sym),
                  let frets = payload.voicings.first?.explain.frets,
                  frets.count == 6
            else { return nil }
            out.append(frets)
        }
        return out.isEmpty ? nil : out
    }
}

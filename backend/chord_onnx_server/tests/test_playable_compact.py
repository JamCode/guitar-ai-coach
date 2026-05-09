"""playableCompact 冒烟测试：无 librosa 环境自动跳过。"""
from __future__ import annotations

import importlib.util
import unittest

HAS_LIBROSA = importlib.util.find_spec("librosa") is not None


@unittest.skipUnless(HAS_LIBROSA, "librosa not installed")
class TestPlayableCompact(unittest.TestCase):
    def test_build_returns_compacted_segments(self) -> None:
        import numpy as np

        from playable_compact_postprocess import build_playable_compact_segments

        sr = 22050
        y = np.random.default_rng(1).normal(0, 0.02, sr * 4).astype(np.float32)
        timing_compact = [
            {"start": 0.0, "end": 1.0, "chord": "A", "confidence": 1.0},
            {"start": 1.0, "end": 1.5, "chord": "Asus4", "confidence": 1.0},
            {"start": 1.5, "end": 2.2, "chord": "A", "confidence": 1.0},
            {"start": 2.2, "end": 3.0, "chord": "E/G#", "confidence": 1.0},
            {"start": 3.0, "end": 4.0, "chord": "F#m", "confidence": 1.0},
        ]
        merged = [
            {"start": 0.0, "end": 1.0, "chord": "A:maj", "confidence": 1.0},
            {"start": 1.0, "end": 1.5, "chord": "A:maj", "confidence": 0.5},
            {"start": 1.5, "end": 2.2, "chord": "A:maj", "confidence": 1.0},
            {"start": 2.2, "end": 3.0, "chord": "E:maj/G#", "confidence": 0.9},
            {"start": 3.0, "end": 4.0, "chord": "F#:min", "confidence": 1.0},
        ]
        out = build_playable_compact_segments(
            y=y,
            sr=sr,
            timing_compact_segments=timing_compact,
            merged_segments=merged,
            hop_length=512,
        )
        self.assertIn("segments", out)
        self.assertIn("stats", out)
        self.assertLessEqual(len(out["segments"]), len(timing_compact))
        self.assertIn("compressedCount", out["stats"])
        self.assertIn("simplifiedChordNameCount", out["stats"])


if __name__ == "__main__":
    unittest.main()


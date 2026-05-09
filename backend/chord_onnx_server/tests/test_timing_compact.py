"""timingCompact 冒烟：需 librosa（与 chord-onnx 环境一致）。"""
from __future__ import annotations

import importlib.util
import unittest

HAS_LIBROSA = importlib.util.find_spec("librosa") is not None


@unittest.skipUnless(HAS_LIBROSA, "librosa not installed")
class TestTimingCompact(unittest.TestCase):
    def test_build_reduces_or_equal_segment_count(self) -> None:
        import numpy as np

        from timing_compact_postprocess import build_timing_compact_segments

        sr = 22050
        y = np.random.default_rng(0).normal(0, 0.02, sr * 2).astype(np.float32)
        timing = [
            {"start": 0.0, "end": 1.0, "chord": "A", "confidence": 1.0},
            {"start": 1.0, "end": 1.25, "chord": "Asus4", "confidence": 1.0},
            {"start": 1.25, "end": 3.0, "chord": "A", "confidence": 1.0},
        ]
        merged = [
            {"start": 0.0, "end": 1.0, "chord": "A:maj", "confidence": 1.0},
            {"start": 1.0, "end": 1.25, "chord": "A:maj", "confidence": 1.0},
            {"start": 1.25, "end": 3.0, "chord": "A:maj", "confidence": 1.0},
        ]
        out = build_timing_compact_segments(y=y, sr=sr, timing_segments=timing, merged_segments=merged, hop_length=512)
        segs = out["segments"]
        self.assertLessEqual(len(segs), len(timing))
        self.assertIn("compressedCount", out["stats"])


if __name__ == "__main__":
    unittest.main()

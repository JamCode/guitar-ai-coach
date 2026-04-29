"""timing 踩点优先后处理冒烟：短静音 + 两段和弦。"""
from __future__ import annotations

import importlib.util
import unittest

import numpy as np

HAS_LIBROSA = importlib.util.find_spec("librosa") is not None

if HAS_LIBROSA:
    from timing_segment_postprocess import build_timing_priority_segments


class _Seg:
    def __init__(self, start: float, end: float, chord: str) -> None:
        self.start = start
        self.end = end
        self.chord = chord


@unittest.skipUnless(HAS_LIBROSA, "requires librosa (chord_onnx_server env)")
class TimingSegmentsSmokeTests(unittest.TestCase):
    def test_runs_without_crash_on_short_audio(self) -> None:
        sr = 22050
        y = (np.random.randn(sr) * 0.01).astype(np.float32)
        no_absorb = [
            _Seg(0.0, 1.0, "C"),
            _Seg(1.0, 1.4, "G"),
            _Seg(1.4, 3.0, "Am"),
        ]
        merged = [
            _Seg(0.0, 0.5, "C"),
            _Seg(0.5, 1.0, "C"),
            _Seg(1.0, 1.2, "G"),
            _Seg(1.2, 1.4, "G"),
            _Seg(1.4, 3.0, "Am"),
        ]
        r = build_timing_priority_segments(
            y=y,
            sr=sr,
            no_absorb_simplified=no_absorb,
            merged_segments=merged,
            hop_length=512,
        )
        self.assertIn("segments", r)
        self.assertIn("stats", r)
        self.assertIn("debug", r)
        self.assertIsInstance(r["segments"], list)
        self.assertGreaterEqual(len(r["segments"]), 1)


if __name__ == "__main__":
    unittest.main()

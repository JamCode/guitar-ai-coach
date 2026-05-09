"""timing 踩点优先后处理冒烟：短静音 + 两段和弦。"""
from __future__ import annotations

import importlib.util
import unittest

import numpy as np

HAS_LIBROSA = importlib.util.find_spec("librosa") is not None

if HAS_LIBROSA:
    from timing_segment_postprocess import _Seg as TimingSeg
    from timing_segment_postprocess import _fill_gaps_from_anchor
    from timing_segment_postprocess import _seal_short_gaps, build_timing_priority_segments


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

    def test_seal_short_gap_between_different_chords(self) -> None:
        segs = [
            TimingSeg(0.0, 1.0, "C"),
            TimingSeg(1.08, 2.0, "G"),
        ]
        out = _seal_short_gaps(segs)
        self.assertEqual(len(out), 2)
        self.assertAlmostEqual(out[0].end, out[1].start, places=3)

    def test_seal_short_gap_merges_same_function_segments(self) -> None:
        segs = [
            TimingSeg(0.0, 1.0, "B"),
            TimingSeg(1.09, 2.1, "B"),
        ]
        out = _seal_short_gaps(segs)
        self.assertEqual(out, [TimingSeg(0.0, 2.1, "B")])

    def test_fill_gap_from_anchor_inserts_mainline_chord(self) -> None:
        segs = [
            TimingSeg(0.0, 1.0, "C"),
            TimingSeg(2.2, 3.0, "G"),
        ]
        anchors = [TimingSeg(0.0, 3.0, "Am")]
        out = _fill_gaps_from_anchor(segs, anchors)
        self.assertEqual(
            out,
            [
                TimingSeg(0.0, 1.0, "C"),
                TimingSeg(1.0, 2.2, "Am"),
                TimingSeg(2.2, 3.0, "G"),
            ],
        )

    def test_fill_gap_from_anchor_extends_matching_neighbor(self) -> None:
        segs = [
            TimingSeg(0.0, 1.0, "C"),
            TimingSeg(2.2, 3.0, "G"),
        ]
        anchors = [TimingSeg(0.0, 3.0, "C")]
        out = _fill_gaps_from_anchor(segs, anchors)
        self.assertEqual(
            out,
            [
                TimingSeg(0.0, 2.2, "C"),
                TimingSeg(2.2, 3.0, "G"),
            ],
        )


if __name__ == "__main__":
    unittest.main()

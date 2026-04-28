"""ONNX 和弦识别时间诊断单元测试。"""
from __future__ import annotations

import unittest
import sys
import types

import numpy as np

sys.modules.setdefault("librosa", types.SimpleNamespace())
sys.modules.setdefault("onnxruntime", types.SimpleNamespace())

from inference import FRAME_SEC, ChordOnnxInferenceService, Segment


def _logits(indices: list[int], class_count: int) -> np.ndarray:
    arr = np.full((len(indices), class_count), -8.0, dtype=np.float32)
    for frame_idx, class_idx in enumerate(indices):
        arr[frame_idx, class_idx] = 8.0
    return arr


def _chroma_logits(active_notes: list[list[int]]) -> np.ndarray:
    arr = np.full((len(active_notes), 12), -8.0, dtype=np.float32)
    for frame_idx, notes in enumerate(active_notes):
        for note in notes:
            arr[frame_idx, note] = 8.0
    return arr


class InferenceTimingDiagnosticsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = ChordOnnxInferenceService.__new__(ChordOnnxInferenceService)

    def test_decode_outputs_uses_feature_frame_start_times(self) -> None:
        result = self.service._decode_outputs(
            {
                "root_logits": _logits([0, 0, 7], 13),
                "bass_logits": _logits([0, 0, 7], 13),
                "chord_logits": _chroma_logits([[0, 4, 7], [0, 4, 7], [7, 11, 2]]),
            },
            frame_sec=FRAME_SEC,
        )

        self.assertEqual(
            result["segments"],
            [
                Segment(start=0.0, end=round(2 * FRAME_SEC, 3), chord="C"),
                Segment(start=round(2 * FRAME_SEC, 3), end=round(3 * FRAME_SEC, 3), chord="G"),
            ],
        )
        frame_rows = result["frame_diagnostics"]
        self.assertEqual(frame_rows[0]["timeSec"], 0.0)
        self.assertEqual(frame_rows[1]["timeSec"], round(FRAME_SEC, 6))
        self.assertEqual(frame_rows[2]["timeSec"], round(2 * FRAME_SEC, 6))
        self.assertEqual(frame_rows[2]["rootPrediction"], "G")
        self.assertEqual(frame_rows[2]["chordLabel"], "G")
        self.assertEqual(frame_rows[2]["smoothedLabel"], "G")

    def test_collect_boundary_diagnostics_maps_final_label_and_chunk(self) -> None:
        frames = [
            {
                "frameIndex": 42,
                "timeSec": 0.93,
                "rootPrediction": "C",
                "chordLabel": "C",
                "confidence": 0.9,
                "smoothedLabel": "C",
                "chunkIndex": 0,
                "chunkStartSec": 0.0,
            },
            {
                "frameIndex": 43,
                "timeSec": 1.05,
                "rootPrediction": "G",
                "chordLabel": "G",
                "confidence": 0.8,
                "smoothedLabel": "G",
                "chunkIndex": 0,
                "chunkStartSec": 0.0,
            },
            {
                "frameIndex": 99,
                "timeSec": 3.0,
                "rootPrediction": "D",
                "chordLabel": "D",
                "confidence": 0.7,
                "smoothedLabel": "D",
                "chunkIndex": 0,
                "chunkStartSec": 0.0,
            },
        ]

        rows = self.service._collect_boundary_frame_diagnostics(
            frames=frames,
            boundary_segments=[
                Segment(start=0.0, end=1.0, chord="C"),
                Segment(start=1.0, end=2.0, chord="G"),
            ],
            final_segments=[Segment(start=0.0, end=2.0, chord="C")],
            radius_sec=1.0,
        )

        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["segmentBoundarySec"], 1.0)
        self.assertEqual(rows[0]["finalSegmentLabel"], "C")
        self.assertEqual(rows[1]["rootPrediction"], "G")
        self.assertEqual(rows[1]["chunkIndex"], 0)


if __name__ == "__main__":
    unittest.main()

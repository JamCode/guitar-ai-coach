"""ONNX 和弦识别时间诊断单元测试。"""
from __future__ import annotations

import unittest
import sys
import types
import importlib.machinery
import importlib.util

import numpy as np

if importlib.util.find_spec("librosa") is None and "librosa" not in sys.modules:
    fake_librosa = types.ModuleType("librosa")
    fake_librosa.__spec__ = importlib.machinery.ModuleSpec("librosa", loader=None)
    sys.modules["librosa"] = fake_librosa
if importlib.util.find_spec("onnxruntime") is None and "onnxruntime" not in sys.modules:
    fake_onnxruntime = types.ModuleType("onnxruntime")
    fake_onnxruntime.__spec__ = importlib.machinery.ModuleSpec("onnxruntime", loader=None)
    sys.modules["onnxruntime"] = fake_onnxruntime

from inference import FRAME_SEC, ChordOnnxInferenceService, Segment


def _logits(indices: list[int], class_count: int) -> np.ndarray:
    arr = np.full((len(indices), class_count), -8.0, dtype=np.float32)
    for frame_idx, class_idx in enumerate(indices):
        arr[frame_idx, class_idx] = 8.0
    return arr


def _logits_with_margin(indices: list[int], class_count: int, *, peak: float, runner_up: float = -8.0) -> np.ndarray:
    arr = np.full((len(indices), class_count), -8.0, dtype=np.float32)
    for frame_idx, class_idx in enumerate(indices):
        arr[frame_idx, class_idx] = peak
        alt_idx = (class_idx + 1) % class_count
        arr[frame_idx, alt_idx] = runner_up
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

    def test_decode_outputs_suppresses_low_confidence_frame(self) -> None:
        result = self.service._decode_outputs(
            {
                "root_logits": _logits_with_margin([0], 13, peak=0.05, runner_up=0.04),
                "bass_logits": _logits_with_margin([0], 13, peak=0.05, runner_up=0.04),
                "chord_logits": np.zeros((1, 12), dtype=np.float32),
            },
            frame_sec=FRAME_SEC,
        )

        self.assertEqual(result["segments"], [])
        self.assertEqual(result["frame_diagnostics"][0]["chordLabel"], "N")
        self.assertEqual(result["frame_diagnostics"][0]["smoothedLabel"], "N")

    def test_decode_outputs_smooths_short_flip_back_to_neighbor(self) -> None:
        result = self.service._decode_outputs(
            {
                "root_logits": _logits([0, 0, 7, 0, 0], 13),
                "bass_logits": _logits([0, 0, 7, 0, 0], 13),
                "chord_logits": _chroma_logits(
                    [
                        [0, 4, 7],
                        [0, 4, 7],
                        [7, 11, 2],
                        [0, 4, 7],
                        [0, 4, 7],
                    ]
                ),
            },
            frame_sec=FRAME_SEC,
        )

        self.assertEqual(
            result["segments"],
            [Segment(start=0.0, end=round(5 * FRAME_SEC, 3), chord="C")],
        )
        self.assertEqual(result["frame_diagnostics"][2]["chordLabel"], "G")
        self.assertEqual(result["frame_diagnostics"][2]["smoothedLabel"], "C")

    def test_make_simplified_segments_drops_short_dominant7(self) -> None:
        out = self.service._make_simplified_segments(
            [
                Segment(start=0.0, end=1.8, chord="E7"),
                Segment(start=1.8, end=3.0, chord="E"),
            ]
        )

        self.assertEqual(
            out,
            [Segment(start=0.0, end=3.0, chord="E")],
        )

    def test_make_simplified_segments_keeps_long_dominant7(self) -> None:
        out = self.service._make_simplified_segments(
            [
                Segment(start=0.0, end=2.6, chord="E7"),
                Segment(start=2.6, end=4.0, chord="A"),
            ]
        )

        self.assertEqual(out[0], Segment(start=0.0, end=2.6, chord="E7"))

    def test_stabilize_frame_labels_delays_switch_until_confident(self) -> None:
        labels = ["C", "C", "G", "G", "G", "G", "G"]
        confidences = np.asarray([0.82, 0.8, 0.41, 0.45, 0.78, 0.79, 0.8], dtype=np.float32)

        out = self.service._stabilize_frame_labels(labels, confidences)

        self.assertEqual(out[:3], ["C", "C", "C"])
        self.assertEqual(out[-3:], ["G", "G", "G"])


if __name__ == "__main__":
    unittest.main()

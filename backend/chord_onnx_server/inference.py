from __future__ import annotations

import shutil
import subprocess
import tempfile
import uuid
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import librosa
import numpy as np
import onnxruntime as ort

from chord_chart_postprocess import build_chord_chart_segments
from playable_compact_postprocess import build_playable_compact_segments
from timing_compact_postprocess import build_timing_compact_segments
from timing_segment_postprocess import build_timing_priority_segments


NOTE_NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
TARGET_SR = 22050
HOP_LENGTH = 512
FRAME_SEC = HOP_LENGTH / TARGET_SR
DEFAULT_N_BINS = 144
BINS_PER_OCTAVE = 24
CHUNK_DURATION_SEC = 20.0
CHUNK_SAMPLES = int(TARGET_SR * CHUNK_DURATION_SEC)
CHUNK_FRAMES = int(np.ceil(CHUNK_SAMPLES / HOP_LENGTH))
FRAME_LABEL_ROOT_CONF_MIN = 0.33
FRAME_LABEL_ROOT_MARGIN_MIN = 0.025
FRAME_LABEL_CONF_MIN = 0.50
FRAME_LABEL_COMPLEX_CONF_MIN = 0.64
FRAME_LABEL_SLASH_CONF_MIN = 0.70
FRAME_LABEL_MIN_MEMBER_PROB = 0.42
STABILIZE_MAJORITY_RADIUS = 3
STABILIZE_MAX_FLIP_FRAMES = 4
STABILIZE_MIN_RUN_FRAMES = 5
STABILIZE_LOW_CONF_MAX = 0.58
STABILIZE_JOIN_GAP_FRAMES = 3
STABILIZE_SWITCH_CONFIRM_FRAMES = 3
STABILIZE_SWITCH_CONFIRM_CONF_MIN = 0.67
STABILIZE_EDGE_TRIM_MAX_FRAMES = 3
STABILIZE_EDGE_TRIM_CONF_MAX = 0.62
STABILIZE_EDGE_KEEP_MIN_FRAMES = 3
STABILIZE_MAX_PASSES = 4
DISPLAY_KEEP_DOMINANT7_MIN_SEC = 2.4
ENABLE_BOUNDARY_DIAGNOSTICS = os.getenv("CHORD_ONNX_BOUNDARY_DIAGNOSTICS", "").strip().lower() in {"1", "true", "yes", "on"}

CHORD_QUALITY_CANDIDATES = (
    {"suffix": "", "intervals": (0, 4, 7), "penalties": (3,), "kind": "basic"},
    {"suffix": "m", "intervals": (0, 3, 7), "penalties": (4,), "kind": "basic"},
    {"suffix": "7", "intervals": (0, 4, 7, 10), "penalties": (3, 11), "kind": "extended"},
    {"suffix": "m7", "intervals": (0, 3, 7, 10), "penalties": (4, 11), "kind": "extended"},
    {"suffix": "maj7", "intervals": (0, 4, 7, 11), "penalties": (3, 10), "kind": "color"},
    {"suffix": "sus4", "intervals": (0, 5, 7), "penalties": (3, 4), "kind": "color"},
    {"suffix": "sus2", "intervals": (0, 2, 7), "penalties": (3, 4, 5), "kind": "color"},
    {"suffix": "dim", "intervals": (0, 3, 6), "penalties": (4, 7), "kind": "color"},
    {"suffix": "aug", "intervals": (0, 4, 8), "penalties": (3, 7), "kind": "color"},
    {"suffix": "5", "intervals": (0, 7), "penalties": (3, 4), "kind": "basic"},
)


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def _decode_to_temp_wav_with_ffmpeg(src: Path) -> Path:
    """Decode arbitrary container/codec to 22050 Hz mono WAV for librosa."""
    if not ffmpeg_available():
        raise RuntimeError("ffmpeg not found on PATH; cannot decode this audio file")
    out = Path(tempfile.gettempdir()) / f"chord_onnx_ff_{uuid.uuid4().hex}.wav"
    try:
        subprocess.run(
            [
                "ffmpeg",
                "-nostdin",
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(src),
                "-ac",
                "1",
                "-ar",
                str(TARGET_SR),
                "-f",
                "wav",
                str(out),
            ],
            check=True,
            timeout=900,
            capture_output=True,
        )
    except Exception:
        out.unlink(missing_ok=True)
        raise
    return out


def load_audio_mono_22050(audio_path: Path) -> np.ndarray:
    """Load audio at TARGET_SR mono; try librosa first, then ffmpeg -> wav -> librosa."""
    try:
        y, _sr = librosa.load(str(audio_path), sr=TARGET_SR, mono=True)
        return y
    except Exception as exc:  # noqa: BLE001
        print(f"[ONNX] librosa.load failed ({audio_path.suffix}): {exc!r}; trying ffmpeg")
        tmp = _decode_to_temp_wav_with_ffmpeg(audio_path)
        try:
            y, _sr = librosa.load(str(tmp), sr=TARGET_SR, mono=True)
            return y
        finally:
            tmp.unlink(missing_ok=True)


class InferenceInputShapeError(RuntimeError):
    pass


@dataclass
class Segment:
    start: float
    end: float
    chord: str


class ChordOnnxInferenceService:
    def __init__(self, model_path: Path) -> None:
        if not model_path.exists():
            raise FileNotFoundError(f"model not found: {model_path}")
        self.session = ort.InferenceSession(
            str(model_path),
            providers=["CPUExecutionProvider"],
        )
        self.input_meta = self.session.get_inputs()[0]
        self.output_meta = self.session.get_outputs()
        self.model_info = {
            "input_name": self.input_meta.name,
            "input_shape": self.input_meta.shape,
            "output_names": [o.name for o in self.output_meta],
            "output_shapes": {o.name: o.shape for o in self.output_meta},
        }

    def transcribe(self, audio_path: Path) -> dict[str, Any]:
        y = load_audio_mono_22050(audio_path)
        sr = TARGET_SR
        duration = float(len(y) / TARGET_SR)
        chunk_count = max(1, int(np.ceil(len(y) / CHUNK_SAMPLES)))
        all_segments: list[Segment] = []
        all_frame_diagnostics: list[dict[str, Any]] = []
        chunk_debug: list[dict[str, Any]] = []
        decode_mode = "simple_root_bass_chroma"
        raw_preview: dict[str, Any] = {}
        last_output_shapes: dict[str, list[int]] = {}
        input_feature_shape: list[int] = []
        model_input_shape: list[int] = []

        for chunk_idx in range(chunk_count):
            chunk_start_sample = chunk_idx * CHUNK_SAMPLES
            chunk_end_sample = min(len(y), chunk_start_sample + CHUNK_SAMPLES)
            if chunk_end_sample <= chunk_start_sample:
                continue

            chunk_samples = y[chunk_start_sample:chunk_end_sample]
            features = self._extract_cqt_features(chunk_samples)
            prepared = self._adapt_input_shape(features)
            outputs = self.session.run(None, {self.input_meta.name: prepared})
            out_map = {meta.name: arr for meta, arr in zip(self.output_meta, outputs)}

            decode_result = self._decode_outputs(out_map, frame_sec=FRAME_SEC)
            decode_mode = decode_result["decode_mode"]
            raw_preview = decode_result.get("raw_preview", {})
            last_output_shapes = {k: list(v.shape) for k, v in out_map.items()}
            input_feature_shape = list(features.shape)
            model_input_shape = list(prepared.shape)

            chunk_start_sec = chunk_start_sample / TARGET_SR
            chunk_end_sec = chunk_end_sample / TARGET_SR
            local_segments: list[Segment] = decode_result["segments"]
            shifted: list[Segment] = []
            local_duration_sec = chunk_end_sec - chunk_start_sec
            local_frame_diagnostics = decode_result.get("frame_diagnostics", [])
            for frame_debug in local_frame_diagnostics:
                local_time_sec = float(frame_debug["timeSec"])
                if local_time_sec >= local_duration_sec:
                    continue
                global_time_sec = chunk_start_sec + local_time_sec
                all_frame_diagnostics.append(
                    {
                        **frame_debug,
                        "frameIndex": int(round(global_time_sec / FRAME_SEC)),
                        "localFrameIndex": frame_debug["frameIndex"],
                        "timeSec": round(global_time_sec, 6),
                        "chunkIndex": chunk_idx,
                        "chunkStartSec": round(chunk_start_sec, 6),
                    }
                )
            for seg in local_segments:
                global_start = chunk_start_sec + seg.start
                global_end = min(chunk_start_sec + seg.end, chunk_end_sec)
                if global_end <= global_start:
                    continue
                shifted.append(
                    Segment(
                        start=round(global_start, 3),
                        end=round(global_end, 3),
                        chord=seg.chord,
                    )
                )
            all_segments.extend(shifted)
            chunk_debug.append(
                {
                    "chunk_index": chunk_idx,
                    "start": round(chunk_start_sec, 3),
                    "end": round(chunk_end_sec, 3),
                    "segment_count": len(shifted),
                    "diagnostic_frame_count": len(local_frame_diagnostics),
                }
            )

        merged_segments = self._merge_adjacent_segments(all_segments, tolerance_sec=FRAME_SEC)
        display_segments, display_stats = self._make_display_segments(merged_segments)
        no_absorb_display, _ = self._make_display_segments(
            merged_segments,
            short_absorb=False,
            boundary_refinement=False,
        )
        simplified_segments = self._make_simplified_segments(display_segments)
        no_absorb_simplified = self._make_simplified_segments(no_absorb_display)
        boundary_frame_diagnostics = self._collect_boundary_frame_diagnostics(
            frames=all_frame_diagnostics,
            boundary_segments=merged_segments,
            final_segments=simplified_segments,
            radius_sec=1.0,
        )
        if ENABLE_BOUNDARY_DIAGNOSTICS:
            self._log_boundary_frame_diagnostics(boundary_frame_diagnostics)
        key_result = self._estimate_key(merged_segments)
        chart_res = build_chord_chart_segments(
            [
                {"start": s.start, "end": s.end, "chord": s.chord, "confidence": 1.0}
                for s in simplified_segments
            ],
            estimated_key=key_result.get("key"),
            enable_segment_absorption=True,
        )
        chart_no_absorb = build_chord_chart_segments(
            [
                {"start": s.start, "end": s.end, "chord": s.chord, "confidence": 1.0}
                for s in no_absorb_simplified
            ],
            estimated_key=key_result.get("key"),
            enable_segment_absorption=False,
        )
        timing_build = build_timing_priority_segments(
            y=y,
            sr=int(sr),
            no_absorb_simplified=no_absorb_simplified,
            merged_segments=merged_segments,
            anchor_segments=simplified_segments,
            hop_length=HOP_LENGTH,
        )
        timing_seg_dicts = timing_build["segments"]
        timing_segments = [
            Segment(start=float(d["start"]), end=float(d["end"]), chord=str(d["chord"]))
            for d in timing_seg_dicts
        ]
        chart_timing = build_chord_chart_segments(
            [dict(d) for d in timing_seg_dicts],
            estimated_key=key_result.get("key"),
            enable_segment_absorption=True,
        )
        compact_build = build_timing_compact_segments(
            y=y,
            sr=int(sr),
            timing_segments=timing_segments,
            merged_segments=merged_segments,
            hop_length=HOP_LENGTH,
        )
        compact_seg_dicts = compact_build["segments"]
        compact_segments = [
            Segment(start=float(d["start"]), end=float(d["end"]), chord=str(d["chord"]))
            for d in compact_seg_dicts
        ]
        chart_timing_compact = build_chord_chart_segments(
            [dict(d) for d in compact_seg_dicts],
            estimated_key=key_result.get("key"),
            enable_segment_absorption=True,
        )
        playable_build = build_playable_compact_segments(
            y=y,
            sr=int(sr),
            timing_compact_segments=compact_segments,
            merged_segments=merged_segments,
            hop_length=HOP_LENGTH,
        )
        playable_seg_dicts = playable_build["segments"]
        playable_segments = [
            Segment(start=float(d["start"]), end=float(d["end"]), chord=str(d["chord"]))
            for d in playable_seg_dicts
        ]
        chart_playable_compact = build_chord_chart_segments(
            [dict(d) for d in playable_seg_dicts],
            estimated_key=key_result.get("key"),
            enable_segment_absorption=True,
        )
        timing_stats_extra = timing_build["stats"]
        compact_stats_extra = compact_build["stats"]
        playable_stats_extra = playable_build["stats"]
        chart_proc_debug = dict(chart_res["debug"])
        chart_proc_debug["chordChartSourceSegmentCount"] = chart_proc_debug.pop(
            "rawSegmentCount", len(simplified_segments)
        )

        normal_display_payload = [s.__dict__ for s in simplified_segments]
        no_absorb_display_payload = [s.__dict__ for s in no_absorb_simplified]
        timing_display_payload = [s.__dict__ for s in timing_segments]
        timing_compact_payload = [s.__dict__ for s in compact_segments]
        playable_compact_payload = [s.__dict__ for s in playable_segments]
        timing_variants: dict[str, Any] = {
            "normal": {
                "displaySegments": normal_display_payload,
                "simplifiedDisplaySegments": normal_display_payload,
                "chordChartSegments": chart_res["chordChartSegments"],
            },
            "noAbsorb": {
                "displaySegments": no_absorb_display_payload,
                "simplifiedDisplaySegments": no_absorb_display_payload,
                "chordChartSegments": chart_no_absorb["chordChartSegments"],
            },
            "timing": {
                "displaySegments": timing_display_payload,
                "simplifiedDisplaySegments": timing_display_payload,
                "chordChartSegments": chart_timing["chordChartSegments"],
            },
            "timingCompact": {
                "displaySegments": timing_compact_payload,
                "simplifiedDisplaySegments": timing_compact_payload,
                "chordChartSegments": chart_timing_compact["chordChartSegments"],
            },
            "playableCompact": {
                "displaySegments": playable_compact_payload,
                "simplifiedDisplaySegments": playable_compact_payload,
                "chordChartSegments": chart_playable_compact["chordChartSegments"],
            },
        }
        timing_variant_stats: dict[str, Any] = {
            "normal": {
                "displayCount": len(normal_display_payload),
                "simplifiedCount": len(normal_display_payload),
                "chordChartCount": len(chart_res["chordChartSegments"]),
            },
            "noAbsorb": {
                "displayCount": len(no_absorb_display_payload),
                "simplifiedCount": len(no_absorb_display_payload),
                "chordChartCount": len(chart_no_absorb["chordChartSegments"]),
            },
            "timing": {
                "displayCount": len(timing_display_payload),
                "simplifiedCount": len(timing_display_payload),
                "chordChartCount": len(chart_timing["chordChartSegments"]),
                "absorbedCount": timing_stats_extra["absorbedCount"],
                "keptShortCount": timing_stats_extra["keptShortCount"],
                "snappedBoundaryCount": timing_stats_extra["snappedBoundaryCount"],
            },
            "timingCompact": {
                "displayCount": len(timing_compact_payload),
                "simplifiedCount": len(timing_compact_payload),
                "chordChartCount": len(chart_timing_compact["chordChartSegments"]),
                "compressedCount": compact_stats_extra["compressedCount"],
                "preservedTransitionCount": compact_stats_extra["preservedTransitionCount"],
            },
            "playableCompact": {
                "displayCount": len(playable_compact_payload),
                "simplifiedCount": len(playable_compact_payload),
                "chordChartCount": len(chart_playable_compact["chordChartSegments"]),
                "compressedCount": playable_stats_extra["compressedCount"],
                "simplifiedChordNameCount": playable_stats_extra["simplifiedChordNameCount"],
                "preservedTransitionCount": playable_stats_extra["preservedTransitionCount"],
                "targetDensityAppliedCount": playable_stats_extra["targetDensityAppliedCount"],
            },
        }

        return {
            "duration": round(duration, 3),
            "key": key_result["key"],
            "segments": [s.__dict__ for s in merged_segments],  # raw segments
            "displaySegments": [s.__dict__ for s in simplified_segments],
            "simplifiedDisplaySegments": [s.__dict__ for s in simplified_segments],
            "chordChartSegments": chart_res["chordChartSegments"],
            "timingVariants": timing_variants,
            "timingVariantStats": timing_variant_stats,
            "debug": {
                "duration": round(duration, 3),
                "chunkDuration": CHUNK_DURATION_SEC,
                "chunkCount": chunk_count,
                "chunks": chunk_debug,
                "sampleRate": TARGET_SR,
                "hopLength": HOP_LENGTH,
                "frameSec": FRAME_SEC,
                "frameTimeFormula": "frameIndex * hopLength / sampleRate",
                "featureFrameTimestampSemantic": "librosa_cqt_center_at_frameIndex_hop_sampleRate",
                "segmentTimestampSemantic": "current_decoder_uses_frameIndex_hop_sampleRate_as_segment_boundary",
                "featureWindowSec": None,
                "featureWindowSemantic": "librosa_cqt_frequency_dependent_centered_windows",
                "boundaryFrameDiagnosticCount": len(boundary_frame_diagnostics),
                "input_feature_shape": input_feature_shape,
                "model_input_shape": model_input_shape,
                "output_shapes": last_output_shapes,
                "decode_mode": decode_mode,
                "raw_preview": raw_preview,
                "keyScores": key_result["top5"],
                "keyConfidence": key_result["confidence"],
                "rawSegmentCount": len(merged_segments),
                "displaySegmentCount": len(simplified_segments),
                "removedShortSegmentCount": display_stats["removed_short_count"],
                "sameSecondConflictCount": display_stats["same_second_conflict_count"],
                "displayChordText": self._build_display_chord_text(simplified_segments, max_lines=20),
                "simplifiedChordText": self._build_display_chord_text(simplified_segments, max_lines=20),
                "simplifiedSegmentCount": len(simplified_segments),
                **chart_proc_debug,
                **timing_build["debug"],
                **compact_build["debug"],
                **playable_build["debug"],
            },
        }

    def _extract_cqt_features(self, y: np.ndarray) -> np.ndarray:
        # Keep first 20s chunk for MVP service, matching iOS-side ONNX chunking shape.
        if y.shape[0] < CHUNK_SAMPLES:
            y = np.pad(y, (0, CHUNK_SAMPLES - y.shape[0]), mode="constant")
        elif y.shape[0] > CHUNK_SAMPLES:
            y = y[:CHUNK_SAMPLES]

        cqt = librosa.cqt(
            y,
            sr=TARGET_SR,
            hop_length=HOP_LENGTH,
            n_bins=DEFAULT_N_BINS,
            bins_per_octave=BINS_PER_OCTAVE,
        )
        mag = np.abs(cqt).astype(np.float32)
        feat = np.log1p(mag)
        # Strong guard for model reshape expectation.
        if feat.shape[1] < CHUNK_FRAMES:
            feat = np.pad(feat, ((0, 0), (0, CHUNK_FRAMES - feat.shape[1])), mode="constant")
        elif feat.shape[1] > CHUNK_FRAMES:
            feat = feat[:, :CHUNK_FRAMES]
        # [1, 1, n_bins, frames]
        return feat[np.newaxis, np.newaxis, :, :]

    def _adapt_input_shape(self, x: np.ndarray) -> np.ndarray:
        expected = self.input_meta.shape
        if len(expected) != 4:
            raise InferenceInputShapeError(f"unsupported model input rank: {expected}")

        out = x.astype(np.float32, copy=False)
        for axis, exp in enumerate(expected):
            if isinstance(exp, str) or exp is None:
                continue
            exp = int(exp)
            cur = out.shape[axis]
            if exp <= 0 or cur == exp:
                continue

            # axis 0/1 are batch/channel, force to 1
            if axis in (0, 1):
                if exp != 1:
                    raise InferenceInputShapeError(
                        f"cannot adapt axis {axis} from {cur} to {exp}"
                    )
                if cur > 1:
                    slicer = [slice(None)] * out.ndim
                    slicer[axis] = slice(0, 1)
                    out = out[tuple(slicer)]
                else:
                    pad_width = [(0, 0)] * out.ndim
                    pad_width[axis] = (0, exp - cur)
                    out = np.pad(out, pad_width, mode="constant")
                continue

            # axis 2/3 are bins/frames, crop or right-pad zeros
            if cur > exp:
                slicer = [slice(None)] * out.ndim
                slicer[axis] = slice(0, exp)
                out = out[tuple(slicer)]
            else:
                pad_width = [(0, 0)] * out.ndim
                pad_width[axis] = (0, exp - cur)
                out = np.pad(out, pad_width, mode="constant")

        if any(
            (not isinstance(exp, str) and exp is not None and int(exp) > 0 and out.shape[i] != int(exp))
            for i, exp in enumerate(expected)
        ):
            raise InferenceInputShapeError(
                f"feature shape mismatch: got {list(out.shape)}, expected {expected}"
            )
        return out

    def _decode_outputs(self, outputs: dict[str, np.ndarray], frame_sec: float) -> dict[str, Any]:
        root_logits = outputs.get("root_logits")
        bass_logits = outputs.get("bass_logits")
        chord_logits = outputs.get("chord_logits")

        if root_logits is None or bass_logits is None or chord_logits is None:
            # fallback: return raw shape preview so user can debug decoder mapping
            preview = {
                name: {
                    "shape": list(arr.shape),
                    "first_values": arr.reshape(-1)[:10].astype(float).tolist(),
                }
                for name, arr in outputs.items()
            }
            return {
                "key": "C",
                "segments": [],
                "decode_mode": "raw_preview_only",
                "raw_preview": preview,
            }

        root_2d = self._reshape_to_2d(root_logits, class_count=13)
        bass_2d = self._reshape_to_2d(bass_logits, class_count=13)
        chroma_2d = self._reshape_to_2d(chord_logits, class_count=12)

        frame_count = min(root_2d.shape[0], bass_2d.shape[0], chroma_2d.shape[0])
        root_slice = root_2d[:frame_count]
        bass_slice = bass_2d[:frame_count]
        root_idx = np.argmax(root_slice, axis=1)
        bass_idx = np.argmax(bass_slice, axis=1)
        chroma_prob = 1.0 / (1.0 + np.exp(-chroma_2d[:frame_count]))
        root_prob = self._softmax(root_slice)
        bass_prob = self._softmax(bass_slice)

        predictions = [
            self._decode_frame_prediction(
                root=int(root_idx[i]),
                bass=int(bass_idx[i]),
                chroma_prob=chroma_prob[i],
                root_prob=root_prob[i],
                bass_prob=bass_prob[i],
            )
            for i in range(frame_count)
        ]
        labels = [pred["label"] for pred in predictions]
        label_conf = np.asarray([pred["confidence"] for pred in predictions], dtype=np.float32)
        smoothed_labels = self._stabilize_frame_labels(labels, label_conf)
        frame_diagnostics = [
            {
                "frameIndex": i,
                "timeSec": round(i * frame_sec, 6),
                "rootPrediction": NOTE_NAMES[int(root_idx[i])] if int(root_idx[i]) < 12 else "N",
                "chordLabel": labels[i],
                "confidence": round(float(label_conf[i]), 6),
                "smoothedLabel": smoothed_labels[i],
            }
            for i in range(frame_count)
        ]
        segments = self._merge_labels(smoothed_labels, frame_sec=frame_sec)
        return {
            "key": "C",
            "segments": segments,
            "decode_mode": "simple_root_bass_chroma",
            "frame_diagnostics": frame_diagnostics,
        }

    def _softmax_max(self, logits: np.ndarray) -> np.ndarray:
        if logits.size == 0:
            return np.zeros((0,), dtype=np.float32)
        probs = self._softmax(logits)
        return np.max(probs, axis=1)

    def _softmax(self, logits: np.ndarray) -> np.ndarray:
        if logits.size == 0:
            return np.zeros_like(logits, dtype=np.float32)
        stable = logits - np.max(logits, axis=1, keepdims=True)
        exp = np.exp(stable)
        denom = np.sum(exp, axis=1, keepdims=True)
        return (exp / np.maximum(denom, 1e-12)).astype(np.float32)

    def _reshape_to_2d(self, arr: np.ndarray, class_count: int) -> np.ndarray:
        arr = np.asarray(arr)
        if arr.size == 0:
            return np.zeros((0, class_count), dtype=np.float32)
        if arr.shape[-1] == class_count:
            return arr.reshape(-1, class_count).astype(np.float32)
        # Fallback for unexpected layout
        flat = arr.reshape(-1)
        frame_count = flat.size // class_count
        if frame_count <= 0:
            return np.zeros((0, class_count), dtype=np.float32)
        return flat[: frame_count * class_count].reshape(frame_count, class_count).astype(np.float32)

    def _decode_frame_prediction(
        self,
        *,
        root: int,
        bass: int,
        chroma_prob: np.ndarray,
        root_prob: np.ndarray,
        bass_prob: np.ndarray,
    ) -> dict[str, Any]:
        if root >= 12:
            return {"label": "N", "confidence": 0.0}

        root_conf = float(root_prob[root])
        root_margin = self._top1_margin(root_prob)
        if root_conf < FRAME_LABEL_ROOT_CONF_MIN or root_margin < FRAME_LABEL_ROOT_MARGIN_MIN:
            return {"label": "N", "confidence": max(0.0, root_conf)}

        rel_prob = np.asarray(
            [float(chroma_prob[(root + interval) % 12]) for interval in range(12)],
            dtype=np.float32,
        )
        candidate = self._select_quality_candidate(rel_prob)
        if candidate is None:
            return {"label": "N", "confidence": root_conf}

        quality_conf = float(candidate["score"])
        combined_conf = (
            0.38 * root_conf
            + 0.22 * min(1.0, root_margin / 0.18)
            + 0.40 * quality_conf
        )
        combined_conf = round(float(np.clip(combined_conf, 0.0, 1.0)), 6)
        min_member_prob = float(candidate["min_member_prob"])
        required_conf = FRAME_LABEL_COMPLEX_CONF_MIN if candidate["kind"] != "basic" else FRAME_LABEL_CONF_MIN
        if combined_conf < required_conf or min_member_prob < FRAME_LABEL_MIN_MEMBER_PROB:
            fallback = self._fallback_basic_candidate(rel_prob)
            if fallback is None:
                return {"label": "N", "confidence": combined_conf}
            candidate = fallback
            quality_conf = float(candidate["score"])
            combined_conf = round(
                float(
                    np.clip(
                        0.42 * root_conf
                        + 0.18 * min(1.0, root_margin / 0.18)
                        + 0.40 * quality_conf,
                        0.0,
                        1.0,
                    )
                ),
                6,
            )
            min_member_prob = float(candidate["min_member_prob"])
            if combined_conf < FRAME_LABEL_CONF_MIN or min_member_prob < FRAME_LABEL_MIN_MEMBER_PROB:
                return {"label": "N", "confidence": combined_conf}

        suffix = str(candidate["suffix"])
        base = f"{NOTE_NAMES[root]}{suffix}"
        if bass < 12 and bass != root:
            bass_conf = float(bass_prob[bass])
            bass_rel_prob = float(rel_prob[(bass - root) % 12])
            if (
                combined_conf >= FRAME_LABEL_SLASH_CONF_MIN
                and bass_conf >= 0.40
                and bass_rel_prob >= 0.40
            ):
                base = f"{base}/{NOTE_NAMES[bass]}"
        return {"label": base, "confidence": combined_conf}

    def _select_quality_candidate(self, rel_prob: np.ndarray) -> dict[str, Any] | None:
        candidates = [self._score_quality_candidate(rel_prob, spec) for spec in CHORD_QUALITY_CANDIDATES]
        if not candidates:
            return None
        candidates.sort(key=lambda item: (item["score"], item["min_member_prob"]), reverse=True)
        best = candidates[0]
        if best["score"] < 0.44:
            return None
        return best

    def _fallback_basic_candidate(self, rel_prob: np.ndarray) -> dict[str, Any] | None:
        basic = [
            self._score_quality_candidate(rel_prob, spec)
            for spec in CHORD_QUALITY_CANDIDATES
            if spec["kind"] == "basic"
        ]
        if not basic:
            return None
        basic.sort(key=lambda item: (item["score"], item["min_member_prob"]), reverse=True)
        return basic[0]

    def _score_quality_candidate(self, rel_prob: np.ndarray, spec: dict[str, Any]) -> dict[str, Any]:
        members = np.asarray(spec["intervals"], dtype=np.int32)
        penalties = np.asarray(spec["penalties"], dtype=np.int32)
        member_prob = rel_prob[members]
        member_mean = float(np.mean(member_prob))
        member_min = float(np.min(member_prob))
        penalty_mean = float(np.mean(rel_prob[penalties])) if penalties.size else 0.0
        outsider_mask = np.ones(12, dtype=bool)
        outsider_mask[members] = False
        outsider_top = float(np.max(rel_prob[outsider_mask])) if np.any(outsider_mask) else 0.0
        score = (
            0.62 * member_mean
            + 0.28 * member_min
            - 0.18 * penalty_mean
            - 0.08 * outsider_top
        )
        score = float(np.clip(score, 0.0, 1.0))
        return {
            "suffix": spec["suffix"],
            "kind": spec["kind"],
            "score": score,
            "min_member_prob": member_min,
        }

    def _top1_margin(self, prob: np.ndarray) -> float:
        if prob.size <= 1:
            return 0.0
        top2 = np.partition(prob, -2)[-2:]
        return float(top2[-1] - top2[-2])

    def _stabilize_frame_labels(self, labels: list[str], confidences: np.ndarray) -> list[str]:
        if not labels:
            return []
        smoothed = self._majority_vote_labels(labels, confidences, radius=STABILIZE_MAJORITY_RADIUS)
        smoothed = self._collapse_short_runs(smoothed, confidences)
        smoothed = self._confirm_label_switches(smoothed, confidences)
        smoothed = self._trim_unstable_run_edges(smoothed, confidences)
        smoothed = self._join_short_gaps(smoothed, confidences)
        smoothed = self._collapse_short_runs(smoothed, confidences)
        return smoothed

    def _majority_vote_labels(self, labels: list[str], confidences: np.ndarray, *, radius: int) -> list[str]:
        if radius <= 0 or len(labels) <= 2:
            return list(labels)
        out = list(labels)
        for idx, current in enumerate(labels):
            lo = max(0, idx - radius)
            hi = min(len(labels), idx + radius + 1)
            weights: dict[str, float] = {}
            for j in range(lo, hi):
                label = labels[j]
                if label == "N":
                    continue
                distance_boost = 1.0 / (1.0 + abs(j - idx))
                weights[label] = weights.get(label, 0.0) + float(confidences[j]) * distance_boost
            if not weights:
                continue
            best_label, best_weight = max(weights.items(), key=lambda item: item[1])
            current_weight = weights.get(current, 0.0)
            if current == "N":
                if best_weight >= 0.95:
                    out[idx] = best_label
                continue
            if best_label != current and best_weight >= current_weight + 0.18:
                out[idx] = best_label
        return out

    def _collapse_short_runs(self, labels: list[str], confidences: np.ndarray) -> list[str]:
        out = list(labels)
        for _ in range(STABILIZE_MAX_PASSES):
            runs = self._label_runs(out)
            changed = False
            for idx, run in enumerate(runs):
                run_len = run["end"] - run["start"]
                run_conf = float(np.mean(confidences[run["start"]:run["end"]]))
                prev_run = runs[idx - 1] if idx > 0 else None
                next_run = runs[idx + 1] if idx + 1 < len(runs) else None
                if (
                    prev_run is not None
                    and next_run is not None
                    and prev_run["label"] == next_run["label"]
                    and run_len <= STABILIZE_MAX_FLIP_FRAMES
                    and run_conf <= 0.66
                ):
                    for pos in range(run["start"], run["end"]):
                        out[pos] = prev_run["label"]
                    changed = True
                    break
                if run["label"] == "N":
                    continue
                if run_len >= STABILIZE_MIN_RUN_FRAMES or run_conf > STABILIZE_LOW_CONF_MAX:
                    continue
                replacement = None
                if prev_run is not None and next_run is not None:
                    prev_score = (prev_run["end"] - prev_run["start"], float(np.mean(confidences[prev_run["start"]:prev_run["end"]])))
                    next_score = (next_run["end"] - next_run["start"], float(np.mean(confidences[next_run["start"]:next_run["end"]])))
                    replacement = prev_run["label"] if prev_score >= next_score else next_run["label"]
                elif prev_run is not None:
                    replacement = prev_run["label"]
                elif next_run is not None:
                    replacement = next_run["label"]
                if replacement is None:
                    continue
                for pos in range(run["start"], run["end"]):
                    out[pos] = replacement
                changed = True
                break
            if not changed:
                return out
        return out

    def _join_short_gaps(self, labels: list[str], confidences: np.ndarray) -> list[str]:
        out = list(labels)
        for _ in range(STABILIZE_MAX_PASSES):
            runs = self._label_runs(out)
            changed = False
            for idx, run in enumerate(runs):
                if run["label"] != "N":
                    continue
                prev_run = runs[idx - 1] if idx > 0 else None
                next_run = runs[idx + 1] if idx + 1 < len(runs) else None
                if prev_run is None or next_run is None or prev_run["label"] != next_run["label"]:
                    continue
                run_len = run["end"] - run["start"]
                run_conf = float(np.mean(confidences[run["start"]:run["end"]]))
                if run_len > STABILIZE_JOIN_GAP_FRAMES or run_conf > 0.62:
                    continue
                for pos in range(run["start"], run["end"]):
                    out[pos] = prev_run["label"]
                changed = True
                break
            if not changed:
                return out
        return out

    def _confirm_label_switches(self, labels: list[str], confidences: np.ndarray) -> list[str]:
        out = list(labels)
        if len(out) <= 1:
            return out
        runs = self._label_runs(out)
        for idx, run in enumerate(runs):
            if idx == 0 or run["label"] == "N":
                continue
            prev_run = runs[idx - 1]
            if prev_run["label"] == "N" or prev_run["label"] == run["label"]:
                continue
            confirm_at = self._find_switch_confirmation_index(run, confidences)
            if confirm_at is None:
                continue
            for pos in range(run["start"], confirm_at):
                out[pos] = prev_run["label"]
        return out

    def _find_switch_confirmation_index(
        self,
        run: dict[str, Any],
        confidences: np.ndarray,
    ) -> int | None:
        run_start = int(run["start"])
        run_end = int(run["end"])
        run_len = run_end - run_start
        if run_len <= STABILIZE_SWITCH_CONFIRM_FRAMES:
            return None
        streak = 0
        for pos in range(run_start, run_end):
            if float(confidences[pos]) >= STABILIZE_SWITCH_CONFIRM_CONF_MIN:
                streak += 1
            else:
                streak = 0
            if streak >= STABILIZE_SWITCH_CONFIRM_FRAMES:
                confirm_at = pos - STABILIZE_SWITCH_CONFIRM_FRAMES + 1
                if confirm_at > run_start:
                    return confirm_at
                return None
        max_delay = max(0, run_len - STABILIZE_EDGE_KEEP_MIN_FRAMES)
        if max_delay <= 0:
            return None
        delay = min(max_delay, STABILIZE_EDGE_TRIM_MAX_FRAMES)
        return run_start + delay if delay > 0 else None

    def _trim_unstable_run_edges(self, labels: list[str], confidences: np.ndarray) -> list[str]:
        out = list(labels)
        for _ in range(STABILIZE_MAX_PASSES):
            runs = self._label_runs(out)
            changed = False
            for idx, run in enumerate(runs):
                if run["label"] == "N":
                    continue
                prev_run = runs[idx - 1] if idx > 0 else None
                next_run = runs[idx + 1] if idx + 1 < len(runs) else None
                run_len = run["end"] - run["start"]
                if run_len <= STABILIZE_EDGE_KEEP_MIN_FRAMES:
                    continue

                max_start_trim = min(
                    STABILIZE_EDGE_TRIM_MAX_FRAMES,
                    max(0, run_len - STABILIZE_EDGE_KEEP_MIN_FRAMES),
                )
                trim_start = 0
                if prev_run is not None and prev_run["label"] != run["label"]:
                    while trim_start < max_start_trim:
                        pos = run["start"] + trim_start
                        if float(confidences[pos]) > STABILIZE_EDGE_TRIM_CONF_MAX:
                            break
                        trim_start += 1

                max_end_trim = min(
                    STABILIZE_EDGE_TRIM_MAX_FRAMES,
                    max(0, run_len - STABILIZE_EDGE_KEEP_MIN_FRAMES - trim_start),
                )
                trim_end = 0
                if next_run is not None and next_run["label"] != run["label"]:
                    while trim_end < max_end_trim:
                        pos = run["end"] - 1 - trim_end
                        if float(confidences[pos]) > STABILIZE_EDGE_TRIM_CONF_MAX:
                            break
                        trim_end += 1

                if trim_start == 0 and trim_end == 0:
                    continue

                if prev_run is not None and trim_start > 0:
                    for pos in range(run["start"], run["start"] + trim_start):
                        out[pos] = prev_run["label"]
                if next_run is not None and trim_end > 0:
                    for pos in range(run["end"] - trim_end, run["end"]):
                        out[pos] = next_run["label"]
                changed = True
                break
            if not changed:
                return out
        return out

    def _label_runs(self, labels: list[str]) -> list[dict[str, Any]]:
        if not labels:
            return []
        runs: list[dict[str, Any]] = []
        start = 0
        current = labels[0]
        for idx in range(1, len(labels)):
            if labels[idx] == current:
                continue
            runs.append({"label": current, "start": start, "end": idx})
            current = labels[idx]
            start = idx
        runs.append({"label": current, "start": start, "end": len(labels)})
        return runs

    def _merge_labels(self, labels: list[str], frame_sec: float) -> list[Segment]:
        if not labels:
            return []
        out: list[Segment] = []
        start = 0
        current = labels[0]
        for i in range(1, len(labels)):
            if labels[i] == current:
                continue
            if current != "N":
                out.append(
                    Segment(
                        start=round(start * frame_sec, 3),
                        end=round(i * frame_sec, 3),
                        chord=current,
                    )
                )
            current = labels[i]
            start = i
        if current != "N":
            out.append(
                Segment(
                    start=round(start * frame_sec, 3),
                    end=round(len(labels) * frame_sec, 3),
                    chord=current,
                )
            )
        return out

    def _collect_boundary_frame_diagnostics(
        self,
        *,
        frames: list[dict[str, Any]],
        boundary_segments: list[Segment],
        final_segments: list[Segment],
        radius_sec: float,
    ) -> list[dict[str, Any]]:
        if not frames or len(boundary_segments) < 2:
            return []

        rows: list[dict[str, Any]] = []
        seen: set[tuple[float, int]] = set()
        boundaries = [
            round(boundary_segments[i].start, 6)
            for i in range(1, len(boundary_segments))
        ]
        for boundary_sec in boundaries:
            for frame in frames:
                time_sec = float(frame["timeSec"])
                if abs(time_sec - boundary_sec) > radius_sec:
                    continue
                key = (boundary_sec, int(frame["frameIndex"]))
                if key in seen:
                    continue
                seen.add(key)
                rows.append(
                    {
                        "segmentBoundarySec": round(boundary_sec, 6),
                        "frameIndex": frame["frameIndex"],
                        "timeSec": round(time_sec, 6),
                        "rootPrediction": frame["rootPrediction"],
                        "chordLabel": frame["chordLabel"],
                        "confidence": frame["confidence"],
                        "smoothedLabel": frame["smoothedLabel"],
                        "finalSegmentLabel": self._label_at_time(final_segments, time_sec),
                        "chunkIndex": frame["chunkIndex"],
                        "chunkStartSec": frame["chunkStartSec"],
                    }
                )
        return sorted(rows, key=lambda r: (r["segmentBoundarySec"], r["timeSec"], r["frameIndex"]))

    def _label_at_time(self, segments: list[Segment], time_sec: float) -> str:
        for seg in segments:
            if seg.start <= time_sec < seg.end:
                return seg.chord
        return "-"

    def _log_boundary_frame_diagnostics(self, rows: list[dict[str, Any]]) -> None:
        if not rows:
            print("[CHORD_TIMING] no segment boundary frame diagnostics")
            return

        print(
            "[CHORD_TIMING] boundary diagnostics "
            "columns=boundarySec | frameIndex | timeSec | rootPrediction | chordLabel | "
            "confidence | smoothedLabel | finalSegmentLabel | chunkIndex | chunkStartSec"
        )
        for row in rows:
            print(
                "[CHORD_TIMING] "
                f"{row['segmentBoundarySec']:.6f} | "
                f"{row['frameIndex']} | "
                f"{row['timeSec']:.6f} | "
                f"{row['rootPrediction']} | "
                f"{row['chordLabel']} | "
                f"{row['confidence']:.6f} | "
                f"{row['smoothedLabel']} | "
                f"{row['finalSegmentLabel']} | "
                f"{row['chunkIndex']} | "
                f"{row['chunkStartSec']:.6f}"
            )

    def _merge_adjacent_segments(self, segments: list[Segment], tolerance_sec: float) -> list[Segment]:
        if not segments:
            return []
        segments = sorted(segments, key=lambda s: (s.start, s.end))
        merged: list[Segment] = [segments[0]]
        for seg in segments[1:]:
            last = merged[-1]
            same_chord = seg.chord == last.chord
            touching = seg.start <= (last.end + tolerance_sec)
            if same_chord and touching:
                merged[-1] = Segment(start=last.start, end=max(last.end, seg.end), chord=last.chord)
            else:
                merged.append(seg)
        return merged

    def _make_display_segments(
        self,
        raw_segments: list[Segment],
        *,
        short_absorb: bool = True,
        boundary_refinement: bool = True,
    ) -> tuple[list[Segment], dict[str, int]]:
        min_display_duration = 0.5
        if not raw_segments:
            return [], {"removed_short_count": 0, "same_second_conflict_count": 0}

        def valid(chord: str) -> bool:
            c = (chord or "").strip().lower()
            return c not in {"", "-", "—", "n", "nc", "unknown"}

        working = [s for s in raw_segments if valid(s.chord) and s.end > s.start]
        working = self._merge_adjacent_segments(working, tolerance_sec=0.2)

        removed_short = 0
        if short_absorb:
            changed = True
            while changed and working:
                changed = False
                i = 0
                while i < len(working):
                    seg = working[i]
                    dur = seg.end - seg.start
                    if dur >= min_display_duration:
                        i += 1
                        continue

                    prev_idx = i - 1 if i > 0 else None
                    next_idx = i + 1 if i + 1 < len(working) else None
                    if prev_idx is None and next_idx is None:
                        i += 1
                        continue

                    def merge_pair(a: Segment, b: Segment) -> Segment:
                        keep = a.chord if (a.end - a.start) >= (b.end - b.start) else b.chord
                        return Segment(start=min(a.start, b.start), end=max(a.end, b.end), chord=keep)

                    target = None
                    if prev_idx is not None and working[prev_idx].chord == seg.chord:
                        target = prev_idx
                    elif next_idx is not None and working[next_idx].chord == seg.chord:
                        target = next_idx
                    elif prev_idx is not None and next_idx is not None:
                        target = prev_idx if (working[prev_idx].end - working[prev_idx].start) >= (working[next_idx].end - working[next_idx].start) else next_idx
                    else:
                        target = prev_idx if prev_idx is not None else next_idx

                    if target is None:
                        i += 1
                        continue

                    first = min(i, target)
                    second = max(i, target)
                    merged = merge_pair(working[i], working[target])
                    working[second] = merged
                    working.pop(first)
                    removed_short += 1
                    changed = True
                    i = max(0, first - 1)

                working = self._merge_adjacent_segments(working, tolerance_sec=0.2)

        # same-second conflict resolution
        by_second: dict[int, list[Segment]] = {}
        for seg in working:
            sec = int(seg.start)
            by_second.setdefault(sec, []).append(seg)

        same_second_conflicts = 0
        resolved: list[Segment] = []
        for sec in sorted(by_second.keys()):
            bucket = by_second[sec]
            distinct = {s.chord for s in bucket}
            if len(distinct) <= 1:
                resolved.extend(bucket)
                continue
            same_second_conflicts += 1
            keep = max(bucket, key=lambda s: (s.end - s.start))
            resolved.append(keep)

        resolved = sorted(resolved, key=lambda s: (s.start, s.end))
        resolved = self._merge_adjacent_segments(resolved, tolerance_sec=0.2)
        if not boundary_refinement:
            rounded = [
                Segment(start=round(seg.start, 3), end=round(seg.end, 3), chord=seg.chord) for seg in resolved
            ]
            return rounded, {
                "removed_short_count": removed_short,
                "same_second_conflict_count": same_second_conflicts,
            }

        # enforce monotonic and positive duration
        normalized: list[Segment] = []
        for seg in resolved:
            start = max(seg.start, normalized[-1].end if normalized else seg.start)
            end = max(seg.end, start + 0.001)
            normalized.append(Segment(start=round(start, 3), end=round(end, 3), chord=seg.chord))

        return normalized, {
            "removed_short_count": removed_short,
            "same_second_conflict_count": same_second_conflicts,
        }

    def _build_display_chord_text(self, display_segments: list[Segment], max_lines: int = 20) -> list[str]:
        if not display_segments:
            return []
        lines: list[str] = []
        for i in range(0, len(display_segments), 4):
            if len(lines) >= max_lines:
                break
            row = display_segments[i:i + 4]
            if not row:
                continue
            t = self._format_mmss(row[0].start)
            chord_cells = " | ".join(seg.chord for seg in row)
            lines.append(f"{t} | {chord_cells} |")
        return lines

    def _format_mmss(self, sec: float) -> str:
        total = max(0, int(sec))
        mm = total // 60
        ss = total % 60
        return f"{mm:02d}:{ss:02d}"

    def _make_simplified_segments(self, display_segments: list[Segment]) -> list[Segment]:
        if not display_segments:
            return []

        mapped: list[Segment] = []
        for seg in display_segments:
            mapped.append(
                Segment(
                    start=seg.start,
                    end=seg.end,
                    chord=self._simplify_display_chord(seg),
                )
            )
        return self._merge_adjacent_segments(mapped, tolerance_sec=0.2)

    def _simplify_display_chord(self, seg: Segment) -> str:
        base = seg.chord.split("/", 1)[0].strip()
        if not base:
            return seg.chord

        parsed = self._parse_chord(base)
        if parsed is None:
            return base
        root_pc, quality = parsed
        root = NOTE_NAMES[root_pc]
        duration = max(0.0, seg.end - seg.start)

        # Player timeline and reference chart both favor easy-to-play reference chords.
        if quality in {"minor", "m7", "minor_extension"}:
            return f"{root}m"
        if quality == "dominant7":
            if duration >= DISPLAY_KEEP_DOMINANT7_MIN_SEC:
                return f"{root}7"
            return root
        return root

    def _estimate_key(self, segments: list[Segment]) -> dict[str, Any]:
        if not segments:
            return {"key": "C", "top5": [], "confidence": 0.0}

        # Degree weights: emphasize I/IV/V/vi in major, i/III/VI/VII in minor.
        major_weights = {0: 3.0, 5: 2.6, 7: 3.0, 9: 2.4, 2: 1.6, 4: 1.3, 11: 0.8}
        minor_weights = {0: 3.0, 3: 2.3, 5: 1.7, 7: 2.4, 8: 2.2, 10: 2.0, 2: 1.0}

        all_scores: list[dict[str, Any]] = []
        for tonic_pc in range(12):
            all_scores.append(
                self._score_key_candidate(
                    tonic_pc=tonic_pc,
                    mode="major",
                    segments=segments,
                    degree_weights=major_weights,
                )
            )
            all_scores.append(
                self._score_key_candidate(
                    tonic_pc=tonic_pc,
                    mode="minor",
                    segments=segments,
                    degree_weights=minor_weights,
                )
            )

        ranked = sorted(all_scores, key=lambda x: x["score"], reverse=True)
        best = ranked[0]
        second = ranked[1] if len(ranked) > 1 else {"score": 0.0}
        confidence = 0.0
        if best["score"] > 0:
            confidence = round(max(0.0, (best["score"] - second["score"]) / best["score"]), 3)

        return {
            "key": best["key"],
            "top5": ranked[:5],
            "confidence": confidence,
        }

    def _score_key_candidate(
        self,
        tonic_pc: int,
        mode: str,
        segments: list[Segment],
        degree_weights: dict[int, float],
    ) -> dict[str, Any]:
        tonic_name = NOTE_NAMES[tonic_pc]
        key_name = tonic_name if mode == "major" else f"{tonic_name}m"
        score = 0.0
        support_by_chord: dict[str, float] = {}

        for seg in segments:
            dur = max(0.0, seg.end - seg.start)
            if dur <= 0:
                continue
            parsed = self._parse_chord(seg.chord)
            if parsed is None:
                continue
            root_pc, quality = parsed
            degree = (root_pc - tonic_pc) % 12
            base = degree_weights.get(degree, -1.2)

            # Quality-aware adjustment.
            quality_adj = self._quality_adjustment(mode=mode, degree=degree, quality=quality)
            seg_score = dur * (base + quality_adj)
            score += seg_score
            support_by_chord[seg.chord] = support_by_chord.get(seg.chord, 0.0) + seg_score

        top_support = sorted(support_by_chord.items(), key=lambda x: x[1], reverse=True)[:5]
        return {
            "key": key_name,
            "score": round(score, 3),
            "supports": [{"chord": chord, "contrib": round(val, 3)} for chord, val in top_support],
        }

    def _parse_chord(self, chord: str) -> tuple[int, str] | None:
        token = chord.split("/", 1)[0].strip()
        if not token:
            return None
        root = token[:2] if len(token) >= 2 and token[1] in {"#", "b"} else token[:1]
        if root not in NOTE_NAMES:
            return None
        root_pc = NOTE_NAMES.index(root)
        suffix = token[len(root):].lower()
        if "maj7" in suffix:
            quality = "maj7"
        elif "m7" in suffix:
            quality = "m7"
        elif suffix.startswith("m") and any(ext in suffix for ext in ("add", "sus", "9", "11", "13", "6")):
            quality = "minor_extension"
        elif suffix.startswith("m"):
            quality = "minor"
        elif "7" in suffix:
            quality = "dominant7"
        else:
            quality = "major"
        return root_pc, quality

    def _quality_adjustment(self, mode: str, degree: int, quality: str) -> float:
        # Strongly favor dominant 7 on V in major/minor.
        if quality == "dominant7":
            if degree == 7:
                return 1.2
            return 0.2

        if mode == "major":
            if degree in {0, 5, 7} and quality in {"major", "maj7"}:
                return 0.6
            if degree in {2, 4, 9} and quality in {"minor", "m7"}:
                return 0.45
            if degree == 11 and quality in {"minor", "m7"}:
                return 0.2
        else:
            if degree in {0, 3, 8} and quality in {"minor", "m7"}:
                return 0.55
            if degree in {5, 10} and quality in {"major", "maj7"}:
                return 0.35
            if degree == 7 and quality == "dominant7":
                return 0.6
        # slight penalty for mismatch
        if quality in {"major", "maj7"} and mode == "minor" and degree in {0, 3, 8}:
            return -0.25
        if quality in {"minor", "m7"} and mode == "major" and degree in {0, 5, 7}:
            return -0.25
        return 0.0

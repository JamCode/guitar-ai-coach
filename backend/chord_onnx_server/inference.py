from __future__ import annotations

import shutil
import subprocess
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import librosa
import numpy as np
import onnxruntime as ort

from chord_chart_postprocess import build_chord_chart_segments
from timing_compact_postprocess import build_timing_compact_segments
from timing_segment_postprocess import build_timing_priority_segments


NOTE_NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
TARGET_SR = 22050
HOP_LENGTH = 512
DEFAULT_N_BINS = 144
BINS_PER_OCTAVE = 24
CHUNK_DURATION_SEC = 20.0
CHUNK_SAMPLES = int(TARGET_SR * CHUNK_DURATION_SEC)
CHUNK_FRAMES = int(np.ceil(CHUNK_SAMPLES / HOP_LENGTH))


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

            decode_result = self._decode_outputs(out_map, frame_sec=HOP_LENGTH / TARGET_SR)
            decode_mode = decode_result["decode_mode"]
            raw_preview = decode_result.get("raw_preview", {})
            last_output_shapes = {k: list(v.shape) for k, v in out_map.items()}
            input_feature_shape = list(features.shape)
            model_input_shape = list(prepared.shape)

            chunk_start_sec = chunk_start_sample / TARGET_SR
            chunk_end_sec = chunk_end_sample / TARGET_SR
            local_segments: list[Segment] = decode_result["segments"]
            shifted: list[Segment] = []
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
                }
            )

        merged_segments = self._merge_adjacent_segments(all_segments, tolerance_sec=HOP_LENGTH / TARGET_SR)
        display_segments, display_stats = self._make_display_segments(merged_segments)
        no_absorb_display, _ = self._make_display_segments(
            merged_segments,
            short_absorb=False,
            boundary_refinement=False,
        )
        simplified_segments = self._make_simplified_segments(display_segments)
        no_absorb_simplified = self._make_simplified_segments(no_absorb_display)
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
        timing_stats_extra = timing_build["stats"]
        compact_stats_extra = compact_build["stats"]
        chart_proc_debug = dict(chart_res["debug"])
        chart_proc_debug["chordChartSourceSegmentCount"] = chart_proc_debug.pop(
            "rawSegmentCount", len(simplified_segments)
        )

        normal_display_payload = [s.__dict__ for s in simplified_segments]
        no_absorb_display_payload = [s.__dict__ for s in no_absorb_simplified]
        timing_display_payload = [s.__dict__ for s in timing_segments]
        timing_compact_payload = [s.__dict__ for s in compact_segments]
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
        root_idx = np.argmax(root_2d[:frame_count], axis=1)
        bass_idx = np.argmax(bass_2d[:frame_count], axis=1)
        chroma_prob = 1.0 / (1.0 + np.exp(-chroma_2d[:frame_count]))

        labels = [self._decode_frame_label(int(r), int(b), chroma_prob[i]) for i, (r, b) in enumerate(zip(root_idx, bass_idx))]
        segments = self._merge_labels(labels, frame_sec=frame_sec)
        return {
            "key": "C",
            "segments": segments,
            "decode_mode": "simple_root_bass_chroma",
        }

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

    def _decode_frame_label(self, root: int, bass: int, chroma_prob: np.ndarray) -> str:
        if root >= 12:
            return "N"

        intervals = {0}
        for abs_note in np.where(chroma_prob >= 0.5)[0]:
            intervals.add((int(abs_note) - root) % 12)

        suffix = self._classify_suffix(intervals)
        base = f"{NOTE_NAMES[root]}{suffix}"
        if bass < 12 and bass != root:
            return f"{base}/{NOTE_NAMES[bass]}"
        return base

    def _classify_suffix(self, intervals: set[int]) -> str:
        if {0, 4, 7}.issubset(intervals):
            if 11 in intervals:
                return "maj7"
            if 10 in intervals:
                return "7"
            if 2 in intervals:
                return "add9"
            return ""
        if {0, 3, 7}.issubset(intervals):
            if 10 in intervals:
                return "m7"
            if 2 in intervals:
                return "m9"
            return "m"
        if {0, 5, 7}.issubset(intervals):
            return "sus4"
        if {0, 2, 7}.issubset(intervals):
            return "sus2"
        if {0, 3, 6}.issubset(intervals):
            return "dim"
        if {0, 4, 8}.issubset(intervals):
            return "aug"
        if {0, 7}.issubset(intervals):
            return "5"
        return ""

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
                    chord=self._simplify_chord(seg.chord),
                )
            )
        return self._merge_adjacent_segments(mapped, tolerance_sec=0.2)

    def _simplify_chord(self, chord: str) -> str:
        base = chord.split("/", 1)[0].strip()
        if not base:
            return chord

        parsed = self._parse_chord(base)
        if parsed is None:
            return base
        root_pc, quality = parsed
        root = NOTE_NAMES[root_pc]

        # Player timeline and reference chart both favor easy-to-play reference chords.
        if quality in {"minor", "m7", "minor_extension"}:
            return f"{root}m"
        if quality == "dominant7":
            return f"{root}7"
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


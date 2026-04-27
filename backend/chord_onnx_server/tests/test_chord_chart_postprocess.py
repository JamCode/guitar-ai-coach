"""和弦谱后处理单元测试。"""
from __future__ import annotations

import unittest

from chord_chart_postprocess import build_chord_chart_segments, build_chord_chart_text


class ChordChartPostprocessTests(unittest.TestCase):
    def test_merge_adjacent_same_chord(self) -> None:
        raw = [
            {"start": 0.0, "end": 1.0, "chord": "A"},
            {"start": 1.0, "end": 2.0, "chord": "A"},
        ]
        r = build_chord_chart_segments(raw, estimated_key="A")
        segs = r["chordChartSegments"]
        self.assertEqual(len(segs), 1)
        self.assertEqual(segs[0]["chord"], "A")
        self.assertEqual(segs[0]["end"], 2.0)

    def test_short_segment_absorbed(self) -> None:
        raw = [
            {"start": 0.0, "end": 2.0, "chord": "A"},
            {"start": 2.0, "end": 2.3, "chord": "Bm", "confidence": 1.0},
            {"start": 2.3, "end": 5.0, "chord": "A"},
        ]
        r = build_chord_chart_segments(raw, estimated_key="A")
        d = r["debug"]
        self.assertGreater(d.get("absorbedShortChordCount", 0), 0)
        names = [s["chord"] for s in r["chordChartSegments"]]
        self.assertEqual(names.count("A"), len(names) if set(names) == {"A"} else 0)

    def test_a_major_short_out_of_key_figure(self) -> None:
        # 1.0s≤dur<1.4s：不走 B（<1.0），走 D：离调短和弦
        raw = [
            {"start": 0.0, "end": 2.0, "chord": "A"},
            {"start": 2.0, "end": 3.1, "chord": "F#:(1)", "confidence": 1.0},
            {"start": 3.1, "end": 6.0, "chord": "D"},
        ]
        r = build_chord_chart_segments(raw, estimated_key="A")
        d = r["debug"]
        self.assertGreater(d.get("absorbedOutOfKeyCount", 0), 0)
        for s in r["chordChartSegments"]:
            self.assertNotEqual(s["chord"], "F#:(1)")

    def test_low_confidence_short_absorbed(self) -> None:
        raw = [
            {"start": 0.0, "end": 2.0, "chord": "A"},
            {"start": 2.0, "end": 3.5, "chord": "D", "confidence": 0.2},
            {"start": 3.5, "end": 6.0, "chord": "A"},
        ]
        r = build_chord_chart_segments(raw, estimated_key="A")
        d = r["debug"]
        self.assertGreater(d.get("absorbedLowConfidenceCount", 0), 0)

    def test_chord_chart_text_four_chords_per_line(self) -> None:
        # 五段均在 C 大调主干内、各 1.2s，避免被 D 当离调短片段吸收
        line = ["C", "Dm", "Em", "F", "G"]
        text = build_chord_chart_text(line)
        lines = text.splitlines()
        self.assertEqual(lines[0], "C Dm Em F")
        self.assertEqual(lines[1], "G")
        segs = [{"start": i * 1.2, "end": (i + 1) * 1.2, "chord": c} for i, c in enumerate(line)]
        r = build_chord_chart_segments(segs, estimated_key="C")
        t2 = r["chordChartText"]
        self.assertIn("C Dm Em F", t2)
        self.assertIn("G", t2)


if __name__ == "__main__":
    unittest.main()

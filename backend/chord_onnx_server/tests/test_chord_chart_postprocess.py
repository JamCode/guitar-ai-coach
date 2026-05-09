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
            {"start": 2.0, "end": 3.4, "chord": "D", "confidence": 0.2},
            {"start": 3.4, "end": 6.0, "chord": "A"},
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

    def test_extended_chords_are_simplified_for_chart(self) -> None:
        raw = [
            {"start": 0.0, "end": 2.0, "chord": "Cadd9"},
            {"start": 2.0, "end": 4.0, "chord": "Dsus4"},
            {"start": 4.0, "end": 6.0, "chord": "Em9"},
            {"start": 6.0, "end": 8.0, "chord": "Gmaj7"},
        ]
        r = build_chord_chart_segments(raw, estimated_key="C")

        self.assertEqual([s["chord"] for s in r["chordChartSegments"]], ["C", "D", "Em", "G"])
        self.assertEqual(r["debug"]["simplifiedComplexChordCount"], 4)

    def test_short_complex_chord_is_absorbed(self) -> None:
        raw = [
            {"start": 0.0, "end": 2.0, "chord": "C"},
            {"start": 2.0, "end": 3.2, "chord": "Daug"},
            {"start": 3.7, "end": 6.0, "chord": "G"},
        ]
        r = build_chord_chart_segments(raw, estimated_key="C")

        self.assertNotIn("D", [s["chord"] for s in r["chordChartSegments"]])
        self.assertGreater(r["debug"]["absorbedComplexChordCount"], 0)

    def test_very_short_plain_chord_is_absorbed(self) -> None:
        raw = [
            {"start": 0.0, "end": 2.0, "chord": "C"},
            {"start": 2.0, "end": 2.3, "chord": "Dm"},
            {"start": 2.3, "end": 6.0, "chord": "C"},
        ]
        r = build_chord_chart_segments(raw, estimated_key="C")

        self.assertGreater(r["debug"]["absorbedShortChordCount"], 0)
        self.assertNotIn("Dm", [s["chord"] for s in r["chordChartSegments"]])

    def test_mid_length_plain_chord_is_kept(self) -> None:
        raw = [
            {"start": 0.0, "end": 2.0, "chord": "C"},
            {"start": 2.0, "end": 3.2, "chord": "Dm"},
            {"start": 3.2, "end": 6.0, "chord": "C"},
        ]
        r = build_chord_chart_segments(raw, estimated_key="C")

        self.assertEqual(r["debug"]["absorbedShortChordCount"], 0)
        self.assertIn("Dm", [s["chord"] for s in r["chordChartSegments"]])

    def test_absorption_disabled_keeps_short_segments(self) -> None:
        raw = [
            {"start": 0.0, "end": 2.0, "chord": "C"},
            {"start": 2.0, "end": 3.2, "chord": "Dm"},
            {"start": 3.2, "end": 6.0, "chord": "C"},
        ]
        r = build_chord_chart_segments(raw, estimated_key="C", enable_segment_absorption=False)
        d = r["debug"]
        self.assertEqual(d.get("absorbedShortChordCount", 0), 0)
        self.assertEqual(d.get("absorbedOutOfKeyCount", 0), 0)
        self.assertEqual(d.get("absorbedComplexChordCount", 0), 0)
        self.assertEqual(d.get("absorbedLowConfidenceCount", 0), 0)
        names = [s["chord"] for s in r["chordChartSegments"]]
        self.assertIn("Dm", names)


if __name__ == "__main__":
    unittest.main()

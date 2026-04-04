#!/usr/bin/env python3
"""
Validate quiz seed JSON for:
1) format integrity (4 options, unique correct answer, key consistency)
2) basic music-theory correctness of the standard answer fingering

Usage:
  python requirements/validate_quiz_seed.py
  python requirements/validate_quiz_seed.py requirements/和弦题库-100题种子.json
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple


DEFAULT_PATH = Path("requirements/和弦题库-100题种子.json")

# Standard tuning E A D G B E (low -> high), pitch classes
OPEN_STRING_PCS = [4, 9, 2, 7, 11, 4]

NOTE_TO_PC = {
    "C": 0,
    "B#": 0,
    "C#": 1,
    "Db": 1,
    "D": 2,
    "D#": 3,
    "Eb": 3,
    "E": 4,
    "Fb": 4,
    "E#": 5,
    "F": 5,
    "F#": 6,
    "Gb": 6,
    "G": 7,
    "G#": 8,
    "Ab": 8,
    "A": 9,
    "A#": 10,
    "Bb": 10,
    "B": 11,
    "Cb": 11,
}

QUALITY_INTERVALS = {
    "major": {"required": {0, 4}, "optional": {7}},
    "minor": {"required": {0, 3}, "optional": {7}},
    "dominant7": {"required": {0, 4, 10}, "optional": {7}},
    "maj7": {"required": {0, 4, 11}, "optional": {7}},
    "m7": {"required": {0, 3, 10}, "optional": {7}},
    "sus2": {"required": {0, 2}, "optional": {7}},
    "sus4": {"required": {0, 5}, "optional": {7}},
    "add9": {"required": {0, 4, 2}, "optional": {7}},
    "m7b5": {"required": {0, 3, 6, 10}, "optional": set()},
    "aug": {"required": {0, 4, 8}, "optional": set()},
}


def normalize_note(note: str) -> str:
    return note.replace("♭", "b").replace("♯", "#")


def note_to_pc(note: str) -> Optional[int]:
    return NOTE_TO_PC.get(normalize_note(note))


def parse_symbol(symbol: str) -> Optional[Dict[str, Optional[str]]]:
    m = re.match(r"^([A-G](?:#|b)?)([^/]*)?(?:/([A-G](?:#|b)?))?$", symbol)
    if not m:
        return None

    root = m.group(1)
    suffix = m.group(2) or ""
    slash = m.group(3)

    # Ordered by specificity
    if suffix == "":
        quality = "major"
    elif suffix == "m":
        quality = "minor"
    elif suffix == "7":
        quality = "dominant7"
    elif suffix == "maj7":
        quality = "maj7"
    elif suffix == "m7":
        quality = "m7"
    elif suffix == "sus2":
        quality = "sus2"
    elif suffix == "sus4":
        quality = "sus4"
    elif suffix == "add9":
        quality = "add9"
    elif suffix == "m7b5":
        quality = "m7b5"
    elif suffix == "aug":
        quality = "aug"
    else:
        return None

    return {"root": root, "quality": quality, "slash": slash}


def fingering_to_pcs(fingering: str) -> Optional[List[int]]:
    if len(fingering) != 6:
        return None
    pcs: List[int] = []
    for idx, ch in enumerate(fingering):
        if ch in ("x", "X"):
            continue
        if not ch.isdigit():
            return None
        fret = int(ch)
        pcs.append((OPEN_STRING_PCS[idx] + fret) % 12)
    return pcs if pcs else None


def expected_quality_label(parsed: Dict[str, Optional[str]]) -> str:
    if parsed["slash"] is not None:
        return "slash"
    return parsed["quality"] or "unknown"


def check_theory(symbol: str, quality_label: str, fingering: str) -> List[str]:
    errs: List[str] = []
    parsed = parse_symbol(symbol)
    if parsed is None:
        return [f"无法解析 chord_symbol: {symbol}"]

    root_pc = note_to_pc(parsed["root"] or "")
    if root_pc is None:
        return [f"无法识别根音: {parsed['root']}"]

    actual_quality = parsed["quality"] or "major"
    if actual_quality not in QUALITY_INTERVALS:
        return [f"不支持的和弦类型: {actual_quality}"]

    # chord_quality field consistency
    expected_label = expected_quality_label(parsed)
    if quality_label != expected_label:
        errs.append(f"chord_quality 不匹配: 字段={quality_label}, 由符号推断={expected_label}")

    played = fingering_to_pcs(fingering)
    if played is None:
        return errs + [f"无法解析 fingering: {fingering}"]

    played_set = set(played)
    required_intervals = QUALITY_INTERVALS[actual_quality]["required"]
    optional_intervals = QUALITY_INTERVALS[actual_quality]["optional"]
    required_pcs = {(root_pc + x) % 12 for x in required_intervals}
    allowed_pcs = {(root_pc + x) % 12 for x in required_intervals | optional_intervals}

    missing = required_pcs - played_set
    if missing:
        errs.append(f"缺少必要和弦音: {sorted(missing)}")

    out_of_set = played_set - allowed_pcs
    if out_of_set:
        errs.append(f"出现非和弦音: {sorted(out_of_set)}")

    slash = parsed["slash"]
    if slash:
        slash_pc = note_to_pc(slash)
        if slash_pc is None:
            errs.append(f"无法识别 slash 低音: {slash}")
        else:
            bass_pc = played[0]  # lowest played string in EADGBE order
            if bass_pc != slash_pc:
                errs.append(f"slash 低音不匹配: 期望={slash_pc}, 实际={bass_pc}")

    return errs


def validate(path: Path) -> Tuple[List[str], Dict[str, int]]:
    errors: List[str] = []
    stats = {"total": 0, "beginner": 0, "intermediate": 0, "advanced": 0}

    data = json.loads(path.read_text(encoding="utf-8"))
    questions = data.get("questions")
    if not isinstance(questions, list):
        return ["questions 字段不存在或不是数组"], stats

    seen_ids: Set[str] = set()
    for i, q in enumerate(questions):
        loc = f"[{i}]"
        stats["total"] += 1

        qid = q.get("id")
        if not isinstance(qid, str) or not qid:
            errors.append(f"{loc}: 缺少有效 id")
            continue
        if qid in seen_ids:
            errors.append(f"{loc}({qid}): 重复 id")
        seen_ids.add(qid)

        difficulty = q.get("difficulty")
        if difficulty not in ("beginner", "intermediate", "advanced"):
            errors.append(f"{qid}: difficulty 非法: {difficulty}")
        else:
            stats[difficulty] += 1

        chord_symbol = q.get("chord_symbol")
        chord_quality = q.get("chord_quality")
        correct_key = q.get("correct_option_key")
        options = q.get("options")

        if not isinstance(chord_symbol, str) or not chord_symbol:
            errors.append(f"{qid}: chord_symbol 缺失")
        if not isinstance(chord_quality, str) or not chord_quality:
            errors.append(f"{qid}: chord_quality 缺失")
        if correct_key not in ("A", "B", "C", "D"):
            errors.append(f"{qid}: correct_option_key 非法: {correct_key}")

        if not isinstance(options, list) or len(options) != 4:
            errors.append(f"{qid}: options 必须是4项数组")
            continue

        keys = []
        correct_count = 0
        correct_fingering = None
        fingering_set = set()

        for opt in options:
            k = opt.get("key")
            f = opt.get("fingering")
            is_correct = opt.get("is_correct")
            keys.append(k)

            if k not in ("A", "B", "C", "D"):
                errors.append(f"{qid}: option key 非法: {k}")

            if not isinstance(f, str):
                errors.append(f"{qid}: option({k}) fingering 非字符串")
            else:
                if f in fingering_set:
                    errors.append(f"{qid}: options 存在重复 fingering: {f}")
                fingering_set.add(f)

            if is_correct is True:
                correct_count += 1
                correct_fingering = f

        if set(keys) != {"A", "B", "C", "D"}:
            errors.append(f"{qid}: option key 需恰好包含 A/B/C/D")

        if correct_count != 1:
            errors.append(f"{qid}: 必须且只能有一个 is_correct=true，当前={correct_count}")

        key_map = {opt["key"]: opt for opt in options if isinstance(opt, dict) and "key" in opt}
        marked = key_map.get(correct_key)
        if not marked or marked.get("is_correct") is not True:
            errors.append(f"{qid}: correct_option_key 与 is_correct 标记不一致")

        if isinstance(chord_symbol, str) and isinstance(chord_quality, str) and isinstance(correct_fingering, str):
            theory_errs = check_theory(chord_symbol, chord_quality, correct_fingering)
            for te in theory_errs:
                errors.append(f"{qid}: {te}")

    return errors, stats


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PATH
    if not path.exists():
        print(f"[ERROR] 文件不存在: {path}")
        return 2

    errors, stats = validate(path)
    print(f"Checked file: {path}")
    print(
        f"Questions: total={stats['total']}, beginner={stats['beginner']}, "
        f"intermediate={stats['intermediate']}, advanced={stats['advanced']}"
    )
    if errors:
        print(f"\n[FAILED] Found {len(errors)} issue(s):")
        for e in errors:
            print(f"- {e}")
        return 1

    print("\n[OK] All format and theory checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


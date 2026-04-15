#!/usr/bin/env python3
"""
生成练耳一期题库种子（A/B）与 C 模式组卷蓝图。

默认输出:
  requirements/练耳题库-一期种子.json

用法:
  python requirements/generate_ear_seed_v1.py
  python requirements/generate_ear_seed_v1.py --out requirements/练耳题库-一期种子.json
"""

from __future__ import annotations

import argparse
import json
import random
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List


ROOTS_12 = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

QUALITY_POOL = [
    {"id": "major", "label_zh": "大三", "suffix": ""},
    {"id": "minor", "label_zh": "小三", "suffix": "m"},
    {"id": "dominant7", "label_zh": "属七", "suffix": "7"},
]

B_PROGRESSIONS = [
    {"id": "P01", "roman": "I-V-vi-IV", "name_zh": "流行主副歌常见进行"},
    {"id": "P02", "roman": "vi-IV-I-V", "name_zh": "反向流行进行"},
    {"id": "P03", "roman": "I-vi-IV-V", "name_zh": "经典 50s 进行"},
    {"id": "P04", "roman": "ii-V-I", "name_zh": "功能回归进行"},
    {"id": "P05", "roman": "I-IV-V", "name_zh": "基础三和弦进行"},
]

B_VARIANTS = [
    {"id": "std", "tempo_bpm": 78, "hint": "标准节奏型"},
    {"id": "alt", "tempo_bpm": 92, "hint": "换起始位/节奏型"},
]

B_LEVEL_BY_PROGRESSION = {
    "P01": "B2",
    "P02": "B2",
    "P03": "B2",
    "P04": "B3",
    "P05": "B1",
}


@dataclass
class BuildOptions:
    out: Path
    seed: int


def _choice_key(i: int) -> str:
    return ["A", "B", "C", "D"][i]


def _build_a_questions(rng: random.Random) -> List[Dict]:
    questions: List[Dict] = []
    q_index = 1
    for root in ROOTS_12:
        for quality in QUALITY_POOL:
            symbol = f"{root}{quality['suffix']}"
            option_labels = [x["label_zh"] for x in QUALITY_POOL]
            # 补齐到四选一：加入一个固定干扰项，降低纯猜中率
            option_labels.append("maj7")
            rng.shuffle(option_labels)
            correct_key = _choice_key(option_labels.index(quality["label_zh"]))
            options = [
                {
                    "key": _choice_key(i),
                    "label": label,
                    "is_correct": label == quality["label_zh"],
                }
                for i, label in enumerate(option_labels)
            ]
            questions.append(
                {
                    "id": f"EA{q_index:04d}",
                    "mode": "A",
                    "question_type": "single_chord_quality",
                    "difficulty": "A1",
                    "root": root,
                    "chord_symbol": symbol,
                    "target_quality": quality["id"],
                    "prompt_zh": f"听音后判断和弦性质：{root} ?",
                    "audio_ref": {
                        "pack": "ear_v1_acoustic",
                        "key": f"a/{root}/{quality['id']}.mp3",
                        "tempo_bpm": 72,
                        "duration_sec": 2.8,
                    },
                    "correct_option_key": correct_key,
                    "options": options,
                    "tags": ["ear", "mvp", "A", quality["id"], root],
                }
            )
            q_index += 1
    return questions


def _build_b_questions(rng: random.Random) -> List[Dict]:
    questions: List[Dict] = []
    q_index = 1
    roman_pool = [x["roman"] for x in B_PROGRESSIONS]

    for key_name in ROOTS_12:
        for prog in B_PROGRESSIONS:
            for variant in B_VARIANTS:
                distractors = [x for x in roman_pool if x != prog["roman"]]
                rng.shuffle(distractors)
                opts = [prog["roman"]] + distractors[:3]
                rng.shuffle(opts)
                correct_key = _choice_key(opts.index(prog["roman"]))
                options = [
                    {"key": _choice_key(i), "label": opt, "is_correct": opt == prog["roman"]}
                    for i, opt in enumerate(opts)
                ]
                questions.append(
                    {
                        "id": f"EB{q_index:04d}",
                        "mode": "B",
                        "question_type": "progression_recognition",
                        "difficulty": B_LEVEL_BY_PROGRESSION[prog["id"]],
                        "music_key": key_name,
                        "progression_id": prog["id"],
                        "progression_roman": prog["roman"],
                        "variant_id": variant["id"],
                        "prompt_zh": "听和弦进行，选择最符合的一项",
                        "audio_ref": {
                            "pack": "ear_v1_progression",
                            "key": f"b/{prog['id']}/{key_name}/{variant['id']}.mp3",
                            "tempo_bpm": variant["tempo_bpm"],
                            "duration_sec": 6.0,
                        },
                        "correct_option_key": correct_key,
                        "options": options,
                        "tags": ["ear", "mvp", "B", prog["id"], key_name, variant["id"]],
                        "hint_zh": prog["name_zh"],
                    }
                )
                q_index += 1
    return questions


def build_seed(opts: BuildOptions) -> Dict:
    rng = random.Random(opts.seed)
    a_questions = _build_a_questions(rng)
    b_questions = _build_b_questions(rng)

    payload = {
        "version": "ear_seed_v1",
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "generator": {
            "script": "requirements/generate_ear_seed_v1.py",
            "seed": opts.seed,
            "strategy": "offline-prebuilt-no-llm",
        },
        "notes": [
            "本期不接入大模型，题库离线预生成。",
            "A: 单和弦听辨（大三/小三/属七）；B: 常见进行听辨。",
            "C 模式不单独建题，复用 A/B 题池并按规则组卷。",
        ],
        "banks": {
            "A": a_questions,
            "B": b_questions,
        },
        "daily_plan_blueprint": {
            "mode": "C",
            "daily_question_count": 10,
            "composition": [
                {"source": "mistake_book", "count": 6},
                {"source": "weak_dimension", "count": 2},
                {"source": "retention", "count": 2},
            ],
            "priority_formula": "0.5*recency + 0.3*error_count + 0.2*low_accuracy_tag",
        },
        "stats": {
            "A_total": len(a_questions),
            "B_total": len(b_questions),
            "total": len(a_questions) + len(b_questions),
        },
    }
    return payload


def parse_args() -> BuildOptions:
    parser = argparse.ArgumentParser(description="Generate ear training seed v1")
    parser.add_argument(
        "--out",
        default="requirements/练耳题库-一期种子.json",
        help="Output JSON path",
    )
    parser.add_argument("--seed", type=int, default=20260331, help="Random seed")
    args = parser.parse_args()
    return BuildOptions(out=Path(args.out), seed=args.seed)


def main() -> int:
    opts = parse_args()
    payload = build_seed(opts)
    opts.out.parent.mkdir(parents=True, exist_ok=True)
    opts.out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    stats = payload["stats"]
    print(f"[OK] wrote seed file: {opts.out}")
    print(
        f"[STATS] A={stats['A_total']}, B={stats['B_total']}, total={stats['total']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


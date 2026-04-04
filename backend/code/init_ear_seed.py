#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
初始化练耳题库种子数据。

用法:
  python backend/code/init_ear_seed.py
  python backend/code/init_ear_seed.py --seed requirements/练耳题库-一期种子.json --version ear_seed_v1
"""

from __future__ import annotations

import argparse
import os
import sys

from ear_db import ensure_ear_schema, import_ear_seed


def parse_args():
    parser = argparse.ArgumentParser(description="Import ear seed JSON into MySQL")
    parser.add_argument(
        "--seed",
        default=os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "requirements", "练耳题库-一期种子.json")
        ),
        help="Ear seed json file path",
    )
    parser.add_argument("--status", default="active", help="Question status")
    parser.add_argument("--version", default="", help="Override version")
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        ensure_ear_schema()
        out = import_ear_seed(
            args.seed,
            version=(args.version.strip() or None),
            status=(args.status.strip() or "active"),
        )
    except Exception as e:  # pragma: no cover
        print(f"[ERROR] init ear seed failed: {e}")
        return 1
    print(f"[OK] ear seed imported: saved={out.get('saved')} version={out.get('version')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())


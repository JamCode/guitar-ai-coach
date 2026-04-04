# -*- coding: utf-8 -*-
"""和弦变调：纯乐理推算，不调用 AI。假定参考调为 C 大调记谱。"""

import re

# 页面 12 个调（半音阶主音）
TWELVE_KEYS = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

REFERENCE_KEY = "C"

# 主音 -> 音级 (0=C)
_KEY_PC = {
    "C": 0,
    "B#": 0,
    "C#": 1,
    "Db": 1,
    "D": 2,
    "D#": 3,
    "Eb": 3,
    "E": 4,
    "Fb": 4,
    "F": 5,
    "E#": 5,
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

_SHARP_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
_FLAT_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

# 输出时倾向用降号写的调
_PREFER_FLATS = {
    "C": False,
    "Db": True,
    "D": False,
    "Eb": True,
    "E": False,
    "F": True,
    "Gb": True,
    "G": False,
    "Ab": True,
    "A": False,
    "Bb": True,
    "B": False,
}


def normalize_key(name):
    if not name or not isinstance(name, str):
        return REFERENCE_KEY
    k = name.strip()
    if k in _KEY_PC:
        return k
    low = k.lower()
    for canon in TWELVE_KEYS:
        if canon.lower() == low:
            return canon
    return REFERENCE_KEY


def key_pitch_class(key):
    return _KEY_PC.get(normalize_key(key), 0)


def prefer_flats_for_key(key):
    return _PREFER_FLATS.get(normalize_key(key), False)


def semitone_delta(from_key, to_key):
    a = key_pitch_class(from_key)
    b = key_pitch_class(to_key)
    return (b - a) % 12


def note_to_pc(note):
    m = re.match(r"^([A-G])([#b]?)$", note.strip())
    if not m:
        return None
    name = m.group(1) + m.group(2)
    return _KEY_PC.get(name)


def pc_to_note(pc, prefer_flats):
    pc = pc % 12
    names = _FLAT_NAMES if prefer_flats else _SHARP_NAMES
    return names[pc]


def transpose_note(note, semitones, prefer_flats):
    pc = note_to_pc(note)
    if pc is None:
        return note
    return pc_to_note(pc + semitones, prefer_flats)


_CHORD_HEAD = re.compile(r"^([A-G])([#b]?)(.*)$")


def transpose_chord_symbol(chord, semitones, prefer_flats):
    chord = chord.strip()
    if not chord:
        return chord
    bass = None
    if "/" in chord:
        main, bass = chord.split("/", 1)
        main = main.strip()
        bass = bass.strip()
    else:
        main = chord

    m = _CHORD_HEAD.match(main)
    if not m:
        return chord
    root = m.group(1) + m.group(2)
    quality = m.group(3)
    new_root = transpose_note(root, semitones, prefer_flats)
    out = new_root + quality
    if bass:
        mb = _CHORD_HEAD.match(bass)
        if mb:
            broot = mb.group(1) + mb.group(2)
            out += "/" + transpose_note(broot, semitones, prefer_flats)
        else:
            out += "/" + bass
    return out


def transpose_progression_line(line, semitones, prefer_flats):
    parts = [p.strip() for p in line.split(" - ")]
    return " - ".join(
        transpose_chord_symbol(p, semitones, prefer_flats) for p in parts if p
    )


def transpose_lines(lines, from_key, to_key):
    fk = normalize_key(from_key)
    tk = normalize_key(to_key)
    delta = semitone_delta(fk, tk)
    pf = prefer_flats_for_key(tk)
    out = []
    for line in lines:
        if isinstance(line, str) and line.strip():
            out.append(transpose_progression_line(line, delta, pf))
        else:
            out.append(line)
    return out

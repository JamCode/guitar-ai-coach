/**
 * 练耳 B 题：罗马级数字符串（与 seed 中 progression_roman 一致）→ 调内和弦符号。
 * 供 POST /chords/explain 与 playChordFromFrets，与「和弦进行」页合成试听同源。
 */

const KEY_PC: Record<string, number> = {
  C: 0,
  'C#': 1,
  Db: 1,
  D: 2,
  'D#': 3,
  Eb: 3,
  E: 4,
  F: 5,
  'F#': 6,
  Gb: 6,
  G: 7,
  'G#': 8,
  Ab: 8,
  A: 9,
  'A#': 10,
  Bb: 10,
  B: 11,
}

const PREFER_FLATS_FOR_KEY: Record<string, boolean> = {
  Db: true,
  Eb: true,
  F: true,
  Gb: true,
  Ab: true,
  Bb: true,
}

const SHARP_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
const FLAT_NAMES = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B']

const MAJOR_SCALE_STEPS = [0, 2, 4, 5, 7, 9, 11]

/** 与 generate_ear_seed_v1.py 中 B 进行片段一致 */
const ROMAN_TOKEN: Record<string, { deg: number; suffix: string }> = {
  I: { deg: 1, suffix: '' },
  ii: { deg: 2, suffix: 'm' },
  iii: { deg: 3, suffix: 'm' },
  IV: { deg: 4, suffix: '' },
  V: { deg: 5, suffix: '' },
  vi: { deg: 6, suffix: 'm' },
}

export function normalizeEarKey(name: string): string {
  const t = name.trim()
  if (KEY_PC[t] !== undefined) return t
  const low = t.toLowerCase()
  for (const k of Object.keys(KEY_PC)) {
    if (k.toLowerCase() === low) return k
  }
  return 'C'
}

export function earRomanProgressionToSymbols(progressionRoman: string, musicKey: string): string[] {
  const key = normalizeEarKey(musicKey)
  const kpc = KEY_PC[key] ?? 0
  const preferFlats = PREFER_FLATS_FOR_KEY[key] === true
  const names = preferFlats ? FLAT_NAMES : SHARP_NAMES
  const parts = progressionRoman
    .split('-')
    .map((p) => p.trim())
    .filter(Boolean)
  const out: string[] = []
  for (const raw of parts) {
    const meta = ROMAN_TOKEN[raw]
    if (!meta) {
      throw new Error(`不支持的级数：${raw}`)
    }
    const step = MAJOR_SCALE_STEPS[meta.deg - 1]
    if (step === undefined) {
      throw new Error(`级数越界：${meta.deg}`)
    }
    const pc = (kpc + step) % 12
    const root = names[pc] ?? SHARP_NAMES[pc]
    out.push(`${root}${meta.suffix}`)
  }
  return out
}

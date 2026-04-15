/**
 * 指法数组校验（无音频依赖，可随主包加载）。
 * 与后端约定：6 弦→1 弦，-1 闷音、0 空弦、>0 品格。
 */
export const OPEN_STRING_MIDI = [40, 45, 50, 55, 59, 64] as const

export function coerceFretCell(v: unknown): number {
  if (v === null || v === undefined) return -1
  if (typeof v === 'number' && Number.isFinite(v)) {
    if (v === -1) return -1
    if (v === 0) return 0
    if (v > 0 && v <= 24) return Math.trunc(v)
    return -1
  }
  if (typeof v === 'string') {
    const s = v.trim().toLowerCase()
    if (s === '' || s === 'x' || s === 'm' || s === 'mute') return -1
    const n = parseInt(s, 10)
    if (n === 0) return 0
    if (n > 0 && n <= 24) return n
  }
  return -1
}

export function canPlayChordFrets(frets: readonly number[]): boolean {
  return frets.length === 6 && frets.some((f) => coerceFretCell(f) >= 0)
}

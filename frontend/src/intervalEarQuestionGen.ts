/**
 * 音程识别：基于 12 平均律的参数化出题（无题库）。
 * 每次根据允许的半音集合、MIDI 音域与乐理近邻规则生成一题。
 */

export type TritoneLabelMode = 'aug4' | 'dim5'

export type IntervalEarQuestionParams = {
  /** 本题允许出现的半音跨度（含正确答案与干扰项），元素为 0..12 的整数且互异，长度至少 4 */
  allowedSimpleSemitones: readonly number[]
  /** 低音音符 MIDI（含） */
  lowerMidiMin: number
  /** 低音音符 MIDI（含） */
  lowerMidiMax: number
  /** 高音音符 MIDI 上限（含）；用于截断低音可选范围 */
  upperMidiMax?: number
  /** 三全音（6 半音）在 UI 上的规范名称 */
  tritoneLabel: TritoneLabelMode
  /** 返回 [0,1) 的伪随机数；可注入 seed RNG 以便测试 */
  random: () => number
  /** 减轻「凭绝对音高猜题」：若提供，则尽量使本题的 lower 与上一题相差至少若干半音 */
  antiAbsolutePitch?: { previousLowerMidi: number; minSemitoneDelta: number }
}

export type IntervalEarOption = {
  /** 稳定键，如 "M3" */
  id: string
  labelZh: string
  simpleSemitones: number
}

export type IntervalEarQuestion = {
  lowerMidi: number
  upperMidi: number
  /** 与 lower/upper 一致：upper - lower，落在 0..12 */
  simpleSemitones: number
  /** 四选一，顺序已随机洗牌 */
  options: IntervalEarOption[]
  /** options 中正确答案的下标 */
  correctIndex: number
}

const MAJOR_MINOR_PAIRS: ReadonlyArray<readonly [number, number]> = [
  [1, 2],
  [3, 4],
  [8, 9],
  [10, 11],
]

function assertPool(pool: readonly number[]): number[] {
  const uniq = Array.from(new Set(pool.map((n) => Math.trunc(n))))
  for (const n of uniq) {
    if (!Number.isFinite(n) || n < 0 || n > 12) {
      throw new Error(`allowedSimpleSemitones 越界：${n}（仅支持 0..12 的简单音程）`)
    }
  }
  if (uniq.length < 4) {
    throw new Error('allowedSimpleSemitones 至少需要 4 个不同半音，才能构成四选一')
  }
  return uniq
}

function semitoneToMeta(d: number, tritoneLabel: TritoneLabelMode): { id: string; labelZh: string } {
  switch (d) {
    case 0:
      return { id: 'P1', labelZh: '纯一度' }
    case 1:
      return { id: 'm2', labelZh: '小二度' }
    case 2:
      return { id: 'M2', labelZh: '大二度' }
    case 3:
      return { id: 'm3', labelZh: '小三度' }
    case 4:
      return { id: 'M3', labelZh: '大三度' }
    case 5:
      return { id: 'P4', labelZh: '纯四度' }
    case 6:
      return tritoneLabel === 'dim5'
        ? { id: 'd5', labelZh: '减五度' }
        : { id: 'A4', labelZh: '增四度' }
    case 7:
      return { id: 'P5', labelZh: '纯五度' }
    case 8:
      return { id: 'm6', labelZh: '小六度' }
    case 9:
      return { id: 'M6', labelZh: '大六度' }
    case 10:
      return { id: 'm7', labelZh: '小七度' }
    case 11:
      return { id: 'M7', labelZh: '大七度' }
    case 12:
      return { id: 'P8', labelZh: '纯八度' }
    default:
      throw new Error(`不支持的半音跨度：${d}`)
  }
}

function inversionBonus(a: number, b: number): number {
  if (a <= 0 || a >= 12 || b <= 0 || b >= 12) return 0
  return a + b === 12 ? 92 : 0
}

function majorMinorNeighborBonus(a: number, b: number): number {
  for (const [x, y] of MAJOR_MINOR_PAIRS) {
    if ((a === x && b === y) || (a === y && b === x)) return 88
  }
  return 0
}

function chromaticBonus(a: number, b: number): number {
  const u = Math.abs(a - b)
  if (u === 1) return 100
  if (u === 2) return 78
  return 0
}

function perfectFourthFifthBonus(a: number, b: number): number {
  const s = new Set([a, b])
  return s.has(5) && s.has(7) ? 72 : 0
}

function distractorScore(correct: number, cand: number): number {
  return (
    chromaticBonus(correct, cand) +
    inversionBonus(correct, cand) +
    majorMinorNeighborBonus(correct, cand) +
    perfectFourthFifthBonus(correct, cand)
  )
}

function shuffleInPlace<T>(arr: T[], random: () => number): void {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1))
    const t = arr[i]
    arr[i] = arr[j]!
    arr[j] = t!
  }
}

function pickLowerMidi(
  d: number,
  lowerMidiMin: number,
  lowerMidiMax: number,
  upperMidiMax: number,
  random: () => number,
  anti?: IntervalEarQuestionParams['antiAbsolutePitch'],
): number {
  const hi = Math.min(lowerMidiMax, upperMidiMax - d)
  if (hi < lowerMidiMin) {
    throw new Error('音域与半音跨度不兼容：在给定 upperMidiMax 下无法放置该音程')
  }
  const span = hi - lowerMidiMin + 1
  const maxTry = anti ? 48 : 1
  for (let t = 0; t < maxTry; t++) {
    const k = Math.floor(random() * span)
    const m = lowerMidiMin + k
    if (!anti) return m
    if (Math.abs(m - anti.previousLowerMidi) >= anti.minSemitoneDelta) return m
  }
  const k = Math.floor(random() * span)
  return lowerMidiMin + k
}

/**
 * 可复现 RNG（32-bit LCG）。用于测试或需要稳定序列的场景。
 */
export function createDeterministicRng(seed: number): () => number {
  let s = seed >>> 0
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0
    return s / 2 ** 32
  }
}

/**
 * 生成一题：先按乐理相关度挑选目标音程与三个干扰项，再随机低音与选项顺序。
 */
export function generateIntervalEarQuestion(params: IntervalEarQuestionParams): IntervalEarQuestion {
  const pool = assertPool(params.allowedSimpleSemitones)
  const rnd = params.random
  const upperMax = params.upperMidiMax ?? 127

  const correctSemitones = pool[Math.floor(rnd() * pool.length)]!
  const wrongPool = pool.filter((d) => d !== correctSemitones)
  const scored = wrongPool.map((d) => ({ d, s: distractorScore(correctSemitones, d) }))
  scored.sort((a, b) => b.s - a.s || (rnd() < 0.5 ? 1 : -1))

  const chosen = new Set<number>()
  for (const row of scored) {
    if (chosen.size >= 3) break
    chosen.add(row.d)
  }
  for (const d of wrongPool) {
    if (chosen.size >= 3) break
    chosen.add(d)
  }

  const wrong = Array.from(chosen).slice(0, 3)
  if (wrong.length !== 3) {
    throw new Error('内部错误：干扰项数量不足')
  }

  const options: IntervalEarOption[] = [correctSemitones, ...wrong].map((d) => {
    const meta = semitoneToMeta(d, params.tritoneLabel)
    return { id: meta.id, labelZh: meta.labelZh, simpleSemitones: d }
  })
  shuffleInPlace(options, rnd)

  const correctIndex = options.findIndex((o) => o.simpleSemitones === correctSemitones)
  if (correctIndex < 0) {
    throw new Error('内部错误：正确答案丢失')
  }

  const lowerMidi = pickLowerMidi(
    correctSemitones,
    params.lowerMidiMin,
    params.lowerMidiMax,
    upperMax,
    rnd,
    params.antiAbsolutePitch,
  )
  const upperMidi = lowerMidi + correctSemitones

  return {
    lowerMidi,
    upperMidi,
    simpleSemitones: correctSemitones,
    options,
    correctIndex,
  }
}

export function intervalMetaForSemitone(d: number, tritoneLabel: TritoneLabelMode): { id: string; labelZh: string } {
  return semitoneToMeta(d, tritoneLabel)
}

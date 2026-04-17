import { describe, expect, it } from 'vitest'
import {
  createDeterministicRng,
  generateIntervalEarQuestion,
  generateIntervalEarQuestionByDifficulty,
  intervalMetaForSemitone,
  resolveIntervalEarDifficultyPreset,
} from './intervalEarQuestionGen'

const DEFAULT_POOL = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] as const

describe('generateIntervalEarQuestionByDifficulty', () => {
  it('初级：四选项半音均落在初级池内且带回难度', () => {
    const preset = resolveIntervalEarDifficultyPreset('初级')
    const q = generateIntervalEarQuestionByDifficulty({
      difficulty: '初级',
      random: createDeterministicRng(20260417),
    })
    expect(q.difficulty).toBe('初级')
    for (const o of q.options) {
      expect(preset.allowedSimpleSemitones).toContain(o.simpleSemitones)
    }
    expect(q.upperMidi - q.lowerMidi).toBe(q.simpleSemitones)
    expect(q.lowerMidi).toBeGreaterThanOrEqual(preset.lowerMidiMin)
    expect(q.upperMidi).toBeLessThanOrEqual(preset.upperMidiMax)
  })

  it('中级预设不含三全音（6 半音）', () => {
    const p = resolveIntervalEarDifficultyPreset('中级')
    expect(p.allowedSimpleSemitones).not.toContain(6)
  })

  it('高级预设含三全音', () => {
    const p = resolveIntervalEarDifficultyPreset('高级')
    expect(p.allowedSimpleSemitones).toContain(6)
  })
})

describe('generateIntervalEarQuestion', () => {
  it('生成四互异半音选项且仅一个与题目一致', () => {
    const q = generateIntervalEarQuestion({
      allowedSimpleSemitones: DEFAULT_POOL,
      lowerMidiMin: 55,
      lowerMidiMax: 72,
      upperMidiMax: 84,
      tritoneLabel: 'aug4',
      random: createDeterministicRng(20260417),
    })
    expect(q.difficulty).toBeUndefined()
    expect(q.options).toHaveLength(4)
    const sems = q.options.map((o) => o.simpleSemitones)
    expect(new Set(sems).size).toBe(4)
    expect(q.upperMidi - q.lowerMidi).toBe(q.simpleSemitones)
    expect(q.options[q.correctIndex]!.simpleSemitones).toBe(q.simpleSemitones)
    expect(q.lowerMidi).toBeGreaterThanOrEqual(55)
    expect(q.upperMidi).toBeLessThanOrEqual(84)
  })

  it('allowedSimpleSemitones 少于 4 时抛错', () => {
    expect(() =>
      generateIntervalEarQuestion({
        allowedSimpleSemitones: [3, 4, 5],
        lowerMidiMin: 60,
        lowerMidiMax: 60,
        tritoneLabel: 'dim5',
        random: Math.random,
      }),
    ).toThrow(/至少需要 4 个/)
  })

  it('音域无法容纳目标音程时抛错', () => {
    expect(() =>
      generateIntervalEarQuestion({
        allowedSimpleSemitones: [12, 11, 10, 9],
        lowerMidiMin: 80,
        lowerMidiMax: 80,
        upperMidiMax: 80,
        tritoneLabel: 'aug4',
        random: createDeterministicRng(1),
      }),
    ).toThrow(/音域/)
  })
})

describe('intervalMetaForSemitone', () => {
  it('三全音可按参数命名', () => {
    expect(intervalMetaForSemitone(6, 'aug4').labelZh).toBe('增四度')
    expect(intervalMetaForSemitone(6, 'dim5').labelZh).toBe('减五度')
  })
})

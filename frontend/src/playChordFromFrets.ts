/**
 * 按指法 frets 合成和弦试听（重模块：Tone + 多段 MP3）。
 * 由 `chordAudioLazy.ts` 动态 import，避免拖慢首屏。
 * 优先木吉他采样（minify 采样集以减小体积）；失败时 Karplus–Strong。
 */
import { Frequency, getContext, now, start } from 'tone'
import { GuitarAcousticSlimSampler } from './guitarAcousticSlimSampler'
import { OPEN_STRING_MIDI, canPlayChordFrets, coerceFretCell } from './chordFretUtils'

function midiToFreq(midi: number): number {
  return 440 * 2 ** ((midi - 69) / 12)
}

let context: AudioContext | null = null
let outputGain: GainNode | null = null
let toneGuitar: GuitarAcousticSlimSampler | null = null
let toneGuitarInflight: Promise<GuitarAcousticSlimSampler | null> | null = null
const cleanupFns: Array<() => void> = []

function stopAll(): void {
  for (const fn of cleanupFns) {
    try {
      fn()
    } catch {
      /* ignore */
    }
  }
  cleanupFns.length = 0
}

function registerCleanup(nodes: AudioNode[], src?: AudioBufferSourceNode): void {
  cleanupFns.push(() => {
    if (src) {
      try {
        src.stop()
      } catch {
        /* already stopped */
      }
    }
    for (const n of nodes) {
      try {
        n.disconnect()
      } catch {
        /* ignore */
      }
    }
  })
}

function minKarplusPeriod(ctx: AudioContext): number {
  return 256 / ctx.sampleRate
}

function startKarplusString(
  ctx: AudioContext,
  freq: number,
  tStart: number,
  dest: AudioNode,
  peak: number,
  arpeggio = false,
): void {
  const period = 1 / freq
  const delay = ctx.createDelay(Math.max(period * 2, 0.08))
  delay.delayTime.value = period

  const damp = ctx.createBiquadFilter()
  damp.type = 'lowpass'
  damp.frequency.value = Math.min(6200, 1400 + freq * 6.2)
  damp.Q.value = 0.55

  const feedback = ctx.createGain()
  feedback.gain.value = Math.min(0.92, 0.78 + freq / 11000)

  delay.connect(damp)
  damp.connect(feedback)
  feedback.connect(delay)

  const bright = ctx.createBiquadFilter()
  bright.type = 'highshelf'
  bright.frequency.value = 2600
  bright.gain.value = arpeggio ? 3.2 : 3.8

  const outG = ctx.createGain()
  outG.gain.setValueAtTime(0.0001, tStart)
  outG.gain.exponentialRampToValueAtTime(peak, tStart + 0.008)
  damp.connect(bright)
  bright.connect(outG)
  outG.connect(dest)

  const len = Math.max(
    64,
    Math.ceil(ctx.sampleRate * Math.min(period * 2.2, 0.022)),
  )
  const buf = ctx.createBuffer(1, len, ctx.sampleRate)
  const ch = buf.getChannelData(0)
  for (let i = 0; i < len; i++) {
    const w = 1 - i / len
    ch[i] = (Math.random() * 2 - 1) * w ** 0.45
  }
  const src = ctx.createBufferSource()
  src.buffer = buf
  const exG = ctx.createGain()
  exG.gain.value = 0.95
  src.connect(exG)
  exG.connect(delay)

  const holdEnd = arpeggio ? tStart + 0.16 : tStart + 0.45
  const tailEnd = arpeggio ? tStart + 0.62 : tStart + 1.45
  outG.gain.setValueAtTime(peak, holdEnd)
  outG.gain.exponentialRampToValueAtTime(0.0001, tailEnd)

  src.start(tStart)
  src.stop(tStart + len / ctx.sampleRate + 0.002)

  registerCleanup([delay, damp, feedback, bright, outG, exG, src], src)
}

function startNoisePluck(
  ctx: AudioContext,
  freq: number,
  tStart: number,
  dest: AudioNode,
  peak: number,
  arpeggio = false,
): void {
  const len = Math.ceil(ctx.sampleRate * 0.04)
  const buffer = ctx.createBuffer(1, len, ctx.sampleRate)
  const ch = buffer.getChannelData(0)
  for (let i = 0; i < len; i++) {
    ch[i] = (Math.random() * 2 - 1) * (1 - i / len) ** 0.3
  }
  const src = ctx.createBufferSource()
  src.buffer = buffer

  const bp = ctx.createBiquadFilter()
  bp.type = 'bandpass'
  bp.frequency.value = freq
  bp.Q.value = arpeggio ? 6.5 : 8

  const hp = ctx.createBiquadFilter()
  hp.type = 'highpass'
  hp.frequency.value = 80
  hp.Q.value = 0.7

  const shelf = ctx.createBiquadFilter()
  shelf.type = 'highshelf'
  shelf.frequency.value = 1800
  shelf.gain.value = arpeggio ? 3.5 : 4.5

  const g = ctx.createGain()
  g.gain.setValueAtTime(0.0001, tStart)
  g.gain.exponentialRampToValueAtTime(peak, tStart + 0.005)
  g.gain.exponentialRampToValueAtTime(0.0001, tStart + (arpeggio ? 0.38 : 0.55))

  src.connect(bp)
  bp.connect(hp)
  hp.connect(shelf)
  shelf.connect(g)
  g.connect(dest)

  src.start(tStart)
  src.stop(tStart + len / ctx.sampleRate + 0.001)

  registerCleanup([bp, hp, shelf, g, src], src)
}

function playStringAt(
  ctx: AudioContext,
  minP: number,
  freq: number,
  physStringIdx: number,
  tStart: number,
  out: GainNode,
  peak: number,
  arpeggio: boolean,
): void {
  const pan = -0.75 + (1.5 * physStringIdx) / 5
  const panner = ctx.createStereoPanner()
  panner.pan.value = pan
  panner.connect(out)

  const period = 1 / freq
  if (period >= minP * 1.2) {
    startKarplusString(ctx, freq, tStart, panner, peak, arpeggio)
  } else {
    startNoisePluck(ctx, freq, tStart, panner, peak * 0.85, arpeggio)
  }
  registerCleanup([panner])
}

type Voice = { midi: number; phys: number; cents: number }

function midiToNoteName(midi: number, cents: number): string {
  return Frequency(midi + cents / 100, 'midi').toNote()
}

async function ensureToneGuitar(): Promise<GuitarAcousticSlimSampler | null> {
  await start()
  if (toneGuitar) return toneGuitar
  if (!toneGuitarInflight) {
    toneGuitarInflight = new Promise<GuitarAcousticSlimSampler | null>(
      (resolve) => {
        try {
          const g = new GuitarAcousticSlimSampler({
            onload: () => {
              g.volume.value = -5
              g.toDestination()
              toneGuitar = g
              resolve(g)
            },
          })
        } catch {
          resolve(null)
        }
      },
    ).finally(() => {
      toneGuitarInflight = null
    })
  }
  return toneGuitarInflight
}

function playChordWithToneGuitar(
  guitar: GuitarAcousticSlimSampler,
  arpVoices: Voice[],
  voices: Voice[],
): void {
  guitar.releaseAll()

  const arpStep = 0.3
  const pauseBeforeBlock = 0.22
  const strum = 0.032
  let t = now() + 0.05

  for (const v of arpVoices) {
    const n = midiToNoteName(v.midi, v.cents)
    guitar.triggerAttackRelease(n, 0.55, t, 0.88)
    t += arpStep
  }

  const blockT0 = t + pauseBeforeBlock
  for (let k = 0; k < voices.length; k++) {
    const v = voices[k]!
    guitar.triggerAttackRelease(
      midiToNoteName(v.midi, v.cents),
      1.25,
      blockT0 + k * strum,
      0.78,
    )
  }
}

/** 和弦进行：仅柱式扫弦，短尾音，便于按小节跟拍 */
function playChordWithToneGuitarProgression(
  guitar: GuitarAcousticSlimSampler,
  voices: Voice[],
): void {
  guitar.releaseAll()
  const strum = 0.03
  const t0 = now() + 0.04
  for (let k = 0; k < voices.length; k++) {
    const v = voices[k]!
    guitar.triggerAttackRelease(
      midiToNoteName(v.midi, v.cents),
      0.82,
      t0 + k * strum,
      0.85,
    )
  }
}

function playChordKarplus(
  ctx: AudioContext,
  out: GainNode,
  voices: Voice[],
  arpVoices: Voice[],
): void {
  const t0 = ctx.currentTime
  const minP = minKarplusPeriod(ctx)
  const n = voices.length
  const nArp = arpVoices.length
  const freqOf = (v: Voice) => midiToFreq(v.midi) * 2 ** (v.cents / 1200)
  const peakBlock = 0.2 / Math.sqrt(n)
  const peakArp = Math.min(0.28, 0.2 + 0.022 * nArp)
  const arpStep = 0.3
  const pauseBeforeBlock = 0.22
  const strum = 0.032

  let t = t0
  for (const v of arpVoices) {
    playStringAt(ctx, minP, freqOf(v), v.phys, t, out, peakArp, true)
    t += arpStep
  }

  const blockT0 = t + pauseBeforeBlock
  for (let k = 0; k < voices.length; k++) {
    const v = voices[k]!
    playStringAt(ctx, minP, freqOf(v), v.phys, blockT0 + k * strum, out, peakBlock, false)
  }
}

function playChordKarplusProgression(
  ctx: AudioContext,
  out: GainNode,
  voices: Voice[],
): void {
  const t0 = ctx.currentTime + 0.02
  const minP = minKarplusPeriod(ctx)
  const n = voices.length
  const freqOf = (v: Voice) => midiToFreq(v.midi) * 2 ** (v.cents / 1200)
  const peakBlock = 0.22 / Math.sqrt(n)
  const strum = 0.028
  for (let k = 0; k < voices.length; k++) {
    const v = voices[k]!
    playStringAt(ctx, minP, freqOf(v), v.phys, t0 + k * strum, out, peakBlock, false)
  }
}

export type PlayChordOptions = {
  /** full：分解+柱式（抽屉试听）；progression：仅柱式，适合整条进行跟拍 */
  variant?: 'full' | 'progression'
}

export async function playChordFromFrets(
  frets: readonly number[],
  options?: PlayChordOptions,
): Promise<void> {
  if (!canPlayChordFrets(frets)) return

  const variant = options?.variant ?? 'full'

  await start()
  context = getContext().rawContext as AudioContext
  await context.resume()

  stopAll()
  toneGuitar?.releaseAll(0)

  if (!outputGain || outputGain.context !== context) {
    outputGain = context.createGain()
    outputGain.connect(context.destination)
    toneGuitar?.dispose()
    toneGuitar = null
  }
  const out = outputGain

  const voices: Voice[] = []
  for (let i = 0; i < 6; i++) {
    const f = coerceFretCell(frets[i])
    if (f >= 0) {
      const cents = (Math.random() - 0.5) * 8
      voices.push({
        midi: OPEN_STRING_MIDI[i]! + f,
        phys: i,
        cents,
      })
    }
  }
  if (!voices.length) return

  const seenMidi = new Set<number>()
  const arpVoices: Voice[] = []
  for (const v of voices) {
    if (seenMidi.has(v.midi)) continue
    seenMidi.add(v.midi)
    arpVoices.push(v)
  }
  arpVoices.sort((a, b) => a.midi - b.midi)

  const guitar = await ensureToneGuitar()
  if (guitar) {
    if (variant === 'progression') {
      playChordWithToneGuitarProgression(guitar, voices)
    } else {
      playChordWithToneGuitar(guitar, arpVoices, voices)
    }
    return
  }

  out.gain.value = 0.24
  if (variant === 'progression') {
    playChordKarplusProgression(context, out, voices)
  } else {
    playChordKarplus(context, out, voices, arpVoices)
  }
}

/** 立即静音（合成节点 + Tone 采样），用于停止整条进行试听 */
export function stopChordPlayback(): void {
  stopAll()
  toneGuitar?.releaseAll(0)
}

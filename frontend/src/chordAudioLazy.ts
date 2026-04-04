/**
 * 延迟加载 `playChordFromFrets.ts`（内含 Tone + 大量 MP3），加快首屏与主 bundle。
 * 首次点击试听时再下载独立 chunk；Vite 会对动态 import 单独分包。
 */
import type { PlayChordOptions } from './playChordFromFrets'

export type { PlayChordOptions } from './playChordFromFrets'

let audioModule: typeof import('./playChordFromFrets') | null = null

function loadChordAudioModule(): Promise<typeof import('./playChordFromFrets')> {
  if (audioModule) return Promise.resolve(audioModule)
  return import('./playChordFromFrets').then((m) => {
    audioModule = m
    return m
  })
}

export async function playChordFromFrets(
  frets: readonly number[],
  options?: PlayChordOptions,
): Promise<void> {
  const m = await loadChordAudioModule()
  return m.playChordFromFrets(frets, options)
}

export function stopChordPlayback(): void {
  audioModule?.stopChordPlayback()
}

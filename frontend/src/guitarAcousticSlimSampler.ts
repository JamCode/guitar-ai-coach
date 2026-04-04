/**
 * 仅打包 tonejs-instruments 木吉他的 **minify** 采样（10 段 MP3），
 * 避免官方包「全量 import」导致 dist 仍含 30+ 文件。
 */
import { Sampler } from 'tone'
import A2 from 'tonejs-instrument-guitar-acoustic-mp3/A2.mp3'
import As3 from 'tonejs-instrument-guitar-acoustic-mp3/As3.mp3'
import B4 from 'tonejs-instrument-guitar-acoustic-mp3/B4.mp3'
import Cs3 from 'tonejs-instrument-guitar-acoustic-mp3/Cs3.mp3'
import D3 from 'tonejs-instrument-guitar-acoustic-mp3/D3.mp3'
import Ds3 from 'tonejs-instrument-guitar-acoustic-mp3/Ds3.mp3'
import E4 from 'tonejs-instrument-guitar-acoustic-mp3/E4.mp3'
import Fs2 from 'tonejs-instrument-guitar-acoustic-mp3/Fs2.mp3'
import G3 from 'tonejs-instrument-guitar-acoustic-mp3/G3.mp3'
import Gs4 from 'tonejs-instrument-guitar-acoustic-mp3/Gs4.mp3'

const SLIM_URLS = {
  A2,
  'A#3': As3,
  B4,
  'C#3': Cs3,
  D3,
  'D#3': Ds3,
  E4,
  'F#2': Fs2,
  G3,
  'G#4': Gs4,
} as const

export class GuitarAcousticSlimSampler extends Sampler {
  constructor(options: { onload?: () => void } = {}) {
    super({
      urls: SLIM_URLS,
      onload: options.onload,
    })
  }
}

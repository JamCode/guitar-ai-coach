/**
 * 全站共享：调号、难度（和弦进行页与和弦速查页共用，与需求 PRD 一致）。
 */
import { ref } from 'vue'

export const selectedKey = ref('C')
export const selectedLevel = ref('中级')
export const referenceKey = ref('C')
export const keys = ref<string[]>([
  'C',
  'Db',
  'D',
  'Eb',
  'E',
  'F',
  'Gb',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
])
export const levels = ref<string[]>(['初级', '中级', '高级'])

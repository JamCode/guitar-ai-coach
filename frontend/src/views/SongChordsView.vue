<template>
  <div class="song-wrap">
    <div class="song-card">
      <h1 class="song-title">找歌和弦（30 秒开唱）</h1>
      <p class="song-sub">输入歌名后返回可弹可唱版本，支持 12 调实时查看。</p>

      <label class="song-label" for="song-query">输入歌曲（歌名 / 歌名+歌手）</label>
      <input
        id="song-query"
        v-model.trim="queryText"
        class="song-input"
        type="text"
        placeholder="例如：夜空中最亮的星 逃跑计划"
        @keyup.enter="onSearch"
      />
      <button type="button" class="song-main-btn" :disabled="loading" @click="onSearch">
        {{ loading ? '搜索中…' : '搜索可弹和弦' }}
      </button>
      <p class="song-status">{{ searchStatus }}</p>

      <div class="difficulty-row">
        <button
          v-for="item in difficultyOptions"
          :key="item.id"
          type="button"
          class="difficulty-btn"
          :class="{ on: item.id === difficulty }"
          @click="onSwitchDifficulty(item.id)"
        >
          {{ item.label }}
        </button>
      </div>

      <section v-if="scoreView" class="result-card" aria-live="polite">
        <h2 class="result-title">{{ scoreView.title_display }}</h2>
        <div class="result-chips">
          <span class="chip em">{{ difficultyLabel(scoreView.difficulty_level) }}</span>
          <span class="chip">来源：{{ scoreView.source_type }}</span>
          <span class="chip">版本：{{ scoreView.version_no }}</span>
        </div>

        <div class="result-grid">
          <div class="mini">
            <b>调号</b>
            原调：{{ scoreView.key_original }}
          </div>
          <div class="mini">
            <b>选调（12 调）</b>
            <select v-model="targetKey" class="mini-select">
              <option v-for="k in allKeys" :key="k" :value="k">{{ k }}</option>
            </select>
          </div>
        </div>

        <div class="progression-box">
          <b>主歌和弦</b>
          <div class="line">{{ scoreView.verse_progression.join(' - ') }}</div>
        </div>
        <div class="progression-box">
          <b>副歌和弦</b>
          <div class="line">{{ scoreView.chorus_progression.join(' - ') }}</div>
        </div>

        <div class="chart-box">
          <b>完整歌谱（和弦位置按 pos 渲染）</b>
          <template v-if="scoreView.chart_json?.sections?.length">
            <div v-for="(sec, si) in scoreView.chart_json.sections" :key="`sec-${si}`" class="chart-section">
              <div class="chart-section-title">{{ sec.name }}</div>
              <div v-for="(line, li) in sec.lines" :key="`line-${si}-${li}`" class="chart-line">
                <div class="chord-row">
                  <template v-for="(part, pi) in layoutLine(line).parts" :key="`cp-${si}-${li}-${pi}`">
                    <span class="lyric-part">{{ part.text }}</span>
                    <span v-if="part.chords.length" class="chord-token">{{ part.chords.join('/') }}</span>
                  </template>
                </div>
                <div class="lyric-row">{{ line.lyric }}</div>
              </div>
            </div>
          </template>
          <template v-else>
            <pre class="chart-fallback">{{ scoreView.full_chart_lines.join('\n') }}</pre>
          </template>
        </div>

        <p class="why">推荐理由：{{ scoreView.why_recommended }}</p>

        <div class="action-row">
          <button type="button" class="song-main-btn" :disabled="verifying" @click="onAiVerify">
            {{ verifying ? 'AI核对中…' : 'AI核对并更新' }}
          </button>
          <button type="button" class="song-sub-btn" :disabled="loadingV2" @click="onViewV2">
            {{ loadingV2 ? '加载中…' : '查看上一版（v2）' }}
          </button>
        </div>

        <div v-if="v2View" class="v2-box">
          <b>上一版（v2）：{{ v2View.title_display }}</b>
          <div class="line">{{ v2View.verse_progression.join(' - ') }}</div>
          <div class="line">{{ v2View.chorus_progression.join(' - ') }}</div>
        </div>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'

type DifficultyId = 'beginner' | 'intermediate' | 'advanced'
type LineEvent = { symbol: string; pos: number }
type ChartLine = { lyric: string; chord_events: LineEvent[] }
type ChartSection = { name: string; lines: ChartLine[] }
type ScorePayload = {
  song_id: number
  version_id: number
  version_no: string
  title_display: string
  difficulty_level: DifficultyId
  key_original: string
  key_recommended: string
  verse_progression: string[]
  chorus_progression: string[]
  full_chart_lines: string[]
  chart_json: { sections: ChartSection[] }
  quality_score: number
  source_type: string
  why_recommended: string
}

const allKeys = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B']
const keyIndex: Record<string, number> = {
  C: 0,
  'B#': 0,
  Db: 1,
  'C#': 1,
  D: 2,
  Eb: 3,
  'D#': 3,
  E: 4,
  Fb: 4,
  F: 5,
  'E#': 5,
  Gb: 6,
  'F#': 6,
  G: 7,
  Ab: 8,
  'G#': 8,
  A: 9,
  Bb: 10,
  'A#': 10,
  B: 11,
  Cb: 11,
}

const difficultyOptions: Array<{ id: DifficultyId; label: string }> = [
  { id: 'beginner', label: '新手' },
  { id: 'intermediate', label: '中级' },
  { id: 'advanced', label: '进阶' },
]
const SEARCH_TIMEOUT_MS = 240000

const queryText = ref('夜空中最亮的星 逃跑计划')
const difficulty = ref<DifficultyId>('beginner')
const loading = ref(false)
const verifying = ref(false)
const loadingV2 = ref(false)
const searchStatus = ref('等待搜索')
const baseScore = ref<ScorePayload | null>(null)
const v2View = ref<ScorePayload | null>(null)
const targetKey = ref('C')

const apiBase = (import.meta.env.VITE_API_BASE_URL || '/api').replace(/\/$/, '')
function apiUrl(path: string) {
  const p = path.startsWith('/') ? path : `/${path}`
  return `${apiBase}${p}`
}

function normalize12(n: number) {
  return ((n % 12) + 12) % 12
}

function transposeKeyName(key: string, semitones: number) {
  const idx = keyIndex[key]
  if (idx === undefined) return key
  return allKeys[normalize12(idx + semitones)] || key
}

function semitoneDistance(fromKey: string, toKey: string) {
  const f = keyIndex[normalizePitchKey(fromKey)]
  const t = keyIndex[normalizePitchKey(toKey)]
  if (f === undefined || t === undefined) return 0
  return t - f
}

function normalizePitchKey(key: string) {
  const raw = (key || '').trim()
  const m = raw.match(/^([A-G](?:b|#)?)/)
  return m ? m[1] : raw
}

function transposeChordSymbol(symbol: string, semitones: number) {
  const m = symbol.trim().match(/^([A-G](?:b|#)?)([^/]*)((?:\/)([A-G](?:b|#)?))?$/)
  if (!m) return symbol
  const root = m[1]
  const quality = m[2] || ''
  const bass = m[4] || ''
  const rootT = transposeKeyName(root, semitones)
  const bassT = bass ? transposeKeyName(bass, semitones) : ''
  return `${rootT}${quality}${bassT ? `/${bassT}` : ''}`
}

function transposeProgression(arr: string[], semitones: number) {
  return arr.map((s) => transposeChordSymbol(s, semitones))
}

function transposeChartJson(chart: { sections: ChartSection[] }, semitones: number) {
  return {
    sections: (chart?.sections || []).map((sec) => ({
      ...sec,
      lines: (sec.lines || []).map((line) => ({
        ...line,
        chord_events: (line.chord_events || []).map((e) => ({
          ...e,
          symbol: transposeChordSymbol(e.symbol, semitones),
        })),
      })),
    })),
  }
}

const scoreView = computed<ScorePayload | null>(() => {
  if (!baseScore.value) return null
  const delta = semitoneDistance(baseScore.value.key_recommended, targetKey.value)
  return {
    ...baseScore.value,
    verse_progression: transposeProgression(baseScore.value.verse_progression || [], delta),
    chorus_progression: transposeProgression(baseScore.value.chorus_progression || [], delta),
    chart_json: transposeChartJson(baseScore.value.chart_json || { sections: [] }, delta),
  }
})

function difficultyLabel(v: DifficultyId) {
  const found = difficultyOptions.find((x) => x.id === v)
  return found ? found.label : v
}

function layoutLine(line: ChartLine) {
  const lyric = line?.lyric || ''
  const events = [...(line?.chord_events || [])].sort((a, b) => a.pos - b.pos)
  const parts: Array<{ text: string; chords: string[] }> = []
  let cursor = 0
  for (let i = 0; i < events.length; ) {
    const pos = Math.max(0, Math.min(lyric.length, Number(events[i]?.pos || 0)))
    const grouped: string[] = []
    while (i < events.length && Number(events[i]?.pos || 0) === pos) {
      if (events[i]?.symbol) grouped.push(events[i].symbol)
      i += 1
    }
    parts.push({ text: lyric.slice(cursor, pos), chords: grouped })
    cursor = pos
  }
  parts.push({ text: lyric.slice(cursor), chords: [] })
  return { parts }
}

async function onSearch() {
  if (!queryText.value.trim()) return
  loading.value = true
  searchStatus.value = '搜索中，首次命中可能需要 10~60 秒…'
  v2View.value = null
  const controller = new AbortController()
  const timer = window.setTimeout(() => controller.abort(), SEARCH_TIMEOUT_MS)
  try {
    const resp = await fetch(apiUrl('/song-chords/search'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      signal: controller.signal,
      body: JSON.stringify({
        query_text: queryText.value.trim(),
        difficulty: difficulty.value,
      }),
    })
    const data = (await resp.json().catch(() => ({}))) as {
      score?: ScorePayload
      latency_ms?: number
      search_status?: string
      error?: string
    }
    if (!resp.ok || !data.score) {
      throw new Error(data.error || `请求失败（HTTP ${resp.status}）`)
    }
    baseScore.value = data.score
    targetKey.value = normalizePitchKey(data.score.key_original || data.score.key_recommended || 'C')
    searchStatus.value = `搜索完成：${data.search_status || 'ok'}（${data.latency_ms ?? 0}ms）`
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      searchStatus.value = `搜索超时（>${Math.floor(SEARCH_TIMEOUT_MS / 1000)}s），请重试或补充更精确歌名与歌手`
    } else {
      searchStatus.value = err instanceof Error ? err.message : '搜索失败'
    }
  } finally {
    window.clearTimeout(timer)
    loading.value = false
  }
}

async function onAiVerify() {
  if (!baseScore.value?.song_id) return
  verifying.value = true
  try {
    const resp = await fetch(apiUrl('/song-chords/ai-verify'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        song_id: baseScore.value.song_id,
        difficulty: difficulty.value,
      }),
    })
    const data = (await resp.json().catch(() => ({}))) as { score?: ScorePayload; error?: string }
    if (!resp.ok || !data.score) {
      throw new Error(data.error || `请求失败（HTTP ${resp.status}）`)
    }
    baseScore.value = data.score
    targetKey.value = normalizePitchKey(data.score.key_original || data.score.key_recommended || targetKey.value)
    searchStatus.value = 'AI核对完成：已备份旧版到 v2，并更新当前 v1'
  } catch (err) {
    searchStatus.value = err instanceof Error ? err.message : 'AI核对失败'
  } finally {
    verifying.value = false
  }
}

async function onViewV2() {
  if (!baseScore.value?.song_id) return
  loadingV2.value = true
  try {
    const resp = await fetch(apiUrl('/song-chords/version'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        song_id: baseScore.value.song_id,
        difficulty: difficulty.value,
        version_no: 'v2',
      }),
    })
    const data = (await resp.json().catch(() => ({}))) as { score?: ScorePayload; error?: string }
    if (!resp.ok || !data.score) {
      throw new Error(data.error || `请求失败（HTTP ${resp.status}）`)
    }
    v2View.value = data.score
  } catch (err) {
    searchStatus.value = err instanceof Error ? err.message : '读取 v2 失败'
  } finally {
    loadingV2.value = false
  }
}

function onSwitchDifficulty(next: DifficultyId) {
  difficulty.value = next
  if (baseScore.value) {
    void onSearch()
  }
}
</script>

<style scoped>
.song-wrap {
  width: 100%;
  display: flex;
  justify-content: center;
  padding: 20px 16px calc(22px + 56px + env(safe-area-inset-bottom, 0px));
  box-sizing: border-box;
}

.song-card {
  width: 560px;
  max-width: 100%;
  text-align: left;
}

.song-title {
  margin: 0 0 4px;
  font-size: 1.25rem;
  font-weight: 800;
  color: #111;
}

.song-sub {
  margin: 0 0 14px;
  font-size: 13px;
  color: rgba(17, 17, 17, 0.76);
}

.song-label {
  display: block;
  margin: 0 0 6px;
  font-size: 13px;
  font-weight: 700;
}

.song-input {
  width: 100%;
  border: 1px solid #ccc;
  border-radius: 10px;
  padding: 11px 10px;
  font-size: 15px;
  box-sizing: border-box;
}

.song-main-btn {
  width: 100%;
  margin-top: 10px;
  border: 1px solid #111;
  border-radius: 10px;
  padding: 11px 12px;
  font-size: 15px;
  font-weight: 760;
  cursor: pointer;
  color: #fff;
  background: #111;
}

.song-sub-btn {
  width: 100%;
  margin-top: 8px;
  border: 1px solid #111;
  border-radius: 10px;
  padding: 11px 12px;
  font-size: 15px;
  font-weight: 760;
  cursor: pointer;
  color: #111;
  background: #fff;
}

.song-main-btn:disabled,
.song-sub-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.song-status {
  margin: 10px 0 0;
  font-size: 13px;
  color: rgba(17, 17, 17, 0.8);
}

.difficulty-row {
  margin-top: 10px;
  display: flex;
  gap: 8px;
}

.difficulty-btn {
  width: auto;
  border: 1px solid #111;
  border-radius: 999px;
  padding: 6px 10px;
  font-size: 13px;
  background: #fff;
  color: #111;
  cursor: pointer;
}

.difficulty-btn.on {
  background: #111;
  color: #fff;
}

.result-card {
  margin-top: 14px;
  border: 1px dashed #d8d8d8;
  border-radius: 12px;
  padding: 12px;
  background: #fcfcfc;
}

.result-title {
  margin: 0 0 8px;
  font-size: 17px;
  font-weight: 800;
}

.result-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-bottom: 10px;
}

.chip {
  border: 1px solid #d8d8d8;
  border-radius: 999px;
  padding: 2px 8px;
  font-size: 12px;
}

.chip.em {
  color: #146c2e;
  border-color: #b8dfc0;
  background: #edf8ef;
}

.result-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
}

.mini {
  border: 1px solid #d8d8d8;
  border-radius: 8px;
  padding: 8px;
  font-size: 13px;
}

.mini b {
  display: block;
  margin-bottom: 4px;
}

.mini-select {
  width: 100%;
  border: 1px solid #d8d8d8;
  border-radius: 8px;
  padding: 7px 9px;
}

.progression-box,
.chart-box,
.v2-box {
  margin-top: 10px;
  border: 1px solid #d8d8d8;
  border-radius: 8px;
  padding: 8px;
  background: #fff;
}

.line {
  margin-top: 4px;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 13px;
}

.chart-section {
  margin-top: 8px;
}

.chart-section-title {
  font-size: 12px;
  font-weight: 800;
  color: rgba(17, 17, 17, 0.76);
  margin-bottom: 5px;
}

.chart-line {
  margin-bottom: 8px;
}

.chord-row {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 12px;
  min-height: 20px;
  color: #0f5aa6;
  line-height: 1.2;
}

.lyric-row {
  white-space: pre-wrap;
  font-size: 14px;
}

.chord-token {
  display: inline-block;
  margin-right: 4px;
  font-weight: 700;
}

.why {
  margin: 10px 0 0;
  font-size: 12px;
  color: rgba(17, 17, 17, 0.78);
}

.action-row {
  margin-top: 10px;
}

.chart-fallback {
  margin: 6px 0 0;
  white-space: pre-wrap;
  font-size: 13px;
  line-height: 1.5;
}

@media (prefers-color-scheme: dark) {
  .song-title {
    color: #d8dce6;
  }
  .song-sub {
    color: rgba(216, 220, 230, 0.82);
  }
  .song-label {
    color: rgba(216, 220, 230, 0.92);
  }
  .song-input {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.22);
    color: #d8dce6;
  }
  .song-input::placeholder {
    color: rgba(216, 220, 230, 0.58);
  }
  .song-main-btn {
    border-color: #ffffff;
    background: #ffffff;
    color: #0b0b0f;
  }
  .song-sub-btn {
    border-color: rgba(255, 255, 255, 0.26);
    background: rgba(255, 255, 255, 0.08);
    color: #d8dce6;
  }
  .song-status {
    color: rgba(216, 220, 230, 0.84);
  }
  .difficulty-btn {
    border-color: rgba(255, 255, 255, 0.28);
    background: rgba(255, 255, 255, 0.08);
    color: #d8dce6;
  }
  .difficulty-btn.on {
    border-color: #ffffff;
    background: #ffffff;
    color: #0b0b0f;
  }
  .result-card {
    border-color: rgba(255, 255, 255, 0.16);
    background: rgba(15, 15, 18, 0.96);
  }
  .result-title {
    color: #d8dce6;
  }
  .chip {
    border-color: rgba(255, 255, 255, 0.22);
    color: rgba(216, 220, 230, 0.9);
  }
  .chip.em {
    color: #c6f6d1;
    border-color: rgba(143, 231, 176, 0.5);
    background: rgba(98, 196, 137, 0.24);
  }
  .mini,
  .progression-box,
  .chart-box,
  .v2-box {
    border-color: rgba(255, 255, 255, 0.16);
    background: rgba(255, 255, 255, 0.06);
    color: rgba(216, 220, 230, 0.92);
  }
  .mini-select {
    border-color: rgba(255, 255, 255, 0.24);
    background: rgba(255, 255, 255, 0.08);
    color: #d8dce6;
  }
  .chart-section-title {
    color: rgba(216, 220, 230, 0.82);
  }
  .chord-row {
    color: #8dc6ff;
  }
  .lyric-row {
    color: rgba(216, 220, 230, 0.94);
  }
  .why {
    color: rgba(216, 220, 230, 0.82);
  }
  .chart-fallback {
    color: rgba(216, 220, 230, 0.92);
  }
}
</style>

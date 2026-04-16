<!--
  和弦速查：下拉拼和弦符号 → 变调预览 → 多套指法（/chords/explain-multi）。
  调号、难度与 session 共用。
-->
<template>
  <div class="dict-wrap">
    <div class="dict-card">
      <h1 class="dict-title">和弦速查</h1>
      <p class="dict-sub">用下拉选择和弦；调号与「和弦进行」页同步。</p>
      <RouterLink class="dict-quiz-link" to="/quiz">去训练题库，强化按法记忆 →</RouterLink>

      <section class="dict-section" aria-labelledby="live-h">
        <h2 id="live-h" class="dict-section-h">当前和弦</h2>
        <div class="live-chord" aria-live="polite">
          <div class="live-label">与谱子上的字母对照（C 调记谱变到当前调）</div>
          <div class="live-sym">{{ displaySymbol || '—' }}</div>
          <p class="live-parts">{{ previewParts }}</p>
          <p class="live-key">
            当前查看调：<strong>{{ selectedKey }}</strong> · 难度：<strong>{{ selectedLevel }}</strong>
          </p>
        </div>
      </section>

      <section class="dict-section">
        <h2 class="dict-section-h">选择和弦</h2>
        <label class="field-label" for="dr">根音</label>
        <select id="dr" v-model="selRoot" class="field-select">
          <option v-for="r in keys" :key="r" :value="r">{{ r }}</option>
        </select>

        <label class="field-label" for="dq">和弦性质</label>
        <select id="dq" v-model="selQual" class="field-select">
          <option v-for="q in qualOptions" :key="q.id" :value="q.id">{{ q.label }}</option>
        </select>

        <label class="field-label" for="db">低音 / 转位</label>
        <select id="db" v-model="selBass" class="field-select">
          <option v-for="b in bassOptions" :key="b.id" :value="b.id">{{ b.label }}</option>
        </select>

        <label class="field-label" for="dk">目标调（与全站同步）</label>
        <select id="dk" v-model="selectedKey" class="field-select">
          <option v-for="k in keys" :key="k" :value="k">{{ k }} 调</option>
        </select>

        <label class="field-label" for="dl">难度</label>
        <select id="dl" v-model="selectedLevel" class="field-select">
          <option v-for="lv in levels" :key="lv" :value="lv">{{ lv }}</option>
        </select>
      </section>

      <button type="button" class="dict-primary" :disabled="loading" @click="fetchMulti(false)">
        {{ loading ? '加载中…' : '查看多种按法' }}
      </button>
      <button
        v-if="voicings.length"
        type="button"
        class="dict-secondary"
        :disabled="recalibrating"
        @click="fetchMulti(true)"
      >
        {{ recalibrating ? '重新生成中…' : '指法不理想？让 AI 全部重算' }}
      </button>
      <p v-if="errorMsg" class="dict-err">{{ errorMsg }}</p>

      <section v-if="chordSummary && voicings.length" class="dict-section dict-results">
        <h2 class="dict-section-h">和弦说明</h2>
        <p v-if="chordSummary.notes_letters?.length" class="summary-notes">
          构成音：{{ chordSummary.notes_letters.join(' · ') }}
        </p>
        <p v-if="chordSummary.notes_explain_zh" class="summary-p">{{ chordSummary.notes_explain_zh }}</p>

        <h3 class="dict-voicings-h">多种按法</h3>
        <article v-for="(v, i) in voicings" :key="i" class="voicing-card">
          <div class="voicing-tags">{{ v.label_zh }}</div>
          <ChordDiagram
            :frets="v.explain.frets"
            :fingers="v.explain.fingers"
            :base-fret="v.explain.base_fret"
            :barre="v.explain.barre"
          />
          <p v-if="v.explain.voicing_explain_zh" class="voicing-txt">{{ v.explain.voicing_explain_zh }}</p>
          <button
            type="button"
            class="dict-play"
            :disabled="!canPlayChordFrets(v.explain.frets) || previewLoadingIndex !== null"
            @click="playOne(i, v.explain.frets)"
          >
            <span
              v-if="previewLoadingIndex === i && previewShowSlowSpinner"
              class="chord-audio-spinner"
              aria-hidden="true"
            />
            {{
              previewLoadingIndex === i
                ? previewShowSlowSpinner
                  ? '准备音色中…'
                  : '载入中…'
                : '试听这一按法'
            }}
          </button>
        </article>
        <p v-if="disclaimer" class="dict-disclaimer">{{ disclaimer }}</p>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { RouterLink } from 'vue-router'
import ChordDiagram from '../components/ChordDiagram.vue'
import { startChordSlowSpinnerTimer } from '../chordAudioSpinnerDelay'
import { canPlayChordFrets } from '../chordFretUtils'
import { playChordFromFrets } from '../chordAudioLazy'
import { keys, levels, referenceKey, selectedKey, selectedLevel } from '../session'

type ChordExplain = {
  symbol: string
  notes_letters: string[]
  notes_explain_zh: string
  voicing_explain_zh: string
  frets: number[]
  fingers: (number | null)[] | null
  base_fret: number
  barre: { fret: number; from_string: number; to_string: number } | null
}

/** 正在加载试听音频（Tone chunk + 采样）的按法下标；非空时禁用全部试听防并发 */
const previewLoadingIndex = ref<number | null>(null)
/** 加载超过 CHORD_AUDIO_SPINNER_DELAY_MS 后才为 true，用于显示转圈 */
const previewShowSlowSpinner = ref(false)
let previewSpinnerDisarm: (() => void) | null = null

function disarmPreviewSpinner() {
  previewSpinnerDisarm?.()
  previewSpinnerDisarm = null
  previewShowSlowSpinner.value = false
}

const apiBase = (import.meta.env.VITE_API_BASE_URL || '/api').replace(/\/$/, '')
function apiUrl(path: string) {
  const p = path.startsWith('/') ? path : `/${path}`
  return `${apiBase}${p}`
}

const qualOptions = [
  { id: '', label: '大三（无后缀）' },
  { id: 'm', label: '小三 (m)' },
  { id: '7', label: '属七 (7)' },
  { id: 'maj7', label: '大七 (maj7)' },
  { id: 'm7', label: '小七 (m7)' },
  { id: 'sus2', label: 'sus2' },
  { id: 'sus4', label: 'sus4' },
  { id: 'add9', label: 'add9' },
  { id: 'dim', label: 'dim' },
  { id: 'aug', label: 'aug' },
]

const bassOptions = [
  { id: '', label: '无转位' },
  { id: '/C', label: '低音 C' },
  { id: '/Db', label: '低音 Db' },
  { id: '/D', label: '低音 D' },
  { id: '/Eb', label: '低音 Eb' },
  { id: '/E', label: '低音 E' },
  { id: '/F', label: '低音 F' },
  { id: '/Gb', label: '低音 Gb' },
  { id: '/G', label: '低音 G' },
  { id: '/Ab', label: '低音 Ab' },
  { id: '/A', label: '低音 A' },
  { id: '/Bb', label: '低音 Bb' },
  { id: '/B', label: '低音 B' },
]

const selRoot = ref('C')
const selQual = ref('')
const selBass = ref('')

const builtSymbol = computed(() => {
  if (!selRoot.value) return ''
  return `${selRoot.value}${selQual.value}${selBass.value}`
})

const displaySymbol = ref('')
const loading = ref(false)
const recalibrating = ref(false)
const errorMsg = ref('')
const disclaimer = ref('')
const chordSummary = ref<{
  symbol: string
  notes_letters: string[]
  notes_explain_zh: string
} | null>(null)
const voicings = ref<{ label_zh: string; explain: ChordExplain }[]>([])

const previewParts = computed(() => {
  if (!builtSymbol.value) return '请选择根音与性质'
  const q = qualOptions.find((o) => o.id === selQual.value)
  const ql = q ? q.label.replace(/\s*\([^)]*\)\s*$/, '').trim() : ''
  const bass =
    selBass.value === '' ? '无 slash 转位' : `slash ${selBass.value.slice(1)}`
  return `C 调记谱：${builtSymbol.value} · 性质 ${ql} · ${bass}`
})

async function updateDisplaySymbol() {
  const sym = builtSymbol.value.trim()
  if (!sym) {
    displaySymbol.value = ''
    return
  }
  if (referenceKey.value === selectedKey.value) {
    displaySymbol.value = sym
    return
  }
  try {
    const resp = await fetch(apiUrl('/chords/transpose'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from_key: referenceKey.value,
        to_key: selectedKey.value,
        lines: [sym],
      }),
    })
    if (!resp.ok) {
      displaySymbol.value = sym
      return
    }
    const data = (await resp.json()) as { lines?: string[] }
    displaySymbol.value = (data.lines && data.lines[0]) || sym
  } catch {
    displaySymbol.value = sym
  }
}

watch([builtSymbol, selectedKey, referenceKey], () => void updateDisplaySymbol(), {
  immediate: true,
})

async function fetchMulti(force: boolean) {
  const sym = displaySymbol.value.trim()
  if (!sym) {
    errorMsg.value = '请先选择和弦'
    return
  }
  errorMsg.value = ''
  if (force) recalibrating.value = true
  else loading.value = true
  try {
    const resp = await fetch(apiUrl('/chords/explain-multi'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        symbol: sym,
        key: selectedKey.value,
        level: selectedLevel.value,
        ...(force ? { force_refresh: true } : {}),
      }),
    })
    if (!resp.ok) {
      const errBody = await resp.json().catch(() => ({}))
      const msg =
        typeof (errBody as { detail?: string }).detail === 'string'
          ? (errBody as { detail: string }).detail
          : typeof (errBody as { error?: string }).error === 'string'
            ? (errBody as { error: string }).error
            : `请求失败（HTTP ${resp.status}）`
      throw new Error(msg)
    }
    const data = (await resp.json()) as {
      chord_summary?: {
        symbol: string
        notes_letters: string[]
        notes_explain_zh: string
      }
      voicings?: { label_zh: string; explain: ChordExplain }[]
      disclaimer?: string
    }
    chordSummary.value = data.chord_summary || null
    voicings.value = Array.isArray(data.voicings) ? data.voicings : []
    disclaimer.value = data.disclaimer || ''
    if (!voicings.value.length) throw new Error('未返回按法数据')
  } catch (e) {
    chordSummary.value = null
    voicings.value = []
    errorMsg.value = e instanceof Error ? e.message : '加载失败'
  } finally {
    loading.value = false
    recalibrating.value = false
  }
}

async function playOne(index: number, frets: number[]) {
  if (!canPlayChordFrets(frets) || previewLoadingIndex.value !== null) return
  disarmPreviewSpinner()
  previewShowSlowSpinner.value = false
  previewSpinnerDisarm = startChordSlowSpinnerTimer(() => {
    previewShowSlowSpinner.value = true
  })
  previewLoadingIndex.value = index
  try {
    await playChordFromFrets(frets)
  } catch {
    /* ignore */
  } finally {
    disarmPreviewSpinner()
    previewLoadingIndex.value = null
  }
}
</script>

<style scoped>
.dict-wrap {
  width: 100%;
  display: flex;
  justify-content: center;
  padding: 24px 16px calc(24px + 56px + env(safe-area-inset-bottom, 0px));
  box-sizing: border-box;
}

.dict-card {
  width: 520px;
  max-width: 100%;
  text-align: left;
}

.dict-title {
  font-size: 1.25rem;
  margin: 0 0 4px;
  font-weight: 800;
  color: #111;
}

.dict-sub {
  font-size: 13px;
  color: rgba(17, 17, 17, 0.76);
  margin: 0 0 18px;
}

.dict-quiz-link {
  display: inline-block;
  margin: 0 0 14px;
  font-size: 13px;
  font-weight: 700;
  color: #111;
  text-decoration: none;
  opacity: 1;
}

.dict-quiz-link:hover {
  text-decoration: underline;
  opacity: 1;
}

.dict-section {
  border: 1px dashed #ccc;
  border-radius: 12px;
  padding: 14px;
  margin-bottom: 14px;
  background: #fff;
}

.dict-section-h {
  font-size: 12px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgba(17, 17, 17, 0.72);
  margin: 0 0 12px;
}

.live-chord {
  background: linear-gradient(180deg, #eef6ff 0%, #f8fbff 100%);
  border: 1px solid #9ec5e8;
  border-radius: 10px;
  padding: 12px 14px;
  text-align: center;
}

.live-label {
  font-size: 12px;
  font-weight: 700;
  color: rgba(17, 17, 17, 0.72);
}

.live-sym {
  font-size: 1.85rem;
  font-weight: 800;
  margin: 8px 0;
  word-break: break-all;
}

.live-parts,
.live-key {
  font-size: 13px;
  color: #333;
  margin: 0;
  line-height: 1.5;
}

.live-key {
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px dashed #bcd;
  font-size: 12px;
  color: rgba(17, 17, 17, 0.72);
}

.field-label {
  display: block;
  font-size: 13px;
  font-weight: 600;
  color: #111111;
  margin: 10px 0 4px;
}

.field-label:first-of-type {
  margin-top: 0;
}

.field-select {
  width: 100%;
  padding: 10px 12px;
  font-size: 15px;
  border: 1px solid #ccc;
  border-radius: 8px;
}

.dict-primary {
  width: 100%;
  padding: 12px 16px;
  border-radius: 12px;
  border: 1px solid #111;
  background: #111;
  color: #fff;
  font-weight: 800;
  font-size: 16px;
  cursor: pointer;
  margin-bottom: 10px;
}

.dict-primary:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

.dict-secondary {
  width: 100%;
  padding: 10px 14px;
  border-radius: 12px;
  border: 1px solid rgba(17, 17, 17, 0.25);
  background: rgba(0, 0, 0, 0.04);
  font-weight: 700;
  font-size: 14px;
  cursor: pointer;
  margin-bottom: 10px;
}

.dict-err {
  color: #b42318;
  font-size: 14px;
  margin: 0 0 12px;
}

.dict-results {
  border-style: solid;
  border-color: #e5e5e5;
}

.summary-notes {
  font-size: 15px;
  font-weight: 700;
  margin: 0 0 8px;
}

.summary-p {
  font-size: 14px;
  line-height: 1.55;
  margin: 0 0 16px;
  color: #222;
}

.dict-voicings-h {
  font-size: 14px;
  margin: 0 0 12px;
}

.voicing-card {
  border: 1px solid #e5e5e5;
  border-radius: 12px;
  padding: 12px;
  margin-bottom: 12px;
  background: #fafafa;
}

.voicing-tags {
  font-size: 13px;
  font-weight: 700;
  color: rgba(17, 17, 17, 0.8);
  margin-bottom: 10px;
}

.voicing-txt {
  font-size: 14px;
  line-height: 1.5;
  margin: 10px 0;
  color: #333;
}

.dict-play {
  width: 100%;
  padding: 10px;
  border-radius: 10px;
  border: 1px solid #111;
  background: #111;
  color: #fff;
  font-weight: 700;
  font-size: 14px;
  cursor: pointer;
}

.dict-disclaimer {
  font-size: 12px;
  color: rgba(17, 17, 17, 0.7);
  margin: 16px 0 0;
  line-height: 1.45;
}

@media (prefers-color-scheme: dark) {
  .dict-title {
    color: #d8dce6;
  }
  .dict-sub {
    color: rgba(216, 220, 230, 0.65);
  }
  .dict-quiz-link {
    color: #d8dce6;
  }
  .dict-section {
    background: rgba(15, 15, 18, 0.96);
    border-color: rgba(255, 255, 255, 0.14);
  }
  .dict-section-h {
    color: rgba(216, 220, 230, 0.8);
  }
  .live-chord {
    background: linear-gradient(180deg, rgba(58, 105, 151, 0.34) 0%, rgba(40, 66, 102, 0.3) 100%);
    border-color: rgba(138, 187, 237, 0.58);
  }
  .live-label {
    color: rgba(216, 220, 230, 0.8);
  }
  .live-parts {
    color: rgba(216, 220, 230, 0.92);
  }
  .live-key {
    color: rgba(216, 220, 230, 0.8);
    border-top-color: rgba(188, 214, 240, 0.55);
  }
  .field-label {
    color: rgba(216, 220, 230, 0.92);
  }
  .field-select {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.2);
    color: #d8dce6;
  }
  .dict-primary {
    border-color: #fff;
    background: #fff;
    color: #0b0b0f;
  }
  .dict-secondary {
    border-color: rgba(255, 255, 255, 0.26);
    background: rgba(255, 255, 255, 0.08);
    color: #d8dce6;
  }
  .summary-notes,
  .dict-voicings-h {
    color: #d8dce6;
  }
  .voicing-card {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.12);
  }
  .voicing-tags {
    color: rgba(216, 220, 230, 0.84);
  }
  .summary-p,
  .voicing-txt {
    color: rgba(216, 220, 230, 0.9);
  }
  .dict-disclaimer {
    color: rgba(216, 220, 230, 0.74);
  }
}
</style>

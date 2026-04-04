<!--
  和弦进行页：选风格/难度/调号 → 生成进行；点和弦看指法；试听；换调。
  调号/难度与和弦字典共用 session。
-->
<template>
  <div class="tech-wrap">
    <!-- 主操作区：筛选条件、生成按钮、和弦进行列表 -->
    <div class="tech-card" role="region" aria-label="音乐风格选择">
      <div class="tech-title">音乐风格</div>

      <div class="chips" role="group" aria-label="音乐风格">
        <button
          v-for="s in styles"
          :key="s"
          type="button"
          class="chip"
          :class="{ active: s === selectedStyle }"
          :aria-pressed="s === selectedStyle"
          @click="onSelectStyle(s)"
        >
          {{ s }}
        </button>
      </div>

      <div class="section-label">难度</div>
      <div class="chips level-chips" role="group" aria-label="难度">
        <button
          v-for="lv in levels"
          :key="lv"
          type="button"
          class="chip level-chip"
          :class="{ active: lv === selectedLevel }"
          :aria-pressed="lv === selectedLevel"
          @click="onSelectLevel(lv)"
        >
          {{ lv }}
        </button>
      </div>

      <div class="section-label">调号（12 调）</div>
      <div class="chips key-chips" role="group" aria-label="调号">
        <button
          v-for="k in keys"
          :key="k"
          type="button"
          class="chip key-chip"
          :class="{ active: k === selectedKey }"
          :aria-pressed="k === selectedKey"
          @click="onSelectKey(k)"
        >
          {{ k }}
        </button>
      </div>

      <button class="generate-btn" type="button" @click="onGenerate">
        生成和弦
      </button>

      <div class="result" aria-live="polite">
        <div class="result-head">
          和弦进行（{{ selectedStyle }} · {{ selectedLevel }} · {{ selectedKey }} 调）
        </div>
        <div v-if="progressions.length" class="playback-toolbar" @click.stop>
          <span class="playback-toolbar-label">试听速度</span>
          <div class="bpm-chips" role="group" aria-label="和弦进行试听速度 BPM">
            <button
              v-for="b in progressionBpmChoices"
              :key="b"
              type="button"
              class="bpm-chip"
              :class="{ active: progressionBpm === b }"
              :aria-pressed="progressionBpm === b"
              @click="progressionBpm = b"
            >
              {{ b }}
            </button>
          </div>
          <span class="playback-toolbar-hint">4/4，每和弦一小节</span>
        </div>
        <p v-if="progressionError" class="progression-err">{{ progressionError }}</p>

        <div v-if="isGenerating" class="result-loading">生成中...</div>
        <div v-else-if="isTransposing" class="result-loading">变调中...</div>

        <ul v-else-if="progressions.length" class="progressions">
          <li
            v-for="(p, i) in progressions"
            :key="i"
            class="progression-item"
            :class="{
              expanded: expandedIndex === i,
              'is-playing-line': progressionPlayback?.lineIndex === i,
            }"
            @click="toggleProgression(i)"
          >
            <span class="num">{{ i + 1 }}.</span>
            <button
              type="button"
              class="prog-play-btn"
              :class="{ active: progressionPlayback?.lineIndex === i }"
              :aria-label="
                progressionAudioBootstrappingLine === i
                  ? '正在准备试听'
                  : progressionPlayback?.lineIndex === i
                    ? '停止播放本条和弦进行'
                    : '试听本条和弦进行'
              "
              @click.stop="togglePlayProgression(i)"
            >
              <template v-if="progressionAudioBootstrappingLine === i">
                <span
                  v-if="progressionBootstrapShowSpinner"
                  class="chord-audio-spinner"
                  aria-hidden="true"
                />
                {{ progressionBootstrapShowSpinner ? '准备中…' : '载入中…' }}
              </template>
              <template v-else>
                {{ progressionPlayback?.lineIndex === i ? '停止' : '试听' }}
              </template>
            </button>
            <div class="prog-wrap">
              <span class="prog chord-line">
                <template v-for="(tok, ti) in splitChordTokens(p.chords)" :key="ti">
                  <span v-if="ti > 0" class="chord-sep"> - </span>
                  <button
                    type="button"
                    class="chord-token"
                    :class="{
                      'chord-token--playing':
                        progressionPlayback?.lineIndex === i &&
                        progressionPlayback?.chordIndex === ti,
                    }"
                    @click.stop="openChordExplain(tok)"
                  >
                    {{ tok }}
                  </button>
                </template>
              </span>
              <span class="tip">
                点和弦可看指法；点「试听」按当前 BPM 逐小节播放；点击空白处展开适合歌曲
              </span>
              <ul v-if="expandedIndex === i" class="songs">
                <li v-if="!p.song_refs.length" class="song-empty">暂无歌曲参考</li>
                <li v-for="(song, songIdx) in p.song_refs" :key="songIdx">{{ song }}</li>
              </ul>
            </div>
          </li>
        </ul>

        <div v-else-if="errorMessage" class="result-empty">{{ errorMessage }}</div>
        <div v-else class="result-empty">点击上面的「生成和弦」获取和弦进行</div>
      </div>
    </div>

    <!-- 和弦说明抽屉：挂到 body，避免卡片 overflow 裁剪遮罩 -->
    <Teleport to="body">
      <div
        v-if="sheetOpen"
        class="sheet-backdrop"
        @click.self="closeChordSheet"
      >
        <div class="sheet-panel" role="dialog" aria-modal="true" :aria-label="sheetTitle">
          <div class="sheet-head">
            <span class="sheet-title">{{ sheetTitle }}</span>
            <button type="button" class="sheet-close" aria-label="关闭" @click="closeChordSheet">
              ×
            </button>
          </div>
          <div v-if="sheetLoading" class="sheet-loading">加载指法中…</div>
          <div v-else-if="sheetError" class="sheet-error">{{ sheetError }}</div>
          <div v-else-if="sheetExplain" class="sheet-body">
            <ChordDiagram
              :frets="sheetExplain.frets"
              :fingers="sheetExplain.fingers"
              :base-fret="sheetExplain.base_fret"
              :barre="sheetExplain.barre"
            />
            <section v-if="sheetExplain.notes_letters.length" class="sheet-section">
              <h4 class="sheet-h">构成音</h4>
              <p class="sheet-notes">{{ sheetExplain.notes_letters.join(' · ') }}</p>
            </section>
            <section v-if="sheetExplain.notes_explain_zh" class="sheet-section">
              <h4 class="sheet-h">音名与和弦结构</h4>
              <p class="sheet-p">{{ sheetExplain.notes_explain_zh }}</p>
            </section>
            <section v-if="sheetExplain.voicing_explain_zh" class="sheet-section">
              <h4 class="sheet-h">为何这样按</h4>
              <p class="sheet-p">{{ sheetExplain.voicing_explain_zh }}</p>
            </section>
            <div class="sheet-actions">
              <button
                type="button"
                class="sheet-play"
                :disabled="!sheetCanPreviewChord || sheetChordAudioLoading"
                @click="onPreviewChordInSheet"
              >
                <span
                  v-if="sheetChordAudioLoading && sheetChordShowSlowSpinner"
                  class="chord-audio-spinner"
                  aria-hidden="true"
                />
                {{
                  sheetChordAudioLoading
                    ? sheetChordShowSlowSpinner
                      ? '准备音色中…'
                      : '载入中…'
                    : '试听这一和弦'
                }}
              </button>
              <p v-if="sheetPreviewError" class="sheet-preview-err">{{ sheetPreviewError }}</p>
              <button
                type="button"
                class="sheet-recalibrate"
                :disabled="sheetRecalibrating"
                @click="recalibrateChordExplain"
              >
                {{
                  sheetRecalibrating
                    ? '正在请 AI 重新校准…'
                    : '指法或描述不对？让 AI 重新校准'
                }}
              </button>
              <p v-if="sheetRecalibrateError" class="sheet-recalibrate-err">
                {{ sheetRecalibrateError }}
              </p>
            </div>
            <p v-if="sheetDisclaimer" class="sheet-disclaimer">{{ sheetDisclaimer }}</p>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<script setup lang="ts">
/**
 * 本文件即应用主界面逻辑：选项状态、HTTP 调用、和弦说明弹层。
 * 后端基址：环境变量 VITE_API_BASE_URL，默认走同源 /api（由 nginx 等反代到后端）。
 */
import { computed, onMounted, ref } from 'vue'
import ChordDiagram from '../components/ChordDiagram.vue'
import { startChordSlowSpinnerTimer } from '../chordAudioSpinnerDelay'
import { canPlayChordFrets } from '../chordFretUtils'
import { playChordFromFrets, stopChordPlayback } from '../chordAudioLazy'
import {
  keys,
  levels,
  referenceKey,
  selectedKey,
  selectedLevel,
} from '../session'

/** 单条和弦进行：展示用 chords（可能已变调）、变调基准 chords_base、参考歌曲名列表 */
type ProgressionItem = {
  chords: string
  chords_base: string
  song_refs: string[]
}

// ---------- 生成条件与结果列表 ----------
const styles = ref<string[]>([])
const selectedStyle = ref<string>('')
const isGenerating = ref(false)
const progressions = ref<ProgressionItem[]>([])
const errorMessage = ref('')
/** 展开某条进行以显示「适合歌曲」列表；点击同一项可收起 */
const expandedIndex = ref<number | null>(null)
const isTransposing = ref(false)

/** 和弦进行试听：当前 BPM（每和弦占 4/4 一小节） */
const progressionBpmChoices = [52, 60, 72, 84] as const
const progressionBpm = ref<number>(60)
/** 本条进行：首次加载试听模块/采样完成前为 true，避免误以为卡顿 */
const progressionAudioBootstrappingLine = ref<number | null>(null)
/** 进行试听：超过延迟后才显示转圈 */
const progressionBootstrapShowSpinner = ref(false)
let progressionBootstrapSpinnerDisarm: (() => void) | null = null

function disarmProgressionBootstrapSpinner() {
  progressionBootstrapSpinnerDisarm?.()
  progressionBootstrapSpinnerDisarm = null
  progressionBootstrapShowSpinner.value = false
}

/** 抽屉内「试听」：异步加载音频引擎时 */
const sheetChordAudioLoading = ref(false)
const sheetChordShowSlowSpinner = ref(false)
let sheetChordSpinnerDisarm: (() => void) | null = null

function disarmSheetChordSpinner() {
  sheetChordSpinnerDisarm?.()
  sheetChordSpinnerDisarm = null
  sheetChordShowSlowSpinner.value = false
}

/** 正在播放的进行下标 + 当前和弦 token 下标（高亮用） */
const progressionPlayback = ref<{ lineIndex: number; chordIndex: number } | null>(
  null,
)
const progressionError = ref('')
let progressionAbort: AbortController | null = null
const explainCache = new Map<string, ChordExplain>()

// ---------- 和弦说明底部抽屉（指法图 + 文案）----------
const sheetOpen = ref(false)
const sheetLoading = ref(false)
const sheetError = ref('')
const sheetSymbol = ref('')
const sheetExplain = ref<ChordExplain | null>(null)
const sheetDisclaimer = ref('')
const sheetRecalibrating = ref(false)
const sheetRecalibrateError = ref('')
const sheetPreviewError = ref('')

const sheetCanPreviewChord = computed(() =>
  sheetExplain.value ? canPlayChordFrets(sheetExplain.value.frets) : false,
)

/** 与 POST /chords/explain 返回的 explain 字段一致：指法数组 + 说明文案 */
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

const sheetTitle = computed(() =>
  sheetSymbol.value ? `和弦：${sheetSymbol.value}` : '和弦指法',
)

// ---------- API 地址 ----------
const apiBase = (import.meta.env.VITE_API_BASE_URL || '/api').replace(/\/$/, '')
function apiUrl(path: string) {
  const normalizedPath = path.startsWith('/') ? path : `/${path}`
  return `${apiBase}${normalizedPath}`
}

/** 拉取可选音乐风格，并设置默认选中项 */
async function fetchStyles() {
  errorMessage.value = ''
  const resp = await fetch(apiUrl('/styles'))
  if (!resp.ok) {
    throw new Error(`加载风格失败（HTTP ${resp.status}）`)
  }
  const data = (await resp.json()) as { styles?: string[]; defaultStyle?: string }
  const loaded = Array.isArray(data.styles) ? data.styles : []
  styles.value = loaded
  if (!selectedStyle.value) {
    selectedStyle.value = data.defaultStyle || loaded[0] || ''
  }
}

/** 同步后端支持的调号列表与参考调（变调起点） */
async function fetchKeys() {
  const resp = await fetch(apiUrl('/keys'))
  if (!resp.ok) return
  const data = (await resp.json()) as {
    keys?: string[]
    defaultKey?: string
    referenceKey?: string
  }
  if (Array.isArray(data.keys) && data.keys.length) {
    keys.value = data.keys
  }
  if (data.referenceKey) {
    referenceKey.value = data.referenceKey
  }
  if (data.defaultKey && !selectedKey.value) {
    selectedKey.value = data.defaultKey
  }
}

/** 可选难度档位（若后端提供则覆盖本地默认） */
async function fetchLevels() {
  const resp = await fetch(apiUrl('/levels'))
  if (!resp.ok) return
  const data = (await resp.json()) as { levels?: string[] }
  if (Array.isArray(data.levels) && data.levels.length) {
    levels.value = data.levels
  }
}

/** 在已有 progressions 上按 referenceKey → selectedKey 批量变调，只改 chords 展示行 */
async function applyTranspose() {
  const bases = progressions.value.map((p) => p.chords_base).filter(Boolean)
  if (!bases.length) return
  isTransposing.value = true
  errorMessage.value = ''
  try {
    const resp = await fetch(apiUrl('/chords/transpose'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from_key: referenceKey.value,
        to_key: selectedKey.value,
        lines: bases,
      }),
    })
    if (!resp.ok) {
      throw new Error(`变调失败（HTTP ${resp.status}）`)
    }
    const data = (await resp.json()) as { lines?: string[] }
    const out = data.lines
    if (Array.isArray(out)) {
      out.forEach((line, i) => {
        if (progressions.value[i]) {
          progressions.value[i].chords = line
        }
      })
      explainCache.clear()
      stopProgressionPlayback()
    }
  } catch (err) {
    errorMessage.value = err instanceof Error ? err.message : '变调失败'
  } finally {
    isTransposing.value = false
  }
}

/** 调用 /chords/generate，清空并填充 progressions，并可能同步后端返回的 key/level/style */
async function triggerGenerate(style: string) {
  if (!style) return
  isGenerating.value = true
  stopProgressionPlayback()
  explainCache.clear()
  progressions.value = []
  expandedIndex.value = null
  errorMessage.value = ''
  try {
    const resp = await fetch(apiUrl('/chords/generate'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        style,
        key: selectedKey.value,
        level: selectedLevel.value,
      }),
    })
    if (!resp.ok) {
      throw new Error(`生成失败（HTTP ${resp.status}）`)
    }
    const data = (await resp.json()) as {
      progressions?: Array<{
        chords?: string
        chords_base?: string
        song_ref?: string
        song_refs?: string[]
      }>
      style?: string
      target_key?: string
      level?: string
    }
    if (data.target_key) {
      selectedKey.value = data.target_key
    }
    if (data.level && levels.value.includes(data.level)) {
      selectedLevel.value = data.level
    }
    progressions.value = Array.isArray(data.progressions)
      ? data.progressions
          .map((item) => {
            const chordsBase = (item?.chords_base || item?.chords || '').trim()
            const chords = (item?.chords || chordsBase).trim()
            const songRefs = Array.isArray(item?.song_refs)
              ? item.song_refs.filter((s) => typeof s === 'string' && s.trim()).map((s) => s.trim())
              : item?.song_ref
                ? [item.song_ref.trim()]
                : []
            return { chords, chords_base: chordsBase, song_refs: songRefs }
          })
          .filter((item) => item.chords_base)
      : []
    if (data.style && styles.value.includes(data.style)) {
      selectedStyle.value = data.style
    }
  } catch (err) {
    errorMessage.value = err instanceof Error ? err.message : '请求失败，请稍后重试'
  } finally {
    isGenerating.value = false
  }
}

async function onGenerate() {
  await triggerGenerate(selectedStyle.value)
}

function onSelectStyle(style: string) {
  selectedStyle.value = style
  // 换风格即重新生成（与点「生成和弦」效果一致）
  void triggerGenerate(style)
}

function onSelectLevel(lv: string) {
  if (lv === selectedLevel.value) return
  selectedLevel.value = lv
  stopProgressionPlayback()
  explainCache.clear()
  // 难度变更后列表语义变化，清空结果避免与旧数据混淆
  progressions.value = []
  expandedIndex.value = null
}

function onSelectKey(k: string) {
  if (k === selectedKey.value) return
  selectedKey.value = k
  if (
    progressions.value.length &&
    progressions.value.every((p) => p.chords_base)
  ) {
    void applyTranspose()
  }
}

function toggleProgression(index: number) {
  expandedIndex.value = expandedIndex.value === index ? null : index
}

/** 和弦进行字符串按 " - " 拆成单个和弦符号（与后端约定一致） */
function splitChordTokens(line: string) {
  return line
    .split(' - ')
    .map((t) => t.trim())
    .filter(Boolean)
}

function explainCacheKey(symbol: string) {
  return `${selectedKey.value}|${selectedLevel.value}|${symbol.trim()}`
}

function sleepMs(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    if (ms <= 0) {
      resolve()
      return
    }
    if (signal?.aborted) {
      resolve()
      return
    }
    const id = window.setTimeout(() => {
      signal?.removeEventListener('abort', onAbort)
      resolve()
    }, ms)
    const onAbort = () => {
      window.clearTimeout(id)
      signal?.removeEventListener('abort', onAbort)
      resolve()
    }
    signal?.addEventListener('abort', onAbort)
  })
}

function stopProgressionPlayback() {
  disarmProgressionBootstrapSpinner()
  progressionAbort?.abort()
  progressionAbort = null
  progressionPlayback.value = null
  progressionAudioBootstrappingLine.value = null
  stopChordPlayback()
}

async function fetchChordExplainPayload(
  symbol: string,
  forceRefresh = false,
): Promise<{ explain: ChordExplain; disclaimer: string }> {
  const s = symbol.trim()
  if (!s) throw new Error('和弦名为空')
  const body: Record<string, unknown> = {
    symbol: s,
    key: selectedKey.value,
    level: selectedLevel.value,
  }
  if (forceRefresh) body.force_refresh = true
  const resp = await fetch(apiUrl('/chords/explain'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
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
    explain?: ChordExplain
    disclaimer?: string
  }
  if (!data.explain || !Array.isArray(data.explain.frets)) {
    throw new Error('返回数据不完整')
  }
  return { explain: data.explain, disclaimer: data.disclaimer || '' }
}

async function runProgressionPlayback(lineIndex: number, signal: AbortSignal) {
  progressionError.value = ''
  disarmProgressionBootstrapSpinner()
  progressionAudioBootstrappingLine.value = lineIndex
  progressionBootstrapShowSpinner.value = false
  progressionBootstrapSpinnerDisarm = startChordSlowSpinnerTimer(() => {
    progressionBootstrapShowSpinner.value = true
  })
  const clearBootstrap = () => {
    disarmProgressionBootstrapSpinner()
    if (progressionAudioBootstrappingLine.value === lineIndex) {
      progressionAudioBootstrappingLine.value = null
    }
  }
  let firstChordAudioDone = false

  const line = progressions.value[lineIndex]
  if (!line) {
    clearBootstrap()
    return
  }
  const tokens = splitChordTokens(line.chords)
  if (!tokens.length) {
    clearBootstrap()
    return
  }

  const barMs = 240_000 / progressionBpm.value

  for (let ci = 0; ci < tokens.length; ci++) {
    if (signal.aborted) {
      clearBootstrap()
      return
    }
    progressionPlayback.value = { lineIndex, chordIndex: ci }
    const sym = tokens[ci]!
    const ckey = explainCacheKey(sym)
    let ex = explainCache.get(ckey)
    if (!ex) {
      try {
        const { explain } = await fetchChordExplainPayload(sym)
        ex = explain
        explainCache.set(ckey, ex)
      } catch (err) {
        progressionError.value =
          err instanceof Error
            ? `「${sym}」加载指法失败：${err.message}`
            : '加载指法失败'
        clearBootstrap()
        return
      }
    }
    if (!canPlayChordFrets(ex.frets)) {
      progressionError.value = `「${sym}」暂无可用指法试听`
      clearBootstrap()
      return
    }
    const t0 = performance.now()
    try {
      await playChordFromFrets(ex.frets, { variant: 'progression' })
    } finally {
      if (!firstChordAudioDone) {
        firstChordAudioDone = true
        clearBootstrap()
      }
    }
    if (signal.aborted) return
    const elapsed = performance.now() - t0
    await sleepMs(Math.max(0, barMs - elapsed), signal)
  }
}

async function togglePlayProgression(lineIndex: number) {
  if (progressionPlayback.value?.lineIndex === lineIndex && progressionAbort) {
    stopProgressionPlayback()
    return
  }
  stopProgressionPlayback()
  progressionError.value = ''
  const ac = new AbortController()
  progressionAbort = ac
  try {
    await runProgressionPlayback(lineIndex, ac.signal)
  } finally {
    if (progressionAbort === ac) {
      progressionAbort = null
      progressionPlayback.value = null
    }
  }
}

function closeChordSheet() {
  sheetOpen.value = false
  sheetLoading.value = false
  sheetError.value = ''
  sheetExplain.value = null
  sheetDisclaimer.value = ''
  sheetRecalibrating.value = false
  sheetRecalibrateError.value = ''
  sheetPreviewError.value = ''
  sheetChordAudioLoading.value = false
  disarmSheetChordSpinner()
}

async function onPreviewChordInSheet() {
  const ex = sheetExplain.value
  if (!ex || !canPlayChordFrets(ex.frets) || sheetChordAudioLoading.value) return
  sheetPreviewError.value = ''
  disarmSheetChordSpinner()
  sheetChordShowSlowSpinner.value = false
  sheetChordSpinnerDisarm = startChordSlowSpinnerTimer(() => {
    sheetChordShowSlowSpinner.value = true
  })
  sheetChordAudioLoading.value = true
  try {
    await playChordFromFrets(ex.frets)
  } catch (err) {
    sheetPreviewError.value =
      err instanceof Error ? err.message : '无法播放，请再试一次'
  } finally {
    disarmSheetChordSpinner()
    sheetChordAudioLoading.value = false
  }
}

/** 打开抽屉并请求 /chords/explain（可走缓存）；展示 ChordDiagram + 说明段落 */
async function openChordExplain(symbol: string) {
  const s = symbol.trim()
  if (!s) return
  stopProgressionPlayback()
  sheetSymbol.value = s
  sheetOpen.value = true
  sheetLoading.value = true
  sheetError.value = ''
  sheetExplain.value = null
  sheetDisclaimer.value = ''
  sheetRecalibrateError.value = ''
  sheetPreviewError.value = ''
  try {
    const { explain, disclaimer } = await fetchChordExplainPayload(s)
    sheetExplain.value = explain
    sheetDisclaimer.value = disclaimer
    explainCache.set(explainCacheKey(s), explain)
  } catch (err) {
    sheetError.value = err instanceof Error ? err.message : '加载失败'
  } finally {
    sheetLoading.value = false
  }
}

/** 同 openChordExplain，但 force_refresh 强制后端/AI 重新生成说明（忽略缓存） */
async function recalibrateChordExplain() {
  const s = sheetSymbol.value.trim()
  if (!s || sheetRecalibrating.value) return
  sheetRecalibrateError.value = ''
  sheetRecalibrating.value = true
  try {
    const { explain, disclaimer } = await fetchChordExplainPayload(s, true)
    sheetExplain.value = explain
    sheetDisclaimer.value = disclaimer
    explainCache.set(explainCacheKey(s), explain)
  } catch (err) {
    sheetRecalibrateError.value = err instanceof Error ? err.message : '校准失败'
  } finally {
    sheetRecalibrating.value = false
  }
}

// 首屏并行拉取风格、调号、难度
onMounted(async () => {
  try {
    await Promise.all([fetchStyles(), fetchKeys(), fetchLevels()])
  } catch (err) {
    errorMessage.value = err instanceof Error ? err.message : '加载风格失败'
  }
})
</script>

<style scoped>
/* 布局：外层居中 + 主卡片；下方大块为结果列表与和弦 token 样式；sheet-* 为底部抽屉 */

.tech-wrap {
  width: 100%;
  display: flex;
  justify-content: center;
  padding: 40px 16px calc(40px + 56px + env(safe-area-inset-bottom, 0px));
  box-sizing: border-box;
}

.tech-card {
  width: 520px;
  max-width: 100%;
  text-align: left;

  padding: 18px 18px 16px;
  border-radius: 16px;
  border: 1px solid #e5e5e5;
  background: #ffffff;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.06);
}

.tech-title {
  font-size: 18px;
  font-weight: 800;
  letter-spacing: 0.3px;
  margin-bottom: 12px;
  color: #111111;
}

.section-label {
  font-size: 13px;
  font-weight: 700;
  color: rgba(17, 17, 17, 0.84);
  margin-bottom: 8px;
}

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-bottom: 18px;
}

.level-chips {
  margin-bottom: 12px;
}

.level-chip {
  font-size: 13px;
}

.key-chips {
  margin-bottom: 14px;
}

.key-chip {
  min-width: 2.25rem;
  text-align: center;
  padding-left: 10px;
  padding-right: 10px;
}

.chip {
  padding: 9px 12px;
  border-radius: 999px;
  border: 1px solid #e5e5e5;
  background: #f3f3f3;
  color: #111111;
  cursor: pointer;
  transition: 0.15s ease;
  font-size: 14px;
}

.chip:hover {
  background: #ededed;
}

.chip.active {
  border-color: #111111;
  background: #111111;
  color: #ffffff;
}

.generate-btn {
  width: 100%;
  padding: 12px 16px;
  border-radius: 12px;
  border: 1px solid #111111;
  cursor: pointer;
  font-weight: 800;
  font-size: 16px;
  color: #ffffff;
  background: #111111;
  transition: 0.15s ease;
}

.generate-btn:hover {
  background: #000000;
}

.generate-btn:focus-visible {
  outline: 2px solid #111111;
  outline-offset: 3px;
}

@media (prefers-color-scheme: dark) {
  .tech-card {
    border-color: rgba(255, 255, 255, 0.14);
    background: rgba(15, 15, 18, 0.96);
    box-shadow: 0 14px 46px rgba(0, 0, 0, 0.45);
  }

  .tech-title {
    color: #f8f8f8;
  }

  .section-label {
    color: rgba(248, 248, 248, 0.72);
  }

  .chip {
    border-color: rgba(255, 255, 255, 0.16);
    background: rgba(255, 255, 255, 0.06);
    color: #f8f8f8;
  }

  .chip:hover {
    background: rgba(255, 255, 255, 0.10);
  }

  .chip.active {
    border-color: #ffffff;
    background: #ffffff;
    color: #0b0b0f;
  }

  .generate-btn {
    border-color: #ffffff;
    background: #ffffff;
    color: #0b0b0f;
  }

  .generate-btn:hover {
    background: rgba(255, 255, 255, 0.92);
  }

  .generate-btn:focus-visible {
    outline: 2px solid rgba(255, 255, 255, 0.9);
  }
}

.result {
  margin-top: 14px;
  padding-top: 14px;
  border-top: 1px solid rgba(0, 0, 0, 0.06);
}

.result-head {
  font-size: 13px;
  font-weight: 700;
  color: #111111;
  margin-bottom: 10px;
}

.playback-toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px 12px;
  margin-bottom: 10px;
  padding: 8px 10px;
  border-radius: 10px;
  background: rgba(0, 0, 0, 0.03);
  border: 1px solid rgba(0, 0, 0, 0.06);
}

.playback-toolbar-label {
  font-size: 12px;
  font-weight: 700;
  color: rgba(17, 17, 17, 0.8);
}

.playback-toolbar-hint {
  font-size: 11px;
  color: rgba(17, 17, 17, 0.68);
  flex-basis: 100%;
}

.bpm-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.bpm-chip {
  min-width: 2.5rem;
  padding: 5px 10px;
  border-radius: 999px;
  border: 1px solid #e5e5e5;
  background: #f8f8f8;
  font-size: 12px;
  font-weight: 700;
  cursor: pointer;
  color: #111111;
}

.bpm-chip:hover {
  background: #efefef;
}

.bpm-chip.active {
  border-color: #111111;
  background: #111111;
  color: #ffffff;
}

.progression-err {
  margin: 0 0 8px;
  font-size: 12px;
  line-height: 1.45;
  color: #b42318;
}

.result-loading,
.result-empty {
  font-size: 13px;
  color: rgba(17, 17, 17, 0.76);
  padding: 10px 0 2px;
}

.progressions {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.progression-item {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 10px 12px;
  border-radius: 12px;
  border: 1px solid rgba(0, 0, 0, 0.06);
  background: rgba(0, 0, 0, 0.02);
  cursor: pointer;
  transition: border-color 0.15s ease, background 0.15s ease;
}

.progression-item.is-playing-line {
  border-color: rgba(17, 113, 182, 0.45);
  background: rgba(17, 113, 182, 0.06);
}

.prog-play-btn {
  flex-shrink: 0;
  margin-top: 1px;
  padding: 4px 10px;
  border-radius: 8px;
  border: 1px solid rgba(17, 17, 17, 0.2);
  background: #ffffff;
  font-size: 12px;
  font-weight: 800;
  cursor: pointer;
  color: #111111;
}

.prog-play-btn:hover {
  background: rgba(0, 0, 0, 0.04);
}

.prog-play-btn.active {
  border-color: #b42318;
  background: rgba(180, 35, 24, 0.08);
  color: #8f1d12;
}

.prog-wrap {
  flex: 1;
}

.tip {
  display: block;
  margin-top: 6px;
  font-size: 12px;
  color: rgba(17, 17, 17, 0.74);
}

.songs {
  margin: 8px 0 0 0;
  padding-left: 18px;
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-size: 13px;
}

.song-empty {
  color: rgba(17, 17, 17, 0.74);
}

.progression-item.expanded {
  border-color: rgba(17, 17, 17, 0.18);
  background: rgba(17, 17, 17, 0.05);
}

.num {
  width: 28px;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  color: rgba(17, 17, 17, 0.72);
  font-size: 13px;
}

.prog {
  font-weight: 700;
  font-size: 14px;
  color: #111111;
}

.chord-line {
  display: inline;
  line-height: 1.5;
}

.chord-sep {
  font-weight: 600;
  color: rgba(17, 17, 17, 0.62);
}

.chord-token {
  display: inline;
  margin: 0;
  padding: 0 2px;
  border: none;
  background: transparent;
  font: inherit;
  font-weight: 800;
  color: inherit;
  cursor: pointer;
  text-decoration: underline;
  text-decoration-color: rgba(17, 17, 17, 0.35);
  text-underline-offset: 3px;
}

.chord-token:hover {
  text-decoration-color: rgba(17, 17, 17, 0.65);
}

.chord-token:focus-visible {
  outline: 2px solid #111111;
  outline-offset: 2px;
  border-radius: 4px;
}

.chord-token--playing {
  text-decoration: none;
  background: rgba(17, 113, 182, 0.2);
  border-radius: 4px;
  padding: 0 4px;
  margin: 0 -2px;
  box-decoration-break: clone;
  -webkit-box-decoration-break: clone;
}

.sheet-backdrop {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background: rgba(0, 0, 0, 0.45);
  display: flex;
  align-items: flex-end;
  justify-content: center;
  padding: 0;
}

.sheet-panel {
  width: 100%;
  max-width: 520px;
  max-height: 78vh;
  overflow: auto;
  border-radius: 16px 16px 0 0;
  background: #ffffff;
  border: 1px solid rgba(0, 0, 0, 0.08);
  border-bottom: none;
  box-shadow: 0 -8px 40px rgba(0, 0, 0, 0.12);
  padding: 0 16px 20px;
  box-sizing: border-box;
}

.sheet-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 14px 0 10px;
  position: sticky;
  top: 0;
  background: #ffffff;
  z-index: 1;
}

.sheet-title {
  font-size: 16px;
  font-weight: 800;
  color: #111111;
}

.sheet-close {
  border: none;
  background: rgba(0, 0, 0, 0.06);
  width: 36px;
  height: 36px;
  border-radius: 10px;
  font-size: 22px;
  line-height: 1;
  cursor: pointer;
  color: #111111;
}

.sheet-close:hover {
  background: rgba(0, 0, 0, 0.1);
}

.sheet-loading,
.sheet-error {
  padding: 24px 0 32px;
  font-size: 14px;
  color: rgba(17, 17, 17, 0.65);
  text-align: center;
}

.sheet-error {
  color: #b42318;
}

.sheet-body {
  padding-bottom: 8px;
}

.sheet-section {
  margin-top: 14px;
}

.sheet-h {
  margin: 0 0 6px;
  font-size: 12px;
  font-weight: 800;
  letter-spacing: 0.02em;
  color: rgba(17, 17, 17, 0.72);
  text-transform: uppercase;
}

.sheet-notes {
  margin: 0;
  font-size: 15px;
  font-weight: 700;
  color: #111111;
}

.sheet-p {
  margin: 0;
  font-size: 14px;
  line-height: 1.55;
  color: rgba(17, 17, 17, 0.88);
  white-space: pre-wrap;
}

.sheet-actions {
  margin-top: 18px;
  padding-top: 14px;
  border-top: 1px solid rgba(0, 0, 0, 0.08);
}

.sheet-play {
  width: 100%;
  padding: 11px 14px;
  margin-bottom: 10px;
  border-radius: 12px;
  border: 1px solid #111111;
  background: #111111;
  color: #ffffff;
  font-size: 14px;
  font-weight: 800;
  cursor: pointer;
  transition: background 0.15s ease, border-color 0.15s ease;
}

.sheet-play:hover:not(:disabled) {
  background: #000000;
  border-color: #000000;
}

.sheet-play:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.sheet-preview-err {
  margin: 0 0 10px;
  font-size: 13px;
  color: #b42318;
  line-height: 1.45;
}

.sheet-recalibrate {
  width: 100%;
  padding: 11px 14px;
  border-radius: 12px;
  border: 1px solid rgba(17, 17, 17, 0.22);
  background: rgba(0, 0, 0, 0.03);
  color: #111111;
  font-size: 14px;
  font-weight: 700;
  cursor: pointer;
  transition: background 0.15s ease, border-color 0.15s ease;
}

.sheet-recalibrate:hover:not(:disabled) {
  background: rgba(0, 0, 0, 0.06);
  border-color: rgba(17, 17, 17, 0.35);
}

.sheet-recalibrate:disabled {
  opacity: 0.65;
  cursor: not-allowed;
}

.sheet-recalibrate-err {
  margin: 10px 0 0;
  font-size: 13px;
  color: #b42318;
  line-height: 1.45;
}

.sheet-disclaimer {
  margin: 18px 0 0;
  font-size: 12px;
  line-height: 1.45;
  color: rgba(17, 17, 17, 0.7);
}

@media (prefers-color-scheme: dark) {
  .result {
    border-top-color: rgba(255, 255, 255, 0.12);
  }

  .result-head {
    color: #f8f8f8;
  }

  .playback-toolbar {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.12);
  }

  .playback-toolbar-label {
    color: rgba(248, 248, 248, 0.84);
  }

  .playback-toolbar-hint {
    color: rgba(248, 248, 248, 0.74);
  }

  .bpm-chip {
    border-color: rgba(255, 255, 255, 0.18);
    background: rgba(255, 255, 255, 0.08);
    color: #f8f8f8;
  }

  .bpm-chip:hover {
    background: rgba(255, 255, 255, 0.12);
  }

  .bpm-chip.active {
    border-color: #ffffff;
    background: #ffffff;
    color: #0b0b0f;
  }

  .progression-err {
    color: #ff8a80;
  }

  .result-loading,
  .result-empty {
    color: rgba(248, 248, 248, 0.84);
  }

  .progression-item {
    border-color: rgba(255, 255, 255, 0.12);
    background: rgba(255, 255, 255, 0.06);
  }

  .progression-item.expanded {
    border-color: rgba(255, 255, 255, 0.22);
    background: rgba(255, 255, 255, 0.1);
  }

  .progression-item.is-playing-line {
    border-color: rgba(100, 181, 246, 0.55);
    background: rgba(100, 181, 246, 0.1);
  }

  .prog-play-btn {
    border-color: rgba(255, 255, 255, 0.22);
    background: rgba(255, 255, 255, 0.08);
    color: #f8f8f8;
  }

  .prog-play-btn:hover {
    background: rgba(255, 255, 255, 0.12);
  }

  .prog-play-btn.active {
    border-color: #ff8a80;
    background: rgba(255, 138, 128, 0.12);
    color: #ffc4bd;
  }

  .num {
    color: rgba(248, 248, 248, 0.82);
  }

  .prog {
    color: #f8f8f8;
  }

  .chord-sep {
    color: rgba(248, 248, 248, 0.74);
  }

  .chord-token {
    text-decoration-color: rgba(248, 248, 248, 0.35);
  }

  .chord-token:hover {
    text-decoration-color: rgba(248, 248, 248, 0.65);
  }

  .chord-token:focus-visible {
    outline-color: rgba(255, 255, 255, 0.9);
  }

  .chord-token--playing {
    background: rgba(100, 181, 246, 0.28);
  }

  .sheet-panel {
    background: rgba(18, 18, 22, 0.98);
    border-color: rgba(255, 255, 255, 0.12);
    box-shadow: 0 -8px 40px rgba(0, 0, 0, 0.55);
  }

  .sheet-head {
    background: rgba(18, 18, 22, 0.98);
  }

  .sheet-title {
    color: #f8f8f8;
  }

  .sheet-close {
    background: rgba(255, 255, 255, 0.1);
    color: #f8f8f8;
  }

  .sheet-close:hover {
    background: rgba(255, 255, 255, 0.16);
  }

  .sheet-loading,
  .sheet-error {
    color: rgba(248, 248, 248, 0.7);
  }

  .sheet-error {
    color: #ff8a80;
  }

  .sheet-h {
    color: rgba(248, 248, 248, 0.8);
  }

  .sheet-notes {
    color: #f8f8f8;
  }

  .sheet-p {
    color: rgba(248, 248, 248, 0.9);
  }

  .sheet-actions {
    border-top-color: rgba(255, 255, 255, 0.12);
  }

  .sheet-play {
    border-color: #ffffff;
    background: #ffffff;
    color: #0b0b0f;
  }

  .sheet-play:hover:not(:disabled) {
    background: rgba(255, 255, 255, 0.92);
    border-color: rgba(255, 255, 255, 0.92);
  }

  .sheet-preview-err {
    color: #ff8a80;
  }

  .sheet-recalibrate {
    border-color: rgba(255, 255, 255, 0.22);
    background: rgba(255, 255, 255, 0.06);
    color: #f8f8f8;
  }

  .sheet-recalibrate:hover:not(:disabled) {
    background: rgba(255, 255, 255, 0.1);
    border-color: rgba(255, 255, 255, 0.35);
  }

  .sheet-recalibrate-err {
    color: #ff8a80;
  }

  .sheet-disclaimer {
    color: rgba(248, 248, 248, 0.74);
  }

  .tip {
    color: rgba(248, 248, 248, 0.84);
  }

  .song-empty {
    color: rgba(248, 248, 248, 0.84);
  }
}
</style>


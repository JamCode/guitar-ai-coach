<template>
  <div class="ear-wrap">
    <div class="ear-card">
      <div class="lang-panels">
        <section class="lang-panel" aria-labelledby="ear-hero-en">
          <h2 id="ear-hero-en" class="lang-panel__label">English</h2>
          <h1 class="lang-panel__title">Ear training</h1>
          <p class="lang-panel__note">Chord and progression drills in the browser.</p>
        </section>
        <section class="lang-panel" lang="zh-Hans" aria-labelledby="ear-hero-zh">
          <h2 id="ear-hero-zh" class="lang-panel__label">中文</h2>
          <h1 class="lang-panel__title">练耳训练</h1>
          <p class="lang-panel__note">网页和弦练耳与单音练耳。</p>
        </section>
      </div>
      <div class="track-tabs">
        <button
          type="button"
          class="track-tab track-tab-bi"
          :class="{ active: activeTrack === 'legacy' }"
          @click="activeTrack = 'legacy'"
        >
          <span class="bi-pair" lang="en">Chord ear training</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">和弦练耳</span>
        </button>
        <button
          type="button"
          class="track-tab track-tab-bi"
          :class="{ active: activeTrack === 'single_note' }"
          @click="activeTrack = 'single_note'"
        >
          <span class="bi-pair" lang="en">Single-note (new)</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">单音练耳（新）</span>
        </button>
      </div>

      <template v-if="activeTrack === 'legacy'">
      <section v-if="stage === 'setup'" class="ear-section">
        <div class="section-bi-h">
          <p class="bi-pair" lang="en">Choose mode</p>
          <p class="bi-pair bi-pair--zh" lang="zh-Hans">模式选择</p>
        </div>
        <div class="mode-list">
          <button
            v-for="m in modes"
            :key="m.id"
            type="button"
            class="mode-item"
            :class="{ active: mode === m.id }"
            @click="mode = m.id"
          >
            <strong>
              <span class="bi-pair" lang="en">{{ m.titleEn }}</span>
              <span class="bi-pair bi-pair--zh" lang="zh-Hans">{{ m.titleZh }}</span>
            </strong>
            <span class="mode-item-desc">
              <span class="bi-pair" lang="en">{{ m.descEn }}</span>
              <span class="bi-pair bi-pair--zh" lang="zh-Hans">{{ m.descZh }}</span>
            </span>
          </button>
        </div>
        <button type="button" class="btn-primary btn-bi" :disabled="busy" @click="startSession">
          <span class="bi-pair" lang="en">Start</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">开始训练</span>
        </button>
        <button
          v-if="mode === 'C'"
          type="button"
          class="btn-secondary btn-bi"
          :disabled="busy"
          @click="refreshDailySet"
        >
          <span class="bi-pair" lang="en">Regenerate today’s set</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">重置今日题单</span>
        </button>
        <p v-if="dailyInfo && mode === 'C'" class="muted-line muted-line--bi">
          <span class="bi-pair" lang="en"
            >Today’s set: {{ dailyInfo.question_ids.length }} items ({{ dailyInfo.day_date }})</span
          >
          <span class="bi-pair bi-pair--zh" lang="zh-Hans"
            >今日题单：{{ dailyInfo.question_ids.length }} 题（{{ dailyInfo.day_date }}）</span
          >
        </p>
        <div v-if="errorMsg" class="err-block" role="alert">
          <p class="bi-pair" lang="en">Error</p>
          <p class="bi-pair bi-pair--zh" lang="zh-Hans">错误</p>
          <p class="err err-msg">{{ errorMsg }}</p>
        </div>
      </section>

      <section v-else-if="stage === 'quiz'" class="ear-section">
        <div class="section-bi-h">
          <p class="bi-pair" lang="en">In session</p>
          <p class="bi-pair bi-pair--zh" lang="zh-Hans">答题中</p>
        </div>
        <p class="progress progress--bi">
          <span class="bi-pair" lang="en"
            >Answered {{ answered }} · Correct {{ correct
            }}<span v-if="attempt?.mode === 'C'"> · Daily goal: 10</span></span
          >
          <span class="bi-pair bi-pair--zh" lang="zh-Hans"
            >已完成 {{ answered }} 题 · 答对 {{ correct }} 题<span v-if="attempt?.mode === 'C'">
              · 今日目标 10 题</span
            ></span
          >
        </p>
        <div class="stem-head">
          <p class="bi-pair" lang="en">Question (prompt is in Chinese)</p>
          <p class="bi-pair bi-pair--zh" lang="zh-Hans">题目</p>
        </div>
        <p class="stem">{{ question?.prompt_zh }}</p>
        <div class="audio-row">
          <button type="button" class="btn-secondary small btn-bi" @click="playEarAudio">
            <span class="bi-pair" lang="en">Play audio</span>
            <span class="bi-pair bi-pair--zh" lang="zh-Hans">播放音频</span>
          </button>
          <button type="button" class="btn-secondary small btn-bi" @click="playEarSlowAudio">
            <span class="bi-pair" lang="en">Replay 0.8×</span>
            <span class="bi-pair bi-pair--zh" lang="zh-Hans">0.8x 重听</span>
          </button>
        </div>

        <div v-if="question" class="options">
          <button
            v-for="opt in question.options"
            :key="opt.key"
            type="button"
            class="option"
            :disabled="busy || reveal"
            :class="{
              selected: selectedOptionKey === opt.key,
              correct: reveal && feedback?.correct_option_key === opt.key,
              wrong: reveal && selectedOptionKey === opt.key && feedback?.correct_option_key !== opt.key,
            }"
            @click="selectedOptionKey = opt.key"
          >
            <span class="option-key">{{ opt.key }}</span>
            <span class="option-label">{{ opt.label }}</span>
          </button>
        </div>

        <div
          v-if="reveal && feedback"
          :class="feedback.is_correct ? 'ok' : 'err'"
          class="feedback feedback--bi"
        >
          <template v-if="feedback.is_correct">
            <p class="bi-pair" lang="en">
              Correct: {{ feedback.correct_option_key }} — {{ feedback.correct_option_label }}
            </p>
            <p class="bi-pair bi-pair--zh" lang="zh-Hans">
              回答正确：{{ feedback.correct_option_key }} — {{ feedback.correct_option_label }}
            </p>
          </template>
          <template v-else>
            <p class="bi-pair" lang="en">
              Incorrect. Correct answer: {{ feedback.correct_option_key }} —
              {{ feedback.correct_option_label }}
            </p>
            <p class="bi-pair bi-pair--zh" lang="zh-Hans">
              回答错误：正确答案是 {{ feedback.correct_option_key }} — {{ feedback.correct_option_label }}
            </p>
          </template>
        </div>
        <div v-if="reveal && feedback && (answerTruthEn || answerTruthLine)" class="answer-truth-box">
          <p v-if="answerTruthEn" class="bi-pair" lang="en">{{ answerTruthEn }}</p>
          <p v-if="answerTruthLine" class="bi-pair bi-pair--zh" lang="zh-Hans">{{ answerTruthLine }}</p>
        </div>

        <button
          type="button"
          class="btn-primary btn-bi"
          :disabled="busy || !selectedOptionKey || reveal"
          @click="submitAnswer"
        >
          <span class="bi-pair" lang="en">Submit</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">提交答案</span>
        </button>
        <button v-if="reveal" type="button" class="btn-primary btn-bi" :disabled="busy" @click="nextQuestion">
          <span class="bi-pair" lang="en">Next</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">下一题</span>
        </button>
        <button type="button" class="btn-secondary btn-bi" :disabled="busy" @click="finishSession">
          <span class="bi-pair" lang="en">End &amp; see results</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">结束并查看结果</span>
        </button>
        <div v-if="errorMsg" class="err-block" role="alert">
          <p class="bi-pair" lang="en">Error</p>
          <p class="bi-pair bi-pair--zh" lang="zh-Hans">错误</p>
          <p class="err err-msg">{{ errorMsg }}</p>
        </div>
      </section>

      <section v-else class="ear-section">
        <div class="section-bi-h">
          <p class="bi-pair" lang="en">Session results</p>
          <p class="bi-pair bi-pair--zh" lang="zh-Hans">训练结果</p>
        </div>
        <p class="result-line result-line--bi">
          <span class="bi-pair" lang="en"
            >This session (mode {{ summary?.mode }}): {{ summary?.total_correct || 0 }}/{{
              summary?.total_answered || 0
            }}
            ({{ formatPercent(summary?.accuracy || 0) }})</span
          >
          <span class="bi-pair bi-pair--zh" lang="zh-Hans"
            >本次 {{ summary?.mode }} 模式：{{ summary?.total_correct || 0 }}/{{
              summary?.total_answered || 0
            }}
            （{{ formatPercent(summary?.accuracy || 0) }}）</span
          >
        </p>
        <p class="muted-line muted-line--bi">
          <span class="bi-pair" lang="en">Learner: {{ learnerId.slice(0, 12) }}…</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">学习者：{{ learnerId.slice(0, 12) }}…</span>
        </p>

        <div v-if="summary?.by_mode_stats?.length" class="box">
          <h3 class="box-h-bi">
            <span class="bi-pair" lang="en">By dimension</span>
            <span class="bi-pair bi-pair--zh" lang="zh-Hans">维度表现</span>
          </h3>
          <ul>
            <li v-for="s in summary?.by_mode_stats ?? []" :key="s.mode" class="li-bi">
              <span class="bi-pair" lang="en"
                >{{ earModeBilingual(s.mode).en }}: {{ s.right_count }}/{{ s.total_count }} ({{
                  formatPercent(s.accuracy)
                }})</span
              >
              <span class="bi-pair bi-pair--zh" lang="zh-Hans"
                >{{ earModeBilingual(s.mode).zh }}：{{ s.right_count }}/{{ s.total_count }}（{{
                  formatPercent(s.accuracy)
                }}）</span
              >
            </li>
          </ul>
        </div>

        <div v-if="summary?.wrongs?.length" class="box">
          <h3 class="box-h-bi">
            <span class="bi-pair" lang="en">Review mistakes (Chinese prompts)</span>
            <span class="bi-pair bi-pair--zh" lang="zh-Hans">错题回顾</span>
          </h3>
          <ul>
            <li v-for="(w, idx) in (summary?.wrongs ?? []).slice(0, 10)" :key="idx">
              {{ w.prompt_zh }}（正确：{{ w.correct_option_label }}）
            </li>
          </ul>
        </div>

        <button type="button" class="btn-primary btn-bi" :disabled="busy" @click="startSession">
          <span class="bi-pair" lang="en">Continue</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">继续训练</span>
        </button>
        <button type="button" class="btn-secondary btn-bi" :disabled="busy" @click="fetchMistakes">
          <span class="bi-pair" lang="en">Mistake list</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">查看错题本</span>
        </button>
        <button type="button" class="btn-secondary btn-bi" :disabled="busy" @click="resetAll">
          <span class="bi-pair" lang="en">Back to mode selection</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">返回模式选择</span>
        </button>

        <div v-if="mistakes.length" class="box">
          <h3 class="box-h-bi">
            <span class="bi-pair" lang="en">Mistake list (recent)</span>
            <span class="bi-pair bi-pair--zh" lang="zh-Hans">错题本（最近）</span>
          </h3>
          <ul>
            <li v-for="m in mistakes.slice(0, 10)" :key="m.question_id">
              {{ m.prompt_zh }} · 错{{ m.wrong_count }}次 · 状态{{ m.status }}
            </li>
          </ul>
        </div>
        <div v-if="errorMsg" class="err-block" role="alert">
          <p class="bi-pair" lang="en">Error</p>
          <p class="bi-pair bi-pair--zh" lang="zh-Hans">错误</p>
          <p class="err err-msg">{{ errorMsg }}</p>
        </div>
      </section>
      </template>
      <SingleNoteEarTrainer v-else />
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onUnmounted, ref } from 'vue'
import SingleNoteEarTrainer from '../components/SingleNoteEarTrainer.vue'
import { playChordFromFrets, stopChordPlayback } from '../chordAudioLazy'
import { canPlayChordFrets } from '../chordFretUtils'
import { earRomanProgressionToSymbols, normalizeEarKey } from '../earRomanToSymbols'
import { selectedKey, selectedLevel } from '../session'

type Mode = 'A' | 'B' | 'C'
type EarQuestion = {
  question_id: string
  mode: Mode
  question_type: string
  difficulty: string
  prompt_zh: string
  hint_zh?: string
  chord_symbol?: string
  music_key?: string
  progression_roman?: string
  audio_ref?: Record<string, unknown> | null
  options: Array<{ key: 'A' | 'B' | 'C' | 'D'; label: string }>
}

type ChordExplain = {
  symbol: string
  frets: number[]
}
type EarFeedback = {
  question_id: string
  is_correct: boolean
  correct_option_key: 'A' | 'B' | 'C' | 'D'
  correct_option_label: string
  chord_symbol?: string
  music_key?: string
  progression_roman?: string
}
type EarSummary = {
  attempt_id: number
  mode: Mode
  total_answered: number
  total_correct: number
  accuracy: number
  by_mode_stats: Array<{ mode: string; right_count: number; total_count: number; accuracy: number }>
  wrongs: Array<{ prompt_zh: string; correct_option_label: string }>
}
type DailySet = { daily_set_id: number; day_date: string; question_ids: string[] }

const apiBase = (import.meta.env.VITE_API_BASE_URL || '/api').replace(/\/$/, '')
const apiUrl = (path: string) => `${apiBase}${path.startsWith('/') ? path : `/${path}`}`

const LEARNER_KEY = 'guitar_ai_coach_learner_id_v1'
function getLearnerId() {
  const old = window.localStorage.getItem(LEARNER_KEY)
  if (old) return old
  const id = `anon_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`
  window.localStorage.setItem(LEARNER_KEY, id)
  return id
}

const learnerId = getLearnerId()
const modes = [
  {
    id: 'A' as Mode,
    titleEn: 'A · Single chord',
    titleZh: 'A 单和弦听辨',
    descEn: 'Major, minor, dominant 7',
    descZh: '大三 / 小三 / 属七',
  },
  {
    id: 'B' as Mode,
    titleEn: 'B · Progression',
    titleZh: 'B 常见进行听辨',
    descEn: '2–4 chord progressions',
    descZh: '2~4 和弦进行识别',
  },
  {
    id: 'C' as Mode,
    titleEn: 'C · Daily 10',
    titleZh: 'C 每日 10 题',
    descEn: '6 review + 2 weak + 2 warm-up',
    descZh: '6错题+2薄弱+2保温',
  },
]

function earModeBilingual(mode: string): { en: string; zh: string } {
  const map: Record<string, { en: string; zh: string }> = {
    A: { en: 'Mode A · Single chord', zh: 'A 单和弦听辨' },
    B: { en: 'Mode B · Progression', zh: 'B 常见进行听辨' },
    C: { en: 'Mode C · Daily 10', zh: 'C 每日 10 题' },
  }
  return map[mode] ?? { en: mode, zh: mode }
}

const mode = ref<Mode>('A')
const stage = ref<'setup' | 'quiz' | 'result'>('setup')
const busy = ref(false)
const errorMsg = ref('')
const attempt = ref<{ attempt_id: number; mode: Mode } | null>(null)
const question = ref<EarQuestion | null>(null)
const selectedOptionKey = ref<'A' | 'B' | 'C' | 'D' | null>(null)
const reveal = ref(false)
const feedback = ref<EarFeedback | null>(null)
const summary = ref<EarSummary | null>(null)
const answered = ref(0)
const correct = ref(0)
const mistakes = ref<Array<{ question_id: string; prompt_zh: string; wrong_count: number; status: string }>>([])
const dailyInfo = ref<DailySet | null>(null)
const activeTrack = ref<'legacy' | 'single_note'>('legacy')

const answerTruthLine = computed(() => {
  const f = feedback.value
  if (!f) return ''
  const cs = f.chord_symbol?.trim()
  if (cs) {
    return `标准答案和弦：${cs}`
  }
  const mk = f.music_key?.trim()
  const roman = f.progression_roman?.trim()
  if (mk && roman) {
    try {
      const syms = earRomanProgressionToSymbols(roman, normalizeEarKey(mk))
      return `标准答案进行：${mk} 调 · ${roman}（${syms.join(' → ')}）`
    } catch {
      return `标准答案进行：${mk} 调 · ${roman}`
    }
  }
  return ''
})

const answerTruthEn = computed(() => {
  const f = feedback.value
  if (!f) return ''
  const cs = f.chord_symbol?.trim()
  if (cs) {
    return `Reference chord: ${cs}`
  }
  const mk = f.music_key?.trim()
  const roman = f.progression_roman?.trim()
  if (mk && roman) {
    try {
      const syms = earRomanProgressionToSymbols(roman, normalizeEarKey(mk))
      return `Reference progression: ${mk} · ${roman} (${syms.join(' → ')})`
    } catch {
      return `Reference progression: ${mk} · ${roman}`
    }
  }
  return ''
})

const explainCache = new Map<string, ChordExplain>()
let earPlayAbort: AbortController | null = null

function clearExplainCache() {
  explainCache.clear()
}

function stopAllEarPlayback() {
  earPlayAbort?.abort()
  earPlayAbort = null
  stopChordPlayback()
}

/** 与和弦速查一致：无题目调号时用全站「目标调」；B 题用题目 music_key。 */
function voicingKeyForQuestion(q: EarQuestion): string {
  const mk = q.music_key?.trim()
  if (mk) return normalizeEarKey(mk)
  return selectedKey.value
}

function explainCacheKey(voicingKey: string, symbol: string): string {
  return `${voicingKey}|${selectedLevel.value}|${symbol.trim()}`
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

async function fetchChordExplainPayload(symbol: string, voicingKey: string): Promise<ChordExplain> {
  const s = symbol.trim()
  if (!s) throw new Error('和弦名为空')
  const resp = await fetch(apiUrl('/chords/explain'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      symbol: s,
      key: voicingKey,
      level: selectedLevel.value,
    }),
  })
  const data = (await resp.json().catch(() => ({}))) as {
    explain?: ChordExplain
    error?: string
    message?: string
    detail?: string
  }
  if (!resp.ok) {
    const msg =
      data.detail ||
      data.message ||
      data.error ||
      `请求和弦指法失败（HTTP ${resp.status}）`
    throw new Error(msg)
  }
  if (!data.explain || !Array.isArray(data.explain.frets) || data.explain.frets.length !== 6) {
    throw new Error('返回数据不完整')
  }
  return data.explain
}

async function playSingleChordQuestion(q: EarQuestion, _rate: number, signal: AbortSignal) {
  const sym = (q.chord_symbol || '').trim()
  if (!sym) throw new Error('缺少和弦符号')
  const vk = voicingKeyForQuestion(q)
  const ck = explainCacheKey(vk, sym)
  let ex = explainCache.get(ck)
  if (!ex) {
    ex = await fetchChordExplainPayload(sym, vk)
    explainCache.set(ck, ex)
  }
  if (signal.aborted) return
  if (!canPlayChordFrets(ex.frets)) throw new Error('暂无可用指法试听')
  await playChordFromFrets(ex.frets)
}

async function playProgressionQuestion(q: EarQuestion, rate: number, signal: AbortSignal) {
  const mk = (q.music_key || '').trim()
  const roman = (q.progression_roman || '').trim()
  if (!mk || !roman) throw new Error('缺少调号或进行')
  const vk = normalizeEarKey(mk)
  const symbols = earRomanProgressionToSymbols(roman, vk)
  const bpmRaw =
    q.audio_ref && typeof q.audio_ref['tempo_bpm'] === 'number'
      ? (q.audio_ref['tempo_bpm'] as number)
      : 78
  const barMs = 240_000 / (bpmRaw * rate)

  for (let ci = 0; ci < symbols.length; ci++) {
    if (signal.aborted) return
    const sym = symbols[ci]!
    const ck = explainCacheKey(vk, sym)
    let ex = explainCache.get(ck)
    if (!ex) {
      ex = await fetchChordExplainPayload(sym, vk)
      explainCache.set(ck, ex)
    }
    if (signal.aborted) return
    if (!canPlayChordFrets(ex.frets)) {
      throw new Error(`「${sym}」暂无可用指法试听`)
    }
    const t0 = performance.now()
    await playChordFromFrets(ex.frets, { variant: 'progression' })
    if (signal.aborted) return
    const elapsed = performance.now() - t0
    await sleepMs(Math.max(0, barMs - elapsed), signal)
  }
}

async function playEarAtRate(rate: number) {
  const q = question.value
  if (!q) return
  stopAllEarPlayback()
  const ac = new AbortController()
  earPlayAbort = ac
  const signal = ac.signal
  try {
    if (q.progression_roman && q.music_key) {
      await playProgressionQuestion(q, rate, signal)
    } else if (q.chord_symbol) {
      await playSingleChordQuestion(q, rate, signal)
    } else {
      errorMsg.value = '本题缺少和弦符号或调内进行数据，无法试听。'
      return
    }
  } catch (e) {
    if (signal.aborted) return
    errorMsg.value = e instanceof Error ? e.message : '播放失败'
  } finally {
    if (earPlayAbort === ac) {
      earPlayAbort = null
    }
  }
}

async function playEarAudio() {
  errorMsg.value = ''
  await playEarAtRate(1)
}

async function playEarSlowAudio() {
  errorMsg.value = ''
  await playEarAtRate(0.8)
}

function formatPercent(n: number) {
  return `${Math.round(n * 100)}%`
}

async function refreshDailySet() {
  errorMsg.value = ''
  busy.value = true
  try {
    const resp = await fetch(apiUrl('/ear/daily/generate'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ learner_id: learnerId, force_regenerate: true }),
    })
    const data = (await resp.json()) as DailySet & { detail?: string }
    if (!resp.ok) throw new Error(data.detail || `生成题单失败（HTTP ${resp.status}）`)
    dailyInfo.value = data
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '生成题单失败'
  } finally {
    busy.value = false
  }
}

async function startSession() {
  errorMsg.value = ''
  busy.value = true
  try {
    if (mode.value === 'C') {
      const today = await fetch(apiUrl(`/ear/daily/today?learner_id=${encodeURIComponent(learnerId)}`))
      const todayData = (await today.json()) as DailySet
      if (today.ok) dailyInfo.value = todayData
    }
    const resp = await fetch(
      apiUrl(`/ear/train/start?mode=${mode.value}&learner_id=${encodeURIComponent(learnerId)}`),
    )
    const data = (await resp.json()) as {
      attempt?: { attempt_id: number; mode: Mode }
      question?: EarQuestion | null
      detail?: string
    }
    if (!resp.ok) throw new Error(data.detail || `启动失败（HTTP ${resp.status}）`)
    attempt.value = data.attempt || null
    stopAllEarPlayback()
    clearExplainCache()
    question.value = data.question || null
    selectedOptionKey.value = null
    reveal.value = false
    feedback.value = null
    summary.value = null
    answered.value = 0
    correct.value = 0
    stage.value = 'quiz'
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '启动失败'
  } finally {
    busy.value = false
  }
}

async function submitAnswer() {
  if (!attempt.value || !question.value || !selectedOptionKey.value) return
  errorMsg.value = ''
  busy.value = true
  try {
    const resp = await fetch(apiUrl('/ear/train/answer'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        attempt_id: attempt.value.attempt_id,
        question_id: question.value.question_id,
        selected_option_key: selectedOptionKey.value,
      }),
    })
    const data = (await resp.json()) as EarFeedback & { detail?: string }
    if (!resp.ok) throw new Error(data.detail || `提交失败（HTTP ${resp.status}）`)
    feedback.value = data
    reveal.value = true
    answered.value += 1
    if (data.is_correct) correct.value += 1
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '提交失败'
  } finally {
    busy.value = false
  }
}

async function nextQuestion() {
  if (!attempt.value) return
  errorMsg.value = ''
  busy.value = true
  try {
    const resp = await fetch(apiUrl('/ear/train/next'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ attempt_id: attempt.value.attempt_id }),
    })
    const data = (await resp.json()) as { question?: EarQuestion | null; detail?: string }
    if (!resp.ok) throw new Error(data.detail || `下一题失败（HTTP ${resp.status}）`)
    if (!data.question) {
      await finishSession()
      return
    }
    stopAllEarPlayback()
    clearExplainCache()
    question.value = data.question
    selectedOptionKey.value = null
    reveal.value = false
    feedback.value = null
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '下一题失败'
  } finally {
    busy.value = false
  }
}

async function finishSession() {
  if (!attempt.value) return
  stopAllEarPlayback()
  errorMsg.value = ''
  busy.value = true
  try {
    const resp = await fetch(apiUrl(`/ear/train/result/${attempt.value.attempt_id}`))
    const data = (await resp.json()) as EarSummary & { detail?: string }
    if (!resp.ok) throw new Error(data.detail || `结束失败（HTTP ${resp.status}）`)
    summary.value = data
    stage.value = 'result'
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '结束失败'
  } finally {
    busy.value = false
  }
}

async function fetchMistakes() {
  errorMsg.value = ''
  busy.value = true
  try {
    const resp = await fetch(apiUrl(`/ear/mistakes?learner_id=${encodeURIComponent(learnerId)}`))
    const data = (await resp.json()) as {
      mistakes?: Array<{ question_id: string; prompt_zh: string; wrong_count: number; status: string }>
      detail?: string
    }
    if (!resp.ok) throw new Error(data.detail || `加载错题失败（HTTP ${resp.status}）`)
    mistakes.value = data.mistakes || []
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '加载错题失败'
  } finally {
    busy.value = false
  }
}

function resetAll() {
  stopAllEarPlayback()
  clearExplainCache()
  stage.value = 'setup'
  attempt.value = null
  question.value = null
  selectedOptionKey.value = null
  reveal.value = false
  feedback.value = null
  summary.value = null
  answered.value = 0
  correct.value = 0
  errorMsg.value = ''
}

onUnmounted(() => {
  stopAllEarPlayback()
})
</script>

<style scoped>
/* 与训练题库 / 和弦进行一致：不用全局 :root --text（偏紫灰易被看成偏蓝），主正文用 #111 */
.ear-wrap {
  --ear-text-primary: #111111;
  --ear-text-secondary: #2a2a2a;
  --ear-text-muted: #3b3b3b;
  width: 100%;
  display: flex;
  justify-content: center;
  padding: 24px 16px calc(24px + 56px + env(safe-area-inset-bottom, 0px));
  box-sizing: border-box;
  color: var(--ear-text-primary);
  background: var(--bg);
}
.ear-card { width: 560px; max-width: 100%; }
.lang-panels { margin-bottom: 12px; }
.track-tabs { display: flex; gap: 8px; margin-bottom: 10px; }
.track-tab {
  flex: 1;
  border: 1px solid #ddd;
  background: #ececec;
  color: var(--ear-text-secondary);
  border-radius: 10px;
  padding: 8px 10px;
  cursor: pointer;
  font-weight: 700;
}
.track-tab.active {
  border-color: #cfcfcf;
  background: #fff;
  color: #000;
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.08);
}
.ear-section { border: 1px dashed #ccc; border-radius: 12px; background: #fff; padding: 14px; }
.mode-list { display: grid; gap: 8px; }
.mode-item { border: 1px solid #ddd; border-radius: 10px; background: #fff; text-align: left; padding: 10px; cursor: pointer; }
.mode-item.active { border: 2px solid #111; }
.mode-item strong { display: block; margin-bottom: 4px; color: var(--ear-text-primary); }
.mode-item-desc { display: block; color: var(--ear-text-muted); font-size: 13px; }
.stem-head { margin-bottom: 4px; }
.answer-truth-box {
  margin: 8px 0;
  padding: 8px 10px;
  border-radius: 8px;
  background: #f7f7f7;
  border: 1px solid #e5e5e5;
}
.err-block { margin-top: 8px; }
.err-block .err-msg { margin: 6px 0 0; }
.box-h-bi { margin: 0 0 8px; font-size: 13px; }
.box-h-bi .bi-pair, .box-h-bi .bi-pair--zh { display: block; }
.li-bi { margin-bottom: 4px; }
.muted-line--bi .bi-pair,
.muted-line--bi .bi-pair--zh { display: block; }
.progress--bi .bi-pair,
.progress--bi .bi-pair--zh,
.result-line--bi .bi-pair,
.result-line--bi .bi-pair--zh { display: block; }
.feedback--bi { font-size: 13px; }
.feedback--bi .bi-pair,
.feedback--bi .bi-pair--zh { display: block; }
.btn-primary,.btn-secondary { width: 100%; margin-top: 10px; padding: 11px 14px; border-radius: 10px; font-size: 14px; font-weight: 800; cursor: pointer; }
.btn-primary { border: 1px solid #111; background: #111; color: #fff; }
.btn-secondary { border: 1px solid #8a8a8a; background: #f4f4f4; color: var(--ear-text-primary); }
.btn-secondary.small { width: auto; margin-top: 0; font-size: 13px; padding: 7px 10px; }
.btn-primary:disabled,.btn-secondary:disabled { opacity: .6; cursor: not-allowed; }
.progress,
.stem,
.result-line {
  margin: 0 0 8px;
  color: var(--ear-text-primary);
}
.muted-line {
  margin: 0 0 8px;
  color: var(--ear-text-muted);
  font-size: 13px;
}
.audio-row { display: flex; gap: 8px; margin-bottom: 8px; }
.options { display: grid; grid-template-columns: repeat(2,minmax(0,1fr)); gap: 8px; }
.option {
  border: 1px solid #ddd;
  border-radius: 10px;
  background: #fff;
  color: #111;
  text-align: left;
  padding: 10px;
  cursor: pointer;
}
.option.selected { border-color: #111; }
.option.correct { border-color: #1f8a43; background: #effaf3; }
.option.wrong { border-color: #b42318; background: #fef1f1; }
.option-key { display: inline-block; min-width: 1.2rem; font-weight: 800; margin-right: 6px; }
.feedback { margin-top: 10px; font-size: 13px; }
.ok { color: #1f8a43; }
.err { color: #b42318; font-size: 13px; margin-top: 10px; }
.box { margin-top: 10px; border: 1px solid #e5e5e5; border-radius: 10px; background: #fafafa; padding: 10px; color: var(--ear-text-primary); }
.box h3 { margin: 0 0 8px; font-size: 13px; color: var(--ear-text-primary); }
.box ul { margin: 0; padding-left: 18px; font-size: 13px; line-height: 1.6; color: var(--ear-text-primary); }

@media (prefers-color-scheme: dark) {
  .ear-wrap {
    --ear-text-primary: #d8dce6;
    --ear-text-secondary: rgba(216, 220, 230, 0.88);
    --ear-text-muted: rgba(216, 220, 230, 0.72);
    color: var(--ear-text-primary);
  }
  .answer-truth-box {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.14);
  }
  .track-tab {
    border-color: rgba(255, 255, 255, 0.18);
    background: rgba(255, 255, 255, 0.08);
    color: rgba(216, 220, 230, 0.86);
  }
  .track-tab.active {
    border-color: rgba(255, 255, 255, 0.28);
    background: rgba(15, 15, 18, 0.96);
    color: #d8dce6;
    box-shadow: 0 3px 10px rgba(0, 0, 0, 0.35);
  }
  .ear-section {
    border-color: rgba(255, 255, 255, 0.14);
    background: rgba(15, 15, 18, 0.96);
  }
  .ear-section-h {
    color: rgba(216, 220, 230, 0.8);
  }
  .mode-item {
    border-color: rgba(255, 255, 255, 0.18);
    background: rgba(255, 255, 255, 0.06);
  }
  .mode-item.active {
    border-color: #ffffff;
  }
  .mode-item strong {
    color: #d8dce6;
  }
  .mode-item span {
    color: rgba(216, 220, 230, 0.78);
  }
  .btn-primary {
    border-color: #ffffff;
    background: #ffffff;
    color: #0b0b0f;
  }
  .btn-secondary {
    border-color: rgba(255, 255, 255, 0.26);
    background: rgba(255, 255, 255, 0.08);
    color: #d8dce6;
  }
  .option {
    border-color: rgba(255, 255, 255, 0.18);
    background: rgba(255, 255, 255, 0.06);
    color: #d8dce6;
  }
  .option.selected {
    border-color: #ffffff;
  }
  .option.correct {
    border-color: #62c489;
    background: rgba(98, 196, 137, 0.2);
  }
  .option.wrong {
    border-color: #ff8a80;
    background: rgba(255, 138, 128, 0.16);
  }
  .ok {
    color: #8fe7b0;
  }
  .err {
    color: #ff8a80;
  }
  .box {
    border-color: rgba(255, 255, 255, 0.14);
    background: rgba(255, 255, 255, 0.06);
  }
  .box h3,
  .box ul {
    color: rgba(216, 220, 230, 0.92);
  }
}
</style>

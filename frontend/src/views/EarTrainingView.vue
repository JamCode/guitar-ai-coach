<template>
  <div class="ear-wrap">
    <div class="ear-card">
      <div class="ear-hero">
        <h1 class="ear-title">练耳训练</h1>
      </div>
      <div class="track-tabs">
        <button
          type="button"
          class="track-tab"
          :class="{ active: activeTrack === 'legacy' }"
          @click="activeTrack = 'legacy'"
        >
          和弦练耳
        </button>
        <button
          type="button"
          class="track-tab"
          :class="{ active: activeTrack === 'single_note' }"
          @click="activeTrack = 'single_note'"
        >
          单音练耳（新）
        </button>
      </div>

      <template v-if="activeTrack === 'legacy'">
      <section v-if="stage === 'setup'" class="ear-section">
        <h2 class="ear-section-h">模式选择</h2>
        <div class="mode-list">
          <button
            v-for="m in modes"
            :key="m.id"
            type="button"
            class="mode-item"
            :class="{ active: mode === m.id }"
            @click="mode = m.id"
          >
            <strong>{{ m.title }}</strong>
            <span>{{ m.desc }}</span>
          </button>
        </div>
        <button type="button" class="btn-primary" :disabled="busy" @click="startSession">
          开始训练
        </button>
        <button
          v-if="mode === 'C'"
          type="button"
          class="btn-secondary"
          :disabled="busy"
          @click="refreshDailySet"
        >
          重置今日题单
        </button>
        <p v-if="dailyInfo && mode === 'C'" class="muted-line">
          今日题单：{{ dailyInfo.question_ids.length }} 题（{{ dailyInfo.day_date }}）
        </p>
        <p v-if="errorMsg" class="err">{{ errorMsg }}</p>
      </section>

      <section v-else-if="stage === 'quiz'" class="ear-section">
        <h2 class="ear-section-h">答题中</h2>
        <p class="progress">
          已完成 {{ answered }} 题 · 答对 {{ correct }} 题
          <span v-if="attempt?.mode === 'C'"> · 今日目标 10 题</span>
        </p>
        <p class="stem">{{ question?.prompt_zh }}</p>
        <div class="audio-row">
          <button type="button" class="btn-secondary small" @click="playEarAudio">播放音频</button>
          <button type="button" class="btn-secondary small" @click="playEarSlowAudio">0.8x 重听</button>
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

        <p v-if="reveal && feedback" :class="feedback.is_correct ? 'ok' : 'err'" class="feedback">
          {{
            feedback.is_correct
              ? `回答正确：${feedback.correct_option_key} - ${feedback.correct_option_label}`
              : `回答错误：正确答案是 ${feedback.correct_option_key} - ${feedback.correct_option_label}`
          }}
        </p>
        <p v-if="reveal && feedback && answerTruthLine" class="muted-line answer-truth">
          {{ answerTruthLine }}
        </p>

        <button type="button" class="btn-primary" :disabled="busy || !selectedOptionKey || reveal" @click="submitAnswer">
          提交答案
        </button>
        <button v-if="reveal" type="button" class="btn-primary" :disabled="busy" @click="nextQuestion">
          下一题
        </button>
        <button type="button" class="btn-secondary" :disabled="busy" @click="finishSession">
          结束并查看结果
        </button>
        <p v-if="errorMsg" class="err">{{ errorMsg }}</p>
      </section>

      <section v-else class="ear-section">
        <h2 class="ear-section-h">训练结果</h2>
        <p class="result-line">
          本次 {{ summary?.mode }} 模式：{{ summary?.total_correct || 0 }}/{{ summary?.total_answered || 0 }}
          （{{ formatPercent(summary?.accuracy || 0) }}）
        </p>
        <p class="muted-line">学习者：{{ learnerId.slice(0, 12) }}...</p>

        <div v-if="summary?.by_mode_stats?.length" class="box">
          <h3>维度表现</h3>
          <ul>
            <li v-for="s in summary.by_mode_stats" :key="s.mode">
              {{ s.mode }}：{{ s.right_count }}/{{ s.total_count }}（{{ formatPercent(s.accuracy) }}）
            </li>
          </ul>
        </div>

        <div v-if="summary?.wrongs?.length" class="box">
          <h3>错题回顾</h3>
          <ul>
            <li v-for="(w, idx) in summary.wrongs.slice(0, 10)" :key="idx">
              {{ w.prompt_zh }}（正确：{{ w.correct_option_label }}）
            </li>
          </ul>
        </div>

        <button type="button" class="btn-primary" :disabled="busy" @click="startSession">
          继续训练
        </button>
        <button type="button" class="btn-secondary" :disabled="busy" @click="fetchMistakes">
          查看错题本
        </button>
        <button type="button" class="btn-secondary" :disabled="busy" @click="resetAll">
          返回模式选择
        </button>

        <div v-if="mistakes.length" class="box">
          <h3>错题本（最近）</h3>
          <ul>
            <li v-for="m in mistakes.slice(0, 10)" :key="m.question_id">
              {{ m.prompt_zh }} · 错{{ m.wrong_count }}次 · 状态{{ m.status }}
            </li>
          </ul>
        </div>
        <p v-if="errorMsg" class="err">{{ errorMsg }}</p>
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
  { id: 'A' as Mode, title: 'A 单和弦听辨', desc: '大三 / 小三 / 属七' },
  { id: 'B' as Mode, title: 'B 常见进行听辨', desc: '2~4 和弦进行识别' },
  { id: 'C' as Mode, title: 'C 每日 10 题', desc: '6错题+2薄弱+2保温' },
]

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

/** 与和弦字典一致：无题目调号时用全站「目标调」；B 题用题目 music_key。 */
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
}
.ear-card { width: 560px; max-width: 100%; }
.ear-hero {
  margin-bottom: 12px;
  border: 1px solid #d8d8d8;
  border-radius: 14px;
  background: linear-gradient(180deg, #ffffff 0%, #f5f5f5 100%);
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.05);
  padding: 14px 16px;
}
.ear-title {
  margin: 0;
  font-size: 1.4rem;
  font-weight: 900;
  color: #000;
  letter-spacing: 0.01em;
}
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
.ear-section-h { margin: 0 0 10px; font-size: 12px; letter-spacing: .04em; text-transform: uppercase; color: var(--ear-text-secondary); }
.mode-list { display: grid; gap: 8px; }
.mode-item { border: 1px solid #ddd; border-radius: 10px; background: #fff; text-align: left; padding: 10px; cursor: pointer; }
.mode-item.active { border: 2px solid #111; }
.mode-item strong { display: block; margin-bottom: 4px; color: var(--ear-text-primary); }
.mode-item span { color: var(--ear-text-muted); font-size: 13px; }
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
</style>

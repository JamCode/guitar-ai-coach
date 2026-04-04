<template>
  <div class="quiz-wrap">
    <div class="quiz-card">
      <h1 class="quiz-title">和弦题库训练</h1>
        <p class="quiz-sub">不限题量，选择答案后会立即判定，可一直点「下一题」练习。</p>

      <section v-if="stage === 'setup'" class="quiz-section">
        <h2 class="quiz-section-h">训练设置</h2>
        <label class="field-label" for="qdifficulty">难度</label>
        <select id="qdifficulty" v-model="difficulty" class="field-select">
          <option value="beginner">初级（大三 / 小三 / 属七）</option>
          <option value="intermediate">中级（maj7 / m7 / sus / add9）</option>
          <option value="advanced">高级（m7b5 / aug / slash）</option>
        </select>
        <button type="button" class="btn-primary" :disabled="busy" @click="startSession(false)">
          开始训练
        </button>
        <p v-if="errorMsg" class="err">{{ errorMsg }}</p>
      </section>

      <section v-else-if="stage === 'quiz'" class="quiz-section">
        <h2 class="quiz-section-h">答题中</h2>
        <p class="progress">已完成 {{ answered }} 题 · 答对 {{ correct }} 题</p>
        <label class="auto-next-toggle">
          <input v-model="autoNextEnabled" type="checkbox" :disabled="busy" />
          <span>答题后自动下一题（0.8 秒）</span>
        </label>
        <p class="stem">请选择和弦 <strong>{{ question?.chord_symbol }}</strong> 的正确按法</p>

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
              wrong:
                reveal &&
                selectedOptionKey === opt.key &&
                feedback?.correct_option_key !== opt.key,
            }"
            @click="selectAndJudge(opt.key)"
          >
            <div class="option-top">选项 {{ opt.key }}</div>
            <ChordDiagram
              :frets="fingeringToFrets(opt.fingering)"
              :fingers="null"
              :base-fret="computeBaseFret(opt.fingering)"
              :barre="null"
            />
            <div class="option-f">{{ opt.fingering }}</div>
          </button>
        </div>

        <p v-if="reveal && feedback" :class="feedback.is_correct ? 'ok' : 'err'" class="feedback">
          {{
            feedback.is_correct
              ? `回答正确：${feedback.chord_symbol} 的正确按法是 ${feedback.correct_fingering}`
              : `回答错误：正确按法是 ${feedback.correct_fingering}`
          }}
        </p>
        <p v-if="errorMsg" class="err">{{ errorMsg }}</p>

        <button
          type="button"
          class="btn-secondary"
          :disabled="busy || !question || chordExplainLoading"
          @click="toggleChordExplain"
        >
          {{ chordExplainVisible ? '收起和弦介绍' : chordExplainLoading ? '加载介绍中…' : '查看和弦介绍' }}
        </button>
        <div v-if="chordExplainVisible" class="quality-box">
          <h3 class="quality-title">和弦介绍</h3>
          <p v-if="chordExplainError" class="err">{{ chordExplainError }}</p>
          <template v-else-if="chordExplain">
            <p v-if="chordExplain.notes_letters?.length" class="result-line">
              构成音：{{ chordExplain.notes_letters.join(' · ') }}
            </p>
            <p v-if="chordExplain.notes_explain_zh" class="result-line">{{ chordExplain.notes_explain_zh }}</p>
            <p v-if="chordExplain.voicing_explain_zh" class="result-line">{{ chordExplain.voicing_explain_zh }}</p>
            <ChordDiagram
              :frets="chordExplain.frets"
              :fingers="chordExplain.fingers"
              :base-fret="chordExplain.base_fret"
              :barre="chordExplain.barre"
            />
          </template>
          <p v-else class="result-line muted">暂无介绍</p>
        </div>
        <button v-if="reveal" type="button" class="btn-primary" :disabled="busy" @click="nextQuestion">
          下一题
        </button>
        <button type="button" class="btn-secondary" :disabled="busy" @click="finishSession">
          结束本次训练
        </button>
      </section>

      <section v-else class="quiz-section">
        <h2 class="quiz-section-h">训练结果</h2>
        <p class="result-line">
          已完成 {{ summary?.total_answered || 0 }} 题，答对 {{ summary?.total_correct || 0 }} 题（正确率
          {{ formatPercent(summary?.accuracy || 0) }}）
        </p>
        <p class="result-line muted">
          难度：{{ summary?.difficulty || difficulty }} · 学习者：{{ learnerId.slice(0, 12) }}...
        </p>

        <div v-if="summary?.quality_stats?.length" class="quality-box">
          <h3 class="quality-title">按和弦性质统计</h3>
          <ul class="quality-list">
            <li v-for="q in summary.quality_stats" :key="q.chord_quality">
              {{ q.chord_quality }}：{{ q.right_count }}/{{ q.total_count }}（{{ formatPercent(q.accuracy) }}）
            </li>
          </ul>
        </div>

        <div v-if="summary?.wrongs?.length" class="quality-box">
          <h3 class="quality-title">错题回顾</h3>
          <ul class="quality-list">
            <li v-for="(w, idx) in summary.wrongs.slice(0, 20)" :key="idx">
              {{ w.chord_symbol }}（{{ w.chord_quality }}）→ {{ w.correct_fingering }}
            </li>
          </ul>
        </div>

        <button type="button" class="btn-primary" :disabled="busy" @click="continueTraining">
          继续训练
        </button>
        <button type="button" class="btn-primary" :disabled="busy" @click="startSession(true)">
          再练错题
        </button>
        <button type="button" class="btn-secondary" :disabled="busy" @click="resetAll">
          重新选难度
        </button>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onBeforeUnmount, ref } from 'vue'
import ChordDiagram from '../components/ChordDiagram.vue'

type OptionItem = { key: 'A' | 'B' | 'C' | 'D'; fingering: string }
type Question = {
  question_id: string
  chord_symbol: string
  chord_quality: string
  options: OptionItem[]
}
type Feedback = {
  question_id: string
  is_correct: boolean
  correct_option_key: 'A' | 'B' | 'C' | 'D'
  correct_fingering: string
  chord_symbol: string
  chord_quality: string
}
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
type QualityStat = {
  chord_quality: string
  right_count: number
  total_count: number
  accuracy: number
}
type Summary = {
  attempt_id: number
  learner_id: string
  difficulty: string
  total_answered: number
  total_correct: number
  accuracy: number
  quality_stats: QualityStat[]
  wrongs: Array<{
    chord_symbol: string
    chord_quality: string
    correct_option_key: string
    correct_fingering: string
  }>
}

const apiBase = (import.meta.env.VITE_API_BASE_URL || '/api').replace(/\/$/, '')
function apiUrl(path: string) {
  const p = path.startsWith('/') ? path : `/${path}`
  return `${apiBase}${p}`
}

const LEARNER_KEY = 'guitar_ai_coach_learner_id_v1'
function createFallbackLearnerId() {
  const t = Date.now().toString(36)
  const r = Math.random().toString(36).slice(2, 10)
  return `anon_${t}_${r}`
}
function getLearnerId() {
  try {
    const old = window.localStorage.getItem(LEARNER_KEY)
    if (old) return old
    const cryptoObj = window.crypto as Crypto & { randomUUID?: () => string }
    const id =
      cryptoObj && typeof cryptoObj.randomUUID === 'function'
        ? `anon_${cryptoObj.randomUUID().replace(/-/g, '')}`
        : createFallbackLearnerId()
    window.localStorage.setItem(LEARNER_KEY, id)
    return id
  } catch {
    return createFallbackLearnerId()
  }
}

const learnerId = getLearnerId()
const difficulty = ref<'beginner' | 'intermediate' | 'advanced'>('beginner')
const stage = ref<'setup' | 'quiz' | 'result'>('setup')
const attemptId = ref<number | null>(null)
const question = ref<Question | null>(null)
const selectedOptionKey = ref<'A' | 'B' | 'C' | 'D' | null>(null)
const feedback = ref<Feedback | null>(null)
const summary = ref<Summary | null>(null)
const reveal = ref(false)
const answered = ref(0)
const correct = ref(0)
const busy = ref(false)
const errorMsg = ref('')
const autoNextEnabled = ref(true)
const chordExplainVisible = ref(false)
const chordExplainLoading = ref(false)
const chordExplainError = ref('')
const chordExplain = ref<ChordExplain | null>(null)
let autoNextTimer: number | null = null

function clearAutoNextTimer() {
  if (autoNextTimer !== null) {
    window.clearTimeout(autoNextTimer)
    autoNextTimer = null
  }
}

function fingeringToFrets(fingering: string) {
  if (!fingering || fingering.length !== 6) return [-1, -1, -1, -1, -1, -1]
  return fingering.split('').map((ch) => {
    if (ch === 'x' || ch === 'X') return -1
    const n = Number(ch)
    return Number.isFinite(n) ? n : -1
  })
}

function computeBaseFret(fingering: string) {
  const frets = fingeringToFrets(fingering).filter((f) => f > 0)
  if (!frets.length) return 1
  return Math.max(1, Math.min(...frets))
}

function formatPercent(n: number) {
  return `${Math.round(n * 100)}%`
}

async function startSession(wrongOnly: boolean) {
  errorMsg.value = ''
  busy.value = true
  try {
    const resp = await fetch(apiUrl('/quiz/session/start'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        learner_id: learnerId,
        difficulty: difficulty.value,
        wrong_only: wrongOnly,
      }),
    })
    if (!resp.ok) {
      const errBody = await resp.json().catch(() => ({}))
      throw new Error((errBody as { detail?: string }).detail || `启动失败（HTTP ${resp.status}）`)
    }
    const data = (await resp.json()) as { attempt?: { attempt_id: number }; question?: Question }
    attemptId.value = data.attempt?.attempt_id || null
    question.value = data.question || null
    selectedOptionKey.value = null
    feedback.value = null
    summary.value = null
    reveal.value = false
    answered.value = 0
    correct.value = 0
    chordExplainVisible.value = false
    chordExplainLoading.value = false
    chordExplainError.value = ''
    chordExplain.value = null
    stage.value = 'quiz'
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '启动失败'
  } finally {
    busy.value = false
  }
}

async function nextQuestion() {
  clearAutoNextTimer()
  if (!attemptId.value) return
  errorMsg.value = ''
  busy.value = true
  try {
    const resp = await fetch(apiUrl('/quiz/session/next'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ attempt_id: attemptId.value }),
    })
    if (!resp.ok) {
      const errBody = await resp.json().catch(() => ({}))
      throw new Error((errBody as { detail?: string }).detail || `下一题失败（HTTP ${resp.status}）`)
    }
    const data = (await resp.json()) as { question?: Question }
    question.value = data.question || null
    selectedOptionKey.value = null
    feedback.value = null
    reveal.value = false
    chordExplainVisible.value = false
    chordExplainLoading.value = false
    chordExplainError.value = ''
    chordExplain.value = null
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '下一题失败'
  } finally {
    busy.value = false
  }
}

async function submitAnswer() {
  if (!attemptId.value || !question.value || !selectedOptionKey.value) return
  clearAutoNextTimer()
  errorMsg.value = ''
  busy.value = true
  try {
    const resp = await fetch(apiUrl('/quiz/session/answer'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        attempt_id: attemptId.value,
        question_id: question.value.question_id,
        selected_option_key: selectedOptionKey.value,
      }),
    })
    if (!resp.ok) {
      const errBody = await resp.json().catch(() => ({}))
      throw new Error((errBody as { detail?: string }).detail || `提交失败（HTTP ${resp.status}）`)
    }
    const data = (await resp.json()) as Feedback
    feedback.value = data
    reveal.value = true
    answered.value += 1
    if (data.is_correct) correct.value += 1
    if (autoNextEnabled.value) {
      autoNextTimer = window.setTimeout(() => {
        autoNextTimer = null
        if (stage.value === 'quiz' && reveal.value && !busy.value) {
          void nextQuestion()
        }
      }, 800)
    }
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '提交失败'
  } finally {
    busy.value = false
  }
}

function selectAndJudge(key: 'A' | 'B' | 'C' | 'D') {
  if (busy.value || reveal.value) return
  selectedOptionKey.value = key
  void submitAnswer()
}

async function toggleChordExplain() {
  if (!question.value || chordExplainLoading.value) return
  if (chordExplainVisible.value) {
    chordExplainVisible.value = false
    return
  }
  chordExplainVisible.value = true
  if (chordExplain.value) return
  chordExplainError.value = ''
  chordExplainLoading.value = true
  try {
    const resp = await fetch(apiUrl('/chords/explain'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ symbol: question.value.chord_symbol }),
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
    const data = (await resp.json()) as { explain?: ChordExplain }
    if (!data.explain || !Array.isArray(data.explain.frets)) throw new Error('返回介绍数据不完整')
    chordExplain.value = data.explain
  } catch (e) {
    chordExplainError.value = e instanceof Error ? e.message : '加载和弦介绍失败'
  } finally {
    chordExplainLoading.value = false
  }
}

async function finishSession() {
  clearAutoNextTimer()
  if (!attemptId.value) return
  errorMsg.value = ''
  busy.value = true
  try {
    const resp = await fetch(apiUrl('/quiz/session/finish'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ attempt_id: attemptId.value }),
    })
    if (!resp.ok) {
      const errBody = await resp.json().catch(() => ({}))
      throw new Error((errBody as { detail?: string }).detail || `结束失败（HTTP ${resp.status}）`)
    }
    summary.value = (await resp.json()) as Summary
    stage.value = 'result'
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '结束失败'
  } finally {
    busy.value = false
  }
}

function continueTraining() {
  void startSession(false)
}

function resetAll() {
  clearAutoNextTimer()
  stage.value = 'setup'
  attemptId.value = null
  question.value = null
  selectedOptionKey.value = null
  feedback.value = null
  summary.value = null
  reveal.value = false
  answered.value = 0
  correct.value = 0
  errorMsg.value = ''
  chordExplainVisible.value = false
  chordExplainLoading.value = false
  chordExplainError.value = ''
  chordExplain.value = null
}

onBeforeUnmount(() => {
  clearAutoNextTimer()
})
</script>

<style scoped>
.quiz-wrap {
  width: 100%;
  display: flex;
  justify-content: center;
  padding: 24px 16px calc(24px + 56px + env(safe-area-inset-bottom, 0px));
  box-sizing: border-box;
  color: #111;
}
.quiz-card {
  width: 560px;
  max-width: 100%;
}
.quiz-title {
  margin: 0 0 4px;
  font-size: 1.25rem;
  font-weight: 800;
  color: #111;
}
.quiz-sub {
  margin: 0 0 14px;
  color: rgba(17, 17, 17, 0.76);
  font-size: 13px;
}
.quiz-section {
  border: 1px dashed #ccc;
  border-radius: 12px;
  background: #fff;
  padding: 14px;
}
.quiz-section-h {
  margin: 0 0 10px;
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: rgba(17, 17, 17, 0.72);
}
.field-label {
  display: block;
  font-size: 13px;
  font-weight: 600;
  margin-bottom: 4px;
}
.field-select {
  width: 100%;
  padding: 10px 12px;
  border: 1px solid #ccc;
  border-radius: 8px;
  font-size: 15px;
}
.btn-primary,
.btn-secondary {
  width: 100%;
  margin-top: 10px;
  padding: 11px 14px;
  border-radius: 10px;
  font-size: 14px;
  font-weight: 800;
  cursor: pointer;
}
.btn-primary {
  border: 1px solid #111;
  background: #111;
  color: #fff;
}
.btn-secondary {
  border: 1px solid rgba(17, 17, 17, 0.25);
  background: rgba(0, 0, 0, 0.04);
}
.btn-primary:disabled,
.btn-secondary:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.progress {
  margin: 0 0 8px;
  font-size: 13px;
  color: rgba(17, 17, 17, 0.8);
}
.auto-next-toggle {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  margin: 0 0 10px;
  font-size: 13px;
  color: rgba(17, 17, 17, 0.84);
}
.auto-next-toggle input {
  width: 14px;
  height: 14px;
}
.stem {
  margin: 0 0 10px;
  color: rgba(17, 17, 17, 0.86);
}
.stem strong {
  font-size: 1.5rem;
  color: #111;
}
.options {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
}
.option {
  min-width: 0;
  border: 1px solid #ddd;
  border-radius: 10px;
  background: #fff;
  color: #111;
  padding: 8px;
  text-align: left;
  cursor: pointer;
  overflow: hidden;
  -webkit-appearance: none;
  appearance: none;
}
.option :deep(.chord-svg) {
  width: 100%;
  max-width: 100%;
  height: auto;
  margin-bottom: 6px;
}
.option.selected {
  border-color: #111;
}
.option.correct {
  border-color: #1f8a43;
  background: #f0fbf4;
}
.option.wrong {
  border-color: #b42318;
  background: #fef1f1;
}
.option-top {
  font-size: 12px;
  font-weight: 700;
  color: rgba(17, 17, 17, 0.75);
  margin-bottom: 8px;
}
.option-f {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  margin-top: 8px;
  font-size: 12px;
  color: rgba(17, 17, 17, 0.86);
}
.feedback {
  margin: 10px 0 0;
  font-size: 13px;
}
.ok {
  color: #1f8a43;
}
.err {
  margin-top: 10px;
  color: #b42318;
  font-size: 13px;
}
.result-line {
  margin: 0 0 8px;
  line-height: 1.5;
}
.result-line.muted {
  color: rgba(17, 17, 17, 0.76);
  font-size: 13px;
}
.quality-box {
  border: 1px solid #e5e5e5;
  border-radius: 10px;
  background: #fafafa;
  padding: 10px;
  margin: 8px 0;
}
.quality-title {
  margin: 0 0 8px;
  font-size: 13px;
}
.quality-list {
  margin: 0;
  padding-left: 18px;
  font-size: 13px;
  line-height: 1.6;
}

@media (prefers-color-scheme: dark) {
  .quiz-title {
    color: #f8f8f8;
  }
  .quiz-sub {
    color: rgba(248, 248, 248, 0.82);
  }
  .quiz-section {
    border-color: rgba(255, 255, 255, 0.14);
    background: rgba(15, 15, 18, 0.96);
  }
  .quiz-section-h {
    color: rgba(248, 248, 248, 0.8);
  }
  .field-label {
    color: rgba(248, 248, 248, 0.92);
  }
  .field-select {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.2);
    color: #f8f8f8;
  }
  .btn-primary {
    border-color: #ffffff;
    background: #ffffff;
    color: #0b0b0f;
  }
  .btn-secondary {
    border-color: rgba(255, 255, 255, 0.26);
    background: rgba(255, 255, 255, 0.08);
    color: #f8f8f8;
  }
  .progress {
    color: rgba(248, 248, 248, 0.84);
  }
  .auto-next-toggle {
    color: rgba(248, 248, 248, 0.86);
  }
  .stem {
    color: rgba(248, 248, 248, 0.96);
  }
  .option {
    border-color: rgba(255, 255, 255, 0.18);
    background: rgba(255, 255, 255, 0.06);
    color: #f8f8f8;
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
  .option-top {
    color: rgba(248, 248, 248, 0.82);
  }
  .option-f {
    color: rgba(248, 248, 248, 0.9);
  }
  .ok {
    color: #8fe7b0;
  }
  .err {
    color: #ff8a80;
  }
  .result-line {
    color: rgba(248, 248, 248, 0.92);
  }
  .result-line.muted {
    color: rgba(248, 248, 248, 0.82);
  }
  .quality-box {
    border-color: rgba(255, 255, 255, 0.14);
    background: rgba(255, 255, 255, 0.06);
  }
  .quality-title {
    color: #f8f8f8;
  }
  .quality-list {
    color: rgba(248, 248, 248, 0.9);
  }
}

@media (max-width: 680px) {
  .quiz-wrap {
    padding-left: 10px;
    padding-right: 10px;
  }
  .quiz-card {
    width: 100%;
  }
  .quiz-section {
    padding: 12px;
  }
  .options {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px;
  }
  .option {
    padding: 6px;
  }
  .option-top {
    font-size: 11px;
    margin-bottom: 6px;
  }
  .option-f {
    font-size: 11px;
    line-height: 1.3;
    word-break: break-all;
  }
  .option :deep(.chord-svg) {
    max-width: 132px;
  }
}
</style>

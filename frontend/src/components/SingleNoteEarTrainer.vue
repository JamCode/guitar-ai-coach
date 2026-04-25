<template>
  <section class="single-note">
    <div class="lang-panels lang-panels--tight">
      <section class="lang-panel" lang="en" aria-labelledby="sn-en">
        <h2 id="sn-en" class="lang-panel__label">English</h2>
        <h1 class="lang-panel__title sn-title">Single-note ear training</h1>
        <p class="lang-panel__note">Identify notes after A4.</p>
      </section>
      <section class="lang-panel" lang="zh-Hans" aria-labelledby="sn-zh">
        <h2 id="sn-zh" class="lang-panel__label">中文</h2>
        <h1 class="lang-panel__title sn-title">单音练耳</h1>
        <p class="lang-panel__note">在标准音 A4 后辨认单音。</p>
      </section>
    </div>

    <template v-if="stage === 'setup'">
      <div class="row">
        <label class="field">
          <span class="field-label-bi">
            <span class="bi-pair" lang="en">Type</span>
            <span class="bi-pair bi-pair--zh" lang="zh-Hans">题型</span>
          </span>
          <select v-model="mode">
            <option value="single_note">One note / 单个单音</option>
            <option value="multi_note">3 notes / 多个单音（3个）</option>
          </select>
        </label>
        <label class="check">
          <input v-model="includeAccidental" type="checkbox" />
          <span>
            <span class="bi-pair" lang="en">Include accidentals (#)</span>
            <span class="bi-pair bi-pair--zh" lang="zh-Hans">包含半音（#）</span>
          </span>
        </label>
      </div>
      <button class="btn-primary btn-bi" :disabled="busy" @click="startSession">
        <span class="bi-pair" lang="en">Start</span>
        <span class="bi-pair bi-pair--zh" lang="zh-Hans">开始训练</span>
      </button>
      <div v-if="errorMsg" class="err-block" role="alert">
        <p class="bi-pair" lang="en">Error</p>
        <p class="bi-pair bi-pair--zh" lang="zh-Hans">错误</p>
        <p class="err err-msg">{{ errorMsg }}</p>
      </div>
    </template>

    <template v-else-if="stage === 'quiz' && currentQuestion">
      <p class="progress progress--bi">
        <span class="bi-pair" lang="en"
          >Q {{ currentQuestion.index }}/{{ currentQuestion.total_questions }} · Correct
          {{ correctCount }}</span
        >
        <span class="bi-pair bi-pair--zh" lang="zh-Hans"
          >第 {{ currentQuestion.index }}/{{ currentQuestion.total_questions }} 题 · 已答对
          {{ correctCount }} 题</span
        >
      </p>
      <div class="actions">
        <button class="btn-secondary small btn-bi" :disabled="busy" @click="playQuestion">
          <span class="bi-pair" lang="en">A4 + question</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">播放标准音 + 题目</span>
        </button>
        <button class="btn-secondary small btn-bi" :disabled="busy" @click="replayQuestion">
          <span class="bi-pair" lang="en">Replay this item</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">重播本题</span>
        </button>
      </div>

      <div v-if="isMultiMode" class="slots">
        <span
          v-for="(slot, idx) in answers"
          :key="idx"
          class="slot"
          :class="{ active: idx === fillIndex }"
        >
          {{ slot || `第${idx + 1}个` }}
        </span>
      </div>

      <div class="keys">
        <button
          v-for="label in currentQuestion.candidate_labels"
          :key="label"
          class="key-btn"
          :class="{ selected: isLabelSelected(label) }"
          :disabled="busy || reveal"
          @click="selectLabel(label)"
        >
          {{ label }}
        </button>
      </div>

      <div class="actions">
        <button class="btn-secondary small btn-bi" :disabled="busy || reveal" @click="undoAnswer">
          <span class="bi-pair" lang="en">Undo</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">撤销一步</span>
        </button>
        <button class="btn-secondary small btn-bi" :disabled="busy || reveal" @click="clearAnswer">
          <span class="bi-pair" lang="en">Clear</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">清空</span>
        </button>
      </div>

      <button class="btn-primary btn-bi" :disabled="busy || !canSubmit || reveal" @click="submitAnswer">
        <span class="bi-pair" lang="en">Submit</span>
        <span class="bi-pair bi-pair--zh" lang="zh-Hans">提交答案</span>
      </button>
      <button v-if="reveal" class="btn-primary btn-bi" :disabled="busy" @click="nextQuestion">
        <span class="bi-pair" lang="en">Next</span>
        <span class="bi-pair bi-pair--zh" lang="zh-Hans">下一题</span>
      </button>

      <div v-if="feedback" :class="feedback.is_correct ? 'ok' : 'err'" class="feedback feedback--bi">
        <template v-if="feedback.is_correct">
          <p class="bi-pair" lang="en">Correct: {{ feedback.correct_answers.join(' – ') }}</p>
          <p class="bi-pair bi-pair--zh" lang="zh-Hans">
            回答正确：{{ feedback.correct_answers.join(' - ') }}
          </p>
        </template>
        <template v-else>
          <p class="bi-pair" lang="en">Correct answer: {{ feedback.correct_answers.join(' – ') }}</p>
          <p class="bi-pair bi-pair--zh" lang="zh-Hans">
            回答错误：正确答案是 {{ feedback.correct_answers.join(' - ') }}
          </p>
        </template>
      </div>
      <div v-if="errorMsg" class="err-block" role="alert">
        <p class="bi-pair" lang="en">Error</p>
        <p class="bi-pair bi-pair--zh" lang="zh-Hans">错误</p>
        <p class="err err-msg">{{ errorMsg }}</p>
      </div>
    </template>

    <template v-else>
      <div class="section-bi-h result-head">
        <p class="bi-pair" lang="en">Session results</p>
        <p class="bi-pair bi-pair--zh" lang="zh-Hans">训练结果</p>
      </div>
      <p class="result-line result-line--bi">
        <span class="bi-pair" lang="en"
          >Correct {{ summary.correct }}/{{ summary.total }} ({{ formatPercent(summary.accuracy) }})</span
        >
        <span class="bi-pair bi-pair--zh" lang="zh-Hans"
          >正确 {{ summary.correct }}/{{ summary.total }}（{{ formatPercent(summary.accuracy) }}）</span
        >
      </p>
      <p class="muted muted--bi">
        <span class="bi-pair" lang="en">Mode: {{ modeLabelEn }}</span>
        <span class="bi-pair bi-pair--zh" lang="zh-Hans">模式：{{ modeLabelZh }}</span>
      </p>
      <div v-if="wrongs.length" class="wrong-box">
        <div class="wrong-box-h">
          <span class="bi-pair" lang="en">Mistakes</span>
          <span class="bi-pair bi-pair--zh" lang="zh-Hans">错题回顾</span>
        </div>
        <ul>
          <li v-for="item in wrongs" :key="item.question_id">
            你的：{{ item.user_answers.join(' - ') || '-' }}；正确：{{ item.correct_answers.join(' - ') }}
          </li>
        </ul>
      </div>
      <button class="btn-primary btn-bi" :disabled="busy" @click="resetAll">
        <span class="bi-pair" lang="en">Another round</span>
        <span class="bi-pair bi-pair--zh" lang="zh-Hans">再来一组</span>
      </button>
    </template>
  </section>
</template>

<script setup lang="ts">
import * as Tone from 'tone'
import { computed, ref } from 'vue'

type Mode = 'single_note' | 'multi_note'
type Question = {
  question_id: string
  index: number
  total_questions: number
  notes_per_question: number
  candidate_notes: string[]
  candidate_labels: string[]
  target_notes: string[]
}
type Feedback = {
  question_id: string
  is_correct: boolean
  correct_answers: string[]
  user_answers: string[]
  progress: { answered: number; correct: number; total: number; accuracy: number }
}
type WrongItem = {
  question_id: string
  user_answers: string[]
  correct_answers: string[]
}

const apiBase = (import.meta.env.VITE_API_BASE_URL || '/api').replace(/\/$/, '')
const apiUrl = (path: string) => `${apiBase}${path.startsWith('/') ? path : `/${path}`}`

const stage = ref<'setup' | 'quiz' | 'result'>('setup')
const mode = ref<Mode>('single_note')
const includeAccidental = ref(false)
const busy = ref(false)
const errorMsg = ref('')
const sessionId = ref('')
const currentQuestion = ref<Question | null>(null)
const answers = ref<string[]>([])
const reveal = ref(false)
const feedback = ref<Feedback | null>(null)
const correctCount = ref(0)
const summary = ref({ answered: 0, correct: 0, total: 0, accuracy: 0 })
const wrongs = ref<WrongItem[]>([])
const playToken = ref(0)

const isMultiMode = computed(() => mode.value === 'multi_note')
const expectedCount = computed(() => currentQuestion.value?.notes_per_question || 1)
const canSubmit = computed(() => answers.value.length === expectedCount.value)
const fillIndex = computed(() => Math.min(answers.value.length, expectedCount.value - 1))
const modeLabelEn = computed(() =>
  mode.value === 'single_note' ? 'One note' : 'Three notes',
)
const modeLabelZh = computed(() =>
  mode.value === 'single_note' ? '单个单音' : '多个单音（3个）',
)

function formatPercent(n: number) {
  return `${Math.round(n * 100)}%`
}

function clearAnswer() {
  answers.value = []
}

function undoAnswer() {
  answers.value = answers.value.slice(0, -1)
}

function isLabelSelected(label: string) {
  if (isMultiMode.value) return answers.value.includes(label)
  return answers.value[0] === label
}

function selectLabel(label: string) {
  if (reveal.value) return
  if (!isMultiMode.value) {
    answers.value = [label]
    return
  }
  if (answers.value.length >= expectedCount.value) return
  answers.value = [...answers.value, label]
}

function sleep(ms: number) {
  return new Promise((resolve) => window.setTimeout(resolve, ms))
}

async function playNoteSequence(notes: string[]) {
  await Tone.start()
  const synth = new Tone.Synth({ oscillator: { type: 'triangle' } }).toDestination()
  try {
    for (const note of notes) {
      synth.triggerAttackRelease(note, '8n')
      await sleep(650)
    }
  } finally {
    synth.dispose()
  }
}

async function playQuestion() {
  const q = currentQuestion.value
  if (!q) return
  errorMsg.value = ''
  const token = playToken.value + 1
  playToken.value = token
  try {
    await playNoteSequence(['A4'])
    if (playToken.value !== token) return
    await sleep(1000)
    if (playToken.value !== token) return
    const targets = (q.target_notes || []).filter((n) => typeof n === 'string' && n.endsWith('4'))
    if (targets.length === 0) return
    await playNoteSequence(targets)
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '播放失败'
  }
}

async function replayQuestion() {
  await playQuestion()
}

async function startSession() {
  errorMsg.value = ''
  busy.value = true
  try {
    const resp = await fetch(apiUrl('/ear-note/session/start'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        mode: mode.value,
        include_accidental: includeAccidental.value,
        notes_per_question: mode.value === 'single_note' ? 1 : 3,
        question_count: 10,
      }),
    })
    const data = (await resp.json()) as { session_id: string; question: Question; error?: string }
    if (!resp.ok) throw new Error(data.error || `启动失败（HTTP ${resp.status}）`)
    sessionId.value = data.session_id
    currentQuestion.value = data.question
    answers.value = []
    reveal.value = false
    feedback.value = null
    correctCount.value = 0
    summary.value = { answered: 0, correct: 0, total: 0, accuracy: 0 }
    wrongs.value = []
    stage.value = 'quiz'
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '启动失败'
  } finally {
    busy.value = false
  }
}

async function submitAnswer() {
  const q = currentQuestion.value
  if (!q || !canSubmit.value) return
  errorMsg.value = ''
  busy.value = true
  try {
    const resp = await fetch(apiUrl('/ear-note/session/answer'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        session_id: sessionId.value,
        question_id: q.question_id,
        answers: answers.value,
      }),
    })
    const data = (await resp.json()) as Feedback & { error?: string }
    if (!resp.ok) throw new Error(data.error || `提交失败（HTTP ${resp.status}）`)
    feedback.value = data
    reveal.value = true
    if (data.is_correct) {
      correctCount.value = data.progress.correct
    } else {
      wrongs.value = [
        ...wrongs.value,
        {
          question_id: data.question_id,
          user_answers: data.user_answers,
          correct_answers: data.correct_answers,
        },
      ]
    }
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '提交失败'
  } finally {
    busy.value = false
  }
}

async function nextQuestion() {
  errorMsg.value = ''
  busy.value = true
  try {
    const resp = await fetch(apiUrl('/ear-note/session/next'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ session_id: sessionId.value }),
    })
    const data = (await resp.json()) as { question: Question | null; has_next: boolean; error?: string }
    if (!resp.ok) throw new Error(data.error || `下一题失败（HTTP ${resp.status}）`)
    if (!data.question) {
      await finishSession()
      return
    }
    currentQuestion.value = data.question
    answers.value = []
    feedback.value = null
    reveal.value = false
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : '下一题失败'
  } finally {
    busy.value = false
  }
}

async function finishSession() {
  const sid = sessionId.value
  if (!sid) return
  const resp = await fetch(apiUrl(`/ear-note/session/result/${encodeURIComponent(sid)}`))
  const data = (await resp.json().catch(() => ({}))) as {
    summary?: { answered: number; correct: number; total: number; accuracy: number }
    wrongs?: WrongItem[]
    error?: string
  }
  if (!resp.ok) throw new Error(data.error || `结果获取失败（HTTP ${resp.status}）`)
  summary.value = data.summary || { answered: 0, correct: 0, total: 0, accuracy: 0 }
  wrongs.value = data.wrongs || wrongs.value
  stage.value = 'result'
}

function resetAll() {
  stage.value = 'setup'
  sessionId.value = ''
  currentQuestion.value = null
  answers.value = []
  feedback.value = null
  reveal.value = false
  errorMsg.value = ''
}
</script>

<style scoped>
.single-note {
  --sn-text-primary: #111111;
  --sn-text-secondary: #2a2a2a;
  --sn-text-muted: #3b3b3b;
  border: 1px dashed #ccc;
  border-radius: 12px;
  background: #fff;
  padding: 14px;
  color: var(--sn-text-primary);
}
.sn-title {
  font-size: 1.2rem;
}
.lang-panels {
  margin-bottom: 12px;
}
.field-label-bi {
  display: block;
  margin-bottom: 6px;
}
.field-label-bi .bi-pair--zh {
  display: block;
  margin-top: 2px;
  font-size: 12px;
}
.err-block {
  margin-top: 8px;
}
.err-block .err-msg {
  margin: 6px 0 0;
}
.progress--bi .bi-pair,
.progress--bi .bi-pair--zh,
.result-line--bi .bi-pair,
.result-line--bi .bi-pair--zh,
.muted--bi .bi-pair,
.muted--bi .bi-pair--zh {
  display: block;
}
.feedback--bi .bi-pair,
.feedback--bi .bi-pair--zh {
  display: block;
  font-size: 13px;
}
.wrong-box-h {
  display: block;
  margin-bottom: 6px;
  font-weight: 800;
}
.wrong-box-h .bi-pair--zh {
  display: block;
  margin-top: 2px;
  font-size: 12px;
  font-weight: 700;
}
.result-head {
  margin-bottom: 8px;
}
.row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 8px; }
.field select {
  width: 100%;
  border: 1px solid #ddd;
  border-radius: 8px;
  padding: 8px 10px;
  color: var(--sn-text-primary);
  background: #fff;
}
.check { display: flex; align-items: end; gap: 8px; padding-bottom: 8px; color: var(--sn-text-primary); }
.field span { display: block; font-size: 13px; margin-bottom: 6px; color: var(--sn-text-secondary); }
.muted { margin: 0 0 8px; color: var(--sn-text-muted); font-size: 13px; }
.progress { margin: 0 0 8px; color: var(--sn-text-primary); }
.actions { display: flex; gap: 8px; margin-bottom: 8px; }
.keys {
  display: grid;
  grid-template-columns: repeat(6, minmax(0, 1fr));
  gap: 8px;
  margin-bottom: 8px;
}
.key-btn {
  border: 1px solid #ddd;
  border-radius: 8px;
  background: #fff;
  color: var(--sn-text-primary);
  padding: 8px 6px;
  font-weight: 700;
  cursor: pointer;
}
.key-btn.selected { border-color: #111; background: #f5f5f5; }
.slots { display: flex; gap: 8px; margin-bottom: 8px; }
.slot {
  border: 1px dashed #bbb;
  border-radius: 8px;
  padding: 8px 10px;
  min-width: 68px;
  text-align: center;
  color: var(--sn-text-muted);
}
.slot.active { border-color: #111; color: var(--sn-text-primary); }
.feedback { margin: 8px 0; font-size: 13px; }
.ok { color: #1f8a43; }
.err { color: #b42318; font-size: 13px; margin-top: 8px; }
.btn-primary,.btn-secondary { width: 100%; margin-top: 8px; padding: 11px 14px; border-radius: 10px; font-size: 14px; font-weight: 800; cursor: pointer; }
.btn-primary { border: 1px solid #111; background: #111; color: #fff; }
.btn-secondary { border: 1px solid #8a8a8a; background: #f4f4f4; color: var(--sn-text-primary); }
.btn-secondary.small { width: auto; margin-top: 0; padding: 7px 10px; font-size: 13px; }
.result-title { margin: 0 0 8px; color: var(--sn-text-primary); }
.result-line { margin: 0 0 6px; color: var(--sn-text-primary); }
.wrong-box { margin: 8px 0; border: 1px solid #e6e6e6; border-radius: 8px; padding: 8px; background: #fafafa; }
.wrong-box ul { margin: 6px 0 0; padding-left: 18px; }
@media (max-width: 640px) {
  .row { grid-template-columns: 1fr; }
  .keys { grid-template-columns: repeat(4, minmax(0, 1fr)); }
}

@media (prefers-color-scheme: dark) {
  .single-note {
    --sn-text-primary: #d8dce6;
    --sn-text-secondary: rgba(216, 220, 230, 0.88);
    --sn-text-muted: rgba(216, 220, 230, 0.72);
    border-color: rgba(255, 255, 255, 0.14);
    background: rgba(15, 15, 18, 0.96);
    color: #d8dce6;
  }
  .field select {
    border-color: rgba(255, 255, 255, 0.2);
    background: rgba(255, 255, 255, 0.06);
    color: #d8dce6;
  }
  .check,
  .field span {
    color: rgba(216, 220, 230, 0.86);
  }
  .key-btn {
    border-color: rgba(255, 255, 255, 0.18);
    background: rgba(255, 255, 255, 0.06);
    color: #d8dce6;
  }
  .key-btn.selected {
    border-color: #ffffff;
    background: rgba(255, 255, 255, 0.1);
  }
  .slot {
    border-color: rgba(255, 255, 255, 0.22);
    color: rgba(216, 220, 230, 0.72);
  }
  .slot.active {
    border-color: #ffffff;
    color: #d8dce6;
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
  .result-title,
  .result-line,
  .progress {
    color: rgba(216, 220, 230, 0.92);
  }
  .muted {
    color: rgba(216, 220, 230, 0.78);
  }
  .ok {
    color: #8fe7b0;
  }
  .err {
    color: #ff8a80;
  }
  .wrong-box {
    border-color: rgba(255, 255, 255, 0.14);
    background: rgba(255, 255, 255, 0.06);
    color: rgba(216, 220, 230, 0.92);
  }
}
</style>

<template>
  <section class="single-note">
    <h2 class="ear-section-h">单音练耳</h2>

    <template v-if="stage === 'setup'">
      <div class="row">
        <label class="field">
          <span>题型</span>
          <select v-model="mode">
            <option value="single_note">单个单音</option>
            <option value="multi_note">多个单音（3个）</option>
          </select>
        </label>
        <label class="check">
          <input v-model="includeAccidental" type="checkbox" />
          <span>包含半音（#）</span>
        </label>
      </div>
      <button class="btn-primary" :disabled="busy" @click="startSession">开始训练</button>
      <p v-if="errorMsg" class="err">{{ errorMsg }}</p>
    </template>

    <template v-else-if="stage === 'quiz' && currentQuestion">
      <p class="progress">
        第 {{ currentQuestion.index }}/{{ currentQuestion.total_questions }} 题 · 已答对 {{ correctCount }} 题
      </p>
      <div class="actions">
        <button class="btn-secondary small" :disabled="busy" @click="playQuestion">播放标准音 + 题目</button>
        <button class="btn-secondary small" :disabled="busy" @click="replayQuestion">重播本题</button>
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
        <button class="btn-secondary small" :disabled="busy || reveal" @click="undoAnswer">撤销一步</button>
        <button class="btn-secondary small" :disabled="busy || reveal" @click="clearAnswer">清空</button>
      </div>

      <button class="btn-primary" :disabled="busy || !canSubmit || reveal" @click="submitAnswer">
        提交答案
      </button>
      <button v-if="reveal" class="btn-primary" :disabled="busy" @click="nextQuestion">下一题</button>

      <p v-if="feedback" :class="feedback.is_correct ? 'ok' : 'err'" class="feedback">
        {{
          feedback.is_correct
            ? `回答正确：${feedback.correct_answers.join(' - ')}`
            : `回答错误：正确答案是 ${feedback.correct_answers.join(' - ')}`
        }}
      </p>
      <p v-if="errorMsg" class="err">{{ errorMsg }}</p>
    </template>

    <template v-else>
      <h3 class="result-title">训练结果</h3>
      <p class="result-line">
        正确 {{ summary.correct }}/{{ summary.total }}（{{ formatPercent(summary.accuracy) }}）
      </p>
      <p class="muted">模式：{{ modeLabel }}</p>
      <div v-if="wrongs.length" class="wrong-box">
        <strong>错题回顾</strong>
        <ul>
          <li v-for="item in wrongs" :key="item.question_id">
            你的答案：{{ item.user_answers.join(' - ') || '-' }}；正确：{{ item.correct_answers.join(' - ') }}
          </li>
        </ul>
      </div>
      <button class="btn-primary" :disabled="busy" @click="resetAll">再来一组</button>
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
const modeLabel = computed(() => (mode.value === 'single_note' ? '单个单音' : '多个单音（3个）'))

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
</style>

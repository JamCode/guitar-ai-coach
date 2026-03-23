<template>
  <div class="tech-wrap">
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
          @click="selectedStyle = s"
        >
          {{ s }}
        </button>
      </div>

      <button class="generate-btn" type="button" @click="onGenerate">
        生成和弦
      </button>

      <div class="result" aria-live="polite">
        <div class="result-head">和弦进行（{{ selectedStyle }}）</div>

        <div v-if="isGenerating" class="result-loading">生成中...</div>

        <ul v-else-if="progressions.length" class="progressions">
          <li v-for="(p, i) in progressions" :key="i">
            <span class="num">{{ i + 1 }}.</span>
            <span class="prog">{{ p }}</span>
          </li>
        </ul>

        <div v-else class="result-empty">点击上面的「生成和弦」获取和弦进行</div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'

const styles = ref<string[]>(['流行', '民谣', '摇滚', '抒情', '校园', '轻摇滚', '国风', 'R&B'])
const selectedStyle = ref<string>('流行')

const isGenerating = ref(false)
const progressions = ref<string[]>([])

const progressionPool: Record<string, string[]> = {
  '流行': [
    'C - Am - F - G',
    'Em - C - G - D',
    'F - Dm - Bb - C',
    'Am - F - C - G',
    'Dm - Bb - F - C',
  ],
  '民谣': [
    'Am - G - F - E7',
    'C - G - Am - F',
    'Dm - Bb - C - Am',
    'Em - D - C - B7',
    'G - Em - C - D',
  ],
  '摇滚': [
    'Am - C - G - D',
    'Em - C - G - D',
    'G - D - Em - C',
    'A - E - F#m - D',
    'Dm - Bb - C - Am',
  ],
  '抒情': [
    'C - G/B - Am - F',
    'Dm - Bb - F - C',
    'Em - C - D - B7',
    'F - Dm - Gm - C7',
    'Am - F - C - G (更柔和的落点)',
  ],
  '校园': [
    'C - Em - F - G',
    'Am - Em - F - C',
    'G - D - Em - C',
    'F - G - Am - Em',
    'Dm - G - C - Am',
  ],
  '轻摇滚': [
    'Em - C - G - D',
    'D - A - Bm - G',
    'A - E - F#m - D',
    'G - Bm - C - D',
    'Am - F - G - Em',
  ],
  '国风': [
    'Am - Em - F - E7',
    'Dm - G - C - A7',
    'C - G - Am - Em',
    'Dm - Bb - F - C（偏古典走向）',
    'Em - C - Am - B7（旋律导向）',
  ],
  'R&B': [
    'Am7 - D7 - Gmaj7 - Cmaj7',
    'Dm7 - G7 - Cmaj7 - Bm7b5',
    'Em7 - A7 - Dmaj7 - B7',
    'Cmaj7 - Am7 - Dm7 - G7',
    'Fm7 - Bb7 - Ebmaj7 - Abmaj7',
  ],
}

function pickRandomUnique(arr: string[], count: number) {
  const copy = [...arr]
  const out: string[] = []
  const n = Math.min(count, copy.length)
  for (let i = 0; i < n; i++) {
    const idx = Math.floor(Math.random() * copy.length)
    out.push(copy[idx])
    copy.splice(idx, 1)
  }
  return out
}

function onGenerate() {
  isGenerating.value = true
  progressions.value = []

  // 这里先用前端内置示例生成；接后端后把 selectedStyle 发给接口即可。
  const pool = progressionPool[selectedStyle.value] ?? progressionPool['流行']

  setTimeout(() => {
    progressions.value = pickRandomUnique(pool, 4)
    isGenerating.value = false
  }, 350)
}
</script>

<style scoped>
.tech-wrap {
  width: 100%;
  display: flex;
  justify-content: center;
  padding: 40px 16px;
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

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-bottom: 18px;
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

.result-loading,
.result-empty {
  font-size: 13px;
  color: rgba(17, 17, 17, 0.6);
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

.progressions li {
  display: flex;
  align-items: baseline;
  gap: 8px;
  padding: 10px 12px;
  border-radius: 12px;
  border: 1px solid rgba(0, 0, 0, 0.06);
  background: rgba(0, 0, 0, 0.02);
}

.num {
  width: 28px;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  color: rgba(17, 17, 17, 0.55);
  font-size: 13px;
}

.prog {
  font-weight: 700;
  font-size: 14px;
  color: #111111;
}

@media (prefers-color-scheme: dark) {
  .result {
    border-top-color: rgba(255, 255, 255, 0.12);
  }

  .result-head {
    color: #f8f8f8;
  }

  .result-loading,
  .result-empty {
    color: rgba(248, 248, 248, 0.65);
  }

  .progressions li {
    border-color: rgba(255, 255, 255, 0.12);
    background: rgba(255, 255, 255, 0.06);
  }

  .num {
    color: rgba(248, 248, 248, 0.6);
  }

  .prog {
    color: #f8f8f8;
  }
}
</style>


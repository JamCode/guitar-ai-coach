<!--
  ChordDiagram — 吉他和弦指法示意图（纯 SVG）
  父组件（App.vue 抽屉）传入每根弦品位、手指编号、起始品位与横按信息，本组件负责指板布局与绘制。
-->
<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  frets: number[]
  fingers: (number | null)[] | null
  baseFret: number
  barre?: { fret: number; from_string: number; to_string: number } | null
}>()

// 画布与指板几何（与 viewBox 一致，单位 px）
const W = 200
const H = 168
const nutY = 32
const fretH = 26
const leftX = 22
const stringSpan = W - 2 * leftX

/** 根据已按弦品位决定显示从第几品起、画几格品丝，避免高把位和弦挤在一角 */
const layout = computed(() => {
  const frets = props.frets
  let base = Math.max(1, props.baseFret)
  const pressed = frets.filter((f) => f > 0)
  if (pressed.length) {
    const mn = Math.min(...pressed)
    if (base > mn) base = mn
  }
  const maxF = pressed.length ? Math.max(...pressed) : base
  const span = Math.max(1, maxF - base + 1)
  const rows = Math.min(5, Math.max(4, span))
  return { base, rows, maxF }
})

function stringX(i: number) {
  return leftX + (i * stringSpan) / 5
}

function dotY(absFret: number) {
  const { base } = layout.value
  const row = absFret - base + 1
  return nutY + (row - 0.5) * fretH
}

/** 某弦上的手指编号（0/空表示不显示数字） */
function fingerAt(idx: number): number | null {
  const f = props.fingers
  if (!f || f[idx] == null) return null
  const n = f[idx]!
  return n > 0 ? n : null
}

/** 横按线在 SVG 中的 y 与两端 x（弦索引与 props 的 from_string/to_string 一致转换） */
const barreGeom = computed(() => {
  const b = props.barre
  if (!b || typeof b.fret !== 'number') return null
  const { base, rows } = layout.value
  if (b.fret < base || b.fret > base + rows - 1) return null
  const iLo = Math.min(6 - b.from_string, 6 - b.to_string)
  const iHi = Math.max(6 - b.from_string, 6 - b.to_string)
  const y = dotY(b.fret)
  const x1 = stringX(iLo)
  const x2 = stringX(iHi)
  return { y, x1, x2, cy: y }
})
</script>

<template>
  <!-- 六根弦：frets[i] 为 -1 闷音、0 空弦、>0 按品；fingers 为圆点内数字 -->
  <svg
    class="chord-svg"
    :viewBox="`0 0 ${W} ${H}`"
    width="200"
    height="168"
    aria-hidden="true"
  >
    <!-- 弦顶：× 闷音 / ○ 空弦 -->
    <g v-for="i in 6" :key="'om' + i" :transform="`translate(${stringX(i - 1)}, 0)`">
      <text
        v-if="frets[i - 1] === -1"
        x="0"
        y="18"
        text-anchor="middle"
        class="om-x"
      >
        ×
      </text>
      <circle
        v-else-if="frets[i - 1] === 0"
        cx="0"
        cy="14"
        r="5"
        fill="none"
        class="om-o"
      />
    </g>

    <!-- 琴枕（加粗横线） -->
    <line
      :x1="leftX - 4"
      :y1="nutY"
      :x2="W - leftX + 4"
      :y2="nutY"
      class="nut"
    />

    <!-- 品丝横线 -->
    <g v-for="r in layout.rows" :key="'f' + r">
      <line
        :x1="leftX - 4"
        :y1="nutY + r * fretH"
        :x2="W - leftX + 4"
        :y2="nutY + r * fretH"
        class="fret"
      />
    </g>

    <!-- 六根弦竖线 -->
    <g v-for="i in 6" :key="'s' + i">
      <line
        :x1="stringX(i - 1)"
        :y1="nutY"
        :x2="stringX(i - 1)"
        :y2="nutY + layout.rows * fretH"
        class="string"
      />
    </g>

    <!-- 横按 -->
    <line
      v-if="barreGeom"
      :x1="barreGeom.x1"
      :y1="barreGeom.y"
      :x2="barreGeom.x2"
      :y2="barreGeom.y"
      class="barre-line"
    />

    <!-- 按弦圆点 + 可选手指序号 -->
    <g v-for="i in 6" :key="'d' + i">
      <template v-if="frets[i - 1] > 0">
        <circle
          :cx="stringX(i - 1)"
          :cy="dotY(frets[i - 1])"
          r="9"
          class="dot"
        />
        <text
          v-if="fingerAt(i - 1) != null"
          :x="stringX(i - 1)"
          :y="dotY(frets[i - 1]) + 4"
          text-anchor="middle"
          class="finger-num"
        >
          {{ fingerAt(i - 1) }}
        </text>
      </template>
    </g>

    <!-- 高把位时左侧标注起始品位 -->
    <text v-if="layout.base > 1" x="4" :y="nutY + fretH * 0.75" class="base-label">
      {{ layout.base }}fr
    </text>
  </svg>
</template>

<style scoped>
.chord-svg {
  display: block;
  margin: 0 auto 12px;
}
.nut {
  stroke: currentColor;
  stroke-width: 4;
}
.fret {
  stroke: currentColor;
  stroke-width: 1;
  opacity: 0.35;
}
.string {
  stroke: currentColor;
  stroke-width: 1.2;
  opacity: 0.45;
}
.dot {
  fill: currentColor;
  opacity: 0.92;
}
.finger-num {
  fill: #fff;
  font-size: 11px;
  font-weight: 800;
}
.om-x {
  fill: currentColor;
  font-size: 15px;
  font-weight: 700;
  opacity: 0.7;
}
.om-o {
  stroke: currentColor;
  stroke-width: 1.5;
  opacity: 0.65;
}
.barre-line {
  stroke: currentColor;
  stroke-width: 5;
  stroke-linecap: round;
  opacity: 0.85;
}
.base-label {
  fill: currentColor;
  font-size: 11px;
  font-weight: 700;
  opacity: 0.65;
}
</style>

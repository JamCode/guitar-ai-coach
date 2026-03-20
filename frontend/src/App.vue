<template>
  <div id="app">
    <h1>Guitar AI Coach</h1>
    <p>
      这个 PWA 脚手架支持离线缓存与“添加到主屏幕”。你可以继续在
      `src/App.vue` 里做业务扩展。
    </p>
    <button class="counter" type="button" @click="count++">
      count: {{ count }}
    </button>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'

const count = ref(0)
</script>


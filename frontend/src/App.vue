<!--
  应用壳：路由视图 + 底部 Tab（与需求原型一致）。
-->
<template>
  <div class="app-shell">
    <main class="app-main">
      <RouterView />
    </main>
    <nav class="tab-bar" aria-label="主导航">
      <RouterLink class="tab" active-class="tab--active" to="/">
        <span class="tab-ico" aria-hidden="true">🎸</span>
        <span>和弦进行</span>
      </RouterLink>
      <RouterLink class="tab" active-class="tab--active" to="/dictionary">
        <span class="tab-ico" aria-hidden="true">📖</span>
        <span>和弦字典</span>
      </RouterLink>
      <RouterLink class="tab" active-class="tab--active" to="/quiz">
        <span class="tab-ico" aria-hidden="true">🎵</span>
        <span>训练题库</span>
      </RouterLink>
      <RouterLink class="tab" active-class="tab--active" to="/ear">
        <span class="tab-ico" aria-hidden="true">👂</span>
        <span>练耳训练</span>
      </RouterLink>
    </nav>
  </div>
</template>

<script setup lang="ts">
import { RouterLink, RouterView } from 'vue-router'
</script>

<style>
/* 全局底栏：子页面用 padding-bottom 留白 */
.app-shell {
  min-height: 100dvh;
  box-sizing: border-box;
}

.app-main {
  min-height: 100%;
}

.tab-bar {
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 200;
  display: flex;
  background: #ffffff;
  border-top: 1px solid #e5e5e5;
  padding-bottom: env(safe-area-inset-bottom, 0px);
  box-shadow: 0 -4px 20px rgba(0, 0, 0, 0.06);
}

.tab-bar .tab {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 2px;
  padding: 8px 6px 10px;
  text-decoration: none;
  color: rgba(28, 24, 36, 0.52);
  font-size: 11px;
  font-weight: 600;
  border-top: 3px solid transparent;
  min-height: 52px;
  box-sizing: border-box;
}

.tab-bar .tab:hover {
  color: #2a2633;
  background: #fafafa;
}

.tab-bar .tab--active {
  color: #2a2633;
  border-top-color: #2a2633;
  font-weight: 800;
}

.tab-bar .tab-ico {
  font-size: 20px;
  line-height: 1;
}

@media (prefers-color-scheme: dark) {
  .tab-bar {
    background: rgba(15, 15, 18, 0.98);
    border-top-color: rgba(255, 255, 255, 0.12);
  }
  .tab-bar .tab {
    color: rgba(216, 220, 230, 0.55);
  }
  .tab-bar .tab:hover {
    color: #d8dce6;
    background: rgba(255, 255, 255, 0.06);
  }
  .tab-bar .tab--active {
    color: #d8dce6;
    border-top-color: rgba(255, 255, 255, 0.85);
  }
}
</style>

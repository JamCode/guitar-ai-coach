import { createApp } from 'vue'
import { registerSW } from 'virtual:pwa-register'
import './style.css'
import App from './App.vue'

// Service Worker 注册（用于在需要时自动更新页面）
registerSW({
  onNeedRefresh() {
    window.location.reload()
  },
})

createApp(App).mount('#app')

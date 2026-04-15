/**
 * 前端入口：Vue Router + App 壳，注册 PWA Service Worker。
 */
import { createApp } from 'vue'
import { registerSW } from 'virtual:pwa-register'
import './style.css'
import App from './App.vue'
import { router } from './router'

registerSW({
  onNeedRefresh() {
    window.location.reload()
  },
})

createApp(App).use(router).mount('#app')

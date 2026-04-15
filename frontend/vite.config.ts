/**
 * Vite 构建配置：Vue 单页应用 + PWA（离线缓存、manifest、应用名来自环境变量）。
 */
import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const appName = env.VITE_APP_NAME || '吉他AI教练'
  const appShortName = env.VITE_APP_SHORT_NAME || '吉他教练'
  const appDescription = env.VITE_APP_DESCRIPTION || '吉他AI教练 - 支持离线访问'

  return {
    plugins: [
      vue(),
      VitePWA({
      // 生产环境会自动注册 service worker；开发环境也能快速验证
      devOptions: {
        enabled: true,
      },
      // 让新版 SW 自动更新并刷新页面
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg', 'apple-touch-icon.png'],
      manifest: {
        name: appName,
        short_name: appShortName,
        description: appDescription,
        theme_color: '#0B0B0F',
        background_color: '#0B0B0F',
        display: 'standalone',
        icons: [
          {
            src: '/pwa-192x192.png',
            sizes: '192x192',
            type: 'image/png',
          },
          {
            src: '/pwa-512x512.png',
            sizes: '512x512',
            type: 'image/png',
          },
          {
            src: '/maskable-512x512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        // 简单的运行时缓存策略：页面网络优先，静态资源缓存优先
        runtimeCaching: [
          {
            urlPattern: ({ request }) =>
              request.destination === 'document' || request.mode === 'navigate',
            handler: 'NetworkFirst',
            options: {
              cacheName: 'html-cache',
              networkTimeoutSeconds: 10,
            },
          },
          {
            urlPattern: ({ request }) => request.destination === 'image',
            handler: 'CacheFirst',
            options: {
              cacheName: 'image-cache',
              expiration: {
                maxEntries: 60,
                maxAgeSeconds: 30 * 24 * 60 * 60,
              },
            },
          },
        ],
      },
      }),
    ],
  }
})


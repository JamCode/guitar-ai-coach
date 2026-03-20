import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    vue(),
    VitePWA({
      // 生产环境会自动注册 service worker；开发环境也能快速验证
      devOptions: {
        enabled: true,
      },
      // 让新版 SW 自动更新并刷新页面
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg'],
      manifest: {
        name: 'Guitar AI Coach',
        short_name: 'GuitarAI',
        description: 'Guitar AI Coach - offline capable',
        theme_color: '#0B0B0F',
        background_color: '#0B0B0F',
        display: 'standalone',
        icons: [
          {
            src: '/favicon.svg',
            sizes: 'any',
            type: 'image/svg+xml',
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
})


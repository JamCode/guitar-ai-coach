import { createRouter, createWebHistory } from 'vue-router'
import ProgressionView from './views/ProgressionView.vue'
import ChordDictionaryView from './views/ChordDictionaryView.vue'
import QuizTrainingView from './views/QuizTrainingView.vue'
import EarTrainingView from './views/EarTrainingView.vue'

export const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    { path: '/', name: 'progression', component: ProgressionView },
    { path: '/dictionary', name: 'dictionary', component: ChordDictionaryView },
    { path: '/quiz', name: 'quiz', component: QuizTrainingView },
    { path: '/ear', name: 'ear', component: EarTrainingView },
    { path: '/song-chords', redirect: '/' },
  ],
})

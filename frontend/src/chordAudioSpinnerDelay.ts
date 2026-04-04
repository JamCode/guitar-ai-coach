/** 试听加载超过该时长后再显示转圈，避免快路径闪一下 */
export const CHORD_AUDIO_SPINNER_DELAY_MS = 1000

/** 返回取消函数：清除 timeout，应在 finally / 停止播放时调用 */
export function startChordSlowSpinnerTimer(onShow: () => void): () => void {
  const id = window.setTimeout(onShow, CHORD_AUDIO_SPINNER_DELAY_MS)
  return () => {
    window.clearTimeout(id)
  }
}

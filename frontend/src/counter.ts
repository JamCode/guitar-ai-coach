/**
 * Vite 模板遗留示例（当前项目未引用）。若删除需同步清理 style.css 中的 .counter 样式。
 */
export function setupCounter(element: HTMLButtonElement) {
  let counter = 0
  const setCounter = (count: number) => {
    counter = count
    element.innerHTML = `Count is ${counter}`
  }
  element.addEventListener('click', () => setCounter(counter + 1))
  setCounter(0)
}

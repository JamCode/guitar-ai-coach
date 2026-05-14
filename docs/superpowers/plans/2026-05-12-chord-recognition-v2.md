# Chord Recognition v2 后端实施计划

> **Goal:** 用 chroma + beat-sync + HMM 替换 ONNX 模型推理，提升和弦识别精度，保持 API 接口完全兼容。
>
> **Architecture:** 音频加载 → chroma_cens 提取 → beat tracking → 每拍聚合 chroma → 调性估计 → HMM Viterbi 和弦解码 → 复用现有 postprocess 管线。
>
> **Tech Stack:** Python, librosa, numpy, FastAPI（已有）

---

### Task 1: 环境准备和阅读现有代码

**文件：**
- 参考：`backend/chord_onnx_server/inference.py`
- 参考：`backend/chord_onnx_server/app.py`
- 参考：`backend/chord_onnx_server/requirements.txt`

- [ ] **Step 1: 确认已有依赖可用**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach/backend/chord_onnx_server
source .venv/bin/activate 2>/dev/null || python3 -m venv .venv && source .venv/bin/activate
pip install librosa numpy
# onnxruntime 可以保留（不卸载也没影响），只是不再调用
```

- [ ] **Step 2: 阅读 inference.py 并标记需要保留的方法**

需要在 `inference.py` 中保留的方法：
- `load_audio_mono_22050()`
- `ffmpeg_available()` / `_decode_to_temp_wav_with_ffmpeg()`
- `_merge_adjacent_segments()`
- `_make_display_segments()`
- `_make_simplified_segments()`
- `_simplify_display_chord()`
- `_merge_labels()`
- `_estimate_key()` → 改进
- `_score_key_candidate()` → 改进
- `_parse_chord()` → 改进
- `_quality_adjustment()` → 改进
- `_collect_boundary_frame_diagnostics()`
- `_build_display_chord_text()`

需要删除的方法：
- `__init__` 中的 ONNX 初始化
- `_extract_cqt_features()`
- `_adapt_input_shape()`
- `_decode_outputs()` 及其所有子方法（`_decode_frame_prediction`, `_select_quality_candidate` 等）
- `_stabilize_frame_labels()` 及其子方法
- 所有 ONNX 常量

---

### Task 2: 实现 chroma 提取和 beat tracking

**文件：**
- 修改：`backend/chord_onnx_server/inference.py`

**核心思路：** `librosa.chroma_cens()` 提取 12 维 chroma，`librosa.beat.beat_track()` 检测拍点，按拍聚合。

- [ ] **Step 1: 在 inference.py 顶部新增 chroma/beat 常量**

```python
# 新增在现有常量之后
CHROMA_HOP_LENGTH = 512
CHROMA_N_CHROMA = 12          # 12 个半音
BEAT_HOP_LENGTH = 512
```

- [ ] **Step 2: 新增 `_extract_chroma()` 方法**

```python
def _extract_chroma(self, y: np.ndarray) -> np.ndarray:
    """提取 12 维 CENS chroma。返回 (12, n_frames)。"""
    if y.size == 0:
        return np.zeros((CHROMA_N_CHROMA, 1), dtype=np.float32)
    chroma = librosa.feature.chroma_cens(
        y=y,
        sr=TARGET_SR,
        hop_length=CHROMA_HOP_LENGTH,
        n_chroma=CHROMA_N_CHROMA,
    )
    return chroma.astype(np.float32)
```

- [ ] **Step 3: 新增 `_beat_track()` 方法**

```python
def _beat_track(self, y: np.ndarray) -> tuple[float, np.ndarray]:
    """返回 (tempo_bpm, beat_frame_indices)。"""
    if y.size < TARGET_SR:  # 太短的音频返回默认拍点
        return 120.0, np.array([0])
    tempo, beats = librosa.beat.beat_track(
        y=y, sr=TARGET_SR, hop_length=BEAT_HOP_LENGTH, units='frames'
    )
    if len(beats) < 2:
        return float(tempo), np.array([0, len(y) // BEAT_HOP_LENGTH])
    return float(tempo), beats
```

- [ ] **Step 4: 新增 `_aggregate_per_beat()` 方法**

```python
def _aggregate_per_beat(self, chroma: np.ndarray, beat_frames: np.ndarray) -> np.ndarray:
    """每拍聚合 chroma 向量。返回 (n_beats, 12)。"""
    n_beats = len(beat_frames)
    if n_beats < 2:
        # 没有有效拍点，fallback: 等分
        n_frames = chroma.shape[1]
        seg_size = max(1, n_frames // 8)
        beat_frames = np.arange(0, n_frames, seg_size, dtype=int)
        if beat_frames[-1] < n_frames:
            beat_frames = np.append(beat_frames, n_frames)
        n_beats = len(beat_frames) - 1
    
    result = np.zeros((n_beats - 1, CHROMA_N_CHROMA), dtype=np.float32)
    for i in range(n_beats - 1):
        start = int(beat_frames[i])
        end = int(beat_frames[i + 1])
        if end <= start:
            result[i] = chroma[:, start] if start < chroma.shape[1] else chroma[:, -1]
        else:
            result[i] = np.median(chroma[:, start:end], axis=1)
    
    # 归一化
    row_sums = np.sum(result, axis=1, keepdims=True)
    row_sums = np.maximum(row_sums, 1e-10)
    result = result / row_sums
    
    return result
```

- [ ] **Step 5: 写一个简单测试验证 chroma + beat 输出正确**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach/backend/chord_onnx_server
python3 -c "
import numpy as np
import librosa
# 测试: 纯正弦波 (A440) 的 chroma 应该在 index 9 最强
sr = 22050
t = np.linspace(0, 2.0, int(sr * 2.0), endpoint=False)
y = np.sin(2.0 * np.pi * 440.0 * t)  # A4
chroma = librosa.feature.chroma_cens(y=y, sr=sr, hop_length=512)
mean_chroma = np.mean(chroma, axis=1)
peak_idx = int(np.argmax(mean_chroma))
print(f'Chroma peak at index {peak_idx} (expect ~9 for A): {\"PASS\" if peak_idx == 9 else \"FAIL\"}')"
```

---

### Task 3: 构建和弦模板库

**文件：**
- 修改：`backend/chord_onnx_server/inference.py`

- [ ] **Step 1: 定义和弦质量模板（12 个半音的 chroma profile）**

```python
# 质量模板（相对根音，12 个半音向量）
CHORD_QUALITY_TEMPLATES = {
    '':    [1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0],  # major
    'm':   [1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0],  # minor
    '7':   [1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0],  # dominant 7th
    'm7':  [1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0],  # minor 7th
    'maj7': [1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1], # major 7th
    'dim':  [1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0],  # diminished
    'aug':  [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],  # augmented
    'sus4': [1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0],  # sus4
    'sus2': [1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0],  # sus2
    '5':    [1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0],  # power chord
}

NOTE_NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
```

- [ ] **Step 2: 新增 `_build_chord_templates()` 方法**

```python
def _build_chord_templates(self) -> dict[str, np.ndarray]:
    """生成所有根音 × 质量的 chroma 模板。返回 {chord_name: profile_vector}。"""
    templates = {}
    for root_idx in range(12):
        root_name = NOTE_NAMES[root_idx]
        for suffix, profile in CHORD_QUALITY_TEMPLATES.items():
            # 循环移位到对应根音
            shifted = np.roll(profile, root_idx)
            name = f"{root_name}{suffix}"
            templates[name] = shifted.astype(np.float32)
    return templates

# 在 __init__ 中调用：
# self.chord_templates = self._build_chord_templates()
# self.template_names = sorted(self.chord_templates.keys())
# self.template_matrix = np.array([self.chord_templates[n] for n in self.template_names])
```

- [ ] **Step 3: 验证模板生成正确**

```bash
python3 -c "
import numpy as np
NOTE_NAMES = ['C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B']
profile = [1,0,0,0,1,0,0,1,0,0,0,0]
# C 模板：index 0,4,7 为 1
shifted = np.roll(profile, 3)
print(f'Eb: {shifted}')  # index 3,7,10 应为 1
assert shifted[3] == 1 and shifted[7] == 1 and shifted[10] == 1, 'FAIL'
print('PASS')"
```

---

### Task 4: 实现 HMM Viterbi 解码

**文件：**
- 修改：`backend/chord_onnx_server/inference.py`

- [ ] **Step 1: 定义调性-和弦映射**

```python
# 每个调性内可用的和弦（音符集约束）
MAJOR_KEY_CHORDS = {
    'C':  ['C', 'Dm', 'Em', 'F', 'G', 'G7', 'Am', 'Bdim'],
    'G':  ['G', 'Am', 'Bm', 'C', 'D', 'D7', 'Em', 'F#dim'],
    'D':  ['D', 'Em', 'F#m', 'G', 'A', 'A7', 'Bm', 'C#dim'],
    'A':  ['A', 'Bm', 'C#m', 'D', 'E', 'E7', 'F#m', 'G#dim'],
    'E':  ['E', 'F#m', 'G#m', 'A', 'B', 'B7', 'C#m', 'D#dim'],
    'F':  ['F', 'Gm', 'Am', 'Bb', 'C', 'C7', 'Dm', 'Edim'],
    'Bb': ['Bb', 'Cm', 'Dm', 'Eb', 'F', 'F7', 'Gm', 'Adim'],
    'Eb': ['Eb', 'Fm', 'Gm', 'Ab', 'Bb', 'Bb7', 'Cm', 'Ddim'],
    'Ab': ['Ab', 'Bbm', 'Cm', 'Db', 'Eb', 'Eb7', 'Fm', 'Gdim'],
}
```

- [ ] **Step 2: 新增 `_get_key_consistent_states()`**

```python
def _get_key_consistent_states(self, key: str) -> list[str]:
    """根据估计调性返回可选和弦列表，fallback 到全部模板。"""
    root = key.rstrip('m')  # 去掉 m 后缀
    if root in MAJOR_KEY_CHORDS:
        return MAJOR_KEY_CHORDS[root]
    # 小调用关系大调
    relative_major = {'Am': 'C', 'Em': 'G', 'Bm': 'D', 'F#m': 'A', 'C#m': 'E',
                      'Dm': 'F', 'Gm': 'Bb', 'Cm': 'Eb', 'Fm': 'Ab', 'Bbm': 'Db'}
    if key in relative_major:
        return MAJOR_KEY_CHORDS[relative_major[key]]
    # fallback
    return self.template_names
```

- [ ] **Step 3: 新增 `_build_transition_matrix()`**

```python
def _build_transition_matrix(self, state_names: list[str]) -> np.ndarray:
    """基于音乐理论构建和弦转移概率矩阵。"""
    n = len(state_names)
    trans = np.full((n, n), 0.001, dtype=np.float32)  # 极小概率
    
    # 同一和弦延续的高概率
    np.fill_diagonal(trans, 0.6)
    
    # 五度圈（升四度/降五度）
    circle_of_fifths_up = {'C': 'F', 'G': 'C', 'D': 'G', 'A': 'D', 'E': 'A',
                           'F': 'Bb', 'Bb': 'Eb', 'Eb': 'Ab'}
    circle_of_fifths_down = {'C': 'G', 'F': 'C', 'Bb': 'F', 'Eb': 'Bb',
                             'G': 'D', 'D': 'A', 'A': 'E'}
    
    for i, chord_a in enumerate(state_names):
        root_a = chord_a.rstrip('m').rstrip('7').rstrip('dim')
        for j, chord_b in enumerate(state_names):
            if i == j:
                continue
            root_b = chord_b.rstrip('m').rstrip('7').rstrip('dim')
            
            # 五度圈进行: V → I
            if circle_of_fifths_up.get(root_a) == root_b:
                trans[i, j] = 0.15
            # 五度圈反向: I → V
            elif circle_of_fifths_down.get(root_a) == root_b:
                trans[i, j] = 0.12
            # 关系大小调互换: I ↔ vi
            elif (chord_a.rstrip('m') == root_b and chord_b.endswith('m')) or \
                 (chord_b.rstrip('m') == root_a and chord_a.endswith('m')):
                trans[i, j] = 0.10
            # 其他
            else:
                trans[i, j] = 0.03
    
    # 归一化
    row_sums = trans.sum(axis=1, keepdims=True)
    trans = trans / np.maximum(row_sums, 1e-10)
    return trans
```

- [ ] **Step 4: 新增 `_viterbi_decode()`**

```python
def _viterbi_decode(
    self,
    observations: np.ndarray,      # (n_beats, 12)
    state_names: list[str],
) -> list[str]:
    """Viterbi 解码，返回每拍的和弦名。"""
    n_states = len(state_names)
    n_steps = observations.shape[0]
    
    # 获得对应的模板矩阵 (n_states, 12)
    template_matrix = np.array([self.chord_templates[name] for name in state_names])
    
    # 发射概率：cosine similarity
    emission = np.zeros((n_steps, n_states), dtype=np.float32)
    for t in range(n_steps):
        obs = observations[t]
        obs_norm = np.linalg.norm(obs)
        if obs_norm > 1e-10:
            obs_u = obs / obs_norm
            templ_norms = np.linalg.norm(template_matrix, axis=1)
            templ_u = template_matrix / np.maximum(templ_norms[:, np.newaxis], 1e-10)
            sim = obs_u @ templ_u.T
            emission[t] = np.clip(sim, 0.0, 1.0) ** 2  # 平方放大差异
    
    # 转移矩阵
    trans = self._build_transition_matrix(state_names)
    log_trans = np.log(np.maximum(trans, 1e-10))
    
    # Viterbi
    nlog = -np.log(np.maximum(emission, 1e-10))
    delta = nlog[0].copy()
    psi = np.zeros((n_steps, n_states), dtype=np.int32)
    
    for t in range(1, n_steps):
        for j in range(n_states):
            candidates = delta + log_trans[:, j]
            best_i = int(np.argmin(candidates))
            psi[t, j] = best_i
            delta[j] = candidates[best_i] + nlog[t, j]
    
    # Backtrack
    path = [int(np.argmin(delta))]
    for t in range(n_steps - 1, 0, -1):
        path.insert(0, int(psi[t, path[0]]))
    
    return [state_names[s] for s in path]
```

---

### Task 5: 重写 `transcribe()` 方法和更新 `__init__`

**文件：**
- 修改：`backend/chord_onnx_server/inference.py`

- [ ] **Step 1: 重写 `ChordOnnxInferenceService.__init__()`**

```python
class ChordOnnxInferenceService:
    def __init__(self, model_path: Path | None = None):
        # 不再依赖 ONNX 模型，model_path 参数保留是为了兼容
        self.chord_templates = self._build_chord_templates()
        self.template_names = sorted(self.chord_templates.keys())
```

- [ ] **Step 2: 重写 `transcribe()` 方法的核心推理部分**

将 `transcribe()` 方法中调 ONNX 模型的部分替换为 chroma + beat + HMM 路径。
原有框架（加载 → 推理 → 后处理）保持不变，替换中间的推理段落（第 150-221 行）。

```python
# 替代原本的 ONNX 推理循环（替代 inference.py 第 146-221 行）
def transcribe(self, audio_path: Path) -> dict[str, Any]:
    y = load_audio_mono_22050(audio_path)
    sr = TARGET_SR
    duration = float(len(y) / TARGET_SR)
    
    # --- 新流程 ---
    chroma = self._extract_chroma(y)                    # (12, n_frames)
    tempo, beat_frames = self._beat_track(y)            # beats in frames
    beat_chromas = self._aggregate_per_beat(chroma, beat_frames)  # (n_beats-1, 12)
    
    # Key estimation (on beat-level chroma)
    # ... (改进版 _estimate_key)
    
    # HMM decode
    states = self._get_key_consistent_states(key_result['key'])
    best_labels = self._viterbi_decode(beat_chromas, states)
    
    # Convert beat labels to time segments
    beat_times = librosa.frames_to_time(beat_frames, sr=TARGET_SR, hop_length=CHROMA_HOP_LENGTH)
    segments = []
    for i, label in enumerate(best_labels):
        if i < len(beat_times) - 1 and label != 'N':
            segments.append(Segment(
                start=round(float(beat_times[i]), 3),
                end=round(float(beat_times[i+1]), 3),
                chord=label,
            ))
    
    # --- 以下复用现有后处理 ---
    merged_segments = self._merge_adjacent_segments(segments, tolerance_sec=0.05)
    display_segments, display_stats = self._make_display_segments(merged_segments)
    simplified_segments = self._make_simplified_segments(display_segments)
    key_result = self._estimate_key(merged_segments)  # 也用 segments 跑一次
    # ... (后续 chart/timing/playable 处理完全不变)
```

返回的 dict 字段格式不变。

---

### Task 6: 更新 `app.py`

**文件：**
- 修改：`backend/chord_onnx_server/app.py`

- [ ] **Step 1: 修改导入（第 16 行附近）**

```python
# 删除 InferenceInputShapeError 导入
from chord_auth import APP_TOKEN_ENV, app_token_status, configured_app_token
from inference import ChordOnnxInferenceService, ffmpeg_available
```

- [ ] **Step 2: 移除 ONNX model 路径和初始化调整（第 21、30 行）**

```python
# 删除 MODEL_PATH 定义
# MAX_UPLOAD_BYTES 等保留

# 初始化取消 model_path 参数
service = ChordOnnxInferenceService()
```

- [ ] **Step 3: 删除启动时的 model_info 打印（第 136-144 行）**

```python
@app.on_event("startup")
def _startup_log_model() -> None:
    print("[SERVICE] ffmpeg on PATH:", ffmpeg_available())
```

- [ ] **Step 4: 删除 `InferenceInputShapeError` 异常处理（第 266-281 行）**

删除整个 `except InferenceInputShapeError` 块。

- [ ] **Step 5: 验证改动**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach/backend/chord_onnx_server
python3 -c "from app import app; print('app imported OK')"
```

---

### Task 7: 集成测试

**文件：**
- 测试：使用 `eval_audio/` 下的文件和 `transcribe_batch.py`

- [ ] **Step 1: 启动服务并测试音频文件**

```bash
# 终端 1: 启动服务
cd /Users/wanghan/Documents/guitar-ai-coach/backend/chord_onnx_server
BACKEND_HOST=127.0.0.1 CHORD_ONNX_APP_TOKEN=test_token python3 -c "
import uvicorn
uvicorn.run('app:app', host='127.0.0.1', port=8000)
"

# 终端 2: 运行批量测试
cd /Users/wanghan/Documents/guitar-ai-coach/backend/chord_onnx_server
CHORD_ONNX_APP_TOKEN=test_token python3 transcribe_batch.py eval_audio/yanyuan.m4a --out-dir outputs/test_v2
```

- [ ] **Step 2: 验证输出字段完整性**

```bash
python3 -c "
import json
with open('outputs/test_v2/yanyuan.json') as f:
    data = json.load(f)
assert data['success'] == True, 'success field missing'
assert 'segments' in data, 'segments missing'
assert 'displaySegments' in data, 'displaySegments missing'
assert 'chordChartSegments' in data, 'chordChartSegments missing'
assert 'timingVariants' in data, 'timingVariants missing'
assert 'duration' in data and data['duration'] > 0, 'duration missing'
print(f'OK: duration={data[\"duration\"]}s, segments={len(data[\"segments\"])}, '
      f'chordChart={len(data[\"chordChartSegments\"])}')"
```

- [ ] **Step 3: 与旧版结果做对比**

```bash
# 如果有旧版输出，对比和弦列表差异
python3 -c "
import json
with open('outputs/test_v2/yanyuan.json') as f:
    new = json.load(f)
# 对比 chordChartSegments
charts = new.get('chordChartSegments', [])
for s in charts[:20]:
    print(f\"{s['start']:6.1f}s - {s['end']:6.1f}s  {s['chord']}\")"
```

---

### Task 8（可选）：LLM 精修后处理

**文件：**
- 新建：`backend/chord_onnx_server/llm_refine.py`
- 修改：`backend/chord_onnx_server/inference.py`

- [ ] **Step 1: 新建 `llm_refine.py`**

```python
"""调用 DeepSeek API 精修和弦序列。"""
import json
import os
from typing import Any

DASHSCOPE_API_KEY_ENV = "DASHSCOPE_API_KEY"


def refine_chord_sequence(
    segments: list[dict[str, Any]],
    estimated_key: str,
) -> list[dict[str, Any]]:
    """
    用大模型修正可疑的和弦序列。
    仅在置信度较低时调用（可配置阈值）。
    """
    api_key = os.getenv(DASHSCOPE_API_KEY_ENV, "").strip()
    if not api_key:
        return segments  # 无 API key 则跳过
    
    chord_text = " | ".join(
        f"{s['chord']} {s['end'] - s['start']:.1f}s" for s in segments
    )
    
    prompt = (
        "你是吉他谱专家。下面是一段和弦序列，时间单位是秒。\n"
        f"调性: {estimated_key}\n"
        f"和弦序列: {chord_text}\n\n"
        "任务: 修正不符合音乐理论和常见和弦进行的部分。\n"
        "规则: \n"
        "1. 只修正明显错误的和弦（如在 C 调中出现 C#）\n"
        "2. 合并短促的不稳定片段\n"
        "3. 保持和输入完全相同的格式\n"
        "4. 如果没有问题，完全原样返回\n\n"
        "输出格式: 和弦名 时长s | 和弦名 时长s | ...\n"
    )
    
    # 调用 DeepSeek API（复用已有环境变量）
    # ...
    
    return segments
```

- [ ] **Step 2: 在 `transcribe()` 中可选择性调用**

```python
if os.getenv("CHORD_REFINE_WITH_LLM", "").strip().lower() in {"1", "true"}:
    try:
        from llm_refine import refine_chord_sequence
        refined = refine_chord_sequence(chart_segments, key_result["key"])
        if refined:
            chart_segments = refined
    except Exception:
        pass  # LLM 精修失败不影响主流程
```

---

**计划写完，请看是否需要调整。确认后就可以开始逐步实现。**

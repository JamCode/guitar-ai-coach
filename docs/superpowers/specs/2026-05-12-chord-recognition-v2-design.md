# Chord Recognition v2: Chroma + Beat-Sync + HMM 后端方案

## 动机

当前基于 `consonance_ace.onnx` 的和弦识别准确率不理想，核心问题：

- 模型太小，12 维 chroma 输出去判别 24+ 种和弦区分力不足
- 逐帧预测导致边界随机漂移、短噪音段多
- 后处理的 stabilize 是启发式的 patch，不是系统性的解决方案

## 架构

```
音频文件 (.wav/.mp3/.m4a)
  │
  ▼
load_audio_mono_22050()  ← 复用现有
  │
  ├─┬─ _extract_chroma()          ← 新增：librosa chroma_cens
  │ └─ _beat_track()              ← 新增：librosa beat_track
  │
  ▼
_aggregate_per_beat()             ← 新增：每拍聚合 chroma 向量
  │
  ▼
_estimate_key()                   ← 改进：用聚合后的 chroma 做 Krumhansl 调性估计
  │
  ▼
HMM Viterbi 解码                  ← 新增：和弦模板 + 音乐理论转移概率
  │
  ▼
merge_labels → segments           ← 复用现有
  │
  ▼
现有 postprocess 管线完全复用：
  _merge_adjacent_segments()
  _make_display_segments()
  _make_simplified_segments()
  chord_chart_postprocess.build_chord_chart_segments()
  timing_compact_postprocess.build_timing_compact_segments()
  playable_compact_postprocess.build_playable_compact_segments()
  _estimate_key()                 ← 也用 segments 再跑一次，保持兼容
```

## 核心算法

### 1. Chroma 提取

```python
chroma = librosa.feature.chroma_cens(y=y, sr=sr, hop_length=512)
# 输出: (12, n_frames)，12 个音级的增强型能量分布
```

CENS 相比普通 chroma 的优势：对动态变化、音色差异更鲁棒。

### 2. 拍点检测

```python
tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr, hop_length=512)
# beat_frames: 每拍的帧索引
```

### 3. 按拍聚合

```python
for i in range(len(beat_frames)-1):
    start, end = beat_frames[i], beat_frames[i+1]
    beat_chroma[i] = np.median(chroma[:, start:end], axis=1)
```

### 4. 和弦模板

```python
TEMPLATES = {
    'C':  [1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0],  # 大三和弦
    'Cm': [1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0],  # 小三和弦
    'C7': [1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0],  # 属七
    # ... 12个根音 × 5-7种质量 = 60-84 个模板
}
```

模板按根音转调生成，不是手写 12 套。

### 5. HMM Viterbi

- **发射概率**：观测 chroma 与和弦模板的 cosine similarity
- **转移概率**：
  - 同一和弦继续：0.6（倾向于不变化）
  - 五度圈进行（C→F, C→G, Am→Dm...）：0.15
  - 其他常见进行（C→Am, F→G, G→C...）：0.08
  - 极少见进行：0.01
  - **最优的状态空间受调性约束**：只包含当前调性内的常用和弦（I/IIm/IIIm/IV/V/VIm + 属七）

### 6. 后处理

完全复用现有链。

## 改动范围

| 文件 | 改动 |
|------|------|
| `inference.py` | 重写 `ChordOnnxInferenceService` 为 `ChordRecognitionService` |
| `app.py` | 导入、初始化、异常处理调整 |
| 其余 8 个文件 | 不改 |

## 向前兼容

- `transcribe()` 返回的 dict 字段完全不变
- iOS 端不需要任何改动
- `transcribe_batch.py` 测试工具可以直接用
- `run_eval_set.py` 评估工具可以直接用

## 实现步骤

见实施计划文档。

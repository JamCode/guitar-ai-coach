# chord_bench v1

扒歌和弦识别的自动化基准测试（第一版最小可用）。

## 做什么

- 用程序合成一批**可控、可复现**的 wav 样本（48 个）作为测试集。
- 把每个样本喂给 **与当前 iOS 扒歌完全等价的 Python pipeline**：`consonance_ace.onnx` 模型 + `伪 CQT 特征 extractor` + `OnnxChordLabelDecoder` 规则 + `minChordDurationMs=300` 短段过滤 + `TranscriptionEngine.mergeSegments` 合并。
- 输出两份报告：机器可读的 `reports/bench_result.json` 和人类可读的 `reports/bench_report.md`。

## 目录结构

```
benchmarks/chord_bench/
├── generate_samples.py      # 合成 48 个 wav + ground_truth.json
├── pipeline.py              # Python 版扒歌 pipeline（端到端等价移植）
├── evaluate.py              # 跑 pipeline + 指标聚合 + 生成报告
├── samples/                 # 生成的 wav（.gitignore，不入库）
├── samples/ground_truth.json
├── reports/bench_result.json
└── reports/bench_report.md
```

## 用法

```bash
cd /workspace
pip install onnxruntime soundfile numpy   # 一次性

python3 benchmarks/chord_bench/generate_samples.py
python3 benchmarks/chord_bench/evaluate.py
```

第一条会把 48 个 wav 写入 `samples/`，第二条会跑 pipeline 并生成报告。

## 为什么用 Python 而不是 Swift/Xcode

Cursor Cloud Agent VM 里没有 Xcode / Accelerate，跑不了真实的 `TranscriptionCQTFeatureExtractor`（它依赖 `vDSP.FFT`）。Python 侧**逐行**对齐了 Swift 的算法：

| Swift 文件 | Python 对应 | 状态 |
|---|---|---|
| `TranscriptionCQTFeatureExtractor.extractChunk` | `pipeline.extract_chunk` | 用 `numpy.fft.rfft` 复刻；`hanningDenormalized` 用 `numpy.hanning` 近似（峰值都是 1.0；对 argmax 结果不敏感） |
| `TranscriptionCQTFeatureExtractor.makeBinSamplePoints` | `pipeline.make_sample_points` | 完全一致（单 bin 线性插值） |
| `OnnxChordRecognizer.runOnnxModel` | `pipeline.run_onnx` | 一致，包括分 chunk、`frameCount` 截断、chunk 偏移 |
| `OnnxChordRecognizer.resampleForChunking` | `pipeline.resample_to_22050` | 线性插值，一致 |
| `OnnxChordLabelDecoder.decodeLabel` / `classifyChordSuffix` / `matches` / `removeShortFrames` | `pipeline.decode_label` 等 | 规则集 + 命中顺序一致（包括 `dim` vs 补 5 的已知问题） |
| `OnnxChordRecognizer.detectOriginalKey` | `pipeline.detect_original_key` | 一致 |
| `TranscriptionEngine.mergeSegments` | `pipeline.merge_segments` | 一致 |

**不在本版**：`runDSPFallback` 回落路径（本 bench 假设 ONNX 模型可用，所以不会走回落；如果将来要 bench 回落可再加）。

## ground_truth 时间段约定

为了回避 chunk 边界、静音填充、attack/release 瞬态等不确定性，段级答案**不要求从 0 ms 到 N ms 精确对齐**，而是用"每段中间 60%"的时间窗口对齐；只要 pipeline 在这段中间的主标签正确，就算这段对。细节见 `evaluate.py` 的 `score_progression`。

单音/单和弦（无时间线）用"主标签 == 预期"判定，允许 pipeline 输出不止一段，但需要持续时间最长的段落正确。

# 本地历史驱动的 6 模块今日推荐设计

## 1. 背景与目标

本设计用于 Swift 侧“今日推荐”能力：基于用户本地历史训练数据，为 6 个程序化生成模块各生成 1 条当日训练内容，并为每个模块自动判定难度（初级/中级/高级）。

本期明确约束：

- 仅使用本地历史数据，不依赖后端。
- 每个模块固定输出 1 条（总计 6 条）。
- 样本不足时默认初级。
- 不绑定当前 UI 结构，输出统一推荐计划数据，供后续页面重构时按类型渲染。

## 2. In Scope / Out of Scope

### In Scope

- 新增“推荐编排层”，聚合历史评估与生成器调用。
- 为每个模块计算 `masteryScore` 并映射难度。
- 产出统一 `TodayRecommendationPlan` 数据结构。
- 提供失败兜底，保证固定输出 6 条。
- 记录推荐决策日志，支持后续阈值调参。

### Out of Scope

- 不改现有页面导航、入口布局与具体 UI。
- 不引入后端历史同步。
- 不做机器学习模型，仅采用可解释规则评分。

## 3. 程序化生成模块清单（当前已确认）

1. `IntervalQuestionGenerator`（音程识别）
2. `EarChordMcqGenerator`（和弦听辨）
3. `LocalSightSingingRepository`（视唱训练）
4. `ChordSwitchGenerator`（和弦切换）
5. `ScaleTrainingGenerator`（音阶训练）
6. `TraditionalCrawlGenerator`（传统爬格子）

注：`ChordProgressionEngine` 属于解析/映射规则引擎，不作为独立出题生成器统计。

## 4. 总体方案（A：规则分层 + 置信门控）

流程分 2 步：

1. **难度判定**：每个模块独立计算 `masteryScore(0~100)`，映射到初/中/高。
2. **内容生成**：按模块难度调用对应程序化生成器，产出 1 条内容。

每个模块互相独立判定，不做“全局统一档位”强绑定。

## 5. 难度判定规则

### 5.1 冷启动与样本门槛

- 统计窗口：最近 7 天。
- 有效样本 `< 3`：直接判定为 `初级`。

### 5.2 评分项

`masteryScore = accuracyScore + completionScore + stabilityScore + streakScore`

- `accuracyScore`：0~45，正确率/通过率。
- `completionScore`：0~25，完成率。
- `stabilityScore`：0~20，时长与结果波动稳定性。
- `streakScore`：0~10，连续训练天数。

### 5.3 阈值映射

- `< 40` => `初级`
- `40~70` => `中级`
- `> 70` => `高级`

### 5.4 保护规则

- 最近 2 次连续失败或中断：下调 1 档。
- 最近 3 天无训练：当日最高不超过 `中级`。

## 6. 6 模块调用映射

### 6.1 音程识别

- 难度来源：`DifficultyAdvisor.interval`
- 调用：`IntervalQuestionGenerator.next(difficulty: ...)`

### 6.2 和弦听辨

- 难度来源：`DifficultyAdvisor.earChord`
- 调用：`EarChordMcqGenerator.makeQuestion(difficulty: ...)`

### 6.3 视唱训练

- 难度来源：`DifficultyAdvisor.sightSinging`
- 难度参数映射：`difficulty -> pitchRange/includeAccidental/questionCount`
- 调用：`LocalSightSingingRepository.startSession(...)`（取首题作为今日入口内容）

### 6.4 和弦切换

- 难度来源：`DifficultyAdvisor.chordSwitch`
- 调用：`ChordSwitchGenerator.buildExercise(difficulty: ...)`

### 6.5 音阶训练

- 难度来源：`DifficultyAdvisor.scaleTraining`
- 调用：`ScaleTrainingGenerator.buildExercise(difficulty: ...)`

### 6.6 传统爬格子

- 难度来源：`DifficultyAdvisor.traditionalCrawl`
- 调用：`TraditionalCrawlGenerator.buildExercise(difficulty: ...)`

## 7. 输出数据结构

建议新增统一输出：

- `TodayRecommendationPlan`
  - `generatedAt: Date`
  - `items: [RecommendationItem]`（固定 6 条）

- `RecommendationItem`
  - `moduleType`（6 选 1）
  - `difficulty`（初/中/高）
  - `reason`（推荐理由：样本数、正确率、连续天数等）
  - `payload`（各模块具体题目/训练内容）

该结构与 UI 解耦，后续页面可按 `moduleType + payload` 路由到对应逐页渲染流程。

## 8. 异常处理与兜底

- 历史读取失败：该模块按初级生成并记录日志。
- 生成器调用失败：该模块返回初级兜底内容，不影响其余模块。
- 任意单模块异常不应导致整份推荐计划失败。

目标：无论何种异常，当日都稳定输出 6 条推荐内容。

## 9. 可观测性

每个模块记录一次推荐决策日志，至少包含：

- `sampleCount`
- 四项子分（accuracy/completion/stability/streak）
- `masteryScore`
- 最终难度
- 是否触发保护规则（降档、冷启动、久未练封顶）

## 10. 验收标准

### 功能验收

- 固定输出 6 条（每模块 1 条）。
- 每条包含难度与推荐理由。
- 样本不足自动初级。

### 行为验收

- 各模块难度可不同。
- 历史表现提升时，难度可上调。
- 连续失败后，难度会降档保护。

### 稳定性验收

- 单模块失败不影响整体输出。
- 每次都能产出完整推荐计划。

## 11. 版本与后续

本期先落地规则版（方案 A）。后续可演进：

1. 阈值与权重在线可配（本地配置文件）。
2. 加入更细粒度题级反馈后升级到 ELO 式动态评分。
3. 引入后端历史作为补充信号（保持本地优先）。

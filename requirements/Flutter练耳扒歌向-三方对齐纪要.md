# Flutter 练耳（扒歌向）· PM / 架构 / 开发对齐纪要

> 触发：独立 App 主线、优先扒歌；参考竞品「自由练习 / 课程」结构。  
> 角色分工遵循：`.cursor/skills/product-manager-workflow`、`software-architect-workflow`、`developer-delivery-workflow`。

## 产品（PM）结论

- **本期目标**：把「和弦听辨 + 和弦进行」从占位变为 **可做题的 MVP**，直接服务扒歌所需的 **色彩 + 走向**。
- **In Scope**：题库来源 `assets/data/ear_seed_v1.json`（由 `requirements/练耳题库-一期种子.json` 同步）；模式 **A 单和弦性质**、**B 进行辨认**；四选一 + 播放 + 重听 + 即时反馈；练耳 Tab 内 **自由练习式入口列表**。
- **Out of Scope（本期）**：单音辨认、调式课表化、节奏/旋律听写、视唱与麦克风判分、错题本 C、用户账号与云端。
- **验收**：未配置后端亦可完成练耳；任意一题可播放；提交后可见对错与正确答案；10 题会话可走完。

## 架构结论

- **音频**：种子中 `audio_ref` 指向的 `ear_v1_*` 包 **仓库未提供**，本期不阻塞产品——采用 **现有 `guitar_chromatic` 采样** 按 MIDI 合成 **柱式和弦（短琶音起音）** 与 **和弦进行（多和弦串行）**。
- **数据**：题库 **随 App 打包**，离线可用；解析失败时明确错误态。
- **模块**：`ear_seed_*`（模型/加载）、`diatonic_roman`（大调罗马数字 → MIDI）、`ear_chord_player`（播放）、`ear_mcq_session_screen`（会话 UI）。
- **演进**：后续可换 **预渲染 MP3** 或 **服务端下发音频 URL**，题型层尽量不动。

## 开发结论

- 按 `multi-feature-incremental-test.mdc`：**加载 + A 模式 playable → 补单测 → B 模式 → Widget 测 → 文档**。
- 遵守：`new-feature-testing-requirement.mdc`（单元 + 界面层）；本期无新 HTTP 契约，**不做 API 集成测试**。
- 收尾：`dart analyze`、`flutter test`，提交并推送（除非用户要求暂缓）。

## 需产品后续确认

- 合成音色与「真题预录」听感差异是否接受；若否，排期补音频包或采购素材。

## 需开发验证

- 极低音/极高音和弦是否偶发超出 `guitar_chromatic` 覆盖范围（D2–D5）；若触发，需在合成层自动移八度。

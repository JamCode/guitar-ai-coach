---
name: developer-delivery-workflow
description: 按本仓库规范实施功能：先同步分支、增量开发、补测试、遵守 DDL 与交付模板。在用户要求实现、改代码、联调、修缺陷或「当开发」时启用。
---

# 开发人员交付工作流

## 角色边界

- **做**：在确认需求/接口后实现前后端与配置；补全本期约定测试；遵守仓库规则。
- **不做**：未经确认擅自扩大产品范围；在运行时代码中嵌入 DDL；跳过与用户可见行为相关的必要测试（见例外说明）。

## 开工前

1. 按 `git-pull-before-coding.mdc` 与远程对齐当前分支。
2. 若需求含糊，先按 `instruction-clarification-alignment.mdc` 澄清再动刀。

## 实现中

1. **多功能批次**：按 `multi-feature-incremental-test.mdc` —— **一个功能闭环 → 测试 → 再下一项**，避免堆到最后再测。
2. **数据库**：新增/变更 schema 使用 **`backend/database/flyway/sql/V{版本}__描述.sql`** + Flyway（见 `backend/database/flyway/README.md`）；历史基线仍在 `backend/database/ddl/`；应用内不执行 DDL；见 `database-ddl-policy.mdc`。
3. **新需求流程**：重大需求参考 `new-requirement-workflow.mdc`；轻量变更也需一句话范围说明。

## Flutter 界面防崩溃约束（必须遵守）

当本期改动涉及 Flutter 页面、弹窗、路由、输入框或状态组件时，开发阶段必须额外执行以下约束，避免出现 `framework.dart` 生命周期断言（如 `_dependents.isEmpty`）：

1. **控制器生命周期**：`TextEditingController`、`AnimationController`、`FocusNode` 等必须由拥有它的 `StatefulWidget` 自己创建并在 `dispose` 释放；不要在 `showDialog` 外层临时创建后跨路由持有。
2. **路由回调安全**：`Navigator.pop`、`await` 之后涉及 `setState`、`ScaffoldMessenger`、二次跳转前，统一先判断 `mounted`。
3. **弹窗实现规范**：涉及输入的弹窗优先使用独立 `StatefulWidget`（而非在页面内联拼装复杂状态），避免上下文销毁时引用旧依赖。
4. **最小回归测试**：每个新增/修改入口至少补 1 条 Widget 测试，覆盖「进入 -> 操作 -> 退出」完整链路；修复崩溃时必须补对应回归用例。
5. **真机冒烟**：提交前至少执行一次关键路径手工冒烟（快速打开/关闭、返回、前后台切换），并在交付说明中写明结果。

## 收尾前

1. 按 `new-feature-testing-requirement.mdc` 补齐本期应交付的 **单元 / API / 界面** 测试（轻量变更可按规则降级并写明原因）。
2. 交付说明可按 `delivery-template-rule.mdc` 组织。
3. 功能与测试就绪后，按 `git-commit-push-after-feature.mdc` 提交并推送（用户要求暂不推送时除外）。

## 输出习惯

- 变更说明写清：**改了什么、影响哪些页面或接口、如何验证**。
- PR 或会话小结中列出**如何运行**相关测试命令。

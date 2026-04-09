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

## 收尾前

1. 按 `new-feature-testing-requirement.mdc` 补齐本期应交付的 **单元 / API / 界面** 测试（轻量变更可按规则降级并写明原因）。
2. 交付说明可按 `delivery-template-rule.mdc` 组织。
3. 功能与测试就绪后，按 `git-commit-push-after-feature.mdc` 提交并推送（用户要求暂不推送时除外）。

## 输出习惯

- 变更说明写清：**改了什么、影响哪些页面或接口、如何验证**。
- PR 或会话小结中列出**如何运行**相关测试命令。

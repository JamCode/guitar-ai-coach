# Flyway 数据库迁移（MySQL）

用于**版本化、可审计、防重复执行**的 schema 变更。执行记录写在目标库表 **`flyway_schema_history`**（由 Flyway 自动创建）。

## 与 `database/ddl/` 的关系

| 目录 | 用途 |
|------|------|
| `../ddl/*.sql` | **历史基线**：已有环境多半已手工执行过；**新环境**可按 `../ddl/README.md` 顺序跑一遍后做 **baseline**（见下）。**不要再把本期新增 schema 只写在这里**，避免与 Flyway 双轨、漏跑/重跑分不清。 |
| `sql/V{版本号}__描述.sql` | **本期起新增/变更**的 DDL：唯一权威脚本；由 Flyway 在部署时按版本号**顺序执行**，并已执行过的版本**不会重复跑**（校验和变更的 repeatable 除外）。 |

命名规则：`V` + **整数版本** + `__` + 蛇形英文描述 + `.sql`。  
示例：`V2__add_practice_streak_table.sql`、`V3__add_index_on_learner_id.sql`。

- 版本号**全局递增**，勿与分支名混用；合并到主线后仍按数字顺序。
- **禁止**修改已合并且已在任何环境执行过的迁移文件内容（checksum 会变导致 Flyway 失败）；修正请**新建**更高版本号的迁移（如再执行一条 `ALTER`）。

## 安装 Flyway CLI

- macOS：`brew install flyway`（或从 [Redgate Flyway](https://www.red-gate.com/products/flyway/community/) 下载）。
- 需能使用 **JDBC** 连接 MySQL（Flyway 自带 MySQL 驱动）。

## 环境变量（推荐）

```bash
export FLYWAY_URL="jdbc:mysql://<主机>:<端口>/<库名>?useSSL=true&characterEncoding=utf8"
export FLYWAY_USER="<用户>"
export FLYWAY_PASSWORD="<密码>"
```

在 **`backend/database/flyway`** 下执行子命令（使 `flyway.conf` 与 `sql/` 相对路径生效）。

## 已有数据库（曾执行过 `../ddl/` 里的脚本）

只对**尚未**由 Flyway 管理过的库做一次 **baseline**，标记「历史已应用」，之后只跑 `sql/` 里新版本：

```bash
cd backend/database/flyway
flyway baseline -baselineVersion=1 -baselineDescription="Pre-Flyway legacy ddl in database/ddl"
```

含义：Flyway 认为版本 **1 及以前**已应用，**不会**再执行 `V1__*.sql`（若你未放置 `V1` 文件，仅写入历史表）。  
之后新增文件从 **`V2__...sql`** 开始。

若你希望 baseline 对齐其他数字（例如团队约定从 `100` 起）：把 `-baselineVersion=` 改成约定值，后续迁移从 `101` 起。

## 空库 / 全新实例

1. 按 **`../ddl/README.md`** 顺序执行历史脚本（建表与授权）。
2. 再执行上一节的 **`flyway baseline -baselineVersion=1`**。
3. 后续变更只加 **`sql/V2__...`** 及更高版本，用 **`flyway migrate`** 执行。

（若将来把历史整包做成单文件 `V1__baseline.sql` 再讨论；当前保持 ddl 为基线来源，避免重复维护两份大脚本。）

## 日常命令

```bash
cd backend/database/flyway
flyway info      # 查看已应用与待应用版本
flyway validate  # 校验命名与校验和
flyway migrate   # 执行未应用迁移
```

生产环境建议：**先 `info`/`validate`，再 `migrate`**；由 CI/CD 或运维在发版窗口执行，**不要**在应用 API 请求里执行。

## 防漏跑、防重复跑的原理

- **漏跑**：发版时执行 `flyway migrate`，未在 `flyway_schema_history` 登记的版本会按序执行；部署流水线固定调用即可。
- **重复跑**：已成功执行的版本有记录，**同一文件不会再次执行**；若误改已执行文件，Flyway 会报错，避免静默漂移。

## 与 Git 分支

- 迁移文件随代码合并；**版本号在主线全局递增**，避免两个分支各建 `V2__` 造成冲突。
- 分支上的设计说明仍可写在 `docs/<分支>/database-notes.md`，但**可执行 DDL** 只放在本目录 `sql/`。

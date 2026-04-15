# 历史 DDL 脚本（基线）

本目录为 **Flyway 引入前**的建表与授权脚本，仍用于：

- **新环境首次建库**：按下列顺序手工执行（或通过运维管道执行）后，再在 `../flyway/` 对目标库执行 **`flyway baseline`**（见 `../flyway/README.md`）。
- **查阅历史结构**：与线上已存在库对齐时对照用。

## 建议执行顺序（MySQL）

表创建在前，对应 `grant_*.sql` 紧跟其后（授权依赖表已存在）。

1. `demo_items.sql`
2. `ear_training_tables.sql`
3. `grant_ear_training_tables_guitar_app.sql`
4. `quiz_training_tables.sql`
5. `grant_quiz_training_tables_guitar_app.sql`
6. `song_chords_tables.sql`
7. `grant_song_chords_tables_guitar_app.sql`
8. `chord_explain_cache.sql`
9. `grant_chord_explain_cache_guitar_app.sql`

执行示例：

```bash
mysql -u<user> -p<pass> <db_name> < demo_items.sql
# …其余依序执行
```

**本期起新增的 schema 变更**：请写入 **`../flyway/sql/V{版本}__描述.sql`**，并用 Flyway `migrate` 应用，**不要**仅在本目录追加文件（见 `../flyway/README.md` 与仓库 `database-ddl-policy.mdc`）。

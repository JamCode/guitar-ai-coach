-- 和弦指法 / 乐理解释缓存（大模型结果），按 symbol + 调号 + 难度 去重。
-- 部署时先在目标库执行本文件后再启用后端 MySQL 缓存，例如：
--   mysql -u... -p... guitar_ai_coach < chord_explain_cache.sql
-- 表权限授予应用用户：grant_chord_explain_cache_guitar_app.sql

CREATE TABLE IF NOT EXISTS chord_explain_cache (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  symbol VARCHAR(64) NOT NULL COMMENT '和弦符号，与 API 请求一致（已校验）',
  music_key VARCHAR(32) NOT NULL COMMENT '规范化调号，如 C、F#',
  level VARCHAR(32) NOT NULL COMMENT '难度档：初级/中级/高级',
  explain_json JSON NOT NULL COMMENT 'validate 后的 explain 对象（frets、notes_letters 等）',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_symbol_key_level (symbol, music_key, level)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

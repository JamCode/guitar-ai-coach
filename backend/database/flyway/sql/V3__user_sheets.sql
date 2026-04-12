-- 用户曲谱（云端）：元数据在库，页文件在同机磁盘（路径由应用层按 SHEETS_STORAGE_ROOT 解析）。
CREATE TABLE IF NOT EXISTS user_sheets (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL COMMENT 'apple_users.id',
  public_id CHAR(36) NOT NULL COMMENT '对外 UUID，用于 URL',
  display_name VARCHAR(255) NOT NULL,
  page_count INT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_user_sheets_public_id (public_id),
  KEY idx_user_sheets_user_updated (user_id, updated_at),
  CONSTRAINT fk_user_sheets_user FOREIGN KEY (user_id) REFERENCES apple_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS user_sheet_pages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sheet_id BIGINT UNSIGNED NOT NULL,
  page_index INT UNSIGNED NOT NULL COMMENT '从 0 起',
  storage_relpath VARCHAR(512) NOT NULL COMMENT '相对 SHEETS_STORAGE_ROOT 的路径',
  mime_type VARCHAR(64) NOT NULL,
  byte_size BIGINT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_sheet_page (sheet_id, page_index),
  KEY idx_user_sheet_pages_sheet (sheet_id),
  CONSTRAINT fk_user_sheet_pages_sheet FOREIGN KEY (sheet_id) REFERENCES user_sheets (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

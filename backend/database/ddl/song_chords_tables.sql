-- 找歌和弦（MVP）表结构
-- 执行方式：
--   mysql -u<user> -p <db_name> < song_chords_tables.sql

CREATE TABLE IF NOT EXISTS song (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  title VARCHAR(255) NOT NULL COMMENT '歌名',
  artist VARCHAR(255) NOT NULL DEFAULT '' COMMENT '歌手',
  title_norm VARCHAR(255) NOT NULL COMMENT '歌名归一化检索键',
  artist_norm VARCHAR(255) NOT NULL DEFAULT '' COMMENT '歌手归一化检索键',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_song_title_artist_norm (title_norm, artist_norm)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS song_search_alias (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  song_id BIGINT UNSIGNED NOT NULL,
  alias_text VARCHAR(255) NOT NULL COMMENT '用户搜索词或别名',
  alias_norm VARCHAR(255) NOT NULL COMMENT '别名归一化检索键',
  is_primary TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否主别名',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_song_alias_norm (alias_norm),
  KEY idx_song_alias_song (song_id),
  CONSTRAINT fk_song_alias_song
    FOREIGN KEY (song_id) REFERENCES song(id)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS song_score (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  song_id BIGINT UNSIGNED NOT NULL,
  difficulty_level VARCHAR(16) NOT NULL COMMENT 'beginner/intermediate/advanced',
  version_no VARCHAR(8) NOT NULL COMMENT 'v1/v2',
  is_current TINYINT(1) NOT NULL DEFAULT 0 COMMENT '当前版本标记',
  title_display VARCHAR(255) NOT NULL COMMENT '结果卡片标题',
  key_original VARCHAR(16) NOT NULL COMMENT '原调',
  key_recommended VARCHAR(16) NOT NULL COMMENT '推荐调（存储基准调）',
  source_type VARCHAR(16) NOT NULL COMMENT 'library/ai/hybrid',
  why_recommended VARCHAR(512) NOT NULL DEFAULT '' COMMENT '推荐理由',
  quality_score INT NOT NULL DEFAULT 0 COMMENT '质量评分 0-100',
  last_verified_at TIMESTAMP NULL DEFAULT NULL COMMENT '最近 AI 核对时间',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_song_score_version (song_id, difficulty_level, version_no),
  KEY idx_song_score_current (song_id, difficulty_level, is_current),
  CONSTRAINT fk_song_score_song
    FOREIGN KEY (song_id) REFERENCES song(id)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS song_score_content (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  song_score_id BIGINT UNSIGNED NOT NULL,
  verse_progression_json JSON NOT NULL COMMENT '主歌和弦数组',
  chorus_progression_json JSON NOT NULL COMMENT '副歌和弦数组',
  full_chart_lines_json JSON NOT NULL COMMENT '完整谱逐行文本',
  chart_json JSON NOT NULL COMMENT '结构化谱面（sections/lyrics/chord_events(pos)）',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_song_score_content_score (song_score_id),
  CONSTRAINT fk_song_score_content_score
    FOREIGN KEY (song_score_id) REFERENCES song_score(id)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

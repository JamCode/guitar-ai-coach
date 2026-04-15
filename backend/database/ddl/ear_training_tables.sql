-- 练耳训练（A/B/C）表结构
-- 执行方式：
--   mysql -u<user> -p <db_name> < ear_training_tables.sql

CREATE TABLE IF NOT EXISTS ear_question (
  id VARCHAR(32) NOT NULL COMMENT '题目ID',
  mode CHAR(1) NOT NULL COMMENT 'A/B（C复用A/B题池）',
  question_type VARCHAR(64) NOT NULL COMMENT '题型标识',
  difficulty VARCHAR(16) NOT NULL COMMENT 'A1/B1/B2/B3',
  music_key VARCHAR(8) NULL COMMENT '题目调号',
  root VARCHAR(8) NULL COMMENT '根音',
  chord_symbol VARCHAR(24) NULL COMMENT '和弦符号',
  target_quality VARCHAR(24) NULL COMMENT '目标性质',
  progression_id VARCHAR(24) NULL COMMENT '进行ID',
  progression_roman VARCHAR(32) NULL COMMENT '进行罗马级数',
  variant_id VARCHAR(24) NULL COMMENT '变体ID',
  prompt_zh VARCHAR(255) NOT NULL COMMENT '题干',
  hint_zh VARCHAR(255) NULL COMMENT '提示',
  audio_json JSON NOT NULL COMMENT '音频元数据',
  correct_option_key CHAR(1) NOT NULL COMMENT 'A/B/C/D',
  options_json JSON NOT NULL COMMENT '4选项 key/label/is_correct',
  tags_json JSON NOT NULL COMMENT '标签数组',
  status VARCHAR(16) NOT NULL DEFAULT 'active' COMMENT 'draft/active/offline',
  version VARCHAR(32) NOT NULL DEFAULT 'ear_seed_v1',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ear_q_mode_status (mode, status),
  KEY idx_ear_q_diff_status (difficulty, status),
  KEY idx_ear_q_version (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ear_daily_set (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '每日题单ID',
  learner_id VARCHAR(64) NOT NULL COMMENT '匿名学习者ID',
  day_date DATE NOT NULL COMMENT '自然日',
  question_ids_json JSON NOT NULL COMMENT '当日题目ID列表',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_ear_daily_learner_date (learner_id, day_date),
  KEY idx_ear_daily_date (day_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ear_attempt (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '训练会话ID',
  learner_id VARCHAR(64) NOT NULL COMMENT '匿名学习者ID',
  mode CHAR(1) NOT NULL COMMENT 'A/B/C',
  daily_set_id BIGINT UNSIGNED NULL COMMENT 'C模式关联每日题单',
  started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ended_at TIMESTAMP NULL DEFAULT NULL,
  total_answered INT NOT NULL DEFAULT 0,
  total_correct INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ear_attempt_learner_started (learner_id, started_at),
  KEY idx_ear_attempt_mode_started (mode, started_at),
  CONSTRAINT fk_ear_attempt_daily_set
    FOREIGN KEY (daily_set_id) REFERENCES ear_daily_set(id)
    ON DELETE SET NULL ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ear_attempt_item (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '作答明细ID',
  attempt_id BIGINT UNSIGNED NOT NULL,
  question_id VARCHAR(32) NOT NULL,
  selected_option_key CHAR(1) NOT NULL,
  is_correct TINYINT(1) NOT NULL DEFAULT 0,
  answered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ear_ai_attempt_time (attempt_id, answered_at),
  KEY idx_ear_ai_question (question_id),
  CONSTRAINT fk_ear_ai_attempt
    FOREIGN KEY (attempt_id) REFERENCES ear_attempt(id)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT fk_ear_ai_question
    FOREIGN KEY (question_id) REFERENCES ear_question(id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ear_mistake_book (
  learner_id VARCHAR(64) NOT NULL,
  question_id VARCHAR(32) NOT NULL,
  wrong_count INT NOT NULL DEFAULT 0,
  right_streak INT NOT NULL DEFAULT 0,
  status VARCHAR(16) NOT NULL DEFAULT 'new' COMMENT 'new/reviewing/mastered',
  last_wrong_at TIMESTAMP NULL DEFAULT NULL,
  last_right_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (learner_id, question_id),
  KEY idx_ear_mistake_status_updated (status, updated_at),
  KEY idx_ear_mistake_wrong_updated (wrong_count, updated_at),
  CONSTRAINT fk_ear_mistake_question
    FOREIGN KEY (question_id) REFERENCES ear_question(id)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


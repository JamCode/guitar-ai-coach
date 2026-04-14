-- 视唱训练（单音/多音）会话与作答明细

CREATE TABLE IF NOT EXISTS ear_sight_attempt (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '视唱会话ID',
  learner_id VARCHAR(64) NOT NULL COMMENT '匿名学习者ID',
  mode VARCHAR(16) NOT NULL DEFAULT 'single_note' COMMENT 'single_note/multi_note',
  include_accidental TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否包含升降号',
  min_note VARCHAR(8) NOT NULL COMMENT '最小音高（如 C3）',
  max_note VARCHAR(8) NOT NULL COMMENT '最大音高（如 B4）',
  question_count INT NOT NULL DEFAULT 10,
  answered_count INT NOT NULL DEFAULT 0,
  correct_count INT NOT NULL DEFAULT 0,
  total_score DECIMAL(6,2) NOT NULL DEFAULT 0 COMMENT '累计分数',
  started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ended_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ear_sight_attempt_learner_started (learner_id, started_at),
  KEY idx_ear_sight_attempt_mode_started (mode, started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ear_sight_attempt_item (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '视唱单题作答ID',
  attempt_id BIGINT UNSIGNED NOT NULL,
  question_id VARCHAR(32) NOT NULL,
  target_notes_json JSON NOT NULL COMMENT '目标音（顺序敏感）',
  user_notes_json JSON NOT NULL COMMENT '用户音（顺序敏感）',
  avg_cents_abs DECIMAL(7,3) NOT NULL DEFAULT 0 COMMENT '平均绝对偏差',
  stable_hit_ms INT NOT NULL DEFAULT 0 COMMENT '连续命中时长（毫秒）',
  duration_ms INT NOT NULL DEFAULT 0 COMMENT '评估窗口时长（毫秒）',
  score DECIMAL(5,2) NOT NULL DEFAULT 0 COMMENT '单题得分（0-10）',
  is_correct TINYINT(1) NOT NULL DEFAULT 0,
  answered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ear_sight_item_attempt_time (attempt_id, answered_at),
  KEY idx_ear_sight_item_question (question_id),
  CONSTRAINT fk_ear_sight_item_attempt
    FOREIGN KEY (attempt_id) REFERENCES ear_sight_attempt(id)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

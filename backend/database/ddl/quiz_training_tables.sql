-- Quiz 训练题库（方案 B：匿名 learner_id）
-- 执行方式：
--   mysql -u<user> -p <db_name> < quiz_training_tables.sql

CREATE TABLE IF NOT EXISTS quiz_question (
  id VARCHAR(32) NOT NULL COMMENT '题目ID',
  difficulty VARCHAR(16) NOT NULL COMMENT 'beginner/intermediate/advanced',
  chord_symbol VARCHAR(32) NOT NULL COMMENT '和弦符号',
  chord_quality VARCHAR(32) NOT NULL COMMENT '和弦性质',
  correct_option_key CHAR(1) NOT NULL COMMENT 'A/B/C/D',
  options_json JSON NOT NULL COMMENT '4个选项，含 key/fingering/is_correct',
  status VARCHAR(16) NOT NULL DEFAULT 'active' COMMENT 'draft/active/offline',
  version VARCHAR(32) NOT NULL DEFAULT 'quiz_seed_100_v2',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_q_difficulty_status (difficulty, status),
  KEY idx_q_symbol (chord_symbol),
  KEY idx_q_version (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS quiz_attempt (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '训练会话ID',
  learner_id VARCHAR(64) NOT NULL COMMENT '匿名学习者ID',
  difficulty VARCHAR(16) NOT NULL COMMENT '本次难度',
  wrong_only TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否仅错题模式',
  started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ended_at TIMESTAMP NULL DEFAULT NULL,
  total_answered INT NOT NULL DEFAULT 0,
  total_correct INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_attempt_learner_started (learner_id, started_at),
  KEY idx_attempt_diff_started (difficulty, started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS quiz_attempt_answer (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '作答明细ID',
  attempt_id BIGINT UNSIGNED NOT NULL,
  question_id VARCHAR(32) NOT NULL,
  selected_option_key CHAR(1) NOT NULL,
  is_correct TINYINT(1) NOT NULL DEFAULT 0,
  answered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ans_attempt_time (attempt_id, answered_at),
  KEY idx_ans_qid (question_id),
  CONSTRAINT fk_quiz_answer_attempt
    FOREIGN KEY (attempt_id) REFERENCES quiz_attempt(id)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

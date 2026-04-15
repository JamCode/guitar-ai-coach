-- 和弦题库训练 MySQL 建表草案（方案 B：匿名 learner_id）
-- 目标：
-- 1) 支持题库初始化入库
-- 2) 支持匿名训练会话与作答记录
-- 3) 支持后续账号体系迁移（保留 learner_id）

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- =========================================================
-- 1) 题目主表
-- =========================================================
CREATE TABLE IF NOT EXISTS quiz_question (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '题目ID',
  difficulty VARCHAR(16) NOT NULL COMMENT 'beginner/intermediate/advanced',
  chord_symbol VARCHAR(32) NOT NULL COMMENT '和弦符号，如 Am7',
  chord_quality VARCHAR(32) NOT NULL COMMENT '和弦性质，如 m7',
  correct_fingering VARCHAR(32) NOT NULL COMMENT '标准按法编码',
  status VARCHAR(16) NOT NULL DEFAULT 'draft' COMMENT 'draft/active/offline',
  version VARCHAR(32) NOT NULL COMMENT '题库版本，如 v1_2026_03',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_question_difficulty_status (difficulty, status),
  KEY idx_question_version (version),
  KEY idx_question_symbol (chord_symbol),
  KEY idx_question_quality (chord_quality)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='和弦题目主表';

-- =========================================================
-- 2) 题目选项表（A/B/C/D）
-- =========================================================
CREATE TABLE IF NOT EXISTS quiz_question_option (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '选项ID',
  question_id BIGINT UNSIGNED NOT NULL COMMENT '关联 quiz_question.id',
  option_key CHAR(1) NOT NULL COMMENT 'A/B/C/D',
  fingering VARCHAR(32) NOT NULL COMMENT '候选按法编码',
  is_correct TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否正确答案',
  display_order INT NOT NULL DEFAULT 0 COMMENT '展示顺序',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_question_option_key (question_id, option_key),
  KEY idx_option_question (question_id),
  KEY idx_option_correct (is_correct),
  CONSTRAINT fk_option_question
    FOREIGN KEY (question_id) REFERENCES quiz_question(id)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='题目选项表';

-- =========================================================
-- 3) 训练会话表（匿名 learner 维度）
-- =========================================================
CREATE TABLE IF NOT EXISTS quiz_attempt (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '会话ID',
  learner_id VARCHAR(64) NOT NULL COMMENT '匿名学习者ID（前端本地生成UUID）',
  difficulty VARCHAR(16) NOT NULL COMMENT '本次训练难度',
  started_at DATETIME NOT NULL COMMENT '会话开始时间',
  ended_at DATETIME NULL COMMENT '会话结束时间',
  total_answered INT NOT NULL DEFAULT 0 COMMENT '本次作答题数',
  total_correct INT NOT NULL DEFAULT 0 COMMENT '本次答对题数',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_attempt_learner_started (learner_id, started_at),
  KEY idx_attempt_difficulty_started (difficulty, started_at),
  KEY idx_attempt_ended_at (ended_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='训练会话表';

-- =========================================================
-- 4) 作答明细表
-- =========================================================
CREATE TABLE IF NOT EXISTS quiz_attempt_answer (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '明细ID',
  attempt_id BIGINT UNSIGNED NOT NULL COMMENT '关联 quiz_attempt.id',
  question_id BIGINT UNSIGNED NOT NULL COMMENT '关联 quiz_question.id',
  selected_option_key CHAR(1) NOT NULL COMMENT '用户选择 A/B/C/D',
  is_correct TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否答对',
  answered_at DATETIME NOT NULL COMMENT '作答时间',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_answer_attempt (attempt_id),
  KEY idx_answer_question (question_id),
  KEY idx_answer_correct (is_correct),
  CONSTRAINT fk_answer_attempt
    FOREIGN KEY (attempt_id) REFERENCES quiz_attempt(id)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT fk_answer_question
    FOREIGN KEY (question_id) REFERENCES quiz_question(id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='作答明细表';

-- =========================================================
-- 5) 预留：匿名身份与账号映射（后续登录体系）
-- =========================================================
CREATE TABLE IF NOT EXISTS learner_identity_map (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '映射ID',
  learner_id VARCHAR(64) NOT NULL COMMENT '匿名学习者ID',
  user_id BIGINT UNSIGNED NOT NULL COMMENT '正式用户ID（未来账号体系）',
  linked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '绑定时间',
  PRIMARY KEY (id),
  UNIQUE KEY uniq_learner_id (learner_id),
  KEY idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='匿名身份与账号映射表（预留）';

SET FOREIGN_KEY_CHECKS = 1;

-- =========================================================
-- 初始化入库建议（执行顺序）
-- 1) 导入 quiz_question
-- 2) 导入 quiz_question_option
-- 3) 将可上线题目标记为 status=active
-- =========================================================


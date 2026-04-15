-- 用户练习会话：与 App 端 PracticeSession 字段对齐，按用户隔离。
CREATE TABLE IF NOT EXISTS user_practice_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL COMMENT 'apple_users.id',
  client_session_id CHAR(36) NOT NULL COMMENT '客户端生成的 UUID，幂等上报',
  task_id VARCHAR(64) NOT NULL,
  task_name VARCHAR(255) NOT NULL,
  started_at DATETIME(3) NOT NULL,
  ended_at DATETIME(3) NOT NULL,
  duration_seconds INT UNSIGNED NOT NULL,
  completed TINYINT(1) NOT NULL DEFAULT 0,
  difficulty TINYINT UNSIGNED NOT NULL DEFAULT 3,
  note TEXT NULL,
  progression_id VARCHAR(128) NULL,
  music_key VARCHAR(32) NULL,
  complexity VARCHAR(64) NULL,
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_user_practice_client (user_id, client_session_id),
  KEY idx_user_practice_ended (user_id, ended_at DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='练琴 Tab 单次练习记录';

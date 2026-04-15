-- Apple Sign In：按 apple_sub（JWT sub）唯一标识用户，供 /auth/apple upsert 使用。
CREATE TABLE IF NOT EXISTS apple_users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  apple_sub VARCHAR(255) NOT NULL COMMENT 'Apple ID Token 中的 sub，稳定唯一',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  last_login_at TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_apple_sub (apple_sub)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

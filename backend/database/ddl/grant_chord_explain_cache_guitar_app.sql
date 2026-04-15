-- 将和弦缓存表的权限授予应用账号（在 MySQL 中以管理员执行，例如 root）
-- 若已对 guitar_ai_coach.* 授予 ALL，本脚本为冗余但可明确最小权限意图。
-- 用法示例：mysql -uroot -p < grant_chord_explain_cache_guitar_app.sql

GRANT SELECT, INSERT, UPDATE, DELETE
  ON guitar_ai_coach.chord_explain_cache
  TO 'guitar_app'@'localhost';

FLUSH PRIVILEGES;

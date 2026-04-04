-- 为应用账号授予练耳训练表权限
-- 执行前请确认数据库名与账号主机名

GRANT SELECT, INSERT, UPDATE, DELETE
ON guitar_ai_coach.ear_question
TO 'guitar_app'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE
ON guitar_ai_coach.ear_daily_set
TO 'guitar_app'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE
ON guitar_ai_coach.ear_attempt
TO 'guitar_app'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE
ON guitar_ai_coach.ear_attempt_item
TO 'guitar_app'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE
ON guitar_ai_coach.ear_mistake_book
TO 'guitar_app'@'localhost';

FLUSH PRIVILEGES;


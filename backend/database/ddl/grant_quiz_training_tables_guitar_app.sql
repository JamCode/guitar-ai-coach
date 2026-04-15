-- 将 Quiz 训练表权限授予应用账号（以管理员执行）

GRANT SELECT, INSERT, UPDATE, DELETE
  ON guitar_ai_coach.quiz_question
  TO 'guitar_app'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE
  ON guitar_ai_coach.quiz_attempt
  TO 'guitar_app'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE
  ON guitar_ai_coach.quiz_attempt_answer
  TO 'guitar_app'@'localhost';

FLUSH PRIVILEGES;

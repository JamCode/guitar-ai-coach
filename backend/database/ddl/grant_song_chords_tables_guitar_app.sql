-- 将找歌和弦表权限授予应用账号（以管理员执行）

GRANT SELECT, INSERT, UPDATE, DELETE
  ON guitar_ai_coach.song
  TO 'guitar_app'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE
  ON guitar_ai_coach.song_search_alias
  TO 'guitar_app'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE
  ON guitar_ai_coach.song_score
  TO 'guitar_app'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE
  ON guitar_ai_coach.song_score_content
  TO 'guitar_app'@'localhost';

FLUSH PRIVILEGES;

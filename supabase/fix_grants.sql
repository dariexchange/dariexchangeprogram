-- 사이트(로그인한 사용자)가 표와 함수에 접근할 수 있도록 권한 부여
-- 실제로 누가 어떤 행을 보고 바꿀 수 있는지는 행 수준 보안(RLS) 규칙이 그대로 제한합니다.
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to anon, authenticated;
-- 참가자가 직접 고칠 수 있는 열은 프로필 항목뿐
revoke update on participants from authenticated;
grant update (goal, interests, intro, en_level, ar_level, ko_level, kakao_id) on participants to authenticated;

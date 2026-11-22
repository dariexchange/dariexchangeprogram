-- =====================================================================
-- DARI 초기 설정 — schema.sql 실행 후, 값을 바꿔서 실행하세요.
-- =====================================================================

-- 1) 현재 운영 기수 (회차별 날짜·시간과 Zoom 링크는 사이트의 운영 관리 > 일정 · Zoom 에서 입력)
insert into settings (cohort, active) values (6, true)
on conflict (cohort) do update set active = true;

-- 2) 운영진 계정 등록
--    먼저 각 운영진이 사이트에서 "로그인 링크 받기"를 한 번 누르거나,
--    Supabase 대시보드 > Authentication > Users > Add user 로 계정을 만든 뒤 실행하세요.
--    mlang: 'ko' = 한국 운영진, 'ar' = HAN.AL (권한은 같고, 화면 표시용 구분입니다)
insert into profiles (id, name, role, mlang, lang)
select id, 'DARI 한국 운영진', 'admin', 'ko', 'ko' from auth.users where email = 'korea-admin@example.com'
on conflict (id) do update set role = 'admin', mlang = 'ko';

insert into profiles (id, name, role, mlang, lang)
select id, 'HAN.AL 운영진', 'admin', 'ar', 'ar' from auth.users where email = 'hanal-admin@example.com'
on conflict (id) do update set role = 'admin', mlang = 'ar';

-- 운영진이 더 있으면 위 블록을 복사해 이메일·이름·담당 언어만 바꿔 실행하세요.

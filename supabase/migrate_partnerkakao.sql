-- =====================================================================
-- DARI 업데이트: 매칭된 파트너끼리 카카오톡 ID 공개 (보강 일정 연락용)
-- 매칭된 내 파트너의 카카오톡 ID만 보이고, 다른 참가자의 정보·이메일은 여전히 보이지 않습니다.
-- SQL Editor에 붙여 넣고 한 번 실행하세요. 여러 번 실행해도 안전합니다.
-- =====================================================================
drop function if exists my_partner();
create function my_partner()
returns table (id uuid, name text, side text, univ text, cohort int, goal text, interests text[], intro text,
               en_level int, ar_level int, ko_level int, kakao_id text)
language sql stable security definer set search_path=public as $$
  select p.id, p.name, p.side, p.univ, p.cohort, p.goal, p.interests, p.intro, p.en_level, p.ar_level, p.ko_level, p.kakao_id
    from pairs pr join participants p
      on p.id = case when pr.kr_id = my_pid() then pr.dz_id else pr.kr_id end
   where my_pid() in (pr.kr_id, pr.dz_id)
$$;
revoke all on function my_partner() from public, anon;
grant execute on function my_partner() to authenticated;

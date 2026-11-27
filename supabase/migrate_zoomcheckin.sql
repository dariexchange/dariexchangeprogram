-- =====================================================================
-- DARI 업데이트: Zoom 입장 버튼으로 자동 출석
-- 참가자가 사이트의 'Zoom 입장' 버튼을 수업 시작 15분 전 ~ 15분 후 사이에 누르면
-- 해당 회차가 출석(P)으로 기록됩니다. 시간 판단은 서버(한국 시간) 기준입니다.
-- 이미 기록된 출석(운영진이 입력한 값 포함)은 바꾸지 않습니다.
-- SQL Editor에 붙여 넣고 한 번 실행하세요. 여러 번 실행해도 안전합니다.
-- =====================================================================
create or replace function zoom_checkin() returns int
language plpgsql security definer set search_path = public as $$
declare v_me uuid := my_pid(); v_c int := my_cohort(); v_no int; v_now timestamp := kst_now(); v_n int;
begin
  if v_me is null then return null; end if;
  select no into v_no from rounds
   where cohort = v_c
     and v_now between (date + time) - interval '15 minutes' and (date + time) + interval '15 minutes'
   order by no limit 1;
  if v_no is null then return null; end if;
  insert into attendance (participant_id, round, s, n)
  values (v_me, v_no, 'P', 'Zoom ✓ ' || to_char(v_now, 'HH24:MI'))
  on conflict (participant_id, round) do nothing;
  get diagnostics v_n = row_count;
  return case when v_n > 0 then v_no else -v_no end;
end $$;
revoke all on function zoom_checkin() from public, anon;
grant execute on function zoom_checkin() to authenticated;

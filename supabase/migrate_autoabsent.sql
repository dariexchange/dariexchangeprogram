-- =====================================================================
-- DARI 업데이트: 보강 인증 사진 규칙 변경
--  · 보강 시작 전에도 인증 사진 제출 가능 (보강 당일 23:59까지)
--  · 보강 당일 23:59까지 사진을 내지 않으면(또는 반려 후 다시 내지 않으면) 자동 결석
-- SQL Editor에 붙여 넣고 한 번 실행하세요. 여러 번 실행해도 안전합니다.
-- =====================================================================
create or replace function submit_makeup_photo(p_id uuid, p_path text, p_name text) returns void
language plpgsql security definer set search_path=public as $$
declare m makeups;
begin
  select * into m from makeups where id = p_id;
  if m.id is null or m.pair_id is distinct from my_pair() then raise exception 'not_allowed'; end if;
  if m.status not in ('scheduled','rejected') then raise exception 'not_submittable'; end if;
  if kst_now() > m.date + time '23:59:59' then raise exception 'deadline_passed'; end if;
  if split_part(p_path, '/', 1) <> m.pair_id::text then raise exception 'bad_path'; end if;
  update makeups set photo_path = p_path, photo_name = p_name, status = 'submitted', submitted_at = kst_now() where id = p_id;
end $$;

-- 기한(보강 당일 23:59)이 지난 미제출 보강 → 결석. 두 참가자 모두 해당 회차를 결석으로.
create or replace function expire_makeups() returns int
language plpgsql security definer set search_path=public as $$
declare r record; v_n int := 0;
begin
  for r in
    update makeups set status = 'absent'
     where status in ('scheduled','rejected') and kst_now() > date + time '23:59:59'
    returning pair_id, round
  loop
    insert into attendance (participant_id, round, s, n)
    select x, r.round, 'A', '보강 미인증 (자동)' from pairs pr, unnest(array[pr.kr_id, pr.dz_id]) x where pr.id = r.pair_id
    on conflict (participant_id, round) do update set s = 'A', n = excluded.n where attendance.s = 'M';
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
revoke all on function expire_makeups() from public, anon;
grant execute on function expire_makeups() to authenticated;

-- (선택) 아무도 접속하지 않아도 15분마다 자동 처리 — pg_cron을 쓸 수 있으면 등록, 없으면 건너뜀
-- 사이트는 접속할 때마다 이 처리를 먼저 하므로 pg_cron이 없어도 화면에는 항상 반영됩니다.
do $$ begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'dari-expire-makeups';
  perform cron.schedule('dari-expire-makeups', '*/15 * * * *', 'select public.expire_makeups()');
exception when others then raise notice 'pg_cron 등록을 건너뜀: %', sqlerrm;
end $$;

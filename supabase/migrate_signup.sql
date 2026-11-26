-- =====================================================================
-- DARI 업데이트: 참가자 직접 회원가입 + 운영진 승인
-- 이미 schema.sql을 실행한 프로젝트에서 SQL Editor에 붙여 넣고 한 번 실행하세요.
-- 여러 번 실행해도 안전합니다.
-- =====================================================================

-- 참가자 상태: active(참가 중) · pending(승인 대기) · rejected(거절)
alter table participants add column if not exists status text not null default 'active';
do $$ begin
  alter table participants add constraint participants_status_check check (status in ('active','pending','rejected'));
exception when duplicate_object then null; end $$;

-- 승인된(active) 참가자만 프로그램 데이터(일정·자료·출석·보강 등)를 볼 수 있도록
create or replace function my_pid() returns uuid language sql stable security definer set search_path=public as
$$ select id from participants where user_id = auth.uid() and status = 'active' $$;

create or replace function my_cohort() returns int language sql stable security definer set search_path=public as
$$ select cohort from participants where user_id = auth.uid() and status = 'active' $$;

-- 로그인 직후 호출
--  · 운영진이 미리 등록한 이메일이면 그 참가자 행에 연결 (바로 참가)
--  · 직접 가입한 사람이면 가입 때 입력한 정보로 '승인 대기' 참가자 행을 만듦
create or replace function claim_participant() returns text
language plpgsql security definer set search_path=public as $$
declare v_role text; v_p participants; v_meta jsonb; v_cohort int; v_side text;
  lv text;
begin
  select role into v_role from profiles where id = auth.uid();
  if v_role = 'admin' then return 'admin'; end if;
  update participants set user_id = auth.uid()
   where lower(email) = lower(auth.email()) and user_id is null;
  select * into v_p from participants where user_id = auth.uid();
  if v_p.id is null then
    select raw_user_meta_data into v_meta from auth.users where id = auth.uid();
    if v_meta is null or not (v_meta ? 'dari_signup') then return 'unregistered'; end if;
    select cohort into v_cohort from settings where active limit 1;
    if v_cohort is null then return 'no_cohort'; end if;
    v_side := case when v_meta->>'side' in ('KR','DZ') then v_meta->>'side' else 'KR' end;
    insert into participants (user_id, cohort, name, email, side, univ, kakao_id, ar_level, ko_level, en_level, status)
    values (auth.uid(), v_cohort,
            coalesce(nullif(trim(v_meta->>'name'), ''), split_part(auth.email(), '@', 1)),
            lower(auth.email()), v_side,
            nullif(trim(coalesce(v_meta->>'univ','')), ''), nullif(trim(coalesce(v_meta->>'kakao','')), ''),
            case when v_side = 'KR' and v_meta->>'ar_level' in ('1','2','3') then (v_meta->>'ar_level')::int end,
            case when v_side = 'DZ' and v_meta->>'ko_level' in ('1','2','3') then (v_meta->>'ko_level')::int end,
            case when v_meta->>'en_level' in ('1','2','3') then (v_meta->>'en_level')::int end,
            'pending')
    returning * into v_p;
  end if;
  insert into profiles(id, name, role) values (auth.uid(), v_p.name, 'participant') on conflict (id) do nothing;
  if v_p.status = 'pending' then return 'pending'; end if;
  if v_p.status = 'rejected' then return 'rejected'; end if;
  return 'participant';
end $$;

-- 운영진이 가입 신청을 승인하거나 거절
create or replace function approve_participant(p_id uuid, p_status text) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'admins_only'; end if;
  if p_status not in ('active','rejected','pending') then raise exception 'bad_status'; end if;
  update participants set status = p_status where id = p_id;
end $$;

grant execute on all functions in schema public to anon, authenticated;

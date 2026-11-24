-- =====================================================================
-- DARI — Supabase schema v4 (실제 운영용)
-- Supabase 대시보드 > SQL Editor 에 전체를 붙여 넣고 한 번 실행하세요.
--
-- 담는 것
--   · 참가자/매칭/회차/학습자료/출석/보강/수료증 테이블
--   · 행 수준 보안(RLS): 참가자는 본인·본인 팀 데이터만, 운영진은 전체
--   · 보강 규칙을 서버에서 강제하는 함수(RPC)
--       - 1인 1회: 본인이 신청한 보강이 취소되지 않고 남아 있으면 추가 신청 불가
--         (파트너가 신청한 보강은 포함하지 않음 · 인증 사진을 올린 뒤에는 다시 신청할 수 없음)
--       - 신청: 해당 회차 수업 시작 3시간 전까지
--       - 보강 일시: 지금 이후 ~ 다음 회차 수업 시작 전
--       - 보강 일정 수정·취소: 사진 제출 전, 다음 회차 수업 시작 전까지 (팀원 누구나)
--       - 인증 사진: 보강 시작 ~ 보강일 23:59
--       - 운영진 출석 처리 시 두 참가자 모두 출석으로 변경
--   · 파일 저장소(모두 비공개): materials(학습자료), evidence(보강 인증 사진), certs(수료증)
--   · 실시간 반영(Realtime) 대상 테이블 등록
-- 시간은 모두 한국 시간(Asia/Seoul) 기준으로 저장·비교합니다.
-- =====================================================================

-- ---------- 계정 ----------
create table if not exists profiles (
  id     uuid primary key references auth.users(id) on delete cascade,
  name   text not null,
  role   text not null default 'participant' check (role in ('participant','admin')),
  mlang  text check (mlang in ('ko','ar')),          -- 운영진 구분: ko = 한국 운영진, ar = HAN.AL
  lang   text not null default 'ko' check (lang in ('ko','ar'))
);

-- ---------- 기수 설정 (+ 기수 공통 Zoom 링크) ----------
create table if not exists settings (
  cohort   int primary key,
  active   boolean not null default false,
  zoom_url text, zoom_id text, zoom_pw text            -- 모든 참가자에게 같은 링크가 보입니다
);
create unique index if not exists settings_one_active on settings(active) where active;

-- ---------- 참가자 ----------
create table if not exists participants (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid unique references auth.users(id) on delete set null,
  cohort    int not null references settings(cohort),
  name      text not null,
  email     text not null unique,
  kakao_id  text,                                     -- 운영진만 조회 (파트너에게는 비공개)
  side      text not null check (side in ('KR','DZ')),
  univ      text,
  goal      text check (goal in ('talk','exam','culture','career')),
  interests text[] not null default '{}',
  intro     text,
  en_level  int check (en_level between 1 and 3),
  ar_level  int check (ar_level between 1 and 3),     -- 한국 참가자
  ko_level  int check (ko_level between 1 and 3)      -- 알제리 참가자
);

-- ---------- 매칭 ----------
create table if not exists pairs (
  id       uuid primary key default gen_random_uuid(),
  cohort   int not null references settings(cohort),
  kr_id    uuid not null unique references participants(id) on delete cascade,
  dz_id    uuid not null unique references participants(id) on delete cascade
);

-- ---------- 회차 (기수당 4회) — 활동일·시간·유형·주제를 운영진이 직접 관리 ----------
create table if not exists rounds (
  cohort   int not null references settings(cohort),
  no       int not null check (no between 1 and 4),
  type     text not null default 'talk' check (type in ('talk','act')),
  date     date not null,                             -- 활동일
  time     time not null default '21:00',             -- 시작 시간(한국 시간)
  topic_ko text not null default '',
  topic_ar text,
  primary key (cohort, no)
);

-- ---------- 학습자료 ----------
create table if not exists materials (
  id         uuid primary key default gen_random_uuid(),
  cohort     int not null,
  round      int not null,
  lang       text not null check (lang in ('ko','ar')),
  title      text not null,                           -- 파일 이름(또는 링크 주소)
  descr      text,
  kind       text not null check (kind in ('file','link')),
  file_path  text, file_name text, size bigint, mime text,
  url        text,
  created_by uuid references auth.users(id),
  created_at timestamp not null default (now() at time zone 'Asia/Seoul'),
  foreign key (cohort, round) references rounds(cohort, no) on delete cascade
);

-- ---------- 출석 ----------
create table if not exists attendance (
  participant_id uuid not null references participants(id) on delete cascade,
  round          int not null,
  s              text not null check (s in ('P','A','M')),   -- 출석 / 결석 / 보강 예정
  n              text not null default '',
  primary key (participant_id, round)
);

-- ---------- 보강 ----------
create table if not exists makeups (
  id           uuid primary key default gen_random_uuid(),
  pair_id      uuid not null references pairs(id) on delete cascade,
  round        int not null,
  requested_by uuid not null references participants(id) on delete cascade,
  requested_at timestamp not null default (now() at time zone 'Asia/Seoul'),
  date         date not null,
  time         time not null,
  status       text not null default 'scheduled'
               check (status in ('scheduled','submitted','confirmed','rejected','absent','cancelled')),
  photo_path   text, photo_name text,
  submitted_at timestamp,
  review       text not null default '',
  updated_at   timestamp,
  cancelled_at timestamp
);

-- ---------- 수료증 (운영진이 파일을 올리면 참가자가 내려받음) ----------
create table if not exists certs (
  participant_id uuid primary key references participants(id) on delete cascade,
  date           date not null default ((now() at time zone 'Asia/Seoul')::date),
  file_path      text, file_name text, mime text
);

-- =====================================================================
-- 도우미 함수
-- =====================================================================
create or replace function kst_now() returns timestamp language sql stable as
$$ select now() at time zone 'Asia/Seoul' $$;

create or replace function is_admin() returns boolean language sql stable security definer set search_path=public as
$$ select exists (select 1 from profiles where id = auth.uid() and role = 'admin') $$;

create or replace function my_pid() returns uuid language sql stable security definer set search_path=public as
$$ select id from participants where user_id = auth.uid() $$;

create or replace function my_cohort() returns int language sql stable security definer set search_path=public as
$$ select cohort from participants where user_id = auth.uid() $$;

create or replace function my_pair() returns uuid language sql stable security definer set search_path=public as
$$ select id from pairs where my_pid() in (kr_id, dz_id) $$;

-- 회차 수업 시작 시각(한국 시간)
create or replace function session_start(p_pair uuid, p_round int) returns timestamp
language sql stable security definer set search_path=public as $$
  select r.date + r.time from pairs pr join rounds r on r.cohort = pr.cohort and r.no = p_round where pr.id = p_pair
$$;

-- 다음 회차 수업 시작 시각 (마지막 회차면 7일 뒤)
create or replace function next_session(p_pair uuid, p_round int) returns timestamp
language sql stable security definer set search_path=public as $$
  select coalesce(session_start(p_pair, p_round + 1), session_start(p_pair, p_round) + interval '7 days')
$$;

-- 로그인 직후 호출: 운영진이 등록한 이메일과 같은 참가자 행을 내 계정에 연결
create or replace function claim_participant() returns text
language plpgsql security definer set search_path=public as $$
declare v_role text; v_name text;
begin
  select role into v_role from profiles where id = auth.uid();
  if v_role = 'admin' then return 'admin'; end if;
  update participants set user_id = auth.uid()
   where lower(email) = lower(auth.email()) and user_id is null;
  select name into v_name from participants where user_id = auth.uid();
  if v_name is null then return 'unregistered'; end if;
  insert into profiles(id, name, role) values (auth.uid(), v_name, 'participant')
  on conflict (id) do nothing;
  return 'participant';
end $$;

-- 내 파트너 프로필 (이메일·카카오톡 ID 제외)
create or replace function my_partner()
returns table (id uuid, name text, side text, univ text, cohort int, goal text, interests text[], intro text,
               en_level int, ar_level int, ko_level int)
language sql stable security definer set search_path=public as $$
  select p.id, p.name, p.side, p.univ, p.cohort, p.goal, p.interests, p.intro, p.en_level, p.ar_level, p.ko_level
    from pairs pr join participants p
      on p.id = case when pr.kr_id = my_pid() then pr.dz_id else pr.kr_id end
   where my_pid() in (pr.kr_id, pr.dz_id)
$$;

-- =====================================================================
-- 보강 규칙 (서버에서 강제)
-- =====================================================================
create or replace function request_makeup(p_round int, p_date date, p_time time) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_me uuid := my_pid(); v_pair pairs; v_start timestamp; v_when timestamp; v_id uuid;
begin
  if v_me is null then raise exception 'not_participant'; end if;
  select * into v_pair from pairs where v_me in (kr_id, dz_id);
  if v_pair.id is null then raise exception 'no_pair'; end if;
  -- 1인 1회: 내가 신청한 보강이 취소되지 않고 남아 있으면 불가 (파트너가 신청한 보강은 제외)
  if exists (select 1 from makeups where requested_by = v_me and status <> 'cancelled') then
    raise exception 'already_requested';
  end if;
  v_start := session_start(v_pair.id, p_round);
  if v_start is null then raise exception 'no_session'; end if;
  if kst_now() >= v_start - interval '3 hours' then raise exception 'deadline_passed'; end if;
  v_when := p_date + p_time;
  if not (v_when > kst_now() and v_when < next_session(v_pair.id, p_round)) then raise exception 'out_of_window'; end if;
  if exists (select 1 from attendance where participant_id = v_me and round = p_round) then
    raise exception 'already_recorded';
  end if;
  insert into makeups(pair_id, round, requested_by, date, time) values (v_pair.id, p_round, v_me, p_date, p_time)
  returning id into v_id;
  insert into attendance(participant_id, round, s, n) values (v_pair.kr_id, p_round, 'M', ''), (v_pair.dz_id, p_round, 'M', '')
  on conflict (participant_id, round) do update set s = 'M', n = '';
  return v_id;
end $$;

-- 보강 일정 수정: 팀원 누구나 · 사진 제출 전 · 다음 회차 수업 시작 전까지
create or replace function reschedule_makeup(p_id uuid, p_date date, p_time time) returns void
language plpgsql security definer set search_path=public as $$
declare m makeups; v_until timestamp; v_when timestamp := p_date + p_time;
begin
  select * into m from makeups where id = p_id;
  if m.id is null or m.pair_id is distinct from my_pair() then raise exception 'not_allowed'; end if;
  if m.status <> 'scheduled' then raise exception 'not_cancellable'; end if;
  v_until := next_session(m.pair_id, m.round);
  if kst_now() >= v_until then raise exception 'deadline_passed'; end if;
  if not (v_when > kst_now() and v_when < v_until) then raise exception 'out_of_window'; end if;
  update makeups set date = p_date, time = p_time, updated_at = kst_now() where id = p_id;
end $$;

-- 보강 취소: 팀원 누구나 · 사진 제출 전 · 다음 회차 수업 시작 전까지
create or replace function cancel_makeup(p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare m makeups; v_pair pairs;
begin
  select * into m from makeups where id = p_id;
  if m.id is null or m.pair_id is distinct from my_pair() then raise exception 'not_allowed'; end if;
  if m.status <> 'scheduled' then raise exception 'not_cancellable'; end if;
  if kst_now() >= next_session(m.pair_id, m.round) then raise exception 'deadline_passed'; end if;
  update makeups set status = 'cancelled', cancelled_at = kst_now() where id = p_id;
  select * into v_pair from pairs where id = m.pair_id;
  delete from attendance where round = m.round and s = 'M' and participant_id in (v_pair.kr_id, v_pair.dz_id);
end $$;

create or replace function submit_makeup_photo(p_id uuid, p_path text, p_name text) returns void
language plpgsql security definer set search_path=public as $$
declare m makeups;
begin
  select * into m from makeups where id = p_id;
  if m.id is null or m.pair_id is distinct from my_pair() then raise exception 'not_allowed'; end if;
  if m.status not in ('scheduled','rejected') then raise exception 'not_submittable'; end if;
  if kst_now() < m.date + m.time then raise exception 'too_early'; end if;
  if kst_now() > m.date + time '23:59:59' then raise exception 'deadline_passed'; end if;
  if split_part(p_path, '/', 1) <> m.pair_id::text then raise exception 'bad_path'; end if;
  update makeups set photo_path = p_path, photo_name = p_name, status = 'submitted', submitted_at = kst_now() where id = p_id;
end $$;

create or replace function review_makeup(p_id uuid, p_decision text, p_review text) returns void
language plpgsql security definer set search_path=public as $$
declare m makeups; v_pair pairs;
begin
  if not is_admin() then raise exception 'admins_only'; end if;
  select * into m from makeups where id = p_id;
  if m.status <> 'submitted' then raise exception 'not_submitted'; end if;
  if p_decision = 'rejected' and coalesce(trim(p_review), '') = '' then raise exception 'review_required'; end if;
  update makeups set status = p_decision, review = coalesce(p_review, '') where id = p_id;
  if p_decision = 'confirmed' then
    select * into v_pair from pairs where id = m.pair_id;
    insert into attendance(participant_id, round, s, n)
    values (v_pair.kr_id, m.round, 'P', '↻ ' || to_char(m.date, 'MM.DD')), (v_pair.dz_id, m.round, 'P', '↻ ' || to_char(m.date, 'MM.DD'))
    on conflict (participant_id, round) do update set s = 'P', n = excluded.n;
  end if;
end $$;

create or replace function mark_makeup_absent(p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare m makeups; v_pair pairs;
begin
  if not is_admin() then raise exception 'admins_only'; end if;
  select * into m from makeups where id = p_id;
  update makeups set status = 'absent' where id = p_id;
  select * into v_pair from pairs where id = m.pair_id;
  insert into attendance(participant_id, round, s, n) values (v_pair.kr_id, m.round, 'A', ''), (v_pair.dz_id, m.round, 'A', '')
  on conflict (participant_id, round) do update set s = 'A', n = '';
end $$;

-- =====================================================================
-- 행 수준 보안 (RLS)
-- =====================================================================
alter table profiles     enable row level security;
alter table settings     enable row level security;
alter table participants enable row level security;
alter table pairs        enable row level security;
alter table rounds       enable row level security;
alter table materials    enable row level security;
alter table attendance   enable row level security;
alter table makeups      enable row level security;
alter table certs        enable row level security;

-- 운영진: 전체 (한국 운영진·HAN.AL 구분 없이 같은 권한)
create policy admin_all on profiles     for all using (is_admin()) with check (is_admin());
create policy admin_all on settings     for all using (is_admin()) with check (is_admin());
create policy admin_all on participants for all using (is_admin()) with check (is_admin());
create policy admin_all on pairs        for all using (is_admin()) with check (is_admin());
create policy admin_all on rounds       for all using (is_admin()) with check (is_admin());
create policy admin_all on materials    for all using (is_admin()) with check (is_admin());
create policy admin_all on attendance   for all using (is_admin()) with check (is_admin());
create policy admin_read on makeups     for select using (is_admin());
create policy admin_all on certs        for all using (is_admin()) with check (is_admin());

-- 참가자: 본인 · 본인 팀 · 본인 기수
create policy own_profile    on profiles     for select using (id = auth.uid());
create policy read_settings  on settings     for select using (cohort = my_cohort());
create policy own_row        on participants for select using (user_id = auth.uid());
create policy own_row_update on participants for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_pair       on pairs        for select using (my_pid() in (kr_id, dz_id));
create policy cohort_rounds  on rounds       for select using (cohort = my_cohort());
create policy cohort_mats    on materials    for select using (cohort = my_cohort());
create policy own_att        on attendance   for select using (participant_id = my_pid());
create policy own_makeups    on makeups      for select using (pair_id = my_pair());
create policy own_cert       on certs        for select using (participant_id = my_pid());
-- 보강 신청·수정·취소·제출·검토는 위 함수로만 가능 (makeups에 직접 쓰기 정책 없음)

-- 참가자가 직접 고칠 수 있는 열은 프로필 항목뿐
-- 사이트(로그인한 사용자)가 표와 함수에 접근할 수 있도록 권한 부여 (실제 범위는 위 RLS 규칙이 제한)
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to anon, authenticated;
revoke update on participants from authenticated;
grant update (goal, interests, intro, en_level, ar_level, ko_level, kakao_id) on participants to authenticated;

-- =====================================================================
-- 파일 저장소 (비공개 버킷)
--   materials/<기수>/<회차>/<ko|ar>/<파일>
--   evidence/<팀 id>/<파일>
--   certs/<참가자 id>/<파일>
-- =====================================================================
insert into storage.buckets (id, name, public) values ('materials', 'materials', false) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('evidence', 'evidence', false) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('certs', 'certs', false) on conflict (id) do nothing;

create policy materials_read on storage.objects for select
  using (bucket_id = 'materials' and (is_admin() or (storage.foldername(name))[1] = my_cohort()::text));
create policy materials_write on storage.objects for insert
  with check (bucket_id = 'materials' and is_admin());
create policy materials_delete on storage.objects for delete
  using (bucket_id = 'materials' and is_admin());
create policy evidence_read on storage.objects for select
  using (bucket_id = 'evidence' and (is_admin() or (storage.foldername(name))[1] = my_pair()::text));
create policy evidence_write on storage.objects for insert
  with check (bucket_id = 'evidence' and (storage.foldername(name))[1] = my_pair()::text);
create policy certs_read on storage.objects for select
  using (bucket_id = 'certs' and (is_admin() or (storage.foldername(name))[1] = my_pid()::text));
create policy certs_write on storage.objects for insert
  with check (bucket_id = 'certs' and is_admin());
create policy certs_delete on storage.objects for delete
  using (bucket_id = 'certs' and is_admin());

-- =====================================================================
-- 실시간 반영: 다른 기기·다른 운영진의 변경이 바로 화면에 나타나도록
-- =====================================================================
alter publication supabase_realtime add table settings, participants, pairs, rounds, materials, attendance, makeups, certs;

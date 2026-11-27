-- =====================================================================
-- DARI 업데이트: 운영진의 참가자 비밀번호 초기화
-- SQL Editor에 붙여 넣고 한 번 실행하세요. 여러 번 실행해도 안전합니다.
-- =====================================================================
create or replace function admin_reset_password(p_pid uuid, p_password text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid; v_email text;
begin
  if not is_admin() then raise exception 'admins_only'; end if;
  if p_password is null or length(p_password) < 6 then raise exception 'weak_password'; end if;
  select user_id, email into v_uid, v_email from participants where id = p_pid;
  if v_email is null then raise exception 'not_found'; end if;
  if v_uid is null then select id into v_uid from auth.users where lower(email) = lower(v_email); end if;
  if v_uid is null then raise exception 'no_account'; end if;
  update auth.users
     set encrypted_password = crypt(p_password, gen_salt('bf')),
         email_confirmed_at = coalesce(email_confirmed_at, now())
   where id = v_uid;
end $$;
revoke all on function admin_reset_password(uuid, text) from public, anon;
grant execute on function admin_reset_password(uuid, text) to authenticated;

-- 앱 안에서 본인 계정 삭제 (Google Play 계정 삭제 정책).
-- auth.users 를 지우면 items 는 on delete cascade 로 함께 지워진다.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not signed in';
  end if;
  delete from public.items where user_id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

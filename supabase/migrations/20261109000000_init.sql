-- 계열화 To-Do: items 한 테이블로 목표/프로젝트/액션 3단계를 표현
create table public.items (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  parent_id text,
  level int not null default 0,
  sort double precision not null default 0,
  title text not null default '',
  status text not null default 'todo',
  priority int not null default 2,
  due date,
  deps text[] not null default '{}',
  seq boolean not null default false,
  today boolean not null default false,
  note text not null default '',
  done_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted boolean not null default false,
  -- 서버가 찍는 시각. 기기 시계와 무관하게 "마지막 동기화 이후 변경분"을 가져올 때 쓴다.
  synced_at timestamptz not null default now()
);

alter table public.items enable row level security;

create policy "own rows" on public.items
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create index on public.items (user_id, updated_at);
create index on public.items (user_id, synced_at);

-- last-write-wins: 더 오래된 updated_at 으로는 덮어쓰지 않는다. synced_at 은 항상 서버 시각.
create or replace function public.items_lww()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.updated_at < old.updated_at then
      return null; -- 더 오래된 변경은 무시
    end if;
    new.user_id := old.user_id;
  end if;
  new.synced_at := now();
  return new;
end;
$$;

create trigger items_lww
  before insert or update on public.items
  for each row execute function public.items_lww();

alter publication supabase_realtime add table public.items;

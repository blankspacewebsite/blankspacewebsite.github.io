-- Blank Space v128: owner-only leaderboard delete + restore missing profile rows + show all leaderboard accounts
-- Paste this whole file into Supabase SQL Editor and click Run.
--
-- Important recovery note:
-- This can recover accounts removed from public.profiles ONLY if their auth.users login row still exists.
-- If an account was deleted from auth.users, SQL cannot recover its login/password without a Supabase backup.
--
-- What this does:
-- - Restores missing public.profiles rows from auth.users.
-- - Makes get_public_leaderboard return up to 10000 accounts, not just top 100.
-- - Adds owner_delete_account(uuid), protected so only Owner can use it.
-- - Protects Owner/Admin accounts from deletion.
-- - Does not reset points, achievements, icons, banners, chats, or passwords.

alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists points integer default 0;
alter table public.profiles add column if not exists rank text default 'member';
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists equipped_icon text;
alter table public.profiles add column if not exists true_member boolean default false;
alter table public.profiles add column if not exists last_seen_at timestamptz;
alter table public.profiles add column if not exists created_at timestamptz default now();
alter table public.profiles add column if not exists updated_at timestamptz default now();

create or replace function public.blank_space_clean_restore_username(p_raw text, p_id uuid)
returns text
language sql
immutable
as $$
  select left(
    regexp_replace(
      coalesce(nullif(trim(p_raw), ''), 'User' || substring(p_id::text from 1 for 8)),
      '[^A-Za-z0-9.-]',
      '',
      'g'
    ),
    48
  );
$$;

create or replace function public.blank_space_unique_restore_username(p_raw text, p_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base text;
  v_candidate text;
  v_suffix integer := 2;
begin
  v_base := public.blank_space_clean_restore_username(p_raw, p_id);
  if v_base is null or trim(v_base) = '' then
    v_base := 'User' || substring(p_id::text from 1 for 8);
  end if;

  v_candidate := left(v_base, 64);

  if not exists (
    select 1 from public.profiles p
    where lower(trim(p.username)) = lower(trim(v_candidate))
      and p.id is distinct from p_id
  ) then
    return v_candidate;
  end if;

  loop
    v_candidate := left(v_base, greatest(1, 64 - length(v_suffix::text))) || v_suffix::text;

    if not exists (
      select 1 from public.profiles p
      where lower(trim(p.username)) = lower(trim(v_candidate))
        and p.id is distinct from p_id
    ) then
      return v_candidate;
    end if;

    v_suffix := v_suffix + 1;
    if v_suffix > 9999 then
      return left('User' || replace(p_id::text, '-', ''), 64);
    end if;
  end loop;
end;
$$;

-- Recover profile rows for auth accounts that still exist.
do $$
declare
  r record;
  v_raw text;
  v_username text;
begin
  for r in
    select u.*
    from auth.users u
    left join public.profiles p on p.id = u.id
    where p.id is null
    order by u.created_at asc nulls last, u.id asc
  loop
    v_raw := coalesce(
      nullif(trim(r.raw_user_meta_data->>'username'), ''),
      nullif(trim(r.raw_user_meta_data->>'name'), ''),
      nullif(trim(split_part(r.email, '@', 1)), ''),
      'User' || substring(r.id::text from 1 for 8)
    );

    v_username := public.blank_space_unique_restore_username(v_raw, r.id);

    insert into public.profiles(
      id, username, display_name, points, rank, true_member, created_at, updated_at
    )
    values(
      r.id,
      v_username,
      v_username,
      0,
      case when lower(trim(v_username)) in ('owner','admin') then 'owner' else 'member' end,
      false,
      coalesce(r.created_at, now()),
      now()
    )
    on conflict(id) do nothing;
  end loop;
end $$;

-- Keep Owner safe.
update public.profiles
set username='Owner', display_name='Owner', rank='owner', points=coalesce(points,0), updated_at=now()
where lower(trim(coalesce(username,''))) in ('owner','admin');

-- RLS and grants.
alter table public.profiles enable row level security;

drop policy if exists "blank_space_profiles_select_public" on public.profiles;
drop policy if exists "blank_space_profiles_insert_own" on public.profiles;
drop policy if exists "blank_space_profiles_update_own" on public.profiles;

create policy "blank_space_profiles_select_public"
on public.profiles
for select
to anon, authenticated
using (true);

create policy "blank_space_profiles_insert_own"
on public.profiles
for insert
to authenticated
with check (id = auth.uid());

create policy "blank_space_profiles_update_own"
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

grant usage on schema public to anon, authenticated;
grant select on public.profiles to anon, authenticated;
grant insert, update on public.profiles to authenticated;

-- Full leaderboard RPC.
drop function if exists public.get_public_leaderboard(integer);

create function public.get_public_leaderboard(max_rows integer default 10000)
returns table(
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  points integer,
  equipped_icon text,
  rank text,
  true_member boolean,
  last_seen_at timestamptz,
  equipped_banner_id text,
  equipped_banner_name text,
  equipped_banner_gradient text
)
language sql
security definer
set search_path = public
as $$
  select
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    coalesce(p.points,0)::integer as points,
    p.equipped_icon,
    coalesce(p.rank,'member') as rank,
    coalesce(p.true_member,false) as true_member,
    p.last_seen_at,
    case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='equipped_banner_id') then null::text else null::text end as equipped_banner_id,
    case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='equipped_banner_name') then null::text else null::text end as equipped_banner_name,
    case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='equipped_banner_gradient') then null::text else null::text end as equipped_banner_gradient
  from public.profiles p
  where p.id is not null
  order by coalesce(p.points,0) desc, lower(coalesce(p.username,'')) asc
  limit greatest(1, least(coalesce(max_rows,10000), 10000));
$$;

grant execute on function public.get_public_leaderboard(integer) to anon, authenticated;

-- Owner-only delete function. This removes profile-related rows and then tries to remove auth.users.
drop function if exists public.owner_delete_account(uuid);

create function public.owner_delete_account(p_target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_actor_rank text;
  v_actor_username text;
  v_target_username text;
  v_target_rank text;
  r record;
begin
  if v_actor is null then
    raise exception 'Sign in first.';
  end if;

  select lower(trim(coalesce(rank,''))), lower(trim(coalesce(username,'')))
  into v_actor_rank, v_actor_username
  from public.profiles
  where id = v_actor;

  if v_actor_rank <> 'owner' and v_actor_username <> 'owner' then
    raise exception 'Owner only.';
  end if;

  if p_target_user_id is null then
    raise exception 'Missing target user id.';
  end if;

  if p_target_user_id = v_actor then
    raise exception 'You cannot remove your own Owner account.';
  end if;

  select username, lower(trim(coalesce(rank,'')))
  into v_target_username, v_target_rank
  from public.profiles
  where id = p_target_user_id;

  if p_target_user_id is null or v_target_username is null then
    raise exception 'Target account not found.';
  end if;

  if lower(trim(coalesce(v_target_username,''))) in ('owner','admin') or v_target_rank in ('owner','admin') then
    raise exception 'Protected account cannot be removed.';
  end if;

  -- Delete common user-linked rows first.
  for r in
    select c.table_schema, c.table_name, c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema
     and t.table_name = c.table_name
    where c.table_schema = 'public'
      and t.table_type = 'BASE TABLE'
      and c.data_type = 'uuid'
      and c.column_name in (
        'user_id','profile_id','owner_id','sender_id','receiver_id','recipient_id',
        'from_user_id','to_user_id','target_user_id','blocked_user_id','blocker_id',
        'friend_id','requester_id','addressee_id','member_id','created_by','last_user_id'
      )
  loop
    execute format('delete from %I.%I where %I = $1', r.table_schema, r.table_name, r.column_name)
    using p_target_user_id;
  end loop;

  delete from public.profiles where id = p_target_user_id;
  delete from auth.users where id = p_target_user_id;

  return jsonb_build_object('ok', true, 'removed_username', v_target_username, 'removed_user_id', p_target_user_id);
end;
$$;

grant execute on function public.owner_delete_account(uuid) to authenticated;

create index if not exists profiles_points_username_idx on public.profiles(points desc, lower(username));
create index if not exists profiles_username_lower_idx on public.profiles(lower(username));
create index if not exists profiles_rank_lower_idx on public.profiles(lower(rank));

select pg_notify('pgrst','reload schema');

-- Final checks.
select
  (select count(*) from auth.users u left join public.profiles p on p.id=u.id where p.id is null) as auth_accounts_still_missing_profiles,
  (select count(*) from public.profiles) as profiles_now,
  (select count(*) from public.get_public_leaderboard(10000)) as leaderboard_rows_now;

-- Blank Space v129: banners, True Member maker, leaderboard medal support
-- Paste this into Supabase SQL Editor and click Run.
--
-- What this fixes:
-- - Banner collection/loading/equipping.
-- - True Member maker in Owner Panel.
-- - Leaderboard RPC returns true_member and banner fields.
-- - Does NOT reset points, achievements, chats, passwords, icons, or existing banners.

alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists points integer default 0;
alter table public.profiles add column if not exists rank text default 'member';
alter table public.profiles add column if not exists true_member boolean default false;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists equipped_icon text;
alter table public.profiles add column if not exists equipped_banner_id text;
alter table public.profiles add column if not exists equipped_banner_name text;
alter table public.profiles add column if not exists equipped_banner_gradient text;
alter table public.profiles add column if not exists updated_at timestamptz default now();

create table if not exists public.user_banners (
  user_id uuid not null references public.profiles(id) on delete cascade,
  banner_id text not null,
  banner_name text not null,
  banner_gradient text not null,
  unlocked_at timestamptz not null default now(),
  primary key(user_id, banner_id)
);

alter table public.user_banners enable row level security;

drop policy if exists "blank_space_user_banners_select" on public.user_banners;
drop policy if exists "blank_space_user_banners_insert_own" on public.user_banners;
drop policy if exists "blank_space_user_banners_update_own" on public.user_banners;

create policy "blank_space_user_banners_select"
on public.user_banners
for select
to authenticated
using (true);

create policy "blank_space_user_banners_insert_own"
on public.user_banners
for insert
to authenticated
with check (user_id = auth.uid());

create policy "blank_space_user_banners_update_own"
on public.user_banners
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

grant select, insert, update on public.user_banners to authenticated;

create or replace function public.get_my_banners_v129()
returns table(
  banner_id text,
  banner_name text,
  banner_gradient text,
  unlocked_at timestamptz,
  equipped boolean
)
language sql
security definer
set search_path = public
as $$
  select
    b.banner_id,
    b.banner_name,
    b.banner_gradient,
    b.unlocked_at,
    (p.equipped_banner_id = b.banner_id) as equipped
  from public.user_banners b
  join public.profiles p on p.id = b.user_id
  where b.user_id = auth.uid()
  order by b.unlocked_at desc, b.banner_name asc;
$$;

grant execute on function public.get_my_banners_v129() to authenticated;

create or replace function public.buy_banner_pack_v129(p_pack_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_pack text := lower(trim(coalesce(p_pack_id,'')));
  v_cost integer;
  v_points integer;
  v_added integer := 0;
begin
  if v_uid is null then raise exception 'Sign in first.'; end if;

  v_cost := case v_pack
    when 'starter' then 10
    when 'neon' then 25
    when 'royal' then 40
    else null
  end;

  if v_cost is null then raise exception 'Unknown banner pack.'; end if;

  select coalesce(points,0) into v_points from public.profiles where id = v_uid for update;
  if v_points is null then raise exception 'Profile not found.'; end if;
  if v_points < v_cost then raise exception 'Not enough points.'; end if;

  perform set_config('blank_space.allow_points_update','1',true);
  update public.profiles set points = points - v_cost, updated_at = now() where id = v_uid;

  if v_pack = 'starter' then
    insert into public.user_banners(user_id,banner_id,banner_name,banner_gradient) values
      (v_uid,'midnight','Midnight','linear-gradient(135deg,#020617,#1e293b)'),
      (v_uid,'ocean','Ocean','linear-gradient(135deg,#0f172a,#0369a1,#22d3ee)'),
      (v_uid,'forest','Forest','linear-gradient(135deg,#052e16,#16a34a,#bbf7d0)')
    on conflict do nothing;
  elsif v_pack = 'neon' then
    insert into public.user_banners(user_id,banner_id,banner_name,banner_gradient) values
      (v_uid,'neon-pink','Neon Pink','linear-gradient(135deg,#111827,#db2777,#f0abfc)'),
      (v_uid,'electric','Electric','linear-gradient(135deg,#020617,#2563eb,#67e8f9)'),
      (v_uid,'toxic','Toxic','linear-gradient(135deg,#111827,#65a30d,#d9f99d)')
    on conflict do nothing;
  elsif v_pack = 'royal' then
    insert into public.user_banners(user_id,banner_id,banner_name,banner_gradient) values
      (v_uid,'gold','Gold','linear-gradient(135deg,#422006,#ca8a04,#fef08a)'),
      (v_uid,'purple','Purple','linear-gradient(135deg,#2e1065,#7e22ce,#e9d5ff)'),
      (v_uid,'ruby','Ruby','linear-gradient(135deg,#450a0a,#dc2626,#fecaca)')
    on conflict do nothing;
  end if;

  get diagnostics v_added = row_count;

  return jsonb_build_object('ok', true, 'pack_id', v_pack, 'cost', v_cost, 'added', v_added);
end;
$$;

grant execute on function public.buy_banner_pack_v129(text) to authenticated;

create or replace function public.equip_banner_v129(p_banner_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  b record;
begin
  if v_uid is null then raise exception 'Sign in first.'; end if;

  select *
  into b
  from public.user_banners
  where user_id = v_uid
    and banner_id = trim(coalesce(p_banner_id,''))
  limit 1;

  if b.banner_id is null then
    raise exception 'You do not own this banner.';
  end if;

  update public.profiles
  set
    equipped_banner_id = b.banner_id,
    equipped_banner_name = b.banner_name,
    equipped_banner_gradient = b.banner_gradient,
    updated_at = now()
  where id = v_uid;

  return jsonb_build_object('ok', true, 'banner_id', b.banner_id, 'banner_name', b.banner_name);
end;
$$;

grant execute on function public.equip_banner_v129(text) to authenticated;

-- Compatibility aliases from older versions.
create or replace function public.get_my_banners()
returns table(banner_id text, banner_name text, banner_gradient text, unlocked_at timestamptz, equipped boolean)
language sql
security definer
set search_path = public
as $$
  select * from public.get_my_banners_v129();
$$;
grant execute on function public.get_my_banners() to authenticated;

create or replace function public.buy_banner_pack(p_pack_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.buy_banner_pack_v129(p_pack_id);
end;
$$;
grant execute on function public.buy_banner_pack(text) to authenticated;

create or replace function public.equip_banner(p_banner_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.equip_banner_v129(p_banner_id);
end;
$$;
grant execute on function public.equip_banner(text) to authenticated;

create or replace function public.owner_make_true_member_v129(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_actor_rank text;
  v_actor_username text;
  v_target record;
begin
  if v_actor is null then raise exception 'Sign in first.'; end if;

  select lower(trim(coalesce(rank,''))), lower(trim(coalesce(username,'')))
  into v_actor_rank, v_actor_username
  from public.profiles
  where id = v_actor;

  if v_actor_rank <> 'owner' and v_actor_username <> 'owner' then
    raise exception 'Owner only.';
  end if;

  select id, username
  into v_target
  from public.profiles
  where lower(trim(username)) = lower(trim(p_username))
  order by created_at asc nulls last, id asc
  limit 1;

  if v_target.id is null then raise exception 'User not found.'; end if;

  update public.profiles
  set true_member = true, updated_at = now()
  where id = v_target.id;

  return jsonb_build_object('ok', true, 'user_id', v_target.id, 'username', v_target.username);
end;
$$;

grant execute on function public.owner_make_true_member_v129(text) to authenticated;

create or replace function public.owner_make_true_member(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.owner_make_true_member_v129(p_username);
end;
$$;

grant execute on function public.owner_make_true_member(text) to authenticated;

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
    coalesce(p.points,0)::integer,
    p.equipped_icon,
    coalesce(p.rank,'member'),
    coalesce(p.true_member,false),
    p.last_seen_at,
    p.equipped_banner_id,
    p.equipped_banner_name,
    p.equipped_banner_gradient
  from public.profiles p
  where p.id is not null
  order by coalesce(p.points,0) desc, lower(coalesce(p.username,'')) asc
  limit greatest(1, least(coalesce(max_rows,10000), 10000));
$$;

grant execute on function public.get_public_leaderboard(integer) to anon, authenticated;

create index if not exists user_banners_user_id_idx on public.user_banners(user_id);
create index if not exists profiles_banner_idx on public.profiles(equipped_banner_id);
create index if not exists profiles_true_member_idx on public.profiles(true_member);

select pg_notify('pgrst','reload schema');

select
  'OK - v129 banners and true member functions installed' as status,
  (select count(*) from public.user_banners) as banner_rows,
  (select count(*) from public.profiles where true_member = true) as true_members;

-- Blank Space v130: banners, True Member maker, and leaderboard medal support
-- Paste this into Supabase SQL Editor and click Run.
--
-- What this fixes:
-- - Banner loading, buying, and equipping.
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
  banner_name text,
  banner_gradient text,
  name text,
  gradient text,
  rarity text default 'common',
  unlocked_at timestamptz default now(),
  acquired_at timestamptz default now(),
  primary key(user_id, banner_id)
);

alter table public.user_banners add column if not exists banner_name text;
alter table public.user_banners add column if not exists banner_gradient text;
alter table public.user_banners add column if not exists name text;
alter table public.user_banners add column if not exists gradient text;
alter table public.user_banners add column if not exists rarity text default 'common';
alter table public.user_banners add column if not exists unlocked_at timestamptz default now();
alter table public.user_banners add column if not exists acquired_at timestamptz default now();

update public.user_banners
set
  banner_name = coalesce(nullif(trim(banner_name), ''), nullif(trim(name), ''), banner_id),
  name = coalesce(nullif(trim(name), ''), nullif(trim(banner_name), ''), banner_id),
  banner_gradient = coalesce(nullif(trim(banner_gradient), ''), nullif(trim(gradient), ''), 'linear-gradient(135deg,#111827,#22c55e)'),
  gradient = coalesce(nullif(trim(gradient), ''), nullif(trim(banner_gradient), ''), 'linear-gradient(135deg,#111827,#22c55e)'),
  unlocked_at = coalesce(unlocked_at, acquired_at, now()),
  acquired_at = coalesce(acquired_at, unlocked_at, now());

alter table public.user_banners enable row level security;

drop policy if exists "blank_space_user_banners_select" on public.user_banners;
drop policy if exists "blank_space_user_banners_insert_own" on public.user_banners;
drop policy if exists "blank_space_user_banners_update_own" on public.user_banners;
drop policy if exists "blank_space_user_banners_delete_own" on public.user_banners;

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

create policy "blank_space_user_banners_delete_own"
on public.user_banners
for delete
to authenticated
using (user_id = auth.uid());

grant select, insert, update, delete on public.user_banners to authenticated;

create or replace function public.get_my_banners_v130()
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
    coalesce(nullif(b.banner_name,''), nullif(b.name,''), b.banner_id) as banner_name,
    coalesce(nullif(b.banner_gradient,''), nullif(b.gradient,''), 'linear-gradient(135deg,#111827,#22c55e)') as banner_gradient,
    coalesce(b.unlocked_at, b.acquired_at, now()) as unlocked_at,
    (p.equipped_banner_id = b.banner_id) as equipped
  from public.user_banners b
  join public.profiles p on p.id = b.user_id
  where b.user_id = auth.uid()
  order by coalesce(b.unlocked_at, b.acquired_at, now()) desc, coalesce(b.banner_name,b.name,b.banner_id) asc;
$$;

grant execute on function public.get_my_banners_v130() to authenticated;

create or replace function public.buy_banner_pack_v130(p_pack_id text)
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
  update public.profiles set points = greatest(0, coalesce(points,0) - v_cost), updated_at = now() where id = v_uid;

  if v_pack = 'starter' then
    insert into public.user_banners(user_id,banner_id,banner_name,banner_gradient,name,gradient,rarity) values
      (v_uid,'midnight','Midnight','linear-gradient(135deg,#020617,#1e293b)','Midnight','linear-gradient(135deg,#020617,#1e293b)','common'),
      (v_uid,'ocean','Ocean','linear-gradient(135deg,#0f172a,#0369a1,#22d3ee)','Ocean','linear-gradient(135deg,#0f172a,#0369a1,#22d3ee)','common'),
      (v_uid,'forest','Forest','linear-gradient(135deg,#052e16,#16a34a,#bbf7d0)','Forest','linear-gradient(135deg,#052e16,#16a34a,#bbf7d0)','common')
    on conflict do nothing;
  elsif v_pack = 'neon' then
    insert into public.user_banners(user_id,banner_id,banner_name,banner_gradient,name,gradient,rarity) values
      (v_uid,'neon-pink','Neon Pink','linear-gradient(135deg,#111827,#db2777,#f0abfc)','Neon Pink','linear-gradient(135deg,#111827,#db2777,#f0abfc)','rare'),
      (v_uid,'electric','Electric','linear-gradient(135deg,#020617,#2563eb,#67e8f9)','Electric','linear-gradient(135deg,#020617,#2563eb,#67e8f9)','rare'),
      (v_uid,'toxic','Toxic','linear-gradient(135deg,#111827,#65a30d,#d9f99d)','Toxic','linear-gradient(135deg,#111827,#65a30d,#d9f99d)','rare')
    on conflict do nothing;
  elsif v_pack = 'royal' then
    insert into public.user_banners(user_id,banner_id,banner_name,banner_gradient,name,gradient,rarity) values
      (v_uid,'gold','Gold','linear-gradient(135deg,#422006,#ca8a04,#fef08a)','Gold','linear-gradient(135deg,#422006,#ca8a04,#fef08a)','epic'),
      (v_uid,'purple','Purple','linear-gradient(135deg,#2e1065,#7e22ce,#e9d5ff)','Purple','linear-gradient(135deg,#2e1065,#7e22ce,#e9d5ff)','epic'),
      (v_uid,'ruby','Ruby','linear-gradient(135deg,#450a0a,#dc2626,#fecaca)','Ruby','linear-gradient(135deg,#450a0a,#dc2626,#fecaca)','epic')
    on conflict do nothing;
  end if;

  get diagnostics v_added = row_count;

  return jsonb_build_object('ok', true, 'pack_id', v_pack, 'cost', v_cost, 'added', v_added);
end;
$$;

grant execute on function public.buy_banner_pack_v130(text) to authenticated;

create or replace function public.equip_banner_v130(p_banner_id text)
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

  select
    banner_id,
    coalesce(nullif(banner_name,''), nullif(name,''), banner_id) as banner_name,
    coalesce(nullif(banner_gradient,''), nullif(gradient,''), 'linear-gradient(135deg,#111827,#22c55e)') as banner_gradient
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

grant execute on function public.equip_banner_v130(text) to authenticated;

-- Compatibility aliases.
create or replace function public.get_my_banners()
returns table(banner_id text, banner_name text, banner_gradient text, unlocked_at timestamptz, equipped boolean)
language sql
security definer
set search_path = public
as $$
  select * from public.get_my_banners_v130();
$$;
grant execute on function public.get_my_banners() to authenticated;

create or replace function public.buy_banner_pack(p_pack_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.buy_banner_pack_v130(p_pack_id);
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
  return public.equip_banner_v130(p_banner_id);
end;
$$;
grant execute on function public.equip_banner(text) to authenticated;

create or replace function public.owner_make_true_member_v130(p_username text)
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

grant execute on function public.owner_make_true_member_v130(text) to authenticated;

create or replace function public.owner_make_true_member(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.owner_make_true_member_v130(p_username);
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
  order by coalesce(p.points,0) desc, lower(coalesce(p.username,'')) asc
  limit greatest(1, least(coalesce(max_rows,10000), 10000));
$$;

grant execute on function public.get_public_leaderboard(integer) to anon, authenticated;

alter table public.profiles enable row level security;

drop policy if exists "blank_space_profiles_select_public" on public.profiles;
drop policy if exists "blank_space_profiles_update_own" on public.profiles;

create policy "blank_space_profiles_select_public"
on public.profiles
for select
to anon, authenticated
using (true);

create policy "blank_space_profiles_update_own"
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

grant usage on schema public to anon, authenticated;
grant select on public.profiles to anon, authenticated;
grant update on public.profiles to authenticated;

create index if not exists user_banners_user_id_idx on public.user_banners(user_id);
create index if not exists profiles_points_username_idx on public.profiles(points desc, lower(username));
create index if not exists profiles_username_lower_idx on public.profiles(lower(username));

select pg_notify('pgrst','reload schema');

select
  'OK - v130 banners, true member, and leaderboard fields installed' as status,
  (select count(*) from public.user_banners) as banner_rows,
  (select count(*) from public.profiles where true_member is true) as true_members;

-- Blank Space v136: banners + Pause Website + Message Responses
-- Paste this into Supabase SQL Editor and click Run.
--
-- Fixes/adds:
-- - Strong banner loading, buying, and equipping RPCs.
-- - Owner-only Pause Website/Unpause Website, with exception ranks.
-- - Owner Message system with optional user responses.
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
on public.user_banners for select to authenticated using (true);

create policy "blank_space_user_banners_insert_own"
on public.user_banners for insert to authenticated with check (user_id = auth.uid());

create policy "blank_space_user_banners_update_own"
on public.user_banners for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "blank_space_user_banners_delete_own"
on public.user_banners for delete to authenticated using (user_id = auth.uid());

grant select, insert, update, delete on public.user_banners to authenticated;

create or replace function public.blank_space_is_owner()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and (lower(trim(coalesce(rank,''))) = 'owner' or lower(trim(coalesce(username,''))) = 'owner')
  );
$$;

grant execute on function public.blank_space_is_owner() to authenticated;

create or replace function public.get_my_banners_v136()
returns table(
  banner_id text,
  banner_name text,
  banner_gradient text,
  rarity text,
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
    coalesce(nullif(b.rarity,''), 'common') as rarity,
    coalesce(b.unlocked_at, b.acquired_at, now()) as unlocked_at,
    (p.equipped_banner_id = b.banner_id) as equipped
  from public.user_banners b
  join public.profiles p on p.id = b.user_id
  where b.user_id = auth.uid()
  order by coalesce(b.unlocked_at, b.acquired_at, now()) desc, coalesce(b.banner_name,b.name,b.banner_id) asc;
$$;

grant execute on function public.get_my_banners_v136() to authenticated;

create or replace function public.buy_banner_pack_v136(p_pack_id text)
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
begin
  if v_uid is null then raise exception 'Sign in first.'; end if;

  v_cost := case v_pack when 'starter' then 10 when 'neon' then 25 when 'royal' then 40 else null end;
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

  return jsonb_build_object('ok', true, 'pack_id', v_pack, 'cost', v_cost);
end;
$$;

grant execute on function public.buy_banner_pack_v136(text) to authenticated;

create or replace function public.equip_banner_v136(p_banner_id text)
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
  where user_id = v_uid and banner_id = trim(coalesce(p_banner_id,''))
  limit 1;

  if b.banner_id is null then raise exception 'You do not own this banner.'; end if;

  update public.profiles
  set equipped_banner_id = b.banner_id,
      equipped_banner_name = b.banner_name,
      equipped_banner_gradient = b.banner_gradient,
      updated_at = now()
  where id = v_uid;

  return jsonb_build_object('ok', true, 'banner_id', b.banner_id, 'banner_name', b.banner_name);
end;
$$;

grant execute on function public.equip_banner_v136(text) to authenticated;

create or replace function public.get_my_banners()
returns table(banner_id text, banner_name text, banner_gradient text, rarity text, unlocked_at timestamptz, equipped boolean)
language sql security definer set search_path = public as $$
  select * from public.get_my_banners_v136();
$$;
grant execute on function public.get_my_banners() to authenticated;

create or replace function public.buy_banner_pack(p_pack_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return public.buy_banner_pack_v136(p_pack_id);
end; $$;
grant execute on function public.buy_banner_pack(text) to authenticated;

create or replace function public.equip_banner(p_banner_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return public.equip_banner_v136(p_banner_id);
end; $$;
grant execute on function public.equip_banner(text) to authenticated;

-- Pause Website
create table if not exists public.site_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now(),
  updated_by uuid
);

alter table public.site_settings enable row level security;

drop policy if exists "blank_space_site_settings_select" on public.site_settings;
create policy "blank_space_site_settings_select" on public.site_settings for select to anon, authenticated using (true);
grant select on public.site_settings to anon, authenticated;

insert into public.site_settings(key,value)
values ('website_pause', '{"paused":false,"except_ranks":[]}'::jsonb)
on conflict (key) do nothing;

create or replace function public.set_website_pause_v136(p_paused boolean, p_except_ranks text[] default array[]::text[])
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_allowed text[];
  v_clean text[];
begin
  if not public.blank_space_is_owner() then raise exception 'Owner only.'; end if;

  v_allowed := array['testers','managers','admins'];
  select coalesce(array_agg(x), array[]::text[]) into v_clean
  from unnest(coalesce(p_except_ranks, array[]::text[])) as x
  where x = any(v_allowed);

  insert into public.site_settings(key,value,updated_at,updated_by)
  values ('website_pause', jsonb_build_object('paused', coalesce(p_paused,false), 'except_ranks', v_clean), now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = auth.uid();

  return (select value from public.site_settings where key='website_pause');
end;
$$;
grant execute on function public.set_website_pause_v136(boolean,text[]) to authenticated;

create or replace function public.get_website_pause_status_v136()
returns jsonb
language sql security definer set search_path = public
as $$
  select coalesce((select value from public.site_settings where key='website_pause'), '{"paused":false,"except_ranks":[]}'::jsonb);
$$;
grant execute on function public.get_website_pause_status_v136() to anon, authenticated;

create or replace function public.set_website_pause(p_paused boolean, p_except_ranks text[] default array[]::text[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return public.set_website_pause_v136(p_paused, p_except_ranks);
end; $$;
grant execute on function public.set_website_pause(boolean,text[]) to authenticated;

create or replace function public.get_website_pause_status()
returns jsonb language sql security definer set search_path = public as $$
  select public.get_website_pause_status_v136();
$$;
grant execute on function public.get_website_pause_status() to anon, authenticated;

-- Message + Responses
create table if not exists public.owner_messages_v136 (
  id uuid primary key default gen_random_uuid(),
  message_text text not null,
  requires_response boolean not null default false,
  active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.owner_message_responses_v136 (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.owner_messages_v136(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  response_text text not null,
  created_at timestamptz not null default now(),
  unique(message_id, user_id)
);

alter table public.owner_messages_v136 enable row level security;
alter table public.owner_message_responses_v136 enable row level security;

drop policy if exists "blank_space_owner_messages_select" on public.owner_messages_v136;
drop policy if exists "blank_space_owner_responses_select_own" on public.owner_message_responses_v136;
drop policy if exists "blank_space_owner_responses_insert_own" on public.owner_message_responses_v136;

create policy "blank_space_owner_messages_select"
on public.owner_messages_v136 for select to authenticated using (true);

create policy "blank_space_owner_responses_select_own"
on public.owner_message_responses_v136 for select to authenticated
using (user_id = auth.uid() or public.blank_space_is_owner());

create policy "blank_space_owner_responses_insert_own"
on public.owner_message_responses_v136 for insert to authenticated
with check (user_id = auth.uid());

grant select on public.owner_messages_v136 to authenticated;
grant select, insert on public.owner_message_responses_v136 to authenticated;

create or replace function public.send_owner_message_v136(p_message text, p_requires_response boolean default false)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.blank_space_is_owner() then raise exception 'Owner only.'; end if;
  if trim(coalesce(p_message,'')) = '' then raise exception 'Message cannot be blank.'; end if;

  update public.owner_messages_v136 set active=false where active=true;

  insert into public.owner_messages_v136(message_text, requires_response, active, created_by)
  values (trim(p_message), coalesce(p_requires_response,false), true, auth.uid())
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;
grant execute on function public.send_owner_message_v136(text,boolean) to authenticated;

create or replace function public.get_active_owner_messages_v136()
returns table(id uuid, message_text text, requires_response boolean, created_at timestamptz)
language sql security definer set search_path = public
as $$
  select id, message_text, requires_response, created_at
  from public.owner_messages_v136
  where active = true
  order by created_at desc
  limit 1;
$$;
grant execute on function public.get_active_owner_messages_v136() to authenticated;

create or replace function public.submit_message_response_v136(p_message_id uuid, p_response text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Sign in first.'; end if;
  if trim(coalesce(p_response,'')) = '' then raise exception 'Response cannot be blank.'; end if;

  insert into public.owner_message_responses_v136(message_id, user_id, response_text)
  values (p_message_id, auth.uid(), trim(p_response))
  on conflict (message_id, user_id) do update set response_text=excluded.response_text, created_at=now();

  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.submit_message_response_v136(uuid,text) to authenticated;

create or replace function public.get_message_responses_v136()
returns table(
  message_id uuid,
  message_text text,
  username text,
  response_text text,
  created_at timestamptz
)
language sql security definer set search_path = public
as $$
  select m.id, m.message_text, p.username, r.response_text, r.created_at
  from public.owner_message_responses_v136 r
  join public.owner_messages_v136 m on m.id = r.message_id
  left join public.profiles p on p.id = r.user_id
  where public.blank_space_is_owner()
  order by r.created_at desc;
$$;
grant execute on function public.get_message_responses_v136() to authenticated;

create or replace function public.send_owner_message(p_message text, p_requires_response boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
begin return public.send_owner_message_v136(p_message, p_requires_response); end; $$;
grant execute on function public.send_owner_message(text,boolean) to authenticated;

create or replace function public.get_active_owner_messages()
returns table(id uuid, message_text text, requires_response boolean, created_at timestamptz)
language sql security definer set search_path = public as $$
  select * from public.get_active_owner_messages_v136();
$$;
grant execute on function public.get_active_owner_messages() to authenticated;

create or replace function public.submit_message_response(p_message_id uuid, p_response text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin return public.submit_message_response_v136(p_message_id, p_response); end; $$;
grant execute on function public.submit_message_response(uuid,text) to authenticated;

create or replace function public.get_message_responses()
returns table(message_id uuid, message_text text, username text, response_text text, created_at timestamptz)
language sql security definer set search_path = public as $$
  select * from public.get_message_responses_v136();
$$;
grant execute on function public.get_message_responses() to authenticated;

-- Leaderboard includes banner fields.
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
language sql security definer set search_path = public
as $$
  select
    p.id, p.username, p.display_name, p.avatar_url,
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

create policy "blank_space_profiles_select_public" on public.profiles for select to anon, authenticated using (true);
create policy "blank_space_profiles_update_own" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

grant usage on schema public to anon, authenticated;
grant select on public.profiles to anon, authenticated;
grant update on public.profiles to authenticated;

create index if not exists user_banners_user_id_idx on public.user_banners(user_id);
create index if not exists profiles_points_username_idx on public.profiles(points desc, lower(username));
create index if not exists owner_message_responses_message_idx on public.owner_message_responses_v136(message_id, created_at desc);

select pg_notify('pgrst','reload schema');

select
  'OK - v136 installed' as status,
  (select count(*) from public.user_banners) as banner_rows,
  (select value from public.site_settings where key='website_pause') as pause_status;

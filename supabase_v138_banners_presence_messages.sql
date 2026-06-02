-- Blank Space v138: presence indicators, rank/banner leaderboard, and unified Message panel backend
-- Run this after v136 fixed SQL. Safe to run more than once.

alter table public.profiles add column if not exists last_seen_at timestamptz;
alter table public.profiles add column if not exists equipped_banner_id text;
alter table public.profiles add column if not exists equipped_banner_name text;
alter table public.profiles add column if not exists equipped_banner_gradient text;
alter table public.profiles add column if not exists true_member boolean default false;
alter table public.profiles add column if not exists rank text default 'member';

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

create or replace function public.touch_presence_v138()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Sign in first.'; end if;
  update public.profiles set last_seen_at = now(), updated_at = now() where id = auth.uid();
  return jsonb_build_object('ok', true, 'last_seen_at', now());
end;
$$;
grant execute on function public.touch_presence_v138() to authenticated;

create or replace function public.touch_presence()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.touch_presence_v138();
end;
$$;
grant execute on function public.touch_presence() to authenticated;

drop function if exists public.get_public_leaderboard_v138(integer);
create function public.get_public_leaderboard_v138(max_rows integer default 10000)
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
grant execute on function public.get_public_leaderboard_v138(integer) to anon, authenticated;

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
  select * from public.get_public_leaderboard_v138(max_rows);
$$;
grant execute on function public.get_public_leaderboard(integer) to anon, authenticated;

create or replace function public.get_my_banners_v138()
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
grant execute on function public.get_my_banners_v138() to authenticated;

create or replace function public.equip_banner_v138(p_banner_id text)
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
grant execute on function public.equip_banner_v138(text) to authenticated;

create or replace function public.equip_banner(p_banner_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.equip_banner_v138(p_banner_id);
end;
$$;
grant execute on function public.equip_banner(text) to authenticated;

drop function if exists public.send_owner_message_v138(text, boolean, boolean, text, integer);
create function public.send_owner_message_v138(
  p_message text,
  p_requires_response boolean default false,
  p_send_to_everyone boolean default false,
  p_target_username text default null,
  p_minutes integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
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

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'send_to_everyone', coalesce(p_send_to_everyone,false),
    'target_username', p_target_username,
    'minutes', p_minutes,
    'owner_excluded_for_response', coalesce(p_requires_response,false) and coalesce(p_send_to_everyone,false)
  );
end;
$$;
grant execute on function public.send_owner_message_v138(text,boolean,boolean,text,integer) to authenticated;

drop function if exists public.get_message_responses_v138();
create function public.get_message_responses_v138()
returns table(
  message_id uuid,
  message_text text,
  username text,
  response_text text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select m.id, m.message_text, p.username, r.response_text, r.created_at
  from public.owner_message_responses_v136 r
  join public.owner_messages_v136 m on m.id = r.message_id
  left join public.profiles p on p.id = r.user_id
  where public.blank_space_is_owner()
  order by r.created_at desc;
$$;
grant execute on function public.get_message_responses_v138() to authenticated;

select pg_notify('pgrst','reload schema');
select 'OK - v138 installed' as status;

-- Blank Space v118 banner session/backend fix
-- Paste into Supabase SQL Editor and Run.
--
-- This adds v118 banner RPC names and keeps the v117 banner functions available.
-- The "signed in but banners says sign in" issue is mostly frontend session detection,
-- so the matching Blank Space v118.zip is also required.

alter table public.profiles add column if not exists points integer default 0;
alter table public.profiles add column if not exists equipped_banner_id text;
alter table public.profiles add column if not exists equipped_banner_name text;
alter table public.profiles add column if not exists equipped_banner_gradient text;

create table if not exists public.user_banners (
  user_id uuid not null references public.profiles(id) on delete cascade,
  banner_id text not null,
  name text not null,
  rarity text not null default 'common',
  gradient text not null,
  acquired_at timestamptz not null default now(),
  primary key(user_id, banner_id)
);

drop function if exists public.get_my_banners_v118();

create function public.get_my_banners_v118()
returns table(
  banner_id text,
  name text,
  rarity text,
  gradient text,
  acquired_at timestamptz,
  equipped boolean
)
language sql
security definer
set search_path = public
as $$
  select
    b.banner_id,
    b.name,
    b.rarity,
    b.gradient,
    b.acquired_at,
    (p.equipped_banner_id = b.banner_id) as equipped
  from public.user_banners b
  join public.profiles p on p.id = b.user_id
  where b.user_id = auth.uid()
  order by b.acquired_at desc, b.name asc;
$$;

grant execute on function public.get_my_banners_v118() to authenticated;

drop function if exists public.buy_banner_pack_v118(text, integer, text, text, text, text);

create function public.buy_banner_pack_v118(
  p_pack_id text,
  p_price integer,
  p_banner_id text,
  p_name text,
  p_rarity text,
  p_gradient text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_points integer := 0;
  v_price integer := greatest(0, coalesce(p_price,0));
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;

  select coalesce(points,0)
  into v_points
  from public.profiles
  where id = auth.uid()
  for update;

  if v_points < v_price then
    raise exception 'Not enough points.';
  end if;

  perform set_config('blank_space.allow_points_update','1',true);

  update public.profiles
  set points = coalesce(points,0) - v_price
  where id = auth.uid();

  insert into public.user_banners(user_id, banner_id, name, rarity, gradient, acquired_at)
  values(
    auth.uid(),
    left(coalesce(nullif(trim(p_banner_id),''),'banner'), 120),
    left(coalesce(nullif(trim(p_name),''),'Banner'), 120),
    left(coalesce(nullif(trim(p_rarity),''),'common'), 40),
    left(coalesce(nullif(trim(p_gradient),''),'linear-gradient(135deg,#111827,#22c55e)'), 500),
    now()
  )
  on conflict(user_id, banner_id) do update set
    name = excluded.name,
    rarity = excluded.rarity,
    gradient = excluded.gradient,
    acquired_at = now();

  return jsonb_build_object('ok', true, 'banner_id', p_banner_id, 'name', p_name);
end;
$$;

grant execute on function public.buy_banner_pack_v118(text, integer, text, text, text, text) to authenticated;

drop function if exists public.equip_banner_v118(text);

create function public.equip_banner_v118(p_banner_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.user_banners%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;

  select *
  into b
  from public.user_banners
  where user_id = auth.uid()
    and banner_id = p_banner_id
  limit 1;

  if b.user_id is null then
    raise exception 'You do not own this banner.';
  end if;

  update public.profiles
  set equipped_banner_id = b.banner_id,
      equipped_banner_name = b.name,
      equipped_banner_gradient = b.gradient
  where id = auth.uid();

  return jsonb_build_object('ok', true, 'banner_id', b.banner_id, 'name', b.name);
end;
$$;

grant execute on function public.equip_banner_v118(text) to authenticated;

drop function if exists public.blank_space_v118_banner_healthcheck();

create function public.blank_space_v118_banner_healthcheck()
returns table(check_name text, result text)
language sql
security definer
set search_path = public
as $$
  select 'user_banners_table', case when to_regclass('public.user_banners') is not null then 'installed' else 'missing' end
  union all select 'get_my_banners_v118', case when to_regprocedure('public.get_my_banners_v118()') is not null then 'installed' else 'missing' end
  union all select 'buy_banner_pack_v118', case when to_regprocedure('public.buy_banner_pack_v118(text, integer, text, text, text, text)') is not null then 'installed' else 'missing' end
  union all select 'equip_banner_v118', case when to_regprocedure('public.equip_banner_v118(text)') is not null then 'installed' else 'missing' end
  union all select 'status', 'OK - Blank Space v118 banner session fix installed';
$$;

grant execute on function public.blank_space_v118_banner_healthcheck() to anon, authenticated;

select pg_notify('pgrst','reload schema');

select * from public.blank_space_v118_banner_healthcheck();

-- Done.

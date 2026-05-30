-- Blank Space v117 repair update
-- Paste the whole file into Supabase SQL Editor and click Run.
--
-- Fixes:
-- - Banner collection loading with get_my_banners_v117()
-- - Banner buying/equipping with v117 RPCs and v115 aliases
-- - Achievement backend functions and backfill
-- - Slope achievement targets and score RPCs

-- ============================================================
-- Required columns and tables
-- ============================================================

alter table public.profiles add column if not exists points integer default 0;
alter table public.profiles add column if not exists rank text default 'member';
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists equipped_icon text;
alter table public.profiles add column if not exists true_member boolean not null default false;
alter table public.profiles add column if not exists last_seen_at timestamptz;
alter table public.profiles add column if not exists active_device_id text;
alter table public.profiles add column if not exists friend_requests_enabled boolean not null default true;
alter table public.profiles add column if not exists equipped_banner_id text;
alter table public.profiles add column if not exists equipped_banner_name text;
alter table public.profiles add column if not exists equipped_banner_gradient text;
alter table public.profiles add column if not exists login_email text;

update public.profiles set points = 0 where points is null;
update public.profiles set rank = 'member' where rank is null or trim(rank) = '';

create table if not exists public.user_banners (
  user_id uuid not null references public.profiles(id) on delete cascade,
  banner_id text not null,
  name text not null,
  rarity text not null default 'common',
  gradient text not null,
  acquired_at timestamptz not null default now(),
  primary key(user_id, banner_id)
);

create table if not exists public.game_stats (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game_title text not null,
  play_count integer default 0,
  play_seconds integer default 0,
  first_played_at timestamptz default now(),
  last_played_at timestamptz default now(),
  best_score integer default 0,
  goals integer default 0,
  wins integer default 0,
  fish_caught integer default 0,
  money_earned integer default 0,
  checks integer default 0,
  checkmates integer default 0,
  merges integer default 0,
  best_level integer default 0,
  hits integer default 0,
  snake_mode text
);

alter table public.game_stats add column if not exists play_count integer default 0;
alter table public.game_stats add column if not exists play_seconds integer default 0;
alter table public.game_stats add column if not exists first_played_at timestamptz default now();
alter table public.game_stats add column if not exists last_played_at timestamptz default now();
alter table public.game_stats add column if not exists best_score integer default 0;
alter table public.game_stats add column if not exists goals integer default 0;
alter table public.game_stats add column if not exists wins integer default 0;
alter table public.game_stats add column if not exists fish_caught integer default 0;
alter table public.game_stats add column if not exists money_earned integer default 0;
alter table public.game_stats add column if not exists checks integer default 0;
alter table public.game_stats add column if not exists checkmates integer default 0;
alter table public.game_stats add column if not exists merges integer default 0;
alter table public.game_stats add column if not exists best_level integer default 0;
alter table public.game_stats add column if not exists hits integer default 0;
alter table public.game_stats add column if not exists snake_mode text;

do $$
begin
  if exists (
    select 1 from public.game_stats
    group by user_id, game_title
    having count(*) > 1
  ) then
    create temp table tmp_v117_game_stats on commit drop as
    select
      user_id,
      game_title,
      sum(coalesce(play_count,0))::integer play_count,
      sum(coalesce(play_seconds,0))::integer play_seconds,
      min(coalesce(first_played_at,now())) first_played_at,
      max(coalesce(last_played_at,now())) last_played_at,
      max(coalesce(best_score,0))::integer best_score,
      max(coalesce(goals,0))::integer goals,
      max(coalesce(wins,0))::integer wins,
      max(coalesce(fish_caught,0))::integer fish_caught,
      max(coalesce(money_earned,0))::integer money_earned,
      max(coalesce(checks,0))::integer checks,
      max(coalesce(checkmates,0))::integer checkmates,
      max(coalesce(merges,0))::integer merges,
      max(coalesce(best_level,0))::integer best_level,
      max(coalesce(hits,0))::integer hits,
      max(snake_mode) snake_mode
    from public.game_stats
    group by user_id, game_title;

    delete from public.game_stats;

    insert into public.game_stats(user_id,game_title,play_count,play_seconds,first_played_at,last_played_at,best_score,goals,wins,fish_caught,money_earned,checks,checkmates,merges,best_level,hits,snake_mode)
    select user_id,game_title,play_count,play_seconds,first_played_at,last_played_at,best_score,goals,wins,fish_caught,money_earned,checks,checkmates,merges,best_level,hits,snake_mode
    from tmp_v117_game_stats;
  end if;
end $$;

create unique index if not exists game_stats_user_game_unique on public.game_stats(user_id, game_title);

create table if not exists public.user_achievements (
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_id text not null,
  title text default 'Achievement',
  description text default '',
  icon text default '🏆',
  game_title text,
  reward_points integer default 0,
  earned_at timestamptz default now()
);

alter table public.user_achievements add column if not exists title text default 'Achievement';
alter table public.user_achievements add column if not exists description text default '';
alter table public.user_achievements add column if not exists icon text default '🏆';
alter table public.user_achievements add column if not exists game_title text;
alter table public.user_achievements add column if not exists reward_points integer default 0;
alter table public.user_achievements add column if not exists earned_at timestamptz default now();

do $$
begin
  if exists (
    select 1 from public.user_achievements
    group by user_id, achievement_id
    having count(*) > 1
  ) then
    create temp table tmp_v117_ach on commit drop as
    select distinct on(user_id, achievement_id)
      user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at
    from public.user_achievements
    order by user_id, achievement_id, earned_at asc;

    delete from public.user_achievements;

    insert into public.user_achievements(user_id,achievement_id,title,description,icon,game_title,reward_points,earned_at)
    select user_id,achievement_id,title,description,icon,game_title,reward_points,earned_at
    from tmp_v117_ach;
  end if;
end $$;

create unique index if not exists user_achievements_user_achievement_unique on public.user_achievements(user_id, achievement_id);

create table if not exists public.achievement_catalog (
  achievement_id text,
  title text,
  description text,
  icon text,
  game_title text,
  stat text,
  target integer,
  reward_points integer default 0,
  difficulty text default 'medium'
);

alter table public.achievement_catalog add column if not exists achievement_id text;
alter table public.achievement_catalog add column if not exists title text;
alter table public.achievement_catalog add column if not exists description text;
alter table public.achievement_catalog add column if not exists icon text;
alter table public.achievement_catalog add column if not exists game_title text;
alter table public.achievement_catalog add column if not exists stat text;
alter table public.achievement_catalog add column if not exists target integer;
alter table public.achievement_catalog add column if not exists reward_points integer default 0;
alter table public.achievement_catalog add column if not exists difficulty text default 'medium';

create unique index if not exists achievement_catalog_achievement_unique on public.achievement_catalog(achievement_id);

create table if not exists public.aswc_goal_signal_pairs (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  pending_signals integer not null default 0,
  updated_at timestamptz not null default now()
);

create or replace function public.is_blank_space_owner_or_admin_v117()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and (
        lower(trim(coalesce(p.rank,'member'))) in ('owner','admin')
        or lower(trim(coalesce(p.username,''))) in ('owner','admin')
      )
  );
$$;

grant execute on function public.is_blank_space_owner_or_admin_v117() to anon, authenticated;

-- ============================================================
-- Banner collection RPCs
-- ============================================================

drop function if exists public.get_my_banners_v117();

create function public.get_my_banners_v117()
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

grant execute on function public.get_my_banners_v117() to authenticated;

drop function if exists public.buy_banner_pack_v117(text, integer, text, text, text, text);

create function public.buy_banner_pack_v117(
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

grant execute on function public.buy_banner_pack_v117(text, integer, text, text, text, text) to authenticated;

drop function if exists public.equip_banner_v117(text);

create function public.equip_banner_v117(p_banner_id text)
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

grant execute on function public.equip_banner_v117(text) to authenticated;

-- Keep old website names working too.
drop function if exists public.buy_banner_pack_v115(text, integer, text, text, text, text);
create function public.buy_banner_pack_v115(
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
begin
  return public.buy_banner_pack_v117(p_pack_id, p_price, p_banner_id, p_name, p_rarity, p_gradient);
end;
$$;
grant execute on function public.buy_banner_pack_v115(text, integer, text, text, text, text) to authenticated;

drop function if exists public.equip_banner_v115(text);
create function public.equip_banner_v115(p_banner_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.equip_banner_v117(p_banner_id);
end;
$$;
grant execute on function public.equip_banner_v115(text) to authenticated;

-- ============================================================
-- Achievements
-- ============================================================

-- Make Slope easier and canonical.
with slope_rows as (
  select achievement_id, row_number() over(order by coalesce(target,999999), achievement_id) rn
  from public.achievement_catalog
  where achievement_id like 'slope_%' or lower(coalesce(game_title,'')) = 'slope'
),
targets as (
  select * from (values
    (1,5),(2,10),(3,15),(4,20),(5,25),(6,30),(7,40),(8,50),
    (9,60),(10,75),(11,90),(12,110),(13,130),(14,150),(15,175),(16,200)
  ) as t(rn,target)
)
update public.achievement_catalog c
set game_title = 'Slope',
    stat = 'best_score',
    target = coalesce(t.target, c.target)
from slope_rows s
left join targets t on t.rn = s.rn
where c.achievement_id = s.achievement_id;

-- Ensure there are at least basic Slope rows if a prior catalog was incomplete.
insert into public.achievement_catalog(achievement_id,title,description,icon,game_title,stat,target,reward_points,difficulty)
values
('slope_v117_5','Get 5 points in Slope','Get 5 points in one Slope round','🟢','Slope','best_score',5,2,'easy'),
('slope_v117_10','Get 10 points in Slope','Get 10 points in one Slope round','🟢','Slope','best_score',10,2,'easy'),
('slope_v117_15','Get 15 points in Slope','Get 15 points in one Slope round','🟢','Slope','best_score',15,2,'easy'),
('slope_v117_20','Get 20 points in Slope','Get 20 points in one Slope round','🟢','Slope','best_score',20,2,'easy'),
('slope_v117_30','Get 30 points in Slope','Get 30 points in one Slope round','🟢','Slope','best_score',30,3,'medium'),
('slope_v117_50','Get 50 points in Slope','Get 50 points in one Slope round','🟢','Slope','best_score',50,5,'medium'),
('slope_v117_75','Get 75 points in Slope','Get 75 points in one Slope round','🟢','Slope','best_score',75,5,'hard'),
('slope_v117_100','Get 100 points in Slope','Get 100 points in one Slope round','🟢','Slope','best_score',100,10,'hard')
on conflict(achievement_id) do update set
  title=excluded.title,
  description=excluded.description,
  icon=excluded.icon,
  game_title=excluded.game_title,
  stat=excluded.stat,
  target=excluded.target,
  reward_points=excluded.reward_points,
  difficulty=excluded.difficulty;

drop function if exists public.award_ready_achievements(uuid, text);

create function public.award_ready_achievements(
  p_user_id uuid,
  p_game_title text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth uuid := auth.uid();
  v_awards integer := 0;
  v_points integer := 0;
  v_game text := nullif(trim(coalesce(p_game_title,'')), '');
begin
  if p_user_id is null then
    return 0;
  end if;

  if v_auth is not null
     and p_user_id is distinct from v_auth
     and not public.is_blank_space_owner_or_admin_v117() then
    raise exception 'Not allowed to award another user.';
  end if;

  if lower(coalesce(v_game,'')) in ('slope','slope game') then v_game := 'Slope'; end if;
  if lower(coalesce(v_game,'')) in ('a small world cup','a-small-world-cup','small world cup') then v_game := 'A Small World Cup'; end if;

  with eligible as (
    select c.*
    from public.achievement_catalog c
    join public.game_stats gs
      on gs.user_id = p_user_id
     and gs.game_title = c.game_title
    left join public.user_achievements ua
      on ua.user_id = p_user_id
     and ua.achievement_id = c.achievement_id
    where ua.achievement_id is null
      and c.achievement_id is not null
      and c.game_title is not null
      and (v_game is null or c.game_title = v_game)
      and (
        case c.stat
          when 'play_count' then coalesce(gs.play_count,0)
          when 'play_seconds' then coalesce(gs.play_seconds,0)
          when 'best_score' then coalesce(gs.best_score,0)
          when 'goals' then coalesce(gs.goals,0)
          when 'wins' then coalesce(gs.wins,0)
          when 'fish_caught' then coalesce(gs.fish_caught,0)
          when 'money_earned' then coalesce(gs.money_earned,0)
          when 'checks' then coalesce(gs.checks,0)
          when 'checkmates' then coalesce(gs.checkmates,0)
          when 'merges' then coalesce(gs.merges,0)
          when 'best_level' then coalesce(gs.best_level,0)
          when 'hits' then coalesce(gs.hits,0)
          else 0
        end
      ) >= coalesce(c.target,999999999)
  ),
  inserted as (
    insert into public.user_achievements(
      user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at
    )
    select
      p_user_id,
      achievement_id,
      coalesce(nullif(title,''),'Achievement'),
      coalesce(description,''),
      coalesce(nullif(icon,''),'🏆'),
      game_title,
      greatest(0, coalesce(reward_points,0)),
      now()
    from eligible
    on conflict(user_id, achievement_id) do nothing
    returning reward_points
  )
  select count(*)::integer, coalesce(sum(reward_points),0)::integer
  into v_awards, v_points
  from inserted;

  if v_points > 0 then
    perform set_config('blank_space.allow_points_update','1',true);
    update public.profiles
    set points = coalesce(points,0) + v_points
    where id = p_user_id;
  end if;

  return coalesce(v_awards,0);
end;
$$;

grant execute on function public.award_ready_achievements(uuid, text) to authenticated;

drop function if exists public.record_game_progress(text, boolean, integer);

create function public.record_game_progress(
  p_game_title text,
  p_open_event boolean default false,
  p_seconds integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_game text := trim(coalesce(p_game_title,''));
  v_awards integer := 0;
begin
  if v_uid is null then raise exception 'Sign in first.'; end if;
  if v_game = '' then raise exception 'Game title is required.'; end if;
  if lower(v_game) in ('slope','slope game') then v_game := 'Slope'; end if;
  if lower(v_game) in ('a small world cup','a-small-world-cup','small world cup') then v_game := 'A Small World Cup'; end if;

  insert into public.game_stats(user_id, game_title, play_count, play_seconds, first_played_at, last_played_at)
  values(v_uid, v_game, case when coalesce(p_open_event,false) then 1 else 0 end, greatest(0,coalesce(p_seconds,0)), now(), now())
  on conflict(user_id, game_title) do update set
    play_count = coalesce(public.game_stats.play_count,0) + case when coalesce(p_open_event,false) then 1 else 0 end,
    play_seconds = coalesce(public.game_stats.play_seconds,0) + greatest(0,coalesce(p_seconds,0)),
    last_played_at = now();

  v_awards := public.award_ready_achievements(v_uid, v_game);

  return (
    select to_jsonb(gs) || jsonb_build_object('ok', true, 'new_awards', v_awards)
    from public.game_stats gs
    where gs.user_id = v_uid and gs.game_title = v_game
  );
end;
$$;

grant execute on function public.record_game_progress(text, boolean, integer) to authenticated;

drop function if exists public.record_game_metric(text, text, integer, text);

create function public.record_game_metric(
  p_game_title text,
  p_metric text,
  p_value integer default 1,
  p_mode text default 'max'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_game text := trim(coalesce(p_game_title,''));
  v_metric text := lower(trim(coalesce(p_metric,'')));
  v_mode text := lower(trim(coalesce(p_mode,'max')));
  v_value integer := greatest(0, coalesce(p_value,0));
  v_awards integer := 0;
  v_pending integer := 0;
  v_total integer := 0;
  v_add integer := 0;
begin
  if v_uid is null then raise exception 'Sign in first.'; end if;
  if v_game = '' then raise exception 'Game title is required.'; end if;

  if lower(v_game) in ('slope','slope game') then v_game := 'Slope'; end if;
  if lower(v_game) in ('a small world cup','a-small-world-cup','small world cup') then v_game := 'A Small World Cup'; end if;
  if v_metric = 'score' then v_metric := 'best_score'; end if;

  if v_metric not in ('play_count','play_seconds','best_score','goals','wins','fish_caught','money_earned','checks','checkmates','merges','best_level','hits') then
    raise exception 'Unknown game metric: %', v_metric;
  end if;

  insert into public.game_stats(user_id, game_title, first_played_at, last_played_at)
  values(v_uid, v_game, now(), now())
  on conflict(user_id, game_title) do nothing;

  if v_game = 'A Small World Cup' and v_metric = 'goals' and v_mode in ('add','delta_v93','add_goal_v93','goal_delta') then
    select pending_signals
    into v_pending
    from public.aswc_goal_signal_pairs
    where user_id = v_uid
    for update;

    v_pending := coalesce(v_pending,0);
    v_total := v_pending + greatest(v_value,1);
    v_add := floor(v_total::numeric / 2)::integer;
    v_pending := mod(v_total,2);

    insert into public.aswc_goal_signal_pairs(user_id,pending_signals,updated_at)
    values(v_uid,v_pending,now())
    on conflict(user_id) do update set pending_signals=excluded.pending_signals, updated_at=now();

    update public.game_stats
    set goals = coalesce(goals,0) + v_add,
        last_played_at = now()
    where user_id = v_uid and game_title = v_game;

  elsif v_game = 'A Small World Cup' and v_metric = 'wins' and v_mode in ('add','add_win_v93','win_delta') then
    update public.game_stats
    set wins = coalesce(wins,0) + 1,
        last_played_at = now()
    where user_id = v_uid and game_title = v_game;

  else
    execute format(
      'update public.game_stats set %I = case when $1 = ''replace'' then $2 when $1 = ''add'' then coalesce(%I,0)+greatest($2,1) else greatest(coalesce(%I,0),$2) end, last_played_at=now() where user_id=$3 and game_title=$4',
      v_metric, v_metric, v_metric
    )
    using v_mode, v_value, v_uid, v_game;
  end if;

  v_awards := public.award_ready_achievements(v_uid, v_game);

  return (
    select to_jsonb(gs) || jsonb_build_object('ok', true, 'new_awards', v_awards)
    from public.game_stats gs
    where gs.user_id = v_uid and gs.game_title = v_game
  );
end;
$$;

grant execute on function public.record_game_metric(text, text, integer, text) to authenticated;

drop function if exists public.record_slope_score(integer);
create function public.record_slope_score(p_score integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.record_game_metric('Slope','best_score',greatest(0,coalesce(p_score,0)),'max');
end;
$$;
grant execute on function public.record_slope_score(integer) to authenticated;

drop function if exists public.report_slope_score(integer);
create function public.report_slope_score(p_score integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.record_slope_score(p_score);
end;
$$;
grant execute on function public.report_slope_score(integer) to authenticated;

drop function if exists public.submit_slope_score(integer);
create function public.submit_slope_score(p_score integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.record_slope_score(p_score);
end;
$$;
grant execute on function public.submit_slope_score(integer) to authenticated;

drop function if exists public.backfill_all_achievements_v117();

create function public.backfill_all_achievements_v117()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_total integer := 0;
  v_added integer := 0;
begin
  for r in
    select distinct user_id, game_title
    from public.game_stats
  loop
    v_added := public.award_ready_achievements(r.user_id, r.game_title);
    v_total := v_total + coalesce(v_added,0);
  end loop;

  return jsonb_build_object('ok', true, 'achievements_added', v_total);
end;
$$;

revoke execute on function public.backfill_all_achievements_v117() from public, anon, authenticated;

select public.backfill_all_achievements_v117() as achievement_backfill_result;

drop function if exists public.blank_space_v117_healthcheck();

create function public.blank_space_v117_healthcheck()
returns table(check_name text, result text)
language sql
security definer
set search_path = public
as $$
  select 'banner_rows', count(*)::text from public.user_banners
  union all select 'banner_rpc', case when to_regprocedure('public.get_my_banners_v117()') is not null then 'installed' else 'missing' end
  union all select 'achievement_catalog_rows', count(*)::text from public.achievement_catalog
  union all select 'slope_catalog_rows', count(*)::text from public.achievement_catalog where game_title='Slope'
  union all select 'record_game_progress', case when to_regprocedure('public.record_game_progress(text, boolean, integer)') is not null then 'installed' else 'missing' end
  union all select 'record_game_metric', case when to_regprocedure('public.record_game_metric(text, text, integer, text)') is not null then 'installed' else 'missing' end
  union all select 'slope_score_rpc', case when to_regprocedure('public.record_slope_score(integer)') is not null then 'installed' else 'missing' end
  union all select 'status', 'OK - Blank Space v117 repair update installed';
$$;

grant execute on function public.blank_space_v117_healthcheck() to anon, authenticated;

select pg_notify('pgrst','reload schema');

select * from public.blank_space_v117_healthcheck();

-- Done.

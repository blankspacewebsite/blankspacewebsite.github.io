-- Blank Space v120: full Slope achievement fix
-- Paste this whole file into Supabase SQL Editor and click Run.
-- This fixes the backend side. The matching Blank Space v120.zip fixes the website/Slope score-sending side.

alter table public.profiles add column if not exists points integer default 0;
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists rank text default 'member';

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
  if exists (select 1 from public.game_stats group by user_id, game_title having count(*) > 1) then
    create temp table tmp_v120_game_stats on commit drop as
    select user_id, game_title,
      sum(coalesce(play_count,0))::integer play_count,
      sum(coalesce(play_seconds,0))::integer play_seconds,
      min(coalesce(first_played_at, now())) first_played_at,
      max(coalesce(last_played_at, now())) last_played_at,
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

    insert into public.game_stats(user_id, game_title, play_count, play_seconds, first_played_at, last_played_at, best_score, goals, wins, fish_caught, money_earned, checks, checkmates, merges, best_level, hits, snake_mode)
    select user_id, game_title, play_count, play_seconds, first_played_at, last_played_at, best_score, goals, wins, fish_caught, money_earned, checks, checkmates, merges, best_level, hits, snake_mode
    from tmp_v120_game_stats;
  end if;
end $$;

create unique index if not exists game_stats_user_game_unique on public.game_stats(user_id, game_title);

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

create unique index if not exists achievement_catalog_id_unique on public.achievement_catalog(achievement_id);

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
  if exists (select 1 from public.user_achievements group by user_id, achievement_id having count(*) > 1) then
    create temp table tmp_v120_user_ach on commit drop as
    select distinct on(user_id, achievement_id)
      user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at
    from public.user_achievements
    order by user_id, achievement_id, earned_at asc nulls last;

    delete from public.user_achievements;

    insert into public.user_achievements(user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at)
    select user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at
    from tmp_v120_user_ach;
  end if;
end $$;

create unique index if not exists user_achievements_user_achievement_unique on public.user_achievements(user_id, achievement_id);

delete from public.achievement_catalog
where lower(coalesce(game_title,'')) = 'slope'
   or lower(coalesce(achievement_id,'')) like 'slope%'
   or lower(coalesce(title,'')) like '%slope%';

insert into public.achievement_catalog(achievement_id,title,description,icon,game_title,stat,target,reward_points,difficulty)
values
('slope_score_5','Get 5 points in Slope','Get 5 points in one Slope round','🟢','Slope','best_score',5,2,'easy'),
('slope_score_10','Get 10 points in Slope','Get 10 points in one Slope round','🟢','Slope','best_score',10,2,'easy'),
('slope_score_15','Get 15 points in Slope','Get 15 points in one Slope round','🟢','Slope','best_score',15,2,'easy'),
('slope_score_20','Get 20 points in Slope','Get 20 points in one Slope round','🟢','Slope','best_score',20,2,'easy'),
('slope_score_30','Get 30 points in Slope','Get 30 points in one Slope round','🟢','Slope','best_score',30,3,'medium'),
('slope_score_40','Get 40 points in Slope','Get 40 points in one Slope round','🟢','Slope','best_score',40,3,'medium'),
('slope_score_50','Get 50 points in Slope','Get 50 points in one Slope round','🟢','Slope','best_score',50,5,'medium'),
('slope_score_60','Get 60 points in Slope','Get 60 points in one Slope round','🟢','Slope','best_score',60,5,'medium'),
('slope_score_75','Get 75 points in Slope','Get 75 points in one Slope round','🟢','Slope','best_score',75,5,'hard'),
('slope_score_90','Get 90 points in Slope','Get 90 points in one Slope round','🟢','Slope','best_score',90,8,'hard'),
('slope_score_110','Get 110 points in Slope','Get 110 points in one Slope round','🟢','Slope','best_score',110,10,'hard'),
('slope_score_130','Get 130 points in Slope','Get 130 points in one Slope round','🟢','Slope','best_score',130,10,'hard'),
('slope_score_150','Get 150 points in Slope','Get 150 points in one Slope round','🟢','Slope','best_score',150,15,'crazy'),
('slope_score_175','Get 175 points in Slope','Get 175 points in one Slope round','🟢','Slope','best_score',175,15,'crazy'),
('slope_score_200','Get 200 points in Slope','Get 200 points in one Slope round','🟢','Slope','best_score',200,20,'crazy');

drop function if exists public.award_slope_achievements_for_user(uuid);

create function public.award_slope_achievements_for_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_score integer := 0;
  v_awards integer := 0;
  v_points integer := 0;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'message', 'No user.');
  end if;

  select coalesce(max(best_score),0) into v_score
  from public.game_stats
  where user_id = p_user_id and lower(game_title) = 'slope';

  with eligible as (
    select c.*
    from public.achievement_catalog c
    left join public.user_achievements ua on ua.user_id = p_user_id and ua.achievement_id = c.achievement_id
    where ua.achievement_id is null
      and c.game_title = 'Slope'
      and c.stat = 'best_score'
      and v_score >= coalesce(c.target,999999999)
  ),
  inserted as (
    insert into public.user_achievements(user_id,achievement_id,title,description,icon,game_title,reward_points,earned_at)
    select p_user_id, achievement_id, title, description, icon, game_title, greatest(0,coalesce(reward_points,0)), now()
    from eligible
    on conflict(user_id, achievement_id) do nothing
    returning reward_points
  )
  select count(*)::integer, coalesce(sum(reward_points),0)::integer into v_awards, v_points
  from inserted;

  if v_points > 0 then
    perform set_config('blank_space.allow_points_update','1',true);
    update public.profiles set points = coalesce(points,0) + v_points where id = p_user_id;
  end if;

  return jsonb_build_object('ok', true, 'game_title', 'Slope', 'best_score', v_score, 'new_awards', v_awards, 'points_added', v_points);
end $$;

grant execute on function public.award_slope_achievements_for_user(uuid) to authenticated;

drop function if exists public.record_slope_score(integer);

create function public.record_slope_score(p_score integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_score integer := greatest(0,coalesce(p_score,0));
  v_awards jsonb;
begin
  if v_uid is null then raise exception 'Sign in first.'; end if;

  insert into public.game_stats(user_id, game_title, best_score, play_count, first_played_at, last_played_at)
  values(v_uid, 'Slope', v_score, 1, now(), now())
  on conflict(user_id, game_title) do update set
    best_score = greatest(coalesce(public.game_stats.best_score,0), excluded.best_score),
    play_count = coalesce(public.game_stats.play_count,0) + 1,
    last_played_at = now();

  v_awards := public.award_slope_achievements_for_user(v_uid);

  return (select to_jsonb(gs) || v_awards from public.game_stats gs where gs.user_id = v_uid and gs.game_title = 'Slope');
end $$;

grant execute on function public.record_slope_score(integer) to authenticated;

drop function if exists public.report_slope_score(integer);
create function public.report_slope_score(p_score integer)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return public.record_slope_score(p_score);
end $$;
grant execute on function public.report_slope_score(integer) to authenticated;

drop function if exists public.submit_slope_score(integer);
create function public.submit_slope_score(p_score integer)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return public.record_slope_score(p_score);
end $$;
grant execute on function public.submit_slope_score(integer) to authenticated;

drop function if exists public.record_game_metric(text, text, integer, text);

create function public.record_game_metric(p_game_title text, p_metric text, p_value integer default 1, p_mode text default 'max')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_game text := trim(coalesce(p_game_title,''));
  v_metric text := lower(trim(coalesce(p_metric,'')));
begin
  if v_uid is null then raise exception 'Sign in first.'; end if;
  if lower(v_game) in ('slope','slope game') then v_game := 'Slope'; end if;
  if v_metric in ('score','best','best-score','bestscore') then v_metric := 'best_score'; end if;

  if v_game = 'Slope' and v_metric = 'best_score' then
    return public.record_slope_score(p_value);
  end if;

  raise exception 'This v120 repair RPC only records Slope. Got game=% metric=%', v_game, v_metric;
end $$;

grant execute on function public.record_game_metric(text, text, integer, text) to authenticated;

do $$
declare r record;
begin
  for r in select distinct user_id from public.game_stats where lower(game_title)='slope' loop
    perform public.award_slope_achievements_for_user(r.user_id);
  end loop;
end $$;

drop function if exists public.admin_test_slope_score(text, integer);

create function public.admin_test_slope_score(p_username text, p_score integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first.'; end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and lower(trim(coalesce(p.rank,'member'))) in ('owner','admin')
  ) then
    raise exception 'Owner/Admin only.';
  end if;

  select id into v_target
  from public.profiles
  where lower(trim(username)) = lower(trim(coalesce(p_username,'')))
  order by created_at asc nulls last, id asc
  limit 1;

  if v_target is null then raise exception 'User not found.'; end if;

  insert into public.game_stats(user_id, game_title, best_score, play_count, first_played_at, last_played_at)
  values(v_target, 'Slope', greatest(0,coalesce(p_score,0)), 1, now(), now())
  on conflict(user_id, game_title) do update set
    best_score = greatest(coalesce(public.game_stats.best_score,0), excluded.best_score),
    play_count = coalesce(public.game_stats.play_count,0) + 1,
    last_played_at = now();

  return public.award_slope_achievements_for_user(v_target);
end $$;

grant execute on function public.admin_test_slope_score(text, integer) to authenticated;

drop function if exists public.blank_space_v120_slope_healthcheck();

create function public.blank_space_v120_slope_healthcheck()
returns table(check_name text, result text)
language sql
security definer
set search_path = public
as $$
  select 'slope_catalog_rows', count(*)::text from public.achievement_catalog where game_title='Slope' and stat='best_score'
  union all select 'record_slope_score', case when to_regprocedure('public.record_slope_score(integer)') is not null then 'installed' else 'missing' end
  union all select 'record_game_metric', case when to_regprocedure('public.record_game_metric(text, text, integer, text)') is not null then 'installed' else 'missing' end
  union all select 'existing_slope_stats', count(*)::text from public.game_stats where lower(game_title)='slope'
  union all select 'status', 'OK - v120 Slope achievements fixed';
$$;

grant execute on function public.blank_space_v120_slope_healthcheck() to anon, authenticated;

select pg_notify('pgrst','reload schema');

select * from public.blank_space_v120_slope_healthcheck();

-- Done.

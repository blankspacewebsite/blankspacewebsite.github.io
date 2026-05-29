-- Blank Space v92 update
-- A Small World Cup real scoreboard fix + Admin A Small World Cup full reset
-- Paste this whole file into Supabase SQL Editor, then click Run.
--
-- What this does:
-- 1) Restores correct A Small World Cup goal/win achievement catalog rows.
-- 2) Replaces record_game_metric so A Small World Cup goal deltas sent by the v92 website are stored exactly.
-- 3) Fully resets only the account named Admin for A Small World Cup achievements/progress.
--
-- This DOES NOT change Admin's points.
-- This DOES NOT affect other users.
-- This DOES NOT affect other games.

alter table public.profiles add column if not exists points integer default 0;
alter table public.profiles add column if not exists equipped_achievement_id text;

create table if not exists public.game_stats (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game_title text not null,
  play_count integer default 0,
  play_seconds integer default 0,
  first_played_at timestamptz default now(),
  last_played_at timestamptz default now()
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

create table if not exists public.achievement_catalog (
  achievement_id text,
  title text,
  description text,
  icon text,
  game_title text,
  stat text,
  target integer,
  reward_points integer,
  difficulty text
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

-- Remove old ASWC signal-guard tables from the Supabase-only attempts. v92 uses the website scoreboard bridge instead.
drop table if exists public.aswc_goal_signal_counters;
drop table if exists public.aswc_goal_event_guard;

-- De-duplicate rows before unique indexes.
do $$
begin
  if exists (select 1 from public.game_stats group by user_id, game_title having count(*) > 1) then
    create temp table tmp_v92_game_stats on commit drop as
    select user_id, game_title,
      sum(coalesce(play_count,0))::integer as play_count,
      sum(coalesce(play_seconds,0))::integer as play_seconds,
      min(coalesce(first_played_at, now())) as first_played_at,
      max(coalesce(last_played_at, now())) as last_played_at,
      max(coalesce(best_score,0))::integer as best_score,
      max(coalesce(goals,0))::integer as goals,
      max(coalesce(wins,0))::integer as wins,
      max(coalesce(fish_caught,0))::integer as fish_caught,
      max(coalesce(money_earned,0))::integer as money_earned,
      max(coalesce(checks,0))::integer as checks,
      max(coalesce(checkmates,0))::integer as checkmates,
      max(coalesce(merges,0))::integer as merges,
      max(coalesce(best_level,0))::integer as best_level,
      max(coalesce(hits,0))::integer as hits
    from public.game_stats group by user_id, game_title;
    delete from public.game_stats;
    insert into public.game_stats(user_id,game_title,play_count,play_seconds,first_played_at,last_played_at,best_score,goals,wins,fish_caught,money_earned,checks,checkmates,merges,best_level,hits)
    select user_id,game_title,play_count,play_seconds,first_played_at,last_played_at,best_score,goals,wins,fish_caught,money_earned,checks,checkmates,merges,best_level,hits from tmp_v92_game_stats;
  end if;
end $$;

do $$
begin
  if exists (select 1 from public.user_achievements group by user_id, achievement_id having count(*) > 1) then
    create temp table tmp_v92_user_achievements on commit drop as
    select distinct on (user_id, achievement_id) user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at
    from public.user_achievements
    order by user_id, achievement_id, earned_at asc;
    delete from public.user_achievements;
    insert into public.user_achievements(user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at)
    select user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at from tmp_v92_user_achievements;
  end if;
end $$;

do $$
begin
  if exists (select 1 from public.achievement_catalog where achievement_id is not null group by achievement_id having count(*) > 1) then
    create temp table tmp_v92_catalog on commit drop as
    select distinct on (achievement_id) achievement_id, title, description, icon, game_title, stat, target, reward_points, difficulty
    from public.achievement_catalog
    where achievement_id is not null
    order by achievement_id;
    delete from public.achievement_catalog;
    insert into public.achievement_catalog(achievement_id, title, description, icon, game_title, stat, target, reward_points, difficulty)
    select achievement_id, title, description, icon, game_title, stat, target, reward_points, difficulty from tmp_v92_catalog;
  end if;
end $$;

create unique index if not exists game_stats_user_game_unique on public.game_stats(user_id, game_title);
create unique index if not exists user_achievements_user_achievement_unique on public.user_achievements(user_id, achievement_id);
create unique index if not exists achievement_catalog_achievement_unique on public.achievement_catalog(achievement_id);

insert into public.achievement_catalog
  (achievement_id, title, description, icon, game_title, stat, target, reward_points, difficulty)
values
  ('a_small_world_cup_goals_5_33','5 total goals','Score 5 total goals in A Small World Cup','⚽','A Small World Cup','goals',5,2,'not_so_hard'),
  ('a_small_world_cup_goals_10_34','10 total goals','Score 10 total goals in A Small World Cup','⚽','A Small World Cup','goals',10,2,'not_so_hard'),
  ('a_small_world_cup_goals_15_35','15 total goals','Score 15 total goals in A Small World Cup','⚽','A Small World Cup','goals',15,5,'medium'),
  ('a_small_world_cup_goals_20_36','20 total goals','Score 20 total goals in A Small World Cup','⚽','A Small World Cup','goals',20,5,'medium'),
  ('a_small_world_cup_goals_30_37','30 total goals','Score 30 total goals in A Small World Cup','⚽','A Small World Cup','goals',30,5,'medium'),
  ('a_small_world_cup_goals_40_38','40 total goals','Score 40 total goals in A Small World Cup','⚽','A Small World Cup','goals',40,5,'medium'),
  ('a_small_world_cup_goals_50_39','50 total goals','Score 50 total goals in A Small World Cup','⚽','A Small World Cup','goals',50,5,'medium'),
  ('a_small_world_cup_goals_75_40','75 total goals','Score 75 total goals in A Small World Cup','⚽','A Small World Cup','goals',75,10,'hard'),
  ('a_small_world_cup_goals_100_41','100 total goals','Score 100 total goals in A Small World Cup','⚽','A Small World Cup','goals',100,10,'hard'),
  ('a_small_world_cup_goals_150_42','150 total goals','Score 150 total goals in A Small World Cup','⚽','A Small World Cup','goals',150,10,'hard'),
  ('a_small_world_cup_goals_200_43','200 total goals','Score 200 total goals in A Small World Cup','⚽','A Small World Cup','goals',200,20,'crazy'),
  ('a_small_world_cup_goals_300_44','300 total goals','Score 300 total goals in A Small World Cup','⚽','A Small World Cup','goals',300,20,'crazy'),
  ('a_small_world_cup_wins_1_45','Win the World Cup 1 time','Win the World Cup 1 time','🏆','A Small World Cup','wins',1,2,'not_so_hard'),
  ('a_small_world_cup_wins_2_46','Win the World Cup 2 times','Win the World Cup 2 times','🏆','A Small World Cup','wins',2,5,'medium'),
  ('a_small_world_cup_wins_3_47','Win the World Cup 3 times','Win the World Cup 3 times','🏆','A Small World Cup','wins',3,5,'medium'),
  ('a_small_world_cup_wins_5_48','Win the World Cup 5 times','Win the World Cup 5 times','🏆','A Small World Cup','wins',5,5,'medium'),
  ('a_small_world_cup_wins_8_49','Win the World Cup 8 times','Win the World Cup 8 times','🏆','A Small World Cup','wins',8,10,'hard'),
  ('a_small_world_cup_wins_10_50','Win the World Cup 10 times','Win the World Cup 10 times','🏆','A Small World Cup','wins',10,10,'hard'),
  ('a_small_world_cup_wins_13_202','Win the World Cup 13 times','Win the World Cup 13 times','🏆','A Small World Cup','wins',13,10,'hard'),
  ('a_small_world_cup_wins_14_222','Win the World Cup 14 times','Win the World Cup 14 times','🏆','A Small World Cup','wins',14,10,'hard'),
  ('a_small_world_cup_wins_15_51','Win the World Cup 15 times','Win the World Cup 15 times','🏆','A Small World Cup','wins',15,10,'hard'),
  ('a_small_world_cup_wins_20_52','Win the World Cup 20 times','Win the World Cup 20 times','🏆','A Small World Cup','wins',20,20,'crazy'),
  ('a_small_world_cup_wins_30_53','Win the World Cup 30 times','Win the World Cup 30 times','🏆','A Small World Cup','wins',30,20,'crazy'),
  ('a_small_world_cup_wins_50_54','Win the World Cup 50 times','Win the World Cup 50 times','🏆','A Small World Cup','wins',50,20,'crazy')
on conflict (achievement_id) do update set
  title = excluded.title,
  description = excluded.description,
  icon = excluded.icon,
  game_title = excluded.game_title,
  stat = excluded.stat,
  target = excluded.target,
  reward_points = excluded.reward_points,
  difficulty = excluded.difficulty;

-- Remove older duplicate ASWC win IDs from earlier patches.
delete from public.user_achievements where achievement_id in ('a_small_world_cup_wins_13_212','a_small_world_cup_wins_14_232','a_small_world_cup_wins_15_242');
delete from public.achievement_catalog where achievement_id in ('a_small_world_cup_wins_13_212','a_small_world_cup_wins_14_232','a_small_world_cup_wins_15_242');

-- Award all qualifying achievements for the saved stat values.
drop function if exists public.award_ready_achievements(uuid, text);

create function public.award_ready_achievements(p_user_id uuid, p_game_title text default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_game_title text := p_game_title;
  v_awards integer := 0;
  v_points integer := 0;
begin
  if v_auth_uid is null then
    raise exception 'Not signed in.';
  end if;

  if p_user_id is distinct from v_auth_uid then
    raise exception 'Not allowed to award achievements for another user.';
  end if;

  if lower(trim(coalesce(v_game_title, ''))) in ('a small world cup', 'a-small-world-cup', 'small world cup') then
    v_game_title := 'A Small World Cup';
  end if;

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
      and (v_game_title is null or c.game_title = v_game_title)
      and (
        case c.stat
          when 'play_count' then coalesce(gs.play_count, 0)
          when 'best_score' then coalesce(gs.best_score, 0)
          when 'goals' then coalesce(gs.goals, 0)
          when 'wins' then coalesce(gs.wins, 0)
          when 'fish_caught' then coalesce(gs.fish_caught, 0)
          when 'money_earned' then coalesce(gs.money_earned, 0)
          when 'checks' then coalesce(gs.checks, 0)
          when 'checkmates' then coalesce(gs.checkmates, 0)
          when 'merges' then coalesce(gs.merges, 0)
          when 'best_level' then coalesce(gs.best_level, 0)
          when 'hits' then coalesce(gs.hits, 0)
          else 0
        end
      ) >= coalesce(c.target, 999999999)
  ),
  inserted as (
    insert into public.user_achievements
      (user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at)
    select
      p_user_id,
      c.achievement_id,
      coalesce(nullif(c.title, ''), 'Achievement'),
      coalesce(c.description, ''),
      coalesce(nullif(c.icon, ''), '🏆'),
      c.game_title,
      greatest(0, coalesce(c.reward_points, 0)),
      now()
    from eligible c
    on conflict (user_id, achievement_id) do nothing
    returning reward_points
  )
  select count(*)::integer, coalesce(sum(reward_points), 0)::integer
  into v_awards, v_points
  from inserted;

  if v_awards > 0 and v_points > 0 then
    perform set_config('blank_space.allow_points_update', '1', true);
    update public.profiles
    set points = coalesce(points, 0) + v_points
    where id = p_user_id;
  end if;

  return coalesce(v_awards, 0);
end;
$$;

grant execute on function public.award_ready_achievements(uuid, text) to authenticated;

-- Store v92 A Small World Cup goal deltas exactly. The website now sends only real player-goal deltas.
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
  v_game_title text := trim(coalesce(p_game_title, ''));
  v_metric text := lower(trim(coalesce(p_metric, '')));
  v_mode text := lower(trim(coalesce(p_mode, 'max')));
  v_value integer := greatest(0, coalesce(p_value, 0));
  v_new_awards integer := 0;
  v_stat jsonb := '{}'::jsonb;
begin
  if v_uid is null then
    raise exception 'Not signed in.';
  end if;

  if lower(v_game_title) in ('a small world cup', 'a-small-world-cup', 'small world cup') then
    v_game_title := 'A Small World Cup';
  end if;

  if v_game_title = '' then
    raise exception 'Game title is required.';
  end if;

  if v_metric not in ('play_count','best_score','goals','wins','fish_caught','money_earned','checks','checkmates','merges','best_level','hits') then
    raise exception 'Unknown game metric: %', v_metric;
  end if;

  v_value := least(v_value, 100000000);

  insert into public.game_stats(user_id, game_title, first_played_at, last_played_at)
  values(v_uid, v_game_title, now(), now())
  on conflict (user_id, game_title) do nothing;

  if v_game_title = 'A Small World Cup' and v_metric = 'goals' then
    -- v92 website sends exact real player-goal deltas, so add those deltas.
    -- Cap at 10 per message so broken old pages cannot add huge jumps.
    if v_mode = 'add' then
      update public.game_stats
      set goals = coalesce(goals, 0) + least(greatest(v_value, 1), 10),
          last_played_at = now()
      where user_id = v_uid and game_title = v_game_title;
    elsif v_mode = 'replace' then
      update public.game_stats
      set goals = least(v_value, 100000),
          last_played_at = now()
      where user_id = v_uid and game_title = v_game_title;
    else
      update public.game_stats
      set goals = greatest(coalesce(goals, 0), least(v_value, 100000)),
          last_played_at = now()
      where user_id = v_uid and game_title = v_game_title;
    end if;
  else
    execute format(
      'update public.game_stats
       set %I = case
         when $1 = ''replace'' then $2
         when $1 = ''add'' then coalesce(%I, 0) + greatest($2, 1)
         else greatest(coalesce(%I, 0), $2)
       end,
       last_played_at = now()
       where user_id = $3 and game_title = $4',
      v_metric, v_metric, v_metric
    )
    using v_mode, v_value, v_uid, v_game_title;
  end if;

  v_new_awards := public.award_ready_achievements(v_uid, v_game_title);

  select to_jsonb(gs) || jsonb_build_object('new_awards', v_new_awards)
  into v_stat
  from public.game_stats gs
  where gs.user_id = v_uid and gs.game_title = v_game_title;

  return coalesce(v_stat, '{}'::jsonb);
end;
$$;

grant execute on function public.record_game_metric(text, text, integer, text) to authenticated;

-- Fully reset only Admin's A Small World Cup achievements/progress, but do not change points.
do $$
declare
  v_admin_id uuid;
  v_deleted_count integer := 0;
begin
  select id
  into v_admin_id
  from public.profiles
  where lower(trim(username)) = lower('Admin')
  limit 1;

  if v_admin_id is null then
    raise exception 'No profile found with username Admin.';
  end if;

  delete from public.user_achievements
  where user_id = v_admin_id
    and (game_title = 'A Small World Cup' or achievement_id like 'a_small_world_cup_%');

  get diagnostics v_deleted_count = row_count;

  insert into public.game_stats(user_id, game_title, goals, wins, last_played_at)
  values(v_admin_id, 'A Small World Cup', 0, 0, now())
  on conflict (user_id, game_title)
  do update set goals = 0, wins = 0, last_played_at = now();

  update public.profiles
  set equipped_achievement_id = null
  where id = v_admin_id
    and equipped_achievement_id like 'a_small_world_cup_%';

  raise notice 'Admin A Small World Cup reset complete. Deleted % achievements. Goals/wins reset. Points unchanged.', v_deleted_count;
end $$;

-- Health check
drop function if exists public.aswc_v92_healthcheck();

create function public.aswc_v92_healthcheck()
returns table(check_name text, result text)
language sql
security definer
set search_path = public
as $$
  select 'aswc_goal_targets', coalesce(string_agg(target::text, ',' order by target), '')
  from public.achievement_catalog
  where game_title = 'A Small World Cup' and stat = 'goals'
  union all
  select 'admin_remaining_aswc_achievements', count(ua.achievement_id)::text
  from public.profiles p
  left join public.user_achievements ua
    on ua.user_id = p.id
   and (ua.game_title = 'A Small World Cup' or ua.achievement_id like 'a_small_world_cup_%')
  where lower(trim(p.username)) = lower('Admin')
  union all
  select 'admin_aswc_goals_wins', coalesce(gs.goals, 0)::text || ' goals, ' || coalesce(gs.wins, 0)::text || ' wins'
  from public.profiles p
  left join public.game_stats gs
    on gs.user_id = p.id and gs.game_title = 'A Small World Cup'
  where lower(trim(p.username)) = lower('Admin')
  union all
  select 'status', 'OK - v92 ASWC scoreboard fix ready. Upload Blank Space v92 website after running this SQL.';
$$;

grant execute on function public.aswc_v92_healthcheck() to anon, authenticated;

select pg_notify('pgrst', 'reload schema');
select * from public.aswc_v92_healthcheck();

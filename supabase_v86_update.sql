-- Blank Space v86 achievement cleanup/fix
-- Safe update: fixes achievement unlock thresholds, makes achievements give points only, puts Admin back on the leaderboard,
-- and resets the Admin account's broken achievement progress so it can be tested cleanly.
-- Does not delete accounts, friends, chats, suggestions, trades, or purchased icon-pack icons.

-- Replace old ambiguous/progress functions with jsonb-returning functions.
drop function if exists public.record_game_metric(text, text, integer, text);
drop function if exists public.record_game_progress(text, boolean, integer);
drop function if exists public.award_achievement(text, text, text, text, text, integer);
drop function if exists public.get_public_leaderboard(integer);

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
  v_value integer := greatest(0, coalesce(p_value, 0));
  v_mode text := lower(trim(coalesce(p_mode, 'max')));
  v_stat jsonb;
begin
  if v_uid is null then raise exception 'Not signed in.'; end if;
  if char_length(v_game_title) < 1 then raise exception 'Game title is required.'; end if;

  insert into public.game_stats (user_id, game_title)
  values (v_uid, v_game_title)
  on conflict (user_id, game_title) do nothing;

  if v_metric = 'best_score' then
    update public.game_stats as gs set best_score = greatest(coalesce(gs.best_score, 0), v_value), last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'goals' then
    update public.game_stats as gs set goals = case when v_mode = 'max' then greatest(coalesce(gs.goals,0), v_value) else coalesce(gs.goals,0) + greatest(v_value,1) end, last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'wins' then
    update public.game_stats as gs set wins = case when v_mode = 'max' then greatest(coalesce(gs.wins,0), v_value) else coalesce(gs.wins,0) + greatest(v_value,1) end, last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'fish_caught' then
    update public.game_stats as gs set fish_caught = case when v_mode = 'max' then greatest(coalesce(gs.fish_caught,0), v_value) else coalesce(gs.fish_caught,0) + greatest(v_value,1) end, last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'money_earned' then
    update public.game_stats as gs set money_earned = greatest(coalesce(gs.money_earned, 0), v_value), last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'checks' then
    update public.game_stats as gs set checks = case when v_mode = 'max' then greatest(coalesce(gs.checks,0), v_value) else coalesce(gs.checks,0) + greatest(v_value,1) end, last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'checkmates' then
    update public.game_stats as gs set checkmates = case when v_mode = 'max' then greatest(coalesce(gs.checkmates,0), v_value) else coalesce(gs.checkmates,0) + greatest(v_value,1) end, last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'merges' then
    update public.game_stats as gs set merges = case when v_mode = 'max' then greatest(coalesce(gs.merges,0), v_value) else coalesce(gs.merges,0) + greatest(v_value,1) end, last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'best_level' then
    update public.game_stats as gs set best_level = greatest(coalesce(gs.best_level, 0), v_value), last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'hits' then
    update public.game_stats as gs set hits = case when v_mode = 'max' then greatest(coalesce(gs.hits,0), v_value) else coalesce(gs.hits,0) + greatest(v_value,1) end, last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  else
    raise exception 'Unknown game metric: %', v_metric;
  end if;

  select jsonb_build_object(
    'game_title', gs.game_title,
    'play_count', coalesce(gs.play_count,0),
    'play_seconds', coalesce(gs.play_seconds,0),
    'best_score', coalesce(gs.best_score,0),
    'goals', coalesce(gs.goals,0),
    'wins', coalesce(gs.wins,0),
    'fish_caught', coalesce(gs.fish_caught,0),
    'money_earned', coalesce(gs.money_earned,0),
    'checks', coalesce(gs.checks,0),
    'checkmates', coalesce(gs.checkmates,0),
    'merges', coalesce(gs.merges,0),
    'best_level', coalesce(gs.best_level,0),
    'hits', coalesce(gs.hits,0)
  ) into v_stat
  from public.game_stats as gs
  where gs.user_id = v_uid and gs.game_title = v_game_title;

  return coalesce(v_stat, '{}'::jsonb);
end;
$$;

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
  v_game_title text := trim(coalesce(p_game_title, ''));
  v_add_count integer := case when coalesce(p_open_event, false) then 1 else 0 end;
  v_add_seconds integer := greatest(0, coalesce(p_seconds, 0));
  v_stat jsonb;
begin
  if v_uid is null then raise exception 'Not signed in.'; end if;
  if char_length(v_game_title) < 1 then raise exception 'Game title is required.'; end if;

  insert into public.game_stats (user_id, game_title, play_count, play_seconds)
  values (v_uid, v_game_title, v_add_count, v_add_seconds)
  on conflict (user_id, game_title)
  do update set
    play_count = coalesce(public.game_stats.play_count, 0) + excluded.play_count,
    play_seconds = coalesce(public.game_stats.play_seconds, 0) + excluded.play_seconds,
    last_played_at = now();

  select jsonb_build_object(
    'game_title', gs.game_title,
    'play_count', coalesce(gs.play_count,0),
    'play_seconds', coalesce(gs.play_seconds,0),
    'best_score', coalesce(gs.best_score,0),
    'goals', coalesce(gs.goals,0),
    'wins', coalesce(gs.wins,0),
    'fish_caught', coalesce(gs.fish_caught,0),
    'money_earned', coalesce(gs.money_earned,0),
    'checks', coalesce(gs.checks,0),
    'checkmates', coalesce(gs.checkmates,0),
    'merges', coalesce(gs.merges,0),
    'best_level', coalesce(gs.best_level,0),
    'hits', coalesce(gs.hits,0)
  ) into v_stat
  from public.game_stats as gs
  where gs.user_id = v_uid and gs.game_title = v_game_title;

  return coalesce(v_stat, '{}'::jsonb);
end;
$$;

create function public.award_achievement(
  p_achievement_id text,
  p_title text,
  p_description text,
  p_icon text,
  p_game_title text default null,
  p_reward_points integer default 0
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_inserted_count integer := 0;
  v_safe_points integer := greatest(0, least(coalesce(p_reward_points, 0), 10000));
begin
  if v_uid is null then raise exception 'Not signed in.'; end if;

  insert into public.user_achievements (user_id, achievement_id, title, description, icon, game_title, reward_points)
  values (v_uid, p_achievement_id, p_title, p_description, p_icon, p_game_title, v_safe_points)
  on conflict (user_id, achievement_id) do nothing;

  get diagnostics v_inserted_count = row_count;

  if v_inserted_count > 0 then
    -- Achievements give points only. Icons come only from icon packs.
    update public.profiles
    set points = coalesce(points, 0) + v_safe_points
    where id = v_uid;
    return true;
  end if;
  return false;
end;
$$;

create function public.get_public_leaderboard(max_rows integer default 100)
returns table (id uuid, username text, avatar_url text, points integer, equipped_icon text)
language sql
security definer
set search_path = public
as $$
  select p.id, p.username, p.avatar_url, p.points, p.equipped_icon
  from public.profiles p
  order by p.points desc, lower(p.username) asc
  limit greatest(1, least(coalesce(max_rows, 100), 100));
$$;

grant execute on function public.record_game_metric(text, text, integer, text) to authenticated;
grant execute on function public.record_game_progress(text, boolean, integer) to authenticated;
grant execute on function public.award_achievement(text, text, text, text, text, integer) to authenticated;
grant execute on function public.get_public_leaderboard(integer) to anon, authenticated;

-- Reset only your Admin account's broken achievement/testing progress from the failed versions.
-- This clears Admin's achievement records, game_stats, and points so you can test cleanly.
do $$
declare
  v_admin_id uuid;
begin
  select id into v_admin_id
  from public.profiles
  where lower(username) = lower('Admin')
  limit 1;

  if v_admin_id is not null then
    delete from public.user_achievements where user_id = v_admin_id;
    delete from public.game_stats where user_id = v_admin_id;
    update public.profiles
    set points = 0,
        equipped_achievement_id = null,
        equipped_icon = null
    where id = v_admin_id;
  end if;
end $$;

select pg_notify('pgrst', 'reload schema');

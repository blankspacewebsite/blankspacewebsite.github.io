-- Blank Space v87 strict achievement patch
-- Fixes mass-unlocking by making manual submissions store exact values instead of keeping old inflated stats.
-- Resets only the Admin account's achievement progress/stats/points again for a clean test.
-- Keeps achievements as points-only and cleans achievement-icon leftovers out of user_icons.

create or replace function public.profiles_update_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'Profile ID cannot be changed.';
  end if;

  if new.created_at is distinct from old.created_at then
    raise exception 'Profile creation time cannot be changed.';
  end if;

  if coalesce(current_setting('blank_space.allow_points_update', true), '') <> '1'
     and new.points is distinct from old.points then
    raise exception 'Points can only be changed by an admin award.';
  end if;

  if new.username is distinct from old.username then
    if old.username_last_changed_at is not null and old.username_last_changed_at > now() - interval '7 days' then
      raise exception 'You can only change your username once every 7 days.';
    end if;
    new.username_last_changed_at := now();
  elsif new.username_last_changed_at is distinct from old.username_last_changed_at then
    raise exception 'Username timer cannot be changed directly.';
  end if;

  return new;
end;
$$;

drop function if exists public.record_game_metric(text, text, integer, text);

create function public.record_game_metric(
  p_game_title text,
  p_metric text,
  p_value integer default 1,
  p_mode text default 'replace'
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
  v_mode text := lower(trim(coalesce(p_mode, 'replace')));
  v_stat jsonb;
begin
  if v_uid is null then raise exception 'Not signed in.'; end if;
  if char_length(v_game_title) < 1 then raise exception 'Game title is required.'; end if;

  insert into public.game_stats (user_id, game_title)
  values (v_uid, v_game_title)
  on conflict (user_id, game_title) do nothing;

  if v_metric = 'best_score' then
    update public.game_stats as gs
    set best_score = case when v_mode = 'max' then greatest(coalesce(gs.best_score, 0), v_value) else v_value end,
        last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'goals' then
    update public.game_stats as gs
    set goals = case when v_mode = 'add' then coalesce(gs.goals,0) + greatest(v_value,1) else v_value end,
        last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'wins' then
    update public.game_stats as gs
    set wins = case when v_mode = 'add' then coalesce(gs.wins,0) + greatest(v_value,1) else v_value end,
        last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'fish_caught' then
    update public.game_stats as gs
    set fish_caught = case when v_mode = 'add' then coalesce(gs.fish_caught,0) + greatest(v_value,1) else v_value end,
        last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'money_earned' then
    update public.game_stats as gs
    set money_earned = case when v_mode = 'max' then greatest(coalesce(gs.money_earned, 0), v_value) else v_value end,
        last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'checks' then
    update public.game_stats as gs
    set checks = case when v_mode = 'add' then coalesce(gs.checks,0) + greatest(v_value,1) else v_value end,
        last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'checkmates' then
    update public.game_stats as gs
    set checkmates = case when v_mode = 'add' then coalesce(gs.checkmates,0) + greatest(v_value,1) else v_value end,
        last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'merges' then
    update public.game_stats as gs
    set merges = case when v_mode = 'add' then coalesce(gs.merges,0) + greatest(v_value,1) else v_value end,
        last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'best_level' then
    update public.game_stats as gs
    set best_level = case when v_mode = 'max' then greatest(coalesce(gs.best_level, 0), v_value) else v_value end,
        last_played_at = now()
    where gs.user_id = v_uid and gs.game_title = v_game_title;
  elsif v_metric = 'hits' then
    update public.game_stats as gs
    set hits = case when v_mode = 'add' then coalesce(gs.hits,0) + greatest(v_value,1) else v_value end,
        last_played_at = now()
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

grant execute on function public.record_game_metric(text, text, integer, text) to authenticated;

-- Clean achievement-icon leftovers from the icon inventory. Pack icons use the catalog ids below.
delete from public.user_icons
where icon_id not in (
  'comet','rocket','star','moon','basketball','soccer','snake','fish','pawn','apple',
  'alien','fire','bolt','trophy','car','baseball','cat','duck','sword','target',
  'crown','dragon','gem','ghost','skull','controller','wizard','ninja','king','queen',
  'ufo','saturn','blackhole','phoenix','robot','money','medal','laser',
  'champ','galaxy','diamond','lion','eagle','tornado',
  'void','nova','meteor','neon','godmode','infinity','blankspace'
);

-- Reset Admin cleanly again, including inflated stats that caused mass unlocks.
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
    perform set_config('blank_space.allow_points_update', '1', true);
    update public.profiles
    set points = 0,
        equipped_achievement_id = null,
        equipped_icon = null
    where id = v_admin_id;
  end if;
end $$;

select pg_notify('pgrst', 'reload schema');

-- Blank Space v85 Supabase update
-- Safe update: fixes achievement functions and icon equipping. Does NOT delete accounts, points, friends, messages, suggestions, trades, or achievements.

alter table public.profiles
  add column if not exists equipped_icon text,
  add column if not exists equipped_achievement_id text,
  add column if not exists points integer not null default 0;

create table if not exists public.game_stats (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game_title text not null,
  play_count integer not null default 0,
  play_seconds integer not null default 0,
  first_played_at timestamptz not null default now(),
  last_played_at timestamptz not null default now(),
  primary key (user_id, game_title),
  constraint game_stats_title_length check (char_length(game_title) between 1 and 120)
);

alter table public.game_stats
  add column if not exists best_score integer not null default 0,
  add column if not exists goals integer not null default 0,
  add column if not exists wins integer not null default 0,
  add column if not exists fish_caught integer not null default 0,
  add column if not exists money_earned integer not null default 0,
  add column if not exists checks integer not null default 0,
  add column if not exists checkmates integer not null default 0,
  add column if not exists merges integer not null default 0,
  add column if not exists best_level integer not null default 0,
  add column if not exists hits integer not null default 0;

create table if not exists public.user_achievements (
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_id text not null,
  title text not null,
  description text not null,
  icon text not null,
  game_title text,
  reward_points integer not null default 0,
  earned_at timestamptz not null default now(),
  primary key (user_id, achievement_id),
  constraint achievement_id_length check (char_length(achievement_id) between 2 and 80),
  constraint achievement_title_length check (char_length(title) between 2 and 120),
  constraint achievement_description_length check (char_length(description) between 2 and 280),
  constraint achievement_icon_length check (char_length(icon) between 1 and 24),
  constraint achievement_reward_nonnegative check (reward_points >= 0 and reward_points <= 10000)
);

alter table public.game_stats enable row level security;
alter table public.user_achievements enable row level security;

drop policy if exists "game_stats_select_own" on public.game_stats;
drop policy if exists "game_stats_insert_own" on public.game_stats;
drop policy if exists "game_stats_update_own" on public.game_stats;

create policy "game_stats_select_own"
on public.game_stats
for select
to authenticated
using (user_id = auth.uid() or public.is_blank_space_admin());

create policy "game_stats_insert_own"
on public.game_stats
for insert
to authenticated
with check (user_id = auth.uid());

create policy "game_stats_update_own"
on public.game_stats
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "user_achievements_select_own_or_admin" on public.user_achievements;
drop policy if exists "user_achievements_insert_own" on public.user_achievements;
drop policy if exists "user_achievements_update_own" on public.user_achievements;

create policy "user_achievements_select_own_or_admin"
on public.user_achievements
for select
to authenticated
using (user_id = auth.uid() or public.is_blank_space_admin());

create policy "user_achievements_insert_own"
on public.user_achievements
for insert
to authenticated
with check (user_id = auth.uid());

create policy "user_achievements_update_own"
on public.user_achievements
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Replace broken/old function signatures safely.
drop function if exists public.record_game_progress(text, boolean, integer);
drop function if exists public.record_game_metric(text, text, integer, text);
drop function if exists public.award_achievement(text, text, text, text, text, integer);
drop function if exists public.equip_achievement_icon(text);
drop function if exists public.get_public_leaderboard(integer);

create function public.record_game_progress(
  p_game_title text,
  p_open_event boolean default false,
  p_seconds integer default 0
)
returns table (
  game_title text,
  play_count integer,
  play_seconds integer,
  best_score integer,
  goals integer,
  wins integer,
  fish_caught integer,
  money_earned integer,
  checks integer,
  checkmates integer,
  merges integer,
  best_level integer,
  hits integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  add_count integer := case when coalesce(p_open_event, false) then 1 else 0 end;
  add_seconds integer := greatest(0, coalesce(p_seconds, 0));
begin
  if uid is null then raise exception 'Not signed in.'; end if;
  if p_game_title is null or char_length(trim(p_game_title)) < 1 then raise exception 'Game title is required.'; end if;

  insert into public.game_stats (user_id, game_title, play_count, play_seconds)
  values (uid, trim(p_game_title), add_count, add_seconds)
  on conflict (user_id, game_title)
  do update set
    play_count = public.game_stats.play_count + excluded.play_count,
    play_seconds = public.game_stats.play_seconds + excluded.play_seconds,
    last_played_at = now();

  return query
  select gs.game_title, gs.play_count, gs.play_seconds, gs.best_score, gs.goals, gs.wins,
         gs.fish_caught, gs.money_earned, gs.checks, gs.checkmates, gs.merges, gs.best_level, gs.hits
  from public.game_stats gs
  where gs.user_id = uid and gs.game_title = trim(p_game_title);
end;
$$;

create function public.record_game_metric(
  p_game_title text,
  p_metric text,
  p_value integer default 1,
  p_mode text default 'max'
)
returns table (
  game_title text,
  play_count integer,
  play_seconds integer,
  best_score integer,
  goals integer,
  wins integer,
  fish_caught integer,
  money_earned integer,
  checks integer,
  checkmates integer,
  merges integer,
  best_level integer,
  hits integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  metric text := lower(trim(coalesce(p_metric, '')));
  val integer := greatest(0, coalesce(p_value, 0));
begin
  if uid is null then raise exception 'Not signed in.'; end if;
  if p_game_title is null or char_length(trim(p_game_title)) < 1 then raise exception 'Game title is required.'; end if;

  insert into public.game_stats (user_id, game_title)
  values (uid, trim(p_game_title))
  on conflict (user_id, game_title) do nothing;

  if metric = 'best_score' then
    update public.game_stats set best_score = greatest(best_score, val), last_played_at = now() where user_id = uid and game_title = trim(p_game_title);
  elsif metric = 'goals' then
    update public.game_stats set goals = goals + greatest(val, 1), last_played_at = now() where user_id = uid and game_title = trim(p_game_title);
  elsif metric = 'wins' then
    update public.game_stats set wins = wins + greatest(val, 1), last_played_at = now() where user_id = uid and game_title = trim(p_game_title);
  elsif metric = 'fish_caught' then
    update public.game_stats set fish_caught = fish_caught + greatest(val, 1), last_played_at = now() where user_id = uid and game_title = trim(p_game_title);
  elsif metric = 'money_earned' then
    update public.game_stats set money_earned = greatest(money_earned, val), last_played_at = now() where user_id = uid and game_title = trim(p_game_title);
  elsif metric = 'checks' then
    update public.game_stats set checks = checks + greatest(val, 1), last_played_at = now() where user_id = uid and game_title = trim(p_game_title);
  elsif metric = 'checkmates' then
    update public.game_stats set checkmates = checkmates + greatest(val, 1), last_played_at = now() where user_id = uid and game_title = trim(p_game_title);
  elsif metric = 'merges' then
    update public.game_stats set merges = merges + greatest(val, 1), last_played_at = now() where user_id = uid and game_title = trim(p_game_title);
  elsif metric = 'best_level' then
    update public.game_stats set best_level = greatest(best_level, val), last_played_at = now() where user_id = uid and game_title = trim(p_game_title);
  elsif metric = 'hits' then
    update public.game_stats set hits = hits + greatest(val, 1), last_played_at = now() where user_id = uid and game_title = trim(p_game_title);
  else
    raise exception 'Unknown game metric: %', metric;
  end if;

  return query
  select gs.game_title, gs.play_count, gs.play_seconds, gs.best_score, gs.goals, gs.wins,
         gs.fish_caught, gs.money_earned, gs.checks, gs.checkmates, gs.merges, gs.best_level, gs.hits
  from public.game_stats gs
  where gs.user_id = uid and gs.game_title = trim(p_game_title);
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
  uid uuid := auth.uid();
  inserted_count integer := 0;
  safe_points integer := greatest(0, least(coalesce(p_reward_points, 0), 10000));
begin
  if uid is null then raise exception 'Not signed in.'; end if;

  insert into public.user_achievements (user_id, achievement_id, title, description, icon, game_title, reward_points)
  values (uid, p_achievement_id, p_title, p_description, p_icon, p_game_title, safe_points)
  on conflict (user_id, achievement_id) do nothing;

  get diagnostics inserted_count = row_count;

  if inserted_count > 0 then
    update public.profiles
    set points = coalesce(points, 0) + safe_points,
        equipped_icon = coalesce(equipped_icon, p_icon),
        equipped_achievement_id = coalesce(equipped_achievement_id, p_achievement_id)
    where id = uid;
    return true;
  end if;
  return false;
end;
$$;

create function public.equip_achievement_icon(p_achievement_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  chosen_icon text;
begin
  if uid is null then raise exception 'Not signed in.'; end if;

  select ua.icon into chosen_icon
  from public.user_achievements ua
  where ua.user_id = uid
    and ua.achievement_id = p_achievement_id;

  if chosen_icon is null then
    raise exception 'You have not unlocked that icon yet.';
  end if;

  update public.profiles
  set equipped_icon = chosen_icon,
      equipped_achievement_id = p_achievement_id
  where id = uid;
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
  where not exists (select 1 from public.admin_users a where a.user_id = p.id)
  order by p.points desc, lower(p.username) asc
  limit greatest(1, least(coalesce(max_rows, 100), 100));
$$;

grant execute on function public.record_game_progress(text, boolean, integer) to authenticated;
grant execute on function public.record_game_metric(text, text, integer, text) to authenticated;
grant execute on function public.award_achievement(text, text, text, text, text, integer) to authenticated;
grant execute on function public.equip_achievement_icon(text) to authenticated;
grant execute on function public.get_public_leaderboard(integer) to anon, authenticated;

select pg_notify('pgrst', 'reload schema');

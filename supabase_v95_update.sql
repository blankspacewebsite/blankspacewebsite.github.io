-- Blank Space v95 update
-- Paste this whole file into Supabase SQL Editor, then click Run.
-- Adds the one-of-one Owner rank for Admin, manager+ leaderboard flagging,
-- warnings with 3 warnings = 1 day suspension, chat bad-word auto-warnings,
-- timed messages to everyone, owner read-only chat view, and an A Small World Cup double-goal guard.
-- This does NOT delete accounts, friends, chats, trades, suggestions, owned icons, or points.

-- ============================================================
-- 1) Required columns/tables
-- ============================================================

alter table public.profiles add column if not exists rank text not null default 'member';
alter table public.profiles add column if not exists points integer not null default 0;
alter table public.profiles add column if not exists equipped_icon text;
alter table public.profiles add column if not exists equipped_achievement_id text;
alter table public.profiles add column if not exists is_banned boolean not null default false;
alter table public.profiles add column if not exists ban_reason text;
alter table public.profiles add column if not exists chat_muted_until timestamptz;
alter table public.profiles add column if not exists suspended_until timestamptz;
alter table public.profiles add column if not exists force_sign_out_at timestamptz;


-- Core achievement/stat tables used by the repair below.
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


update public.profiles
set rank = 'member'
where rank is null or lower(rank) not in ('owner','admin','manager','tester','member');

create table if not exists public.admin_users (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_actions_log (
  id bigint generated by default as identity primary key,
  admin_id uuid references public.profiles(id) on delete set null,
  target_user_id uuid references public.profiles(id) on delete set null,
  target_username text,
  action text not null,
  reason text,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_user_messages (
  id bigint generated by default as identity primary key,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  admin_id uuid references public.profiles(id) on delete set null,
  title text,
  message text not null,
  style text not null default 'notice',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

alter table public.admin_user_messages add column if not exists title text;
alter table public.admin_user_messages add column if not exists style text not null default 'notice';
alter table public.admin_user_messages add column if not exists active boolean not null default true;
alter table public.admin_user_messages add column if not exists expires_at timestamptz not null default (now() + interval '20 seconds');

create index if not exists admin_user_messages_target_active_idx on public.admin_user_messages(target_user_id, active, expires_at desc);

create table if not exists public.user_warnings (
  id bigint generated by default as identity primary key,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  target_username text,
  issued_by uuid references public.profiles(id) on delete set null,
  source text not null default 'manual',
  reason text,
  warning_number integer not null,
  created_at timestamptz not null default now()
);

create index if not exists user_warnings_target_idx on public.user_warnings(target_user_id, created_at desc);

-- A Small World Cup double-signal guard: two signals = one real goal.
create table if not exists public.aswc_goal_signal_pairs (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  pending_signals integer not null default 0,
  updated_at timestamptz not null default now()
);

drop table if exists public.aswc_goal_signal_counters;
drop table if exists public.aswc_goal_event_guard;

-- ============================================================
-- 2) Owner/Admin/Manager helpers
-- ============================================================

create or replace function public.is_blank_space_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and lower(coalesce(p.rank,'member')) = 'owner'
  );
$$;

grant execute on function public.is_blank_space_owner() to anon, authenticated;

create or replace function public.is_blank_space_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admin_users a where a.user_id = auth.uid())
     or exists (
       select 1 from public.profiles p
       where p.id = auth.uid() and lower(coalesce(p.rank,'member')) in ('owner','admin')
     );
$$;

grant execute on function public.is_blank_space_admin() to anon, authenticated;

create or replace function public.is_blank_space_moderator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and lower(coalesce(p.rank,'member')) in ('owner','admin','manager')
  ) or public.is_blank_space_admin();
$$;

grant execute on function public.is_blank_space_moderator() to anon, authenticated;

-- Make Admin the one-of-one Owner. Clear any accidental other owners first.
do $$
declare
  v_admin uuid;
begin
  perform set_config('blank_space.allow_rank_update','1', true);

  update public.profiles
  set rank = 'member'
  where lower(coalesce(rank,'member')) = 'owner'
    and lower(trim(username)) <> lower('Admin');

  update public.profiles
  set rank = 'owner'
  where lower(trim(username)) = lower('Admin')
  returning id into v_admin;

  if v_admin is not null then
    insert into public.admin_users(user_id) values(v_admin) on conflict(user_id) do nothing;
  end if;
end $$;

create unique index if not exists one_blank_space_owner_rank
on public.profiles((lower(rank)))
where lower(rank) = 'owner';

-- ============================================================
-- 3) RLS grants/policies
-- ============================================================

alter table public.admin_actions_log enable row level security;
alter table public.admin_user_messages enable row level security;
alter table public.user_warnings enable row level security;

drop policy if exists admin_actions_select_v95 on public.admin_actions_log;
create policy admin_actions_select_v95 on public.admin_actions_log
for select to authenticated
using (public.is_blank_space_moderator());

drop policy if exists admin_messages_select_v95 on public.admin_user_messages;
create policy admin_messages_select_v95 on public.admin_user_messages
for select to authenticated
using (target_user_id = auth.uid() or public.is_blank_space_admin());

drop policy if exists user_warnings_select_v95 on public.user_warnings;
create policy user_warnings_select_v95 on public.user_warnings
for select to authenticated
using (target_user_id = auth.uid() or public.is_blank_space_moderator());

grant select, insert on table public.admin_actions_log to authenticated;
grant select on table public.admin_user_messages to authenticated;
grant select on table public.user_warnings to authenticated;
grant usage, select on all sequences in schema public to authenticated;

create or replace function public.log_admin_action(p_target_user_id uuid, p_target_username text, p_action text, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_actions_log(admin_id, target_user_id, target_username, action, reason)
  values(auth.uid(), p_target_user_id, p_target_username, left(coalesce(p_action,''),120), left(nullif(trim(coalesce(p_reason,'')),''),300));
end;
$$;

grant execute on function public.log_admin_action(uuid, text, text, text) to authenticated;

-- ============================================================
-- 4) Owner-compatible rank function
-- ============================================================

drop function if exists public.admin_set_rank_v89(text, text, text);

create function public.admin_set_rank_v89(p_username text, p_rank text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := auth.uid();
  v_target public.profiles%rowtype;
  v_rank text := lower(trim(coalesce(p_rank,'member')));
begin
  if v_admin is null or not public.is_blank_space_admin() then
    raise exception 'Owner/Admin only.';
  end if;

  if v_rank not in ('owner','admin','manager','tester','member') then
    raise exception 'Invalid rank.';
  end if;

  select * into v_target
  from public.profiles
  where lower(trim(username)) = lower(trim(coalesce(p_username,'')))
  limit 1;

  if v_target.id is null then
    raise exception 'User not found.';
  end if;

  if v_rank = 'owner' then
    if not public.is_blank_space_owner() then
      raise exception 'Only the Owner can assign Owner.';
    end if;
    if lower(trim(v_target.username)) <> lower('Admin') then
      raise exception 'Owner is one-of-one and locked to Admin.';
    end if;
  end if;

  perform set_config('blank_space.allow_rank_update','1',true);
  update public.profiles set rank = v_rank where id = v_target.id;

  if v_rank in ('owner','admin') then
    insert into public.admin_users(user_id) values(v_target.id) on conflict(user_id) do nothing;
  else
    delete from public.admin_users where user_id = v_target.id;
  end if;

  perform public.log_admin_action(v_target.id, v_target.username, 'set_rank:' || v_rank, p_reason);
  return jsonb_build_object('ok', true, 'username', v_target.username, 'rank', v_rank);
end;
$$;

grant execute on function public.admin_set_rank_v89(text, text, text) to authenticated;

-- ============================================================
-- 5) Warning/flagging system
-- ============================================================

drop function if exists public.create_user_warning_v95(uuid, text, text, uuid);

create function public.create_user_warning_v95(
  p_target_user_id uuid,
  p_reason text default null,
  p_source text default 'manual',
  p_issued_by uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.profiles%rowtype;
  v_reason text := left(coalesce(nullif(trim(p_reason),''),'Flagged for review.'),300);
  v_source text := left(coalesce(nullif(trim(p_source),''),'manual'),80);
  v_warning_number integer := 0;
  v_suspended boolean := false;
  v_title text;
  v_message text;
begin
  select * into v_target from public.profiles where id = p_target_user_id limit 1;
  if v_target.id is null then
    raise exception 'Target user not found.';
  end if;

  select coalesce(max(warning_number),0) + 1
  into v_warning_number
  from public.user_warnings
  where target_user_id = v_target.id;

  insert into public.user_warnings(target_user_id, target_username, issued_by, source, reason, warning_number)
  values(v_target.id, v_target.username, p_issued_by, v_source, v_reason, v_warning_number);

  if v_warning_number % 3 = 0 then
    v_suspended := true;
    perform set_config('blank_space.allow_moderation_update','1',true);
    update public.profiles
    set suspended_until = now() + interval '1 day',
        chat_muted_until = now() + interval '1 day'
    where id = v_target.id;
  end if;

  v_title := 'Warning ' || v_warning_number::text;
  v_message := case when v_suspended then
    'You reached 3 warnings and received a 1 day suspension. Reason: ' || v_reason
  else
    'If you get 3 warnings, it is a one day suspension. Reason: ' || v_reason
  end;

  insert into public.admin_user_messages(target_user_id, admin_id, title, message, style, expires_at)
  values(v_target.id, p_issued_by, v_title, v_message, case when v_suspended then 'danger' else 'warning' end, now() + interval '45 seconds');

  insert into public.admin_actions_log(admin_id, target_user_id, target_username, action, reason)
  values(p_issued_by, v_target.id, v_target.username, 'warning:' || v_source, v_reason);

  return jsonb_build_object('ok', true, 'username', v_target.username, 'warning_count', v_warning_number, 'suspended', v_suspended);
end;
$$;

grant execute on function public.create_user_warning_v95(uuid, text, text, uuid) to authenticated;

drop function if exists public.admin_flag_user_v95(text, text);

create function public.admin_flag_user_v95(p_username text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.profiles%rowtype;
begin
  if not public.is_blank_space_moderator() then
    raise exception 'Managers and above only.';
  end if;

  select * into v_target
  from public.profiles
  where lower(trim(username)) = lower(trim(coalesce(p_username,'')))
  limit 1;

  if v_target.id is null then
    raise exception 'User not found.';
  end if;

  return public.create_user_warning_v95(v_target.id, coalesce(p_reason,'Flagged from leaderboard'), 'leaderboard_flag', auth.uid());
end;
$$;

grant execute on function public.admin_flag_user_v95(text, text) to authenticated;

drop function if exists public.record_chat_warning_v95(text);

create function public.record_chat_warning_v95(p_reason text default 'Blocked language in chat')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not signed in.';
  end if;
  return public.create_user_warning_v95(v_uid, coalesce(p_reason,'Blocked language in chat'), 'chat_bad_word', v_uid);
end;
$$;

grant execute on function public.record_chat_warning_v95(text) to authenticated;

-- ============================================================
-- 6) Chat inappropriate word auto-warning and suspension enforcement
-- ============================================================

drop function if exists public.bs_contains_bad_language(text);

create function public.bs_contains_bad_language(p_text text)
returns boolean
language plpgsql
immutable
as $$
declare
  v_text text := lower(coalesce(p_text,''));
begin
  return v_text ~ '(^|[^a-z0-9])(fuck|shit|bitch|asshole|dick|pussy|porn|nude|sex|kys|kill yourself|nazi|hitler)([^a-z0-9]|$)';
end;
$$;

drop function if exists public.enforce_chat_moderation();

create function public.enforce_chat_moderation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_banned boolean;
  v_muted_until timestamptz;
  v_suspended_until timestamptz;
begin
  select is_banned, chat_muted_until, suspended_until
  into v_is_banned, v_muted_until, v_suspended_until
  from public.profiles
  where id = new.sender_id;

  if v_suspended_until is not null and v_suspended_until > now() then
    raise exception 'You are suspended until %.', v_suspended_until;
  end if;

  if coalesce(v_is_banned,false) then
    raise exception 'You are banned from chat.';
  end if;

  if v_muted_until is not null and v_muted_until > now() then
    raise exception 'You are muted from chat until %.', v_muted_until;
  end if;

  if public.bs_contains_bad_language(new.body) then
    perform public.create_user_warning_v95(new.sender_id, 'Blocked inappropriate word in chat', 'chat_bad_word', new.sender_id);
    raise exception 'Message blocked for inappropriate language. Warning issued.';
  end if;

  return new;
end;
$$;

do $$ begin
  if to_regclass('public.friend_messages') is not null then
    execute 'drop trigger if exists friend_messages_moderation_trigger on public.friend_messages';
    execute 'create trigger friend_messages_moderation_trigger before insert on public.friend_messages for each row execute function public.enforce_chat_moderation()';
  end if;
  if to_regclass('public.group_chat_messages') is not null then
    execute 'drop trigger if exists group_chat_messages_moderation_trigger on public.group_chat_messages';
    execute 'create trigger group_chat_messages_moderation_trigger before insert on public.group_chat_messages for each row execute function public.enforce_chat_moderation()';
  end if;
end $$;

-- ============================================================
-- 7) Timed messages: one user or everyone
-- ============================================================

drop function if exists public.admin_send_user_message_v95(text, text, integer, text, boolean);

create function public.admin_send_user_message_v95(
  p_username text,
  p_message text,
  p_seconds integer default 20,
  p_style text default 'notice',
  p_send_all boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
  v_target public.profiles%rowtype;
  v_seconds integer := greatest(3, least(coalesce(p_seconds, 20), 3600));
  v_style text := lower(trim(coalesce(p_style, 'notice')));
  v_message text := left(trim(coalesce(p_message, '')), 500);
  v_count integer := 0;
begin
  if not public.is_blank_space_admin() then
    raise exception 'Owner/Admin only.';
  end if;

  if v_message = '' then
    raise exception 'Message is required.';
  end if;

  if v_style not in ('notice','warning','danger') then
    v_style := 'notice';
  end if;

  if coalesce(p_send_all,false) then
    insert into public.admin_user_messages(target_user_id, admin_id, title, message, style, expires_at)
    select id, v_admin_id, 'Blank Space Notice', v_message, v_style, now() + make_interval(secs => v_seconds)
    from public.profiles;
    get diagnostics v_count = row_count;

    insert into public.admin_actions_log(admin_id, target_user_id, target_username, action, reason)
    values(v_admin_id, null, 'ALL USERS', 'timed_message_all', left(v_message,240));

    return jsonb_build_object('ok', true, 'sent_to', v_count, 'all', true, 'seconds', v_seconds, 'style', v_style);
  end if;

  select * into v_target
  from public.profiles
  where lower(trim(username)) = lower(trim(coalesce(p_username, '')))
  limit 1;

  if v_target.id is null then
    raise exception 'User not found.';
  end if;

  insert into public.admin_user_messages(target_user_id, admin_id, title, message, style, expires_at)
  values(v_target.id, v_admin_id, 'Blank Space Notice', v_message, v_style, now() + make_interval(secs => v_seconds));

  insert into public.admin_actions_log(admin_id, target_user_id, target_username, action, reason)
  values(v_admin_id, v_target.id, v_target.username, 'timed_message', left(v_message, 240));

  return jsonb_build_object('ok', true, 'sent_to', 1, 'target_username', v_target.username, 'seconds', v_seconds, 'style', v_style);
end;
$$;

grant execute on function public.admin_send_user_message_v95(text, text, integer, text, boolean) to authenticated;

-- ============================================================
-- 8) Owner read-only chat view
-- ============================================================

drop function if exists public.owner_get_user_chat_view_v95(text, integer);

create function public.owner_get_user_chat_view_v95(p_username text, p_limit integer default 200)
returns table(
  chat_type text,
  chat_name text,
  sender_username text,
  body text,
  image_url text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.profiles%rowtype;
  v_limit integer := greatest(1, least(coalesce(p_limit,200), 500));
begin
  if not public.is_blank_space_owner() then
    raise exception 'Owner only.';
  end if;

  select * into v_target
  from public.profiles
  where lower(trim(username)) = lower(trim(coalesce(p_username,'')))
  limit 1;

  if v_target.id is null then
    raise exception 'User not found.';
  end if;

  return query
  select * from (
    select
      'friend'::text as chat_type,
      ('Chat with @' || coalesce(case when f.requester_id = v_target.id then pr.username else pq.username end, 'unknown'))::text as chat_name,
      coalesce(ps.username, 'unknown')::text as sender_username,
      fm.body::text as body,
      fm.image_url::text as image_url,
      fm.created_at
    from public.friend_messages fm
    join public.friends f on f.id = fm.friendship_id
    left join public.profiles ps on ps.id = fm.sender_id
    left join public.profiles pr on pr.id = f.receiver_id
    left join public.profiles pq on pq.id = f.requester_id
    where f.requester_id = v_target.id or f.receiver_id = v_target.id

    union all

    select
      'group'::text as chat_type,
      ('Group: ' || coalesce(gc.name, 'Group'))::text as chat_name,
      coalesce(ps.username, 'unknown')::text as sender_username,
      gm.body::text as body,
      gm.image_url::text as image_url,
      gm.created_at
    from public.group_chat_messages gm
    join public.group_chat_members mem on mem.group_id = gm.group_id
    join public.group_chats gc on gc.id = gm.group_id
    left join public.profiles ps on ps.id = gm.sender_id
    where mem.user_id = v_target.id
  ) q
  order by q.created_at desc
  limit v_limit;
end;
$$;

grant execute on function public.owner_get_user_chat_view_v95(text, integer) to authenticated;

-- ============================================================
-- 9) A Small World Cup double-goal guard + safe achievement awarding
-- ============================================================

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
  hits integer default 0
);

create unique index if not exists game_stats_user_game_unique on public.game_stats(user_id, game_title);
create unique index if not exists user_achievements_user_achievement_unique on public.user_achievements(user_id, achievement_id);
create unique index if not exists achievement_catalog_achievement_unique on public.achievement_catalog(achievement_id);

-- Restore ASWC target rows so 5 goals only unlocks the 5-goal achievement.
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
  ('a_small_world_cup_goals_300_44','300 total goals','Score 300 total goals in A Small World Cup','⚽','A Small World Cup','goals',300,20,'crazy')
on conflict (achievement_id) do update set
  title = excluded.title,
  description = excluded.description,
  icon = excluded.icon,
  game_title = excluded.game_title,
  stat = excluded.stat,
  target = excluded.target,
  reward_points = excluded.reward_points,
  difficulty = excluded.difficulty;

-- Generic safe award function used by record_game_metric.
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
  if v_auth_uid is null then raise exception 'Not signed in.'; end if;
  if p_user_id is distinct from v_auth_uid then raise exception 'Not allowed to award achievements for another user.'; end if;

  if lower(trim(coalesce(v_game_title,''))) in ('a small world cup','a-small-world-cup','small world cup') then
    v_game_title := 'A Small World Cup';
  end if;

  with eligible as (
    select c.*
    from public.achievement_catalog c
    join public.game_stats gs on gs.user_id = p_user_id and gs.game_title = c.game_title
    left join public.user_achievements ua on ua.user_id = p_user_id and ua.achievement_id = c.achievement_id
    where ua.achievement_id is null
      and c.achievement_id is not null
      and (v_game_title is null or c.game_title = v_game_title)
      and (case c.stat
        when 'play_count' then coalesce(gs.play_count,0)
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
        else 0 end) >= coalesce(c.target,999999999)
  ), inserted as (
    insert into public.user_achievements(user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at)
    select p_user_id, c.achievement_id, coalesce(nullif(c.title,''),'Achievement'), coalesce(c.description,''), coalesce(nullif(c.icon,''),'🏆'), c.game_title, greatest(0,coalesce(c.reward_points,0)), now()
    from eligible c
    on conflict(user_id, achievement_id) do nothing
    returning reward_points
  )
  select count(*)::integer, coalesce(sum(reward_points),0)::integer
  into v_awards, v_points
  from inserted;

  if v_awards > 0 and v_points > 0 then
    perform set_config('blank_space.allow_points_update','1',true);
    update public.profiles set points = coalesce(points,0) + v_points where id = p_user_id;
  end if;

  return coalesce(v_awards,0);
end;
$$;

grant execute on function public.award_ready_achievements(uuid, text) to authenticated;

-- Record metrics. ASWC goal modes delta_v93/add count two incoming signals as one real goal.
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
  v_game_title text := trim(coalesce(p_game_title,''));
  v_metric text := lower(trim(coalesce(p_metric,'')));
  v_mode text := lower(trim(coalesce(p_mode,'max')));
  v_value integer := greatest(0, coalesce(p_value,0));
  v_pending integer := 0;
  v_total_signals integer := 0;
  v_real_goals_to_add integer := 0;
  v_new_awards integer := 0;
  v_stat jsonb := '{}'::jsonb;
begin
  if v_uid is null then raise exception 'Not signed in.'; end if;

  if lower(v_game_title) in ('a small world cup','a-small-world-cup','small world cup') then
    v_game_title := 'A Small World Cup';
  end if;
  if v_game_title = '' then raise exception 'Game title is required.'; end if;
  if v_metric not in ('play_count','best_score','goals','wins','fish_caught','money_earned','checks','checkmates','merges','best_level','hits') then
    raise exception 'Unknown game metric: %', v_metric;
  end if;
  v_value := least(v_value, 100000000);

  insert into public.game_stats(user_id, game_title, first_played_at, last_played_at)
  values(v_uid, v_game_title, now(), now())
  on conflict(user_id, game_title) do nothing;

  if v_game_title = 'A Small World Cup' and v_metric = 'goals' and v_mode in ('delta_v93','add') then
    select pending_signals into v_pending
    from public.aswc_goal_signal_pairs
    where user_id = v_uid
    for update;
    if v_pending is null then v_pending := 0; end if;

    v_total_signals := v_pending + greatest(v_value,1);
    v_real_goals_to_add := floor(v_total_signals::numeric / 2)::integer;
    v_pending := mod(v_total_signals, 2);

    insert into public.aswc_goal_signal_pairs(user_id, pending_signals, updated_at)
    values(v_uid, v_pending, now())
    on conflict(user_id) do update set pending_signals = excluded.pending_signals, updated_at = now();

    update public.game_stats
    set goals = coalesce(goals,0) + v_real_goals_to_add,
        last_played_at = now()
    where user_id = v_uid and game_title = v_game_title;

  elsif v_game_title = 'A Small World Cup' and v_metric = 'wins' and v_mode in ('add_win_v93','add') then
    update public.game_stats
    set wins = coalesce(wins,0) + greatest(v_value,1),
        last_played_at = now()
    where user_id = v_uid and game_title = v_game_title;

  elsif v_game_title = 'A Small World Cup' and v_metric = 'goals' and v_mode in ('max','replace') then
    update public.game_stats
    set goals = case when v_mode = 'replace' then floor(v_value::numeric / 2)::integer else greatest(coalesce(goals,0), floor(v_value::numeric / 2)::integer) end,
        last_played_at = now()
    where user_id = v_uid and game_title = v_game_title;

  else
    execute format(
      'update public.game_stats set %I = case when $1 = ''replace'' then $2 when $1 = ''add'' then coalesce(%I,0) + greatest($2,1) else greatest(coalesce(%I,0), $2) end, last_played_at = now() where user_id = $3 and game_title = $4',
      v_metric, v_metric, v_metric
    ) using v_mode, v_value, v_uid, v_game_title;
  end if;

  v_new_awards := public.award_ready_achievements(v_uid, v_game_title);

  select to_jsonb(gs) || jsonb_build_object('new_awards', v_new_awards, 'aswc_pending_goal_signals', case when v_game_title='A Small World Cup' and v_metric='goals' then (select pending_signals from public.aswc_goal_signal_pairs where user_id=v_uid) else null end)
  into v_stat
  from public.game_stats gs
  where gs.user_id = v_uid and gs.game_title = v_game_title;

  return coalesce(v_stat, '{}'::jsonb);
end;
$$;

grant execute on function public.record_game_metric(text, text, integer, text) to authenticated;

-- ============================================================
-- 10) Health check + realtime
-- ============================================================

drop function if exists public.blank_space_v95_healthcheck();

create function public.blank_space_v95_healthcheck()
returns table(check_name text, result text)
language sql
security definer
set search_path = public
as $$
  select 'admin_rank', coalesce((select rank from public.profiles where lower(trim(username))=lower('Admin') limit 1), 'missing')
  union all select 'owner_count', count(*)::text from public.profiles where lower(coalesce(rank,'member'))='owner'
  union all select 'warning_rows', count(*)::text from public.user_warnings
  union all select 'aswc_goal_targets', coalesce(string_agg(target::text, ',' order by target), '') from public.achievement_catalog where game_title='A Small World Cup' and stat='goals'
  union all select 'status', 'OK - v95 owner rank, warnings, flags, chat safety, timed-all messages, owner chat view, and ASWC double-goal guard installed';
$$;

grant execute on function public.blank_space_v95_healthcheck() to anon, authenticated;

do $$ begin
  begin alter publication supabase_realtime add table public.admin_user_messages; exception when others then null; end;
  begin alter publication supabase_realtime add table public.user_warnings; exception when others then null; end;
end $$;

select pg_notify('pgrst', 'reload schema');
select * from public.blank_space_v95_healthcheck();

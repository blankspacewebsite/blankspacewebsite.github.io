-- Blank Space v148 NEW SUPABASE PROJECT CORE SETUP - FIXED ORDER
-- Paste this into the SQL Editor of your NEW Supabase project and click Run.
-- This creates the base tables/functions needed for accounts, username login,
-- profiles, public leaderboard, suggestions, friends, and basic chat support.
--
-- After this runs, you can also run later feature SQL files already included in
-- this ZIP if a specific advanced feature needs its table/function repaired.
-- v148 fix: defines is_blank_space_admin() before any RLS policy uses it.

create extension if not exists pgcrypto;

-- Updated-at helper used by multiple tables.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Main public profiles table.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  login_email text unique,
  display_name text,
  avatar_url text,
  points integer not null default 0,
  rank text not null default 'member',
  equipped_icon text,
  equipped_icon_id text,
  equipped_achievement_id text,
  equipped_banner_id text,
  equipped_banner_name text,
  equipped_banner_gradient text,
  true_member boolean not null default false,
  friend_requests_enabled boolean not null default true,
  muted_until timestamptz,
  banned_until timestamptz,
  chat_banned boolean not null default false,
  last_seen_at timestamptz,
  active_device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles add column if not exists username text unique;
alter table public.profiles add column if not exists login_email text unique;
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists points integer not null default 0;
alter table public.profiles add column if not exists rank text not null default 'member';
alter table public.profiles add column if not exists equipped_icon text;
alter table public.profiles add column if not exists equipped_icon_id text;
alter table public.profiles add column if not exists equipped_achievement_id text;
alter table public.profiles add column if not exists equipped_banner_id text;
alter table public.profiles add column if not exists equipped_banner_name text;
alter table public.profiles add column if not exists equipped_banner_gradient text;
alter table public.profiles add column if not exists true_member boolean not null default false;
alter table public.profiles add column if not exists friend_requests_enabled boolean not null default true;
alter table public.profiles add column if not exists muted_until timestamptz;
alter table public.profiles add column if not exists banned_until timestamptz;
alter table public.profiles add column if not exists chat_banned boolean not null default false;
alter table public.profiles add column if not exists last_seen_at timestamptz;
alter table public.profiles add column if not exists active_device_id text;
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

create unique index if not exists profiles_username_lower_unique on public.profiles (lower(username));
create unique index if not exists profiles_login_email_lower_unique on public.profiles (lower(login_email));

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_public" on public.profiles;
create policy "profiles_select_public" on public.profiles
for select to anon, authenticated using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
for insert to authenticated with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

-- Admin/owner table. Owner/Admin usernames are also treated as staff automatically.
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text,
  role text not null default 'admin',
  created_at timestamptz not null default now()
);

create or replace function public.is_blank_space_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users a
    where a.user_id = auth.uid()
  )
  or exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and (
        lower(coalesce(p.username,'')) in ('owner','admin')
        or lower(coalesce(p.rank,'')) in ('owner','admin','manager')
      )
  );
$$;

grant execute on function public.is_blank_space_admin() to anon, authenticated;

alter table public.admin_users enable row level security;

drop policy if exists "admin_users_select_staff" on public.admin_users;
create policy "admin_users_select_staff" on public.admin_users
for select to authenticated using (user_id = auth.uid() or public.is_blank_space_admin());

-- Username lookup for the no-email login system.
create or replace function public.lookup_login_email(username_input text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.login_email
  from public.profiles p
  where lower(p.username) = lower(trim(username_input))
  limit 1;
$$;

grant execute on function public.lookup_login_email(text) to anon, authenticated;

-- Public leaderboard used by the website.
create or replace function public.get_public_leaderboard(max_rows integer default 100)
returns table(
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  points integer,
  equipped_icon text,
  equipped_icon_id text,
  equipped_achievement_id text,
  rank text,
  true_member boolean,
  last_seen_at timestamptz,
  equipped_banner_id text,
  equipped_banner_name text,
  equipped_banner_gradient text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.username, p.display_name, p.avatar_url, coalesce(p.points,0),
         p.equipped_icon, p.equipped_icon_id, p.equipped_achievement_id,
         p.rank, p.true_member, p.last_seen_at,
         p.equipped_banner_id, p.equipped_banner_name, p.equipped_banner_gradient
  from public.profiles p
  order by coalesce(p.points,0) desc, lower(coalesce(p.username,'')) asc
  limit greatest(1, least(coalesce(max_rows,100), 10000));
$$;

grant execute on function public.get_public_leaderboard(integer) to anon, authenticated;

-- Presence helpers.
create or replace function public.touch_presence()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles set last_seen_at = now() where id = auth.uid();
end;
$$;

grant execute on function public.touch_presence() to authenticated;

create or replace function public.touch_presence_v138()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.touch_presence();
end;
$$;

grant execute on function public.touch_presence_v138() to authenticated;

-- Suggestions.
create table if not exists public.suggestions (
  id bigint generated by default as identity primary key,
  user_id uuid references public.profiles(id) on delete set null,
  username text,
  title text,
  body text,
  suggestion text,
  status text not null default 'pending',
  admin_comment text,
  points_awarded integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint suggestion_status_check check (status in ('pending','approved','denied','rejected'))
);

alter table public.suggestions enable row level security;

drop policy if exists "suggestions_select_public_or_own_or_admin" on public.suggestions;
create policy "suggestions_select_public_or_own_or_admin" on public.suggestions
for select to anon, authenticated
using (status = 'approved' or user_id = auth.uid() or public.is_blank_space_admin());

drop policy if exists "suggestions_insert_authenticated" on public.suggestions;
create policy "suggestions_insert_authenticated" on public.suggestions
for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "suggestions_admin_update" on public.suggestions;
create policy "suggestions_admin_update" on public.suggestions
for update to authenticated using (public.is_blank_space_admin()) with check (public.is_blank_space_admin());

drop policy if exists "suggestions_admin_delete" on public.suggestions;
create policy "suggestions_admin_delete" on public.suggestions
for delete to authenticated using (public.is_blank_space_admin());

drop trigger if exists suggestions_set_updated_at on public.suggestions;
create trigger suggestions_set_updated_at
before update on public.suggestions
for each row execute function public.set_updated_at();

-- Friends and direct messages.
create table if not exists public.friends (
  id bigint generated by default as identity primary key,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friends_no_self check (requester_id <> receiver_id),
  constraint friends_status_check check (status in ('pending','accepted','declined'))
);

create unique index if not exists friends_one_connection_per_pair
on public.friends ((least(requester_id, receiver_id)), (greatest(requester_id, receiver_id)));

alter table public.friends enable row level security;

drop policy if exists "friends_select_own" on public.friends;
create policy "friends_select_own" on public.friends
for select to authenticated using (requester_id = auth.uid() or receiver_id = auth.uid() or public.is_blank_space_admin());

drop policy if exists "friends_insert_own_pending" on public.friends;
create policy "friends_insert_own_pending" on public.friends
for insert to authenticated with check (requester_id = auth.uid() and status = 'pending');

drop policy if exists "friends_update_receiver_response" on public.friends;
create policy "friends_update_receiver_response" on public.friends
for update to authenticated using (receiver_id = auth.uid() or public.is_blank_space_admin()) with check (receiver_id = auth.uid() or public.is_blank_space_admin());

drop policy if exists "friends_delete_own" on public.friends;
create policy "friends_delete_own" on public.friends
for delete to authenticated using (requester_id = auth.uid() or receiver_id = auth.uid() or public.is_blank_space_admin());

drop trigger if exists friends_set_updated_at on public.friends;
create trigger friends_set_updated_at before update on public.friends
for each row execute function public.set_updated_at();

create table if not exists public.friend_messages (
  id bigint generated by default as identity primary key,
  friendship_id bigint not null references public.friends(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text,
  image_url text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists friend_messages_friendship_created_idx on public.friend_messages(friendship_id, created_at desc);

alter table public.friend_messages enable row level security;

drop policy if exists "friend_messages_select_own_friendship" on public.friend_messages;
create policy "friend_messages_select_own_friendship" on public.friend_messages
for select to authenticated using (
  exists(select 1 from public.friends f where f.id = friendship_id and (f.requester_id = auth.uid() or f.receiver_id = auth.uid() or public.is_blank_space_admin()))
);

drop policy if exists "friend_messages_insert_own_friendship" on public.friend_messages;
create policy "friend_messages_insert_own_friendship" on public.friend_messages
for insert to authenticated with check (
  sender_id = auth.uid()
  and exists(select 1 from public.friends f where f.id = friendship_id and f.status = 'accepted' and (f.requester_id = auth.uid() or f.receiver_id = auth.uid()))
);

drop policy if exists "friend_messages_delete_sender_or_admin" on public.friend_messages;
create policy "friend_messages_delete_sender_or_admin" on public.friend_messages
for delete to authenticated using (sender_id = auth.uid() or public.is_blank_space_admin());

-- Pins.
create table if not exists public.chat_pins (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friendship_id bigint not null references public.friends(id) on delete cascade,
  pinned_at timestamptz not null default now(),
  primary key(user_id, friendship_id)
);

alter table public.chat_pins enable row level security;

drop policy if exists "chat_pins_own" on public.chat_pins;
create policy "chat_pins_own" on public.chat_pins
for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Storage bucket for avatars/images. Ignore the error if Storage is unavailable.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Helpful aliases used by later patches.
create or replace function public.get_public_leaderboard_v138(max_rows integer default 10000)
returns table(
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  points integer,
  equipped_icon text,
  equipped_icon_id text,
  equipped_achievement_id text,
  rank text,
  true_member boolean,
  last_seen_at timestamptz,
  equipped_banner_id text,
  equipped_banner_name text,
  equipped_banner_gradient text
)
language sql
stable
security definer
set search_path = public
as $$
  select * from public.get_public_leaderboard(max_rows);
$$;

grant execute on function public.get_public_leaderboard_v138(integer) to anon, authenticated;

-- If you create the username Owner, the website will treat it as owner/admin automatically.

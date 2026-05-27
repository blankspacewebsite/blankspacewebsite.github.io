-- Blank Space v78 Supabase update
-- Run this in Supabase SQL Editor before testing v78.
-- Adds username/password login support while keeping the same profiles, suggestions, friends, points, and leaderboard data.
-- Safe to run more than once.

alter table public.profiles
  add column if not exists login_email text;

create unique index if not exists profiles_login_email_lower_unique
on public.profiles (lower(login_email))
where login_email is not null;

-- Lets the website find the hidden Supabase Auth email for a username before the user is signed in.
-- Returns:
--   null = username does not exist
--   ''   = username exists, but it is an older browser-only account without password login yet
--   email text = username can sign in with password
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

comment on column public.profiles.login_email is 'Hidden Supabase Auth email used for Blank Space username/password login. Do not show this to users.';

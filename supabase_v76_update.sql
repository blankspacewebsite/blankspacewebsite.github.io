-- Blank Space v76 Supabase update
-- Run this in Supabase SQL Editor before testing v76.
-- Adds a public leaderboard function that hides admin accounts from the leaderboard.
-- It is safe to run more than once.

create or replace function public.get_public_leaderboard(max_rows integer default 100)
returns table (
  id uuid,
  username text,
  avatar_url text,
  points integer
)
language sql
security definer
set search_path = public
as $$
  select p.id, p.username, p.avatar_url, p.points
  from public.profiles p
  where not exists (
    select 1
    from public.admin_users a
    where a.user_id = p.id
  )
  order by p.points desc, lower(p.username) asc
  limit greatest(1, least(coalesce(max_rows, 100), 100));
$$;

grant execute on function public.get_public_leaderboard(integer) to anon, authenticated;

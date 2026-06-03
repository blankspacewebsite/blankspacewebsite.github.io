-- Blank Space v150 ACCOUNT PROFILE REPAIR
-- Run this in your NEW Supabase project if the website says you signed in
-- but still shows Create Account / Sign In and says "Choose a username".
-- It safely creates/repairs the missing public.profiles row for the current signed-in user.

create or replace function public.ensure_own_profile_v150(
  p_username text,
  p_login_email text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_profile public.profiles;
begin
  if v_uid is null then
    raise exception 'Sign in first.';
  end if;

  p_username := trim(coalesce(p_username, ''));
  if p_username !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'Username must be 3-20 letters, numbers, or underscores.';
  end if;

  if exists (
    select 1 from public.profiles
    where lower(username) = lower(p_username)
      and id <> v_uid
  ) then
    raise exception 'That username is already taken. Try another one.';
  end if;

  select email into v_email from auth.users where id = v_uid;
  p_login_email := nullif(trim(coalesce(p_login_email, '')), '');
  if p_login_email is null then
    p_login_email := v_email;
  end if;
  if p_login_email is null then
    p_login_email := 'blankspace-' || replace(v_uid::text, '-', '') || '@blankspaceweb.com';
  end if;

  insert into public.profiles (id, username, login_email, rank, points)
  values (
    v_uid,
    p_username,
    p_login_email,
    case when lower(p_username) = 'owner' then 'owner' else 'member' end,
    0
  )
  on conflict (id) do update set
    username = excluded.username,
    login_email = coalesce(public.profiles.login_email, excluded.login_email),
    rank = case when lower(excluded.username) = 'owner' then 'owner' else public.profiles.rank end,
    updated_at = now()
  returning * into v_profile;

  if lower(p_username) = 'owner' then
    insert into public.admin_users (user_id, username, role)
    values (v_uid, p_username, 'owner')
    on conflict (user_id) do update set username = excluded.username, role = 'owner';
  end if;

  return v_profile;
end;
$$;

grant execute on function public.ensure_own_profile_v150(text, text) to authenticated;

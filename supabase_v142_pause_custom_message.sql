-- Blank Space v142: custom Pause Website message
-- Run this in Supabase, then upload Blank Space v142.zip.

create table if not exists public.website_pause_v136 (
  id integer primary key default 1 check (id = 1),
  paused boolean not null default false,
  except_ranks text[] not null default array[]::text[],
  pause_message text not null default 'This website has been temporarily paused by the owner.',
  updated_at timestamptz default now(),
  updated_by uuid
);

alter table public.website_pause_v136 add column if not exists pause_message text not null default 'This website has been temporarily paused by the owner.';
alter table public.website_pause_v136 add column if not exists updated_at timestamptz default now();
alter table public.website_pause_v136 add column if not exists updated_by uuid;

insert into public.website_pause_v136(id, paused, except_ranks, pause_message)
values (1, false, array[]::text[], 'This website has been temporarily paused by the owner.')
on conflict (id) do nothing;

alter table public.website_pause_v136 enable row level security;

drop policy if exists "blank_space_website_pause_select" on public.website_pause_v136;

create policy "blank_space_website_pause_select"
on public.website_pause_v136
for select
to anon, authenticated
using (true);

grant select on public.website_pause_v136 to anon, authenticated;

create or replace function public.set_website_pause_v142(
  p_paused boolean,
  p_except_ranks text[] default array[]::text[],
  p_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allowed text[] := array['testers','managers','admins'];
  v_clean text[];
  v_message text;
begin
  if not public.blank_space_is_owner() then
    raise exception 'Owner only.';
  end if;

  select coalesce(array_agg(x), array[]::text[])
  into v_clean
  from unnest(coalesce(p_except_ranks, array[]::text[])) as x
  where x = any(v_allowed);

  v_message := nullif(trim(coalesce(p_message, '')), '');
  if v_message is null then
    v_message := 'This website has been temporarily paused by the owner.';
  end if;

  update public.website_pause_v136
  set paused = coalesce(p_paused, false),
      except_ranks = v_clean,
      pause_message = v_message,
      updated_at = now(),
      updated_by = auth.uid()
  where id = 1;

  return (
    select jsonb_build_object(
      'paused', paused,
      'except_ranks', except_ranks,
      'pause_message', pause_message,
      'updated_at', updated_at
    )
    from public.website_pause_v136
    where id = 1
  );
end;
$$;

grant execute on function public.set_website_pause_v142(boolean,text[],text) to authenticated;

create or replace function public.get_website_pause_status_v142()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'paused', paused,
        'except_ranks', except_ranks,
        'pause_message', coalesce(nullif(trim(pause_message), ''), 'This website has been temporarily paused by the owner.'),
        'updated_at', updated_at
      )
      from public.website_pause_v136
      where id = 1
    ),
    '{"paused":false,"except_ranks":[],"pause_message":"This website has been temporarily paused by the owner."}'::jsonb
  );
$$;

grant execute on function public.get_website_pause_status_v142() to anon, authenticated;

drop function if exists public.set_website_pause(boolean,text[]);
drop function if exists public.set_website_pause(boolean,text[],text);

create function public.set_website_pause(
  p_paused boolean,
  p_except_ranks text[] default array[]::text[],
  p_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.set_website_pause_v142(p_paused, p_except_ranks, p_message);
end;
$$;

grant execute on function public.set_website_pause(boolean,text[],text) to authenticated;

create or replace function public.get_website_pause_status()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.get_website_pause_status_v142();
$$;

grant execute on function public.get_website_pause_status() to anon, authenticated;

select pg_notify('pgrst','reload schema');

select 'OK - custom Pause Website message installed' as status;

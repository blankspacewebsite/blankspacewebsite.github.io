-- Blank Space v110: Owner-controlled Settings label
-- Paste this whole file into Supabase SQL Editor and click Run.
--
-- What this does:
-- - Adds a site_settings table for simple global website settings.
-- - Adds get_blank_space_setting_v110(key) for the website to read the label.
-- - Adds set_blank_space_setting_v110(key, value) so Owner/Admin can change it in Owner Panel.
-- - Currently supports only: block_protection_label
--
-- This does NOT change points, achievements, chats, accounts, ranks, or games.

alter table public.profiles add column if not exists rank text default 'member';
alter table public.profiles add column if not exists username text;

create table if not exists public.site_settings (
  key text primary key,
  value text not null,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.site_settings add column if not exists value text;
alter table public.site_settings add column if not exists updated_by uuid references public.profiles(id) on delete set null;
alter table public.site_settings add column if not exists updated_at timestamptz not null default now();

insert into public.site_settings(key, value)
values ('block_protection_label', 'Block Protection')
on conflict (key) do nothing;

create or replace function public.is_blank_space_owner_or_admin_v110()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and (
        lower(trim(coalesce(p.rank, 'member'))) in ('owner', 'admin')
        or lower(trim(coalesce(p.username, ''))) in ('owner', 'admin')
      )
  );
$$;

grant execute on function public.is_blank_space_owner_or_admin_v110() to anon, authenticated;

drop function if exists public.get_blank_space_setting_v110(text);

create function public.get_blank_space_setting_v110(p_key text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := lower(trim(coalesce(p_key, '')));
  v_value text;
begin
  if v_key <> 'block_protection_label' then
    raise exception 'Unsupported setting key.';
  end if;

  select value
  into v_value
  from public.site_settings
  where key = v_key;

  return coalesce(nullif(trim(v_value), ''), 'Block Protection');
end;
$$;

grant execute on function public.get_blank_space_setting_v110(text) to anon, authenticated;

drop function if exists public.set_blank_space_setting_v110(text, text);

create function public.set_blank_space_setting_v110(
  p_key text,
  p_value text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := lower(trim(coalesce(p_key, '')));
  v_value text := trim(regexp_replace(coalesce(p_value, ''), '\s+', ' ', 'g'));
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;

  if not public.is_blank_space_owner_or_admin_v110() then
    raise exception 'Owner/Admin only.';
  end if;

  if v_key <> 'block_protection_label' then
    raise exception 'Unsupported setting key.';
  end if;

  if v_value = '' then
    v_value := 'Block Protection';
  end if;

  v_value := left(v_value, 40);

  insert into public.site_settings(key, value, updated_by, updated_at)
  values (v_key, v_value, auth.uid(), now())
  on conflict (key) do update set
    value = excluded.value,
    updated_by = excluded.updated_by,
    updated_at = now();

  return v_value;
end;
$$;

grant execute on function public.set_blank_space_setting_v110(text, text) to authenticated;

drop function if exists public.blank_space_v110_healthcheck();

create function public.blank_space_v110_healthcheck()
returns table(check_name text, result text)
language sql
security definer
set search_path = public
as $$
  select 'site_settings_table',
         case when to_regclass('public.site_settings') is not null then 'installed' else 'missing' end

  union all

  select 'block_protection_label',
         public.get_blank_space_setting_v110('block_protection_label')

  union all

  select 'get_function',
         case when to_regprocedure('public.get_blank_space_setting_v110(text)') is not null then 'installed' else 'missing' end

  union all

  select 'set_function',
         case when to_regprocedure('public.set_blank_space_setting_v110(text, text)') is not null then 'installed' else 'missing' end

  union all

  select 'status',
         'OK - Blank Space v110 setting label system installed';
$$;

grant execute on function public.blank_space_v110_healthcheck() to anon, authenticated;

select pg_notify('pgrst', 'reload schema');

select * from public.blank_space_v110_healthcheck();

-- Done.

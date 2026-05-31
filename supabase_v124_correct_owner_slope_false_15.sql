-- Blank Space v124: Correct Owner's false Slope 15 back to score 1
-- Run this ONLY if Owner got score 1 but the website saved/awarded score 15.
-- It removes Owner's Slope achievements, subtracts only those Slope reward points, and sets Owner's Slope best_score to 1.

do $$
declare
  v_user_id uuid;
  v_points_to_remove integer := 0;
  v_removed integer := 0;
begin
  select id into v_user_id
  from public.profiles
  where lower(trim(username)) = lower(trim('Owner'))
  order by created_at asc nulls last, id asc
  limit 1;

  if v_user_id is null then
    raise exception 'Could not find username Owner.';
  end if;

  select coalesce(sum(greatest(0, coalesce(ua.reward_points,0))),0)::integer
  into v_points_to_remove
  from public.user_achievements ua
  where ua.user_id = v_user_id
    and (
      lower(coalesce(ua.game_title,'')) = 'slope'
      or lower(coalesce(ua.achievement_id,'')) like 'slope%'
      or ua.achievement_id in (
        select achievement_id from public.achievement_catalog
        where lower(coalesce(game_title,'')) = 'slope'
           or lower(coalesce(achievement_id,'')) like 'slope%'
      )
    );

  delete from public.user_achievements ua
  where ua.user_id = v_user_id
    and (
      lower(coalesce(ua.game_title,'')) = 'slope'
      or lower(coalesce(ua.achievement_id,'')) like 'slope%'
      or ua.achievement_id in (
        select achievement_id from public.achievement_catalog
        where lower(coalesce(game_title,'')) = 'slope'
           or lower(coalesce(achievement_id,'')) like 'slope%'
      )
    );

  get diagnostics v_removed = row_count;

  perform set_config('blank_space.allow_points_update','1',true);
  update public.profiles
  set points = greatest(0, coalesce(points,0) - v_points_to_remove)
  where id = v_user_id;

  insert into public.game_stats(user_id, game_title, best_score, play_count, first_played_at, last_played_at)
  values(v_user_id, 'Slope', 1, 1, now(), now())
  on conflict(user_id, game_title) do update set
    best_score = 1,
    last_played_at = now();

  raise notice 'Corrected Owner Slope. Removed % Slope achievements, subtracted % wrong Slope points, set Slope best_score to 1.',
    v_removed, v_points_to_remove;
end $$;

select
  p.username,
  p.points,
  coalesce(gs.best_score,0) as slope_best_score,
  (
    select count(*)
    from public.user_achievements ua
    where ua.user_id = p.id
      and (
        lower(coalesce(ua.game_title,'')) = 'slope'
        or lower(coalesce(ua.achievement_id,'')) like 'slope%'
      )
  ) as remaining_slope_achievements
from public.profiles p
left join public.game_stats gs on gs.user_id = p.id and gs.game_title = 'Slope'
where lower(trim(p.username)) = lower(trim('Owner'))
order by p.created_at asc nulls last, p.id asc
limit 1;

-- Done.

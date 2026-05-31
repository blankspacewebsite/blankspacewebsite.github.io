-- Blank Space v123: Correct Owner's Slope score to at least 33
-- Paste this into Supabase SQL Editor and click Run.
--
-- Use this because Owner got 33 in Slope but the old tracker only saved 15.
-- This does NOT reset anything.
-- This does NOT remove points.
-- It only sets Owner's saved Slope best_score to at least 33 and awards missing Slope achievements.

do $$
declare
  v_user_id uuid;
  v_result jsonb;
begin
  select id
  into v_user_id
  from public.profiles
  where lower(trim(username)) = lower(trim('Owner'))
  order by created_at asc nulls last, id asc
  limit 1;

  if v_user_id is null then
    raise exception 'Could not find username Owner.';
  end if;

  insert into public.game_stats(user_id, game_title, best_score, play_count, first_played_at, last_played_at)
  values(v_user_id, 'Slope', 33, 1, now(), now())
  on conflict(user_id, game_title) do update set
    best_score = greatest(coalesce(public.game_stats.best_score,0), 33),
    play_count = coalesce(public.game_stats.play_count,0) + 1,
    last_played_at = now();

  if to_regprocedure('public.award_slope_achievements_for_user(uuid)') is not null then
    v_result := public.award_slope_achievements_for_user(v_user_id);
  elsif to_regprocedure('public.award_ready_achievements(uuid, text)') is not null then
    v_result := jsonb_build_object('new_awards', public.award_ready_achievements(v_user_id, 'Slope'));
  else
    raise exception 'Achievement award function is missing. Run v121 SQL first.';
  end if;

  raise notice 'Owner Slope corrected to at least 33. Award result: %', v_result;
end $$;

select
  p.username,
  p.points as points_after_missing_rewards,
  gs.best_score as slope_best_score,
  (
    select count(*)
    from public.user_achievements ua
    where ua.user_id = p.id
      and (
        lower(coalesce(ua.game_title,'')) = 'slope'
        or lower(coalesce(ua.achievement_id,'')) like 'slope%'
      )
  ) as slope_achievements_now
from public.profiles p
left join public.game_stats gs
  on gs.user_id = p.id
 and gs.game_title = 'Slope'
where lower(trim(p.username)) = lower(trim('Owner'))
order by p.created_at asc nulls last, p.id asc
limit 1;

-- Done.

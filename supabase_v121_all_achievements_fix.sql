-- Blank Space v121: all achievements repair
-- Paste this whole file into Supabase SQL Editor and click Run.
--
-- This does NOT reset anyone.
-- This does NOT remove anyone's points.
--
-- What this fixes:
-- - Syncs all 240 website achievement cards into Supabase.
-- - Restores record_game_metric for every game, not only Slope.
-- - Makes one metric save unlock every matching achievement.
-- - Keeps A Small World Cup double-signal protection.
-- - Backfills missing achievements from already-saved stats.
-- - Adds admin_test_game_metric(username, game, metric, value, mode) for testing.

alter table public.profiles add column if not exists points integer default 0;
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists rank text default 'member';

update public.profiles set points = 0 where points is null;
update public.profiles set rank = 'member' where rank is null or trim(rank) = '';

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
  hits integer default 0,
  snake_mode text
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
alter table public.game_stats add column if not exists snake_mode text;

do $$
begin
  if exists (select 1 from public.game_stats group by user_id, game_title having count(*) > 1) then
    create temp table tmp_v121_game_stats on commit drop as
    select user_id, game_title,
      sum(coalesce(play_count,0))::integer play_count,
      sum(coalesce(play_seconds,0))::integer play_seconds,
      min(coalesce(first_played_at, now())) first_played_at,
      max(coalesce(last_played_at, now())) last_played_at,
      max(coalesce(best_score,0))::integer best_score,
      max(coalesce(goals,0))::integer goals,
      max(coalesce(wins,0))::integer wins,
      max(coalesce(fish_caught,0))::integer fish_caught,
      max(coalesce(money_earned,0))::integer money_earned,
      max(coalesce(checks,0))::integer checks,
      max(coalesce(checkmates,0))::integer checkmates,
      max(coalesce(merges,0))::integer merges,
      max(coalesce(best_level,0))::integer best_level,
      max(coalesce(hits,0))::integer hits,
      max(snake_mode) snake_mode
    from public.game_stats
    group by user_id, game_title;

    delete from public.game_stats;

    insert into public.game_stats(user_id, game_title, play_count, play_seconds, first_played_at, last_played_at, best_score, goals, wins, fish_caught, money_earned, checks, checkmates, merges, best_level, hits, snake_mode)
    select user_id, game_title, play_count, play_seconds, first_played_at, last_played_at, best_score, goals, wins, fish_caught, money_earned, checks, checkmates, merges, best_level, hits, snake_mode
    from tmp_v121_game_stats;
  end if;
end $$;

create unique index if not exists game_stats_user_game_unique on public.game_stats(user_id, game_title);

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

delete from public.achievement_catalog a
using (
  select achievement_id, min(ctid) keep_ctid
  from public.achievement_catalog
  where achievement_id is not null
  group by achievement_id
  having count(*) > 1
) d
where a.achievement_id = d.achievement_id
  and a.ctid <> d.keep_ctid;

create unique index if not exists achievement_catalog_id_unique on public.achievement_catalog(achievement_id);

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

do $$
begin
  if exists (select 1 from public.user_achievements group by user_id, achievement_id having count(*) > 1) then
    create temp table tmp_v121_user_ach on commit drop as
    select distinct on(user_id, achievement_id)
      user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at
    from public.user_achievements
    order by user_id, achievement_id, earned_at asc nulls last;

    delete from public.user_achievements;

    insert into public.user_achievements(user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at)
    select user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at
    from tmp_v121_user_ach;
  end if;
end $$;

create unique index if not exists user_achievements_user_achievement_unique on public.user_achievements(user_id, achievement_id);

create table if not exists public.aswc_goal_signal_pairs (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  pending_signals integer not null default 0,
  updated_at timestamptz not null default now()
);

delete from public.achievement_catalog
where game_title = any(array['A Small World Cup','Basket Random','Chess-AI','Chess.com','Drive Mad','Google Doodle Baseball','Google Snake','Run 3','Slope','Stick Merge','Tiny Fishing'])
   or achievement_id = any(array['a_small_world_cup_goals_100_41','a_small_world_cup_goals_10_34','a_small_world_cup_goals_150_42','a_small_world_cup_goals_15_35','a_small_world_cup_goals_200_43','a_small_world_cup_goals_20_36','a_small_world_cup_goals_300_44','a_small_world_cup_goals_30_37','a_small_world_cup_goals_40_38','a_small_world_cup_goals_50_39','a_small_world_cup_goals_5_33','a_small_world_cup_goals_75_40','a_small_world_cup_wins_10_50','a_small_world_cup_wins_13_202','a_small_world_cup_wins_14_222','a_small_world_cup_wins_15_51','a_small_world_cup_wins_1_45','a_small_world_cup_wins_20_52','a_small_world_cup_wins_2_46','a_small_world_cup_wins_30_53','a_small_world_cup_wins_3_47','a_small_world_cup_wins_50_54','a_small_world_cup_wins_5_48','a_small_world_cup_wins_8_49','basket_random_best_score_100_63','basket_random_best_score_10_56','basket_random_best_score_150_64','basket_random_best_score_15_57','basket_random_best_score_20_58','basket_random_best_score_30_59','basket_random_best_score_315_193','basket_random_best_score_330_203','basket_random_best_score_345_213','basket_random_best_score_360_223','basket_random_best_score_375_233','basket_random_best_score_390_243','basket_random_best_score_40_60','basket_random_best_score_50_61','basket_random_best_score_5_55','basket_random_best_score_75_62','basket_random_wins_10_68','basket_random_wins_15_69','basket_random_wins_1_65','basket_random_wins_25_70','basket_random_wins_3_66','basket_random_wins_40_71','basket_random_wins_5_67','basket_random_wins_60_72','chess_ai_checkmates_10_106','chess_ai_checkmates_11_195','chess_ai_checkmates_12_205','chess_ai_checkmates_13_225','chess_ai_checkmates_14_245','chess_ai_checkmates_15_107','chess_ai_checkmates_1_102','chess_ai_checkmates_25_108','chess_ai_checkmates_2_103','chess_ai_checkmates_3_104','chess_ai_checkmates_50_109','chess_ai_checkmates_5_105','chess_ai_checks_100_101','chess_ai_checks_10_96','chess_ai_checks_15_97','chess_ai_checks_1_93','chess_ai_checks_25_98','chess_ai_checks_3_94','chess_ai_checks_40_99','chess_ai_checks_5_95','chess_ai_checks_60_100','chess_ai_wins_10_114','chess_ai_wins_15_115','chess_ai_wins_1_110','chess_ai_wins_25_116','chess_ai_wins_2_111','chess_ai_wins_3_112','chess_ai_wins_50_117','chess_ai_wins_5_113','chess_com_wins_10_191','chess_com_wins_1_188','chess_com_wins_25_192','chess_com_wins_3_189','chess_com_wins_5_190','drive_mad_best_level_100_159','drive_mad_best_level_10_151','drive_mad_best_level_15_152','drive_mad_best_level_20_153','drive_mad_best_level_25_154','drive_mad_best_level_30_155','drive_mad_best_level_3_149','drive_mad_best_level_40_156','drive_mad_best_level_50_157','drive_mad_best_level_55_197','drive_mad_best_level_5_150','drive_mad_best_level_60_207','drive_mad_best_level_65_227','drive_mad_best_level_70_247','drive_mad_best_level_75_158','google_doodle_baseball_best_score_100_183','google_doodle_baseball_best_score_10_179','google_doodle_baseball_best_score_150_184','google_doodle_baseball_best_score_200_185','google_doodle_baseball_best_score_25_180','google_doodle_baseball_best_score_300_186','google_doodle_baseball_best_score_500_187','google_doodle_baseball_best_score_50_181','google_doodle_baseball_best_score_75_182','google_doodle_baseball_hits_100_176','google_doodle_baseball_hits_10_171','google_doodle_baseball_hits_150_177','google_doodle_baseball_hits_20_172','google_doodle_baseball_hits_210_199','google_doodle_baseball_hits_220_209','google_doodle_baseball_hits_230_219','google_doodle_baseball_hits_240_229','google_doodle_baseball_hits_250_178','google_doodle_baseball_hits_260_249','google_doodle_baseball_hits_35_173','google_doodle_baseball_hits_50_174','google_doodle_baseball_hits_5_170','google_doodle_baseball_hits_75_175','google_snake_best_score_100_8','google_snake_best_score_10_0','google_snake_best_score_125_9','google_snake_best_score_150_10','google_snake_best_score_175_11','google_snake_best_score_200_12','google_snake_best_score_20_1','google_snake_best_score_250_13','google_snake_best_score_300_14','google_snake_best_score_30_2','google_snake_best_score_350_15','google_snake_best_score_400_16','google_snake_best_score_40_3','google_snake_best_score_500_17','google_snake_best_score_50_4','google_snake_best_score_550_200','google_snake_best_score_575_210','google_snake_best_score_600_220','google_snake_best_score_60_5','google_snake_best_score_625_230','google_snake_best_score_650_240','google_snake_best_score_75_6','google_snake_best_score_90_7','run_3_best_level_100_169','run_3_best_level_10_162','run_3_best_level_15_163','run_3_best_level_20_164','run_3_best_level_30_165','run_3_best_level_3_160','run_3_best_level_40_166','run_3_best_level_50_167','run_3_best_level_55_198','run_3_best_level_5_161','run_3_best_level_60_208','run_3_best_level_65_228','run_3_best_level_70_248','run_3_best_level_75_168','slope_best_score_1000_31','slope_best_score_100_21','slope_best_score_1100_201','slope_best_score_1150_211','slope_best_score_1200_221','slope_best_score_1250_231','slope_best_score_1250_32','slope_best_score_125_22','slope_best_score_1300_241','slope_best_score_150_23','slope_best_score_200_24','slope_best_score_250_25','slope_best_score_25_18','slope_best_score_300_26','slope_best_score_400_27','slope_best_score_500_28','slope_best_score_50_19','slope_best_score_650_29','slope_best_score_75_20','slope_best_score_800_30','stick_merge_best_level_10_136','stick_merge_best_level_12_137','stick_merge_best_level_15_138','stick_merge_best_level_20_139','stick_merge_best_level_25_140','stick_merge_best_level_2_129','stick_merge_best_level_3_130','stick_merge_best_level_4_131','stick_merge_best_level_5_132','stick_merge_best_level_6_133','stick_merge_best_level_7_134','stick_merge_best_level_8_135','stick_merge_best_score_10000_147','stick_merge_best_score_1000_144','stick_merge_best_score_100_141','stick_merge_best_score_2000_145','stick_merge_best_score_25000_148','stick_merge_best_score_250_142','stick_merge_best_score_5000_146','stick_merge_best_score_500_143','stick_merge_merges_100_124','stick_merge_merges_10_119','stick_merge_merges_150_125','stick_merge_merges_20_120','stick_merge_merges_250_126','stick_merge_merges_35_121','stick_merge_merges_400_127','stick_merge_merges_410_196','stick_merge_merges_430_206','stick_merge_merges_450_216','stick_merge_merges_470_226','stick_merge_merges_490_236','stick_merge_merges_50_122','stick_merge_merges_510_246','stick_merge_merges_5_118','stick_merge_merges_600_128','stick_merge_merges_75_123','tiny_fishing_fish_caught_1000_83','tiny_fishing_fish_caught_100_77','tiny_fishing_fish_caught_10_73','tiny_fishing_fish_caught_150_78','tiny_fishing_fish_caught_200_79','tiny_fishing_fish_caught_25_74','tiny_fishing_fish_caught_300_80','tiny_fishing_fish_caught_500_81','tiny_fishing_fish_caught_50_75','tiny_fishing_fish_caught_525_194','tiny_fishing_fish_caught_550_204','tiny_fishing_fish_caught_575_214','tiny_fishing_fish_caught_600_224','tiny_fishing_fish_caught_625_234','tiny_fishing_fish_caught_650_244','tiny_fishing_fish_caught_750_82','tiny_fishing_fish_caught_75_76','tiny_fishing_money_earned_10000_90','tiny_fishing_money_earned_1000_87','tiny_fishing_money_earned_100_84','tiny_fishing_money_earned_25000_91','tiny_fishing_money_earned_2500_88','tiny_fishing_money_earned_250_85','tiny_fishing_money_earned_50000_92','tiny_fishing_money_earned_5000_89','tiny_fishing_money_earned_500_86']);

insert into public.achievement_catalog(
  achievement_id, title, description, icon, game_title, stat, target, reward_points, difficulty
)
values
('google_snake_best_score_10_0','10 points','Get 10 points in Google Snake','🐍','Google Snake','best_score',10,2,'not_so_hard'),
('google_snake_best_score_20_1','20 points','Get 20 points in Google Snake','🐍','Google Snake','best_score',20,5,'medium'),
('google_snake_best_score_30_2','30 points','Get 30 points in Google Snake','🐍','Google Snake','best_score',30,5,'medium'),
('google_snake_best_score_40_3','40 points','Get 40 points in Google Snake','🐍','Google Snake','best_score',40,5,'medium'),
('google_snake_best_score_50_4','50 points','Get 50 points in Google Snake','🐍','Google Snake','best_score',50,5,'medium'),
('google_snake_best_score_60_5','60 points','Get 60 points in Google Snake','🐍','Google Snake','best_score',60,10,'hard'),
('google_snake_best_score_75_6','75 points','Get 75 points in Google Snake','🐍','Google Snake','best_score',75,10,'hard'),
('google_snake_best_score_90_7','90 points','Get 90 points in Google Snake','🐍','Google Snake','best_score',90,10,'hard'),
('google_snake_best_score_100_8','100 points','Get 100 points in Google Snake','🐍','Google Snake','best_score',100,10,'hard'),
('google_snake_best_score_125_9','125 points','Get 125 points in Google Snake','🐍','Google Snake','best_score',125,10,'hard'),
('google_snake_best_score_150_10','150 points','Get 150 points in Google Snake','🐍','Google Snake','best_score',150,10,'hard'),
('google_snake_best_score_175_11','175 points','Get 175 points in Google Snake','🐍','Google Snake','best_score',175,20,'crazy'),
('google_snake_best_score_200_12','200 points','Get 200 points in Google Snake','🐍','Google Snake','best_score',200,20,'crazy'),
('google_snake_best_score_250_13','250 points','Get 250 points in Google Snake','🐍','Google Snake','best_score',250,20,'crazy'),
('google_snake_best_score_300_14','300 points','Get 300 points in Google Snake','🐍','Google Snake','best_score',300,20,'crazy'),
('google_snake_best_score_350_15','350 points','Get 350 points in Google Snake','🐍','Google Snake','best_score',350,20,'crazy'),
('google_snake_best_score_400_16','400 points','Get 400 points in Google Snake','🐍','Google Snake','best_score',400,20,'crazy'),
('google_snake_best_score_500_17','500 points','Get 500 points in Google Snake','🐍','Google Snake','best_score',500,20,'crazy'),
('slope_best_score_25_18','Get 5 points in Slope','Get 5 points in one Slope round','🟢','Slope','best_score',5,2,'easy'),
('slope_best_score_50_19','Get 10 points in Slope','Get 10 points in one Slope round','🟢','Slope','best_score',10,2,'easy'),
('slope_best_score_75_20','Get 15 points in Slope','Get 15 points in one Slope round','🟢','Slope','best_score',15,2,'easy'),
('slope_best_score_100_21','Get 20 points in Slope','Get 20 points in one Slope round','🟢','Slope','best_score',20,2,'easy'),
('slope_best_score_125_22','Get 30 points in Slope','Get 30 points in one Slope round','🟢','Slope','best_score',30,3,'medium'),
('slope_best_score_150_23','Get 40 points in Slope','Get 40 points in one Slope round','🟢','Slope','best_score',40,3,'medium'),
('slope_best_score_200_24','Get 50 points in Slope','Get 50 points in one Slope round','🟢','Slope','best_score',50,3,'medium'),
('slope_best_score_250_25','Get 60 points in Slope','Get 60 points in one Slope round','🟢','Slope','best_score',60,3,'medium'),
('slope_best_score_300_26','Get 75 points in Slope','Get 75 points in one Slope round','🟢','Slope','best_score',75,5,'hard'),
('slope_best_score_400_27','Get 90 points in Slope','Get 90 points in one Slope round','🟢','Slope','best_score',90,5,'hard'),
('slope_best_score_500_28','Get 110 points in Slope','Get 110 points in one Slope round','🟢','Slope','best_score',110,5,'hard'),
('slope_best_score_650_29','Get 130 points in Slope','Get 130 points in one Slope round','🟢','Slope','best_score',130,5,'hard'),
('slope_best_score_800_30','Get 150 points in Slope','Get 150 points in one Slope round','🟢','Slope','best_score',150,10,'crazy'),
('slope_best_score_1000_31','Get 175 points in Slope','Get 175 points in one Slope round','🟢','Slope','best_score',175,10,'crazy'),
('slope_best_score_1250_32','Get 200 points in Slope','Get 200 points in one Slope round','🟢','Slope','best_score',200,10,'crazy'),
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
('a_small_world_cup_goals_300_44','300 total goals','Score 300 total goals in A Small World Cup','⚽','A Small World Cup','goals',300,20,'crazy'),
('a_small_world_cup_wins_1_45','Win the World Cup 1 time(s)','Win the World Cup 1 time(s)','🏆','A Small World Cup','wins',1,2,'not_so_hard'),
('a_small_world_cup_wins_2_46','Win the World Cup 2 time(s)','Win the World Cup 2 time(s)','🏆','A Small World Cup','wins',2,5,'medium'),
('a_small_world_cup_wins_3_47','Win the World Cup 3 time(s)','Win the World Cup 3 time(s)','🏆','A Small World Cup','wins',3,5,'medium'),
('a_small_world_cup_wins_5_48','Win the World Cup 5 time(s)','Win the World Cup 5 time(s)','🏆','A Small World Cup','wins',5,5,'medium'),
('a_small_world_cup_wins_8_49','Win the World Cup 8 time(s)','Win the World Cup 8 time(s)','🏆','A Small World Cup','wins',8,10,'hard'),
('a_small_world_cup_wins_10_50','Win the World Cup 10 time(s)','Win the World Cup 10 time(s)','🏆','A Small World Cup','wins',10,10,'hard'),
('a_small_world_cup_wins_15_51','Win the World Cup 15 time(s)','Win the World Cup 15 time(s)','🏆','A Small World Cup','wins',15,10,'hard'),
('a_small_world_cup_wins_20_52','Win the World Cup 20 time(s)','Win the World Cup 20 time(s)','🏆','A Small World Cup','wins',20,20,'crazy'),
('a_small_world_cup_wins_30_53','Win the World Cup 30 time(s)','Win the World Cup 30 time(s)','🏆','A Small World Cup','wins',30,20,'crazy'),
('a_small_world_cup_wins_50_54','Win the World Cup 50 time(s)','Win the World Cup 50 time(s)','🏆','A Small World Cup','wins',50,20,'crazy'),
('basket_random_best_score_5_55','5 points','Score 5 points in Basket Random','🏀','Basket Random','best_score',5,2,'not_so_hard'),
('basket_random_best_score_10_56','10 points','Score 10 points in Basket Random','🏀','Basket Random','best_score',10,2,'not_so_hard'),
('basket_random_best_score_15_57','15 points','Score 15 points in Basket Random','🏀','Basket Random','best_score',15,5,'medium'),
('basket_random_best_score_20_58','20 points','Score 20 points in Basket Random','🏀','Basket Random','best_score',20,5,'medium'),
('basket_random_best_score_30_59','30 points','Score 30 points in Basket Random','🏀','Basket Random','best_score',30,5,'medium'),
('basket_random_best_score_40_60','40 points','Score 40 points in Basket Random','🏀','Basket Random','best_score',40,5,'medium'),
('basket_random_best_score_50_61','50 points','Score 50 points in Basket Random','🏀','Basket Random','best_score',50,5,'medium'),
('basket_random_best_score_75_62','75 points','Score 75 points in Basket Random','🏀','Basket Random','best_score',75,10,'hard'),
('basket_random_best_score_100_63','100 points','Score 100 points in Basket Random','🏀','Basket Random','best_score',100,10,'hard'),
('basket_random_best_score_150_64','150 points','Score 150 points in Basket Random','🏀','Basket Random','best_score',150,10,'hard'),
('basket_random_wins_1_65','Win 1 Basket Random match(es)','Win 1 Basket Random match(es)','🥇','Basket Random','wins',1,2,'not_so_hard'),
('basket_random_wins_3_66','Win 3 Basket Random match(es)','Win 3 Basket Random match(es)','🥇','Basket Random','wins',3,5,'medium'),
('basket_random_wins_5_67','Win 5 Basket Random match(es)','Win 5 Basket Random match(es)','🥇','Basket Random','wins',5,5,'medium'),
('basket_random_wins_10_68','Win 10 Basket Random match(es)','Win 10 Basket Random match(es)','🥇','Basket Random','wins',10,10,'hard'),
('basket_random_wins_15_69','Win 15 Basket Random match(es)','Win 15 Basket Random match(es)','🥇','Basket Random','wins',15,10,'hard'),
('basket_random_wins_25_70','Win 25 Basket Random match(es)','Win 25 Basket Random match(es)','🥇','Basket Random','wins',25,20,'crazy'),
('basket_random_wins_40_71','Win 40 Basket Random match(es)','Win 40 Basket Random match(es)','🥇','Basket Random','wins',40,20,'crazy'),
('basket_random_wins_60_72','Win 60 Basket Random match(es)','Win 60 Basket Random match(es)','🥇','Basket Random','wins',60,20,'crazy'),
('tiny_fishing_fish_caught_10_73','Catch 10 fish','Catch 10 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',10,2,'not_so_hard'),
('tiny_fishing_fish_caught_25_74','Catch 25 fish','Catch 25 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',25,5,'medium'),
('tiny_fishing_fish_caught_50_75','Catch 50 fish','Catch 50 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',50,5,'medium'),
('tiny_fishing_fish_caught_75_76','Catch 75 fish','Catch 75 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',75,10,'hard'),
('tiny_fishing_fish_caught_100_77','Catch 100 fish','Catch 100 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',100,10,'hard'),
('tiny_fishing_fish_caught_150_78','Catch 150 fish','Catch 150 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',150,10,'hard'),
('tiny_fishing_fish_caught_200_79','Catch 200 fish','Catch 200 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',200,20,'crazy'),
('tiny_fishing_fish_caught_300_80','Catch 300 fish','Catch 300 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',300,20,'crazy'),
('tiny_fishing_fish_caught_500_81','Catch 500 fish','Catch 500 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',500,20,'crazy'),
('tiny_fishing_fish_caught_750_82','Catch 750 fish','Catch 750 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',750,20,'crazy'),
('tiny_fishing_fish_caught_1000_83','Catch 1000 fish','Catch 1000 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',1000,20,'crazy'),
('tiny_fishing_money_earned_100_84','Earn $100','Earn $100 in Tiny Fishing','💰','Tiny Fishing','money_earned',100,10,'hard'),
('tiny_fishing_money_earned_250_85','Earn $250','Earn $250 in Tiny Fishing','💰','Tiny Fishing','money_earned',250,20,'crazy'),
('tiny_fishing_money_earned_500_86','Earn $500','Earn $500 in Tiny Fishing','💰','Tiny Fishing','money_earned',500,20,'crazy'),
('tiny_fishing_money_earned_1000_87','Earn $1000','Earn $1000 in Tiny Fishing','💰','Tiny Fishing','money_earned',1000,20,'crazy'),
('tiny_fishing_money_earned_2500_88','Earn $2500','Earn $2500 in Tiny Fishing','💰','Tiny Fishing','money_earned',2500,20,'crazy'),
('tiny_fishing_money_earned_5000_89','Earn $5000','Earn $5000 in Tiny Fishing','💰','Tiny Fishing','money_earned',5000,20,'crazy'),
('tiny_fishing_money_earned_10000_90','Earn $10000','Earn $10000 in Tiny Fishing','💰','Tiny Fishing','money_earned',10000,20,'crazy'),
('tiny_fishing_money_earned_25000_91','Earn $25000','Earn $25000 in Tiny Fishing','💰','Tiny Fishing','money_earned',25000,20,'crazy'),
('tiny_fishing_money_earned_50000_92','Earn $50000','Earn $50000 in Tiny Fishing','💰','Tiny Fishing','money_earned',50000,20,'crazy'),
('chess_ai_checks_1_93','Put the bot','Put the bot in check 1 time(s)','♟️','Chess-AI','checks',1,2,'not_so_hard'),
('chess_ai_checks_3_94','Put the bot','Put the bot in check 3 time(s)','♟️','Chess-AI','checks',3,2,'not_so_hard'),
('chess_ai_checks_5_95','Put the bot','Put the bot in check 5 time(s)','♟️','Chess-AI','checks',5,2,'not_so_hard'),
('chess_ai_checks_10_96','Put the bot','Put the bot in check 10 time(s)','♟️','Chess-AI','checks',10,2,'not_so_hard'),
('chess_ai_checks_15_97','Put the bot','Put the bot in check 15 time(s)','♟️','Chess-AI','checks',15,5,'medium'),
('chess_ai_checks_25_98','Put the bot','Put the bot in check 25 time(s)','♟️','Chess-AI','checks',25,5,'medium'),
('chess_ai_checks_40_99','Put the bot','Put the bot in check 40 time(s)','♟️','Chess-AI','checks',40,5,'medium'),
('chess_ai_checks_60_100','Put the bot','Put the bot in check 60 time(s)','♟️','Chess-AI','checks',60,10,'hard'),
('chess_ai_checks_100_101','Put the bot','Put the bot in check 100 time(s)','♟️','Chess-AI','checks',100,10,'hard'),
('chess_ai_checkmates_1_102','Checkmate the bot 1 time(s)','Checkmate the bot 1 time(s)','♚','Chess-AI','checkmates',1,2,'not_so_hard'),
('chess_ai_checkmates_2_103','Checkmate the bot 2 time(s)','Checkmate the bot 2 time(s)','♚','Chess-AI','checkmates',2,5,'medium'),
('chess_ai_checkmates_3_104','Checkmate the bot 3 time(s)','Checkmate the bot 3 time(s)','♚','Chess-AI','checkmates',3,5,'medium'),
('chess_ai_checkmates_5_105','Checkmate the bot 5 time(s)','Checkmate the bot 5 time(s)','♚','Chess-AI','checkmates',5,5,'medium'),
('chess_ai_checkmates_10_106','Checkmate the bot 10 time(s)','Checkmate the bot 10 time(s)','♚','Chess-AI','checkmates',10,10,'hard'),
('chess_ai_checkmates_15_107','Checkmate the bot 15 time(s)','Checkmate the bot 15 time(s)','♚','Chess-AI','checkmates',15,10,'hard'),
('chess_ai_checkmates_25_108','Checkmate the bot 25 time(s)','Checkmate the bot 25 time(s)','♚','Chess-AI','checkmates',25,20,'crazy'),
('chess_ai_checkmates_50_109','Checkmate the bot 50 time(s)','Checkmate the bot 50 time(s)','♚','Chess-AI','checkmates',50,20,'crazy'),
('chess_ai_wins_1_110','Beat the chess bot 1 time(s)','Beat the chess bot 1 time(s)','♛','Chess-AI','wins',1,2,'not_so_hard'),
('chess_ai_wins_2_111','Beat the chess bot 2 time(s)','Beat the chess bot 2 time(s)','♛','Chess-AI','wins',2,5,'medium'),
('chess_ai_wins_3_112','Beat the chess bot 3 time(s)','Beat the chess bot 3 time(s)','♛','Chess-AI','wins',3,5,'medium'),
('chess_ai_wins_5_113','Beat the chess bot 5 time(s)','Beat the chess bot 5 time(s)','♛','Chess-AI','wins',5,5,'medium'),
('chess_ai_wins_10_114','Beat the chess bot 10 time(s)','Beat the chess bot 10 time(s)','♛','Chess-AI','wins',10,10,'hard'),
('chess_ai_wins_15_115','Beat the chess bot 15 time(s)','Beat the chess bot 15 time(s)','♛','Chess-AI','wins',15,10,'hard'),
('chess_ai_wins_25_116','Beat the chess bot 25 time(s)','Beat the chess bot 25 time(s)','♛','Chess-AI','wins',25,20,'crazy'),
('chess_ai_wins_50_117','Beat the chess bot 50 time(s)','Beat the chess bot 50 time(s)','♛','Chess-AI','wins',50,20,'crazy'),
('stick_merge_merges_5_118','Merge weapons 5 time(s)','Merge weapons 5 time(s) in Stick Merge','🔫','Stick Merge','merges',5,2,'not_so_hard'),
('stick_merge_merges_10_119','Merge weapons 10 time(s)','Merge weapons 10 time(s) in Stick Merge','🔫','Stick Merge','merges',10,2,'not_so_hard'),
('stick_merge_merges_20_120','Merge weapons 20 time(s)','Merge weapons 20 time(s) in Stick Merge','🔫','Stick Merge','merges',20,5,'medium'),
('stick_merge_merges_35_121','Merge weapons 35 time(s)','Merge weapons 35 time(s) in Stick Merge','🔫','Stick Merge','merges',35,5,'medium'),
('stick_merge_merges_50_122','Merge weapons 50 time(s)','Merge weapons 50 time(s) in Stick Merge','🔫','Stick Merge','merges',50,5,'medium'),
('stick_merge_merges_75_123','Merge weapons 75 time(s)','Merge weapons 75 time(s) in Stick Merge','🔫','Stick Merge','merges',75,10,'hard'),
('stick_merge_merges_100_124','Merge weapons 100 time(s)','Merge weapons 100 time(s) in Stick Merge','🔫','Stick Merge','merges',100,10,'hard'),
('stick_merge_merges_150_125','Merge weapons 150 time(s)','Merge weapons 150 time(s) in Stick Merge','🔫','Stick Merge','merges',150,10,'hard'),
('stick_merge_merges_250_126','Merge weapons 250 time(s)','Merge weapons 250 time(s) in Stick Merge','🔫','Stick Merge','merges',250,20,'crazy'),
('stick_merge_merges_400_127','Merge weapons 400 time(s)','Merge weapons 400 time(s) in Stick Merge','🔫','Stick Merge','merges',400,20,'crazy'),
('stick_merge_merges_600_128','Merge weapons 600 time(s)','Merge weapons 600 time(s) in Stick Merge','🔫','Stick Merge','merges',600,20,'crazy'),
('stick_merge_best_level_2_129','Reach weapon level 2','Reach weapon level 2 in Stick Merge','🧪','Stick Merge','best_level',2,2,'not_so_hard'),
('stick_merge_best_level_3_130','Reach weapon level 3','Reach weapon level 3 in Stick Merge','🧪','Stick Merge','best_level',3,2,'not_so_hard'),
('stick_merge_best_level_4_131','Reach weapon level 4','Reach weapon level 4 in Stick Merge','🧪','Stick Merge','best_level',4,2,'not_so_hard'),
('stick_merge_best_level_5_132','Reach weapon level 5','Reach weapon level 5 in Stick Merge','🧪','Stick Merge','best_level',5,2,'not_so_hard'),
('stick_merge_best_level_6_133','Reach weapon level 6','Reach weapon level 6 in Stick Merge','🧪','Stick Merge','best_level',6,2,'not_so_hard'),
('stick_merge_best_level_7_134','Reach weapon level 7','Reach weapon level 7 in Stick Merge','🧪','Stick Merge','best_level',7,2,'not_so_hard'),
('stick_merge_best_level_8_135','Reach weapon level 8','Reach weapon level 8 in Stick Merge','🧪','Stick Merge','best_level',8,2,'not_so_hard'),
('stick_merge_best_level_10_136','Reach weapon level 10','Reach weapon level 10 in Stick Merge','🧪','Stick Merge','best_level',10,2,'not_so_hard'),
('stick_merge_best_level_12_137','Reach weapon level 12','Reach weapon level 12 in Stick Merge','🧪','Stick Merge','best_level',12,5,'medium'),
('stick_merge_best_level_15_138','Reach weapon level 15','Reach weapon level 15 in Stick Merge','🧪','Stick Merge','best_level',15,5,'medium'),
('stick_merge_best_level_20_139','Reach weapon level 20','Reach weapon level 20 in Stick Merge','🧪','Stick Merge','best_level',20,5,'medium'),
('stick_merge_best_level_25_140','Reach weapon level 25','Reach weapon level 25 in Stick Merge','🧪','Stick Merge','best_level',25,5,'medium'),
('stick_merge_best_score_100_141','100','Score 100 in Stick Merge','💥','Stick Merge','best_score',100,10,'hard'),
('stick_merge_best_score_250_142','250','Score 250 in Stick Merge','💥','Stick Merge','best_score',250,20,'crazy'),
('stick_merge_best_score_500_143','500','Score 500 in Stick Merge','💥','Stick Merge','best_score',500,20,'crazy'),
('stick_merge_best_score_1000_144','1000','Score 1000 in Stick Merge','💥','Stick Merge','best_score',1000,20,'crazy'),
('stick_merge_best_score_2000_145','2000','Score 2000 in Stick Merge','💥','Stick Merge','best_score',2000,20,'crazy'),
('stick_merge_best_score_5000_146','5000','Score 5000 in Stick Merge','💥','Stick Merge','best_score',5000,20,'crazy'),
('stick_merge_best_score_10000_147','10000','Score 10000 in Stick Merge','💥','Stick Merge','best_score',10000,20,'crazy'),
('stick_merge_best_score_25000_148','25000','Score 25000 in Stick Merge','💥','Stick Merge','best_score',25000,20,'crazy'),
('drive_mad_best_level_3_149','Reach level 3','Reach level 3 in Drive Mad','🚗','Drive Mad','best_level',3,2,'not_so_hard'),
('drive_mad_best_level_5_150','Reach level 5','Reach level 5 in Drive Mad','🚗','Drive Mad','best_level',5,2,'not_so_hard'),
('drive_mad_best_level_10_151','Reach level 10','Reach level 10 in Drive Mad','🚗','Drive Mad','best_level',10,2,'not_so_hard'),
('drive_mad_best_level_15_152','Reach level 15','Reach level 15 in Drive Mad','🚗','Drive Mad','best_level',15,5,'medium'),
('drive_mad_best_level_20_153','Reach level 20','Reach level 20 in Drive Mad','🚗','Drive Mad','best_level',20,5,'medium'),
('drive_mad_best_level_25_154','Reach level 25','Reach level 25 in Drive Mad','🚗','Drive Mad','best_level',25,5,'medium'),
('drive_mad_best_level_30_155','Reach level 30','Reach level 30 in Drive Mad','🚗','Drive Mad','best_level',30,5,'medium'),
('drive_mad_best_level_40_156','Reach level 40','Reach level 40 in Drive Mad','🚗','Drive Mad','best_level',40,5,'medium'),
('drive_mad_best_level_50_157','Reach level 50','Reach level 50 in Drive Mad','🚗','Drive Mad','best_level',50,5,'medium'),
('drive_mad_best_level_75_158','Reach level 75','Reach level 75 in Drive Mad','🚗','Drive Mad','best_level',75,10,'hard'),
('drive_mad_best_level_100_159','Reach level 100','Reach level 100 in Drive Mad','🚗','Drive Mad','best_level',100,10,'hard'),
('run_3_best_level_3_160','Reach level 3','Reach level 3 in Run 3','🌌','Run 3','best_level',3,2,'not_so_hard'),
('run_3_best_level_5_161','Reach level 5','Reach level 5 in Run 3','🌌','Run 3','best_level',5,2,'not_so_hard'),
('run_3_best_level_10_162','Reach level 10','Reach level 10 in Run 3','🌌','Run 3','best_level',10,2,'not_so_hard'),
('run_3_best_level_15_163','Reach level 15','Reach level 15 in Run 3','🌌','Run 3','best_level',15,5,'medium'),
('run_3_best_level_20_164','Reach level 20','Reach level 20 in Run 3','🌌','Run 3','best_level',20,5,'medium'),
('run_3_best_level_30_165','Reach level 30','Reach level 30 in Run 3','🌌','Run 3','best_level',30,5,'medium'),
('run_3_best_level_40_166','Reach level 40','Reach level 40 in Run 3','🌌','Run 3','best_level',40,5,'medium'),
('run_3_best_level_50_167','Reach level 50','Reach level 50 in Run 3','🌌','Run 3','best_level',50,5,'medium'),
('run_3_best_level_75_168','Reach level 75','Reach level 75 in Run 3','🌌','Run 3','best_level',75,10,'hard'),
('run_3_best_level_100_169','Reach level 100','Reach level 100 in Run 3','🌌','Run 3','best_level',100,10,'hard'),
('google_doodle_baseball_hits_5_170','5 hits','Get 5 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',5,2,'not_so_hard'),
('google_doodle_baseball_hits_10_171','10 hits','Get 10 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',10,2,'not_so_hard'),
('google_doodle_baseball_hits_20_172','20 hits','Get 20 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',20,5,'medium'),
('google_doodle_baseball_hits_35_173','35 hits','Get 35 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',35,5,'medium'),
('google_doodle_baseball_hits_50_174','50 hits','Get 50 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',50,5,'medium'),
('google_doodle_baseball_hits_75_175','75 hits','Get 75 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',75,10,'hard'),
('google_doodle_baseball_hits_100_176','100 hits','Get 100 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',100,10,'hard'),
('google_doodle_baseball_hits_150_177','150 hits','Get 150 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',150,10,'hard'),
('google_doodle_baseball_hits_250_178','250 hits','Get 250 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',250,20,'crazy'),
('google_doodle_baseball_best_score_10_179','10','Score 10 in Google Doodle Baseball','🌭','Google Doodle Baseball','best_score',10,2,'not_so_hard'),
('google_doodle_baseball_best_score_25_180','25','Score 25 in Google Doodle Baseball','🌭','Google Doodle Baseball','best_score',25,5,'medium'),
('google_doodle_baseball_best_score_50_181','50','Score 50 in Google Doodle Baseball','🌭','Google Doodle Baseball','best_score',50,5,'medium'),
('google_doodle_baseball_best_score_75_182','75','Score 75 in Google Doodle Baseball','🌭','Google Doodle Baseball','best_score',75,10,'hard'),
('google_doodle_baseball_best_score_100_183','100','Score 100 in Google Doodle Baseball','🌭','Google Doodle Baseball','best_score',100,10,'hard'),
('google_doodle_baseball_best_score_150_184','150','Score 150 in Google Doodle Baseball','🌭','Google Doodle Baseball','best_score',150,10,'hard'),
('google_doodle_baseball_best_score_200_185','200','Score 200 in Google Doodle Baseball','🌭','Google Doodle Baseball','best_score',200,20,'crazy'),
('google_doodle_baseball_best_score_300_186','300','Score 300 in Google Doodle Baseball','🌭','Google Doodle Baseball','best_score',300,20,'crazy'),
('google_doodle_baseball_best_score_500_187','500','Score 500 in Google Doodle Baseball','🌭','Google Doodle Baseball','best_score',500,20,'crazy'),
('chess_com_wins_1_188','Win 1 Chess.com game(s)','Win 1 Chess.com game(s)','♜','Chess.com','wins',1,2,'not_so_hard'),
('chess_com_wins_3_189','Win 3 Chess.com game(s)','Win 3 Chess.com game(s)','♜','Chess.com','wins',3,5,'medium'),
('chess_com_wins_5_190','Win 5 Chess.com game(s)','Win 5 Chess.com game(s)','♜','Chess.com','wins',5,5,'medium'),
('chess_com_wins_10_191','Win 10 Chess.com game(s)','Win 10 Chess.com game(s)','♜','Chess.com','wins',10,10,'hard'),
('chess_com_wins_25_192','Win 25 Chess.com game(s)','Win 25 Chess.com game(s)','♜','Chess.com','wins',25,20,'crazy'),
('basket_random_best_score_315_193','Score 315 points in Basket Random','Score 315 points in Basket Random','🏀','Basket Random','best_score',315,20,'crazy'),
('tiny_fishing_fish_caught_525_194','Catch 525 fish in Tiny Fishing','Catch 525 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',525,20,'crazy'),
('chess_ai_checkmates_11_195','Checkmate the bot 11 times','Checkmate the bot 11 times','♛','Chess-AI','checkmates',11,10,'hard'),
('stick_merge_merges_410_196','Merge weapons 410 times in Stick Merge','Merge weapons 410 times in Stick Merge','🔫','Stick Merge','merges',410,20,'crazy'),
('drive_mad_best_level_55_197','Reach level 55 in Drive Mad','Reach level 55 in Drive Mad','🚗','Drive Mad','best_level',55,5,'medium'),
('run_3_best_level_55_198','Reach level 55 in Run 3','Reach level 55 in Run 3','🌌','Run 3','best_level',55,5,'medium'),
('google_doodle_baseball_hits_210_199','Get 210 hits in Google Doodle Baseball','Get 210 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',210,20,'crazy'),
('google_snake_best_score_550_200','Get 550 points in Google Snake','Get 550 points in Google Snake','🍎','Google Snake','best_score',550,20,'crazy'),
('slope_best_score_1100_201','Get 225 points in Slope','Get 225 points in one Slope round','🟢','Slope','best_score',225,10,'crazy'),
('a_small_world_cup_wins_13_202','Win the World Cup 13 times','Win the World Cup 13 times','🏆','A Small World Cup','wins',13,10,'hard'),
('basket_random_best_score_330_203','Score 330 points in Basket Random','Score 330 points in Basket Random','🏀','Basket Random','best_score',330,20,'crazy'),
('tiny_fishing_fish_caught_550_204','Catch 550 fish in Tiny Fishing','Catch 550 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',550,20,'crazy'),
('chess_ai_checkmates_12_205','Checkmate the bot 12 times','Checkmate the bot 12 times','♛','Chess-AI','checkmates',12,10,'hard'),
('stick_merge_merges_430_206','Merge weapons 430 times in Stick Merge','Merge weapons 430 times in Stick Merge','🔫','Stick Merge','merges',430,20,'crazy'),
('drive_mad_best_level_60_207','Reach level 60 in Drive Mad','Reach level 60 in Drive Mad','🚗','Drive Mad','best_level',60,5,'medium'),
('run_3_best_level_60_208','Reach level 60 in Run 3','Reach level 60 in Run 3','🌌','Run 3','best_level',60,5,'medium'),
('google_doodle_baseball_hits_220_209','Get 220 hits in Google Doodle Baseball','Get 220 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',220,20,'crazy'),
('google_snake_best_score_575_210','Get 575 points in Google Snake','Get 575 points in Google Snake','🍎','Google Snake','best_score',575,20,'crazy'),
('slope_best_score_1150_211','Get 250 points in Slope','Get 250 points in one Slope round','🟢','Slope','best_score',250,15,'crazy'),
('basket_random_best_score_345_213','Score 345 points in Basket Random','Score 345 points in Basket Random','🏀','Basket Random','best_score',345,20,'crazy'),
('tiny_fishing_fish_caught_575_214','Catch 575 fish in Tiny Fishing','Catch 575 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',575,20,'crazy'),
('stick_merge_merges_450_216','Merge weapons 450 times in Stick Merge','Merge weapons 450 times in Stick Merge','🔫','Stick Merge','merges',450,20,'crazy'),
('google_doodle_baseball_hits_230_219','Get 230 hits in Google Doodle Baseball','Get 230 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',230,20,'crazy'),
('google_snake_best_score_600_220','Get 600 points in Google Snake','Get 600 points in Google Snake','🍎','Google Snake','best_score',600,20,'crazy'),
('slope_best_score_1200_221','Get 275 points in Slope','Get 275 points in one Slope round','🟢','Slope','best_score',275,15,'crazy'),
('a_small_world_cup_wins_14_222','Win the World Cup 14 times','Win the World Cup 14 times','🏆','A Small World Cup','wins',14,10,'hard'),
('basket_random_best_score_360_223','Score 360 points in Basket Random','Score 360 points in Basket Random','🏀','Basket Random','best_score',360,20,'crazy'),
('tiny_fishing_fish_caught_600_224','Catch 600 fish in Tiny Fishing','Catch 600 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',600,20,'crazy'),
('chess_ai_checkmates_13_225','Checkmate the bot 13 times','Checkmate the bot 13 times','♛','Chess-AI','checkmates',13,10,'hard'),
('stick_merge_merges_470_226','Merge weapons 470 times in Stick Merge','Merge weapons 470 times in Stick Merge','🔫','Stick Merge','merges',470,20,'crazy'),
('drive_mad_best_level_65_227','Reach level 65 in Drive Mad','Reach level 65 in Drive Mad','🚗','Drive Mad','best_level',65,5,'medium'),
('run_3_best_level_65_228','Reach level 65 in Run 3','Reach level 65 in Run 3','🌌','Run 3','best_level',65,5,'medium'),
('google_doodle_baseball_hits_240_229','Get 240 hits in Google Doodle Baseball','Get 240 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',240,20,'crazy'),
('google_snake_best_score_625_230','Get 625 points in Google Snake','Get 625 points in Google Snake','🍎','Google Snake','best_score',625,20,'crazy'),
('slope_best_score_1250_231','Get 300 points in Slope','Get 300 points in one Slope round','🟢','Slope','best_score',300,15,'crazy'),
('basket_random_best_score_375_233','Score 375 points in Basket Random','Score 375 points in Basket Random','🏀','Basket Random','best_score',375,20,'crazy'),
('tiny_fishing_fish_caught_625_234','Catch 625 fish in Tiny Fishing','Catch 625 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',625,20,'crazy'),
('stick_merge_merges_490_236','Merge weapons 490 times in Stick Merge','Merge weapons 490 times in Stick Merge','🔫','Stick Merge','merges',490,20,'crazy'),
('google_snake_best_score_650_240','Get 650 points in Google Snake','Get 650 points in Google Snake','🍎','Google Snake','best_score',650,20,'crazy'),
('slope_best_score_1300_241','Get 350 points in Slope','Get 350 points in one Slope round','🟢','Slope','best_score',350,15,'crazy'),
('basket_random_best_score_390_243','Score 390 points in Basket Random','Score 390 points in Basket Random','🏀','Basket Random','best_score',390,20,'crazy'),
('tiny_fishing_fish_caught_650_244','Catch 650 fish in Tiny Fishing','Catch 650 fish in Tiny Fishing','🎣','Tiny Fishing','fish_caught',650,20,'crazy'),
('chess_ai_checkmates_14_245','Checkmate the bot 14 times','Checkmate the bot 14 times','♛','Chess-AI','checkmates',14,10,'hard'),
('stick_merge_merges_510_246','Merge weapons 510 times in Stick Merge','Merge weapons 510 times in Stick Merge','🔫','Stick Merge','merges',510,20,'crazy'),
('drive_mad_best_level_70_247','Reach level 70 in Drive Mad','Reach level 70 in Drive Mad','🚗','Drive Mad','best_level',70,5,'medium'),
('run_3_best_level_70_248','Reach level 70 in Run 3','Reach level 70 in Run 3','🌌','Run 3','best_level',70,5,'medium'),
('google_doodle_baseball_hits_260_249','Get 260 hits in Google Doodle Baseball','Get 260 hits in Google Doodle Baseball','⚾','Google Doodle Baseball','hits',260,20,'crazy')
on conflict(achievement_id) do update set
  title = excluded.title,
  description = excluded.description,
  icon = excluded.icon,
  game_title = excluded.game_title,
  stat = excluded.stat,
  target = excluded.target,
  reward_points = excluded.reward_points,
  difficulty = excluded.difficulty;

drop function if exists public.award_ready_achievements(uuid, text);

create function public.award_ready_achievements(p_user_id uuid, p_game_title text default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth uuid := auth.uid();
  v_awards integer := 0;
  v_points integer := 0;
  v_game text := nullif(trim(coalesce(p_game_title,'')), '');
begin
  if p_user_id is null then
    return 0;
  end if;

  if v_auth is not null
     and p_user_id is distinct from v_auth
     and not exists (
       select 1 from public.profiles p
       where p.id = v_auth
         and lower(trim(coalesce(p.rank,'member'))) in ('owner','admin')
     ) then
    raise exception 'Not allowed to award another user.';
  end if;

  if lower(coalesce(v_game,'')) in ('slope','slope game') then v_game := 'Slope'; end if;
  if lower(coalesce(v_game,'')) in ('a-small-world-cup','small world cup','a small world cup') then v_game := 'A Small World Cup'; end if;

  with eligible as (
    select c.*
    from public.achievement_catalog c
    join public.game_stats gs
      on gs.user_id = p_user_id
     and gs.game_title = c.game_title
    left join public.user_achievements ua
      on ua.user_id = p_user_id
     and ua.achievement_id = c.achievement_id
    where ua.achievement_id is null
      and c.achievement_id is not null
      and c.game_title is not null
      and (v_game is null or c.game_title = v_game)
      and (
        case c.stat
          when 'play_count' then coalesce(gs.play_count,0)
          when 'play_seconds' then coalesce(gs.play_seconds,0)
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
          else 0
        end
      ) >= coalesce(c.target,999999999)
  ),
  inserted as (
    insert into public.user_achievements(
      user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at
    )
    select
      p_user_id,
      achievement_id,
      coalesce(nullif(title,''),'Achievement'),
      coalesce(description,''),
      coalesce(nullif(icon,''),'🏆'),
      game_title,
      greatest(0, coalesce(reward_points,0)),
      now()
    from eligible
    on conflict(user_id, achievement_id) do nothing
    returning reward_points
  )
  select count(*)::integer, coalesce(sum(reward_points),0)::integer
  into v_awards, v_points
  from inserted;

  if v_points > 0 then
    perform set_config('blank_space.allow_points_update','1',true);
    update public.profiles
    set points = coalesce(points,0) + v_points
    where id = p_user_id;
  end if;

  return coalesce(v_awards,0);
end;
$$;

grant execute on function public.award_ready_achievements(uuid, text) to authenticated;

drop function if exists public.record_game_progress(text, boolean, integer);

create function public.record_game_progress(
  p_game_title text,
  p_open_event boolean default false,
  p_seconds integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_game text := trim(coalesce(p_game_title,''));
  v_awards integer := 0;
begin
  if v_uid is null then raise exception 'Sign in first.'; end if;
  if v_game = '' then raise exception 'Game title is required.'; end if;
  if lower(v_game) in ('slope','slope game') then v_game := 'Slope'; end if;
  if lower(v_game) in ('a-small-world-cup','small world cup','a small world cup') then v_game := 'A Small World Cup'; end if;

  insert into public.game_stats(user_id, game_title, play_count, play_seconds, first_played_at, last_played_at)
  values(v_uid, v_game, case when coalesce(p_open_event,false) then 1 else 0 end, greatest(0,coalesce(p_seconds,0)), now(), now())
  on conflict(user_id, game_title) do update set
    play_count = coalesce(public.game_stats.play_count,0) + case when coalesce(p_open_event,false) then 1 else 0 end,
    play_seconds = coalesce(public.game_stats.play_seconds,0) + greatest(0,coalesce(p_seconds,0)),
    last_played_at = now();

  v_awards := public.award_ready_achievements(v_uid, v_game);

  return (
    select to_jsonb(gs) || jsonb_build_object('ok', true, 'new_awards', v_awards)
    from public.game_stats gs
    where gs.user_id = v_uid and gs.game_title = v_game
  );
end;
$$;

grant execute on function public.record_game_progress(text, boolean, integer) to authenticated;

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
  v_game text := trim(coalesce(p_game_title,''));
  v_metric text := lower(trim(coalesce(p_metric,'')));
  v_mode text := lower(trim(coalesce(p_mode,'max')));
  v_value integer := greatest(0, coalesce(p_value,0));
  v_awards integer := 0;
  v_pending integer := 0;
  v_total integer := 0;
  v_add integer := 0;
begin
  if v_uid is null then raise exception 'Sign in first.'; end if;
  if v_game = '' then raise exception 'Game title is required.'; end if;

  if lower(v_game) in ('slope','slope game') then v_game := 'Slope'; end if;
  if lower(v_game) in ('a-small-world-cup','small world cup','a small world cup') then v_game := 'A Small World Cup'; end if;
  if v_metric in ('score','best','best-score','bestscore') then v_metric := 'best_score'; end if;

  if v_metric not in ('play_count','play_seconds','best_score','goals','wins','fish_caught','money_earned','checks','checkmates','merges','best_level','hits') then
    raise exception 'Unknown game metric: %', v_metric;
  end if;

  insert into public.game_stats(user_id, game_title, first_played_at, last_played_at)
  values(v_uid, v_game, now(), now())
  on conflict(user_id, game_title) do nothing;

  if v_game = 'A Small World Cup' and v_metric = 'goals' and v_mode in ('add','delta_v93','add_goal_v93','goal_delta') then
    select pending_signals
    into v_pending
    from public.aswc_goal_signal_pairs
    where user_id = v_uid
    for update;

    v_pending := coalesce(v_pending,0);
    v_total := v_pending + greatest(v_value,1);
    v_add := floor(v_total::numeric / 2)::integer;
    v_pending := mod(v_total,2);

    insert into public.aswc_goal_signal_pairs(user_id,pending_signals,updated_at)
    values(v_uid,v_pending,now())
    on conflict(user_id) do update set pending_signals=excluded.pending_signals, updated_at=now();

    update public.game_stats
    set goals = coalesce(goals,0) + v_add,
        last_played_at = now()
    where user_id = v_uid and game_title = v_game;

  elsif v_game = 'A Small World Cup' and v_metric = 'wins' and v_mode in ('add','add_win_v93','win_delta') then
    update public.game_stats
    set wins = coalesce(wins,0) + greatest(v_value,1),
        last_played_at = now()
    where user_id = v_uid and game_title = v_game;

  else
    execute format(
      'update public.game_stats set %I = case when $1 = ''replace'' then $2 when $1 = ''add'' then coalesce(%I,0)+greatest($2,1) else greatest(coalesce(%I,0),$2) end, last_played_at=now() where user_id=$3 and game_title=$4',
      v_metric, v_metric, v_metric
    )
    using v_mode, v_value, v_uid, v_game;
  end if;

  v_awards := public.award_ready_achievements(v_uid, v_game);

  return (
    select to_jsonb(gs) || jsonb_build_object('ok', true, 'new_awards', v_awards)
    from public.game_stats gs
    where gs.user_id = v_uid and gs.game_title = v_game
  );
end;
$$;

grant execute on function public.record_game_metric(text, text, integer, text) to authenticated;

drop function if exists public.record_slope_score(integer);
create function public.record_slope_score(p_score integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.record_game_metric('Slope','best_score',greatest(0,coalesce(p_score,0)),'max');
end;
$$;
grant execute on function public.record_slope_score(integer) to authenticated;

drop function if exists public.report_slope_score(integer);
create function public.report_slope_score(p_score integer)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return public.record_slope_score(p_score);
end;
$$;
grant execute on function public.report_slope_score(integer) to authenticated;

drop function if exists public.submit_slope_score(integer);
create function public.submit_slope_score(p_score integer)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return public.record_slope_score(p_score);
end;
$$;
grant execute on function public.submit_slope_score(integer) to authenticated;

drop function if exists public.award_achievement(text, text, text, text, text, integer);

create function public.award_achievement(
  p_achievement_id text,
  p_title text,
  p_description text,
  p_icon text,
  p_game_title text,
  p_reward_points integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_inserted integer := 0;
begin
  if v_uid is null then raise exception 'Sign in first.'; end if;

  insert into public.user_achievements(user_id, achievement_id, title, description, icon, game_title, reward_points, earned_at)
  values(v_uid, p_achievement_id, coalesce(p_title,'Achievement'), coalesce(p_description,''), coalesce(p_icon,'🏆'), p_game_title, greatest(0,coalesce(p_reward_points,0)), now())
  on conflict(user_id, achievement_id) do nothing;

  get diagnostics v_inserted = row_count;

  if v_inserted > 0 and coalesce(p_reward_points,0) > 0 then
    perform set_config('blank_space.allow_points_update','1',true);
    update public.profiles
    set points = coalesce(points,0) + greatest(0,coalesce(p_reward_points,0))
    where id = v_uid;
  end if;

  return v_inserted > 0;
end;
$$;

grant execute on function public.award_achievement(text, text, text, text, text, integer) to authenticated;

drop function if exists public.admin_test_game_metric(text, text, text, integer, text);

create function public.admin_test_game_metric(
  p_username text,
  p_game_title text,
  p_metric text,
  p_value integer,
  p_mode text default 'max'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := auth.uid();
  v_target uuid;
  v_game text := trim(coalesce(p_game_title,''));
  v_metric text := lower(trim(coalesce(p_metric,'')));
  v_mode text := lower(trim(coalesce(p_mode,'max')));
  v_value integer := greatest(0, coalesce(p_value,0));
  v_awards integer := 0;
begin
  if v_admin is null then raise exception 'Sign in first.'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_admin and lower(trim(coalesce(p.rank,'member'))) in ('owner','admin')) then
    raise exception 'Owner/Admin only.';
  end if;

  select id into v_target
  from public.profiles
  where lower(trim(username)) = lower(trim(coalesce(p_username,'')))
  order by created_at asc nulls last, id asc
  limit 1;

  if v_target is null then raise exception 'User not found.'; end if;

  if lower(v_game) in ('slope','slope game') then v_game := 'Slope'; end if;
  if lower(v_game) in ('a-small-world-cup','small world cup','a small world cup') then v_game := 'A Small World Cup'; end if;
  if v_metric in ('score','best','best-score','bestscore') then v_metric := 'best_score'; end if;

  if v_metric not in ('play_count','play_seconds','best_score','goals','wins','fish_caught','money_earned','checks','checkmates','merges','best_level','hits') then
    raise exception 'Unknown game metric: %', v_metric;
  end if;

  insert into public.game_stats(user_id, game_title, first_played_at, last_played_at)
  values(v_target, v_game, now(), now())
  on conflict(user_id, game_title) do nothing;

  execute format(
    'update public.game_stats set %I = case when $1 = ''replace'' then $2 when $1 = ''add'' then coalesce(%I,0)+greatest($2,1) else greatest(coalesce(%I,0),$2) end, last_played_at=now() where user_id=$3 and game_title=$4',
    v_metric, v_metric, v_metric
  )
  using v_mode, v_value, v_target, v_game;

  v_awards := public.award_ready_achievements(v_target, v_game);

  return (
    select to_jsonb(gs) || jsonb_build_object('ok', true, 'new_awards', v_awards)
    from public.game_stats gs
    where gs.user_id = v_target and gs.game_title = v_game
  );
end;
$$;

grant execute on function public.admin_test_game_metric(text, text, text, integer, text) to authenticated;

drop function if exists public.backfill_all_achievements_v121();

create function public.backfill_all_achievements_v121()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_total integer := 0;
  v_added integer := 0;
begin
  for r in select distinct user_id, game_title from public.game_stats loop
    v_added := public.award_ready_achievements(r.user_id, r.game_title);
    v_total := v_total + coalesce(v_added,0);
  end loop;

  return jsonb_build_object('ok', true, 'achievements_added', v_total);
end;
$$;

select public.backfill_all_achievements_v121() as backfill_result;

drop function if exists public.blank_space_v121_achievements_healthcheck();

create function public.blank_space_v121_achievements_healthcheck()
returns table(check_name text, result text)
language sql
security definer
set search_path = public
as $$
  select 'achievement_catalog_rows', count(*)::text from public.achievement_catalog where achievement_id = any(array['a_small_world_cup_goals_100_41','a_small_world_cup_goals_10_34','a_small_world_cup_goals_150_42','a_small_world_cup_goals_15_35','a_small_world_cup_goals_200_43','a_small_world_cup_goals_20_36','a_small_world_cup_goals_300_44','a_small_world_cup_goals_30_37','a_small_world_cup_goals_40_38','a_small_world_cup_goals_50_39','a_small_world_cup_goals_5_33','a_small_world_cup_goals_75_40','a_small_world_cup_wins_10_50','a_small_world_cup_wins_13_202','a_small_world_cup_wins_14_222','a_small_world_cup_wins_15_51','a_small_world_cup_wins_1_45','a_small_world_cup_wins_20_52','a_small_world_cup_wins_2_46','a_small_world_cup_wins_30_53','a_small_world_cup_wins_3_47','a_small_world_cup_wins_50_54','a_small_world_cup_wins_5_48','a_small_world_cup_wins_8_49','basket_random_best_score_100_63','basket_random_best_score_10_56','basket_random_best_score_150_64','basket_random_best_score_15_57','basket_random_best_score_20_58','basket_random_best_score_30_59','basket_random_best_score_315_193','basket_random_best_score_330_203','basket_random_best_score_345_213','basket_random_best_score_360_223','basket_random_best_score_375_233','basket_random_best_score_390_243','basket_random_best_score_40_60','basket_random_best_score_50_61','basket_random_best_score_5_55','basket_random_best_score_75_62','basket_random_wins_10_68','basket_random_wins_15_69','basket_random_wins_1_65','basket_random_wins_25_70','basket_random_wins_3_66','basket_random_wins_40_71','basket_random_wins_5_67','basket_random_wins_60_72','chess_ai_checkmates_10_106','chess_ai_checkmates_11_195','chess_ai_checkmates_12_205','chess_ai_checkmates_13_225','chess_ai_checkmates_14_245','chess_ai_checkmates_15_107','chess_ai_checkmates_1_102','chess_ai_checkmates_25_108','chess_ai_checkmates_2_103','chess_ai_checkmates_3_104','chess_ai_checkmates_50_109','chess_ai_checkmates_5_105','chess_ai_checks_100_101','chess_ai_checks_10_96','chess_ai_checks_15_97','chess_ai_checks_1_93','chess_ai_checks_25_98','chess_ai_checks_3_94','chess_ai_checks_40_99','chess_ai_checks_5_95','chess_ai_checks_60_100','chess_ai_wins_10_114','chess_ai_wins_15_115','chess_ai_wins_1_110','chess_ai_wins_25_116','chess_ai_wins_2_111','chess_ai_wins_3_112','chess_ai_wins_50_117','chess_ai_wins_5_113','chess_com_wins_10_191','chess_com_wins_1_188','chess_com_wins_25_192','chess_com_wins_3_189','chess_com_wins_5_190','drive_mad_best_level_100_159','drive_mad_best_level_10_151','drive_mad_best_level_15_152','drive_mad_best_level_20_153','drive_mad_best_level_25_154','drive_mad_best_level_30_155','drive_mad_best_level_3_149','drive_mad_best_level_40_156','drive_mad_best_level_50_157','drive_mad_best_level_55_197','drive_mad_best_level_5_150','drive_mad_best_level_60_207','drive_mad_best_level_65_227','drive_mad_best_level_70_247','drive_mad_best_level_75_158','google_doodle_baseball_best_score_100_183','google_doodle_baseball_best_score_10_179','google_doodle_baseball_best_score_150_184','google_doodle_baseball_best_score_200_185','google_doodle_baseball_best_score_25_180','google_doodle_baseball_best_score_300_186','google_doodle_baseball_best_score_500_187','google_doodle_baseball_best_score_50_181','google_doodle_baseball_best_score_75_182','google_doodle_baseball_hits_100_176','google_doodle_baseball_hits_10_171','google_doodle_baseball_hits_150_177','google_doodle_baseball_hits_20_172','google_doodle_baseball_hits_210_199','google_doodle_baseball_hits_220_209','google_doodle_baseball_hits_230_219','google_doodle_baseball_hits_240_229','google_doodle_baseball_hits_250_178','google_doodle_baseball_hits_260_249','google_doodle_baseball_hits_35_173','google_doodle_baseball_hits_50_174','google_doodle_baseball_hits_5_170','google_doodle_baseball_hits_75_175','google_snake_best_score_100_8','google_snake_best_score_10_0','google_snake_best_score_125_9','google_snake_best_score_150_10','google_snake_best_score_175_11','google_snake_best_score_200_12','google_snake_best_score_20_1','google_snake_best_score_250_13','google_snake_best_score_300_14','google_snake_best_score_30_2','google_snake_best_score_350_15','google_snake_best_score_400_16','google_snake_best_score_40_3','google_snake_best_score_500_17','google_snake_best_score_50_4','google_snake_best_score_550_200','google_snake_best_score_575_210','google_snake_best_score_600_220','google_snake_best_score_60_5','google_snake_best_score_625_230','google_snake_best_score_650_240','google_snake_best_score_75_6','google_snake_best_score_90_7','run_3_best_level_100_169','run_3_best_level_10_162','run_3_best_level_15_163','run_3_best_level_20_164','run_3_best_level_30_165','run_3_best_level_3_160','run_3_best_level_40_166','run_3_best_level_50_167','run_3_best_level_55_198','run_3_best_level_5_161','run_3_best_level_60_208','run_3_best_level_65_228','run_3_best_level_70_248','run_3_best_level_75_168','slope_best_score_1000_31','slope_best_score_100_21','slope_best_score_1100_201','slope_best_score_1150_211','slope_best_score_1200_221','slope_best_score_1250_231','slope_best_score_1250_32','slope_best_score_125_22','slope_best_score_1300_241','slope_best_score_150_23','slope_best_score_200_24','slope_best_score_250_25','slope_best_score_25_18','slope_best_score_300_26','slope_best_score_400_27','slope_best_score_500_28','slope_best_score_50_19','slope_best_score_650_29','slope_best_score_75_20','slope_best_score_800_30','stick_merge_best_level_10_136','stick_merge_best_level_12_137','stick_merge_best_level_15_138','stick_merge_best_level_20_139','stick_merge_best_level_25_140','stick_merge_best_level_2_129','stick_merge_best_level_3_130','stick_merge_best_level_4_131','stick_merge_best_level_5_132','stick_merge_best_level_6_133','stick_merge_best_level_7_134','stick_merge_best_level_8_135','stick_merge_best_score_10000_147','stick_merge_best_score_1000_144','stick_merge_best_score_100_141','stick_merge_best_score_2000_145','stick_merge_best_score_25000_148','stick_merge_best_score_250_142','stick_merge_best_score_5000_146','stick_merge_best_score_500_143','stick_merge_merges_100_124','stick_merge_merges_10_119','stick_merge_merges_150_125','stick_merge_merges_20_120','stick_merge_merges_250_126','stick_merge_merges_35_121','stick_merge_merges_400_127','stick_merge_merges_410_196','stick_merge_merges_430_206','stick_merge_merges_450_216','stick_merge_merges_470_226','stick_merge_merges_490_236','stick_merge_merges_50_122','stick_merge_merges_510_246','stick_merge_merges_5_118','stick_merge_merges_600_128','stick_merge_merges_75_123','tiny_fishing_fish_caught_1000_83','tiny_fishing_fish_caught_100_77','tiny_fishing_fish_caught_10_73','tiny_fishing_fish_caught_150_78','tiny_fishing_fish_caught_200_79','tiny_fishing_fish_caught_25_74','tiny_fishing_fish_caught_300_80','tiny_fishing_fish_caught_500_81','tiny_fishing_fish_caught_50_75','tiny_fishing_fish_caught_525_194','tiny_fishing_fish_caught_550_204','tiny_fishing_fish_caught_575_214','tiny_fishing_fish_caught_600_224','tiny_fishing_fish_caught_625_234','tiny_fishing_fish_caught_650_244','tiny_fishing_fish_caught_750_82','tiny_fishing_fish_caught_75_76','tiny_fishing_money_earned_10000_90','tiny_fishing_money_earned_1000_87','tiny_fishing_money_earned_100_84','tiny_fishing_money_earned_25000_91','tiny_fishing_money_earned_2500_88','tiny_fishing_money_earned_250_85','tiny_fishing_money_earned_50000_92','tiny_fishing_money_earned_5000_89','tiny_fishing_money_earned_500_86'])
  union all select 'website_achievement_rows_expected', '240'
  union all select 'supported_games', count(distinct game_title)::text from public.achievement_catalog where achievement_id = any(array['a_small_world_cup_goals_100_41','a_small_world_cup_goals_10_34','a_small_world_cup_goals_150_42','a_small_world_cup_goals_15_35','a_small_world_cup_goals_200_43','a_small_world_cup_goals_20_36','a_small_world_cup_goals_300_44','a_small_world_cup_goals_30_37','a_small_world_cup_goals_40_38','a_small_world_cup_goals_50_39','a_small_world_cup_goals_5_33','a_small_world_cup_goals_75_40','a_small_world_cup_wins_10_50','a_small_world_cup_wins_13_202','a_small_world_cup_wins_14_222','a_small_world_cup_wins_15_51','a_small_world_cup_wins_1_45','a_small_world_cup_wins_20_52','a_small_world_cup_wins_2_46','a_small_world_cup_wins_30_53','a_small_world_cup_wins_3_47','a_small_world_cup_wins_50_54','a_small_world_cup_wins_5_48','a_small_world_cup_wins_8_49','basket_random_best_score_100_63','basket_random_best_score_10_56','basket_random_best_score_150_64','basket_random_best_score_15_57','basket_random_best_score_20_58','basket_random_best_score_30_59','basket_random_best_score_315_193','basket_random_best_score_330_203','basket_random_best_score_345_213','basket_random_best_score_360_223','basket_random_best_score_375_233','basket_random_best_score_390_243','basket_random_best_score_40_60','basket_random_best_score_50_61','basket_random_best_score_5_55','basket_random_best_score_75_62','basket_random_wins_10_68','basket_random_wins_15_69','basket_random_wins_1_65','basket_random_wins_25_70','basket_random_wins_3_66','basket_random_wins_40_71','basket_random_wins_5_67','basket_random_wins_60_72','chess_ai_checkmates_10_106','chess_ai_checkmates_11_195','chess_ai_checkmates_12_205','chess_ai_checkmates_13_225','chess_ai_checkmates_14_245','chess_ai_checkmates_15_107','chess_ai_checkmates_1_102','chess_ai_checkmates_25_108','chess_ai_checkmates_2_103','chess_ai_checkmates_3_104','chess_ai_checkmates_50_109','chess_ai_checkmates_5_105','chess_ai_checks_100_101','chess_ai_checks_10_96','chess_ai_checks_15_97','chess_ai_checks_1_93','chess_ai_checks_25_98','chess_ai_checks_3_94','chess_ai_checks_40_99','chess_ai_checks_5_95','chess_ai_checks_60_100','chess_ai_wins_10_114','chess_ai_wins_15_115','chess_ai_wins_1_110','chess_ai_wins_25_116','chess_ai_wins_2_111','chess_ai_wins_3_112','chess_ai_wins_50_117','chess_ai_wins_5_113','chess_com_wins_10_191','chess_com_wins_1_188','chess_com_wins_25_192','chess_com_wins_3_189','chess_com_wins_5_190','drive_mad_best_level_100_159','drive_mad_best_level_10_151','drive_mad_best_level_15_152','drive_mad_best_level_20_153','drive_mad_best_level_25_154','drive_mad_best_level_30_155','drive_mad_best_level_3_149','drive_mad_best_level_40_156','drive_mad_best_level_50_157','drive_mad_best_level_55_197','drive_mad_best_level_5_150','drive_mad_best_level_60_207','drive_mad_best_level_65_227','drive_mad_best_level_70_247','drive_mad_best_level_75_158','google_doodle_baseball_best_score_100_183','google_doodle_baseball_best_score_10_179','google_doodle_baseball_best_score_150_184','google_doodle_baseball_best_score_200_185','google_doodle_baseball_best_score_25_180','google_doodle_baseball_best_score_300_186','google_doodle_baseball_best_score_500_187','google_doodle_baseball_best_score_50_181','google_doodle_baseball_best_score_75_182','google_doodle_baseball_hits_100_176','google_doodle_baseball_hits_10_171','google_doodle_baseball_hits_150_177','google_doodle_baseball_hits_20_172','google_doodle_baseball_hits_210_199','google_doodle_baseball_hits_220_209','google_doodle_baseball_hits_230_219','google_doodle_baseball_hits_240_229','google_doodle_baseball_hits_250_178','google_doodle_baseball_hits_260_249','google_doodle_baseball_hits_35_173','google_doodle_baseball_hits_50_174','google_doodle_baseball_hits_5_170','google_doodle_baseball_hits_75_175','google_snake_best_score_100_8','google_snake_best_score_10_0','google_snake_best_score_125_9','google_snake_best_score_150_10','google_snake_best_score_175_11','google_snake_best_score_200_12','google_snake_best_score_20_1','google_snake_best_score_250_13','google_snake_best_score_300_14','google_snake_best_score_30_2','google_snake_best_score_350_15','google_snake_best_score_400_16','google_snake_best_score_40_3','google_snake_best_score_500_17','google_snake_best_score_50_4','google_snake_best_score_550_200','google_snake_best_score_575_210','google_snake_best_score_600_220','google_snake_best_score_60_5','google_snake_best_score_625_230','google_snake_best_score_650_240','google_snake_best_score_75_6','google_snake_best_score_90_7','run_3_best_level_100_169','run_3_best_level_10_162','run_3_best_level_15_163','run_3_best_level_20_164','run_3_best_level_30_165','run_3_best_level_3_160','run_3_best_level_40_166','run_3_best_level_50_167','run_3_best_level_55_198','run_3_best_level_5_161','run_3_best_level_60_208','run_3_best_level_65_228','run_3_best_level_70_248','run_3_best_level_75_168','slope_best_score_1000_31','slope_best_score_100_21','slope_best_score_1100_201','slope_best_score_1150_211','slope_best_score_1200_221','slope_best_score_1250_231','slope_best_score_1250_32','slope_best_score_125_22','slope_best_score_1300_241','slope_best_score_150_23','slope_best_score_200_24','slope_best_score_250_25','slope_best_score_25_18','slope_best_score_300_26','slope_best_score_400_27','slope_best_score_500_28','slope_best_score_50_19','slope_best_score_650_29','slope_best_score_75_20','slope_best_score_800_30','stick_merge_best_level_10_136','stick_merge_best_level_12_137','stick_merge_best_level_15_138','stick_merge_best_level_20_139','stick_merge_best_level_25_140','stick_merge_best_level_2_129','stick_merge_best_level_3_130','stick_merge_best_level_4_131','stick_merge_best_level_5_132','stick_merge_best_level_6_133','stick_merge_best_level_7_134','stick_merge_best_level_8_135','stick_merge_best_score_10000_147','stick_merge_best_score_1000_144','stick_merge_best_score_100_141','stick_merge_best_score_2000_145','stick_merge_best_score_25000_148','stick_merge_best_score_250_142','stick_merge_best_score_5000_146','stick_merge_best_score_500_143','stick_merge_merges_100_124','stick_merge_merges_10_119','stick_merge_merges_150_125','stick_merge_merges_20_120','stick_merge_merges_250_126','stick_merge_merges_35_121','stick_merge_merges_400_127','stick_merge_merges_410_196','stick_merge_merges_430_206','stick_merge_merges_450_216','stick_merge_merges_470_226','stick_merge_merges_490_236','stick_merge_merges_50_122','stick_merge_merges_510_246','stick_merge_merges_5_118','stick_merge_merges_600_128','stick_merge_merges_75_123','tiny_fishing_fish_caught_1000_83','tiny_fishing_fish_caught_100_77','tiny_fishing_fish_caught_10_73','tiny_fishing_fish_caught_150_78','tiny_fishing_fish_caught_200_79','tiny_fishing_fish_caught_25_74','tiny_fishing_fish_caught_300_80','tiny_fishing_fish_caught_500_81','tiny_fishing_fish_caught_50_75','tiny_fishing_fish_caught_525_194','tiny_fishing_fish_caught_550_204','tiny_fishing_fish_caught_575_214','tiny_fishing_fish_caught_600_224','tiny_fishing_fish_caught_625_234','tiny_fishing_fish_caught_650_244','tiny_fishing_fish_caught_750_82','tiny_fishing_fish_caught_75_76','tiny_fishing_money_earned_10000_90','tiny_fishing_money_earned_1000_87','tiny_fishing_money_earned_100_84','tiny_fishing_money_earned_25000_91','tiny_fishing_money_earned_2500_88','tiny_fishing_money_earned_250_85','tiny_fishing_money_earned_50000_92','tiny_fishing_money_earned_5000_89','tiny_fishing_money_earned_500_86'])
  union all select 'record_game_metric', case when to_regprocedure('public.record_game_metric(text, text, integer, text)') is not null then 'installed' else 'missing' end
  union all select 'record_game_progress', case when to_regprocedure('public.record_game_progress(text, boolean, integer)') is not null then 'installed' else 'missing' end
  union all select 'award_ready_achievements', case when to_regprocedure('public.award_ready_achievements(uuid, text)') is not null then 'installed' else 'missing' end
  union all select 'slope_rows', count(*)::text from public.achievement_catalog where game_title='Slope'
  union all select 'status', 'OK - v121 all achievements fixed';
$$;

grant execute on function public.blank_space_v121_achievements_healthcheck() to anon, authenticated;

select pg_notify('pgrst','reload schema');

select * from public.blank_space_v121_achievements_healthcheck();

-- Done.

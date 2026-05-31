Blank Space v121

Changes:
- Repairs every achievement path, not just Slope.
- Syncs all website achievements into Supabase with supabase_v121_all_achievements_fix.sql.
- Restores generic record_game_metric for all games and all achievement stats.
- Adds live same-origin detection for game text/localStorage/postMessage.
- Adds a small in-game Achievement Sync fallback for sources that block automatic detection.
- Keeps v120 Slope Unity bridge fix.
- Does not reset achievements or remove points.

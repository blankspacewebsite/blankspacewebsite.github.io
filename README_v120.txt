Blank Space v120

Changes:
- Fixes Slope achievement score sending from the real Unity Slope game.
- Repairs the Unity GameCenter_ReportScore bridge so it scans all score arguments instead of only the first one.
- Adds a parent-page Slope poller that directly calls record_slope_score when it sees the score.
- Adds supabase_v120_slope_full_fix.sql for the backend Slope functions and backfill.

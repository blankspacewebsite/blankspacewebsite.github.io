Blank Space v124

Fixes the Slope false 15 problem:
- Removes old v120/v123 Slope tracker scripts that could send stale or guessed scores.
- Clears old Slope localStorage cache when Slope opens.
- Patches the Slope Unity bridge to ignore the false constant 15.
- Keeps achievements automatic-only.
- No new Supabase SQL is required for future tracking if v121 SQL already ran.
- Optional SQL is included to undo Owner's current false score-15 Slope awards.

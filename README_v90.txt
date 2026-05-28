Blank Space v90

Changes:
- Replaced the old Unity Slope iframe with a verified self-hosted Slope runner that sends real best_score messages to Blank Space.
- Restored Slope achievements to score-based unlocks and removed the bad play-count fallback.
- Included supabase_v90_update.sql to hard-fix achievements and clean accidental Slope fallback rows from 2026-05-28.
- Kept v89 group chats, rank tools, browser fix, moderation tools, and removed player Achievement Tester button.

Publish order:
1. Run supabase_v90_update.sql in Supabase SQL Editor.
2. Upload the website files to GitHub Pages.
3. Hard refresh the website and play Slope from the Games tab.

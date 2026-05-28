Blank Space v91

This version restores the real Unity Slope game and patches its Unity WebGL score function so it can send real Slope scores to the Blank Space achievement system.

Publish order:
1. Run supabase_v91_update.sql in Supabase first.
2. Upload all files in this folder to GitHub Pages.
3. Hard refresh the website.
4. Play real Slope and check Achievements.

Notes:
- Slope achievements are score-based again.
- The bad play-count fallback is removed.
- Slope achievements/progress are cleaned so fake/fallback Slope awards can be re-earned from real scores.
- Group chats, ranks, moderation tools, browser fix, and removed player Achievement Tester button are preserved.

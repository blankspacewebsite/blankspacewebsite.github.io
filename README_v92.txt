Blank Space v92

Fixes A Small World Cup achievements properly by updating the GitHub game code, not only Supabase.

Changes:
- Disabled the generic same-origin achievement scanner for A Small World Cup.
- Patched games/a-small-world-cup/index.html with a real scoreboard bridge.
- The bridge reads the Construct 2 scoreboard text and sends only player goal deltas.
- Supabase v92 stores A Small World Cup goal deltas exactly.
- Supabase v92 fully resets Admin's A Small World Cup achievements/progress without changing Admin's points.
- Keeps real Slope, v89/v91 group chats, ranks, moderation tools, browser fixes, and no player Achievement Tester button.

Publish order:
1. Run supabase_v92_update.sql in Supabase.
2. Upload the contents of this ZIP to GitHub Pages.
3. Hard refresh the website and test A Small World Cup.

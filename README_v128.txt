Blank Space v128

Changes:
- Owner-only trash can button on leaderboard rows with DELETE confirmation.
- Owner delete uses Supabase RPC owner_delete_account and protects Owner/Admin accounts.
- Leaderboard loads up to 10000 accounts instead of top 100.
- Supabase SQL restores missing profile rows for accounts still present in auth.users.
- SQL cannot restore accounts already deleted from auth.users; those need a Supabase backup.

Steps:
1. Run supabase_v128_leaderboard_owner_delete_restore.sql in Supabase.
2. Upload Blank Space v128.zip to GitHub Pages.
3. Hard refresh the website.

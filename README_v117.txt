Blank Space v117

Changes:
- Fixes banner collection display by loading banners through a security-definer RPC and adding a local fallback cache.
- Keeps Shop > Banners working and refreshable.
- Makes Change Password visible in the Account tab when signed in and rewires the button.
- Strengthens achievement recording and backfill.
- Makes Slope achievement score capture stronger using the real Unity score bridge plus a same-origin localStorage fallback.
- Requires supabase_v117_repair_update.sql.

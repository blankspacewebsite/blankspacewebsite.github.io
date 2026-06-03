Blank Space v149

Fixes account creation on the new Supabase project.

Change:
- Generated hidden login emails now use @blankspaceweb.com instead of @blankspace.invalid so Supabase Auth accepts them.

Supabase:
- No new SQL is required for v149.
- If your new project is not set up yet, run supabase_v148_new_project_core_setup_FIXED.sql first.

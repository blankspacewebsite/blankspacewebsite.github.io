Blank Space v147

What changed:
- Connected the website to the new Supabase project URL/key provided in this chat.
- Added a new Supabase setup file for a fresh Supabase project:
  supabase_v147_new_project_core_setup.sql

Website Supabase project now used:
- Project URL: https://orcmlmuxvwqxamrdvfgv.supabase.co
- Public key type: sb_publishable_...

What to do:
1. Upload this ZIP to GitHub Pages like normal.
2. In the NEW Supabase project, open SQL Editor.
3. Paste and run: supabase_v147_new_project_core_setup.sql
4. If an advanced feature still says a missing function/table error, run the older feature SQL files in the ZIP, newest major ones first:
   - supabase_v125_all_achievements_and_slope_fix.sql
   - supabase_v128_leaderboard_owner_delete_restore.sql
   - supabase_v130_banners_true_member_medals.sql
   - supabase_v136_banners_pause_message.sql
   - supabase_v138_banners_presence_messages.sql
   - supabase_v143_pause_custom_message_fix.sql

Important:
- The new Supabase project is empty, so old accounts/points/achievements will not appear unless they are migrated later.
- Create the Owner account again on the website. The setup SQL treats username Owner as owner/admin automatically.
- Do not put service_role keys in the website.

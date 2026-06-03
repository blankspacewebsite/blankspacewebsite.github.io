Blank Space v146

Fixes:
- Fixed the auth crash where sign-in/create-account could eventually show "achievement not defined" / "achievement is not defined".
- Repaired the username lookup error handler so it no longer references a missing achievement variable.
- Added faster sign-in/create-account handling with timeouts and non-blocking page refreshes after auth succeeds.
- Users can now open and use the other main tabs without being signed in.
- Account-only features still require sign-in inside their own actions, such as chat, friends, progress saving, shop ownership, and achievements.

Supabase:
- No new database changes are required.
- The Supabase file for this update is supabase_v146_auth_public_tabs_fix.sql.

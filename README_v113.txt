Blank Space v113

Changes:
- Fixed the actual reason the unlock code stopped working: an earlier update accidentally inserted a real script block inside an embedded game HTML template, which broke the main website script before the unlock code could load.
- Removed the broken injected script from inside the game template.
- Added a hard fallback unlock handler directly after the lock screen, so keyboard numbers and keypad taps work even if another later script has an issue.
- No typing box was added. The unlock screen stays the original style: code display plus keypad.
- No Supabase changes required if v110 SQL was already run.

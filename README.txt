Blank Space v82

Changes:
- Added Chess-AI as a verified self-hosted game.
- Added Stick Merge as a verified self-hosted game.
- Added a stronger 50-achievement system with equipable icons.
- Achievements now target scores, wins, goals, catches, checkmates, merges, and game-specific actions when the game files can report them.
- Added a separate Chat tab.
- Added unread chat badges on the Chat tab and the in-game quick chat button.
- Added bottom-right chat notifications for new messages.
- Added a quick chat button while playing games.
- Removed Chat button from the Your Friends sub-tab.
- Browser title is less bold.
- Browser search uses an iframe-friendly Google search page.

Important:
- Run supabase_v82_update.sql in Supabase before deploying this folder to Netlify.
- The SQL is a safe update and should not delete accounts, points, friends, messages, suggestions, or achievements.
- Some achievements are marked experimental because compiled games do not always expose exact scores to the website.

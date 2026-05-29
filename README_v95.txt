Blank Space v95

What changed:
- Keeps the v94 real Unity Slope startup fix.
- Makes the account named Admin the one-of-one Owner rank.
- Adds leaderboard flagging for Manager, Admin, and Owner ranks.
- Adds warning pop-ups: Warning 1, Warning 2, Warning 3. Every third warning gives a one-day suspension.
- Adds chat safety notice the first time a user opens Chat after this update.
- Gives warnings for bad/inappropriate words in Chat and blocks the message.
- Renames Admin Panel to Owner Panel.
- Adds Owner Chat View, a read-only owner view of a selected user's chats.
- Renames Timed User Message to Timed Message and lets Owner/Admin send a timed message to everyone.
- Adds Supabase-side A Small World Cup protection for duplicate goal signals: 2 goal signals count as 1 real goal.

Publish order:
1. Run supabase_v95_update.sql in Supabase first.
2. Upload the contents of this ZIP to GitHub Pages.
3. Hard refresh the website.

Blank Space v87 strict achievement patch

This is a small patch, not a full website ZIP.

It fixes mass unlocking by:
- disabling all automatic achievement messages/scanning
- making manual score submissions store exact values instead of using old inflated stats
- resetting only the Admin account's achievement progress/game stats/points
- removing achievement icons from the icon inventory so icons only come from packs

Publish steps:
1. Run supabase_v87_strict_update.sql in Supabase.
2. Replace only index.html in your GitHub repo with the patched index.html.
3. Commit and push with GitHub Desktop.
4. Hard refresh your website.

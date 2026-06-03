Blank Space v151

Fixes the half-signed-in account state where Supabase Auth says the user is signed in, but the Account tab still shows "Choose a username" and the Create Account / Sign In boxes.

Run this SQL in the new Supabase project first:
  supabase_v151_finish_profile_repair.sql

Then upload this ZIP to GitHub Pages and refresh the site.
If the page says "Choose a username", type Owner and the password in the Create Account box and click Create Account once. It will attach the username/profile to the signed-in Supabase account instead of creating another broken half-account.

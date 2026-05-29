Blank Space v94

This update fixes the Slope startup error:

An error occurred running the Unity content... Uncaught SyntaxError: Invalid or unexpected token

Cause: the patched real Slope Unity framework file was recompressed as normal gzip. This UnityLoader only recognizes Unity-marked compressed files, so the browser tried to run compressed bytes as JavaScript.

Fix: the real Slope framework is now stored uncompressed at the same Build/slope_27Sept.wasm.framework.unityweb path. The real Unity Slope game files remain intact, and the patched GameCenter_ReportScore bridge remains in the real framework so real Slope scores can still be sent to Blank Space/Supabase.

No new Supabase SQL is needed for this Slope loading fix. Keep using supabase_v93_update.sql / your latest achievement SQL.

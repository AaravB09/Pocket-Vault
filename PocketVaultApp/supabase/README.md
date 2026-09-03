# PocketVault Supabase security deployment

This folder is the server-side companion to the mobile client. The client no
longer contains an AI shared secret. The `coach` Edge Function requires a real
Supabase user session, validates it server-side, applies an atomic per-user
quota, and calls Gemini with a server-only API key.

Before deploying, rotate the previously exposed `vault_secret_998877` value and
any AI provider key it protected. Treat it as compromised.

```sh
supabase link --project-ref hbyrgmckacgbqqtteaq
supabase db push
supabase secrets set GEMINI_API_KEY=... GEMINI_MODEL=gemini-2.5-flash
supabase functions deploy coach --no-verify-jwt
supabase functions deploy delete-account --no-verify-jwt
```

`--no-verify-jwt` is intentional here: the function uses `auth.getUser()` for
server-side validation, which supports current key formats and produces the
same authenticated-user guarantee. Never make this endpoint anonymous.

Use the Dashboard to configure production backups, MFA, auth rate limits, log
retention, and alerts. Run RLS tests against every table/RPC before release;
the mobile app alone cannot establish those controls.

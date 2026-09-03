import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "content-type": "application/json",
  // Mobile apps do not use browser CORS. Keeping this narrow prevents a
  // browser origin from treating this endpoint as a public cross-origin API.
  "access-control-allow-origin": "https://pocketvault.app",
  "access-control-allow-headers": "authorization, content-type",
};

const fail = (status: number, message: string) =>
  new Response(JSON.stringify({ error: message }), { status, headers: corsHeaders });

/**
 * Permanently deletes a user's account and all associated data.
 *
 * Deletion order (each must succeed before the next runs):
 *   1. Leave every shared goal the caller owns or is partnered on
 *      (leave_shared_goal is a security-definer RPC that uses auth.uid()
 *       to determine the caller's role).
 *   2. DELETE any shared_deposits the caller contributed to that weren't
 *      already cascade-deleted by step 1 (orphan safety net).
 *   3. DELETE feedback rows tied to this user.
 *   4. DELETE friendships in both directions.
 *   5. DELETE the user's profile row.
 *   6. DELETE the auth.users record (cascades plaid_items /
 *      plaid_transactions automatically).
 *
 * If any step 1-5 fails, the function stops and returns which step
 * failed -- auth deletion is NOT attempted on partial failure.
 */
Deno.serve(async (request) => {
  if (request.method !== "POST") return fail(405, "method not allowed");

  const authHeader = request.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) return fail(401, "authentication required");

  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) return fail(500, "server misconfigured");

  // Validate the caller's token and extract their identity.
  // Never trust a client-supplied user id -- always derive it from the JWT.
  const callerClient = createClient(url, serviceRoleKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await callerClient.auth.getUser();
  if (authError || !user) return fail(401, "invalid session");

  const callerId = user.id;

  // Admin client bypasses RLS for all DELETE operations. Never expose the
  // service-role key to the device -- it is confined to this server.
  const admin = createClient(url, serviceRoleKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // -- Step 1: leave every shared goal where the caller is owner or partner --
  // leave_shared_goal is a security-definer RPC that determines "am I the
  // owner or the partner?" from auth.uid() -- call it with the caller's own
  // client so that context is set correctly.
  let ownedGoals: { id: string }[] = [];
  try {
    const { data, error } = await admin
      .from("shared_goals")
      .select("id")
      .or(`owner_id.eq.${callerId},partner_id.eq.${callerId}`);
    if (error) throw error;
    ownedGoals = data ?? [];
  } catch (err) {
    console.error("Step 1 failed -- fetch shared_goals:", err, callerId);
    return fail(500, "step 1 failed: could not fetch shared goals");
  }

  for (const goal of ownedGoals) {
    const { error: leaveError } = await admin.rpc("leave_shared_goal", {
      p_shared_goal_id: goal.id,
    });
    if (leaveError) {
      console.error("Step 1 failed -- leave_shared_goal for goal", goal.id, leaveError, callerId);
      return fail(500, "step 1 failed: could not leave shared goal");
    }
  }

  // -- Step 2: safety-net DELETE for any remaining shared_deposits --
  // Covers contributions the caller made to goals they no longer own/partner,
  // where cascade from leave_shared_goal would not have reached them.
  const { error: depositsError } = await admin
    .from("shared_deposits")
    .delete()
    .eq("contributor_id", callerId);
  if (depositsError) {
    console.error("Step 2 failed:", depositsError, callerId);
    return fail(500, "step 2 failed: could not delete shared deposits");
  }

  // -- Step 3: DELETE feedback rows --
  // feedback.user_id is plain text, not a FK to auth.users -- handled manually.
  const { error: feedbackError } = await admin
    .from("feedback")
    .delete()
    .eq("user_id", callerId);
  if (feedbackError) {
    console.error("Step 3 failed:", feedbackError, callerId);
    return fail(500, "step 3 failed: could not delete feedback");
  }

  // -- Step 4: DELETE friendships (both directions) --
  // The caller's row and any other user's row that references the caller as
  // their friend both need to go.
  const { error: friendshipsError } = await admin
    .from("friendships")
    .delete()
    .or(`user_id.eq.${callerId},friend_id.eq.${callerId}`);
  if (friendshipsError) {
    console.error("Step 4 failed:", friendshipsError, callerId);
    return fail(500, "step 4 failed: could not delete friendships");
  }

  // -- Step 5: DELETE the profile row --
  // profiles.id is plain text (not a FK to auth.users). Cascade from here
  // handles friendships since their FK references profiles.id.
  const { error: profileError } = await admin
    .from("profiles")
    .delete()
    .eq("id", callerId);
  if (profileError) {
    console.error("Step 5 failed:", profileError, callerId);
    return fail(500, "step 5 failed: could not delete profile");
  }

  // -- Step 6: DELETE the auth.users record --
  // plaid_items and plaid_transactions cascade automatically from here.
  // supabase-js v2 exposes auth.admin methods via the admin client.
  const { error: deleteAuthError } = await admin.auth.admin.deleteUser(callerId);
  if (deleteAuthError) {
    console.error("Step 6 failed:", deleteAuthError, callerId);
    return fail(500, "step 6 failed: could not delete auth account");
  }

  return new Response(JSON.stringify({ ok: true }), { status: 200, headers: corsHeaders });
});


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

const boundedString = (value: unknown, maxLength: number): value is string =>
  typeof value === "string" && value.length > 0 && value.length <= maxLength;

Deno.serve(async (request) => {
  if (request.method !== "POST") return fail(405, "method not allowed");

  const authHeader = request.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) return fail(401, "authentication required");

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  if (!url || !anonKey || !serviceRoleKey || !geminiKey) return fail(500, "server misconfigured");

  // `getUser` validates the token with Supabase Auth. Never trust a decoded
  // JWT payload alone when this identity gates paid/provider usage.
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return fail(401, "invalid session");

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch {
    return fail(400, "invalid JSON");
  }

  // The app has two request types. Enforce strict bounds before provider use.
  const prompt = payload.prompt;
  const contents = payload.contents;
  const isPrompt = boundedString(prompt, 8_000);
  const isChat = Array.isArray(contents) && contents.length > 0 && contents.length <= 24;
  if (!isPrompt && !isChat) return fail(400, "invalid request");

  const maxTokens = Number(payload.max_tokens ?? (isPrompt ? 500 : 350));
  if (!Number.isInteger(maxTokens) || maxTokens < 1 || maxTokens > 500) {
    return fail(400, "invalid token limit");
  }

  // The service role never reaches the device. The SQL upsert is atomic, so
  // simultaneous requests cannot bypass the per-user quota.
  const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false } });
  const { data: allowed, error: quotaError } = await admin.rpc("consume_ai_quota", {
    p_user_id: user.id,
    p_limit: 20,
    p_window_seconds: 3600,
  });
  if (quotaError) return fail(500, "quota check failed");
  if (!allowed) return fail(429, "AI limit reached. Try again later.");

  const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
  const providerBody = isPrompt
    ? { contents: [{ role: "user", parts: [{ text: prompt }] }], generationConfig: { maxOutputTokens: maxTokens } }
    : { contents, generationConfig: { maxOutputTokens: maxTokens } };

  const providerResponse = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(geminiKey)}`,
    { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(providerBody) },
  );
  if (!providerResponse.ok) {
    console.error("Gemini request failed", providerResponse.status, user.id);
    return fail(502, "AI provider unavailable");
  }

  // Return only the response shape the app needs; do not expose provider
  // headers, API keys, or raw errors to the client.
  const providerData = await providerResponse.json();
  return new Response(JSON.stringify({ candidates: providerData.candidates ?? [] }), { status: 200, headers: corsHeaders });
});

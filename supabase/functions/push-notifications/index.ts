import { createClient } from "npm:@supabase/supabase-js@2";
import { generateVapidKey, vapidPublicKey, send } from "jsr:@daaku/webpush@0.2.0";

const cors = {
  "Access-Control-Allow-Origin": "https://berniaja5036-blip.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });
function secretKey(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
  return keys.default || Object.values(keys)[0] as string;
}
function publishableKey(): string {
  const legacy = Deno.env.get("SUPABASE_ANON_KEY");
  if (legacy) return legacy;
  const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}");
  return keys.default || Object.values(keys)[0] as string;
}
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const service = secretKey();
  if (!url || !service) return json({ error: "Server configuration incomplete" }, 500);
  const admin = createClient(url, service, { auth: { persistSession: false } });
  let payload: any;
  try { payload = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const authToken = (req.headers.get("Authorization") || "").replace(/^Bearer\\s+/i, "");
  const pubKey = publishableKey();
  const authenticatedUser = async () => {
    if (!authToken || !pubKey) return null;
    const client = createClient(url, pubKey, { auth: { persistSession: false } });
    const { data, error } = await client.auth.getUser(authToken);
    return error ? null : data.user;
  };

  if (payload?.action === "register_subscription" || payload?.action === "remove_subscription") {
    const user = await authenticatedUser();
    if (!user) return json({ error: "Invalid session" }, 401);
    const endpoint = payload?.subscription?.endpoint || payload?.endpoint;
    if (typeof endpoint !== "string" || !endpoint.startsWith("https://")) return json({ error: "Invalid endpoint" }, 400);
    if (payload.action === "remove_subscription") {
      const { error } = await admin.from("push_subscriptions").delete().eq("user_id", user.id).eq("endpoint", endpoint);
      if (error) return json({ error: "Could not remove subscription" }, 500);
      return json({ ok: true });
    }
    const keys = payload?.subscription?.keys;
    if (!keys?.p256dh || !keys?.auth) return json({ error: "Subscription keys missing" }, 400);
    const { data: existing } = await admin.from("push_subscriptions").select("user_id").eq("endpoint", endpoint).maybeSingle();
    if (existing && existing.user_id !== user.id) return json({ error: "Perangkat ini masih terhubung ke akun lain. Keluar dari akun lama terlebih dahulu, lalu coba lagi." }, 409);
    const { error } = await admin.from("push_subscriptions").upsert({
      user_id: user.id, endpoint, p256dh: keys.p256dh, auth_secret: keys.auth,
      expiration_time: payload.subscription.expirationTime ? new Date(payload.subscription.expirationTime).toISOString() : null,
      updated_at: new Date().toISOString()
    }, { onConflict: "endpoint" });
    if (error) return json({ error: "Could not save device subscription" }, 500);
    return json({ ok: true });
  }

  if (payload?.action === "generate_vapid") {
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Authentication required" }, 401);
    const pub = publishableKey();
    if (!pub) return json({ error: "Publishable key unavailable" }, 500);
    const client = createClient(url, pub, { auth: { persistSession: false } });
    const { data: authData, error: authError } = await client.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Invalid session" }, 401);
    const { data: profile } = await admin.from("profiles").select("role").eq("id", authData.user.id).maybeSingle();
    if (profile?.role !== "admin") return json({ error: "Admin only" }, 403);
    const privateKey = await generateVapidKey();
    const publicKey = vapidPublicKey(privateKey);
    const { error } = await admin.from("push_settings").upsert({ id: 1, public_key: publicKey, subject: "mailto:yisunshin715@gmail.com", updated_at: new Date().toISOString() });
    if (error) return json({ error: "Could not save public VAPID key" }, 500);
    return json({ publicKey, privateKey });
  }

  const supplied = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!supplied || supplied !== service) return json({ error: "Unauthorized webhook" }, 401);
  const record = payload?.record;
  if (!record?.user_id || !record?.title || !record?.body) return json({ ok: true, skipped: true });
  const privateRaw = Deno.env.get("VAPID_PRIVATE_KEY");
  const subject = Deno.env.get("VAPID_SUBJECT") || "mailto:yisunshin715@gmail.com";
  if (!privateRaw) return json({ error: "VAPID_PRIVATE_KEY secret is not configured" }, 503);
  let vapid: JsonWebKey;
  try { vapid = JSON.parse(privateRaw); } catch { return json({ error: "VAPID_PRIVATE_KEY is not valid JSON" }, 500); }
  const { data: subscriptions, error } = await admin.from("push_subscriptions")
    .select("id,endpoint,p256dh,auth_secret").eq("user_id", record.user_id);
  if (error) return json({ error: "Could not load device subscriptions" }, 500);
  let sent = 0, removed = 0;
  for (const row of subscriptions || []) {
    try {
      await send({ endpoint: row.endpoint, keys: { p256dh: row.p256dh, auth: row.auth_secret } },
        JSON.stringify({ title: record.title, body: record.body, url: record.target_path || "./", notificationId: record.id }),
        { vapid, subscriber: subject, ttl: 43200 });
      sent++;
    } catch (err) {
      const status = (err as { statusCode?: number }).statusCode;
      if (status === 404 || status === 410) {
        await admin.from("push_subscriptions").delete().eq("id", row.id);
        removed++;
      } else console.error("Push delivery failed", status, String(err));
    }
  }
  return json({ ok: true, sent, removed });
});
import { createClient } from "npm:@supabase/supabase-js@2.119.0";

const cors = {
  "Access-Control-Allow-Origin": "https://berniaja5036-blip.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });

async function writeAuditLog(admin: ReturnType<typeof createClient>, entry: {
  actor_id: string; action: string; target_type: string; target_id: string | null;
  outcome: "success" | "failure"; details?: Record<string, unknown>;
}) {
  const { error } = await admin.from("admin_audit_logs").insert({
    actor_id: entry.actor_id, action: entry.action, target_type: entry.target_type,
    target_id: entry.target_id, outcome: entry.outcome, details: entry.details || {},
  });
  return !error;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || (() => {
    try { const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}"); return keys.default || Object.values(keys)[0] as string; } catch { return ""; }
  })();
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") || (() => {
    try { const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}"); return keys.default || Object.values(keys)[0] as string; } catch { return ""; }
  })();
  if (!url || !serviceKey || !publishableKey) return json({ error: "Konfigurasi server belum lengkap." }, 500);

  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7).trim() : "";
  if (!token) return json({ error: "Silakan masuk sebagai admin." }, 401);
  const caller = createClient(url, publishableKey, { auth: { persistSession: false } });
  const { data: authData, error: authError } = await caller.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "Sesi tidak valid. Silakan masuk kembali." }, 401);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: adminProfile, error: adminProfileError } = await admin.from("profiles")
    .select("role,account_status").eq("id", authData.user.id).maybeSingle();
  if (adminProfileError || adminProfile?.role !== "admin" || adminProfile.account_status !== "active") {
    return json({ error: "Akses khusus admin ditolak." }, 403);
  }

  // Use the verified admin's JWT for writes guarded by is_admin() triggers.
  // The service-role client remains reserved for Auth Admin and protected reads.
  const adminSession = createClient(url, publishableKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Format permintaan tidak valid." }, 400); }

  if (body?.action === "list_accounts") {
    const { data: profiles, error } = await admin.from("profiles")
      .select("id,full_name,phone,role,account_status,account_status_note,created_at")
      .in("role", ["buyer", "seller", "driver"])
      .order("created_at", { ascending: false }).limit(500);
    if (error) return json({ error: "Daftar akun tidak dapat dimuat." }, 500);
    const ids = (profiles || []).map((p: any) => p.id);
    const [{ data: authUsers, error: authUsersError }, { data: shops }, { data: drivers }] = await Promise.all([
      admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
      admin.from("shops").select("owner_id,name,status").in("owner_id", ids),
      admin.from("driver_profiles").select("id,vehicle_type,vehicle_plate,approval_status").in("id", ids),
    ]);
    if (authUsersError) return json({ error: "Informasi akun tidak dapat dimuat." }, 500);
    const emailMap = new Map((authUsers.users || []).map((u: any) => [u.id, u.email || ""]));
    const shopMap = new Map((shops || []).map((s: any) => [s.owner_id, s]));
    const driverMap = new Map((drivers || []).map((d: any) => [d.id, d]));
    return json({ accounts: (profiles || []).map((p: any) => ({
      id: p.id, full_name: p.full_name, phone: p.phone, role: p.role,
      email: emailMap.get(p.id) || "", account_status: p.account_status,
      account_status_note: p.account_status_note, created_at: p.created_at,
      shop: shopMap.get(p.id) || null, driver: driverMap.get(p.id) || null,
    })) });
  }

  if (body?.action === "suspend_account") {
    const targetId = String(body?.user_id || "");
    const reason = String(body?.reason || "").trim().slice(0, 500);
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(targetId)) return json({ error: "ID akun tidak valid." }, 400);
    if (targetId === authData.user.id) return json({ error: "Admin tidak dapat menonaktifkan akunnya sendiri." }, 400);
    if (reason.length < 5) return json({ error: "Tuliskan alasan penonaktifan minimal 5 karakter." }, 400);
    const { data: target, error: targetError } = await admin.from("profiles")
      .select("id,role,account_status").eq("id", targetId).maybeSingle();
    if (targetError || !target || !["buyer", "seller", "driver"].includes(target.role)) return json({ error: "Akun tidak ditemukan atau tidak dapat dinonaktifkan." }, 404);
    if (target.account_status === "suspended") return json({ error: "Akun ini sudah dinonaktifkan." }, 409);
    let ownedShops: any[] = [];
    if (target.role === "seller") {
      const { data: shops, error: shopsError } = await admin.from("shops").select("id,status").eq("owner_id", targetId);
      if (shopsError) return json({ error: "Toko milik penjual tidak dapat diperiksa." }, 500);
      ownedShops = shops || [];
      const shopIds = ownedShops.map((s: any) => s.id);
      if (shopIds.length) {
        // Orders are related to shops through order_items; orders has no shop_id column.
        const { data: activeOrders, error: ordersError } = await admin.from("order_items")
          .select("id, orders!inner(status)")
          .in("shop_id", shopIds)
          .in("orders.status", ["pending", "confirmed", "ready_for_pickup", "picked_up"])
          .limit(1);
        if (ordersError) return json({ error: "Pesanan aktif toko tidak dapat diperiksa." }, 500);
        if (activeOrders?.length) return json({ error: "Toko masih memiliki pesanan berjalan. Selesaikan atau tangani pesanan melalui admin sebelum menonaktifkan akun." }, 409);
      }
    }
    if (target.role === "driver") {
      const { data: activeTasks, error: taskError } = await admin.from("deliveries")
        .select("id").eq("driver_id", targetId).in("status", ["assigned", "picked_up"]).limit(1);
      if (taskError) return json({ error: "Status tugas driver tidak dapat diperiksa." }, 500);
      if (activeTasks?.length) return json({ error: "Driver masih memiliki tugas aktif. Selesaikan atau alihkan tugasnya melalui admin sebelum menonaktifkan akun." }, 409);
    }

    const { error: banError } = await admin.auth.admin.updateUserById(targetId, { ban_duration: "876000h" });
    if (banError) return json({ error: "Akun gagal diblokir oleh sistem login." }, 500);
    const { error: profileError } = await admin.from("profiles").update({
      account_status: "suspended", account_status_note: reason, account_status_updated_at: new Date().toISOString()
    }).eq("id", targetId);
    if (profileError) {
      await admin.auth.admin.updateUserById(targetId, { ban_duration: "none" });
      return json({ error: "Status akun gagal disimpan. Pemblokiran login dibatalkan; coba lagi." }, 500);
    }
    let relatedError: string | null = null;
    if (target.role === "seller" && ownedShops.length) {
      const shopIds = ownedShops.map((s: any) => s.id);
      const { data: oldProducts, error: oldProductsError } = await admin.from("products").select("id,status").in("shop_id", shopIds);
      const { error: shopUpdateError } = await adminSession.from("shops").update({ status: "suspended" }).in("id", shopIds);
      const { error: productUpdateError } = oldProductsError ? { error: oldProductsError } : await adminSession.from("products").update({ status: "draft" }).in("shop_id", shopIds);
      if (shopUpdateError || productUpdateError) {
        relatedError = "Status toko atau produk gagal diperbarui.";
        for (const shop of ownedShops) await adminSession.from("shops").update({ status: shop.status }).eq("id", shop.id);
        for (const product of oldProducts || []) await adminSession.from("products").update({ status: product.status }).eq("id", product.id);
      }
    }
    if (target.role === "driver") {
      const { error: driverUpdateError } = await admin.from("driver_profiles").update({ approval_status: "suspended" }).eq("id", targetId);
      if (driverUpdateError) relatedError = "Status profil driver gagal diperbarui.";
    }
    if (relatedError) {
      await admin.from("profiles").update({ account_status: "active", account_status_note: null, account_status_updated_at: null }).eq("id", targetId);
      await admin.auth.admin.updateUserById(targetId, { ban_duration: "none" });
      return json({ error: relatedError + " Penonaktifan dibatalkan." }, 500);
    }
    const { error: pushDeleteError } = await admin.from("push_subscriptions").delete().eq("user_id", targetId);
    const auditLogged = await writeAuditLog(admin, {
      actor_id: authData.user.id, action: "suspend_account", target_type: "profile",
      target_id: targetId, outcome: "success",
      details: { target_role: target.role, reason, related_shop_count: ownedShops.length,
        push_subscriptions_removed: !pushDeleteError },
    });
    return json({ ok: true, audit_logged: auditLogged,
      warning: !auditLogged ? "Akun dinonaktifkan, tetapi pencatatan audit gagal." :
        pushDeleteError ? "Akun dinonaktifkan, tetapi langganan notifikasi lama gagal dibersihkan." : null,
      message: "Akun dinonaktifkan. Riwayat pesanan dan transaksi tetap tersimpan." });
  }
  return json({ error: "Aksi tidak dikenal." }, 400);
});

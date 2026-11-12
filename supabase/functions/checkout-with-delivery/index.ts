import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.119.0";

const cors = {
  "Access-Control-Allow-Origin": "https://berniaja5036-blip.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_BODY_LENGTH = 24_000;

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Metode tidak diizinkan." }, 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) return reply({ error: "Silakan masuk kembali." }, 401);

    const rawBody = await req.text();
    if (rawBody.length > MAX_BODY_LENGTH) return reply({ error: "Data checkout terlalu besar." }, 413);
    let body: Record<string, unknown>;
    try {
      const parsed = JSON.parse(rawBody);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        return reply({ error: "Format checkout tidak valid." }, 400);
      }
      body = parsed as Record<string, unknown>;
    } catch {
      return reply({ error: "Format checkout tidak valid." }, 400);
    }

    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return reply({ error: "Sesi login tidak valid. Silakan masuk kembali." }, 401);
    const buyerId = authData.user.id;

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: profile, error: profileError } = await admin.from("profiles").select("role,account_status").eq("id", buyerId).maybeSingle();
    if (profileError || profile?.role !== "buyer" || profile.account_status !== "active") return reply({ error: "Checkout hanya tersedia untuk akun pembeli yang aktif." }, 403);

    const items = body.items;
    const address = typeof body.delivery_address === "string" ? body.delivery_address.trim() : "";
    const notes = typeof body.notes === "string" ? body.notes.trim() : "";
    const rawVoucher = body.voucher_code;
    if (rawVoucher !== undefined && rawVoucher !== null && typeof rawVoucher !== "string") {
      return reply({ error: "Kode voucher tidak valid." }, 400);
    }
    const voucherCode = typeof rawVoucher === "string" ? rawVoucher.trim().toUpperCase() : "";
    const idempotencyKey = typeof body.idempotency_key === "string" ? body.idempotency_key.toLowerCase() : "";
    const lat = body.delivery_latitude;
    const lng = body.delivery_longitude;

    if (!UUID_RE.test(idempotencyKey)) return reply({ error: "Kunci checkout tidak valid. Muat ulang halaman dan coba lagi." }, 400);
    if (voucherCode && !/^[A-Z0-9_-]{3,40}$/.test(voucherCode)) return reply({ error: "Format kode voucher tidak valid." }, 400);
    if (!Array.isArray(items) || items.length < 1 || items.length > 30) return reply({ error: "Keranjang tidak valid." }, 400);
    if (address.length < 8 || address.length > 500 || notes.length > 500 ||
        typeof lat !== "number" || typeof lng !== "number" ||
        !Number.isFinite(lat) || !Number.isFinite(lng) ||
        lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return reply({ error: "Alamat, catatan, atau titik pengantaran tidak valid." }, 400);
    }

    const normalized = new Map<string, number>();
    for (const item of items) {
      if (!item || typeof item !== "object" || Array.isArray(item)) {
        return reply({ error: "Daftar produk atau jumlah barang tidak valid." }, 400);
      }
      const value = item as Record<string, unknown>;
      const id = typeof value.product_id === "string" ? value.product_id.toLowerCase() : "";
      const qty = value.quantity;
      if (!UUID_RE.test(id) || typeof qty !== "number" || !Number.isInteger(qty) ||
          qty < 1 || qty > 100 || normalized.has(id)) {
        return reply({ error: "Daftar produk atau jumlah barang tidak valid." }, 400);
      }
      normalized.set(id, qty);
    }
    const sortedItems = [...normalized.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([product_id, quantity]) => ({ product_id, quantity }));

    const { data: previousResult, error: previousError } = await admin.rpc("get_checkout_idempotent_result_secure", {
      p_buyer_id: buyerId,
      p_idempotency_key: idempotencyKey,
      p_items: sortedItems,
      p_delivery_address: address,
      p_notes: notes,
      p_voucher_code: voucherCode || null,
    });
    if (previousError) {
      const status = /kunci checkout/i.test(previousError.message || "") ? 409 : 500;
      return reply({ error: previousError.message || "Status checkout sebelumnya belum dapat diverifikasi." }, status);
    }
    if (previousResult && typeof previousResult === "object" && !Array.isArray(previousResult) && (previousResult as Record<string, unknown>)._checkout_in_progress === true) {
      return reply({ error: "Checkout dengan kunci ini masih diproses. Muat ulang riwayat pesanan sebelum mencoba lagi." }, 409);
    }
    if (Array.isArray(previousResult)) return reply({ orders: previousResult });
    if (previousResult && typeof previousResult === "object") return reply({ orders: previousResult });

    const { data: settings, error: settingsError } = await admin.from("delivery_fee_settings")
      .select("enabled,base_fee,per_km_fee,minimum_fee,max_distance_km").eq("id", true).single();
    if (settingsError || !settings) return reply({ error: "Pengaturan ongkir belum tersedia." }, 500);
    const baseFee = Number(settings.base_fee);
    const perKmFee = Number(settings.per_km_fee);
    const minimumFee = Number(settings.minimum_fee);
    const maxDistanceKm = Number(settings.max_distance_km);
    if (![baseFee, perKmFee, minimumFee, maxDistanceKm].every(Number.isFinite) ||
        baseFee < 0 || perKmFee < 0 || minimumFee < 0 || maxDistanceKm <= 0) {
      return reply({ error: "Pengaturan tarif ongkir tidak valid. Hubungi admin." }, 500);
    }

    const ids = sortedItems.map(item => item.product_id);
    const { data: products, error: productsError } = await admin.from("products")
      .select("id,shop_id,name,price,stock,status").in("id", ids);
    if (productsError || !products || products.length !== ids.length) return reply({ error: "Ada produk yang sudah tidak tersedia." }, 400);
    for (const product of products) {
      if (product.status !== "active" || Number(product.stock) < normalized.get(product.id)!) {
        return reply({ error: "Stok produk tidak cukup atau produk tidak lagi tersedia." }, 409);
      }
    }

    const shopIds = [...new Set(products.map(product => product.shop_id))];
    const { data: shops, error: shopsError } = await admin.from("shops")
      .select("id,name,status,pickup_latitude,pickup_longitude").in("id", shopIds);
    if (shopsError || !shops || shops.length !== shopIds.length) return reply({ error: "Data toko tidak dapat diverifikasi." }, 500);

    const feeRows: { shop_id: string; distance_meters: number; delivery_fee: number }[] = [];
    for (const shop of shops) {
      if (shop.status !== "approved" || shop.pickup_latitude == null || shop.pickup_longitude == null) {
        return reply({ error: "Toko " + shop.name + " belum siap menerima pesanan atau belum memiliki titik penjemputan." }, 409);
      }
      const pickupLat = Number(shop.pickup_latitude);
      const pickupLng = Number(shop.pickup_longitude);
      if (!Number.isFinite(pickupLat) || !Number.isFinite(pickupLng) ||
          Math.abs(pickupLat) > 90 || Math.abs(pickupLng) > 180) {
        return reply({ error: "Titik penjemputan toko " + shop.name + " tidak valid." }, 409);
      }

      const routeUrl = `https://router.project-osrm.org/route/v1/driving/${pickupLng},${pickupLat};${lng},${lat}?overview=false`;
      const routeResponse = await fetch(routeUrl, { signal: AbortSignal.timeout(12000) });
      if (!routeResponse.ok) return reply({ error: "Rute jalan untuk toko " + shop.name + " belum dapat dihitung. Coba lagi." }, 502);
      const route = await routeResponse.json().catch(() => null);
      const rawDistance = route?.routes?.[0]?.distance;
      if (route?.code !== "Ok" || typeof rawDistance !== "number" ||
          !Number.isFinite(rawDistance) || rawDistance <= 0) {
        return reply({ error: "Rute jalan untuk toko " + shop.name + " tidak ditemukan." }, 422);
      }

      const meters = Math.ceil(rawDistance);
      if (!Number.isSafeInteger(meters) || meters <= 0) return reply({ error: "Jarak rute untuk toko " + shop.name + " tidak valid." }, 422);
      const km = Math.ceil(meters / 1000);
      if (km > maxDistanceKm) return reply({ error: "Jarak toko " + shop.name + " melebihi batas " + maxDistanceKm + " km." }, 422);
      const fee = settings.enabled ? Math.max(minimumFee, baseFee + km * perKmFee) : 0;
      if (!Number.isFinite(fee) || fee < 0) return reply({ error: "Tarif ongkir tidak dapat dihitung." }, 500);
      feeRows.push({ shop_id: shop.id, distance_meters: meters, delivery_fee: fee });
    }

    const { data: created, error: checkoutError } = await admin.rpc("checkout_cart_idempotent_secure", {
      p_buyer_id: buyerId,
      p_idempotency_key: idempotencyKey,
      p_items: sortedItems,
      p_delivery_address: address,
      p_notes: notes,
      p_delivery_latitude: lat,
      p_delivery_longitude: lng,
      p_delivery_fees: feeRows,
      p_voucher_code: voucherCode || null,
    });
    if (checkoutError) {
      const status = /kunci checkout/i.test(checkoutError.message || "") ? 409 : 400;
      return reply({ error: checkoutError.message || "Pesanan belum berhasil dibuat." }, status);
    }
    return reply({ orders: created });
  } catch (error) {
    console.error("checkout-with-delivery:", error);
    return reply({ error: "Terjadi gangguan saat menghitung ongkir atau membuat pesanan. Silakan coba lagi." }, 500);
  }
});

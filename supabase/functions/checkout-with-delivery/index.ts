import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.119.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Metode tidak diizinkan." }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) return reply({ error: "Silakan masuk kembali." }, 401);

    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return reply({ error: "Sesi login tidak valid. Silakan masuk kembali." }, 401);
    const buyerId = authData.user.id;

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: profile, error: profileError } = await admin.from("profiles").select("role").eq("id", buyerId).maybeSingle();
    if (profileError || profile?.role !== "buyer") return reply({ error: "Checkout hanya tersedia untuk akun pembeli." }, 403);

    const body = await req.json();
    const items = body.items;
    const address = String(body.delivery_address || "").trim();
    const notes = String(body.notes || "").trim();
    const voucherCode = String(body.voucher_code || "").trim().toUpperCase();
    if (voucherCode && !/^[A-Z0-9_-]{3,40}$/.test(voucherCode)) return reply({ error: "Format kode voucher tidak valid." }, 400);
    const lat = Number(body.delivery_latitude);
    const lng = Number(body.delivery_longitude);
    if (!Array.isArray(items) || items.length < 1 || items.length > 30) return reply({ error: "Keranjang tidak valid." }, 400);
    if (address.length < 8 || !Number.isFinite(lat) || !Number.isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return reply({ error: "Alamat atau titik pengantaran tidak valid." }, 400);
    }

    const normalized = new Map<string, number>();
    for (const item of items) {
      const id = String(item?.product_id || "");
      const qty = Number(item?.quantity);
      if (!/^[0-9a-f-]{36}$/i.test(id) || !Number.isInteger(qty) || qty < 1 || qty > 100 || normalized.has(id)) {
        return reply({ error: "Daftar produk atau jumlah barang tidak valid." }, 400);
      }
      normalized.set(id, qty);
    }

    const { data: settings, error: settingsError } = await admin.from("delivery_fee_settings")
      .select("enabled,base_fee,per_km_fee,minimum_fee,max_distance_km").eq("id", true).single();
    if (settingsError || !settings) return reply({ error: "Pengaturan ongkir belum tersedia." }, 500);

    const ids = [...normalized.keys()];
    const { data: products, error: productsError } = await admin.from("products")
      .select("id,shop_id,name,price,stock,status").in("id", ids);
    if (productsError || !products || products.length !== ids.length) return reply({ error: "Ada produk yang sudah tidak tersedia." }, 400);
    for (const p of products) {
      if (p.status !== "active" || Number(p.stock) < normalized.get(p.id)!) return reply({ error: "Stok produk tidak cukup atau produk tidak lagi tersedia." }, 409);
    }

    const shopIds = [...new Set(products.map(p => p.shop_id))];
    const { data: shops, error: shopsError } = await admin.from("shops")
      .select("id,name,status,pickup_latitude,pickup_longitude").in("id", shopIds);
    if (shopsError || !shops || shops.length !== shopIds.length) return reply({ error: "Data toko tidak dapat diverifikasi." }, 500);

    const feeRows = [];
    for (const shop of shops) {
      if (shop.status !== "approved" || shop.pickup_latitude == null || shop.pickup_longitude == null) {
        return reply({ error: "Toko " + shop.name + " belum siap menerima pesanan atau belum memiliki titik penjemputan." }, 409);
      }
      const pickupLat = Number(shop.pickup_latitude);
      const pickupLng = Number(shop.pickup_longitude);
      const routeUrl = `https://router.project-osrm.org/route/v1/driving/${pickupLng},${pickupLat};${lng},${lat}?overview=false`;
      const routeResponse = await fetch(routeUrl, { signal: AbortSignal.timeout(12000) });
      if (!routeResponse.ok) return reply({ error: "Rute jalan untuk toko " + shop.name + " belum dapat dihitung. Coba lagi." }, 502);
      const route = await routeResponse.json();
      if (route.code !== "Ok" || !route.routes?.[0] || !Number.isFinite(route.routes[0].distance)) {
        return reply({ error: "Rute jalan untuk toko " + shop.name + " tidak ditemukan." }, 422);
      }
      const meters = Math.ceil(route.routes[0].distance);
      const km = Math.ceil(meters / 1000);
      if (km > Number(settings.max_distance_km)) return reply({ error: "Jarak toko " + shop.name + " melebihi batas " + settings.max_distance_km + " km." }, 422);
      const fee = settings.enabled
        ? Math.max(Number(settings.minimum_fee), Number(settings.base_fee) + km * Number(settings.per_km_fee))
        : 0;
      feeRows.push({ shop_id: shop.id, distance_meters: meters, delivery_fee: fee });
    }

    const { data: created, error: checkoutError } = await admin.rpc("checkout_cart_with_voucher_secure", {
      p_buyer_id: buyerId,
      p_items: [...normalized.entries()].map(([product_id, quantity]) => ({ product_id, quantity })),
      p_delivery_address: address,
      p_notes: notes,
      p_delivery_latitude: lat,
      p_delivery_longitude: lng,
      p_delivery_fees: feeRows,
      p_voucher_code: voucherCode || null,
    });
    if (checkoutError) return reply({ error: checkoutError.message || "Pesanan belum berhasil dibuat." }, 400);
    return reply({ orders: created });
  } catch (error) {
    console.error("checkout-with-delivery:", error);
    return reply({ error: "Terjadi gangguan saat menghitung ongkir atau membuat pesanan. Silakan coba lagi." }, 500);
  }
});
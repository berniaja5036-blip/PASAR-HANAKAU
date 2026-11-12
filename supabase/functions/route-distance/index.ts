import { createClient } from "npm:@supabase/supabase-js@2.119.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://berniaja5036-blip.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Metode tidak diizinkan" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Silakan masuk terlebih dahulu." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !publishableKey) {
      return new Response(JSON.stringify({ error: "Konfigurasi autentikasi tidak tersedia." }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const userClient = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) {
      return new Response(JSON.stringify({ error: "Sesi login tidak valid." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const { data: profile, error: profileError } = await userClient
      .from("profiles")
      .select("account_status")
      .eq("id", authData.user.id)
      .maybeSingle();
    if (profileError || profile?.account_status !== "active") {
      return new Response(JSON.stringify({ error: "Akun tidak aktif." }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json().catch(() => null);
    if (!body || typeof body !== "object") {
      return new Response(JSON.stringify({ error: "Data rute tidak valid" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const { pickup_lat, pickup_lng, delivery_lat, delivery_lng } = body;

    const values = [
      pickup_lat,
      pickup_lng,
      delivery_lat,
      delivery_lng,
    ];

    if (
      values.some((v) => typeof v !== "number" || !Number.isFinite(v)) ||
      Math.abs(pickup_lat) > 90 ||
      Math.abs(delivery_lat) > 90 ||
      Math.abs(pickup_lng) > 180 ||
      Math.abs(delivery_lng) > 180
    ) {
      return new Response(
        JSON.stringify({ error: "Koordinat tidak valid" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const url =
      `https://router.project-osrm.org/route/v1/driving/` +
      `${pickup_lng},${pickup_lat};${delivery_lng},${delivery_lat}` +
      `?overview=false`;

    const response = await fetch(url, { signal: AbortSignal.timeout(12000) });
    const result = await response.json();

    if (!response.ok || result.code !== "Ok" || !result.routes?.length) {
      return new Response(
        JSON.stringify({ error: "Rute jalan tidak ditemukan" }),
        {
          status: 422,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const route = result.routes[0];
    if (typeof route.distance !== "number" || !Number.isFinite(route.distance) || route.distance <= 0 ||
        typeof route.duration !== "number" || !Number.isFinite(route.duration) || route.duration < 0) {
      return new Response(JSON.stringify({ error: "Data rute tidak valid" }), {
        status: 422,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        distance_meters: route.distance,
        distance_km: Math.round(route.distance / 10) / 100,
        duration_seconds: route.duration,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch {
    return new Response(
      JSON.stringify({ error: "Gagal menghitung jarak perjalanan" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

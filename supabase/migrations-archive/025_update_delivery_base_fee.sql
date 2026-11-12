-- Pasar Hanakau: koreksi tarif dasar ongkir sesuai keputusan terbaru.
-- Ongkir tetap nonaktif sampai perhitungan rute jalan selesai diuji.
update public.delivery_fee_settings
set enabled = false,
    base_fee = 2000,
    per_km_fee = 2000,
    minimum_fee = 5000,
    max_distance_km = 15,
    updated_at = now()
where id = true;

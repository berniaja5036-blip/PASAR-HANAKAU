-- Pasar Hanakau: simpan tarif awal ongkir yang telah disepakati.
-- Ongkir tetap NONAKTIF sampai perhitungan jarak jalan selesai diuji.
update public.delivery_fee_settings
set enabled = false,
    base_fee = 3000,
    per_km_fee = 2000,
    minimum_fee = 5000,
    max_distance_km = 15,
    updated_at = now()
where id = true;

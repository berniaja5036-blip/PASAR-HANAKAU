-- Pasar Hanakau: tahap 3 - izin Data API minimum untuk aplikasi web
-- Jalankan setelah 001_initial_schema.sql dan 002_row_level_security.sql.
-- GRANT hanya memberi hak operasi; RLS tetap membatasi baris yang boleh dibaca.

-- Katalog publik: hanya baris yang lolos policy RLS yang dapat terlihat.
grant select on table public.categories to anon, authenticated;
grant select on table public.shops to anon, authenticated;
grant select on table public.products to anon, authenticated;

-- Akun yang sudah masuk dapat membaca profilnya sendiri sesuai policy RLS.
grant select on table public.profiles to authenticated;

-- Tidak memberikan izin tulis langsung untuk pesanan, pembayaran, stok,
-- pengiriman, atau perubahan peran. Fitur tersebut harus melalui proses server
-- yang memvalidasi data dan hak akses.

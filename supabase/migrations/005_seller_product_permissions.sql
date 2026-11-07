-- Pasar Hanakau: izin minimum agar penjual terverifikasi dapat mengelola produk tokonya.
-- RLS pada migrasi 002 membatasi setiap operasi pada toko milik penjual yang disetujui.
grant select on table public.shops to authenticated;
grant select, insert, update, delete on table public.products to authenticated;
grant usage, select on all sequences in schema public to authenticated;

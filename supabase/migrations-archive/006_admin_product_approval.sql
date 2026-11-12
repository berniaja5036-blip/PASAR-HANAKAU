-- Pasar Hanakau: izin admin menerbitkan produk setelah pemeriksaan.
-- Penjual tetap dibatasi oleh policy RLS agar hanya menyimpan draft.
grant update (status) on table public.products to authenticated;

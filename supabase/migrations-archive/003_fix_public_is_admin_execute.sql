-- Pasar Hanakau: izinkan pemeriksaan admin dipanggil oleh pengunjung publik.
-- Fungsi hanya mengembalikan boolean; SECURITY DEFINER dan search_path kosong
-- sudah ditetapkan pada migrasi 002. Tanpa izin ini, kebijakan katalog publik
-- gagal saat dijalankan oleh peran anon.
grant execute on function public.is_admin() to anon, authenticated;

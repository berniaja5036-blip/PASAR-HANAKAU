-- Pasar Hanakau: perbaikan izin fungsi is_admin untuk kebijakan katalog publik.
-- Aman untuk anon: fungsi hanya mengembalikan boolean dan tidak membuka data profil.
grant execute on function public.is_admin() to anon, authenticated;

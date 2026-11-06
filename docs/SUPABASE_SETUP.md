# Menyiapkan proyek Supabase (belum dijalankan)

Langkah ini dilakukan setelah pemilik proyek membuat akun/proyek Supabase sendiri. Jangan kirim password, access token, atau service-role key ke chat maupun ke repositori.

1. Buat proyek Supabase dan simpan kredensial di pengelola rahasia hosting.
2. Buka SQL Editor dan jalankan migration berurutan dari folder `supabase/migrations`.
3. Daftarkan akun pemilik/admin melalui Supabase Auth.
4. Ambil UUID akun admin dari Authentication > Users.
5. Jalankan perintah berikut di SQL Editor dengan UUID akun yang benar:

```sql
insert into public.role_memberships (user_id, role, status)
values ('GANTI_DENGAN_UUID_ADMIN', 'admin', 'approved')
on conflict (user_id, role)
do update set status = 'approved';
```

6. Tetapkan akun penjual/driver melalui proses admin tepercaya setelah pemeriksaan. Jangan memberi pengguna kemampuan menulis langsung ke tabel role_memberships.
7. Uji semua kebijakan RLS dengan akun pembeli, penjual, driver, dan admin sebelum mengaktifkan aplikasi.

Catatan:
- File SQL hanya rancangan awal. Belum ada proyek Supabase yang dibuat atau dihubungkan.
- Checkout, perubahan status, penugasan driver, dan pembayaran harus dibuat sebagai fungsi server transaksional sebelum dipakai.
- Jangan aktifkan pembayaran/top-up uang sungguhan pada tahap prototipe.

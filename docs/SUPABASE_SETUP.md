# Menyiapkan proyek Supabase Pasar Hanakau

Dokumen ini mengikuti skema database yang dipakai website saat ini: `profiles`, `shops`, `categories`, `products`, `orders`, `order_items`, `driver_profiles`, dan `deliveries`.

## Urutan migrasi

Jalankan hanya tiga file berikut, berurutan, melalui Supabase SQL Editor:

1. `supabase/migrations/001_initial_schema.sql`
2. `supabase/migrations/002_row_level_security.sql`
3. `supabase/migrations/003_data_api_grants.sql`

Jangan jalankan file skema alternatif bertanggal `20261106...`; file tersebut memakai rancangan tabel berbeda dan bukan skema yang digunakan website saat ini.

## Akun

1. Daftarkan akun melalui form website.
2. Jika konfirmasi email aktif, buka email dan konfirmasi akun sebelum masuk.
3. Akun baru otomatis dibuat sebagai pembeli.
4. Penetapan admin, penjual, dan driver dilakukan melalui proses admin tepercaya. Jangan izinkan pengguna mengubah perannya sendiri.

Untuk menetapkan admin pertama, setelah akun pemilik terdaftar, ambil UUID akun dari Authentication > Users, lalu jalankan di SQL Editor sebagai pemilik database:

```sql
update public.profiles
set role = 'admin'
where id = 'GANTI_DENGAN_UUID_AKUN_ADMIN';
```

## Keamanan dan batas tahap ini

- File `003_data_api_grants.sql` hanya memberi izin baca minimum pada katalog publik dan profil akun. Row Level Security (RLS) tetap membatasi baris yang terlihat.
- Belum ada checkout transaksional, pengelolaan pesanan lengkap, penugasan driver, atau integrasi pembayaran.
- Jangan gunakan aplikasi ini untuk menerima uang atau pembayaran sungguhan.
- Jangan pernah memasukkan password, service-role key, atau access token ke kode website maupun repositori.
- Publishable key boleh digunakan di browser; keamanan data tetap wajib ditegakkan oleh RLS dan izin database.

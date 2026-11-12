# Menyiapkan proyek Supabase Pasar Hanakau

Dokumen ini mengikuti skema database yang dipakai website saat ini: `profiles`, `shops`, `categories`, `products`, `orders`, `order_items`, `driver_profiles`, dan `deliveries`.

## Urutan migrasi

Untuk database baru, mulai dengan migrasi dasar berikut secara berurutan:

1. `supabase/migrations/001_initial_schema.sql`
2. `supabase/migrations/002_row_level_security.sql`
3. `supabase/migrations/003_data_api_grants.sql`

Fitur aplikasi saat ini juga memerlukan migrasi lanjutan `004` sampai `023` sesuai urutan nomor. Migrasi `202611120015_checkout_request_idempotency.sql` menambahkan perlindungan kunci checkout agar percobaan ulang dengan isi keranjang dan alamat yang sama mengembalikan pesanan yang sudah dibuat, bukan membuat pesanan baru. Pada database yang sudah dipakai, jalankan hanya migrasi yang memang belum diterapkan—jangan mengulang migrasi lama. Khusus migrasi `023_secure_seller_order_read.sql`, jalankan satu kali setelah `022`; migrasi ini menambahkan RPC baca pesanan Seller yang membatasi data dan menghapus kebijakan baca langsung Seller pada tabel `orders`.

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
- Checkout transaksional, pengelolaan status pesanan, permintaan pembatalan, dan penugasan/pembaruan pengiriman Driver sudah tersedia melalui RPC yang memeriksa peran dan stok.
- Pembayaran sungguhan, top-up, dan dompet saldo belum tersedia. Jangan gunakan aplikasi ini untuk menerima uang atau pembayaran sungguhan.
- Jangan pernah memasukkan password, service-role key, atau access token ke kode website maupun repositori.
- Publishable key boleh digunakan di browser; keamanan data tetap wajib ditegakkan oleh RLS dan izin database.

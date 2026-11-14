# Menyiapkan proyek Supabase Pasar Hanakau

Dokumen ini menjelaskan database aktif yang digunakan website Pasar Hanakau: `profiles`, `shops`, `categories`, `products`, `orders`, `order_items`, `driver_profiles`, `deliveries`, dan tabel fitur pendukung.

## Status skema dan migrasi

Proyek aktif memakai riwayat migrasi kanonis 14 digit di `supabase/migrations/`. Per 14 November 2026, terdapat 66 migrasi yang sudah tercatat pada proyek Supabase aktif.

**Penting: folder migrasi aktif bukan paket bootstrap untuk database kosong.** File lama bernomor `001`–`025` dan rancangan alternatif `20261106...` berada di `supabase/migrations-archive/` untuk referensi historis. Jangan jalankan file arsip, jangan menjalankan semua SQL sekaligus, dan jangan mengulang migrasi yang sudah diterapkan. Jika membuat proyek Supabase baru, siapkan baseline skema yang ditinjau khusus atau pulihkan backup tervalidasi terlebih dahulu; jangan memakai file arsip sebagai instalasi baru.

Migrasi penting pada skema aktif:

- `20261112022146_checkout_request_idempotency.sql` menyimpan kunci percobaan checkout per pembeli agar pengulangan permintaan yang sama tidak membuat pesanan ganda.
- `20261114024945_scope_driver_profile_visibility_to_related_orders.sql` membatasi data `driver_profiles`: driver hanya dapat membaca profilnya sendiri, admin dapat membaca untuk pengelolaan, sedangkan pembeli/penjual hanya dapat melihat driver yang ditugaskan pada pesanan yang memang dapat mereka akses.
- `20261114025139_fix_driver_application_review_trim_function.sql` memperbaiki pemeriksaan foto KTP dan wajah saat persetujuan driver dengan fungsi `pg_catalog.btrim` yang valid serta memastikan kedua objek benar-benar tersimpan di bucket privat.
- RPC `seller_list_orders()` sudah tersedia pada database aktif. Hasilnya dibatasi pada nomor/status/tanggal pesanan, catatan untuk penjual, rincian barang milik toko penjual, dan riwayat status. RPC ini tidak mengembalikan alamat atau koordinat GPS pembeli. Instruksi lama tentang `023_secure_seller_order_read.sql` tidak berlaku; file tersebut bukan migrasi kanonis dan tidak boleh dicari atau dijalankan.

## Prosedur perubahan database

1. Periksa riwayat remote dengan `supabase migration list --remote` pada proyek yang benar.
2. Cocokkan setiap versi/nama remote dengan satu file kanonis di `supabase/migrations/`.
3. Tinjau SQL migrasi baru sebelum diterapkan; terapkan hanya migrasi yang memang belum tercatat.
4. Setelah penerapan, periksa ulang riwayat migrasi dan kebijakan/izin yang berubah.
5. Jangan mengedit `supabase_migrations.schema_migrations` secara manual.

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

- Row Level Security (RLS), hak SQL, dan fungsi database harus menegakkan akses; tampilan website bukan batas keamanan.
- Checkout transaksional, pengelolaan status pesanan, permintaan pembatalan, dan penugasan/pembaruan pengiriman Driver tersedia melalui Edge Function/RPC yang memeriksa peran, status akun, stok, dan status pesanan.
- Tarif ongkir masih nonaktif sampai jarak jalan dan penyimpanan tarif diuji menyeluruh. Jangan menganggap estimasi sebagai tagihan final.
- Pembayaran sungguhan, top-up, dan dompet saldo belum tersedia. Jangan gunakan aplikasi ini untuk menerima uang atau pembayaran sungguhan.
- Jangan pernah memasukkan password, service-role key, access token, atau rahasia ke kode website maupun repositori.
- Publishable key boleh digunakan di browser; keamanan data tetap wajib ditegakkan oleh RLS dan izin database.

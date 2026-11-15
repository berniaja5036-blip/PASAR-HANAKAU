# Arsitektur Tiga Aplikasi Pasar Hanakau

Status: rancangan migrasi resmi, 15 November 2026  
Repository: `berniaja5036-blip/PASAR-HANAKAU`  
Branch kerja: `native-android-foundation`

## Tujuan

Pasar Hanakau akan memiliki tiga aplikasi Android terpisah dengan satu backend Supabase. Pemisahan aplikasi adalah pemisahan pengalaman dan jalur distribusi, bukan pemisahan database atau transaksi.

## Aplikasi dan identitas

| Aplikasi | Pengguna | Application ID | Pendaftaran |
|---|---|---|---|
| Pasar Hanakau | Pembeli | `id.pasarhanakau.mobile` (dipertahankan) | Publik, pembeli saja |
| Pasar Hanakau Mitra | Toko dan driver | `id.pasarhanakau.mitra` | Tidak ada pendaftaran bebas; akses diterbitkan/disetujui admin |
| Pasar Hanakau Admin | Pemilik/pengelola | `id.pasarhanakau.admin` | Tidak ada pendaftaran publik |

Application ID aplikasi pembeli dan signing key-nya tidak boleh berubah setelah rilis, agar pembaruan dapat dipasang di atas versi yang sudah ada. Mitra dan Admin memakai application ID serta konfigurasi rilis masing-masing.

## Batas pengalaman pengguna

### Pembeli
- Landing, daftar, dan login hanya sebagai pembeli.
- Katalog, pencarian, kategori, toko, detail produk, wishlist, keranjang, checkout COD, pesanan, status pengiriman, ulasan, chat, dan bantuan.
- Tidak menampilkan menu pengajuan toko/driver atau akses admin.
- Login dengan akun seller/driver/admin ditolak secara jelas dan diarahkan ke aplikasi yang benar.

### Mitra
- Satu aplikasi dengan dashboard berdasarkan hak akses akun.
- Toko: profil toko, produk, stok, pesanan, promosi/iklan, percakapan, laporan.
- Driver: tugas yang ditugaskan, detail pengantaran, status, lokasi dan riwayat.
- Jika satu pengguna disetujui untuk kedua fungsi, aplikasi menampilkan pemilih mode Toko/Driver. Mode tidak memberi hak tambahan; backend tetap memeriksa setiap aksi.
- Pengguna yang belum disetujui atau ditangguhkan tidak dapat memakai fitur operasional.

### Admin
- Aplikasi privat tanpa tombol daftar.
- Hanya akun admin yang dibuat/ditetapkan secara terkendali.
- Pengelolaan persetujuan mitra, toko, produk, pesanan, pengiriman, aduan, biaya, promosi, pembayaran iklan, laporan, dan pengaturan.
- Aksi sensitif dicatat dalam audit log; sesi dapat dicabut; MFA dianjurkan.

## Backend bersama

Satu proyek Supabase tetap menjadi sumber data untuk:
- Auth dan profil;
- katalog, toko, produk dan stok;
- checkout dan pesanan COD;
- penugasan dan status pengiriman;
- chat, ulasan dan notifikasi;
- promosi, tagihan dan laporan.

Aplikasi tidak dipercaya hanya karena nama paket atau karena suatu menu tersembunyi. RLS, fungsi RPC, dan Edge Functions harus memverifikasi identitas, status akun, kepemilikan data, penugasan, dan peran di server.

## Model peran yang perlu dimigrasikan

Saat ini `public.profiles.role` hanya menyimpan satu peran (`buyer`, `seller`, `driver`, `admin`). Fungsi persetujuan seller dan driver mengubah kolom yang sama. Ini belum cukup untuk mendukung satu akun mitra yang dapat menjadi toko sekaligus driver.

Rancangan target:
1. Pertahankan `profiles` sebagai identitas dasar.
2. Tambahkan tabel relasi peran seperti `profile_roles` dengan kunci unik `(user_id, role)`, status `pending/active/suspended/rejected`, waktu persetujuan, dan `approved_by`.
3. Buyer menjadi peran dasar yang diberikan oleh trigger pendaftaran; metadata pengguna tidak boleh memberikan peran istimewa.
4. Seller/driver hanya diberikan melalui alur admin yang memverifikasi permohonan dan dokumen.
5. Admin hanya dapat ditambahkan melalui prosedur admin/bootstrap yang tidak tersedia untuk pengguna publik.
6. Buat helper otorisasi terpusat seperti `has_active_role(user_id, role)`; migrasikan RLS, RPC, trigger, dan Edge Functions secara bertahap agar memeriksa relasi peran.
7. Selama kompatibilitas, `profiles.role` boleh menjadi peran utama sementara, tetapi bukan sumber kebenaran final untuk hak akses multi-peran.
8. Jangan menghapus atau mengubah riwayat akun, toko, driver, pesanan, dan aplikasi lama. Lakukan backfill peran yang sudah disetujui, verifikasi hasilnya, baru pindahkan semua pemeriksaan akses.

## Urutan migrasi

1. **Pembeli terlebih dahulu:** kunci UI publik menjadi buyer-only, pertahankan URL, application ID, signing key, katalog, checkout COD, dan riwayat.
2. **Fondasi peran:** buat tabel peran multi-role, helper, RLS, dan tes; backfill akun yang telah disetujui.
3. **Aplikasi Mitra:** buat entry point dan APK terpisah; uji alur toko dan driver secara end-to-end.
4. **Aplikasi Admin:** buat entry point dan APK privat; audit seluruh fungsi sensitif dan pencatatan aktivitas.
5. **Uji integrasi:** buyer -> seller -> driver -> buyer, pembatalan, stok, jaringan putus, akun suspend, akses lintas pengguna, dan pemulihan sesi.
6. **Rilis bertahap:** internal testing dahulu, lalu pembeli terbatas, kemudian peluncuran publik setelah semua gerbang rilis lulus.

## Gerbang rilis

- Tidak ada pendaftaran role seller/driver/admin dari aplikasi pembeli.
- Pengguna tidak dapat menaikkan role melalui user metadata atau request API buatan sendiri.
- RLS dan RPC mencegah akses lintas toko, lintas pesanan, dan lintas tugas driver.
- Semua aplikasi memakai konfigurasi endpoint dan key publik yang benar; service-role/secret key tidak pernah ada di APK.
- Checkout COD, stok, status pesanan, ongkir, dan penugasan driver lulus pengujian.
- Notifikasi, izin lokasi/kamera, dan pemulihan setelah force-close diuji pada perangkat Android.
- APK/AAB ditandatangani dengan kunci yang benar dan artefak diuji sebelum dibagikan.
- Backup dan prosedur pemulihan telah diverifikasi.

## Batas perubahan pada tahap awal

Jangan menghapus tabel lama, akun, atau data aplikasi. Jangan mematikan fungsi seller/driver yang masih dipakai sistem lama sampai aplikasi Mitra baru lulus pengujian. Jangan merge perubahan buyer-only ke branch `main` sebelum review migrasi dan uji build selesai.

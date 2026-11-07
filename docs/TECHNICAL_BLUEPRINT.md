# Rancangan teknis dan status implementasi Pasar Hanakau

## Ruang lingkup

Marketplace multi-penjual tahap awal untuk Desa Hanakau Jaya, Kecamatan Sungkai Utara, Kabupaten Lampung Utara, Lampung. Aplikasi dibuat responsif agar dapat digunakan melalui browser Android. Pengemasan menjadi APK dapat dipertimbangkan setelah versi web stabil.

## Arsitektur yang berjalan

- Antarmuka: HTML, CSS, dan JavaScript pada `index.html`.
- Backend: Supabase Auth, PostgreSQL, Row Level Security, Storage, dan fungsi RPC.
- Hosting: GitHub Pages melalui GitHub Actions.
- Repositori: `berniaja5036-blip/PASAR-HANAKAU`, branch `main`.

## Peran dan alur yang telah diterapkan

1. Buyer mendaftar/login, melihat produk aktif, menambah ke keranjang, dan checkout.
2. Seller mengajukan toko; Admin menyetujui atau menolak. Seller yang disetujui dapat mengelola produk dan memproses pesanan tokonya.
3. Produk baru menunggu persetujuan Admin sebelum tampil pada katalog Buyer.
4. Checkout dijalankan melalui RPC `checkout_cart`. Fungsi memeriksa akun Buyer, format keranjang, produk aktif, persetujuan toko, dan stok; mengunci baris produk saat transaksi; memisahkan pesanan per toko; lalu mengurangi stok.
5. Admin memantau pesanan, memperbarui status, menyetujui Driver, dan menugaskan Driver untuk pesanan siap dijemput.
6. Driver melihat hanya tugas yang ditugaskan kepadanya, lalu memperbarui status penjemputan dan pengantaran.
7. Perubahan status pesanan direkam di `order_status_history`. Panel pemberitahuan Buyer, Seller, dan Driver membaca status/tugas terbaru dari database.

## Migrasi database

Migrasi berurutan berada di `supabase/migrations/`. Di antaranya:
- `001_initial_schema.sql`: profil, toko, kategori, produk, pesanan, item, driver, dan pengiriman.
- `002_row_level_security.sql` dan migrasi perbaikan berikutnya: kebijakan akses.
- `004`–`008`: pengajuan toko, pengelolaan produk, persetujuan produk, dan penyimpanan gambar.
- `009_secure_cart_checkout.sql`: checkout transaksional dan pemeriksaan stok.
- `010_admin_order_status.sql`: kontrol status pesanan oleh Admin.
- `011_driver_workflow.sql`: pendaftaran, persetujuan, penugasan, dan alur Driver.
- `012_seller_edit_products.sql` dan `013_seller_order_visibility.sql`: pengelolaan produk serta visibilitas pesanan Seller.
- `014_order_status_history.sql`: riwayat status otomatis.

Jangan menjalankan ulang migrasi secara sembarang. Periksa terlebih dahulu migrasi mana yang sudah diterapkan pada proyek Supabase aktif.

## Status pengujian yang pernah dikonfirmasi

- Pengajuan dan persetujuan toko serta produk.
- Buyer menambahkan produk ke keranjang dan membuat pesanan.
- Admin melihat pesanan dan mengubah status.
- Driver disetujui, menerima penugasan, mengonfirmasi penjemputan, lalu pengantaran; Admin melihat status terkirim.
- Seller melihat pesanan tokonya, termasuk rincian barang dan total.
- Seller mengubah dan menghapus produk.
- Unggah foto produk.
- Riwayat status telah dipasang pada database; panel notifikasi Buyer/Seller dan panel pemberitahuan tugas Driver sudah diterapkan di antarmuka. Verifikasi tampilan notifikasi terbaru masih perlu dilakukan oleh pengguna.

## Batasan yang belum selesai

- Pembayaran online, COD terintegrasi, top-up, dan dompet saldo belum tersedia.
- RPC checkout saat ini menetapkan `delivery_fee = 0`; tarif dan mekanisme pembagian biaya pengiriman belum ditetapkan.
- Notifikasi belum memakai push notification browser/Android atau WhatsApp.
- Pembatalan pesanan, refund, sengketa, dan penanganan kegagalan operasional perlu dirancang.
- Belum ada APK Android.
- Pengujian keamanan menyeluruh, privasi, pemulihan backup, dan kesiapan produksi belum selesai.

## Prinsip keamanan

- Terapkan prinsip deny-by-default pada RLS.
- Jangan mengandalkan penyembunyian elemen UI untuk otorisasi.
- Jangan menyimpan password, service-role key, atau rahasia pembayaran di kode klien/repo.
- Fungsi `SECURITY DEFINER` harus memakai `search_path` yang aman, memeriksa peran/otorisasi di dalam fungsi, serta memberi EXECUTE hanya ke role yang diperlukan.
- Pembayaran harus memakai penyedia yang sesuai; verifikasi callback di server, idempotency, rekonsiliasi, refund, dan audit log diperlukan.
- Ledger saldo harus append-only dan hanya ditulis dari transaksi tervalidasi. Jangan membuat atau mengaktifkan uang elektronik internal sebelum kajian hukum dan kemitraan pembayaran.

## Prioritas pengembangan

1. Verifikasi notifikasi dan pengujian ulang alur lengkap semua peran.
2. Rancang aturan tarif pengiriman, pembatalan, dan alur kendala pesanan.
3. Audit RLS, RPC, Storage, validasi input, privasi alamat, serta backup.
4. Evaluasi PWA/push notification setelah izin pengguna dan service worker dirancang.
5. Integrasi pembayaran melalui penyedia yang sesuai setelah rancangan keamanan dan kepatuhan disetujui.
6. Pengemasan Android setelah aplikasi web stabil.

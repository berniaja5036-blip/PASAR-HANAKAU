# Pasar Hanakau

Marketplace multi-penjual untuk tahap awal Desa Hanakau Jaya, Kecamatan Sungkai Utara, Kabupaten Lampung Utara, Lampung.

## Status saat ini

Pasar Hanakau adalah aplikasi web/PWA yang terhubung ke Supabase dan di-host melalui GitHub Pages. Aplikasi masih dalam uji coba terbatas dan **belum siap untuk peluncuran publik atau transaksi uang sungguhan**.

Website: https://berniaja5036-blip.github.io/PASAR-HANAKAU/

## Fitur yang sudah dibangun

- Login dan pendaftaran Buyer, Seller, dan Driver; akses Admin terpisah serta persetujuan peran Seller/Driver.
- Pengajuan dan moderasi toko, katalog, persetujuan produk, serta pengelolaan produk oleh pemilik toko.
- Pencarian dan filter produk, wishlist, keranjang multi-toko, dan fitur beli kembali dari pesanan sebelumnya.
- Checkout melalui Edge Function; harga, stok, voucher, koordinat, dan ongkir diperiksa di server. Kunci idempotensi mencegah pesanan ganda saat permintaan diulang.
- Riwayat pesanan, permintaan pembatalan, status pengiriman, penugasan driver, peta rute, dan ketersediaan driver.
- Chat Buyer–Seller dengan lampiran privat, ulasan produk, dan penilaian driver.
- Panel Admin untuk moderasi akun/toko/produk, statistik, laporan, voucher, pesanan, driver, dan tagihan komisi.
- Notifikasi di dalam aplikasi dan backend Web Push/VAPID.

Fitur-fitur tersebut sudah memiliki implementasi kode/database. Uji simulasi database dalam transaksi yang di-rollback telah lulus untuk pembatasan peran Buyer/Seller/Driver/Admin, pengiriman ulasan dan rating setelah pesanan diterima, serta checkout voucher 10%. Seluruh data simulasi dibatalkan dan tidak tertinggal. Uji penerimaan langsung di browser/perangkat pengguna, notifikasi push, dan pemulihan backup tetap harus diselesaikan sebelum peluncuran publik.

## Batasan yang masih berlaku

- **Tarif ongkir masih nonaktif.** Checkout saat ini menghasilkan ongkir Rp0; jangan menganggapnya sebagai tarif final atau mengaktifkannya sebelum uji jarak jalan dan penyimpanan tarif selesai.
- Pembayaran online, integrasi COD, top-up, dan dompet saldo belum tersedia. Pembayaran barang kepada penjual dan ongkir kepada driver masih di luar aplikasi.
- Backend Web Push sudah tersedia, tetapi pemeriksaan terakhir menemukan **0 langganan perangkat aktif**. Perangkat harus mengaktifkan notifikasi kembali; konfigurasi webhook dan pengiriman juga perlu diuji langsung.
- WhatsApp belum terintegrasi.
- Belum tersedia APK Android; versi sekarang digunakan melalui browser/PWA.
- Ulasan produk dan penilaian driver dapat dikirim pembeli setelah pesanan diterima. Katalog kini menampilkan rata-rata dan jumlah ulasan produk; rincian pesanan menampilkan ringkasan rating driver. Teks ulasan dan identitas pembeli tetap tidak dibuka ke publik.
- Backup dan pemulihan, privasi operasional, serta uji alur Buyer–Seller–Admin–Driver harus diselesaikan sebelum peluncuran publik.

## Peran

- **Admin:** moderasi akun, toko, produk, pesanan, driver, voucher, statistik, dan komisi.
- **Buyer:** melihat katalog, menyimpan wishlist, berbelanja, checkout, chat, dan melacak pesanan.
- **Seller:** mengelola toko/produk, menerima pesanan, chat, dan melihat tagihan komisi.
- **Driver:** melihat ketersediaan dan tugas yang ditugaskan, lalu memperbarui status penjemputan/pengantaran.

## Database dan deployment

- Backend: Supabase (Auth, PostgreSQL, Row Level Security, Storage, RPC, Edge Functions).
- Repositori: `berniaja5036-blip/PASAR-HANAKAU`, branch `main`.
- Website: GitHub Pages melalui GitHub Actions.
- Migrasi database berada di `supabase/migrations/`. Jangan menjalankan ulang migrasi yang sudah diterapkan atau menjalankan seluruh file SQL sebagai satu batch.

## Keamanan

- Jangan memasukkan kata sandi, service-role key, atau rahasia ke repositori maupun browser.
- Hak akses harus ditegakkan oleh RLS, hak SQL, dan fungsi database, bukan hanya tampilan.
- Jangan mengaktifkan pembayaran uang sungguhan sebelum integrasi penyedia pembayaran, verifikasi callback, rekonsiliasi, refund, dan pemeriksaan kepatuhan selesai.
- Pertahankan backup dan uji perubahan di lingkungan yang sesuai sebelum peluncuran.

## Tahap berikutnya

1. Uji penerimaan Buyer–Seller–Admin–Driver menggunakan akun dan data uji khusus.
2. Uji rute dan tarif ongkir tanpa mengaktifkan tarif pada pengguna umum.
3. Aktifkan ulang dan uji notifikasi pada perangkat Android.
4. Uji backup/pemulihan serta pemantauan operasional.
5. Evaluasi PWA dan pengemasan Android setelah alur web stabil.

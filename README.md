# Pasar Hanakau

Marketplace multi-penjual untuk tahap awal Desa Hanakau Jaya, Kecamatan Sungkai Utara, Kabupaten Lampung Utara, Lampung.

## Status saat ini

Pasar Hanakau sudah memiliki prototipe web yang terhubung ke Supabase dan di-host melalui GitHub Pages. Fitur inti telah diuji secara bertahap dengan akun terpisah. Aplikasi masih dalam tahap uji coba terbatas dan **belum siap untuk transaksi atau pembayaran uang sungguhan**.

Website: https://berniaja5036-blip.github.io/PASAR-HANAKAU/

## Fitur yang sudah tersedia

- Login dan pendaftaran dengan pilihan peran Buyer, Seller, dan Driver; akses Admin terpisah.
- Pengajuan toko dan persetujuan oleh Admin.
- Etalase produk, unggah foto, persetujuan produk, serta pengubahan dan penghapusan produk oleh pemilik toko.
- Keranjang dan checkout transaksional melalui Edge Function; stok, harga, ongkir, dan voucher diverifikasi di server, serta kunci idempotensi mencegah pesanan ganda ketika respons jaringan terputus.
- Riwayat pesanan Buyer dan daftar pesanan Seller.
- Panel Admin untuk melihat pesanan, mengubah status, menyetujui pengajuan, dan menugaskan Driver.
- Pengajuan, persetujuan, penjemputan, dan pengantaran oleh Driver.
- Riwayat perubahan status dan panel pemberitahuan di dalam aplikasi untuk Buyer, Seller, dan Driver.

## Batasan yang masih berlaku

- Pembayaran online, COD yang terintegrasi, top-up, dan dompet saldo belum tersedia.
- Biaya pengiriman pada checkout saat ini bernilai Rp0; jangan menganggapnya sebagai tarif final.
- Pemberitahuan saat ini berupa daftar di dalam aplikasi, belum berupa push notification atau WhatsApp.
- Belum ada aplikasi Android APK; versi saat ini dibuka melalui browser.
- Uji coba belum menggantikan pemeriksaan keamanan, privasi, pemulihan data, dan kesiapan operasional sebelum peluncuran publik.

## Peran

- **Admin:** moderasi toko/produk, pemantauan pesanan, pengaturan status, dan penugasan Driver.
- **Buyer:** melihat katalog, mengelola keranjang, checkout, dan melacak pesanan.
- **Seller:** mengelola toko/produk dan memproses pesanan tokonya.
- **Driver:** melihat tugas yang ditugaskan dan memperbarui status penjemputan/pengantaran.

## Database dan deployment

- Backend: Supabase (Auth, PostgreSQL, Row Level Security, Storage, RPC).
- Repositori: `berniaja5036-blip/PASAR-HANAKAU`, branch `main`.
- Deployment website: GitHub Pages melalui GitHub Actions.
- Migrasi database berada di `supabase/migrations/`. Jalankan migrasi sesuai urutan pada proyek Supabase yang benar; jangan menjalankan ulang skrip yang tidak dirancang idempotent.

## Keamanan

- Jangan memasukkan kata sandi, service-role key, atau rahasia pembayaran ke repositori maupun browser.
- Hak akses harus tetap ditegakkan oleh RLS dan fungsi database, bukan hanya tampilan.
- Jangan mengaktifkan pembayaran atau saldo uang sungguhan sebelum integrasi penyedia pembayaran, verifikasi callback, rekonsiliasi, refund, dan pemeriksaan kepatuhan selesai.
- Pertahankan backup dan uji perubahan di lingkungan yang sesuai sebelum peluncuran.

## Tahap pengembangan berikutnya

1. Uji ulang notifikasi dan seluruh alur Buyer–Seller–Admin–Driver.
2. Selesaikan pengaturan operasional seperti tarif pengiriman, pembatalan, dan penanganan kendala pesanan.
3. Perkuat keamanan, validasi, privasi, backup, dan pemantauan.
4. Rancang integrasi pembayaran yang sesuai sebelum menerima uang sungguhan.
5. Evaluasi PWA dan pengemasan Android setelah alur web stabil.

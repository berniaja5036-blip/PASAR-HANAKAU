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
- Validasi arsip backup database/Storage dan pemulihan pada runner terisolasi telah lulus pada 12 November 2026 (72 tabel database dan 8 file dari 4 bucket Storage). Pemulihan ke proyek Supabase baru belum diuji. Uji penerimaan langsung di perangkat dan pemeriksaan privasi operasional tetap perlu sebelum peluncuran publik.

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

### Backup otomatis database dan Storage

Dua workflow backup terpisah tersedia di GitHub Actions. Keduanya berjalan setiap Senin dini hari WIB dan dapat dijalankan manual dari tab Actions:

- **Database backup (weekly and manual):** dump PostgreSQL terenkripsi.
- **Storage backup (weekly and manual):** mengunduh seluruh objek dari bucket `product-images`, `profile-avatars`, `driver-private-documents`, dan `chat-attachments`, lalu mengarsipkan dan mengenkripsinya.

Pastikan Repository secrets berikut tersedia di GitHub (Settings → Secrets and variables → Actions):

1. `SUPABASE_DB_URL`: connection string database dari tombol **Connect** di Supabase Dashboard. Gunakan session pooler bila koneksi langsung tidak tersedia dari runner.
2. `SUPABASE_ACCESS_TOKEN`: Personal Access Token Supabase untuk mengakses Storage melalui CLI. Buat dari pengaturan akun Supabase; berikan hanya akses yang diperlukan dan jangan pernah menaruh token di chat atau commit.
3. `BACKUP_ENCRYPTION_PASSPHRASE`: frasa sandi kuat khusus untuk mengenkripsi backup. Simpan di tempat aman terpisah; tanpa frasa ini backup tidak dapat dibuka.

Setiap artefak disimpan GitHub selama 14 hari. Unduh salinan berkala ke tempat penyimpanan milik sendiri sebelum kedaluwarsa. Backup Storage berisi file objek; metadata bucket dan objek juga ada di database. Jangan kirim connection string, token, password, atau frasa sandi ke chat/repositori. Backup belum dianggap selesai sampai workflow berhasil, file diunduh, dan prosedur pemulihannya diuji pada lingkungan terpisah. Artefak backup GitHub bukan arsip permanen.

## Keamanan

- Jangan memasukkan kata sandi, service-role key, atau rahasia ke repositori maupun browser.
- Hak akses harus ditegakkan oleh RLS, hak SQL, dan fungsi database, bukan hanya tampilan.
- Jangan mengaktifkan pembayaran uang sungguhan sebelum integrasi penyedia pembayaran, verifikasi callback, rekonsiliasi, refund, dan pemeriksaan kepatuhan selesai.
- Pertahankan backup dan uji perubahan di lingkungan yang sesuai sebelum peluncuran.

## Tahap berikutnya

1. Unduh dan simpan artefak backup database serta Storage sebelum masa retensinya berakhir; lakukan uji pemulihan ke proyek Supabase terpisah sebelum peluncuran publik bila lingkungan uji tersedia.
2. Uji penerimaan Buyer–Seller–Admin–Driver menggunakan akun dan data uji khusus.
3. Uji rute dan tarif ongkir tanpa mengaktifkan tarif pada pengguna umum.
4. Aktifkan ulang dan uji notifikasi pada perangkat Android.
5. Uji backup/pemulihan serta pemantauan operasional.
6. Evaluasi PWA dan pengemasan Android setelah alur web stabil.

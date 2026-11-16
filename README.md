# Pasar Hanakau

Marketplace multi-penjual untuk tahap awal Desa Hanakau Jaya, Kecamatan Sungkai Utara, Kabupaten Lampung Utara, Lampung.

## Status saat ini

Pasar Hanakau adalah marketplace web/PWA yang terhubung ke Supabase dan di-host melalui GitHub Pages, dengan aplikasi Android Pembeli terpisah. Sistem masih dalam uji coba terbatas dan **belum siap untuk peluncuran publik atau transaksi uang sungguhan**.

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
- Pembayaran pesanan pembeli saat ini **COD saja** (bayar langsung saat barang diterima); tidak ada payment gateway, top-up, atau dompet saldo. Pembayaran barang kepada penjual dan biaya pengantaran kepada driver masih diselesaikan di luar aplikasi.
- Backend Web Push sudah tersedia dan pengujian notifikasi untuk peran Admin, Driver, Seller, dan Buyer pernah berhasil dilakukan secara terpisah. Pemeriksaan terakhir menemukan satu langganan aktif pada akun Buyer di browser/perangkat yang terakhir digunakan. Satu browser pada satu perangkat tidak otomatis berlangganan untuk semua akun; tiap akun/perangkat perlu mengaktifkan notifikasi sendiri. Pengujian jalur notifikasi dari setiap peristiwa pesanan masih perlu dilanjutkan.
- WhatsApp belum terintegrasi.
- Aplikasi Android Pembeli sudah memiliki beranda dan keranjang native, lalu membuka jalur web khusus pembeli `/buyer/` untuk login, checkout, pesanan, chat, dan akun. GitHub Actions menghasilkan APK dan AAB bertanda tangan untuk pengujian internal; **belum dinyatakan rilis publik karena uji perangkat fisik masih diperlukan**.
- Ulasan produk dan penilaian driver dapat dikirim pembeli setelah pesanan diterima. Katalog kini menampilkan rata-rata dan jumlah ulasan produk; rincian pesanan menampilkan ringkasan rating driver. Teks ulasan dan identitas pembeli tetap tidak dibuka ke publik.
- Validasi arsip backup database/Storage dan pemulihan pada runner terisolasi telah lulus pada 12 November 2026 (73 tabel database dan 8 file dari 4 bucket Storage). Pemulihan ke proyek Supabase baru belum diuji. Uji penerimaan langsung di perangkat dan pemeriksaan privasi operasional tetap perlu sebelum peluncuran publik.

## Aplikasi Android Pembeli (uji coba)

Aplikasi Android saat ini adalah aplikasi hybrid native, bukan Trusted Web Activity (TWA):

- Application ID tetap: `id.pasarhanakau.mobile`; versi build saat ini `1.3.0` (versionCode `4`). Jangan mengubah ID atau signing key karena pembaruan harus tetap dapat dipasang di atas aplikasi yang sudah ada.
- `NativeHomeActivity` menyediakan beranda, pencarian katalog, detail produk, dan keranjang native yang disimpan secara lokal.
- Saat pembeli melanjutkan checkout, `MainActivity` membuka jalur khusus `/buyer/?client=buyer`. Login, checkout COD, riwayat pesanan, chat, dan akun tetap memakai backend serta alur web pembeli yang sama.
- Web root tetap dipertahankan untuk situs umum; aplikasi Android tidak membuka panel Seller, Driver, atau Admin.
- Workflow **Build Pasar Hanakau Android App** membangun APK dan AAB bertanda tangan melalui GitHub Actions menggunakan kunci rilis yang disimpan sebagai GitHub Actions secrets. Jangan menaruh keystore atau kata sandi di repositori/chat.
- Artefak APK/AAB adalah build untuk uji internal, bukan bukti aplikasi sudah lolos uji perangkat atau siap dipublikasikan. Uji instalasi, pemulihan keranjang, login pembeli, checkout COD, lokasi, unggahan, tautan eksternal, dan perilaku saat koneksi terputus masih wajib dilakukan pada HP Android.
- Karena pembungkus saat ini memakai WebView, persyaratan Digital Asset Links untuk TWA bukan gerbang build versi ini. Jangan mengubah hosting/origin hanya untuk memenuhi panduan TWA lama.

Jangan mengunggah AAB ke Play Store atau menyebut APK sebagai rilis publik sebelum uji perangkat, pemeriksaan privasi, dan persyaratan Play Console benar-benar selesai. Website/PWA tetap dipublikasikan terpisah melalui GitHub Pages.

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

**Status rekonsiliasi migrasi (15 November 2026):** pemeriksaan langsung hari ini menemukan 87 catatan migrasi Supabase dan 87 file kanonis di `supabase/migrations/`, dengan 87 pasangan versi/nama cocok, tanpa versi hilang, file tambahan, atau prefix duplikat. Tujuh sumber migrasi yang sebelumnya hilang sudah dipulihkan dari riwayat SQL produksi; isi SQL dicocokkan dan tidak dieksekusi ulang. Migrasi COD-only `20261115082931_disable_legacy_buyer_order_transfer.sql` tercatat di kedua sisi. Sebelum perubahan database berikutnya, cocokkan kembali `supabase migration list --remote` dengan file kanonis dan pastikan backup serta lingkungan uji terisolasi tersedia. Jangan menjalankan arsip, mengulang migrasi, atau mengubah tabel riwayat migrasi secara manual. Lihat `DATABASE_MIGRATION_RECONCILIATION.md` untuk rincian dan prosedur aman.

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

1. Uji APK Pembeli pada HP fisik: instalasi/pembaruan, beranda, keranjang, sinkronisasi ke akun, checkout COD, riwayat pesanan, lokasi, unggahan, dan pemulihan setelah aplikasi ditutup paksa.
2. Lanjutkan audit penerimaan Buyer–Seller–Admin–Driver di akun uji; jangan memakai transaksi uang sungguhan.
3. Selesaikan rancangan multi-role dan aplikasi Mitra/Admin hanya setelah tersedia database uji terisolasi serta seluruh dependensi RLS, RPC, Storage, trigger, dan Edge Function diuji.
4. Uji rute dan tarif ongkir tanpa mengaktifkan tarif pada pengguna umum.
5. Uji notifikasi per peristiwa pesanan dan prosedur pemulihan backup pada lingkungan terpisah.

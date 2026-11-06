# Rancangan teknis Pasar Hanakau

## Batas MVP
Peluncuran terbatas di Desa Hanakau Jaya. Produk bersifat umum dan berasal dari banyak toko.

## Arsitektur yang disarankan
- Antarmuka web responsif/PWA untuk Android.
- Backend terkelola: Supabase (PostgreSQL, Auth, Storage, dan fungsi server) setelah proyek layanan dibuat.
- Hosting web dengan HTTPS.
- Push notification setelah izin pengguna dan service worker tersedia.
- Pembayaran melalui penyedia yang sesuai; jangan membuat penyimpanan uang elektronik sendiri.

## Entitas data inti
profiles; role_memberships; stores; products; orders; order_items; delivery_tasks; payment_transactions. Wallet_accounts dan wallet_ledger baru ditambahkan setelah model pembayaran dan kepatuhan ditetapkan.

## Aturan bisnis awal
1. Pembeli dapat mendaftar dan berbelanja.
2. Toko penjual aktif setelah verifikasi admin.
3. Driver menerima tugas setelah disetujui admin.
4. Harga dan nama produk disalin sebagai snapshot saat checkout.
5. Perubahan status pesanan memiliki riwayat.
6. Penjual hanya mengelola toko dan produk miliknya.
7. Driver hanya melihat tugas yang ditugaskan kepadanya.
8. Hak akses ditegakkan di backend/database (deny by default).

## Keamanan dan uang
- Gunakan autentikasi terkelola; jangan simpan password dalam tabel profil.
- Aktifkan Row Level Security untuk semua tabel yang diakses klien.
- Rahasia server tidak boleh masuk ke browser atau repositori.
- Verifikasi callback pembayaran di server.
- Cegah transaksi ganda dengan idempotency.
- Wallet ledger bersifat append-only dan hanya mencatat transaksi tervalidasi.
- Siapkan pembatalan, refund, sengketa, dan rekonsiliasi.
- Top-up uang sungguhan menunggu penilaian legal dan mitra pembayaran.

## Belum tersedia
Backend produksi, autentikasi aktif, aturan RLS final, pembayaran, notifikasi, dan APK. Prototipe tidak boleh digunakan untuk transaksi nyata.

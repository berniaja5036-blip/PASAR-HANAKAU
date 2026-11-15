# Checklist Migrasi Peran Multi-Aplikasi Pasar Hanakau

Status: audit awal selesai; perubahan database belum diterapkan.
Branch kerja: `native-android-foundation`

## Temuan audit database (15 November 2026)

- `public.profiles.role` hanya menerima satu nilai: `buyer`, `seller`, `driver`, atau `admin`.
- Helper `public.current_user_has_role(text)` memeriksa langsung `profiles.role`; RLS produk, toko, iklan, dan item pesanan bergantung pada helper ini.
- Fungsi operasional yang perlu diperiksa/migrasikan termasuk:
  - Admin: `admin_assign_delivery`, `admin_get_marketplace_statistics`, `is_admin`.
  - Seller: `can_upload_product_image`, `seller_can_read_order`, `seller_list_orders`, `seller_set_shop_pickup_location`, `seller_submit_commission_payment`.
  - Driver: `driver_update_delivery_status`, `current_user_is_assigned_driver` (dipakai oleh kebijakan akses tugas).
  - Buyer: `checkout_cart`, `buyer_confirm_delivery_fee`, `buyer_confirm_order_received`, `buyer_report_delivery_fee_dispute`.
  - Trigger/notifikasi/audit: `capture_admin_audit_row`, `capture_seller_application_admin_audit`, `notify_admin_application_submissions`, `notify_delivery_events`, `notify_order_events`.
- Persetujuan seller dan driver saat ini mengubah kolom `profiles.role`. Ini harus diganti agar persetujuan peran kedua tidak menimpa peran pertama.
- Tidak ada perubahan database yang dilakukan oleh audit ini.

## Audit lanjutan: kebijakan profil, storage, dan fungsi persetujuan

Pemeriksaan langsung database produksi pada 15 November 2026 menemukan:

- Hak kolom untuk role database `authenticated` pada `profiles` hanya SELECT pada kolom `role`; tidak ada UPDATE privilege untuk kolom `role`. Jadi policy `profiles_update_self` yang membatasi baris berdasarkan `id = auth.uid()` tidak dengan sendirinya memberi pengguna kemampuan mengubah perannya.
- Meski begitu, dua RPC admin yang disetujui secara eksplisit menimpa peran tunggal:
  - `approve_seller_application(uuid)` menjalankan `UPDATE profiles SET role = 'seller'`.
  - `admin_review_driver_application(uuid, boolean)` menjalankan `UPDATE profiles SET role = 'driver'`.
  Inilah penyebab struktural mengapa persetujuan peran kedua dapat menggantikan peran pertama.
- Policy Storage untuk dokumen driver membatasi folder berdasarkan UID dan akses baca admin/pemilik. Policy foto produk memanggil `can_upload_product_image`; helper tersebut harus ikut dimigrasikan agar hanya pemilik toko dengan role seller aktif yang dapat mengunggah.
- Tabel `seller_applications` dan `driver_applications` sudah memiliki pembatasan akun aktif, kepemilikan pengajuan, dan pembacaan admin/pemilik. Kebijakan ini harus dipertahankan ketika jalur pendaftaran mitra dipindahkan ke aplikasi Mitra.
- Data role saat ini: 1 admin aktif, 3 buyer aktif, 1 seller aktif, dan 2 driver aktif. Ini hitungan agregat, bukan daftar identitas.
- Kolom `profiles.role` tetap dapat dibaca oleh pengguna terautentikasi, sehingga aplikasi baru tidak boleh menganggap nilai tersebut sebagai sumber kebenaran multi-role setelah migrasi.

## Daftar fungsi yang wajib diubah saat migrasi

- `approve_seller_application(uuid)`: ganti penimpaan role dengan aktivasi peran seller; pertahankan pembuatan toko dan audit.
- `admin_review_driver_application(uuid, boolean)`: ganti penimpaan role dengan aktivasi peran driver; pertahankan verifikasi dokumen KTP/wajah, pembuatan `driver_profiles`, dan status aplikasi.
- `current_user_has_role(text)`: arahkan ke tabel peran baru dengan syarat status active dan akun aktif.
- `can_upload_product_image(text)`: pastikan owner toko punya seller role aktif dan toko approved.
- `seller_can_read_order(uuid)`, `seller_list_orders()`, `seller_set_shop_pickup_location(numeric,numeric)`, `seller_submit_commission_payment(uuid,text)`: audit seluruh pemeriksaan seller.
- `current_user_is_assigned_driver()`, `driver_update_delivery_status(uuid,text,text)`, `admin_assign_delivery(uuid,uuid)`: pastikan akses driver aktif dan penugasan per pesanan tetap ketat.
- `is_admin()`, fungsi statistik dan RPC admin lain: gunakan role admin aktif; jangan membuat jalur pendaftaran admin publik.
- Periksa kembali seluruh policy RLS dan Storage yang memanggil helper lama, bukan hanya policy pada tabel profiles.

## Pengamanan profil yang harus dipertahankan

- Pertahankan hak UPDATE pengguna hanya pada kolom profil yang memang boleh diedit; jangan memberi UPDATE pada `role`, `account_status`, `account_status_note`, atau kolom persetujuan.
- Jangan menambahkan grant UPDATE tabel penuh pada `profiles` untuk authenticated.
- Pastikan proses signup membuat buyer melalui trigger/prosedur tepercaya dan tidak mempercayai role dari metadata yang dikirim klien.

## Model target

Tabel `public.profile_roles`:
- `user_id uuid` FK ke `profiles.id`.
- `role text` dibatasi pada `buyer`, `seller`, `driver`, `admin`.
- `status text` dibatasi pada `active`, `pending`, `suspended`, `rejected`.
- `created_at`, `updated_at`, `approved_at`, `approved_by`.
- Primary/unique key: `(user_id, role)`.

Aturan:
1. Setiap akun baru otomatis mendapat peran buyer aktif dari trigger server; nilai role dari user metadata tidak dipercaya.
2. Seller dan driver hanya aktif setelah persetujuan admin. Permohonan tetap dicatat pada tabel aplikasi yang sudah ada.
3. Satu user dapat memiliki seller dan driver aktif bersamaan.
4. Admin tidak dapat mendaftar sendiri. Pemberian peran admin hanya melalui prosedur bootstrap/administrasi yang terkendali.
5. `profiles.role` dipertahankan sementara untuk kompatibilitas lama; tidak boleh langsung dihapus atau dijadikan sumber tunggal setelah migrasi.
6. Semua helper otorisasi memeriksa `auth.uid()`, status akun aktif, dan status peran aktif. Jangan memakai `raw_user_meta_data` untuk otorisasi.
7. Aplikasi buyer, mitra, dan admin hanyalah pembatas pengalaman; RLS/RPC tetap menjadi sumber keputusan akses.

## Urutan implementasi aman

Catatan Supabase Data API: sejak perubahan platform yang berlaku 30 Oktober 2026, tabel baru pada schema public tidak otomatis diekspos ke Data API. Saat tabel role dibuat, berikan grant hanya kepada role database yang diperlukan dan expose secara eksplisit; RLS tetap wajib aktif. Jangan membuka tabel ini untuk anon.

- [ ] Buat tabel peran dan indeks/constraint dengan RLS aktif serta akses tabel minimum.
- [ ] Backfill peran yang sudah ada berdasarkan profil dan bukti persetujuan:
  - buyer: semua akun yang telah ada tetap mendapat buyer dasar, kecuali kebijakan khusus ditinjau.
  - seller: hanya akun dengan pengajuan seller berstatus approved dan toko valid/approved.
  - driver: hanya akun dengan pengajuan driver approved, profil driver approved, dan dokumen privat yang masih tersedia.
  - admin: hanya akun yang sudah ditetapkan sebagai admin saat ini.
- [ ] Bandingkan jumlah akun dan hasil backfill; pastikan tidak ada peran mitra hilang.
- [ ] Tambahkan helper baru, misalnya `has_active_role(user_id, role)`, dengan `search_path` terkunci dan pemeriksaan identitas.
- [ ] Migrasikan RLS, Storage policies, RPC, trigger, statistik, dan notifikasi agar menggunakan helper baru.
- [ ] Ubah fungsi persetujuan seller/driver agar hanya mengaktifkan baris peran terkait, bukan menimpa `profiles.role`.
- [ ] Ubah signup agar hanya membuat buyer; hapus jalur self-service pengajuan seller/driver dari aplikasi publik saat aplikasi Mitra siap.
- [ ] Jalankan pengujian role escalation, cross-shop, cross-order, driver assignment, akun suspended, dan multi-role.
- [ ] Pertahankan kompatibilitas aplikasi lama sampai aplikasi Mitra/Admin lulus uji dan distribusi pengganti tersedia.
- [ ] Hapus dependensi `profiles.role` hanya pada migrasi terpisah setelah seluruh klien dan fungsi terverifikasi.

## Gerbang sebelum menerapkan migrasi

Jangan menerapkan perubahan skema produksi sebelum:
- daftar lengkap RLS policies, Storage policies, triggers, RPC, dan Edge Functions yang membaca `profiles.role` telah diaudit;
- definisi semua fungsi yang terdampak telah disalin ke migration plan;
- tes regresi untuk alur checkout COD dan pengantaran lulus;
- backup/pemulihan telah diverifikasi;
- migrasi diuji pada database development yang tidak berbayar/diizinkan.

## Catatan distribusi aplikasi

- Buyer mempertahankan application ID dan signing key yang sudah digunakan.
- Mitra memakai application ID terpisah dan hanya menampilkan dashboard peran aktif.
- Admin memakai application ID terpisah, tidak memiliki pendaftaran publik, dan wajib memiliki kontrol sesi serta audit aksi sensitif.
- Tidak ada secret/service-role key di aplikasi Android mana pun.


## Hasil inventaris dependensi terukur (15 November 2026)

Pencarian katalog PostgreSQL pada database aktif menemukan 24 fungsi publik yang definisinya merujuk helper role atau kolom role profil, serta 5 policy RLS yang memanggil helper role. Daftar nama berikut adalah hasil pencarian aktual, bukan asumsi:

**Fungsi (24):**
- `admin_assign_delivery`, `admin_get_marketplace_statistics`, `admin_review_driver_application`, `approve_seller_application`
- `buyer_confirm_delivery_fee`, `buyer_confirm_order_received`, `buyer_report_delivery_fee_dispute`, `checkout_cart`, `checkout_cart_secure`
- `can_upload_product_image`, `current_user_has_role`, `is_admin`
- `capture_admin_audit_row`, `capture_seller_application_admin_audit`, `handle_new_user`
- `driver_confirm_delivery_fee`, `driver_update_delivery_status`
- `notify_admin_application_submissions`, `notify_delivery_events`, `notify_order_events`
- `seller_can_read_order`, `seller_list_orders`, `seller_set_shop_pickup_location`, `seller_submit_commission_payment`

**Policy RLS (5):**
- `marketplace_ads.marketplace_ads_seller_insert_own`
- `order_items.order_items_read_scoped`
- `products.products_seller_insert_own_shop`
- `products.products_seller_update_own_shop`
- `shops.shops_seller_insert_own`

**Implikasi penting:**
- Pemeriksaan langsung kolom `profiles.role` masih muncul di alur penugasan driver, unggah foto produk, verifikasi pembayaran/aktivitas driver, pencatatan audit admin, dan proses persetujuan seller/driver. Migrasi helper saja belum cukup.
- `handle_new_user` adalah trigger signup; sumber role buyer harus tetap ditetapkan di sisi server. Metadata yang dapat diedit pengguna tidak boleh menentukan otorisasi.
- `checkout_cart_secure` merupakan jalur server/service-role. Jangan mengubah validasi identitas pembeli atau membuka RPC ini untuk klien.
- Lima policy di atas harus diubah secara atomik dengan helper baru, lalu diuji menggunakan akun multi-role, akun non-mitra, akun ditangguhkan, dan pemilik toko lain.
- Inventaris ini merupakan pencarian dependensi pada fungsi dan policy yang terdaftar di schema public; pemeriksaan lanjutan masih diperlukan pada definisi lengkap trigger, Edge Functions, klien web/Android, serta policy Storage.

## Keputusan implementasi tahap berikutnya

Belum aman membuat atau menjalankan migrasi produksi. Langkah berikutnya adalah menyiapkan rancangan migrasi bertahap yang mempertahankan kolom lama, mengisi role berdasarkan bukti persetujuan, mengubah seluruh RPC/policy yang terdampak, dan menyediakan rollback. Draft SQL baru boleh dianggap siap setelah definisi lengkap fungsi yang akan diganti dan seluruh aturan Storage/trigger dicocokkan satu per satu. Tidak ada perubahan skema yang diterapkan pada tahap audit ini.


## Audit Storage, trigger, dan Edge Function (15 November 2026)

Pemeriksaan lanjutan menemukan area yang tidak terlihat dari pencarian helper RLS saja:

**Storage policies (14 policy):**
- Dokumen privat driver: `driver_docs_owner_upload`, `driver_docs_owner_read_or_admin`, `driver_docs_owner_delete`. Kepemilikan folder UID dan pembatasan dokumen yang sudah diajukan harus tetap dipertahankan; admin check harus memakai role admin baru.
- Foto produk: `product_images_seller_upload`, `product_images_seller_update`, `product_images_seller_delete` bergantung pada `can_upload_product_image` dan `is_admin`; keduanya harus dimigrasikan.
- Lampiran chat dan avatar menggunakan kepemilikan peserta/UID; jangan memperluas akses hanya karena user memiliki role tambahan.
- Policy `active_account_required` tetap wajib pada seluruh operasi Storage terautentikasi.

**Trigger yang harus diperbarui/ditinjau:**
- `notify_admin_application_submissions` mencari admin dari `profiles.role='admin'`.
- `notify_order_events` mencari penerima notifikasi admin dari `profiles.role='admin'`.
- `capture_seller_application_admin_audit` memverifikasi admin melalui `profiles.role='admin'`.
- `capture_admin_audit_row` mencatat keputusan review driver dan aksi admin lain; pastikan aktor tetap diverifikasi sebagai admin aktif melalui helper baru.
- Trigger lain untuk chat, pengiriman, komisi, riwayat pesanan, dan sinkronisasi profil juga harus diuji regresi, walaupun tidak semuanya membaca role langsung.

**Edge Functions aktif (4) yang diperiksa:**
- `checkout-with-delivery`: memeriksa `profiles.role === 'buyer'` sebelum checkout. Harus memakai role buyer aktif, bukan kesetaraan role tunggal, supaya akun buyer yang sekaligus seller/driver tetap dapat berbelanja.
- `admin-account-management`: memeriksa `profiles.role === 'admin'` dan daftar akun memakai filter role tunggal. Endpoint ini harus berpindah ke role admin aktif dan menampilkan multi-role tanpa membuka jalur admin publik. Fungsi memverifikasi JWT pengguna sendiri walaupun konfigurasi gateway `verify_jwt=false`; verifikasi ini tidak boleh dihilangkan.
- `push-notifications`: pendaftaran langganan memeriksa status akun; pengiriman memakai data penerima dari notifikasi. Pertahankan autentikasi dan pembatasan akun.
- `route-distance`: memeriksa status akun aktif, bukan role tunggal; tidak perlu mengubah pemeriksaan role kecuali kebijakan produk menetapkan pembatasan khusus.

**Kesimpulan audit tambahan:** migrasi tidak boleh hanya mengganti `current_user_has_role`. Harus mencakup tiga Edge Function yang membaca profil/otorisasi, empat trigger/admin-notification/audit di atas, dan policy Storage foto produk/dokumen driver. Tidak ada kode Edge Function, trigger, policy, atau skema produksi yang diubah pada audit ini.

# Audit Ketergantungan Role pada Kode Aplikasi

Tanggal pemeriksaan: 15 November 2026  
Branch: `native-android-foundation`  
Tujuan: mencocokkan rancangan tiga aplikasi dengan kode yang benar-benar tersimpan pada branch.

## Ringkasan hasil

**Pemisahan tiga aplikasi belum diwujudkan pada kode aplikasi.** Dokumen arsitektur adalah target, bukan kondisi implementasi saat ini. Temuan berikut berasal dari pembacaan file branch `native-android-foundation`.

| Area | File | Kondisi aktual | Dampak |
|---|---|---|---|
| Antarmuka web pembeli | `index.html` | Masih memiliki CSS `.rolegrid`, `.rolecard`, `.landing-roles` dan tampilan pemilih role | Belum memenuhi ketentuan aplikasi pembeli yang hanya untuk buyer |
| Checkout | `supabase/functions/checkout-with-delivery/index.ts` | Membaca `profiles.role` dan mensyaratkan nilainya tepat `buyer` | Akun multi-role yang kolom lamanya berisi seller/driver akan ditolak checkout |
| Admin API | `supabase/functions/admin-account-management/index.ts` | Verifikasi admin dan daftar akun memakai kolom `profiles.role` | Admin multi-role dan daftar multi-role belum didukung |
| Native buyer home | `android/app/src/main/java/id/pasarhanakau/mobile/NativeHomeActivity.kt` | Tidak ditemukan pembacaan role langsung pada file ini | Tetap perlu memverifikasi titik login WebView dan jalur masuk aplikasi |
| WebView | `android/app/src/main/java/id/pasarhanakau/mobile/MainActivity.java` | Memuat situs GitHub Pages yang sama | Pemisahan aplikasi Android tidak bisa hanya dilakukan dengan mengganti dashboard di web; harus ada identitas aplikasi dan pembatasan server |

## Temuan implementasi yang perlu ditangani

### 1. Aplikasi pembeli masih menampilkan pilihan role

Pada `index.html` ditemukan gaya pemilih role lama dan bagian landing `landing-roles`. Ini bertentangan dengan keputusan bahwa aplikasi pembeli hanya memiliki daftar/login pembeli dan tidak menawarkan pengajuan toko, driver, atau admin.

**Perbaikan yang direncanakan:** jadikan buyer sebagai jalur pendaftaran publik tunggal; hilangkan pemilih role dari pengalaman buyer. Alur pengajuan mitra dipindahkan ke aplikasi Mitra atau proses undangan/persetujuan admin. Tidak boleh sekadar menyembunyikan tombol: endpoint, RPC, dan RLS tetap harus menolak eskalasi role oleh klien.

### 2. Checkout mengunci role tunggal

Fungsi checkout mengambil `role,account_status` dari profil dan menolak selain `role === 'buyer'`. Setelah model multi-role aktif, validasi yang benar adalah: pengguna terautentikasi, akun aktif, dan mempunyai entri role buyer berstatus aktif. Status buyer tidak boleh disimpulkan dari metadata pengguna atau input request.

### 3. Edge Function admin memakai role tunggal

Fungsi admin memeriksa `adminProfile.role === 'admin'` dan mengambil akun melalui filter `role` tunggal. Perubahan harus menggunakan role admin aktif yang berasal dari tabel otorisasi server, serta daftar semua role aktif per akun. Akses endpoint harus tetap memverifikasi JWT dan status akun pada setiap request.

### 4. Aplikasi Mitra dan Admin belum menjadi modul Android terpisah

Pada pohon file branch yang diperiksa, modul Android hanya memiliki satu `android/app` dan satu application ID. Belum ditemukan modul/package Mitra atau Admin. Dokumen arsitektur menyebut ID target `id.pasarhanakau.mitra` dan `id.pasarhanakau.admin`, tetapi belum ada modul build untuk keduanya.

## Urutan implementasi aman

1. Selesaikan inventaris semua referensi role pada SQL, policy, trigger, Storage, Edge Functions, dan JavaScript.
2. Siapkan migration SQL bertahap pada branch saja; jangan jalankan di project produksi sebelum pengujian dan backup terverifikasi.
3. Tambahkan helper otorisasi multi-role dan migrasikan seluruh RPC/RLS/Storage/trigger secara konsisten, tetap pertahankan `profiles.role` selama masa kompatibilitas.
4. Ubah checkout dan admin Edge Function agar memeriksa role aktif melalui sumber otorisasi baru.
5. Pisahkan antarmuka buyer dari alur mitra/admin dan tambahkan pengujian akses server-side.
6. Tambahkan modul Android Mitra dan Admin dengan package ID berbeda; pertahankan package ID serta signing buyer yang ada.
7. Uji akun buyer, seller, driver, admin, akun multi-role, akun ditangguhkan, serta akses silang toko/pesanan/driver sebelum rilis.

## Larangan selama transisi

- Jangan hapus atau menimpa `profiles.role` sebelum semua klien, fungsi, trigger, dan policy berpindah.
- Jangan memberi pengguna kemampuan menulis role sendiri.
- Jangan mengubah akun yang ada berdasarkan asumsi; role mitra harus ditopang status persetujuan dan data aplikasi yang sah.
- Jangan deploy Edge Function baru atau menerapkan migration pada database produksi dalam tahap audit.
- Jangan menggabungkan branch kerja ke `main` sebelum seluruh skenario akses diuji.

## Status

Dokumen ini mencatat audit kode, bukan klaim bahwa pemisahan aplikasi atau multi-role telah selesai. Pada commit audit ini tidak ada file aplikasi, Edge Function, atau database produksi yang diubah.

## Pemeriksaan lanjutan database dan alur autentikasi — 15 November 2026

### Hasil pemeriksaan Auth dan halaman publik

- Landing page aktif pada index.html hanya menampilkan tombol Masuk/Daftar pembeli dan CTA Mulai Belanja. Bagian .landing-roles masih berupa CSS lama, tetapi markup panel role lama tidak muncul pada halaman utama yang diperiksa. Jadi temuan sebelumnya perlu diperjelas: pemilih role mitra tidak sedang ditampilkan di landing publik saat ini.
- Form pendaftaran mengirim requested_role dalam metadata pengguna, tetapi trigger public.handle_new_user() secara eksplisit mengabaikan metadata role tersebut dan selalu membuat profiles.role = buyer. Ini adalah pengaman yang benar dan wajib dipertahankan.
- Panel pengajuan toko, pendaftaran driver, dashboard seller, driver, dan admin masih ada di satu index.html. Dashboard ditentukan setelah login berdasarkan profiles.role; ini belum memenuhi pemisahan tiga aplikasi.
- refreshSession() mengambil kolom role tunggal dan melakukan sign-out/menolak akses bila status akun tidak aktif atau role tidak dikenali. Perubahan role harus mengganti sumber keputusan UI ini dengan role aktif yang tervalidasi server, bukan menghapus pemeriksaan status.
- Tombol kembali dari form auth masih bernama backToRoles, tetapi mengarah ke beranda pembeli. Penamaan/flow ini bisa dirapikan saat UI buyer dipisahkan.

### Inventaris dependensi role yang dibaca langsung dari database

Query pada database produksi menemukan 24 fungsi public yang merujuk profiles.role atau current_user_has_role():

1. admin_assign_delivery
2. admin_get_marketplace_statistics
3. admin_review_driver_application
4. approve_seller_application
5. buyer_confirm_delivery_fee
6. buyer_confirm_order_received
7. buyer_report_delivery_fee_dispute
8. can_upload_product_image
9. capture_admin_audit_row
10. capture_seller_application_admin_audit
11. checkout_cart
12. checkout_cart_secure
13. current_user_has_role
14. driver_confirm_delivery_fee
15. driver_update_delivery_status
16. handle_new_user
17. is_admin
18. notify_admin_application_submissions
19. notify_delivery_events
20. notify_order_events
21. seller_can_read_order
22. seller_list_orders
23. seller_set_shop_pickup_location
24. seller_submit_commission_payment

RLS policy yang secara eksplisit bergantung pada pemeriksaan role/profil mencakup driver_presence.driver_presence_insert_approved_self, driver_presence.driver_presence_update_approved_self, driver_profiles.driver_profiles_read_scoped, marketplace_ads.marketplace_ads_seller_insert_own, order_items.order_items_read_scoped, products.products_seller_insert_own_shop, products.products_seller_update_own_shop, dan shops.shops_seller_insert_own. Policy lain yang memakai helper is_admin() atau current_user_is_active() tetap harus direview karena helper tersebut juga bergantung pada model role/status.

### Approval dan trigger

- approve_seller_application(uuid) hanya dapat dijalankan admin, mengunci aplikasi pending, memeriksa koordinat pickup, lalu saat ini menimpa profiles.role menjadi seller dan membuat/memperbarui toko.
- admin_review_driver_application(uuid, boolean) hanya dapat dijalankan admin, memeriksa bahwa foto KTP dan wajah benar-benar tersimpan di bucket privat pada folder UID pemohon, lalu saat ini menimpa profiles.role menjadi driver dan mengaktifkan driver_profiles.
- Dua fungsi approval di atas harus mengaktifkan role tambahan di tabel role baru tanpa menghilangkan role buyer. Semua validasi file privat, koordinat, status aplikasi, dan pencatatan audit wajib tetap utuh.
- Trigger notify_admin_application_submissions dan notify_order_events mencari penerima admin melalui profiles.role='admin'. Trigger audit capture_admin_audit_row dan capture_seller_application_admin_audit juga memverifikasi admin melalui role tunggal. Ini wajib ikut dialihkan ke helper multi-role.

### Edge Functions aktif pada project

Pemeriksaan project menunjukkan empat Edge Functions aktif:

- checkout-with-delivery (versi 14, JWT verification aktif): memanggil auth.getUser(), tetapi kemudian membaca profiles.role melalui service-role dan hanya menerima role tunggal buyer. Ini akan menolak akun yang sekaligus seller/driver setelah migrasi jika role utama lama bukan buyer.
- admin-account-management (versi 13, gateway JWT verification nonaktif): fungsi memverifikasi Bearer token dengan auth.getUser(token) sendiri, lalu memeriksa profiles.role='admin'. Daftar akun juga menggunakan filter role tunggal dan tidak menyertakan akun admin. Perlu multi-role tanpa melemahkan verifikasi JWT, audit, maupun penggunaan service-role.
- push-notifications (versi 20, JWT verification nonaktif): alur harus tetap memvalidasi identitas/izin di dalam fungsi; jangan mengubah pengaturan verifikasi tanpa membaca seluruh implementasi.
- route-distance (versi 10, JWT verification aktif): tetap perlu mempertahankan pemeriksaan status akun dan batas akses yang sudah ada.

### Data akun saat pemeriksaan

Database produksi berisi 7 profil aktif: 1 admin, 3 buyer, 1 seller, dan 2 driver. Pemeriksaan hanya menggunakan agregat; identitas/email/nomor telepon tidak disalin ke dokumen ini. Data ini tidak cukup untuk menebak bahwa seluruh akun seller/driver juga buyer, sehingga backfill role buyer tidak boleh dilakukan secara membabi buta. Pesanan historis, aplikasi yang disetujui, toko, driver_profiles, dan status akun harus menjadi bukti pemetaan role.

### Risiko dan penghambat sebelum migrasi

- Advisor keamanan Supabase melaporkan 28 fungsi SECURITY DEFINER dapat dieksekusi role authenticated. Ini bukan bukti bahwa semuanya rentan, tetapi daftar tersebut wajib diperiksa satu per satu untuk memastikan pemeriksaan role/ownership ada dan hak EXECUTE sesuai kebutuhan. Jangan mencabut seluruh hak secara massal karena aplikasi mungkin bergantung pada RPC tersebut.
- Project tidak memiliki development branch Supabase yang tersedia saat pemeriksaan. Karena itu belum ada lingkungan database terisolasi untuk mencoba migration multi-role dan menguji rollback.
- Perubahan tabel baru di schema public memerlukan perhatian khusus pada RLS, GRANT, dan pengaturan Data API. Jangan membuka akses anon; jangan memberi pengguna hak UPDATE pada kolom role atau status.
- Tidak ada migration produksi, perubahan data, deploy Edge Function, ataupun perubahan policy yang dilakukan selama pemeriksaan ini.

### Gerbang keselamatan untuk tahap implementasi

1. Selesaikan pemetaan akun lama tanpa mengekspos identitas pribadi; buat rencana backfill per akun berdasarkan bukti aplikasi/toko/driver dan pesanan.
2. Siapkan migration bertahap yang mempertahankan profiles.role sebagai kompatibilitas sementara, dan uji pada database non-produksi sebelum rilis.
3. Migrasikan seluruh fungsi, policy, Storage policy, trigger, dan Edge Functions dalam satu urutan kompatibel. Jangan mengaktifkan helper multi-role sebagian saat klien lama masih mengandalkan role tunggal.
4. Uji buyer-only, seller-only, driver-only, admin-only, akun multi-role, akun ditangguhkan, eskalasi role dari metadata, akses silang toko/pesanan, dokumen driver, dan notifikasi.
5. Baru setelah itu pisahkan modul APK buyer, Mitra, dan Admin; pertahankan application ID serta signing buyer yang sudah dipakai.

### Bukti tambahan untuk migrasi akun lama

Agregat relasi data saat audit menunjukkan: 1 akun seller aktif memiliki 1 toko dan 1 aplikasi seller approved; 2 akun driver aktif masing-masing memiliki aplikasi driver approved dan driver_profiles approved; di antara 2 akun driver tersebut, satu akun memiliki riwayat pesanan sebagai pembeli. Satu dari 3 akun buyer aktif memiliki riwayat pesanan. Ini menguatkan bahwa model lama memang dapat menimpa role buyer ketika persetujuan mitra diberikan. Backfill buyer untuk akun mitra harus diputuskan berdasarkan riwayat pendaftaran dan data terkait, bukan hanya nilai profiles.role sekarang.

### Storage policies dan izin kolom profil

Storage memiliki policy terpisah untuk dokumen driver privat, gambar produk, lampiran chat, avatar, serta pembatasan akun aktif. Policy dokumen driver mempertahankan folder UID pemilik dan akses baca admin; policy gambar produk bergantung pada can_upload_product_image() dan is_admin(); lampiran chat dibatasi ke peserta percakapan. Semua policy ini harus diuji ulang setelah helper role berubah, khususnya akses baca dokumen KTP/wajah dan unggah/hapus gambar toko.

Izin kolom profiles yang terbaca untuk authenticated hanya SELECT pada role/status dan UPDATE pada full_name, phone, serta full_address. Tidak ada UPDATE grant pada role, account_status, account_status_note, atau account_status_updated_at. Pembatasan ini adalah kontrol keamanan yang harus dipertahankan; jangan menggantinya dengan GRANT UPDATE tingkat tabel.

### Catatan advisor performa

Advisor performa saat audit menandai 5 foreign key tanpa indeks penutup dan 7 kasus beberapa policy permisif pada operasi yang sama; juga 23 indeks belum pernah dipakai pada statistik saat itu. Ini bukan alasan untuk menghapus indeks atau merombak policy secara otomatis. Setelah fitur stabil, periksa masing-masing berdasarkan query plan dan beban nyata. Perubahan role jangan digabung dengan optimasi indeks/policy yang tidak terkait.

### Pemeriksaan mendalam Edge Function dan helper SQL

Pembacaan source aktif memperluas daftar fungsi role-dependent:

- admin-account-management: verifikasi admin melalui profiles.role; daftar akun memakai filter role tunggal; proses suspend/resume memilih tindakan seller atau driver berdasarkan satu nilai role. Dalam model multi-role, tindakan suspend harus mempertimbangkan semua role aktif dan seluruh aset/pekerjaan yang terkait, bukan hanya role pertama.
- push-notifications (versi 20): endpoint pengaturan kunci push memverifikasi profiles.role='admin' dan account_status='active'. Endpoint pendaftaran/perangkat memeriksa account_status aktif; jangan sampai pemeriksaan admin terlewat saat multi-role.
- checkout-with-delivery: verifikasi buyer tunggal sudah dicatat di atas.
- route-distance hanya memeriksa account_status aktif; tidak ada keputusan role tunggal pada source yang diperiksa.

Helper SQL saat ini: current_user_has_role(required_role) memeriksa profiles.role dan account_status='active'; is_admin() memanggil helper tersebut untuk role admin; current_user_is_active() hanya memeriksa status akun aktif. Ketiganya harus dipisahkan secara jelas saat model role baru diterapkan: helper role membaca role aktif, helper status tetap memblokir akun ditangguhkan, dan admin tidak boleh diwariskan dari metadata pengguna.

Fungsi admin_assign_delivery juga memeriksa profiles.role='driver' dan account_status aktif sebelum memeriksa driver_profiles.approval_status, dokumen privat, status pesanan, serta tugas driver lain. Semua pemeriksaan tersebut tetap wajib; sumber role driver saja yang berpindah ke tabel role baru. admin_get_marketplace_statistics menghitung total buyer/seller/driver dari profiles.role dan perlu menghitung role aktif dari tabel baru agar statistik tidak kehilangan akun multi-role.

Trigger notify_order_events mencari admin melalui profiles.role='admin' (source yang diperiksa tidak memfilter account_status pada jalur notifikasi pesanan), sedangkan notify_admin_application_submissions juga memeriksa account_status aktif. Saat migrasi, notifikasi admin harus memakai daftar admin aktif dan tetap mencegah duplikasi event.

### Rekonsiliasi cabang GitHub

Cabang kerja diselaraskan dengan empat commit terbaru dari main untuk file rekonsiliasi migrasi, skrip validasi, pengarsipan migration agregat yang sudah superseded, serta koreksi nama migration voucher sesuai versi yang sudah tercatat di Supabase. Perubahan UI akses Penjual/Driver/Admin dari main sengaja tidak disalin ke index.html cabang kerja karena bertentangan dengan keputusan aplikasi Pembeli yang hanya untuk buyer. Perbaikan pemeriksaan harga/stok keranjang dari main telah diintegrasikan, dan jalur impor keranjang native kini memiliki fungsi sinkronisasi yang memeriksa ulang produk, harga, stok, serta status toko sebelum data disimpan ke keranjang web.

### Dasar pemetaan role awal (tanpa menampilkan identitas)

Query agregat tambahan menunjukkan seluruh 7 profil memiliki pasangan auth.users dan waktu pembuatan profil berjarak kurang dari 5 detik dari waktu pembuatan akun Auth. Profil seller memiliki satu aplikasi seller approved dan satu toko; kedua profil driver memiliki aplikasi driver approved dan driver_profiles approved; satu dari dua profil driver juga memiliki riwayat sebagai pembeli. Tidak ada profil tanpa pasangan Auth.

Rencana backfill yang paling konservatif berdasarkan bukti saat ini: pertahankan role admin untuk akun admin saja sampai status buyer akun itu dikonfirmasi; buat role buyer bagi 3 akun yang sekarang buyer; untuk akun seller/driver yang memiliki akun Auth dan aplikasi mitra yang telah disetujui, pulihkan role buyer dasar lalu tambahkan role seller/driver aktif sesuai bukti aplikasi, toko, dan driver_profiles yang approved. Nilai raw_user_meta_data.requested_role tidak boleh dipakai sebagai sumber otorisasi atau satu-satunya bukti backfill. Sebelum menjalankan migrasi, lakukan dry-run SELECT yang menampilkan hanya jumlah per role dan daftar konflik tanpa email/nomor telepon.

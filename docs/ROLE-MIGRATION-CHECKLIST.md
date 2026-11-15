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

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

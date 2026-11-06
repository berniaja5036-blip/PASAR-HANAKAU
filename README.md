# Pasar Hanakau

Marketplace multi-penjual untuk tahap awal Desa Hanakau Jaya, Kecamatan Sungkai Utara, Kabupaten Lampung Utara, Lampung.

## Status
Tahap fondasi dan prototipe antarmuka. Belum siap menerima transaksi atau uang sungguhan.

## Peran
- Admin: moderasi anggota, toko, produk, pesanan, dan penugasan driver.
- Pembeli: mencari produk, memesan, membayar, dan melacak pengiriman.
- Penjual: mengelola toko, katalog, stok, dan pesanan.
- Driver: menerima tugas penjemputan dan pengantaran.

## Prinsip keamanan
- Penjual dan driver harus disetujui admin.
- Hak akses diperiksa di server/database, bukan hanya disembunyikan di antarmuka.
- Jangan menyimpan kata sandi atau rahasia pembayaran di kode sumber.
- Pembayaran dan saldo memerlukan pencatatan transaksi serta mitra pembayaran yang sesuai.
- Jangan aktifkan top-up uang sungguhan sebelum integrasi, rekonsiliasi, dan pemeriksaan kepatuhan selesai.

## Tahapan
1. Fondasi antarmuka dan identitas proyek.
2. Backend, autentikasi, database, dan aturan akses.
3. Toko, katalog, dan stok.
4. Keranjang, checkout, dan pesanan.
5. Panel admin dan penugasan driver.
6. Pembayaran, notifikasi, pengujian, dan rilis.

## Prototipe
Buka `index.html` di browser. Halaman ini hanya prototipe visual; belum memiliki autentikasi atau penyimpanan transaksi online.

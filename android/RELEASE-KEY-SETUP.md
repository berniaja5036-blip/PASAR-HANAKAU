# Menyiapkan kunci rilis Android Pasar Hanakau

Panduan ini diperlukan satu kali untuk menyiapkan kunci permanen TWA.

## Identitas aplikasi (jangan diubah setelah rilis)

- Package ID: `id.pasarhanakau.mobile`
- Keystore file: `pasar-hanakau.keystore`
- Alias: `pasar-hanakau`
- Masa berlaku yang disarankan: 10.000 hari

## 1. Buat keystore di perangkat sendiri

Gunakan Termux dari sumber resminya (F-Droid atau GitHub resmi Termux), lalu pasang Java yang menyediakan perintah `keytool`. Jangan gunakan aplikasi Termux dari situs unduhan tidak resmi.

Di Termux, jalankan:

```sh
pkg update
pkg install openjdk-21
mkdir -p ~/pasar-hanakau-release
cd ~/pasar-hanakau-release
keytool -genkeypair -v \
  -keystore pasar-hanakau.keystore \
  -alias pasar-hanakau \
  -keyalg RSA -keysize 2048 -validity 10000
```

Saat diminta, buat password kuat. Simpan password dan file keystore di tempat aman yang terpisah. Jangan kirim password atau file keystore melalui chat, email publik, atau repositori.

**Jangan membuat keystore baru setelah aplikasi rilis.** Pembaruan aplikasi harus ditandatangani dengan kunci yang sama.

## 2. Ambil SHA-256 fingerprint

Jalankan:

```sh
keytool -list -v -keystore pasar-hanakau.keystore -alias pasar-hanakau
```

Masukkan password keystore saat diminta. Catat nilai **SHA256** (format dua digit heksadesimal dipisahkan titik dua). Fingerprint ini bukan password dan akan dipakai untuk Digital Asset Links.

## 3. Siapkan nilai rahasia untuk GitHub Actions

Encode keystore menjadi satu baris Base64:

```sh
base64 -w 0 pasar-hanakau.keystore
```

Salin hasil Base64 secara privat. Jangan menempelkannya ke chat atau file publik.

Di GitHub, buka repositori **PASAR-HANAKAU → Settings → Secrets and variables → Actions → New repository secret**. Tambahkan tiga secret dengan nama persis:

- `ANDROID_KEYSTORE_BASE64` — isi dengan hasil Base64 keystore.
- `ANDROID_KEYSTORE_PASSWORD` — password keystore.
- `ANDROID_KEY_PASSWORD` — password untuk alias/key (jika saat pembuatan diminta sama, gunakan password yang sama).

Jangan mengubah nama secret. Setelah tersimpan, GitHub menyembunyikan nilainya.

## 4. Terbitkan domain verification

Setelah fingerprint tersedia, tambahkan file `.well-known/assetlinks.json` pada repositori domain utama `berniaja5036-blip.github.io` dengan package ID `id.pasarhanakau.mobile` dan fingerprint SHA-256 yang benar.

File wajib dapat diakses melalui HTTPS di `https://berniaja5036-blip.github.io/.well-known/assetlinks.json`, tanpa redirect, dan disajikan sebagai JSON. Jangan memakai fingerprint contoh.

## 5. Build

Setelah GitHub Pages aktif, file Digital Asset Links dapat diakses, dan ketiga secrets sudah tersimpan, jalankan workflow **Android TWA build** dari tab Actions di repositori PASAR-HANAKAU. Workflow akan memeriksa kecocokan sertifikat sebelum membuat APK dan AAB.

## Keamanan dan cadangan

- Simpan minimal dua cadangan offline keystore dan password.
- Jangan commit file `.keystore`, hasil Base64, atau password.
- Jangan kehilangan keystore. Jika hilang, pembaruan aplikasi yang sudah ditandatangani dengan kunci tersebut dapat terhambat.

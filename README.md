<p align="center">
  <img src="assets/icons/logo_sik3_transparent.png" width="120" alt="SiK3 Logo" />
</p>

<h1 align="center">SiK3</h1>

<hr />

<p align="center">
  <b>Sistem Inspeksi K3 Bengkel Sekolah (Offline-First Android App)</b><br />
  Aplikasi Android Flutter dual-peran (Mode Guru ber-PIN lokal &amp; Mode Siswa tanpa login) untuk inspeksi kelengkapan 6 Alat Pelindung Diri (APD) bengkel sekolah melalui QR identitas, pemindaian kamera 2-zona berbasis TFLite modular, validasi draft SQLite lokal, dan ekspor laporan PDF A4 resmi bertanda tangan.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PLATFORM-FLUTTER%20ANDROID%2024%2B-0d2d4d?style=for-the-badge&logo=flutter&logoColor=white&labelColor=1e3a5f" alt="Flutter Android" />
  <img src="https://img.shields.io/badge/MODE-100%25%20OFFLINE--FIRST-0d2d4d?style=for-the-badge&labelColor=1e3a5f" alt="Offline-First" />
  <img src="https://img.shields.io/badge/ML-TFLITE%20%2B%20OPTIONAL%20VISION%20AI-0d2d4d?style=for-the-badge&labelColor=1e3a5f" alt="TFLite + Vision AI" />
  <img src="https://img.shields.io/badge/REPORT-A4%20PDF%20GENERATOR-0d2d4d?style=for-the-badge&labelColor=1e3a5f" alt="A4 PDF" />
  <img src="https://img.shields.io/badge/LICENSE-MIT-0d2d4d?style=for-the-badge&labelColor=1e3a5f" alt="MIT License" />
</p>

<br />

---

## Fitur Utama

- **Single-APK Dual-Role Offline:** Memisahkan **Mode Guru** (terlindungi PIN lokal 4–6 digit) dan **Mode Siswa** (tanpa login/server akun) dalam satu aplikasi Android ringan.
- **Kartu QR Identitas Offline + Input Manual:** Siswa menyimpan profil lokal (Nama, NISN, No. Presensi, Kelas, Jurusan) dan menampilkan kartu QR berpayload JSON `v=1` dengan checksum CRC16-CCITT; tersedia cadangan input manual saat siswa tidak membawa ponsel.
- **6 Standar APD Bengkel Kustom Per Kelas:** Mendukung konfigurasi wajib/opsional untuk `baju_praktik`, `helm`, `kacamata`, `masker`, `sarung_tangan`, dan `sepatu_bengkel` lengkap dengan ikon vektor SVG murni.
- **Kamera 2-Zona Terpandu & Human-in-the-Loop TFLite:** Pemindaian otomatis Zona Atas dan Zona Bawah (zona tanpa item wajib dilewati) dengan ambang keyakinan transparan (`0.70`) serta koreksi satu ketuk oleh guru pada layar tinjau draft.
- **Draft Lokal SQLite Minimalis:** Skema 3 tabel (`classes`, `inspection_sessions`, `scan_records`) dengan *upsert* siswa bebas duplikasi per sesi.
- **Laporan PDF A4 Resmi Siap Cetak:** Menghasilkan laporan K3 berlogo SiK3, daftar siswa urut presensi, matriks ceklis dinamis, rekap kepatuhan, serta blok tanda tangan sejajar Guru Mata Pelajaran dan Wali Kelas.
- **Subsistem Vision AI Online Opsional (`api-verify-apd/`):** Endpoint Next.js / Vercel AI SDK v6 (`POST /api/verify-apd`) untuk opini kedua saat daring tanpa pernah memblokir alur offline.

---

## Struktur Proyek

```text
SiK3/
├── lib/                    # Aplikasi utama Flutter (onboarding, student, teacher, ml, pdf, data)
├── assets/
│   ├── icons/              # Logo resmi SiK3
│   ├── svg/                # Ikon vektor 6 standar APD
│   └── models/             # Model PPE TFLite modular & konfigurasi label
├── test/                   # Unit & widget tests (Flutter test + sqflite_common_ffi)
├── api-verify-apd/         # Opsional backend Next.js / Vercel untuk verifikasi Vision AI
├── PRODUCT.md              # Kontrak produk & ruang lingkup
└── DESIGN.md               # Spesifikasi sistem desain & aksesibilitas
```

---

## Cara Menjalankan & Build

### 1. Aplikasi Flutter Android
```powershell
flutter pub get
flutter test
flutter run
flutter build apk --release
```

### 2. Subsistem Vision AI Online (Opsional)
Lihat panduan konfigurasi pada [`api-verify-apd/README.md`](api-verify-apd/README.md).

---

## Lisensi

Proyek ini dirilis di bawah lisensi **MIT**.

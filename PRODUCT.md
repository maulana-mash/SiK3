# Product

<!-- impeccable:product-schema 1 -->

> **Derivation Notice:** Dokumen ini diturunkan langsung dari spesifikasi desain terkunci pada sesi sebelumnya (`docs/superpowers/specs/2026-11-24-sik3-design.md`) untuk kebutuhan eksekusi Task 1-8. Tidak ada wawancara pengguna tambahan yang dijalankan pada sesi ini.

## Platform

android

## Stack

Flutter Android (`id.sch.sik3`, `minSdk = 24`, `targetSdk = 35`, Material 3, SQLite via `sqflite`, kamera & TFLite lokal) dengan subsistem opsional online Next.js / Vercel Route Handler (`api-verify-apd/`, Vercel AI SDK v6).

## Users

1. **Guru Bengkel Sekolah (SMK / Vokasi) — Mode Guru (PIN lokal 4-6 digit):**
   Melakukan pemeriksaan kelengkapan Alat Pelindung Diri (APD) siswa sebelum praktik bengkel/permesinan di area dengan koneksi internet terbatas atau tidak ada sinyal sama sekali.
2. **Siswa Praktik — Mode Siswa (Tanpa Login):**
   Menyimpan identitas praktik lokal (Nama, NISN, No. Presensi, Kelas, Jurusan) dan menampilkan Kartu QR Identitas kontras tinggi untuk dipindai guru saat absen masuk bengkel.

## Product Purpose

Mempercepat inspeksi dan dokumentasi kepatuhan K3 (Keselamatan dan Kesehatan Kerja) di bengkel sekolah secara **100% offline-first** melalui pemindaian QR identitas siswa, kamera 2-zona terpandu (Zona Atas & Zona Bawah) dengan praseleksi model PPE TFLite modular, koreksi 1 ketuk oleh guru pada draft lokal sementara, serta ekspor langsung laporan PDF A4 resmi bertanda tangan Guru Mata Pelajaran dan Wali Kelas.

## Positioning

- **Single-APK Dual-Role Offline:** Satu aplikasi Android ringan yang memisahkan Mode Guru ber-PIN lokal dan Mode Siswa tanpa login atau server akun terpusat.
- **Human-in-the-Loop Draft Validation:** Kamera offline berfungsi sebagai asisten pra-cek dengan ambang keyakinan transparan (`0.70`); item yang belum terwakili model publik (misalnya `baju_praktik`) atau memiliki keyakinan rendah otomatis masuk `Perlu Cek` (`needsReview`) sehingga keputusan final selalu berada di tangan guru.
- **Optional Cloud Second-Opinion:** Bantuan AI online (`POST /api/verify-apd`) hanya bersifat opsional ketika guru memintanya secara eksplisit dalam kondisi online, tanpa pernah memblokir alur utama.

## Operating Context

- **Lingkungan Bengkel:** Pencahayaan bengkel bervariasi, seragam wearpack berbeda tiap jurusan/sekolah, sinyal seluler/Wi-Fi sering lemah atau tidak tersedia, dan antrean siswa masuk bengkel membutuhkan alur pindai cepat.
- **Perangkat:** Ponsel Android kelas menengah (RAM 4-6 GB); foto bukti dikompresi maks 800px JPG dan dapat dibersihkan setelah inspeksi tanpa menghapus data ceklis.
- **Ritual Pelaporan Sekolah:** Laporan PDF A4 wajib memuat kop resmi berlogo SiK3, daftar siswa urut presensi, kolom ceklis dinamis sesuai APD wajib kelas, rekapitulasi kepatuhan, serta blok tanda tangan sejajar Guru Mata Pelajaran dan Wali Kelas.

## Capabilities and Constraints

- **6 Standar APD Bengkel:** `baju_praktik` (Baju Praktik), `helm` (Helm Safety), `kacamata` (Kacamata Safety), `masker` (Masker), `sarung_tangan` (Sarung Tangan), dan `sepatu_bengkel` (Sepatu Bengkel). Guru dapat menyalakan/mematikan kewajiban tiap item per kelas.
- **Pemindaian 2-Zona Terpandu:** Zona Atas (`baju_praktik`, `helm`, `kacamata`, `masker`, `sarung_tangan`) dan Zona Bawah (`sepatu_bengkel`); zona tanpa item wajib dilewati otomatis.
- **QR Offline + Cadangan Input Manual:** Format payload JSON `v=1` dengan CRC16-CCITT 4-hex lowercase; tetap tersedia form input manual saat siswa lupa membawa HP.
- **Draft Lokal SQLite Minimalis:** Tepat 3 tabel (`classes`, `inspection_sessions`, `scan_records`) dengan `UNIQUE(session_id, nisn)` agar pemindaian ulang siswa yang sama menimpa data lama secara bersih.
- **Batas Ruang Lingkup (Non-Goals):** Tidak ada server autentikasi terpusat, portal web admin, sinkronisasi cloud multi-perangkat, pelatihan ulang dataset YOLO dari nol di versi ini, ataupun target iOS.

## Brand Commitments

- **Nama Resmi:** `SiK3` (Sistem Inspeksi K3 Bengkel Sekolah).
- **Aset Logo Resmi:** Logo perisai navy-amber berikon centang dan roda gigi (`assets/icons/logo_sik3_transparent.png` & `assets/icons/logo_sik3_adaptive_fullbleed.png`) diproses dari aset sumber resmi pengguna.
- **Larangan Emoji:** Zero emoji di seluruh kode antarmuka, label, dan PDF. Seluruh penanda 6 APD menggunakan ikon vektor SVG murni.

## Evidence on Hand

- Spesifikasi desain terkunci: `docs/superpowers/specs/2026-11-24-sik3-design.md`
- Rencana implementasi 8 tugas: `docs/superpowers/plans/2026-11-24-sik3-implementation.md`
- Aset sumber logo aplikasi: `C:/Users/Mash_Maulana/.gemini/antigravity/brain/a00fd2a1-092a-4cf9-b0be-8af2076be78b/.user_uploaded/media_1795488885180_abdea873.jpg`

## Product Principles

1. **Offline Pertama, Online Opsional:** Setiap layar kritis inspeksi dan ekspor PDF bekerja penuh tanpa jaringan.
2. **Kecepatan Antrean Bengkel:** Interaksi inti guru (scan QR -> foto 2 zona -> koreksi 1 ketuk) dirancang untuk alur cepat di lapangan.
3. **Transparansi Ketidakpastian:** Ketidakyakinan model (`< 0.70` atau item non-publik) ditampilkan sebagai *Perlu Cek*, bukan tuduhan *Kurang*.
4. **Sederhana & Tahan Banting:** Skema lokal 3 tabel, batas foto 800px, dan penanganan error terkendali untuk kamera/QR/jaringan.

## Accessibility & Inclusion

- Target sentuh minimum `48x48dp` dengan jarak antar kontrol `>= 8dp` untuk penggunaan satu tangan di bengkel.
- Dukungan penuh system font scale (`sp`), tabular numerals untuk angka presensi/NISN/persentase, serta penghormatan terhadap preferensi *Reduce Motion* dan gestur *System Back* Android.

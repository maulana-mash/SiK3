# SiK3 — Sistem Inspeksi K3 Bengkel Sekolah

**Spec Terkunci:** `docs/superpowers/specs/2026-11-24-sik3-design.md`
**Rencana Implementasi:** `docs/superpowers/plans/2026-11-24-sik3-implementation.md`
**Target Root:** `D:\Game Mash_\Antigravity Project\Proyek Sederhana\SiK3`
**Platform:** Android APK (`id.sch.sik3`, `minSdk = 24`, `targetSdk = 35`)

## Visi Proyek
Menyediakan aplikasi inspeksi Alat Pelindung Diri (APD) bengkel sekolah (SMK/vokasi) yang berjalan **100% offline-first** dalam satu APK dengan dua peran jelas:
1. **Mode Siswa** (tanpa login): menyusun profil lokal dan Kartu QR Identitas (`v=1` + CRC16 checksum).
2. **Mode Guru** (dilindungi PIN lokal 4-6 digit): mengelola kelas + Wali Kelas + preset 6 APD wajib, memindai QR siswa (atau input manual cadangan), melakukan pemindaian kamera 2-zona terpandu (Zona Atas & Zona Bawah) dengan deteksi TFLite modular, meninjau dan mengoreksi hasil pada draft lokal SQLite 3 tabel, lalu mengekspor laporan PDF A4 resmi bertanda tangan Guru Mata Pelajaran dan Wali Kelas.

## Arsitektur 2 Subsistem
- **Subsistem A (Utama — 100% Offline, Flutter Android):**
  - Identitas QR offline (`QrIdentityCodec` CRC16-CCITT) + preferensi lokal (`LocalPrefs` SHA-256 PIN).
  - Database lokal sementara SQLite tepat 3 tabel: `classes`, `inspection_sessions`, `scan_records` (`UNIQUE(session_id, nisn)`).
  - Pipeline ML TFLite modular (`assets/models/ppe_detector.tflite` + `assets/models/ppe_labels.json`) dengan aturan `confidenceThreshold = 0.70` dan `ApdStatus.needsReview` untuk item yang belum tercakup label model publik (misalnya `baju_praktik`).
  - Generator PDF A4 offline multi-halaman (`PdfReportBuilder`).
- **Subsistem B (Opsional — Online Assist, `api-verify-apd/`):**
  - Next.js / Vercel Route Handler `POST /api/verify-apd` menggunakan Vercel AI SDK v6 (`generateText` + `Output.object()` + Zod + `google/gemini-3-flash`), dipanggil hanya saat guru menekan tombol opsional *Verifikasi AI Tambahan* dalam kondisi online (timeout <= 10 detik, gagal elegan tanpa merusak draft SQLite).

## Prinsip Inti
- **Offline-First Penuh:** Tidak ada alur inti guru/siswa yang bergantung pada jaringan internet.
- **Koreksi Guru Berdaulat:** Hasil deteksi otomatis berstatus draft lokal dan dapat dikoreksi 1 ketuk; tidak ada vonis otomatis permanen tanpa review guru.
- **Disiplin Kcode & Visual Operate:** Tepat 3 tabel SQLite, zero emoji di seluruh UI/PDF/aset, 6 ikon SVG murni (`viewBox="0 0 24 24"`), target sentuh >= 48dp, tabular numerals, dan radius konsentris.

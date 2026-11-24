---
name: SiK3 Design System
description: Sistem desain Material 3 Mode Operate untuk SiK3 (Sistem Inspeksi K3 Bengkel Sekolah) berpalet Navy-Amber resmi dengan ikon SVG murni dan zero emoji.
colors:
  navy: "#0D2D4D"
  amber: "#F59E0B"
  amber-pressed: "#D97706"
  surface-light: "#F8FAFC"
  card-surface: "#FFFFFF"
  scanner-dark: "#0B192C"
  status-passed: "#15803D"
  status-review: "#D97706"
  status-missing: "#DC2626"
  border: "#E2E8F0"
  text-primary: "#0F172A"
  text-secondary: "#475569"
typography:
  display:
    fontFamily: "Roboto"
    fontSize: "2rem"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.01em"
  headline:
    fontFamily: "Roboto"
    fontSize: "1.5rem"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "0em"
  title:
    fontFamily: "Roboto"
    fontSize: "1.125rem"
    fontWeight: 600
    lineHeight: 1.33
    letterSpacing: "0em"
  body:
    fontFamily: "Roboto"
    fontSize: "0.9375rem"
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: "0em"
  label:
    fontFamily: "Roboto"
    fontSize: "0.8125rem"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "0.01em"
rounded:
  inner: "8px"
  card-inner: "12px"
  button: "12px"
  outer: "16px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.amber}"
    textColor: "{colors.navy}"
    rounded: "{rounded.button}"
    padding: "12px 20px"
    height: "48px"
  button-primary-pressed:
    backgroundColor: "{colors.amber-pressed}"
    textColor: "{colors.navy}"
  button-secondary:
    backgroundColor: "{colors.navy}"
    textColor: "{colors.card-surface}"
    rounded: "{rounded.button}"
    padding: "12px 20px"
    height: "48px"
  card-draft:
    backgroundColor: "{colors.card-surface}"
    rounded: "{rounded.outer}"
    padding: "16px"
  chip-apd:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.inner}"
    padding: "8px 12px"
    height: "48px"
---

> **Derivation Notice:** Sistem desain ini diturunkan dari spesifikasi visual terkunci dalam `docs/superpowers/specs/2026-11-24-sik3-design.md` dan direalisasikan oleh token Dart di `lib/core/theme/sik3_theme.dart`.

## Overview

SiK3 menganut pendekatan **Operate** (*industrial precision & utility-first*) di atas standar **Material Design 3 Android**: antarmuka berkarakter tegas untuk penggunaan bengkel nyata, fokus pada kejelasan status APD dalam sekali lihat, keterbacaan angka dan identitas di bawah pencahayaan bengkel, serta bebas total dari ornamen berlebihan atau emoji.

## Colors

Seluruh palet diturunkan langsung dari logo perisai SiK3 (Navy `#0D2D4D` dan Safety Amber `#F59E0B`) dipadukan permukaan terang berstruktur dan warna semantik inspeksi:

| Token | Nilai | Peran |
|---|---|---|
| `Sik3Colors.navy` | `#0D2D4D` | Primary brand shell, header bar, tipografi aksen, aksi sekunder |
| `Sik3Colors.amber` | `#F59E0B` | Primary CTA (*Mulai Sesi*, *Scan Siswa*, *Ambil Foto*) & aksen fokus |
| `Sik3Colors.amberPressed` | `#D97706` | State tekan tombol amber |
| `Sik3Colors.surfaceLight` | `#F8FAFC` | Latar kanvas utama aplikasi |
| `Sik3Colors.cardSurface` | `#FFFFFF` | Permukaan kartu daftar kelas & kartu siswa |
| `Sik3Colors.scannerDark` | `#0B192C` | Latar layar pemindai QR dan viewfinder kamera 2-zona |
| `Sik3Colors.statusPassed` | `#15803D` | Status `Lolos` (`ApdStatus.detected`) |
| `Sik3Colors.statusReview` | `#D97706` | Status `Perlu Cek` (`ApdStatus.needsReview`) |
| `Sik3Colors.statusMissing` | `#DC2626` | Status `Kurang` (`ApdStatus.missing`) |
| `Sik3Colors.border` | `#E2E8F0` | Garis pemisah tipis dan border kartu |
| `Sik3Colors.textPrimary` | `#0F172A` | Teks utama kontras tinggi |
| `Sik3Colors.textSecondary` | `#475569` | Teks pendukung, metadata kelas, NIP |

## Typography

- **Jenis Huruf:** Roboto (sistem Android bawaan) dengan skala ukuran responsif (`sp`) Material 3.
- **Tabular Numerals (`FontFeature.tabularFigures()`):** Wajib diterapkan via `Sik3Typography.tabular(...)` pada seluruh angka dinamis atau berkolom: **NISN**, **No. Presensi**, **jumlah siswa**, **ringkasan statistik sesi**, dan **skor confidence**.

## Layout

- **Grid & Irama Spasial (`Sik3Spacing`):** Kelipatan `4dp` dan `8dp` (`xs = 4`, `sm = 8`, `md = 12`, `lg = 16`, `xl = 24`, `xxl = 32`).
- **Safe Areas & Edge-to-Edge:** Konten menghormati status bar, navigation bar, display cutout, dan keyboard IME.
- **Aksesibilitas Sentuh:** Seluruh elemen interaktif (tombol, chip APD 1 ketuk, kartu toggle kelas, tombol flash) memiliki dimensi sentuh minimum `48x48dp` dengan jarak minimum `8dp`.

## Elevation & Depth

Permukaan utama menggunakan **tonal layering** dan border `1dp` (`Sik3Colors.border`) tanpa drop shadow tebal. Layar viewfinder kamera (`#0B192C`) mempertahankan kontras gelap agar panduan siluet dan sudut bingkai terlihat jelas.

## Shapes

Mengikuti hukum **radius konsentris** ($R_{inner} = R_{outer} - P$) pada `Sik3Radius`:
- **Kontainer luar & padding standar:** `outer = 16dp`, `padding = 8dp`, `inner = 8dp`.
- **Kartu & komponen dalam ber-padding rapat:** `cardOuter = 16dp`, `cardPadding = 4dp`, `cardInner = 12dp`.
- **Tombol & Chip:** tombol aksi `12dp`, chip status/APD `8dp`, badge status `pill (999dp)`.

## Components

- **Ikon APD SVG Murni (`ApdSvgIcon`):** 6 aset vektor di `assets/svg/` (`baju_praktik.svg`, `helm.svg`, `kacamata.svg`, `masker.svg`, `sarung_tangan.svg`, `sepatu_bengkel.svg`) menggunakan `viewBox="0 0 24 24"`, `stroke="currentColor"`, `stroke-width="2"`, `stroke-linecap="round"`, `stroke-linejoin="round"`, `fill="none"`.
- **Komponen Material 3 Native:** FilledButton, OutlinedButton, FilterChip/ActionChip kustom >= 48dp, Navigation/TopAppBar, ModalBottomSheet, AlertDialog, dan SnackBar untuk umpan balik non-blocking.
- **Motion (`Sik3Motion`):** Transisi cepat `fast = 150ms`, `normal = 200ms` dengan kurva `Curves.easeOutCubic` (tanpa bounce berlebihan) serta menghormati pengaturan sistem *Remove animations*.

## Do's and Don'ts

- **Do:** Gunakan ikon SVG murni `ApdSvgIcon` untuk setiap representasi APD di layar maupun vektor sederhana di PDF.
- **Do:** Gunakan `Sik3Typography.tabular` pada semua NISN, nomor absen, total kepatuhan, dan skor confidence.
- **Do:** Jaga agar aksi koreksi 1 ketuk guru pada kartu siswa dapat dijangkau mudah dengan ukuran >= 48dp.
- **Don't:** Jangan menyisipkan karakter emoji Unicode di mana pun dalam kode UI, aset, atau laporan PDF.
- **Don't:** Jangan menandai item yang belum tercakup label model publik atau berkeyakinan < 0.70 sebagai `Kurang`; selalu tampilkan `Perlu Cek`.
- **Don't:** Jangan menggunakan shadow tebal atau gaya komponen iOS (Cupertino) di antarmuka Android.

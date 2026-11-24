# Roadmap — SiK3 MVP

## Fase 1: Fondasi, Sistem Desain, Logo & Identitas QR Offline
- [x] **Task 1:** Init `.planning/` GSD-Core, `PRODUCT.md`/`DESIGN.md`, `flutter create` (`id.sch.sik3`), pemrosesan logo transparan & adaptive full-bleed, 6 SVG APD, `apd_item.dart`, `sik3_theme.dart`, `apd_svg_icon.dart`.
- [ ] **Task 2:** `QrIdentityCodec` (CRC16-CCITT), `LocalPrefs` (PIN SHA-256 + profil), `RoleGateScreen`, `StudentQrScreen`.
- [ ] **Task 3:** `inspection_models.dart`, `ClassSetupScreen` (preset 6 APD wajib & Wali Kelas), `QrScanScreen` + bottom sheet input manual cadangan.

## Fase 2: Database Lokal Sementara, Kamera 2-Zona & Deteksi PPE Modular
- [ ] **Task 4:** `AppDatabase` SQLite 3 tabel (`classes`, `inspection_sessions`, `scan_records`) dengan deduplikasi `UNIQUE(session_id, nisn)` & pembersih foto draft.
- [ ] **Task 5:** `PpeLabelConfig`, `TflitePpeDetector` (`assets/models/`), dan `ApdEvaluator` 2-zona dengan ambang `0.70`.
- [ ] **Task 6:** `ApdZoneScanScreen` (kamera 2-zona terpandu + kompresi JPG maks 800px) dan `ReviewDraftScreen` (validasi draft guru dengan koreksi 1 ketuk).

## Fase 3: Generator PDF A4, AI Online Opsional & Rilis APK
- [ ] **Task 7:** `PdfReportBuilder` (PDF A4 multi-halaman bertanda tangan sejajar Guru Mapel & Wali Kelas) + `PdfPreviewScreen`.
- [ ] **Task 8:** `api-verify-apd/` (Next.js/Vercel Route Handler AI SDK v6), `OnlineAiVerifier` (timeout <= 10 detik), integrasi tombol opsional *Verifikasi AI Tambahan*, dan verifikasi build APK release (`flutter build apk --release`).

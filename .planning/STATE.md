# Project State — SiK3

**Current Phase:** Fase 3 — Generator PDF A4, AI Online Opsional & Rilis APK (Selesai)
**Current Task:** Task 8 Complete (Seluruh Fase 1–3 & Task 1–8 Selesai)
**Branch:** `feat/sik3-mvp`
**Previous HEAD:** `91ddabc` (`fix: keep PDF action bar inset-safe and closing summary/signature inseparable`)

## Locked Decisions
1. Flutter project ditempatkan langsung di root `D:\Game Mash_\Antigravity Project\Proyek Sederhana\SiK3` (`id.sch.sik3`, `minSdk = 24`, `targetSdk = 35`).
2. Skema SQLite dibatasi ketat tepat 3 tabel (`classes`, `inspection_sessions`, `scan_records`) dengan `UNIQUE(session_id, nisn)`.
3. Deteksi offline memakai ambang `0.70`; item di bawah ambang atau di luar label model publik wajib berstatus `ApdStatus.needsReview`.
4. Zero emoji di seluruh aplikasi (`lib/`), aset (`assets/`), maupun PDF; 6 APD memakai SVG murni `24x24` stroke `2px`.
5. `PRODUCT.md` dan `DESIGN.md` diturunkan langsung dari spesifikasi terkunci `docs/superpowers/specs/2026-11-24-sik3-design.md`.
6. Subsistem B (`api-verify-apd/`) bersifat 100% opsional (`POST /api/verify-apd`, Next.js App Router, AI SDK v6 `generateText` + `Output.object()`, model `'google/gemini-3-flash'`), dengan `OnlineAiVerifier` memaksa timeout `<= 10s` dan hanya menyimpan `isAiVerified = true` setelah konfirmasi eksplisit guru.

## Final Verification Snapshot
- `flutter analyze`: 0 issues.
- `flutter test`: 88/88 tests passed (seluruh test unit & widget Tasks 1–8).
- `api-verify-apd`: `npx tsc --noEmit` -> 0 errors.
- `flutter build apk --release`: sukses (`build/app/outputs/flutter-apk/app-release.apk`, `99,518,136` bytes / `94.91 MiB`).

# SiK3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Membangun aplikasi Android APK **SiK3** (100% offline-first, 2 peran Guru & Siswa) di `D:\Game Mash_\Antigravity Project\Proyek Sederhana\SiK3` dengan pemindaian QR identitas, kamera deteksi APD 2-zona modular TFLite, database lokal SQLite 3 tabel untuk validasi mandiri guru, ekspor PDF A4 bertanda tangan Guru Mapel & Wali Kelas, serta Subsistem B opsional verifikasi AI online (`api-verify-apd/`).

**Architecture:**
1. **Subsistem A (Utama — 100% Offline):** Aplikasi Flutter Android langsung di root `D:\Game Mash_\Antigravity Project\Proyek Sederhana\SiK3` (`id.sch.sik3`, `minSdk = 24`, `targetSdk = 35`).
2. **Subsistem B (Opsional — Online Assist):** Vercel/Next.js Route Handler di `api-verify-apd/` (`POST /api/verify-apd`, Vercel AI SDK `generateText` + `Output.object()` + Zod + `google/gemini-3-flash`).

**Spec:** `docs/superpowers/specs/2026-11-24-sik3-design.md`

**Environment Toolchain (Windows — WAJIB dipakai di setiap perintah terminal):**
```powershell
$env:PATH = "C:\Users\Mash_Maulana\Downloads\flutter\bin;D:\Game Mash_\Android Studio\jbr\bin;" + $env:PATH
$env:JAVA_HOME = "D:\Game Mash_\Android Studio\jbr"
$env:ANDROID_HOME = "D:\Game Mash_\Android Studio 2"
```

---

## Global Constraints
- **Root Proyek:** `D:\Game Mash_\Antigravity Project\Proyek Sederhana\SiK3` (Flutter project dibuat langsung di root dengan `flutter create --org id.sch --project-name sik3 --platforms android .`).
- **Nama APK & Android SDK:** `SiK3` · Application ID: `id.sch.sik3` · `minSdk = 24`, `targetSdk = 35`.
- **Logo Sumber:** `C:/Users/Mash_Maulana/.gemini/antigravity/brain/a00fd2a1-092a-4cf9-b0be-8af2076be78b/.user_uploaded/media_1795488885180_abdea873.jpg` → diproses menjadi `assets/icons/logo_sik3_transparent.png` (1024×1024 RGBA, keempat sudut alpha=0) dan `assets/icons/logo_sik3_adaptive_fullbleed.png` (1024×1024 full-bleed navy atas & amber bawah untuk Android Adaptive Icon via `flutter_launcher_icons`).
- **Offline-First Penuh:** Seluruh fitur Mode Siswa dan Mode Guru (kecuali tombol opsional *Verifikasi AI Tambahan*) bekerja 100% tanpa internet.
- **Sistem Desain (`/ui-ux-pro-max` + `/impeccable` Mode Operate + `/design-eng`):**
  - Token warna: Primary Navy `#0D2D4D`, Safety Amber `#F59E0B`, Pressed Amber `#D97706`, Surface Light `#F8FAFC`, Card Surface `#FFFFFF`, Scanner Dark `#0B192C`, Lolos `#15803D`, Perlu Cek `#D97706`, Kurang `#DC2626`.
  - **ZERO EMOJI** di seluruh kode UI, komentar tampilan, maupun PDF. Semua 6 item APD menggunakan ikon SVG murni (`assets/svg/*.svg`, `viewBox="0 0 24 24"`, stroke 2px konsisten).
  - Target sentuh minimum `48×48dp`, spacing ≥ `8dp`.
  - Tabular numbers (`FontFeature.tabularFigures()`) untuk NISN, No. Presensi, jumlah siswa, dan skor confidence.
  - Radius konsentris ($R_{inner} = R_{outer} - P$).
  - Transisi *ease-out* cepat 150–200ms, hormati reduced motion, Material 3 native Android, safe areas edge-to-edge.
- **Ambang Deteksi Offline:** `confidenceThreshold = 0.70`. Item dengan skor < `0.70` atau tidak tersedia pada `PpeLabelConfig.supportedItems` WAJIB berstatus `ApdStatus.needsReview`, bukan `ApdStatus.missing`.
- **Disiplin `/kcode`:** Tepat 3 tabel SQLite (`classes`, `inspection_sessions`, `scan_records`) dengan `UNIQUE(session_id, nisn)`, tanpa over-abstraksi atau fitur spekulatif.

## Review Focus
1. **QR invalid / non-SiK3 / checksum diubah** → `QrIdentityCodec.decode()` wajib melempar `QrFormatException` terkendali dan layar menampilkan pesan ramah tanpa crash (Task 2).
2. **Scan ulang siswa sama di sesi sama** → `AppDatabase.upsertScanRecord()` wajib menimpa berdasarkan `(session_id, nisn)` tanpa duplikasi (Task 4).
3. **Item APD tidak ada di label model PPE publik** → `ApdEvaluator.evaluate()` wajib mengembalikan `ApdStatus.needsReview`, bukan `ApdStatus.missing` (Task 5).
4. **36+ siswa & 6 APD wajib pada PDF A4** → `PdfReportBuilder.build()` wajib multi-halaman otomatis, mengulang header tabel, dan menjaga blok tanda tangan Guru Mapel + Wali Kelas utuh tidak terpotong (Task 7).
5. **Offline / timeout saat Verifikasi AI Tambahan** → `OnlineAiVerifier.verify()` wajib timeout ≤ 10 detik, mengembalikan `VerifyFailure` elegan tanpa memodifikasi draft SQLite (Task 8).

---

## Fase 1 — Fondasi, Sistem Desain, Logo & Identitas QR Offline

### Task 1: Init `.planning/` GSD-Core, `flutter create`, Logo Transparan/Adaptive, `sik3_theme.dart`, `apd_item.dart` & 6 SVG APD
**Files:**
- Create: `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, `.planning/config.json`
- Create: `PRODUCT.md`, `DESIGN.md`
- Create: `tools/prepare_logo.py`
- Create: `assets/icons/logo_sik3_transparent.png`, `assets/icons/logo_sik3_adaptive_fullbleed.png`
- Create: `assets/svg/baju_praktik.svg`, `assets/svg/helm.svg`, `assets/svg/kacamata.svg`, `assets/svg/masker.svg`, `assets/svg/sarung_tangan.svg`, `assets/svg/sepatu_bengkel.svg`
- Create: `lib/core/models/apd_item.dart`
- Create: `lib/core/theme/sik3_theme.dart`
- Create: `lib/core/widgets/apd_svg_icon.dart`
- Create: `test/apd_item_test.dart`
- Modify: `pubspec.yaml`, `.gitignore`, `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Produces:
  - `enum ScanZone { upper, lower }`
  - `enum ApdItem { bajuPraktik, helm, kacamata, masker, sarungTangan, sepatuBengkel }` dengan:
    - `String get key` (`'baju_praktik'`, `'helm'`, `'kacamata'`, `'masker'`, `'sarung_tangan'`, `'sepatu_bengkel'`)
    - `String get labelId` (e.g. `'Baju Praktik'`, `'Helm Safety'`, `'Kacamata Safety'`, `'Masker'`, `'Sarung Tangan'`, `'Sepatu Bengkel'`)
    - `String get shortLabelId` (e.g. `'Baju'`, `'Helm'`, `'Kcm'`, `'Mskr'`, `'S.Tgn'`, `'Spt'`)
    - `String get svgAssetPath` (`'assets/svg/<key>.svg'`)
    - `ScanZone get scanZone` (`sepatuBengkel` → `ScanZone.lower`, 5 lainnya → `ScanZone.upper`)
    - `static ApdItem? fromKey(String key)`
  - `enum ApdStatus { detected, needsReview, missing }` dengan `String get key`, `String get labelId`, `static ApdStatus fromKey(String key)`
  - `class ApdCheckResult` (`item`, `status`, `confidence` nullable `double?`, `manualOverride` `bool`, `note` nullable `String?`, `copyWith`, `toJson`, `fromJson`, equality)
  - `class Sik3Colors` (konstanta palet logo: `navy`, `amber`, `amberPressed`, `surfaceLight`, `cardSurface`, `scannerDark`, `statusPassed`, `statusReview`, `statusMissing`, `border`, `textPrimary`, `textSecondary`)
  - `class Sik3Spacing` & `class Sik3Radius` (konsentris: `outer = 16`, `padding = 8`, `inner = 8`; `cardOuter = 16`, `cardInner = 12` dengan padding `4`, dsb.) & `class Sik3Motion` (`fast = Duration(milliseconds: 150)`, `normal = Duration(milliseconds: 200)`, `curve = Curves.easeOutCubic`)
  - `ThemeData buildSik3Theme()` (Material 3, tabular numerals helper `Sik3Typography.tabular`, tombol min height 48dp, zero emoji)
  - `class ApdSvgIcon extends StatelessWidget` (merender `SvgPicture.asset(item.svgAssetPath, ...)` dengan colorFilter & semanticLabel opsional)

**Steps:**
- [ ] **Step 1:** Jalankan `flutter create --org id.sch --project-name sik3 --platforms android .` di `D:\Game Mash_\Antigravity Project\Proyek Sederhana\SiK3` (pastikan tidak menimpa `docs/`). Append `.superpowers/` ke `.gitignore`. Set `minSdk = 24`, `targetSdk = 35`, `applicationId = "id.sch.sik3"` di `android/app/build.gradle.kts`, dan `android:label="SiK3"` + permission `CAMERA` (tanpa hardware required false agar aman di semua device) + `INTERNET` (untuk opsional AI) di `AndroidManifest.xml`.
- [ ] **Step 2:** Buat berkas GSD-Core `.planning/{PROJECT.md,REQUIREMENTS.md,ROADMAP.md,STATE.md,config.json}` serta Impeccable `PRODUCT.md` dan `DESIGN.md` dari spesifikasi terkunci.
- [ ] **Step 3:** Tulis `tools/prepare_logo.py` (Python + Pillow) yang membaca `C:/Users/Mash_Maulana/.gemini/antigravity/brain/a00fd2a1-092a-4cf9-b0be-8af2076be78b/.user_uploaded/media_1795488885180_abdea873.jpg`, memotong/flood-fill background putih di luar squircle secara halus (anti-aliased alpha feathering pada tepi luar, tanpa melubangi perisai/centang/gear putih di dalam!) menghasilkan `assets/icons/logo_sik3_transparent.png` (1024×1024 RGBA), serta menghasilkan `assets/icons/logo_sik3_adaptive_fullbleed.png` (1024×1024 RGB/RGBA) di mana area putih luar squircle diisi dengan warna navy bagian atas (di atas garis lengkung horizon) dan warna amber bagian bawah (di bawah garis horizon) sehingga penuh ke keempat sudut untuk Android Adaptive Icon. Jalankan `python tools/prepare_logo.py` dan verifikasi keempat sudut `logo_sik3_transparent.png` memiliki `alpha == 0` dan `logo_sik3_adaptive_fullbleed.png` tidak memiliki piksel putih di keempat sudut.
- [ ] **Step 4:** Tambahkan dependensi Flutter inti ke `pubspec.yaml`: `flutter_svg`, `shared_preferences`, `crypto`, `qr_flutter`, `mobile_scanner`, `sqflite`, `path`, `path_provider`, `camera`, `tflite_flutter`, `image`, `pdf`, `printing`, `http`; dev_dependencies: `flutter_launcher_icons`, `sqflite_common_ffi`, `flutter_lints`. Konfigurasi `flutter_launcher_icons` (Android adaptive icon memakai `logo_sik3_adaptive_fullbleed.png` + `adaptive_icon_background: "#0D2D4D"` + `adaptive_icon_foreground: "assets/icons/logo_sik3_transparent.png"` dan `image_path: "assets/icons/logo_sik3_adaptive_fullbleed.png"`). Daftarkan `assets/icons/`, `assets/svg/`, `assets/models/` (buat folder `assets/models/.gitkeep` atau placeholder dulu agar `pub get` valid). Jalankan `flutter pub get` dan `dart run flutter_launcher_icons`.
- [ ] **Step 5 (TDD):** Buat 6 berkas SVG murni presisi tinggi (`viewBox="0 0 24 24"`, `stroke="currentColor"`, `stroke-width="2"`, `stroke-linecap="round"`, `stroke-linejoin="round"`, `fill="none"`) untuk `baju_praktik.svg`, `helm.svg`, `kacamata.svg`, `masker.svg`, `sarung_tangan.svg`, `sepatu_bengkel.svg`. Tulis unit test `test/apd_item_test.dart` dulu (pastikan FAIL), lalu implementasikan `lib/core/models/apd_item.dart`, `lib/core/theme/sik3_theme.dart`, dan `lib/core/widgets/apd_svg_icon.dart`. Hapus default `test/widget_test.dart` counter template bawaan Flutter.
- [ ] **Step 6:** Verifikasi: jalankan `flutter analyze` (0 issues), `flutter test` (PASS), dan verifikasi Python untuk alpha sudut logo transparan.
- [ ] **Step 7:** Commit: `feat: initialize SiK3 Flutter app, GSD planning, transparent logo, and design tokens`.

---

### Task 2: `QrIdentityCodec`, `LocalPrefs`, `RoleGateScreen` & `StudentQrScreen`
**Files:**
- Create: `lib/data/qr_identity_codec.dart`
- Create: `lib/data/local_prefs.dart`
- Create: `lib/features/onboarding/role_gate_screen.dart`
- Create: `lib/features/student/student_qr_screen.dart`
- Modify: `lib/main.dart`
- Test: `test/qr_identity_codec_test.dart`
- Test: `test/local_prefs_test.dart`

**Interfaces:**
- Consumes: `buildSik3Theme()`, `Sik3Colors`, `Sik3Spacing`, `Sik3Radius`, `Sik3Motion`, `assets/icons/logo_sik3_transparent.png` (Task 1).
- Produces:
  - `enum AppRole { teacher, student }`
  - `class StudentIdentity { final String nisn; final String attendanceNo; final String name; final String className; final String major; }` (`toJson`, `fromJson`, equality)
  - `class TeacherProfile { final String name; final String nip; final String schoolName; final String aiEndpointUrl; }`
  - `class QrFormatException implements Exception { final String message; }`
  - `class QrIdentityCodec`:
    - `static String computeChecksum({required int v, required String nisn, required String absen, required String nama, required String kelas, required String jurusan})` (CRC16-CCITT 4-char lowercase hex)
    - `static String encode(StudentIdentity student)` → JSON `{"v":1,"nisn":...,"absen":...,"nama":...,"kelas":...,"jurusan":...,"chk":...}`
    - `static StudentIdentity decode(String rawPayload)` (validates JSON object, `v == 1`, non-blank required fields `nisn`/`absen`/`nama`/`kelas`/`jurusan`, and exact 4-hex `chk` CRC16 match; throws `QrFormatException` on any violation)
  - `class LocalPrefs`:
    - `static Future<LocalPrefs> open([SharedPreferences? prefs])`
    - `AppRole? getRole()`, `Future<void> setRole(AppRole? role)`
    - `bool hasTeacherPin()`, `Future<void> setTeacherPin(String pin)` (4–6 digit numeric, SHA-256 salted hash), `bool verifyTeacherPin(String pin)`
    - `StudentIdentity? getStudentProfile()`, `Future<void> saveStudentProfile(StudentIdentity student)`
    - `TeacherProfile getTeacherProfile()`, `Future<void> saveTeacherProfile(TeacherProfile profile)`
  - `class RoleGateScreen extends StatefulWidget` (pemilihan Mode Guru dengan pembuatan/verifikasi PIN 4–6 digit lokal + Mode Siswa; menampilkan logo SiK3 transparan; zero emoji; 48dp+ touch targets)
  - `class StudentQrScreen extends StatefulWidget` (form profil siswa dengan validasi inline + Kartu QR Identitas `qr_flutter` kontras tinggi dengan NISN/Absen tabular numerals, tombol edit profil, tombol ganti peran)
  - `lib/main.dart` (`Sik3App` yang membaca `LocalPrefs` dan merutekan ke `RoleGateScreen`, `StudentQrScreen`, atau placeholder/home Guru sementara yang akan disambungkan ke `ClassSetupScreen` di Task 3)

**Steps:**
- [ ] **Step 1 (TDD RED):** Tulis `test/qr_identity_codec_test.dart`:
  - `encodes_and_decodes_valid_student_identity`
  - `throws_QrFormatException_on_corrupted_checksum`
  - `throws_QrFormatException_on_non_sik3_qr_url`
  - `throws_QrFormatException_when_required_fields_blank`
  - `throws_QrFormatException_on_unsupported_version`
  Dan `test/local_prefs_test.dart` (`SharedPreferences.setMockInitialValues({})`): PIN set & verify (benar/salah), invalid PIN format rejected, student profile & teacher profile round-trip, role persistence.
- [ ] **Step 2:** Jalankan `flutter test test/qr_identity_codec_test.dart test/local_prefs_test.dart` → pastikan FAIL.
- [ ] **Step 3 (GREEN):** Implementasikan `qr_identity_codec.dart`, `local_prefs.dart`, `role_gate_screen.dart`, `student_qr_screen.dart`, dan `lib/main.dart`. Pastikan **zero emoji**, tombol ≥ 48dp, tabular numbers untuk NISN/absen, radius konsentris, dan transisi 150–200ms ease-out.
- [ ] **Step 4:** Jalankan `flutter test` dan `flutter analyze` → pastikan seluruh test PASS dan 0 issues.
- [ ] **Step 5:** Commit: `feat: add offline QR identity codec, PIN role gate, and student QR card`.

---

### Task 3: Mode Guru — `ClassSetupScreen` (Preset APD & Wali Kelas) & `QrScanScreen` (+ Input Manual Cadangan)
**Files:**
- Create: `lib/core/models/school_class_draft.dart` (atau langsung selaras dengan model `SchoolClass` yang dipakai Task 4 — lihat Pre-flight Ruling: letakkan model data bersih `lib/core/models/inspection_models.dart` di Task 3 agar Task 3 & Task 4 memakai model identik tanpa duplikasi!)
- Create: `lib/features/teacher/class_setup_screen.dart`
- Create: `lib/features/teacher/qr_scan_screen.dart`
- Modify: `lib/main.dart` (arahkan Mode Guru ke `ClassSetupScreen`)
- Test: `test/class_setup_screen_test.dart`

**Interfaces:**
- Consumes: `ApdItem`, `ApdSvgIcon`, `QrIdentityCodec.decode`, `LocalPrefs`, `Sik3Theme`.
- Produces:
  - `lib/core/models/inspection_models.dart`:
    - `class SchoolClass { final int? id; final String name; final String homeroomTeacher; final String homeroomNip; final Set<ApdItem> requiredApd; }`
    - `class InspectionSession { final int? id; final int classId; final String subjectName; final String teacherName; final String teacherNip; final String homeroomTeacher; final String homeroomNip; final String schoolName; final DateTime sessionDate; final Set<ApdItem> requiredApd; final String status; }`
    - `class ScanRecord { final int? id; final int sessionId; final String nisn; final String attendanceNo; final String studentName; final Map<ApdItem, ApdCheckResult> apdResults; final String? upperPhotoPath; final String? lowerPhotoPath; final bool isManualOverride; final bool isAiVerified; final DateTime scannedAt; }`
  - `class ClassSetupScreen extends StatefulWidget` (manajemen profil guru mapel & pengaturan URL AI opsional, daftar kelas, tambah/edit/hapus kelas + Nama Wali Kelas + NIP opsional, 6 kartu toggle APD wajib berikon SVG murni ≥ 48dp, tombol *Mulai Sesi Inspeksi* yang dapat menerima callback atau menyimpan kelas via penyimpanan lokal/DB).
  - `Future<StudentIdentity?> openStudentQrScanner(BuildContext context, {String? defaultClassName})` & `class QrScanScreen extends StatefulWidget` (`mobile_scanner` dengan viewfinder 4 sudut Navy/Amber pada latar `#0B192C`, toggle flash, error `QrFormatException` via snackbar non-blocking dengan cooldown agar tidak spam, dan tombol *"Siswa Lupa HP? Input Manual"* yang membuka bottom sheet form `StudentIdentity` lengkap dengan validasi inline).

**Steps:**
- [ ] **Step 1 (TDD RED):** Tulis `test/class_setup_screen_test.dart` menguji:
  - Toggle 6 preset APD wajib merespons tap dan memperbarui status wajib (minimal 1 APD wajib sebelum mulai sesi).
  - Tambah kelas dengan nama kelas dan wali kelas berhasil muncul di daftar.
  - Bottom sheet input manual cadangan pada `QrScanScreen` (via widget/helper test) mengembalikan `StudentIdentity` valid.
- [ ] **Step 2:** Jalankan `flutter test test/class_setup_screen_test.dart` → pastikan FAIL.
- [ ] **Step 3 (GREEN):** Implementasikan `lib/core/models/inspection_models.dart`, `lib/features/teacher/class_setup_screen.dart`, `lib/features/teacher/qr_scan_screen.dart`, dan sambungkan Mode Guru di `lib/main.dart`.
- [ ] **Step 4:** Jalankan `flutter test` dan `flutter analyze` → PASS & 0 issues.
- [ ] **Step 5:** Commit: `feat: add teacher class APD preset setup and QR scanner with manual fallback`.

---

## Fase 2 — Database Lokal Sementara, Kamera 2-Zona & Deteksi PPE Publik Offline

### Task 4: Database Lokal Sementara SQLite (`AppDatabase` — Tepat 3 Tabel)
**Files:**
- Create: `lib/data/app_database.dart`
- Modify: `lib/features/teacher/class_setup_screen.dart` (persist daftar kelas & buat sesi di `AppDatabase`)
- Test: `test/app_database_test.dart`

**Interfaces:**
- Consumes: `ApdItem`, `ApdCheckResult`, `SchoolClass`, `InspectionSession`, `ScanRecord`.
- Produces:
  - `class AppDatabase`:
    - `static Future<AppDatabase> open({String? path, DatabaseFactory? factory})` (mendukung `inMemoryDatabasePath` + `databaseFactoryFfi` untuk unit test)
    - `Future<void> close()`
    - `Future<int> upsertClass(SchoolClass schoolClass)`
    - `Future<List<SchoolClass>> getClasses()`
    - `Future<void> deleteClass(int classId)`
    - `Future<int> createSession(InspectionSession session)`
    - `Future<List<InspectionSession>> getSessionsForClass(int classId)`
    - `Future<InspectionSession?> getSession(int sessionId)`
    - `Future<void> updateSessionStatus(int sessionId, String status)`
    - `Future<int> upsertScanRecord(ScanRecord record)` (constraint `UNIQUE(session_id, nisn)` → menimpa/replace record siswa yang sama pada sesi yang sama tanpa menggandakan, sambil mempertahankan/mengganti foto bukti dengan aman)
    - `Future<List<ScanRecord>> getSessionRecords(int sessionId)` (urut berdasarkan `attendance_no` numerik, fallback lexicographical bila non-angka, lalu `student_name` A–Z)
    - `Future<void> deleteScanRecord(int recordId)`
    - `Future<int> purgeSessionPhotos(int sessionId)` (menghapus file JPG bukti di disk bila ada & mengosongkan `upper_photo_path` & `lower_photo_path` di DB tanpa menghapus hasil ceklis APD; mengembalikan jumlah file/record yang dibersihkan)
    - `Future<void> deleteSession(int sessionId)` (bersihkan foto lalu hapus records & session)

**Steps:**
- [ ] **Step 1 (TDD RED):** Tulis `test/app_database_test.dart` memakai `sqflite_common_ffi` in-memory:
  - `schema_has_exactly_three_user_tables` (verifikasi `sqlite_master` tepat berisi `classes`, `inspection_sessions`, `scan_records`).
  - `upsertClass_and_getClasses_round_trip`.
  - `upsertScanRecord_replaces_duplicate_student_in_same_session` (insert NISN sama 2x → total record tetap 1 dengan hasil terbaru).
  - `getSessionRecords_sorts_by_numeric_attendance_number` (`"10"`, `"02"`, `"1"` → urut `"1"`, `"02"`, `"10"`).
  - `purgeSessionPhotos_deletes_disk_files_and_clears_photo_paths_without_deleting_checklist_data` (buat file JPG temp nyata di `Directory.systemTemp`, verifikasi terhapus dari disk, path di DB jadi null, namun `apdResults` tetap utuh).
- [ ] **Step 2:** Jalankan `flutter test test/app_database_test.dart` → pastikan FAIL.
- [ ] **Step 3 (GREEN):** Implementasikan `lib/data/app_database.dart` dan sambungkan `ClassSetupScreen` agar menyimpan & membaca kelas dari `AppDatabase` (dengan dukungan injeksi `AppDatabase` untuk test).
- [ ] **Step 4:** Jalankan `flutter test` dan `flutter analyze` → PASS & 0 issues.
- [ ] **Step 5:** Commit: `feat: add 3-table SQLite draft database with deduplicated student upsert`.

---

### Task 5: Pipeline Model PPE Publik Modular & Evaluator 2-Zona
**Files:**
- Create: `assets/models/ppe_labels.json`
- Create: `assets/models/ppe_detector.tflite` (unduh model YOLO PPE publik atau generate/siapkan model TFLite valid berformat YOLOv8n/PPE + dokumentasi cara swap model fine-tuned di `assets/models/README.md`)
- Create: `lib/ml/ppe_label_config.dart`
- Create: `lib/ml/tflite_ppe_detector.dart`
- Create: `lib/ml/apd_evaluator.dart`
- Test: `test/apd_evaluator_test.dart`

**Interfaces:**
- Consumes: `ApdItem`, `ApdStatus`, `ApdCheckResult`.
- Produces:
  - `class RawDetection { final String label; final double confidence; final List<double> bbox; }`
  - `class PpeLabelConfig`:
    - `final List<String> modelClassNames;`
    - `final Map<String, ApdItem> labelToApd;`
    - `Set<ApdItem> get supportedItems`
    - `factory PpeLabelConfig.fromJsonString(String jsonStr)`
    - `static Future<PpeLabelConfig> loadFromAsset([String assetPath = 'assets/models/ppe_labels.json'])`
  - `abstract class PpeDetector { Future<List<RawDetection>> detectFile(String imagePath); Future<void> dispose(); }`
  - `class TflitePpeDetector implements PpeDetector`:
    - Membaca `assets/models/ppe_detector.tflite` via `tflite_flutter` (`Interpreter.fromAsset`), pra-proses gambar JPEG/PNG resize letterbox 640×640 (atau sesuai input tensor model), decode output YOLO (mendukung `[1, 4+C, N]` maupun `[1, N, 4+C]`) + NMS (IoU 0.45).
    - Jika model gagal dimuat / tidak valid di lingkungan non-Android/dev, mengembalikan daftar deteksi kosong secara terkendali (tidak crash) dan menandai `bool get isModelLoaded`.
  - `class ApdEvaluator`:
    - `static const double defaultThreshold = 0.70;`
    - `static Map<ApdItem, ApdCheckResult> evaluate({required List<RawDetection> upperDetections, required List<RawDetection> lowerDetections, required Set<ApdItem> requiredItems, required PpeLabelConfig config, double threshold = defaultThreshold})`
    - Aturan ketat:
      - Hanya mengevaluasi item dalam `requiredItems` (abaikan yang tidak wajib).
      - Item zona atas (`ScanZone.upper`) membaca `upperDetections`; item zona bawah (`ScanZone.lower`) membaca `lowerDetections`.
      - Jika `!config.supportedItems.contains(item)` → `ApdStatus.needsReview` (`confidence: null`).
      - Jika didukung model & ada deteksi untuk `item`: ambil `maxConfidence`. Jika `maxConfidence >= threshold` → `ApdStatus.detected`; jika `< threshold` → `ApdStatus.needsReview`.
      - Jika didukung model & tidak ada deteksi sama sekali untuk `item` → `ApdStatus.missing` (`confidence: 0.0`).

**Steps:**
- [ ] **Step 1 (TDD RED):** Tulis `test/apd_evaluator_test.dart`:
  - `marks_detected_when_confidence_at_or_above_0_70` (`helmet: 0.82` dan boundary `0.70` → `ApdStatus.detected`).
  - `marks_needsReview_when_confidence_below_0_70` (`gloves: 0.55` dan `0.699` → `ApdStatus.needsReview`).
  - `marks_needsReview_when_item_not_in_public_model_labels` (`bajuPraktik` wajib tapi tidak ada di `config.supportedItems` → `ApdStatus.needsReview`, BUKAN `missing`).
  - `marks_missing_when_item_supported_but_not_detected` (`helm` didukung model, 0 deteksi → `ApdStatus.missing`).
  - `ignores_items_not_in_requiredItems`.
  - `separates_upper_and_lower_zone_detections` (`shoes` hanya dihitung dari `lowerDetections`, `helmet` hanya dari `upperDetections`).
  - `parses_ppe_labels_json_config_correctly`.
- [ ] **Step 2:** Jalankan `flutter test test/apd_evaluator_test.dart` → pastikan FAIL.
- [ ] **Step 3 (GREEN):** Siapkan `assets/models/ppe_labels.json` (memetakan label PPE publik standar: `helmet`/`hardhat` → `helm`, `goggles`/`safety-glass`/`glasses` → `kacamata`, `mask` → `masker`, `gloves` → `sarung_tangan`, `boots`/`safety-shoes`/`shoes` → `sepatu_bengkel`; `baju_praktik` sengaja belum masuk model publik standar kecuali label `safety-vest` bila tidak mewakili wearpack SMK — catat di JSON agar `baju_praktik` otomatis masuk `needsReview` sesuai Review Focus #3!). Unduh model YOLO PPE publik `.tflite` asli jika tersedia dari HuggingFace/GitHub open source (periksa validitas header FlatBuffer `TFL3`!); jika unduhan publik tidak tersedia tanpa auth, bangun model TFLite valid minimal atau simpan model PPE publik yang bisa diekspor/diunduh dan dokumentasikan sumbernya secara jujur di `assets/models/README.md`. Implementasikan `ppe_label_config.dart`, `apd_evaluator.dart`, dan `tflite_ppe_detector.dart`.
- [ ] **Step 4:** Jalankan `flutter test` dan `flutter analyze` → PASS & 0 issues.
- [ ] **Step 5:** Commit: `feat: add modular TFLite PPE detector and 2-zone APD evaluator`.

---

### Task 6: Layar Kamera 2-Zona Terpandu (`ApdZoneScanScreen`) & Layar Validasi Draft Guru (`ReviewDraftScreen`)
**Files:**
- Create: `lib/features/teacher/apd_zone_scan_screen.dart`
- Create: `lib/features/teacher/review_draft_screen.dart`
- Modify: `lib/features/teacher/class_setup_screen.dart` (hubungkan tombol *Mulai Sesi Inspeksi* & daftar sesi draft ke `ReviewDraftScreen` / alur scan QR → 2-Zona → Draft)
- Test: `test/review_draft_screen_test.dart`

**Interfaces:**
- Consumes: `StudentIdentity`, `SchoolClass`, `InspectionSession`, `ScanRecord`, `PpeDetector`/`TflitePpeDetector`, `PpeLabelConfig`, `ApdEvaluator`, `AppDatabase`, `ApdSvgIcon`, `openStudentQrScanner`.
- Produces:
  - `class ApdZoneScanScreen extends StatefulWidget`:
    - Menampilkan kartu identitas siswa aktif (Nama, No. Presensi, NISN tabular) di atas viewfinder gelap `#0B192C`.
    - **Langkah 1: Zona Atas** (panduan siluet kepala-bahu-tangan, petunjuk "Angkat kedua tangan di depan dada", hanya dijalankan jika ada item wajib Zona Atas; jika tidak ada item Zona Atas wajib, langsung ke Zona Bawah).
    - **Langkah 2: Zona Bawah** (panduan siluet area kaki/sepatu; dilewati otomatis jika `sepatuBengkel` tidak wajib).
    - Mengompresi foto bukti maks lebar/tinggi 800px JPG ke direktori app lokal (`getApplicationDocumentsDirectory()/sik3_evidence/session_<id>/`).
    - Menjalankan `TflitePpeDetector.detectFile()` + `ApdEvaluator.evaluate()`, menyimpan `ScanRecord` ke `AppDatabase.upsertScanRecord()`, dan kembali dengan hasil `ScanRecord`.
    - Penanganan ramah bila izin kamera ditolak atau kamera gagal inisialisasi (tetap memberi opsi *Lanjut Penilaian Manual Tanpa Foto* agar guru tidak macet di bengkel!).
  - `class ReviewDraftScreen extends StatefulWidget`:
    - Membaca `AppDatabase.getSessionRecords(session.id!)`.
    - Menampilkan ringkasan sesi (Kelas, Mata Praktik, total diperiksa / Lengkap / Perlu Cek / Kurang dengan tabular numbers).
    - Setiap kartu siswa menampilkan: No. Presensi, Nama, NISN, badge status, 1-tap toggle chip APD wajib berikon SVG murni (`detected` ↔ `missing`, serta dari `needsReview` → `detected` pada tap pertama) yang langsung menyimpan ke SQLite dengan `isManualOverride = true`, tombol *Lihat Foto* (dialog/sheet foto Zona Atas & Bawah), tombol *Scan Ulang*, dan slot untuk tombol opsional *Verifikasi AI Tambahan* (yang akan diaktifkan di Task 8).
    - Action bar: FAB / CTA *Scan Siswa* (alur QR → `ApdZoneScanScreen` → refresh draft), tombol *Bersihkan Foto Draft* (konfirmasi lalu panggil `purgeSessionPhotos`), dan tombol *Ekspor PDF* (disambungkan ke `PdfPreviewScreen` pada Task 7).

**Steps:**
- [ ] **Step 1 (TDD RED):** Tulis `test/review_draft_screen_test.dart` menggunakan `AppDatabase` in-memory:
  - Menampilkan daftar siswa terurut numerik dengan tabular numbers dan badge `Perlu Cek`.
  - 1 ketuk chip APD mengubah status (`needsReview` → `detected`, `detected` → `missing`) dan menyimpannya ke SQLite dengan `isManualOverride == true`.
  - Tombol *Bersihkan Foto Draft* mengosongkan path foto tanpa menghapus catatan ceklis siswa.
- [ ] **Step 2:** Jalankan `flutter test test/review_draft_screen_test.dart` → pastikan FAIL.
- [ ] **Step 3 (GREEN):** Implementasikan `apd_zone_scan_screen.dart`, `review_draft_screen.dart`, dan hubungkan navigasi penuh dari `class_setup_screen.dart`.
- [ ] **Step 4:** Jalankan `flutter test` dan `flutter analyze` → PASS & 0 issues.
- [ ] **Step 5:** Commit: `feat: add 2-zone guided APD camera flow and teacher local draft review screen`.

---

## Fase 3 — Generator PDF A4, AI Online Opsional & Rilis APK

### Task 7: Generator Laporan PDF A4 Offline (`PdfReportBuilder`) + `PdfPreviewScreen`
**Files:**
- Create: `lib/pdf/pdf_report_builder.dart`
- Create: `lib/features/teacher/pdf_preview_screen.dart`
- Modify: `lib/features/teacher/review_draft_screen.dart` (hubungkan tombol *Ekspor PDF* ke `PdfPreviewScreen` dan tandai sesi `exported`)
- Test: `test/pdf_report_builder_test.dart`

**Interfaces:**
- Consumes: `InspectionSession`, `SchoolClass`, `List<ScanRecord>`, `assets/icons/logo_sik3_transparent.png`.
- Produces:
  - `class PdfReportBuilder`:
    - `static Future<Uint8List> build({required InspectionSession session, required SchoolClass schoolClass, required List<ScanRecord> records, required Uint8List logoBytes})`
    - Layout A4 portrait (`PdfPageFormat.a4`), `pw.MultiPage` otomatis multi-halaman.
    - Kop: Logo SiK3 transparan, judul resmi, nama sekolah, kelas, mata praktik, tanggal.
    - Tabel: `No`, `Absen / NISN`, `Nama Siswa`, **kolom dinamis hanya untuk `session.requiredApd`** (terurut konsisten sesuai `ApdItem.values`), simbol vektor `pw.CustomPaint` (centang hijau `#15803D`, tanda tanya amber `#D97706`, silang merah `#DC2626` — **ZERO EMOJI**), kolom `Status` (`Lengkap` / `Perlu Cek` / `Kurang`). Header tabel berulang otomatis (`tableHeader` / `headerCount: 1`).
    - Ringkasan hitungan (Total, Lengkap, Perlu Cek, Kurang).
    - Blok tanda tangan sejajar Guru Mata Pelajaran (kiri) & Wali Kelas (kanan) beserta nama terang & NIP opsional, dibungkus agar **tidak terpotong antar halaman** (`pw.Container` / `pw.Column` dalam `MultiPage` item tunggal).
  - `class PdfPreviewScreen extends StatelessWidget` (menggunakan `printing` `PdfPreview` dengan aksi cetak & bagikan PDF, nama file `Laporan_K3_<Kelas>_<Tanggal>.pdf`).

**Steps:**
- [ ] **Step 1 (TDD RED):** Tulis `test/pdf_report_builder_test.dart`:
  - `generates_valid_pdf_bytes_with_dynamic_required_apd_columns` (header `%PDF-`, sukses untuk 3 APD wajib maupun 6 APD wajib).
  - `paginates_36_students_cleanly_without_overflow_exception` (36 `ScanRecord`, verifikasi hasil bytes valid dan lebih dari 1 halaman `/Type /Page`).
  - `handles_empty_records_gracefully`.
- [ ] **Step 2:** Jalankan `flutter test test/pdf_report_builder_test.dart` → pastikan FAIL.
- [ ] **Step 3 (GREEN):** Implementasikan `pdf_report_builder.dart`, `pdf_preview_screen.dart`, dan hubungkan tombol *Ekspor PDF* di `review_draft_screen.dart`.
- [ ] **Step 4:** Jalankan `flutter test` dan `flutter analyze` → PASS & 0 issues.
- [ ] **Step 5:** Commit: `feat: add offline A4 PDF K3 report generator with teacher and homeroom signatures`.

---

### Task 8: Subsistem B (`api-verify-apd/`), `OnlineAiVerifier`, Audit UI (`/impeccable` + `/design-eng`) & Release APK Build
**Files:**
- Create: `api-verify-apd/package.json`
- Create: `api-verify-apd/tsconfig.json`
- Create: `api-verify-apd/next.config.ts`
- Create: `api-verify-apd/app/api/verify-apd/route.ts`
- Create: `api-verify-apd/README.md`
- Create: `lib/ml/online_ai_verifier.dart`
- Modify: `lib/features/teacher/review_draft_screen.dart` (tampilkan tombol *Verifikasi AI Tambahan* bila `teacherProfile.aiEndpointUrl` terisi; tampilkan pratinjau hasil AI untuk dikonfirmasi guru sebelum menimpa draft SQLite)
- Modify: `.planning/STATE.md`, `.planning/ROADMAP.md`
- Test: `test/online_ai_verifier_test.dart`

**Interfaces:**
- Consumes: `ApdItem`, `ApdStatus`, `ApdCheckResult`, `LocalPrefs`, `ReviewDraftScreen`.
- Produces:
  - Endpoint `POST /api/verify-apd` (Next.js App Router, Node.js runtime, Vercel AI SDK `ai` v6 `generateText` + `Output.object()` + `zod` schema + model `'google/gemini-3-flash'` via AI Gateway; baca docs aktual di `node_modules/ai/` setelah `npm install` agar API 100% akurat!).
  - `sealed class OnlineVerifyResult` (`VerifySuccess(Map<ApdItem, ApdCheckResult> results, String summary)` | `VerifyFailure(String message, {bool isTimeout})`)
  - `class OnlineAiVerifier`:
    - Constructor menerima optional `http.Client? client` dan `Duration timeout = const Duration(seconds: 10)`
    - `Future<OnlineVerifyResult> verify({required String? upperPhotoPath, required String? lowerPhotoPath, required Set<ApdItem> requiredItems, required String endpointUrl})` (selalu catch timeout/SocketException/HTTP error/malformed JSON → return `VerifyFailure`, tidak pernah melempar uncaught exception).

**Steps:**
- [ ] **Step 1 (TDD RED):** Tulis `test/online_ai_verifier_test.dart` (dengan `MockClient` dari `package:http/testing.dart`):
  - `parses_valid_json_response_into_apd_results`
  - `returns_graceful_failure_on_offline_socket_exception_without_throwing`
  - `returns_graceful_failure_on_timeout_without_throwing`
  - `returns_graceful_failure_on_http_500_or_invalid_json`
- [ ] **Step 2:** Jalankan `flutter test test/online_ai_verifier_test.dart` → pastikan FAIL.
- [ ] **Step 3 (GREEN):**
  - Implementasikan `lib/ml/online_ai_verifier.dart` dan sambungkan ke `review_draft_screen.dart` (tombol opsional *Verifikasi AI Tambahan* muncul saat endpoint URL dikonfigurasi, menampilkan dialog konfirmasi hasil AI sebelum menulis ke SQLite dengan `isAiVerified = true`, dan saat offline/timeout menampilkan snackbar ramah tanpa menyentuh draft SQLite).
  - Buat proyek `api-verify-apd/` (`package.json`, `tsconfig.json`, `next.config.ts`, `app/api/verify-apd/route.ts`, `README.md`), jalankan `npm install` di `api-verify-apd/`, verifikasi API `generateText` + `Output.object()` dari `node_modules/ai`, dan jalankan `npx tsc --noEmit` hingga 0 error!
- [ ] **Step 4:** Audit UI/UX (`/impeccable` + `/design-eng` + `/ui-ux-pro-max` pre-delivery checklist):
  - Verifikasi 0 karakter emoji di seluruh `lib/` dan `assets/`.
  - Verifikasi semua target sentuh ≥ 48dp, tabular numbers pada angka dinamis, konsistensi token `Sik3Colors`, safe areas, kontras, dan error/empty states.
- [ ] **Step 5:** Verifikasi penuh:
  - `flutter analyze` (0 issues)
  - `flutter test` (semua test PASS)
  - `cd api-verify-apd && npx tsc --noEmit` (0 errors)
  - `flutter build apk --release` (verifikasi file `build/app/outputs/flutter-apk/app-release.apk` tercipta!)
- [ ] **Step 6:** Perbarui `.planning/STATE.md` dan `.planning/ROADMAP.md` menandai semua fase selesai, lalu commit: `feat: add optional online Vision AI verification, UI audit, and release APK build`.

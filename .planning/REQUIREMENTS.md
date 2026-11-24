# Requirements — SiK3 MVP

Diturunkan langsung dari `docs/superpowers/specs/2026-11-24-sik3-design.md`.

## Kebutuhan Fungsional

### FR-01: Identitas & Peran Offline
- **FR-01.1:** Satu APK memiliki Gerbang Peran (`Mode Guru` ber-PIN lokal 4-6 digit SHA-256 dan `Mode Siswa` tanpa login).
- **FR-01.2:** Mode Siswa menghasilkan Kartu QR Identitas offline berformat JSON `{"v":1,"nisn":...,"absen":...,"nama":...,"kelas":...,"jurusan":...,"chk":"xxxx"}` dengan checksum CRC16-CCITT 4-hex lowercase.
- **FR-01.3:** QR tidak valid / bukan SiK3 / checksum rusak wajib melempar `QrFormatException` terkendali tanpa crash.

### FR-02: Setup Kelas & Pemindaian QR Siswa
- **FR-02.1:** Guru dapat mengelola profil guru mapel (Nama, NIP opsional, Nama Sekolah/Jurusan, URL Verifikasi AI opsional) serta daftar kelas lengkap dengan Wali Kelas + NIP opsional.
- **FR-02.2:** Setiap kelas menyimpan preset wajib untuk 6 item APD (`baju_praktik`, `helm`, `kacamata`, `masker`, `sarung_tangan`, `sepatu_bengkel`).
- **FR-02.3:** Pemindaian QR siswa menyediakan cadangan *Input Manual* bila siswa lupa membawa HP.

### FR-03: Database Draft Lokal Sementara (Tepat 3 Tabel)
- **FR-03.1:** Skema SQLite tepat berisi 3 tabel: `classes`, `inspection_sessions`, `scan_records`.
- **FR-03.2:** `scan_records` memiliki `UNIQUE(session_id, nisn)`; scan ulang siswa yang sama pada sesi yang sama wajib menimpa record lama tanpa duplikasi.
- **FR-03.3:** `purgeSessionPhotos` wajib menghapus berkas JPG bukti dari disk dan mengosongkan path foto tanpa menghapus hasil ceklis APD.

### FR-04: Deteksi Kamera 2-Zona Modular & Evaluator
- **FR-04.1:** Zona Atas (`baju_praktik`, `helm`, `kacamata`, `masker`, `sarung_tangan`) dan Zona Bawah (`sepatu_bengkel`) dijalankan hanya jika ada item wajib pada zona tersebut.
- **FR-04.2:** Ambang batas keyakinan `0.70`: skor >= `0.70` -> `detected`, skor < `0.70` -> `needsReview`, didukung model namun 0 deteksi -> `missing`.
- **FR-04.3:** Item wajib yang tidak tersedia pada `PpeLabelConfig.supportedItems` wajib berstatus `needsReview`, bukan `missing`.

### FR-05: Validasi Draft Guru & Ekspor PDF A4
- **FR-05.1:** Layar Review Draft Guru menampilkan ringkasan sesi, daftar siswa terurut numerik, koreksi 1 ketuk dengan `isManualOverride = true`, pratinjau foto, dan pembersih foto draft.
- **FR-05.2:** `PdfReportBuilder` menghasilkan PDF A4 multi-halaman otomatis (36+ siswa aman), mengulang header tabel, memakai logo transparan SiK3, ikon vektor tanpa emoji, dan blok tanda tangan sejajar Guru Mata Pelajaran + Wali Kelas yang tidak terpotong antar halaman.

### FR-06: Verifikasi AI Tambahan Opsional (`api-verify-apd/`)
- **FR-06.1:** Route Handler `POST /api/verify-apd` memakai Vercel AI SDK v6 (`generateText` + `Output.object()` + Zod + `google/gemini-3-flash`).
- **FR-06.2:** Klien Flutter `OnlineAiVerifier` memiliki timeout <= 10 detik, mengembalikan `VerifyFailure` elegan saat offline/error tanpa memodifikasi SQLite, dan menerapkan hasil hanya setelah konfirmasi guru.

## Kebutuhan Non-Fungsional & Desain
- **NFR-01 (Offline-First):** 100% alur inti Mode Siswa dan Mode Guru berjalan tanpa koneksi internet.
- **NFR-02 (Zero Emoji):** Nol karakter emoji di UI Flutter, aset SVG, maupun laporan PDF; 6 APD memakai SVG murni `viewBox="0 0 24 24"`.
- **NFR-03 (Aksesibilitas & Material 3):** Target sentuh minimum `48x48dp`, spacing >= `8dp`, tabular numerals pada NISN/Absen/angka dinamis, radius konsentris, dan transisi ease-out 150-200ms yang menghormati reduced motion.

# SiK3 Offline PPE Model Assets

Direktori ini menyimpan pasangan aset model TFLite modular untuk inspeksi APD offline (`TflitePpeDetector` + `PpeLabelConfig`).

## Status Berkas Saat Ini

- `ppe_labels.json`: Konfigurasi label PPE publik standar untuk 5 item (`helmet`, `goggles`, `mask`, `gloves`, `boots`). Item `baju_praktik` sengaja tidak dipetakan (tidak menyamakan wearpack bengkel SMK dengan `safety-vest` proyek), sehingga otomatis berstatus `ApdStatus.needsReview` untuk verifikasi guru.
- `ppe_detector.tflite`: **Placeholder non-inferensi** berheader FlatBuffer `TFL3` (`SIK3_MODEL_PLACEHOLDER`). Saat dimuat, `TflitePpeDetector` menandai `isModelLoaded == false` dan mengembalikan daftar deteksi kosong secara aman tanpa crash agar guru dapat melakukan verifikasi manual atau memakai Verifikasi AI Tambahan.

### Provenansi Pencarian Model Publik

Dalam audit repositori publik tanpa autentikasi:
- `Tanishjain9/yolov8n-ppe-detection-6classes` (HuggingFace, lisensi **MIT**): menyediakan bobot YOLOv8n 6 kelas (`Gloves`, `Vest`, `goggles`, `helmet`, `mask`, `safety_shoe`) dalam format PyTorch `best.pt`, namun belum menyertakan berkas `.tflite` siap unduh.
- `spritlesoftware/ppe-detection-android` (GitHub, lisensi **MIT**): menyediakan `.tflite` YOLOv8, namun berukuran **44,7 MB** (melebihi target <= 25 MB) dan hanya mencakup 2 kelas APD (`helmet`, `vest`).
- `qualcomm/PPE-Detection` (`gear_guard_net`, HuggingFace, lisensi **BSD-3-Clause**): arsitektur anchor 3-skala kustom dan hanya mencakup 2 kelas (`helmet`, `vest`).
- `NathizLubanzi/PPE` (HuggingFace, lisensi **Unlicense**): grafik SSD MobileNet 4-output dengan `labelmap.txt` tidak utuh.

## Cara Mengganti Model (Drop-In Replacement 2 Berkas)

Untuk mengaktifkan inferensi ML offline penuh dari model YOLOv8n / YOLO11n PPE (misalnya `Tanishjain9/yolov8n-ppe-detection-6classes` atau model *fine-tuned* wearpack SMK):

1. Ekspor bobot PyTorch `.pt` menjadi TFLite di lingkungan Python yang memiliki `ultralytics` dan `tensorflow`:

   ```python
   from ultralytics import YOLO

   model = YOLO("best.pt")
   model.export(format="tflite", imgsz=640, int8=True)
   ```

2. Salin berkas `.tflite` hasil ekspor (mis. `best_int8.tflite` atau `best_float16.tflite`) ke:
   - `assets/models/ppe_detector.tflite`

3. Sesuaikan `assets/models/ppe_labels.json`:
   - Isi `model_classes` sesuai urutan indeks kelas pada model Anda (mis. `["Gloves", "Vest", "goggles", "helmet", "mask", "safety_shoe"]`).
   - Petakan nama kelas yang relevan di `label_to_apd` ke kunci kanonis `ApdItem`:
     `baju_praktik`, `helm`, `kacamata`, `masker`, `sarung_tangan`, `sepatu_bengkel`.
   - Biarkan kelas yang tidak mewakili wearpack sekolah tidak dipetakan (atau bernilai `null`) agar item tersebut otomatis berstatus `needs_review`.

4. Bangun ulang aplikasi (`flutter build apk`). `TflitePpeDetector` otomatis membaca ukuran input tensor (`[1, H, W, 3]`), tipe tensor (`float32`/`uint8`/`int8`), dan layout output YOLO (`[1, 4+C, N]` atau `[1, N, 4+C]`) tanpa perlu mengubah kode Dart.

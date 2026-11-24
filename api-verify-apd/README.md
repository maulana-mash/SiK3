# SiK3 — Subsistem B (`api-verify-apd`)

Endpoint backend **opsional** untuk fitur *Verifikasi AI Tambahan* pada aplikasi Android **SiK3**.
Seluruh alur utama SiK3 (QR, deteksi APD TFLite on-device, penyimpanan SQLite lokal, dan ekspor PDF A4) tetap berjalan **100% offline** tanpa memerlukan layanan ini.

## Teknologi

- Next.js App Router (`runtime = 'nodejs'`)
- Vercel AI SDK v6 (`ai` dengan `generateText` + `Output.object()`)
- Model `'google/gemini-3-flash'` melalui Vercel AI Gateway
- Validasi skema request & response menggunakan `zod`

## Konfigurasi Environment Variable

Siapkan salah satu autentikasi Vercel AI Gateway berikut:

- **Lokal / Non-Vercel:** set `AI_GATEWAY_API_KEY` di `.env.local`
  ```env
  AI_GATEWAY_API_KEY=vck_xxxxxxxxxxxxxxxxx
  ```
- **Deploy di Vercel:** gunakan Vercel OIDC otomatis (atau tambahkan `AI_GATEWAY_API_KEY` pada Environment Variables proyek Vercel).

## Pengembangan Lokal & Typecheck

```bash
npm install
npm run typecheck   # menjalankan tsc --noEmit
npm run dev         # menjalankan server di http://localhost:3000
```

## Deploy ke Vercel

```bash
npx vercel deploy --prod
```

Salin URL endpoint produksi (misalnya `https://<proyek-anda>.vercel.app/api/verify-apd`) lalu tempelkan pada kolom **Endpoint Verifikasi AI (Opsional)** di menu **Profil Guru** pada aplikasi SiK3.

## Kontrak API (`POST /api/verify-apd`)

### Request JSON

```json
{
  "requiredItems": ["baju_praktik", "helm", "kacamata", "sepatu_bengkel"],
  "upperPhotoBase64": "<base64 JPEG zona atas>",
  "lowerPhotoBase64": "<base64 JPEG zona bawah>"
}
```

Kunci `requiredItems` yang didukung:
`baju_praktik`, `helm`, `kacamata`, `masker`, `sarung_tangan`, `sepatu_bengkel`.
Minimal salah satu dari `upperPhotoBase64` atau `lowerPhotoBase64` wajib disertakan.

### Response JSON (`200 OK`)

```json
{
  "items": [
    {
      "item": "baju_praktik",
      "worn": true,
      "confidence": 0.94,
      "note": "Wearpack bengkel terlihat lengkap."
    }
  ],
  "summary": "Ringkasan singkat kondisi kepatuhan APD siswa."
}
```

### Error Responses

- `400 Bad Request`: body bukan JSON valid atau payload tidak lolos validasi skema.
- `504 Gateway Timeout`: pemanggilan model AI melebihi batas waktu server (9 detik).
- `500 Internal Server Error`: kegagalan tak terduga saat memanggil AI Gateway.

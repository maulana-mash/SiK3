import { generateText, Output, type ImagePart, type TextPart } from 'ai';
import { NextResponse } from 'next/server';
import { z } from 'zod';

export const runtime = 'nodejs';

const APD_ITEM_KEYS = [
  'baju_praktik',
  'helm',
  'kacamata',
  'masker',
  'sarung_tangan',
  'sepatu_bengkel',
] as const;

type ApdItemKey = (typeof APD_ITEM_KEYS)[number];

const APD_ITEM_DESCRIPTIONS: Record<ApdItemKey, string> = {
  baju_praktik: 'Baju Praktik / Wearpack / Jas Lab bengkel',
  helm: 'Helm Safety / Pelindung Kepala',
  kacamata: 'Kacamata Safety / Pelindung Mata',
  masker: 'Masker / Pelindung Pernapasan',
  sarung_tangan: 'Sarung Tangan Kerja / Safety Gloves',
  sepatu_bengkel: 'Sepatu Bengkel / Safety Shoes tertutup',
};

const ApdItemSchema = z.enum(APD_ITEM_KEYS);

const VerifyRequestSchema = z
  .object({
    requiredItems: z.array(ApdItemSchema).min(1).max(APD_ITEM_KEYS.length),
    upperPhotoBase64: z.string().trim().min(1).max(8_000_000).optional(),
    lowerPhotoBase64: z.string().trim().min(1).max(8_000_000).optional(),
  })
  .refine(
    (payload) => Boolean(payload.upperPhotoBase64 || payload.lowerPhotoBase64),
    {
      message:
        'Minimal satu foto bukti (upperPhotoBase64 atau lowerPhotoBase64) wajib disertakan.',
    },
  );

const VerifyItemSchema = z.object({
  item: ApdItemSchema.describe('Kunci item APD wajib yang dievaluasi.'),
  worn: z
    .boolean()
    .describe('true jika APD terlihat dipakai dengan benar, false jika tidak.'),
  confidence: z
    .number()
    .min(0)
    .max(1)
    .describe('Tingkat keyakinan deteksi visual antara 0.0 hingga 1.0.'),
  note: z
    .string()
    .describe('Catatan singkat objektif dalam Bahasa Indonesia tanpa emoji.'),
});

const VerifyResponseSchema = z.object({
  items: z.array(VerifyItemSchema),
  summary: z
    .string()
    .describe('Ringkasan singkat kondisi kepatuhan APD siswa dalam Bahasa Indonesia tanpa emoji.'),
});

function stripDataUriPrefix(rawBase64: string): {
  data: string;
  mediaType: string;
} {
  const match = /^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/s.exec(rawBase64);
  if (match) {
    return {
      mediaType: match[1],
      data: match[2].trim(),
    };
  }
  return {
    mediaType: 'image/jpeg',
    data: rawBase64.trim(),
  };
}

export async function POST(request: Request): Promise<Response> {
  let rawBody: unknown;
  try {
    rawBody = await request.json();
  } catch {
    return NextResponse.json(
      { error: 'Body permintaan harus berupa JSON yang valid.' },
      { status: 400 },
    );
  }

  const parsedRequest = VerifyRequestSchema.safeParse(rawBody);
  if (!parsedRequest.success) {
    return NextResponse.json(
      {
        error: 'Payload permintaan verifikasi APD tidak valid.',
        issues: parsedRequest.error.issues.map((issue) => issue.message),
      },
      { status: 400 },
    );
  }

  const { requiredItems, upperPhotoBase64, lowerPhotoBase64 } =
    parsedRequest.data;
  const uniqueRequired = Array.from(new Set<ApdItemKey>(requiredItems));

  const itemChecklist = uniqueRequired
    .map((key) => `- ${key}: ${APD_ITEM_DESCRIPTIONS[key]}`)
    .join('\n');

  const contentParts: Array<TextPart | ImagePart> = [
    {
      type: 'text',
      text: [
        'Evaluasi kepatuhan Alat Pelindung Diri (APD) siswa praktik SMK dari foto bukti berikut.',
        'Daftar item APD wajib yang harus dievaluasi:',
        itemChecklist,
        '',
        'Aturan penilaian:',
        '1. Evaluasi HANYA item yang tercantum pada daftar wajib di atas.',
        '2. Jika suatu area tubuh tidak terlihat jelas pada foto yang tersedia, turunkan nilai confidence (< 0.70) dan jelaskan pada note agar guru memeriksa langsung.',
        '3. Gunakan Bahasa Indonesia yang formal, ringkas, dan JANGAN gunakan emoji.',
      ].join('\n'),
    },
  ];

  if (upperPhotoBase64) {
    const { data, mediaType } = stripDataUriPrefix(upperPhotoBase64);
    contentParts.push({
      type: 'text',
      text: 'Foto Zona Atas (kepala, wajah, badan atas, tangan):',
    });
    contentParts.push({
      type: 'image',
      image: data,
      mediaType,
    });
  }

  if (lowerPhotoBase64) {
    const { data, mediaType } = stripDataUriPrefix(lowerPhotoBase64);
    contentParts.push({
      type: 'text',
      text: 'Foto Zona Bawah (kaki dan alas kaki/sepatu bengkel):',
    });
    contentParts.push({
      type: 'image',
      image: data,
      mediaType,
    });
  }

  try {
    const result = await generateText({
      model: 'google/gemini-3-flash',
      system:
        'Anda adalah asisten inspeksi K3 bengkel SMK yang objektif. Kembalikan hasil verifikasi terstruktur sesuai skema tanpa emoji.',
      messages: [
        {
          role: 'user',
          content: contentParts,
        },
      ],
      output: Output.object({
        schema: VerifyResponseSchema,
        name: 'ApdVerificationResult',
        description:
          'Hasil verifikasi kepatuhan APD siswa per item beserta ringkasan singkat.',
      }),
      maxRetries: 1,
      abortSignal: AbortSignal.timeout(9000),
    });

    const requiredSet = new Set<ApdItemKey>(uniqueRequired);
    const byKey = new Map<
      ApdItemKey,
      z.infer<typeof VerifyItemSchema>
    >();

    for (const entry of result.output.items) {
      if (requiredSet.has(entry.item) && !byKey.has(entry.item)) {
        byKey.set(entry.item, {
          item: entry.item,
          worn: entry.worn,
          confidence: Math.min(1, Math.max(0, entry.confidence)),
          note: entry.note.trim(),
        });
      }
    }

    const normalizedItems = uniqueRequired.map(
      (key) =>
        byKey.get(key) ?? {
          item: key,
          worn: false,
          confidence: 0.4,
          note: 'Area APD tidak terlihat cukup jelas, perlu pemeriksaan langsung.',
        },
    );

    return NextResponse.json(
      {
        items: normalizedItems,
        summary: result.output.summary.trim(),
      },
      { status: 200 },
    );
  } catch (error: unknown) {
    const isTimeout =
      error instanceof Error &&
      (error.name === 'TimeoutError' || error.name === 'AbortError');
    return NextResponse.json(
      {
        error: isTimeout
          ? 'Permintaan verifikasi Vision AI melebihi batas waktu.'
          : 'Gagal memproses verifikasi Vision AI pada server.',
      },
      { status: isTimeout ? 504 : 500 },
    );
  }
}

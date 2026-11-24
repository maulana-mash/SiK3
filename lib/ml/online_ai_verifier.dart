import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sik3/core/models/apd_item.dart';

/// Outcome of an optional online Vision AI APD verification request.
sealed class OnlineVerifyResult {
  const OnlineVerifyResult();
}

/// Successful AI verification response parsed strictly against required APD items.
final class VerifySuccess extends OnlineVerifyResult {
  const VerifySuccess(this.results, this.summary);

  final Map<ApdItem, ApdCheckResult> results;
  final String summary;
}

/// Controlled failure when offline, timed out, misconfigured, or receiving invalid data.
final class VerifyFailure extends OnlineVerifyResult {
  const VerifyFailure(this.message, {this.isTimeout = false});

  final String message;
  final bool isTimeout;
}

/// Optional HTTP client calling Subsistem B (`POST /api/verify-apd`) with a strict
/// <= 10s timeout and zero uncaught exceptions so offline workflows are never blocked.
class OnlineAiVerifier {
  OnlineAiVerifier({
    this._client,
    Duration timeout = defaultTimeout,
    this.confidenceThreshold = defaultConfidenceThreshold,
  }) : timeout = _clampTimeout(timeout);

  static const Duration defaultTimeout = Duration(seconds: 10);
  static const Duration maxTimeout = Duration(seconds: 10);
  static const double defaultConfidenceThreshold = 0.70;

  final http.Client? _client;
  final Duration timeout;
  final double confidenceThreshold;

  static Duration _clampTimeout(Duration requested) {
    if (requested <= Duration.zero) return defaultTimeout;
    if (requested > maxTimeout) return maxTimeout;
    return requested;
  }

  /// Sends available student evidence photos (base64 JPEG) to [endpointUrl]
  /// and maps structured AI results onto [requiredItems]. Never throws.
  Future<OnlineVerifyResult> verify({
    required String? upperPhotoPath,
    required String? lowerPhotoPath,
    required Set<ApdItem> requiredItems,
    required String endpointUrl,
  }) async {
    try {
      final uri = _parseEndpointUri(endpointUrl);
      if (uri == null) {
        return const VerifyFailure(
          'URL endpoint Verifikasi AI tidak valid. Periksa pengaturan Profil Guru.',
        );
      }

      if (requiredItems.isEmpty) {
        return const VerifyFailure(
          'Tidak ada item APD wajib yang perlu diverifikasi.',
        );
      }

      final upperBase64 = await _readPhotoAsBase64(upperPhotoPath);
      final lowerBase64 = await _readPhotoAsBase64(lowerPhotoPath);
      if (upperBase64 == null && lowerBase64 == null) {
        return const VerifyFailure(
          'Foto bukti siswa tidak ditemukan atau sudah dibersihkan.',
        );
      }

      final orderedKeys = ApdItem.values
          .where(requiredItems.contains)
          .map((item) => item.key)
          .toList(growable: false);

      final requestPayload = <String, Object?>{
        'requiredItems': orderedKeys,
        'upperPhotoBase64': ?upperBase64,
        'lowerPhotoBase64': ?lowerBase64,
      };

      final client = _client ?? http.Client();
      final ownsClient = _client == null;
      late final http.Response response;
      try {
        response = await client
            .post(
              uri,
              headers: const <String, String>{
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(requestPayload),
            )
            .timeout(timeout);
      } finally {
        if (ownsClient) {
          client.close();
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return VerifyFailure(
          'Server Verifikasi AI mengembalikan galat (HTTP ${response.statusCode}). Draft lokal Anda tetap aman.',
        );
      }

      return _parseSuccessBody(response.body, requiredItems);
    } on TimeoutException {
      return const VerifyFailure(
        'Verifikasi AI melebihi batas waktu (10 detik). Draft lokal Anda tetap aman.',
        isTimeout: true,
      );
    } on SocketException {
      return const VerifyFailure(
        'Tidak ada koneksi internet untuk Verifikasi AI. Draft lokal Anda tetap aman.',
      );
    } on http.ClientException {
      return const VerifyFailure(
        'Gagal terhubung ke server Verifikasi AI. Draft lokal Anda tetap aman.',
      );
    } on FormatException {
      return const VerifyFailure(
        'Respons server Verifikasi AI tidak valid. Draft lokal Anda tetap aman.',
      );
    } on Object {
      return const VerifyFailure(
        'Verifikasi AI tidak dapat diproses saat ini. Draft lokal Anda tetap aman.',
      );
    }
  }

  OnlineVerifyResult _parseSuccessBody(
    String rawBody,
    Set<ApdItem> requiredItems,
  ) {
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map<String, dynamic>) {
      return const VerifyFailure(
        'Format respons server Verifikasi AI tidak sesuai. Draft lokal Anda tetap aman.',
      );
    }

    final rawItems = decoded['items'];
    if (rawItems is! List) {
      return const VerifyFailure(
        'Daftar item APD tidak ditemukan pada respons AI. Draft lokal Anda tetap aman.',
      );
    }

    final parsed = <ApdItem, ApdCheckResult>{};
    for (final entry in rawItems) {
      if (entry is! Map) {
        return const VerifyFailure(
          'Format item pada respons AI tidak valid. Draft lokal Anda tetap aman.',
        );
      }
      final itemKey = entry['item'];
      if (itemKey is! String) continue;
      final item = ApdItem.fromKey(itemKey);
      if (item == null || !requiredItems.contains(item)) continue;

      final worn = entry['worn'];
      final rawConfidence = entry['confidence'];
      if (worn is! bool || rawConfidence is! num || !rawConfidence.isFinite) {
        return const VerifyFailure(
          'Nilai deteksi item APD pada respons AI tidak valid. Draft lokal Anda tetap aman.',
        );
      }

      final confidence = rawConfidence.toDouble().clamp(0.0, 1.0);
      final rawNote = entry['note'];
      final note = (rawNote is String && rawNote.trim().isNotEmpty)
          ? rawNote.trim()
          : null;

      final ApdStatus status;
      if (confidence < confidenceThreshold) {
        status = ApdStatus.needsReview;
      } else if (worn) {
        status = ApdStatus.detected;
      } else {
        status = ApdStatus.missing;
      }

      parsed[item] = ApdCheckResult(
        item: item,
        status: status,
        confidence: confidence,
        manualOverride: false,
        note: note,
      );
    }

    for (final item in ApdItem.values) {
      if (!requiredItems.contains(item)) continue;
      parsed.putIfAbsent(
        item,
        () => ApdCheckResult(
          item: item,
          status: ApdStatus.needsReview,
          confidence: null,
          manualOverride: false,
          note: 'Belum dievaluasi AI, perlu pemeriksaan langsung.',
        ),
      );
    }

    final rawSummary = decoded['summary'];
    final summary = rawSummary is String ? rawSummary.trim() : '';

    return VerifySuccess(
      Map<ApdItem, ApdCheckResult>.unmodifiable(parsed),
      summary,
    );
  }

  static Uri? _parseEndpointUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.host.trim().isEmpty) return null;
    return uri;
  }

  static Future<String?> _readPhotoAsBase64(String? path) async {
    if (path == null || path.trim().isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return base64Encode(bytes);
    } on Object {
      return null;
    }
  }
}

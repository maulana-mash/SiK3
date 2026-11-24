/// Scanning zone on a student's body during 2-zone workshop inspection.
enum ScanZone { upper, lower }

/// The 6 standard workshop Personal Protective Equipment (APD) items in SiK3.
enum ApdItem {
  bajuPraktik(
    key: 'baju_praktik',
    labelId: 'Baju Praktik',
    shortLabelId: 'Baju',
    scanZone: ScanZone.upper,
  ),
  helm(
    key: 'helm',
    labelId: 'Helm Safety',
    shortLabelId: 'Helm',
    scanZone: ScanZone.upper,
  ),
  kacamata(
    key: 'kacamata',
    labelId: 'Kacamata Safety',
    shortLabelId: 'Kcm',
    scanZone: ScanZone.upper,
  ),
  masker(
    key: 'masker',
    labelId: 'Masker',
    shortLabelId: 'Mskr',
    scanZone: ScanZone.upper,
  ),
  sarungTangan(
    key: 'sarung_tangan',
    labelId: 'Sarung Tangan',
    shortLabelId: 'S.Tgn',
    scanZone: ScanZone.upper,
  ),
  sepatuBengkel(
    key: 'sepatu_bengkel',
    labelId: 'Sepatu Bengkel',
    shortLabelId: 'Spt',
    scanZone: ScanZone.lower,
  );

  const ApdItem({
    required this.key,
    required this.labelId,
    required this.shortLabelId,
    required this.scanZone,
  });

  final String key;
  final String labelId;
  final String shortLabelId;
  final ScanZone scanZone;

  String get svgAssetPath => 'assets/svg/$key.svg';

  static ApdItem? fromKey(String key) {
    for (final item in ApdItem.values) {
      if (item.key == key) return item;
    }
    return null;
  }
}

/// Evaluation state of a single required APD item.
enum ApdStatus {
  detected(key: 'detected', labelId: 'Lolos'),
  needsReview(key: 'needs_review', labelId: 'Perlu Cek'),
  missing(key: 'missing', labelId: 'Kurang');

  const ApdStatus({required this.key, required this.labelId});

  final String key;
  final String labelId;

  static ApdStatus fromKey(String key) {
    for (final status in ApdStatus.values) {
      if (status.key == key) return status;
    }
    return ApdStatus.needsReview;
  }
}

/// Result of evaluating a single APD item from offline ML, manual edit, or AI assist.
class ApdCheckResult {
  const ApdCheckResult({
    required this.item,
    required this.status,
    this.confidence,
    this.manualOverride = false,
    this.note,
  });

  final ApdItem item;
  final ApdStatus status;
  final double? confidence;
  final bool manualOverride;
  final String? note;

  ApdCheckResult copyWith({
    ApdItem? item,
    ApdStatus? status,
    double? confidence,
    bool clearConfidence = false,
    bool? manualOverride,
    String? note,
    bool clearNote = false,
  }) {
    return ApdCheckResult(
      item: item ?? this.item,
      status: status ?? this.status,
      confidence: clearConfidence ? null : (confidence ?? this.confidence),
      manualOverride: manualOverride ?? this.manualOverride,
      note: clearNote ? null : (note ?? this.note),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'item': item.key,
      'status': status.key,
      'confidence': confidence,
      'manual_override': manualOverride,
      'note': note,
    };
  }

  factory ApdCheckResult.fromJson(Map<String, dynamic> json) {
    final itemKey = json['item'] as String? ?? '';
    final item = ApdItem.fromKey(itemKey);
    if (item == null) {
      throw FormatException('Unknown APD item key: $itemKey');
    }
    final rawConf = json['confidence'];
    return ApdCheckResult(
      item: item,
      status: ApdStatus.fromKey(json['status'] as String? ?? ''),
      confidence: rawConf is num ? rawConf.toDouble() : null,
      manualOverride: json['manual_override'] as bool? ?? false,
      note: json['note'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ApdCheckResult &&
            runtimeType == other.runtimeType &&
            item == other.item &&
            status == other.status &&
            confidence == other.confidence &&
            manualOverride == other.manualOverride &&
            note == other.note;
  }

  @override
  int get hashCode => Object.hash(item, status, confidence, manualOverride, note);

  @override
  String toString() {
    return 'ApdCheckResult(item: ${item.key}, status: ${status.key}, '
        'confidence: $confidence, manualOverride: $manualOverride)';
  }
}

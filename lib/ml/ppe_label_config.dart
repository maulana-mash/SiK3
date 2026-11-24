import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sik3/core/models/apd_item.dart';

/// Modular mapping between a public PPE detector's raw class labels and SiK3 [ApdItem]s.
class PpeLabelConfig {
  const PpeLabelConfig({
    required this.modelClassNames,
    required this.labelToApd,
    this.inputSize = 640,
    this.confidenceThreshold = 0.70,
    this.iouThreshold = 0.45,
  });

  static const String defaultAssetPath = 'assets/models/ppe_labels.json';

  final List<String> modelClassNames;
  final Map<String, ApdItem> labelToApd;
  final int inputSize;
  final double confidenceThreshold;
  final double iouThreshold;

  /// Canonical set of [ApdItem]s actively covered by the configured model labels.
  Set<ApdItem> get supportedItems => Set<ApdItem>.unmodifiable(labelToApd.values);

  /// Maps a raw model class label (case- and whitespace-insensitive) to an [ApdItem].
  ApdItem? mapLabel(String rawLabel) {
    final direct = labelToApd[rawLabel];
    if (direct != null) return direct;

    final normalized = rawLabel.trim().toLowerCase();
    final exactNormalized = labelToApd[normalized];
    if (exactNormalized != null) return exactNormalized;

    for (final entry in labelToApd.entries) {
      if (entry.key.trim().toLowerCase() == normalized) {
        return entry.value;
      }
    }
    return null;
  }

  /// Parses a JSON string following the `assets/models/ppe_labels.json` schema.
  factory PpeLabelConfig.fromJsonString(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('PPE label config root must be a JSON object.');
    }

    final rawClasses = decoded['model_classes'];
    final classNames = <String>[];
    if (rawClasses is List) {
      for (final entry in rawClasses) {
        if (entry is String && entry.trim().isNotEmpty) {
          classNames.add(entry.trim());
        }
      }
    }

    final rawMapping = decoded['label_to_apd'];
    final mapping = <String, ApdItem>{};
    if (rawMapping is Map) {
      for (final entry in rawMapping.entries) {
        final rawLabel = entry.key.toString().trim().toLowerCase();
        final rawApdKey = entry.value;
        if (rawLabel.isEmpty || rawApdKey is! String) continue;
        final item = ApdItem.fromKey(rawApdKey.trim());
        if (item != null) {
          mapping[rawLabel] = item;
        }
      }
    }

    final rawInputSize = decoded['input_size'];
    final inputSize = rawInputSize is num && rawInputSize.toInt() > 0
        ? rawInputSize.toInt()
        : 640;

    final rawConf = decoded['confidence_threshold'];
    final confidenceThreshold = rawConf is num ? rawConf.toDouble() : 0.70;

    final rawIou = decoded['iou_threshold'];
    final iouThreshold = rawIou is num ? rawIou.toDouble() : 0.45;

    return PpeLabelConfig(
      modelClassNames: List<String>.unmodifiable(classNames),
      labelToApd: Map<String, ApdItem>.unmodifiable(mapping),
      inputSize: inputSize,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
  }

  /// Loads and parses [PpeLabelConfig] from Flutter asset bundle.
  static Future<PpeLabelConfig> loadFromAsset([
    String assetPath = defaultAssetPath,
  ]) async {
    final jsonStr = await rootBundle.loadString(assetPath);
    return PpeLabelConfig.fromJsonString(jsonStr);
  }
}

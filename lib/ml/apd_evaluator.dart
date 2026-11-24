import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/ml/ppe_label_config.dart';

/// Single raw object detection output produced by an offline PPE detector.
class RawDetection {
  const RawDetection({
    required this.label,
    required this.confidence,
    this.bbox = const <double>[0.0, 0.0, 0.0, 0.0],
  });

  final String label;
  final double confidence;

  /// Bounding box `[x1, y1, x2, y2]` normalized in `[0.0, 1.0]` original image space.
  final List<double> bbox;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RawDetection || runtimeType != other.runtimeType) return false;
    if (label != other.label || confidence != other.confidence) return false;
    if (bbox.length != other.bbox.length) return false;
    for (var i = 0; i < bbox.length; i++) {
      if (bbox[i] != other.bbox[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(label, confidence, Object.hashAll(bbox));

  @override
  String toString() {
    return 'RawDetection(label: $label, confidence: $confidence, bbox: $bbox)';
  }
}

/// Evaluates 2-zone student PPE detections against a class's required APD preset.
class ApdEvaluator {
  const ApdEvaluator._();

  static const double defaultThreshold = 0.70;

  /// Maps raw upper-body & lower-body detections into per-item [ApdCheckResult]s.
  ///
  /// Strictly enforces:
  /// 1. Only items in [requiredItems] are included in the returned map.
  /// 2. [ScanZone.upper] items read [upperDetections]; [ScanZone.lower] items read [lowerDetections].
  /// 3. Items absent from `config.supportedItems` evaluate to [ApdStatus.needsReview] (`confidence: null`).
  /// 4. Supported items with `maxConfidence >= threshold` become [ApdStatus.detected];
  ///    scores `< threshold` become [ApdStatus.needsReview]; zero detections become [ApdStatus.missing] (`0.0`).
  static Map<ApdItem, ApdCheckResult> evaluate({
    required List<RawDetection> upperDetections,
    required List<RawDetection> lowerDetections,
    required Set<ApdItem> requiredItems,
    required PpeLabelConfig config,
    double threshold = defaultThreshold,
  }) {
    final supported = config.supportedItems;
    final results = <ApdItem, ApdCheckResult>{};

    for (final item in ApdItem.values) {
      if (!requiredItems.contains(item)) continue;

      if (!supported.contains(item)) {
        results[item] = ApdCheckResult(
          item: item,
          status: ApdStatus.needsReview,
          confidence: null,
        );
        continue;
      }

      final zoneDetections =
          item.scanZone == ScanZone.upper ? upperDetections : lowerDetections;

      double? maxConfidence;
      for (final detection in zoneDetections) {
        if (config.mapLabel(detection.label) != item) continue;
        final score = detection.confidence;
        if (score.isNaN || !score.isFinite) continue;
        if (maxConfidence == null || score > maxConfidence) {
          maxConfidence = score;
        }
      }

      if (maxConfidence == null) {
        results[item] = ApdCheckResult(
          item: item,
          status: ApdStatus.missing,
          confidence: 0.0,
        );
      } else if (maxConfidence >= threshold) {
        results[item] = ApdCheckResult(
          item: item,
          status: ApdStatus.detected,
          confidence: maxConfidence,
        );
      } else {
        results[item] = ApdCheckResult(
          item: item,
          status: ApdStatus.needsReview,
          confidence: maxConfidence,
        );
      }
    }

    return Map<ApdItem, ApdCheckResult>.unmodifiable(results);
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/ml/apd_evaluator.dart';
import 'package:sik3/ml/ppe_label_config.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

export 'package:sik3/ml/apd_evaluator.dart' show RawDetection;

/// Offline object detector contract for scanning workshop APD photos.
abstract class PpeDetector {
  Future<List<RawDetection>> detectFile(String imagePath);
  Future<void> dispose();
}

/// Letterboxed image buffer accompanied by coordinate scaling geometry.
class LetterboxResult {
  const LetterboxResult({
    required this.image,
    required this.srcWidth,
    required this.srcHeight,
    required this.inputWidth,
    required this.inputHeight,
    required this.scale,
    required this.padX,
    required this.padY,
  });

  final img.Image image;
  final int srcWidth;
  final int srcHeight;
  final int inputWidth;
  final int inputHeight;
  final double scale;
  final int padX;
  final int padY;
}

/// Modular TFLite YOLO PPE detector with letterbox preprocessing, multi-layout
/// tensor decoding (`[1, 4+C, N]` and `[1, N, 4+C]`), and IoU NMS.
class TflitePpeDetector implements PpeDetector {
  TflitePpeDetector._(
    this._labelConfig,
    this._minConfidence,
    this._iouThreshold, [
    this._interpreter,
    this._isModelLoaded = false,
  ]);

  static const String defaultModelAssetPath = 'assets/models/ppe_detector.tflite';
  static const String defaultLabelsAssetPath = 'assets/models/ppe_labels.json';
  static const double defaultMinConfidence = 0.25;
  static const double defaultIouThreshold = 0.45;
  static const List<int> _placeholderMarker = <int>[
    0x53, 0x49, 0x4b, 0x33, 0x5f, 0x4d, 0x4f, 0x44, 0x45, 0x4c, 0x5f, 0x50,
    0x4c, 0x41, 0x43, 0x45, 0x48, 0x4f, 0x4c, 0x44, 0x45, 0x52,
  ]; // "SIK3_MODEL_PLACEHOLDER"

  final PpeLabelConfig _labelConfig;
  final double _minConfidence;
  final double _iouThreshold;
  Interpreter? _interpreter;
  bool _isModelLoaded;
  bool _disposed = false;

  /// True only when a valid TFLite FlatBuffer model and native runtime loaded cleanly.
  bool get isModelLoaded => _isModelLoaded;

  PpeLabelConfig get labelConfig => _labelConfig;

  /// Creates and safely initializes a [TflitePpeDetector] from Flutter assets.
  ///
  /// Never throws if the model asset is a placeholder, corrupted, missing, or
  /// running in a non-Android test environment without native TFLite libraries;
  /// instead marks [isModelLoaded] as `false` so manual teacher review takes over.
  static Future<TflitePpeDetector> create({
    String modelAssetPath = defaultModelAssetPath,
    String labelsAssetPath = defaultLabelsAssetPath,
    PpeLabelConfig? labelConfig,
    double minConfidence = defaultMinConfidence,
    double? iouThreshold,
  }) async {
    final resolvedConfig = labelConfig ?? await _loadConfigSafely(labelsAssetPath);
    final resolvedIou = iouThreshold ?? resolvedConfig.iouThreshold;

    Interpreter? interpreter;
    var loaded = false;

    try {
      final rawAsset = await rootBundle.load(modelAssetPath);
      final bytes = rawAsset.buffer.asUint8List(
        rawAsset.offsetInBytes,
        rawAsset.lengthInBytes,
      );

      if (_hasValidTfliteMagic(bytes) && !_containsPlaceholderMarker(bytes)) {
        final options = InterpreterOptions()..threads = 2;
        interpreter = Interpreter.fromBuffer(bytes, options: options);
        loaded = true;
      }
    } on Object {
      interpreter?.close();
      interpreter = null;
      loaded = false;
    }

    return TflitePpeDetector._(
      resolvedConfig,
      minConfidence,
      resolvedIou,
      interpreter,
      loaded,
    );
  }

  static Future<PpeLabelConfig> _loadConfigSafely(String labelsAssetPath) async {
    try {
      return await PpeLabelConfig.loadFromAsset(labelsAssetPath);
    } on Object {
      return const PpeLabelConfig(
        modelClassNames: <String>[],
        labelToApd: <String, ApdItem>{},
      );
    }
  }

  static bool _hasValidTfliteMagic(Uint8List bytes) {
    if (bytes.length < 16) return false;
    // FlatBuffer TFLite identifier "TFL3" sits at byte offset 4..8.
    return bytes[4] == 0x54 &&
        bytes[5] == 0x46 &&
        bytes[6] == 0x4C &&
        bytes[7] == 0x33;
  }

  static bool _containsPlaceholderMarker(Uint8List bytes) {
    final markerLen = _placeholderMarker.length;
    final searchLimit = math.min(bytes.length, 128) - markerLen;
    if (searchLimit < 8) return false;
    for (var i = 8; i <= searchLimit; i++) {
      var matched = true;
      for (var j = 0; j < markerLen; j++) {
        if (bytes[i + j] != _placeholderMarker[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return true;
    }
    return false;
  }

  @override
  Future<List<RawDetection>> detectFile(String imagePath) async {
    if (_disposed || !_isModelLoaded || _interpreter == null) {
      return const <RawDetection>[];
    }

    final file = File(imagePath);
    if (!file.existsSync()) {
      return const <RawDetection>[];
    }

    try {
      final rawBytes = await file.readAsBytes();
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        return const <RawDetection>[];
      }

      final oriented = img.bakeOrientation(decoded);
      final interpreter = _interpreter!;
      final inputTensor = interpreter.getInputTensor(0);
      final outputTensor = interpreter.getOutputTensor(0);

      final inputShape = inputTensor.shape;
      final inputHeight =
          inputShape.length >= 3 ? inputShape[1] : _labelConfig.inputSize;
      final inputWidth =
          inputShape.length >= 3 ? inputShape[2] : _labelConfig.inputSize;

      final letterbox = letterboxImage(oriented, inputWidth, inputHeight);
      final inputBytes = _packInputBuffer(letterbox.image, inputTensor);

      final outputBytes = Uint8List(outputTensor.numBytes());
      final outputs = <int, Object>{0: outputBytes.buffer};
      interpreter.runForMultipleInputs(<Object>[inputBytes], outputs);

      final flatOutput = _unpackOutputValues(outputBytes, outputTensor);
      return decodeYoloOutput(
        flatOutput: flatOutput,
        outputShape: outputTensor.shape,
        classNames: _labelConfig.modelClassNames,
        inputWidth: inputWidth,
        inputHeight: inputHeight,
        srcWidth: letterbox.srcWidth,
        srcHeight: letterbox.srcHeight,
        scale: letterbox.scale,
        padX: letterbox.padX,
        padY: letterbox.padY,
        minConfidence: _minConfidence,
        iouThreshold: _iouThreshold,
      );
    } on Object {
      return const <RawDetection>[];
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _isModelLoaded = false;
    try {
      _interpreter?.close();
    } on Object {
      // Ignore native teardown failures.
    }
    _interpreter = null;
  }

  /// Resizes [src] with aspect-preserving YOLO gray (114, 114, 114) padding.
  static LetterboxResult letterboxImage(
    img.Image src,
    int targetWidth,
    int targetHeight,
  ) {
    final srcW = math.max(1, src.width);
    final srcH = math.max(1, src.height);
    final scale = math.min(targetWidth / srcW, targetHeight / srcH);
    final resizedW = math.max(1, (srcW * scale).round());
    final resizedH = math.max(1, (srcH * scale).round());
    final padX = (targetWidth - resizedW) ~/ 2;
    final padY = (targetHeight - resizedH) ~/ 2;

    final resized = (resizedW == srcW && resizedH == srcH)
        ? src
        : img.copyResize(
            src,
            width: resizedW,
            height: resizedH,
            interpolation: img.Interpolation.linear,
          );

    final canvas = img.Image(width: targetWidth, height: targetHeight);
    canvas.clear(img.ColorRgb8(114, 114, 114));
    img.compositeImage(
      canvas,
      resized,
      dstX: padX,
      dstY: padY,
      blend: img.BlendMode.direct,
    );

    return LetterboxResult(
      image: canvas,
      srcWidth: srcW,
      srcHeight: srcH,
      inputWidth: targetWidth,
      inputHeight: targetHeight,
      scale: scale,
      padX: padX,
      padY: padY,
    );
  }

  static Uint8List _packInputBuffer(img.Image image, Tensor inputTensor) {
    final pixelCount = image.width * image.height;
    final type = inputTensor.type;

    if (type == TensorType.uint8) {
      final params = inputTensor.params;
      final useQuant = params.scale > 0.0;
      final out = Uint8List(pixelCount * 3);
      var idx = 0;
      for (final p in image) {
        if (useQuant) {
          out[idx++] = _quantizeChannel(p.r, params.scale, params.zeroPoint, 0, 255);
          out[idx++] = _quantizeChannel(p.g, params.scale, params.zeroPoint, 0, 255);
          out[idx++] = _quantizeChannel(p.b, params.scale, params.zeroPoint, 0, 255);
        } else {
          out[idx++] = p.r.toInt().clamp(0, 255);
          out[idx++] = p.g.toInt().clamp(0, 255);
          out[idx++] = p.b.toInt().clamp(0, 255);
        }
      }
      return out;
    }

    if (type == TensorType.int8) {
      final params = inputTensor.params;
      final scale = params.scale > 0.0 ? params.scale : (1.0 / 255.0);
      final zeroPoint = params.zeroPoint;
      final out = Int8List(pixelCount * 3);
      var idx = 0;
      for (final p in image) {
        out[idx++] = _quantizeChannel(p.r, scale, zeroPoint, -128, 127);
        out[idx++] = _quantizeChannel(p.g, scale, zeroPoint, -128, 127);
        out[idx++] = _quantizeChannel(p.b, scale, zeroPoint, -128, 127);
      }
      return out.buffer.asUint8List();
    }

    // Default float32 normalized to [0.0, 1.0].
    final out = Float32List(pixelCount * 3);
    var idx = 0;
    for (final p in image) {
      out[idx++] = p.r / 255.0;
      out[idx++] = p.g / 255.0;
      out[idx++] = p.b / 255.0;
    }
    return out.buffer.asUint8List();
  }

  static int _quantizeChannel(
    num channel,
    double scale,
    int zeroPoint,
    int minVal,
    int maxVal,
  ) {
    return (((channel / 255.0) / scale) + zeroPoint)
        .round()
        .clamp(minVal, maxVal);
  }

  static List<double> _unpackOutputValues(
    Uint8List bytes,
    Tensor outputTensor,
  ) {
    final type = outputTensor.type;
    if (type == TensorType.uint8) {
      final params = outputTensor.params;
      final scale = params.scale > 0.0 ? params.scale : (1.0 / 255.0);
      final zeroPoint = params.zeroPoint;
      return List<double>.generate(
        bytes.length,
        (i) => (bytes[i] - zeroPoint) * scale,
        growable: false,
      );
    }

    if (type == TensorType.int8) {
      final signed = Int8List.view(bytes.buffer);
      final params = outputTensor.params;
      final scale = params.scale > 0.0 ? params.scale : (1.0 / 255.0);
      final zeroPoint = params.zeroPoint;
      return List<double>.generate(
        signed.length,
        (i) => (signed[i] - zeroPoint) * scale,
        growable: false,
      );
    }

    final floats = Float32List.view(bytes.buffer);
    return List<double>.generate(
      floats.length,
      (i) => floats[i],
      growable: false,
    );
  }

  /// Decodes raw YOLOv8/YOLOv11 output tensors in either `[1, 4+C, N]`
  /// (channels-first) or `[1, N, 4+C]` (detections-first) layout and runs NMS.
  static List<RawDetection> decodeYoloOutput({
    required List<double> flatOutput,
    required List<int> outputShape,
    required List<String> classNames,
    required int inputWidth,
    required int inputHeight,
    required int srcWidth,
    required int srcHeight,
    double? scale,
    int? padX,
    int? padY,
    double minConfidence = defaultMinConfidence,
    double iouThreshold = defaultIouThreshold,
  }) {
    if (classNames.isEmpty || outputShape.length < 2) {
      return const <RawDetection>[];
    }

    final d1 = outputShape.length >= 3 ? outputShape[1] : outputShape[0];
    final d2 = outputShape.length >= 3 ? outputShape[2] : outputShape[1];
    if (d1 <= 0 || d2 <= 0 || flatOutput.length < d1 * d2) {
      return const <RawDetection>[];
    }

    final numClasses = classNames.length;
    final expectedChannels = 4 + numClasses;

    final bool channelsFirst;
    if (d1 == expectedChannels) {
      channelsFirst = true;
    } else if (d2 == expectedChannels) {
      channelsFirst = false;
    } else if (d1 < d2) {
      channelsFirst = true;
    } else {
      channelsFirst = false;
    }

    final numAttrs = channelsFirst ? d1 : d2;
    final numBoxes = channelsFirst ? d2 : d1;
    if (numAttrs < 5) {
      return const <RawDetection>[];
    }

    final usableClasses = math.min(numClasses, numAttrs - 4);
    final effectiveScale = scale ?? math.min(inputWidth / srcWidth, inputHeight / srcHeight);
    final effectivePadX =
        padX ?? ((inputWidth - (srcWidth * effectiveScale).round()) ~/ 2);
    final effectivePadY =
        padY ?? ((inputHeight - (srcHeight * effectiveScale).round()) ~/ 2);

    double readAttr(int boxIdx, int attrIdx) {
      return channelsFirst
          ? flatOutput[attrIdx * numBoxes + boxIdx]
          : flatOutput[boxIdx * numAttrs + attrIdx];
    }

    final candidates = <_DecodedBox>[];
    var maxBoxCoord = 0.0;

    for (var i = 0; i < numBoxes; i++) {
      var bestClassIdx = -1;
      var bestScore = 0.0;

      for (var c = 0; c < usableClasses; c++) {
        final score = readAttr(i, 4 + c);
        if (score.isFinite && score > bestScore) {
          bestScore = score;
          bestClassIdx = c;
        }
      }

      if (bestClassIdx < 0 || bestScore < minConfidence) {
        continue;
      }

      final cx = readAttr(i, 0);
      final cy = readAttr(i, 1);
      final w = readAttr(i, 2);
      final h = readAttr(i, 3);
      if (!cx.isFinite || !cy.isFinite || !w.isFinite || !h.isFinite) {
        continue;
      }

      maxBoxCoord = math.max(maxBoxCoord, math.max(cx.abs(), cy.abs()));
      maxBoxCoord = math.max(maxBoxCoord, math.max(w.abs(), h.abs()));

      candidates.add(
        _DecodedBox(
          cx: cx,
          cy: cy,
          w: w,
          h: h,
          label: classNames[bestClassIdx],
          confidence: bestScore.clamp(0.0, 1.0),
        ),
      );
    }

    if (candidates.isEmpty) {
      return const <RawDetection>[];
    }

    // Ultralytics TFLite exports often normalize xywh to [0, 1], while ONNX-like
    // exports emit input pixel coordinates [0, inputSize].
    final normalizedCoords = maxBoxCoord <= 2.0;

    final mapped = <RawDetection>[];
    for (final c in candidates) {
      final cxPx = normalizedCoords ? c.cx * inputWidth : c.cx;
      final cyPx = normalizedCoords ? c.cy * inputHeight : c.cy;
      final wPx = normalizedCoords ? c.w * inputWidth : c.w;
      final hPx = normalizedCoords ? c.h * inputHeight : c.h;

      final x1Px = cxPx - (wPx / 2.0);
      final y1Px = cyPx - (hPx / 2.0);
      final x2Px = cxPx + (wPx / 2.0);
      final y2Px = cyPx + (hPx / 2.0);

      final x1 = ((x1Px - effectivePadX) / effectiveScale / srcWidth).clamp(0.0, 1.0);
      final y1 = ((y1Px - effectivePadY) / effectiveScale / srcHeight).clamp(0.0, 1.0);
      final x2 = ((x2Px - effectivePadX) / effectiveScale / srcWidth).clamp(0.0, 1.0);
      final y2 = ((y2Px - effectivePadY) / effectiveScale / srcHeight).clamp(0.0, 1.0);

      if (x2 <= x1 || y2 <= y1) {
        continue;
      }

      mapped.add(
        RawDetection(
          label: c.label,
          confidence: c.confidence,
          bbox: <double>[x1, y1, x2, y2],
        ),
      );
    }

    return nonMaxSuppression(mapped, iouThreshold: iouThreshold);
  }

  /// Applies greedy Non-Maximum Suppression sorted by confidence descending.
  static List<RawDetection> nonMaxSuppression(
    List<RawDetection> detections, {
    double iouThreshold = defaultIouThreshold,
    bool classAgnostic = false,
  }) {
    if (detections.isEmpty) return const <RawDetection>[];

    final sorted = List<RawDetection>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final kept = <RawDetection>[];
    for (final candidate in sorted) {
      var suppressed = false;
      for (final existing in kept) {
        if (!classAgnostic && existing.label != candidate.label) {
          continue;
        }
        if (computeIoU(existing.bbox, candidate.bbox) > iouThreshold) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) {
        kept.add(candidate);
      }
    }
    return List<RawDetection>.unmodifiable(kept);
  }

  /// Computes Intersection-over-Union (IoU) of two `[x1, y1, x2, y2]` boxes.
  static double computeIoU(List<double> boxA, List<double> boxB) {
    if (boxA.length < 4 || boxB.length < 4) return 0.0;

    final interX1 = math.max(boxA[0], boxB[0]);
    final interY1 = math.max(boxA[1], boxB[1]);
    final interX2 = math.min(boxA[2], boxB[2]);
    final interY2 = math.min(boxA[3], boxB[3]);

    final interW = math.max(0.0, interX2 - interX1);
    final interH = math.max(0.0, interY2 - interY1);
    final interArea = interW * interH;
    if (interArea <= 0.0) return 0.0;

    final areaA =
        math.max(0.0, boxA[2] - boxA[0]) * math.max(0.0, boxA[3] - boxA[1]);
    final areaB =
        math.max(0.0, boxB[2] - boxB[0]) * math.max(0.0, boxB[3] - boxB[1]);
    final unionArea = areaA + areaB - interArea;
    if (unionArea <= 0.0) return 0.0;

    return interArea / unionArea;
  }

  /// Helper exposing the ASCII label map version for debugging/telemetry.
  static String encodeConfigSummary(PpeLabelConfig config) => jsonEncode(<String, Object?>{
        'classes': config.modelClassNames,
        'supported_apd': config.supportedItems.map((e) => e.key).toList(),
      });
}

class _DecodedBox {
  const _DecodedBox({
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
    required this.label,
    required this.confidence,
  });

  final double cx;
  final double cy;
  final double w;
  final double h;
  final String label;
  final double confidence;
}

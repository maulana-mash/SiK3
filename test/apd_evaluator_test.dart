import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/ml/apd_evaluator.dart';
import 'package:sik3/ml/ppe_label_config.dart';
import 'package:sik3/ml/tflite_ppe_detector.dart';

void main() {
  const standardConfig = PpeLabelConfig(
    modelClassNames: <String>[
      'helmet',
      'goggles',
      'mask',
      'gloves',
      'boots',
    ],
    labelToApd: <String, ApdItem>{
      'helmet': ApdItem.helm,
      'hardhat': ApdItem.helm,
      'goggles': ApdItem.kacamata,
      'safety-glass': ApdItem.kacamata,
      'glasses': ApdItem.kacamata,
      'mask': ApdItem.masker,
      'gloves': ApdItem.sarungTangan,
      'boots': ApdItem.sepatuBengkel,
      'safety-shoes': ApdItem.sepatuBengkel,
      'shoes': ApdItem.sepatuBengkel,
    },
  );

  group('ApdEvaluator', () {
    test('marks_detected_when_confidence_at_or_above_0_70', () {
      final results = ApdEvaluator.evaluate(
        upperDetections: const <RawDetection>[
          RawDetection(label: 'helmet', confidence: 0.82),
          RawDetection(label: 'mask', confidence: 0.70),
          RawDetection(label: 'helmet', confidence: 0.45),
        ],
        lowerDetections: const <RawDetection>[],
        requiredItems: const <ApdItem>{ApdItem.helm, ApdItem.masker},
        config: standardConfig,
      );

      expect(results[ApdItem.helm]?.status, ApdStatus.detected);
      expect(results[ApdItem.helm]?.confidence, closeTo(0.82, 1e-6));
      expect(results[ApdItem.masker]?.status, ApdStatus.detected);
      expect(results[ApdItem.masker]?.confidence, closeTo(0.70, 1e-6));
    });

    test('marks_needsReview_when_confidence_below_0_70', () {
      final results = ApdEvaluator.evaluate(
        upperDetections: const <RawDetection>[
          RawDetection(label: 'gloves', confidence: 0.55),
          RawDetection(label: 'goggles', confidence: 0.699),
        ],
        lowerDetections: const <RawDetection>[],
        requiredItems: const <ApdItem>{
          ApdItem.sarungTangan,
          ApdItem.kacamata,
        },
        config: standardConfig,
      );

      expect(results[ApdItem.sarungTangan]?.status, ApdStatus.needsReview);
      expect(results[ApdItem.sarungTangan]?.confidence, closeTo(0.55, 1e-6));
      expect(results[ApdItem.kacamata]?.status, ApdStatus.needsReview);
      expect(results[ApdItem.kacamata]?.confidence, closeTo(0.699, 1e-6));
    });

    test('marks_needsReview_when_item_not_in_public_model_labels', () {
      final results = ApdEvaluator.evaluate(
        upperDetections: const <RawDetection>[
          RawDetection(label: 'helmet', confidence: 0.90),
          RawDetection(label: 'safety-vest', confidence: 0.96),
        ],
        lowerDetections: const <RawDetection>[],
        requiredItems: const <ApdItem>{
          ApdItem.bajuPraktik,
          ApdItem.helm,
        },
        config: standardConfig,
      );

      expect(standardConfig.supportedItems.contains(ApdItem.bajuPraktik), isFalse);
      expect(results[ApdItem.bajuPraktik]?.status, ApdStatus.needsReview);
      expect(results[ApdItem.bajuPraktik]?.confidence, isNull);
      expect(results[ApdItem.helm]?.status, ApdStatus.detected);
    });

    test('marks_missing_when_item_supported_but_not_detected', () {
      final results = ApdEvaluator.evaluate(
        upperDetections: const <RawDetection>[],
        lowerDetections: const <RawDetection>[],
        requiredItems: const <ApdItem>{ApdItem.helm},
        config: standardConfig,
      );

      expect(results[ApdItem.helm]?.status, ApdStatus.missing);
      expect(results[ApdItem.helm]?.confidence, 0.0);
    });

    test('ignores_items_not_in_requiredItems', () {
      final results = ApdEvaluator.evaluate(
        upperDetections: const <RawDetection>[
          RawDetection(label: 'helmet', confidence: 0.91),
          RawDetection(label: 'mask', confidence: 0.88),
          RawDetection(label: 'gloves', confidence: 0.85),
        ],
        lowerDetections: const <RawDetection>[
          RawDetection(label: 'boots', confidence: 0.93),
        ],
        requiredItems: const <ApdItem>{ApdItem.helm},
        config: standardConfig,
      );

      expect(results.keys.toSet(), equals(<ApdItem>{ApdItem.helm}));
      expect(results.containsKey(ApdItem.masker), isFalse);
      expect(results.containsKey(ApdItem.sepatuBengkel), isFalse);
    });

    test('separates_upper_and_lower_zone_detections', () {
      // Cross-zone detections must NOT leak across upper and lower zones.
      final misplacedResults = ApdEvaluator.evaluate(
        upperDetections: const <RawDetection>[
          RawDetection(label: 'shoes', confidence: 0.95),
        ],
        lowerDetections: const <RawDetection>[
          RawDetection(label: 'helmet', confidence: 0.95),
        ],
        requiredItems: const <ApdItem>{
          ApdItem.helm,
          ApdItem.sepatuBengkel,
        },
        config: standardConfig,
      );

      expect(misplacedResults[ApdItem.helm]?.status, ApdStatus.missing);
      expect(misplacedResults[ApdItem.sepatuBengkel]?.status, ApdStatus.missing);

      final validZoneResults = ApdEvaluator.evaluate(
        upperDetections: const <RawDetection>[
          RawDetection(label: 'helmet', confidence: 0.84),
        ],
        lowerDetections: const <RawDetection>[
          RawDetection(label: 'shoes', confidence: 0.79),
        ],
        requiredItems: const <ApdItem>{
          ApdItem.helm,
          ApdItem.sepatuBengkel,
        },
        config: standardConfig,
      );

      expect(validZoneResults[ApdItem.helm]?.status, ApdStatus.detected);
      expect(validZoneResults[ApdItem.sepatuBengkel]?.status, ApdStatus.detected);
    });
  });

  group('PpeLabelConfig & Model Assets', () {
    test('parses_ppe_labels_json_config_correctly', () {
      const sampleJson = '''
      {
        "model_classes": ["helmet", "goggles", "mask", "gloves", "boots"],
        "label_to_apd": {
          "helmet": "helm",
          "hardhat": "helm",
          "goggles": "kacamata",
          "mask": "masker",
          "gloves": "sarung_tangan",
          "boots": "sepatu_bengkel",
          "safety-vest": null
        }
      }
      ''';

      final parsed = PpeLabelConfig.fromJsonString(sampleJson);
      expect(
        parsed.modelClassNames,
        equals(<String>['helmet', 'goggles', 'mask', 'gloves', 'boots']),
      );
      expect(parsed.mapLabel('Hardhat'), ApdItem.helm);
      expect(parsed.mapLabel('GOGGLES'), ApdItem.kacamata);
      expect(parsed.mapLabel('safety-vest'), isNull);
      expect(
        parsed.supportedItems,
        equals(<ApdItem>{
          ApdItem.helm,
          ApdItem.kacamata,
          ApdItem.masker,
          ApdItem.sarungTangan,
          ApdItem.sepatuBengkel,
        }),
      );
      expect(parsed.supportedItems.contains(ApdItem.bajuPraktik), isFalse);
    });

    test('bundled assets/models/ppe_labels.json and ppe_detector.tflite are valid', () {
      final labelsFile = File('assets/models/ppe_labels.json');
      expect(labelsFile.existsSync(), isTrue);

      final config = PpeLabelConfig.fromJsonString(labelsFile.readAsStringSync());
      expect(config.modelClassNames, isNotEmpty);
      expect(
        config.supportedItems,
        equals(<ApdItem>{
          ApdItem.helm,
          ApdItem.kacamata,
          ApdItem.masker,
          ApdItem.sarungTangan,
          ApdItem.sepatuBengkel,
        }),
      );
      expect(config.supportedItems.contains(ApdItem.bajuPraktik), isFalse);

      final modelFile = File('assets/models/ppe_detector.tflite');
      expect(modelFile.existsSync(), isTrue);
      final bytes = modelFile.readAsBytesSync();
      expect(bytes.length, greaterThan(8));
      expect(String.fromCharCodes(bytes.sublist(4, 8)), 'TFL3');

      expect(File('assets/models/.gitkeep').existsSync(), isFalse);
      expect(File('assets/models/README.md').existsSync(), isTrue);
    });
  });

  group('YOLO Post-Processing & TflitePpeDetector', () {
    test('decodeYoloOutput parses [1, 4+C, N] channels-first layout', () {
      // 2 classes => 4 + 2 = 6 rows, N = 2 candidate anchors
      // Anchor 0: cx=0.5, cy=0.5, w=0.2, h=0.2, class0=0.88, class1=0.10
      // Anchor 1: cx=0.2, cy=0.2, w=0.1, h=0.1, class0=0.05, class1=0.12 (below 0.25)
      final flat = <double>[
        0.5, 0.2, // cx
        0.5, 0.2, // cy
        0.2, 0.1, // w
        0.2, 0.1, // h
        0.88, 0.05, // class 0 (helmet)
        0.10, 0.12, // class 1 (gloves)
      ];

      final detections = TflitePpeDetector.decodeYoloOutput(
        flatOutput: flat,
        outputShape: const <int>[1, 6, 2],
        classNames: const <String>['helmet', 'gloves'],
        inputWidth: 640,
        inputHeight: 640,
        srcWidth: 640,
        srcHeight: 640,
        minConfidence: 0.25,
        iouThreshold: 0.45,
      );

      expect(detections.length, 1);
      expect(detections.first.label, 'helmet');
      expect(detections.first.confidence, closeTo(0.88, 1e-6));
      expect(detections.first.bbox[0], closeTo(0.4, 1e-5));
      expect(detections.first.bbox[1], closeTo(0.4, 1e-5));
      expect(detections.first.bbox[2], closeTo(0.6, 1e-5));
      expect(detections.first.bbox[3], closeTo(0.6, 1e-5));
    });

    test('decodeYoloOutput parses [1, N, 4+C] detections-first layout and applies NMS', () {
      // 2 classes => 6 cols, N = 3 detections in pixel space [0..640]
      // Det 0 & Det 1 are overlapping helmets (IoU > 0.45) -> Det 1 suppressed
      // Det 2 is gloves overlapping Det 0 -> kept (different class)
      final flat = <double>[
        320, 320, 128, 128, 0.90, 0.05, // helmet 0.90
        324, 324, 128, 128, 0.75, 0.02, // helmet 0.75 (high IoU with Det 0)
        320, 320, 128, 128, 0.10, 0.62, // gloves 0.62 (kept for needsReview!)
      ];

      final detections = TflitePpeDetector.decodeYoloOutput(
        flatOutput: flat,
        outputShape: const <int>[1, 3, 6],
        classNames: const <String>['helmet', 'gloves'],
        inputWidth: 640,
        inputHeight: 640,
        srcWidth: 640,
        srcHeight: 640,
        minConfidence: 0.25,
        iouThreshold: 0.45,
      );

      expect(detections.length, 2);
      expect(detections[0].label, 'helmet');
      expect(detections[0].confidence, closeTo(0.90, 1e-6));
      expect(detections[1].label, 'gloves');
      expect(detections[1].confidence, closeTo(0.62, 1e-6));
    });

    test('computeIoU and nonMaxSuppression handle overlap thresholds accurately', () {
      final iouSame = TflitePpeDetector.computeIoU(
        const <double>[0.0, 0.0, 0.5, 0.5],
        const <double>[0.0, 0.0, 0.5, 0.5],
      );
      expect(iouSame, closeTo(1.0, 1e-6));

      final iouDisjoint = TflitePpeDetector.computeIoU(
        const <double>[0.0, 0.0, 0.2, 0.2],
        const <double>[0.5, 0.5, 0.8, 0.8],
      );
      expect(iouDisjoint, 0.0);

      final kept = TflitePpeDetector.nonMaxSuppression(
        const <RawDetection>[
          RawDetection(
            label: 'helmet',
            confidence: 0.72,
            bbox: <double>[0.1, 0.1, 0.5, 0.5],
          ),
          RawDetection(
            label: 'helmet',
            confidence: 0.85,
            bbox: <double>[0.12, 0.12, 0.52, 0.52],
          ),
          RawDetection(
            label: 'helmet',
            confidence: 0.78,
            bbox: <double>[0.6, 0.6, 0.9, 0.9],
          ),
        ],
        iouThreshold: 0.45,
      );

      expect(kept.length, 2);
      expect(kept[0].confidence, closeTo(0.85, 1e-6));
      expect(kept[1].confidence, closeTo(0.78, 1e-6));
    });

    test('TflitePpeDetector fails gracefully without crashing when model cannot load', () async {
      final detector = await TflitePpeDetector.create(
        modelAssetPath: 'assets/models/non_existent_model.tflite',
        labelConfig: standardConfig,
      );

      expect(detector.isModelLoaded, isFalse);
      final detections = await detector.detectFile('non_existent_image.jpg');
      expect(detections, isEmpty);
      await detector.dispose();
    });

    test('letterboxImage pads non-square images and un-letterboxes YOLO coords', () {
      final portrait = img.Image(width: 480, height: 640);
      portrait.clear(img.ColorRgb8(20, 40, 60));

      final lb = TflitePpeDetector.letterboxImage(portrait, 640, 640);
      expect(lb.scale, closeTo(1.0, 1e-6));
      expect(lb.padX, 80);
      expect(lb.padY, 0);

      final padPixel = lb.image.getPixel(0, 0);
      expect(padPixel.r, 114);
      expect(padPixel.g, 114);
      expect(padPixel.b, 114);

      final centerPixel = lb.image.getPixel(320, 320);
      expect(centerPixel.r, 20);
      expect(centerPixel.g, 40);
      expect(centerPixel.b, 60);

      // Centered box in original 480x640 image ([0.25..0.75] x [0.25..0.75])
      // maps in 640x640 letterbox to cx=320, cy=320, w=240, h=320.
      final detections = TflitePpeDetector.decodeYoloOutput(
        flatOutput: const <double>[
          320.0, 320.0, 240.0, 320.0, 0.86,
        ],
        outputShape: const <int>[1, 5, 1],
        classNames: const <String>['helmet'],
        inputWidth: 640,
        inputHeight: 640,
        srcWidth: lb.srcWidth,
        srcHeight: lb.srcHeight,
        scale: lb.scale,
        padX: lb.padX,
        padY: lb.padY,
      );

      expect(detections.length, 1);
      expect(detections.first.bbox[0], closeTo(0.25, 1e-5));
      expect(detections.first.bbox[1], closeTo(0.25, 1e-5));
      expect(detections.first.bbox[2], closeTo(0.75, 1e-5));
      expect(detections.first.bbox[3], closeTo(0.75, 1e-5));
    });

    test('loadFromAsset and TflitePpeDetector.create handle bundled assets safely', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final loadedConfig = await PpeLabelConfig.loadFromAsset();
      expect(loadedConfig.modelClassNames, hasLength(5));
      expect(loadedConfig.supportedItems.contains(ApdItem.bajuPraktik), isFalse);

      final detector = await TflitePpeDetector.create();
      expect(detector.isModelLoaded, isFalse);
      expect(
        detector.labelConfig.supportedItems,
        equals(loadedConfig.supportedItems),
      );

      final tempDir = Directory.systemTemp.createTempSync('sik3_ppe_test_');
      try {
        final tempImg = File('${tempDir.path}/sample.png');
        final sample = img.Image(width: 64, height: 64);
        tempImg.writeAsBytesSync(img.encodePng(sample));

        final detections = await detector.detectFile(tempImg.path);
        expect(detections, isEmpty);
      } finally {
        await detector.dispose();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });
  });
}

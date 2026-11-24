import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/core/widgets/apd_svg_icon.dart';

void main() {
  group('ApdItem & ScanZone', () {
    test('defines exact 6 APD items with expected keys, labels, and SVG paths', () {
      expect(ApdItem.values.length, 6);

      expect(ApdItem.bajuPraktik.key, 'baju_praktik');
      expect(ApdItem.bajuPraktik.labelId, 'Baju Praktik');
      expect(ApdItem.bajuPraktik.shortLabelId, 'Baju');
      expect(ApdItem.bajuPraktik.svgAssetPath, 'assets/svg/baju_praktik.svg');
      expect(ApdItem.bajuPraktik.scanZone, ScanZone.upper);

      expect(ApdItem.helm.key, 'helm');
      expect(ApdItem.helm.labelId, 'Helm Safety');
      expect(ApdItem.helm.shortLabelId, 'Helm');
      expect(ApdItem.helm.svgAssetPath, 'assets/svg/helm.svg');
      expect(ApdItem.helm.scanZone, ScanZone.upper);

      expect(ApdItem.kacamata.key, 'kacamata');
      expect(ApdItem.kacamata.labelId, 'Kacamata Safety');
      expect(ApdItem.kacamata.shortLabelId, 'Kcm');
      expect(ApdItem.kacamata.svgAssetPath, 'assets/svg/kacamata.svg');
      expect(ApdItem.kacamata.scanZone, ScanZone.upper);

      expect(ApdItem.masker.key, 'masker');
      expect(ApdItem.masker.labelId, 'Masker');
      expect(ApdItem.masker.shortLabelId, 'Mskr');
      expect(ApdItem.masker.svgAssetPath, 'assets/svg/masker.svg');
      expect(ApdItem.masker.scanZone, ScanZone.upper);

      expect(ApdItem.sarungTangan.key, 'sarung_tangan');
      expect(ApdItem.sarungTangan.labelId, 'Sarung Tangan');
      expect(ApdItem.sarungTangan.shortLabelId, 'S.Tgn');
      expect(ApdItem.sarungTangan.svgAssetPath, 'assets/svg/sarung_tangan.svg');
      expect(ApdItem.sarungTangan.scanZone, ScanZone.upper);

      expect(ApdItem.sepatuBengkel.key, 'sepatu_bengkel');
      expect(ApdItem.sepatuBengkel.labelId, 'Sepatu Bengkel');
      expect(ApdItem.sepatuBengkel.shortLabelId, 'Spt');
      expect(
        ApdItem.sepatuBengkel.svgAssetPath,
        'assets/svg/sepatu_bengkel.svg',
      );
      expect(ApdItem.sepatuBengkel.scanZone, ScanZone.lower);
    });

    test('fromKey resolves valid keys and returns null on unknown key', () {
      for (final item in ApdItem.values) {
        expect(ApdItem.fromKey(item.key), item);
      }
      expect(ApdItem.fromKey('unknown_apd'), isNull);
    });

    test('all 6 SVG asset files exist and contain zero emoji', () {
      final emojiRegex = RegExp(
        r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
        unicode: true,
      );
      for (final item in ApdItem.values) {
        expect(emojiRegex.hasMatch(item.labelId), isFalse);
        expect(emojiRegex.hasMatch(item.shortLabelId), isFalse);
        final svgFile = File(item.svgAssetPath);
        expect(svgFile.existsSync(), isTrue, reason: '${item.svgAssetPath} missing');
        final svgText = svgFile.readAsStringSync();
        expect(svgText, contains('viewBox="0 0 24 24"'));
        expect(svgText, contains('stroke="currentColor"'));
        expect(emojiRegex.hasMatch(svgText), isFalse);
      }
    });
  });

  group('ApdStatus & ApdCheckResult', () {
    test('ApdStatus exposes keys, Indonesian labels, and fromKey fallback', () {
      expect(ApdStatus.detected.key, 'detected');
      expect(ApdStatus.detected.labelId, 'Lolos');
      expect(ApdStatus.needsReview.key, 'needs_review');
      expect(ApdStatus.needsReview.labelId, 'Perlu Cek');
      expect(ApdStatus.missing.key, 'missing');
      expect(ApdStatus.missing.labelId, 'Kurang');

      expect(ApdStatus.fromKey('detected'), ApdStatus.detected);
      expect(ApdStatus.fromKey('needs_review'), ApdStatus.needsReview);
      expect(ApdStatus.fromKey('missing'), ApdStatus.missing);
      expect(ApdStatus.fromKey('invalid'), ApdStatus.needsReview);
    });

    test('ApdCheckResult supports copyWith, JSON round-trip, and value equality', () {
      const original = ApdCheckResult(
        item: ApdItem.helm,
        status: ApdStatus.detected,
        confidence: 0.87,
        manualOverride: false,
        note: 'Terlihat jelas',
      );

      final roundTrip = ApdCheckResult.fromJson(original.toJson());
      expect(roundTrip, equals(original));
      expect(roundTrip.hashCode, equals(original.hashCode));

      final updated = original.copyWith(
        status: ApdStatus.missing,
        manualOverride: true,
        clearConfidence: true,
        clearNote: true,
      );
      expect(updated.item, ApdItem.helm);
      expect(updated.status, ApdStatus.missing);
      expect(updated.confidence, isNull);
      expect(updated.manualOverride, isTrue);
      expect(updated.note, isNull);
    });
  });

  group('Sik3Theme & Design Tokens', () {
    test('color, spacing, concentric radius, and motion tokens match locked spec', () {
      expect(Sik3Colors.navy, const Color(0xFF0D2D4D));
      expect(Sik3Colors.amber, const Color(0xFFF59E0B));
      expect(Sik3Colors.amberPressed, const Color(0xFFD97706));
      expect(Sik3Colors.surfaceLight, const Color(0xFFF8FAFC));
      expect(Sik3Colors.cardSurface, const Color(0xFFFFFFFF));
      expect(Sik3Colors.scannerDark, const Color(0xFF0B192C));
      expect(Sik3Colors.statusPassed, const Color(0xFF15803D));
      expect(Sik3Colors.statusReview, const Color(0xFFD97706));
      expect(Sik3Colors.statusMissing, const Color(0xFFDC2626));

      expect(Sik3Spacing.minTouchTarget, greaterThanOrEqualTo(48.0));
      expect(Sik3Radius.outer - Sik3Radius.padding, equals(Sik3Radius.inner));
      expect(
        Sik3Radius.cardOuter - Sik3Radius.cardPadding,
        equals(Sik3Radius.cardInner),
      );

      expect(Sik3Motion.fast.inMilliseconds, inInclusiveRange(150, 200));
      expect(Sik3Motion.normal.inMilliseconds, inInclusiveRange(150, 200));
      expect(Sik3Motion.curve, Curves.easeOutCubic);
    });

    test('buildSik3Theme configures Material 3, 48dp min button height, and tabular figures', () {
      final theme = buildSik3Theme();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, Sik3Colors.navy);
      expect(theme.colorScheme.secondary, Sik3Colors.amber);
      expect(theme.scaffoldBackgroundColor, Sik3Colors.surfaceLight);

      final filledMinSize = theme.filledButtonTheme.style?.minimumSize?.resolve({});
      expect(filledMinSize?.height, greaterThanOrEqualTo(48.0));

      final outlinedMinSize =
          theme.outlinedButtonTheme.style?.minimumSize?.resolve({});
      expect(outlinedMinSize?.height, greaterThanOrEqualTo(48.0));

      final tabular = Sik3Typography.tabular(const TextStyle(fontSize: 16));
      expect(tabular.fontFeatures, contains(const FontFeature.tabularFigures()));
    });
  });

  group('ApdSvgIcon widget', () {
    testWidgets('renders SvgPicture for all 6 APD items without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildSik3Theme(),
          home: Scaffold(
            body: Wrap(
              children: [
                for (final item in ApdItem.values)
                  ApdSvgIcon(
                    item: item,
                    size: 24,
                    color: Sik3Colors.navy,
                    semanticLabel: item.labelId,
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsNWidgets(ApdItem.values.length));
    });
  });
}

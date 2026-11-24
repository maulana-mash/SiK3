import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/core/models/inspection_models.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/core/widgets/apd_svg_icon.dart';
import 'package:sik3/data/app_database.dart';
import 'package:sik3/data/local_prefs.dart';
import 'package:sik3/data/qr_identity_codec.dart';
import 'package:sik3/features/teacher/apd_zone_scan_screen.dart';
import 'package:sik3/features/teacher/class_setup_screen.dart';
import 'package:sik3/features/teacher/review_draft_screen.dart';
import 'package:sik3/ml/ppe_label_config.dart';
import 'package:sik3/ml/tflite_ppe_detector.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePpeDetector implements PpeDetector {
  _FakePpeDetector({
    required this.isModelLoaded,
    this.detectionsByPath,
    this.defaultDetections = const <RawDetection>[],
  });

  @override
  final bool isModelLoaded;

  final List<RawDetection> Function(String imagePath)? detectionsByPath;
  final List<RawDetection> defaultDetections;
  final List<String> detectedPaths = <String>[];
  bool disposed = false;

  @override
  Future<List<RawDetection>> detectFile(String imagePath) async {
    detectedPaths.add(imagePath);
    if (detectionsByPath != null) {
      return detectionsByPath!(imagePath);
    }
    return defaultDetections;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

Uint8List _createSampleJpgBytes({int width = 1200, int height = 900}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(13, 45, 77));
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

Future<void> _pumpWithRealIo(
  WidgetTester tester, {
  bool Function()? until,
  Duration step = const Duration(milliseconds: 50),
  int maxSteps = 40,
}) async {
  await tester.pump();
  for (var i = 0; i < maxSteps; i++) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
    if (until != null && until()) break;
  }
  await tester.pumpAndSettle();
}

void main() {
  final emojiRegex = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
    unicode: true,
  );

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<AppDatabase> openMemoryDb() {
    return AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
  }

  Future<({SchoolClass schoolClass, InspectionSession session})>
  seedClassAndSession(
    AppDatabase db, {
    Set<ApdItem>? requiredApd,
    String className = 'XI TPM 1',
    String subjectName = 'Teknik Pemesinan Bubut',
  }) async {
    final activeApd =
        requiredApd ??
        const <ApdItem>{
          ApdItem.bajuPraktik,
          ApdItem.helm,
          ApdItem.sepatuBengkel,
        };
    final classId = await db.upsertClass(
      SchoolClass(
        name: className,
        homeroomTeacher: 'Drs. Budi Santoso',
        homeroomNip: '197801012005011002',
        requiredApd: activeApd,
      ),
    );
    final sessionDraft = InspectionSession(
      classId: classId,
      subjectName: subjectName,
      teacherName: 'Ir. Hendra Wijaya',
      teacherNip: '198003142009021001',
      homeroomTeacher: 'Drs. Budi Santoso',
      homeroomNip: '197801012005011002',
      schoolName: 'SMK Negeri 2 Surabaya',
      sessionDate: DateTime(2026, 11, 24, 8, 15),
      requiredApd: activeApd,
    );
    final sessionId = await db.createSession(sessionDraft);
    return (
      schoolClass: SchoolClass(
        id: classId,
        name: className,
        homeroomTeacher: 'Drs. Budi Santoso',
        homeroomNip: '197801012005011002',
        requiredApd: activeApd,
      ),
      session: sessionDraft.copyWith(id: sessionId),
    );
  }

  group('Pure helpers for 2-zone scan and draft review', () {
    test('compressEvidencePhotoBytes resizes longest edge to <= 800px without upscaling', () {
      final largeRaw = _createSampleJpgBytes(width: 1600, height: 1200);
      final compressed = compressEvidencePhotoBytes(largeRaw);
      final decoded = img.decodeImage(compressed);
      expect(decoded, isNotNull);
      expect(decoded!.width, 800);
      expect(decoded.height, 600);

      final smallRaw = _createSampleJpgBytes(width: 400, height: 300);
      final smallCompressed = compressEvidencePhotoBytes(smallRaw);
      final smallDecoded = img.decodeImage(smallCompressed);
      expect(smallDecoded, isNotNull);
      expect(smallDecoded!.width, 400);
      expect(smallDecoded.height, 300);
    });

    test('resolveRequiredScanZones skips zones without required APD items', () {
      expect(
        resolveRequiredScanZones(ApdItem.values.toSet()),
        equals(const <ScanZone>[ScanZone.upper, ScanZone.lower]),
      );
      expect(
        resolveRequiredScanZones(const <ApdItem>{ApdItem.helm, ApdItem.masker}),
        equals(const <ScanZone>[ScanZone.upper]),
      );
      expect(
        resolveRequiredScanZones(const <ApdItem>{ApdItem.sepatuBengkel}),
        equals(const <ScanZone>[ScanZone.lower]),
      );
    });

    test('nextApdStatusOnTap follows needsReview -> detected -> missing -> detected', () {
      expect(nextApdStatusOnTap(ApdStatus.needsReview), ApdStatus.detected);
      expect(nextApdStatusOnTap(ApdStatus.detected), ApdStatus.missing);
      expect(nextApdStatusOnTap(ApdStatus.missing), ApdStatus.detected);
    });
  });

  group('ReviewDraftScreen', () {
    testWidgets(
      'displays students sorted numerically with tabular numbers, Perlu Cek badge, SVG icons, and zero emoji',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(db);
        final sessionId = seeded.session.id!;

        await db.upsertScanRecord(
          ScanRecord(
            sessionId: sessionId,
            nisn: '0080000010',
            attendanceNo: '10',
            studentName: 'Dedi Pratama',
            apdResults: const <ApdItem, ApdCheckResult>{
              ApdItem.bajuPraktik: ApdCheckResult(
                item: ApdItem.bajuPraktik,
                status: ApdStatus.detected,
                confidence: 0.91,
              ),
              ApdItem.helm: ApdCheckResult(
                item: ApdItem.helm,
                status: ApdStatus.missing,
                confidence: 0.0,
              ),
              ApdItem.sepatuBengkel: ApdCheckResult(
                item: ApdItem.sepatuBengkel,
                status: ApdStatus.detected,
                confidence: 0.87,
              ),
            },
            scannedAt: DateTime(2026, 11, 24, 8, 20),
          ),
        );
        await db.upsertScanRecord(
          ScanRecord(
            sessionId: sessionId,
            nisn: '0080000002',
            attendanceNo: '02',
            studentName: 'Citra Ayu',
            apdResults: const <ApdItem, ApdCheckResult>{
              ApdItem.bajuPraktik: ApdCheckResult(
                item: ApdItem.bajuPraktik,
                status: ApdStatus.detected,
                confidence: 0.92,
              ),
              ApdItem.helm: ApdCheckResult(
                item: ApdItem.helm,
                status: ApdStatus.needsReview,
                confidence: 0.58,
              ),
              ApdItem.sepatuBengkel: ApdCheckResult(
                item: ApdItem.sepatuBengkel,
                status: ApdStatus.detected,
                confidence: 0.88,
              ),
            },
            scannedAt: DateTime(2026, 11, 24, 8, 18),
          ),
        );
        await db.upsertScanRecord(
          ScanRecord(
            sessionId: sessionId,
            nisn: '0080000001',
            attendanceNo: '1',
            studentName: 'Ahmad Fauzi',
            apdResults: const <ApdItem, ApdCheckResult>{
              ApdItem.bajuPraktik: ApdCheckResult(
                item: ApdItem.bajuPraktik,
                status: ApdStatus.detected,
                confidence: 0.95,
              ),
              ApdItem.helm: ApdCheckResult(
                item: ApdItem.helm,
                status: ApdStatus.detected,
                confidence: 0.94,
              ),
              ApdItem.sepatuBengkel: ApdCheckResult(
                item: ApdItem.sepatuBengkel,
                status: ApdStatus.detected,
                confidence: 0.90,
              ),
            },
            scannedAt: DateTime(2026, 11, 24, 8, 16),
          ),
        );

        tester.view.physicalSize = const Size(420, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ReviewDraftScreen(
              schoolClass: seeded.schoolClass,
              session: seeded.session,
              database: db,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Class and subject metadata shown.
        expect(find.text('XI TPM 1'), findsWidgets);
        expect(find.text('Teknik Pemesinan Bubut'), findsWidgets);

        // Numeric ordering: 1 (Ahmad Fauzi) < 02 (Citra Ayu) < 10 (Dedi Pratama).
        final yAhmad = tester.getTopLeft(find.text('Ahmad Fauzi')).dy;
        final yCitra = tester.getTopLeft(find.text('Citra Ayu')).dy;
        final yDedi = tester.getTopLeft(find.text('Dedi Pratama')).dy;
        expect(yAhmad, lessThan(yCitra));
        expect(yCitra, lessThan(yDedi));

        // Semantic badges present.
        expect(find.text('Lengkap'), findsWidgets);
        expect(find.text('Perlu Cek'), findsWidgets);
        expect(find.text('Kurang'), findsWidgets);

        // Tabular numerals on NISN and summary metric count.
        final nisnWidget = tester.widget<Text>(find.text('NISN 0080000001'));
        expect(
          nisnWidget.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
        final totalMetric = tester.widget<Text>(
          find.byKey(const ValueKey<String>('summary_count_total')),
        );
        expect(totalMetric.data, '3');
        expect(
          totalMetric.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );

        // Pure SVG icons and 48dp+ touch targets on APD chips.
        expect(find.byType(ApdSvgIcon), findsNWidgets(9));
        final helmChip = find.byKey(
          const ValueKey<String>('apd_chip_0080000002_helm'),
        );
        expect(tester.getSize(helmChip).height, greaterThanOrEqualTo(48.0));

        // Zero emoji in rendered UI text.
        for (final textWidget in tester.widgetList<Text>(find.byType(Text))) {
          expect(emojiRegex.hasMatch(textWidget.data ?? ''), isFalse);
        }
      },
    );

    testWidgets(
      '1-tap APD chip toggles needsReview -> detected -> missing -> detected and persists isManualOverride = true to SQLite',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(
          db,
          requiredApd: const <ApdItem>{ApdItem.bajuPraktik, ApdItem.helm},
        );
        final sessionId = seeded.session.id!;

        await db.upsertScanRecord(
          ScanRecord(
            sessionId: sessionId,
            nisn: '0081112223',
            attendanceNo: '04',
            studentName: 'Bagas Saputra',
            apdResults: const <ApdItem, ApdCheckResult>{
              ApdItem.bajuPraktik: ApdCheckResult(
                item: ApdItem.bajuPraktik,
                status: ApdStatus.detected,
                confidence: 0.90,
              ),
              ApdItem.helm: ApdCheckResult(
                item: ApdItem.helm,
                status: ApdStatus.needsReview,
                confidence: 0.52,
              ),
            },
            scannedAt: DateTime(2026, 11, 24, 8, 25),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ReviewDraftScreen(
              schoolClass: seeded.schoolClass,
              session: seeded.session,
              database: db,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey<String>('summary_count_review')),
              )
              .data,
          '1',
        );

        final helmChip = find.byKey(
          const ValueKey<String>('apd_chip_0081112223_helm'),
        );
        await tester.ensureVisible(helmChip);

        // Tap 1: needsReview -> detected.
        await tester.tap(helmChip);
        await tester.pumpAndSettle();

        var records = await db.getSessionRecords(sessionId);
        expect(records.single.apdResults[ApdItem.helm]?.status, ApdStatus.detected);
        expect(records.single.apdResults[ApdItem.helm]?.manualOverride, isTrue);
        expect(records.single.isManualOverride, isTrue);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey<String>('summary_count_complete')),
              )
              .data,
          '1',
        );

        // Tap 2: detected -> missing.
        await tester.tap(helmChip);
        await tester.pumpAndSettle();

        records = await db.getSessionRecords(sessionId);
        expect(records.single.apdResults[ApdItem.helm]?.status, ApdStatus.missing);
        expect(records.single.isManualOverride, isTrue);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey<String>('summary_count_missing')),
              )
              .data,
          '1',
        );

        // Tap 3: missing -> detected.
        await tester.tap(helmChip);
        await tester.pumpAndSettle();

        records = await db.getSessionRecords(sessionId);
        expect(records.single.apdResults[ApdItem.helm]?.status, ApdStatus.detected);
        expect(records.single.isManualOverride, isTrue);
      },
    );

    testWidgets(
      'Bersihkan Foto Draft deletes disk photos and clears DB photo paths without deleting student checklist',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(db);
        final sessionId = seeded.session.id!;

        final tempDir = Directory.systemTemp.createTempSync('sik3_review_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final upperFile = File(p.join(tempDir.path, 'upper.jpg'))
          ..writeAsBytesSync(_createSampleJpgBytes(width: 200, height: 150));
        final lowerFile = File(p.join(tempDir.path, 'lower.jpg'))
          ..writeAsBytesSync(_createSampleJpgBytes(width: 200, height: 150));

        await db.upsertScanRecord(
          ScanRecord(
            sessionId: sessionId,
            nisn: '0089990001',
            attendanceNo: '07',
            studentName: 'Eka Ramadhan',
            apdResults: const <ApdItem, ApdCheckResult>{
              ApdItem.bajuPraktik: ApdCheckResult(
                item: ApdItem.bajuPraktik,
                status: ApdStatus.detected,
                confidence: 0.93,
              ),
              ApdItem.helm: ApdCheckResult(
                item: ApdItem.helm,
                status: ApdStatus.detected,
                confidence: 0.89,
              ),
              ApdItem.sepatuBengkel: ApdCheckResult(
                item: ApdItem.sepatuBengkel,
                status: ApdStatus.needsReview,
              ),
            },
            upperPhotoPath: upperFile.path,
            lowerPhotoPath: lowerFile.path,
            scannedAt: DateTime(2026, 11, 24, 8, 30),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ReviewDraftScreen(
              schoolClass: seeded.schoolClass,
              session: seeded.session,
              database: db,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Lihat Foto button opens photo viewer sheet before purge.
        final viewPhotoBtn = find.byKey(
          const ValueKey<String>('view_photo_0089990001'),
        );
        expect(viewPhotoBtn, findsOneWidget);
        await tester.ensureVisible(viewPhotoBtn);
        await tester.pumpAndSettle();
        await tester.tap(viewPhotoBtn);
        await _pumpWithRealIo(
          tester,
          until: () => find.byType(Image).evaluate().length == 2,
        );
        expect(find.text('Foto Bukti — Eka Ramadhan'), findsOneWidget);
        expect(find.text('Zona Atas (Badan, Kepala & Tangan)'), findsOneWidget);
        expect(find.text('Zona Bawah (Kaki & Sepatu Bengkel)'), findsOneWidget);
        expect(find.byType(Image), findsNWidgets(2));
        await tester.tap(find.byTooltip('Tutup'));
        await tester.pumpAndSettle();

        // Tap Bersihkan Foto Draft and confirm dialog.
        final purgeButton = find.byKey(
          const ValueKey<String>('purge_draft_photos_button'),
        );
        await tester.ensureVisible(purgeButton);
        await tester.pumpAndSettle();
        await tester.tap(purgeButton);
        await tester.pumpAndSettle();

        expect(find.text('Bersihkan Foto Draft?'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm_purge_photos_button')),
        );
        await _pumpWithRealIo(
          tester,
          until: () =>
              !upperFile.existsSync() &&
              !lowerFile.existsSync() &&
              find
                  .byKey(const ValueKey<String>('view_photo_0089990001'))
                  .evaluate()
                  .isEmpty,
        );

        // Disk files removed & DB photo paths cleared, checklist intact.
        expect(upperFile.existsSync(), isFalse);
        expect(lowerFile.existsSync(), isFalse);

        final records = await db.getSessionRecords(sessionId);
        expect(records, hasLength(1));
        expect(records.single.studentName, 'Eka Ramadhan');
        expect(records.single.upperPhotoPath, isNull);
        expect(records.single.lowerPhotoPath, isNull);
        expect(
          records.single.apdResults[ApdItem.bajuPraktik]?.status,
          ApdStatus.detected,
        );
        expect(
          records.single.apdResults[ApdItem.sepatuBengkel]?.status,
          ApdStatus.needsReview,
        );
        expect(find.text('Eka Ramadhan'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('view_photo_0089990001')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Scan Siswa CTA invokes QR scanner -> zone scanner and refreshes draft list; renders cleanly on 360px 1.3x scale',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(db);
        final sessionId = seeded.session.id!;

        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: MaterialApp(
              theme: buildSik3Theme(),
              home: ReviewDraftScreen(
                schoolClass: seeded.schoolClass,
                session: seeded.session,
                database: db,
                openQrScanner: (context, {defaultClassName}) async {
                  return const StudentIdentity(
                    nisn: '0085554443',
                    attendanceNo: '12',
                    name: 'Fajar Nugroho',
                    className: 'XI TPM 1',
                    major: 'Teknik Pemesinan',
                  );
                },
                openZoneScanner: (
                  context, {
                  required session,
                  required student,
                  required database,
                }) async {
                  final rec = ScanRecord(
                    sessionId: sessionId,
                    nisn: student.nisn,
                    attendanceNo: student.attendanceNo,
                    studentName: student.name,
                    apdResults: const <ApdItem, ApdCheckResult>{
                      ApdItem.bajuPraktik: ApdCheckResult(
                        item: ApdItem.bajuPraktik,
                        status: ApdStatus.detected,
                        confidence: 0.91,
                      ),
                      ApdItem.helm: ApdCheckResult(
                        item: ApdItem.helm,
                        status: ApdStatus.needsReview,
                      ),
                      ApdItem.sepatuBengkel: ApdCheckResult(
                        item: ApdItem.sepatuBengkel,
                        status: ApdStatus.detected,
                        confidence: 0.85,
                      ),
                    },
                    scannedAt: DateTime(2026, 11, 24, 8, 40),
                  );
                  final id = await database.upsertScanRecord(rec);
                  return rec.copyWith(id: id);
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Belum Ada Siswa Diperiksa'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('scan_student_button')),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Fajar Nugroho'), findsOneWidget);
        expect(find.text('NISN 0085554443'), findsOneWidget);
      },
    );

    testWidgets(
      'supports Scan Ulang, missing-photo placeholder, and optional AI/PDF seams cleanly',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(
          db,
          requiredApd: const <ApdItem>{ApdItem.helm},
        );
        final sessionId = seeded.session.id!;

        await db.upsertScanRecord(
          ScanRecord(
            sessionId: sessionId,
            nisn: '0083332221',
            attendanceNo: '09',
            studentName: 'Gilang Pratama',
            apdResults: const <ApdItem, ApdCheckResult>{
              ApdItem.helm: ApdCheckResult(
                item: ApdItem.helm,
                status: ApdStatus.needsReview,
              ),
            },
            upperPhotoPath: '/nonexistent/missing_evidence.jpg',
            scannedAt: DateTime(2026, 11, 24, 8, 50),
          ),
        );

        var aiVerifyCalls = 0;
        var exportCalls = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ReviewDraftScreen(
              schoolClass: seeded.schoolClass,
              session: seeded.session,
              database: db,
              openZoneScanner: (
                context, {
                required session,
                required student,
                required database,
              }) async {
                final rescanned = ScanRecord(
                  sessionId: sessionId,
                  nisn: student.nisn,
                  attendanceNo: student.attendanceNo,
                  studentName: student.name,
                  apdResults: const <ApdItem, ApdCheckResult>{
                    ApdItem.helm: ApdCheckResult(
                      item: ApdItem.helm,
                      status: ApdStatus.detected,
                      confidence: 0.96,
                    ),
                  },
                  scannedAt: DateTime(2026, 11, 24, 8, 55),
                );
                final id = await database.upsertScanRecord(rescanned);
                return rescanned.copyWith(id: id);
              },
              onVerifyWithAi: (record) async {
                aiVerifyCalls += 1;
                await db.upsertScanRecord(record.copyWith(isAiVerified: true));
              },
              onExportPdf: (context, schoolClass, session, records) async {
                exportCalls += 1;
                await db.updateSessionStatus(session.id!, 'exported');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Missing file shows graceful placeholder instead of throwing.
        final viewPhoto = find.byKey(
          const ValueKey<String>('view_photo_0083332221'),
        );
        await tester.ensureVisible(viewPhoto);
        await tester.pumpAndSettle();
        await tester.tap(viewPhoto);
        await _pumpWithRealIo(
          tester,
          until: () => find
              .text('Berkas foto tidak ditemukan atau sudah dibersihkan.')
              .evaluate()
              .isNotEmpty,
        );
        expect(
          find.text('Berkas foto tidak ditemukan atau sudah dibersihkan.'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Tutup'));
        await tester.pumpAndSettle();

        // Scan Ulang updates student record in-place.
        final rescanBtn = find.byKey(
          const ValueKey<String>('rescan_student_0083332221'),
        );
        await tester.ensureVisible(rescanBtn);
        await tester.pumpAndSettle();
        await tester.tap(rescanBtn);
        await _pumpWithRealIo(
          tester,
          until: () => find
              .text('Hasil Gilang Pratama tersimpan di draft lokal.')
              .evaluate()
              .isNotEmpty,
        );

        var records = await db.getSessionRecords(sessionId);
        expect(records, hasLength(1));
        expect(records.single.apdResults[ApdItem.helm]?.status, ApdStatus.detected);

        // Optional Verifikasi AI seam invokes callback & shows Terverifikasi AI badge.
        final aiBtn = find.byKey(const ValueKey<String>('verify_ai_0083332221'));
        await tester.ensureVisible(aiBtn);
        await tester.pumpAndSettle();
        await tester.tap(aiBtn);
        await tester.pumpAndSettle();
        expect(aiVerifyCalls, 1);
        expect(find.text('Terverifikasi AI'), findsOneWidget);

        // Optional Ekspor PDF seam invokes callback & reflects exported status.
        await tester.tap(find.byKey(const ValueKey<String>('export_pdf_button')));
        await tester.pumpAndSettle();
        expect(exportCalls, 1);
        expect(find.text('Diekspor'), findsOneWidget);
      },
    );

    testWidgets(
      'locks APD chip toggles and other AI verify buttons while AI verify or busy action is in flight',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(
          db,
          requiredApd: const <ApdItem>{ApdItem.helm},
        );
        final sessionId = seeded.session.id!;

        await db.upsertScanRecord(
          ScanRecord(
            sessionId: sessionId,
            nisn: '0081000001',
            attendanceNo: '01',
            studentName: 'Hadi Kusuma',
            apdResults: const <ApdItem, ApdCheckResult>{
              ApdItem.helm: ApdCheckResult(
                item: ApdItem.helm,
                status: ApdStatus.needsReview,
              ),
            },
            scannedAt: DateTime(2026, 11, 24, 9, 0),
          ),
        );
        await db.upsertScanRecord(
          ScanRecord(
            sessionId: sessionId,
            nisn: '0081000002',
            attendanceNo: '02',
            studentName: 'Indra Wijaya',
            apdResults: const <ApdItem, ApdCheckResult>{
              ApdItem.helm: ApdCheckResult(
                item: ApdItem.helm,
                status: ApdStatus.needsReview,
              ),
            },
            scannedAt: DateTime(2026, 11, 24, 9, 1),
          ),
        );

        final aiCompleter = Completer<void>();
        final exportCompleter = Completer<void>();
        var aiCalls = 0;

        tester.view.physicalSize = const Size(420, 1100);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ReviewDraftScreen(
              schoolClass: seeded.schoolClass,
              session: seeded.session,
              database: db,
              onVerifyWithAi: (record) async {
                aiCalls += 1;
                await aiCompleter.future;
                await db.upsertScanRecord(record.copyWith(isAiVerified: true));
              },
              onExportPdf: (_, _, _, _) => exportCompleter.future,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Start AI verify for student 1 (remains in flight).
        await tester.tap(
          find.byKey(const ValueKey<String>('verify_ai_0081000001')),
        );
        await tester.pump();

        expect(aiCalls, 1);

        // Student 1's APD chip tap is ignored while AI verify is in flight.
        await tester.tap(
          find.byKey(const ValueKey<String>('apd_chip_0081000001_helm')),
        );
        await tester.pump();
        var s1 = (await db.getSessionRecords(sessionId)).first;
        expect(s1.apdResults[ApdItem.helm]?.status, ApdStatus.needsReview);
        expect(s1.isManualOverride, isFalse);

        // Student 2's AI button is disabled while student 1 is verifying.
        final aiBtn2 = tester.widget<TextButton>(
          find.byKey(const ValueKey<String>('verify_ai_0081000002')),
        );
        expect(aiBtn2.onPressed, isNull);
        await tester.tap(
          find.byKey(const ValueKey<String>('verify_ai_0081000002')),
        );
        await tester.pump();
        expect(aiCalls, 1);

        // Complete AI verify -> student 1 verified and buttons re-enabled.
        aiCompleter.complete();
        await tester.pumpAndSettle();
        expect(find.text('Terverifikasi AI'), findsOneWidget);

        // 2. Start busy action (Export PDF) -> APD chip & AI buttons locked while busy.
        await tester.tap(
          find.byKey(const ValueKey<String>('export_pdf_button')),
        );
        await tester.pump();

        await tester.tap(
          find.byKey(const ValueKey<String>('apd_chip_0081000002_helm')),
        );
        await tester.pump();
        final s2WhileBusy = (await db.getSessionRecords(sessionId))[1];
        expect(
          s2WhileBusy.apdResults[ApdItem.helm]?.status,
          ApdStatus.needsReview,
        );
        expect(
          tester
              .widget<TextButton>(
                find.byKey(const ValueKey<String>('verify_ai_0081000002')),
              )
              .onPressed,
          isNull,
        );

        exportCompleter.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'ZonePhotoPreviewCard loads existing photo asynchronously from cached bytes and handles missing photo safely',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(db);
        final tempDir = Directory.systemTemp.createTempSync('sik3_preview_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final existingUpper = File(p.join(tempDir.path, 'existing_upper.jpg'))
          ..writeAsBytesSync(_createSampleJpgBytes(width: 240, height: 180));
        final missingLowerPath = p.join(tempDir.path, 'deleted_lower.jpg');

        await db.upsertScanRecord(
          ScanRecord(
            sessionId: seeded.session.id!,
            nisn: '0082000099',
            attendanceNo: '03',
            studentName: 'Joko Susilo',
            apdResults: const <ApdItem, ApdCheckResult>{
              ApdItem.bajuPraktik: ApdCheckResult(
                item: ApdItem.bajuPraktik,
                status: ApdStatus.detected,
              ),
            },
            upperPhotoPath: existingUpper.path,
            lowerPhotoPath: missingLowerPath,
            scannedAt: DateTime(2026, 11, 24, 9, 5),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ReviewDraftScreen(
              schoolClass: seeded.schoolClass,
              session: seeded.session,
              database: db,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final viewPhotoBtn = find.byKey(
          const ValueKey<String>('view_photo_0082000099'),
        );
        await tester.ensureVisible(viewPhotoBtn);
        await tester.pumpAndSettle();
        await tester.tap(viewPhotoBtn);
        await _pumpWithRealIo(
          tester,
          until: () =>
              find.byType(Image).evaluate().length == 1 &&
              find
                  .text('Berkas foto tidak ditemukan atau sudah dibersihkan.')
                  .evaluate()
                  .isNotEmpty,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(Image), findsOneWidget);
        expect(
          find.text('Berkas foto tidak ditemukan atau sudah dibersihkan.'),
          findsOneWidget,
        );
      },
    );
  });

  group('ApdZoneScanScreen', () {
    const sampleStudent = StudentIdentity(
      nisn: '0081234567',
      attendanceNo: '05',
      name: 'Ahmad Fauzi',
      className: 'XI TPM 1',
      major: 'Teknik Pemesinan',
    );

    const testLabelConfig = PpeLabelConfig(
      modelClassNames: <String>['hardhat', 'safety_vest', 'safety_boots'],
      labelToApd: <String, ApdItem>{
        'hardhat': ApdItem.helm,
        'safety_vest': ApdItem.bajuPraktik,
        'safety_boots': ApdItem.sepatuBengkel,
      },
    );

    testWidgets(
      'captures Upper -> Lower zones, compresses photos to <=800px, evaluates detections, and saves ScanRecord',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(db);
        final tempDir = Directory.systemTemp.createTempSync('sik3_zone_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final detector = _FakePpeDetector(
          isModelLoaded: true,
          detectionsByPath: (path) {
            if (path.contains('_upper_')) {
              return const <RawDetection>[
                RawDetection(label: 'hardhat', confidence: 0.91),
                RawDetection(label: 'safety_vest', confidence: 0.86),
              ];
            }
            return const <RawDetection>[
              RawDetection(label: 'safety_boots', confidence: 0.88),
            ];
          },
        );

        ScanRecord? savedResult;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      savedResult = await Navigator.of(context)
                          .push<ScanRecord>(
                            MaterialPageRoute<ScanRecord>(
                              builder: (_) => ApdZoneScanScreen(
                                session: seeded.session,
                                student: sampleStudent,
                                database: db,
                                detector: detector,
                                labelConfig: testLabelConfig,
                                evidenceDirectoryResolver: () async => tempDir,
                                cameraPreviewBuilder: (_, zone) => ColoredBox(
                                  color: Sik3Colors.scannerDark,
                                  child: Center(
                                    child: Text('PREVIEW_${zone.name}'),
                                  ),
                                ),
                                capturePhotoBytes: (_) async =>
                                    _createSampleJpgBytes(
                                      width: 1200,
                                      height: 900,
                                    ),
                              ),
                            ),
                          );
                    },
                    child: const Text('Buka Kamera 2-Zona'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka Kamera 2-Zona'));
        await tester.pumpAndSettle();

        // Step 1: Upper zone guidance & student identity.
        expect(find.text('Ahmad Fauzi'), findsOneWidget);
        expect(
          find.text(
            'Arahkan ke badan atas — angkat kedua tangan di depan dada',
          ),
          findsOneWidget,
        );
        expect(find.text('PREVIEW_upper'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('zone_capture_button')),
        );
        await _pumpWithRealIo(
          tester,
          until: () => find.text('PREVIEW_lower').evaluate().isNotEmpty,
        );

        // Step 2: Lower zone guidance.
        expect(
          find.text('Arahkan ke area kaki & sepatu bengkel'),
          findsOneWidget,
        );
        expect(find.text('PREVIEW_lower'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('zone_capture_button')),
        );
        await _pumpWithRealIo(
          tester,
          until: () => savedResult != null,
        );

        // Popped with saved ScanRecord and persisted in SQLite.
        expect(savedResult, isNotNull);
        expect(savedResult!.upperPhotoPath, isNotNull);
        expect(savedResult!.lowerPhotoPath, isNotNull);
        expect(File(savedResult!.upperPhotoPath!).existsSync(), isTrue);
        expect(File(savedResult!.lowerPhotoPath!).existsSync(), isTrue);

        final upperDecoded = img.decodeImage(
          File(savedResult!.upperPhotoPath!).readAsBytesSync(),
        );
        expect(upperDecoded!.width, lessThanOrEqualTo(800));
        expect(upperDecoded.height, lessThanOrEqualTo(800));

        expect(
          savedResult!.apdResults[ApdItem.helm]?.status,
          ApdStatus.detected,
        );
        expect(
          savedResult!.apdResults[ApdItem.bajuPraktik]?.status,
          ApdStatus.detected,
        );
        expect(
          savedResult!.apdResults[ApdItem.sepatuBengkel]?.status,
          ApdStatus.detected,
        );

        final dbRecords = await db.getSessionRecords(seeded.session.id!);
        expect(dbRecords, hasLength(1));
        expect(dbRecords.single.nisn, sampleStudent.nisn);
      },
    );

    testWidgets(
      'skips lower zone automatically when sepatuBengkel is not required',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(
          db,
          requiredApd: const <ApdItem>{ApdItem.helm},
        );
        final tempDir = Directory.systemTemp.createTempSync('sik3_upper_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final detector = _FakePpeDetector(isModelLoaded: false);
        ScanRecord? savedResult;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      savedResult = await Navigator.of(context)
                          .push<ScanRecord>(
                            MaterialPageRoute<ScanRecord>(
                              builder: (_) => ApdZoneScanScreen(
                                session: seeded.session,
                                student: sampleStudent,
                                database: db,
                                detector: detector,
                                labelConfig: testLabelConfig,
                                evidenceDirectoryResolver: () async => tempDir,
                                cameraPreviewBuilder: (_, zone) =>
                                    const ColoredBox(
                                      color: Sik3Colors.scannerDark,
                                    ),
                                capturePhotoBytes: (_) async =>
                                    _createSampleJpgBytes(
                                      width: 640,
                                      height: 480,
                                    ),
                              ),
                            ),
                          );
                    },
                    child: const Text('Buka'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka'));
        await tester.pumpAndSettle();

        // Honest note when offline model is not loaded.
        expect(
          find.text('Deteksi offline belum aktif — ceklis ditandai Perlu Cek'),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('zone_capture_button')),
        );
        await _pumpWithRealIo(
          tester,
          until: () => savedResult != null,
        );

        expect(savedResult, isNotNull);
        expect(savedResult!.upperPhotoPath, isNotNull);
        expect(savedResult!.lowerPhotoPath, isNull);
        expect(
          savedResult!.apdResults[ApdItem.helm]?.status,
          ApdStatus.needsReview,
        );
      },
    );

    testWidgets(
      'skips upper zone automatically when only sepatuBengkel is required',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(
          db,
          requiredApd: const <ApdItem>{ApdItem.sepatuBengkel},
        );
        final tempDir = Directory.systemTemp.createTempSync('sik3_lower_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final detector = _FakePpeDetector(
          isModelLoaded: true,
          defaultDetections: const <RawDetection>[
            RawDetection(label: 'safety_boots', confidence: 0.92),
          ],
        );
        ScanRecord? savedResult;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      savedResult = await Navigator.of(context)
                          .push<ScanRecord>(
                            MaterialPageRoute<ScanRecord>(
                              builder: (_) => ApdZoneScanScreen(
                                session: seeded.session,
                                student: sampleStudent,
                                database: db,
                                detector: detector,
                                labelConfig: testLabelConfig,
                                evidenceDirectoryResolver: () async => tempDir,
                                cameraPreviewBuilder: (_, zone) => ColoredBox(
                                  color: Sik3Colors.scannerDark,
                                  child: Center(
                                    child: Text('PREVIEW_${zone.name}'),
                                  ),
                                ),
                                capturePhotoBytes: (_) async =>
                                    _createSampleJpgBytes(
                                      width: 640,
                                      height: 480,
                                    ),
                              ),
                            ),
                          );
                    },
                    child: const Text('Buka Zona Bawah'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka Zona Bawah'));
        await tester.pumpAndSettle();

        expect(find.text('PREVIEW_lower'), findsOneWidget);
        expect(
          find.text('Arahkan ke area kaki & sepatu bengkel'),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('zone_capture_button')),
        );
        await _pumpWithRealIo(
          tester,
          until: () => savedResult != null,
        );

        expect(savedResult, isNotNull);
        expect(savedResult!.upperPhotoPath, isNull);
        expect(savedResult!.lowerPhotoPath, isNotNull);
        expect(
          savedResult!.apdResults[ApdItem.sepatuBengkel]?.status,
          ApdStatus.detected,
        );
      },
    );

    testWidgets(
      'shows dark recovery card when camera permission denied and allows retry or Lanjut Penilaian Manual Tanpa Foto',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(db);
        final detector = _FakePpeDetector(isModelLoaded: false);
        var cameraAttempts = 0;
        ScanRecord? savedResult;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      savedResult = await Navigator.of(context)
                          .push<ScanRecord>(
                            MaterialPageRoute<ScanRecord>(
                              builder: (_) => ApdZoneScanScreen(
                                session: seeded.session,
                                student: sampleStudent,
                                database: db,
                                detector: detector,
                                labelConfig: testLabelConfig,
                                availableCamerasProvider: () async {
                                  cameraAttempts += 1;
                                  throw CameraException(
                                    'CameraAccessDenied',
                                    'User denied camera permission.',
                                  );
                                },
                              ),
                            ),
                          );
                    },
                    child: const Text('Buka Kamera'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka Kamera'));
        await tester.pumpAndSettle();

        expect(cameraAttempts, 1);
        expect(find.text('Kamera Tidak Tersedia'), findsOneWidget);
        expect(find.text('Coba Lagi'), findsOneWidget);

        // Retry button re-attempts camera initialization cleanly.
        await tester.tap(
          find.byKey(const ValueKey<String>('retry_camera_button')),
        );
        await tester.pumpAndSettle();
        expect(cameraAttempts, 2);

        final manualBtn = find.byKey(
          const ValueKey<String>('manual_without_photo_button'),
        );
        expect(manualBtn, findsOneWidget);
        expect(find.text('Lanjut Penilaian Manual Tanpa Foto'), findsOneWidget);

        await tester.tap(manualBtn);
        await tester.pumpAndSettle();

        expect(savedResult, isNotNull);
        expect(savedResult!.upperPhotoPath, isNull);
        expect(savedResult!.lowerPhotoPath, isNull);
        for (final item in seeded.session.requiredApd) {
          expect(savedResult!.apdResults[item]?.status, ApdStatus.needsReview);
        }
        expect(await db.getSessionRecords(seeded.session.id!), hasLength(1));
      },
    );

    testWidgets(
      'capture failure surfaces reachable Manual SnackBar action that completes manual assessment without photo',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(db);
        final detector = _FakePpeDetector(isModelLoaded: true);
        ScanRecord? savedResult;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      savedResult = await Navigator.of(context)
                          .push<ScanRecord>(
                            MaterialPageRoute<ScanRecord>(
                              builder: (_) => ApdZoneScanScreen(
                                session: seeded.session,
                                student: sampleStudent,
                                database: db,
                                detector: detector,
                                labelConfig: testLabelConfig,
                                cameraPreviewBuilder: (_, zone) =>
                                    const ColoredBox(
                                      color: Sik3Colors.scannerDark,
                                    ),
                                capturePhotoBytes: (_) async {
                                  throw Exception('Hardware shutter failure');
                                },
                              ),
                            ),
                          );
                    },
                    child: const Text('Buka Kamera Gagal'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka Kamera Gagal'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('zone_capture_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Gagal mengambil foto. Coba lagi atau gunakan penilaian manual tanpa foto.',
          ),
          findsOneWidget,
        );
        expect(find.text('Manual'), findsOneWidget);

        await tester.tap(find.text('Manual'));
        await tester.pumpAndSettle();

        expect(savedResult, isNotNull);
        expect(savedResult!.upperPhotoPath, isNull);
        expect(savedResult!.lowerPhotoPath, isNull);
        for (final item in seeded.session.requiredApd) {
          expect(savedResult!.apdResults[item]?.status, ApdStatus.needsReview);
        }
        expect(await db.getSessionRecords(seeded.session.id!), hasLength(1));
      },
    );

    testWidgets(
      'PopScope blocks Back navigation while capture/save processing is active',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedClassAndSession(
          db,
          requiredApd: const <ApdItem>{ApdItem.helm},
        );
        final tempDir = Directory.systemTemp.createTempSync('sik3_popscope_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final captureCompleter = Completer<Uint8List>();
        final detector = _FakePpeDetector(isModelLoaded: false);
        ScanRecord? savedResult;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      savedResult = await Navigator.of(context)
                          .push<ScanRecord>(
                            MaterialPageRoute<ScanRecord>(
                              builder: (_) => ApdZoneScanScreen(
                                session: seeded.session,
                                student: sampleStudent,
                                database: db,
                                detector: detector,
                                labelConfig: testLabelConfig,
                                evidenceDirectoryResolver: () async => tempDir,
                                cameraPreviewBuilder: (_, zone) =>
                                    const ColoredBox(
                                      color: Sik3Colors.scannerDark,
                                    ),
                                capturePhotoBytes: (_) =>
                                    captureCompleter.future,
                              ),
                            ),
                          );
                    },
                    child: const Text('Buka PopScope Test'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka PopScope Test'));
        await tester.pumpAndSettle();

        // Trigger capture -> enters _isProcessing = true.
        await tester.tap(
          find.byKey(const ValueKey<String>('zone_capture_button')),
        );
        await tester.pump();

        // Attempt Back navigation while processing -> blocked by PopScope.
        await tester.pageBack();
        await tester.pump();
        expect(find.byType(ApdZoneScanScreen), findsOneWidget);

        // Complete capture -> finishes save and pops cleanly with ScanRecord.
        captureCompleter.complete(
          _createSampleJpgBytes(width: 400, height: 300),
        );
        await _pumpWithRealIo(tester, until: () => savedResult != null);

        expect(find.byType(ApdZoneScanScreen), findsNothing);
        expect(savedResult, isNotNull);
        expect(File(savedResult!.upperPhotoPath!).existsSync(), isTrue);
      },
    );
  });

  group('ClassSetupScreen wiring into ReviewDraftScreen', () {
    testWidgets(
      'starting a session prompts Mata Praktik sheet, opens ReviewDraftScreen, and lists resumable sessions',
      (tester) async {
        final prefs = await LocalPrefs.open();
        final db = await openMemoryDb();
        addTearDown(db.close);

        await db.upsertClass(
          const SchoolClass(
            name: 'XI TKR 1',
            homeroomTeacher: 'Pak Joko',
            requiredApd: <ApdItem>{
              ApdItem.bajuPraktik,
              ApdItem.sepatuBengkel,
            },
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ClassSetupScreen(
              prefs: prefs,
              database: db,
              onSwitchRole: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final startButton = find.byKey(
          const ValueKey<String>('start_session_button'),
        );
        await tester.ensureVisible(startButton);
        await tester.tap(startButton);
        await tester.pumpAndSettle();

        // Bottom sheet asks for Mata Praktik.
        expect(
          find.byKey(const ValueKey<String>('start_session_subject_sheet_field')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('start_session_subject_sheet_field')),
          'Perawatan Rem Cakram',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm_start_session_button')),
        );
        await tester.pumpAndSettle();

        // Navigated to ReviewDraftScreen with created session.
        expect(find.byType(ReviewDraftScreen), findsOneWidget);
        expect(find.text('Perawatan Rem Cakram'), findsWidgets);

        // Navigate back to ClassSetupScreen -> session listed & resumable.
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.byType(ClassSetupScreen), findsOneWidget);
        expect(find.text('Perawatan Rem Cakram'), findsWidgets);

        // Tap saved session card to reopen ReviewDraftScreen.
        final sessions = await db.getSessionsForClass(1);
        expect(sessions, hasLength(1));
        final sessionCard = find.byKey(
          ValueKey<String>('resume_session_${sessions.single.id}'),
        );
        await tester.ensureVisible(sessionCard);
        await tester.tap(sessionCard);
        await tester.pumpAndSettle();

        expect(find.byType(ReviewDraftScreen), findsOneWidget);
        expect(find.text('Perawatan Rem Cakram'), findsWidgets);

        // Return to ClassSetupScreen and delete the saved session with confirmation.
        await tester.pageBack();
        await tester.pumpAndSettle();

        final deleteSessionBtn = find.byKey(
          ValueKey<String>('delete_session_${sessions.single.id}'),
        );
        await tester.ensureVisible(deleteSessionBtn);
        await tester.tap(deleteSessionBtn);
        await tester.pumpAndSettle();

        expect(find.text('Hapus Sesi Inspeksi?'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm_delete_session_button')),
        );
        await tester.pumpAndSettle();

        expect(await db.getSessionsForClass(1), isEmpty);
      },
    );

    testWidgets(
      'inline Mata Praktik starts ReviewDraftScreen directly without popping redundant subject sheet',
      (tester) async {
        final prefs = await LocalPrefs.open();
        final db = await openMemoryDb();
        addTearDown(db.close);

        await db.upsertClass(
          const SchoolClass(
            name: 'XI TP 2',
            homeroomTeacher: 'Pak Wawan',
            requiredApd: <ApdItem>{
              ApdItem.bajuPraktik,
              ApdItem.helm,
            },
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ClassSetupScreen(
              prefs: prefs,
              database: db,
              onSwitchRole: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Enter Mata Praktik inline -> should jump straight to ReviewDraftScreen.
        final subjectField = find.byKey(
          const ValueKey<String>('session_subject_field'),
        );
        await tester.ensureVisible(subjectField);
        await tester.pumpAndSettle();
        await tester.enterText(subjectField, 'Pengelasan SMAW');

        final startButton = find.byKey(
          const ValueKey<String>('start_session_button'),
        );
        await tester.ensureVisible(startButton);
        await tester.pumpAndSettle();
        await tester.tap(startButton);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('start_session_subject_sheet_field')),
          findsNothing,
        );
        expect(find.byType(ReviewDraftScreen), findsOneWidget);
        expect(find.text('Pengelasan SMAW'), findsWidgets);

        // Returning and clearing inline field prompts the subject sheet again.
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.ensureVisible(subjectField);
        await tester.pumpAndSettle();
        await tester.enterText(subjectField, '');
        await tester.ensureVisible(startButton);
        await tester.pumpAndSettle();
        await tester.tap(startButton);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('start_session_subject_sheet_field')),
          findsOneWidget,
        );
      },
    );
  });
}

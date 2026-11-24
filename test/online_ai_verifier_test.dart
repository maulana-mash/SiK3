import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/core/models/inspection_models.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/core/widgets/apd_svg_icon.dart';
import 'package:sik3/data/app_database.dart';
import 'package:sik3/data/local_prefs.dart';
import 'package:sik3/features/teacher/review_draft_screen.dart';
import 'package:sik3/ml/online_ai_verifier.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _StubOnlineAiVerifier extends OnlineAiVerifier {
  _StubOnlineAiVerifier(this._handler);

  final Future<OnlineVerifyResult> Function({
    required String? upperPhotoPath,
    required String? lowerPhotoPath,
    required Set<ApdItem> requiredItems,
    required String endpointUrl,
  })
  _handler;

  int callCount = 0;

  @override
  Future<OnlineVerifyResult> verify({
    required String? upperPhotoPath,
    required String? lowerPhotoPath,
    required Set<ApdItem> requiredItems,
    required String endpointUrl,
  }) {
    callCount += 1;
    return _handler(
      upperPhotoPath: upperPhotoPath,
      lowerPhotoPath: lowerPhotoPath,
      requiredItems: requiredItems,
      endpointUrl: endpointUrl,
    );
  }
}

void main() {
  final emojiRegex = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
    unicode: true,
  );

  late Directory tempDir;
  late File upperPhoto;
  late File lowerPhoto;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = Directory.systemTemp.createTempSync('sik3_online_ai_test_');
    upperPhoto = File(p.join(tempDir.path, 'upper.jpg'))
      ..writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02]);
    lowerPhoto = File(p.join(tempDir.path, 'lower.jpg'))
      ..writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x03, 0x04]);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('OnlineAiVerifier', () {
    test('parses_valid_json_response_into_apd_results', () async {
      Map<String, dynamic>? capturedBody;
      Uri? capturedUri;

      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'item': 'baju_praktik',
                'worn': true,
                'confidence': 0.93,
                'note': 'Wearpack bengkel terlihat lengkap.',
              },
              <String, dynamic>{
                'item': 'helm',
                'worn': false,
                'confidence': 0.88,
                'note': 'Kepala tidak mengenakan helm safety.',
              },
              <String, dynamic>{
                'item': 'kacamata',
                'worn': true,
                'confidence': 0.62,
                'note': 'Wajah agak silau, perlu cek langsung.',
              },
              // Non-required item returned by AI should be ignored.
              <String, dynamic>{
                'item': 'masker',
                'worn': true,
                'confidence': 0.95,
                'note': 'Masker terdeteksi.',
              },
            ],
            'summary': 'Baju praktik lolos, helm tidak dipakai, kacamata perlu cek.',
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final verifier = OnlineAiVerifier(client: mockClient);
      final requiredItems = const <ApdItem>{
        ApdItem.bajuPraktik,
        ApdItem.helm,
        ApdItem.kacamata,
        ApdItem.sepatuBengkel,
      };

      final result = await verifier.verify(
        upperPhotoPath: upperPhoto.path,
        lowerPhotoPath: lowerPhoto.path,
        requiredItems: requiredItems,
        endpointUrl: 'https://sik3-verify.vercel.app/api/verify-apd',
      );

      expect(
        capturedUri,
        Uri.parse('https://sik3-verify.vercel.app/api/verify-apd'),
      );
      expect(capturedBody, isNotNull);
      expect(
        capturedBody!['requiredItems'],
        equals(<String>['baju_praktik', 'helm', 'kacamata', 'sepatu_bengkel']),
      );
      expect(capturedBody!['upperPhotoBase64'], isA<String>());
      expect(capturedBody!['lowerPhotoBase64'], isA<String>());

      expect(result, isA<VerifySuccess>());
      final success = result as VerifySuccess;
      expect(
        success.summary,
        'Baju praktik lolos, helm tidak dipakai, kacamata perlu cek.',
      );

      // Filtered strictly to requiredItems (masker ignored).
      expect(success.results.keys.toSet(), equals(requiredItems));
      expect(success.results.containsKey(ApdItem.masker), isFalse);

      // confidence >= 0.70 & worn == true -> detected
      expect(
        success.results[ApdItem.bajuPraktik]?.status,
        ApdStatus.detected,
      );
      expect(success.results[ApdItem.bajuPraktik]?.confidence, 0.93);
      expect(success.results[ApdItem.bajuPraktik]?.manualOverride, isFalse);
      expect(
        success.results[ApdItem.bajuPraktik]?.note,
        'Wearpack bengkel terlihat lengkap.',
      );

      // confidence >= 0.70 & worn == false -> missing
      expect(success.results[ApdItem.helm]?.status, ApdStatus.missing);
      expect(success.results[ApdItem.helm]?.confidence, 0.88);
      expect(success.results[ApdItem.helm]?.manualOverride, isFalse);

      // confidence < 0.70 -> needsReview
      expect(success.results[ApdItem.kacamata]?.status, ApdStatus.needsReview);
      expect(success.results[ApdItem.kacamata]?.confidence, 0.62);

      // Missing required item from AI response -> needsReview
      expect(
        success.results[ApdItem.sepatuBengkel]?.status,
        ApdStatus.needsReview,
      );
      expect(success.results[ApdItem.sepatuBengkel]?.manualOverride, isFalse);
    });

    test(
      'returns_graceful_failure_on_offline_socket_exception_without_throwing',
      () async {
        final mockClient = MockClient((_) async {
          throw const SocketException('Failed host lookup: offline');
        });

        final verifier = OnlineAiVerifier(client: mockClient);
        final result = await verifier.verify(
          upperPhotoPath: upperPhoto.path,
          lowerPhotoPath: null,
          requiredItems: const <ApdItem>{ApdItem.helm},
          endpointUrl: 'https://sik3-verify.vercel.app/api/verify-apd',
        );

        expect(result, isA<VerifyFailure>());
        final failure = result as VerifyFailure;
        expect(failure.isTimeout, isFalse);
        expect(failure.message, isNotEmpty);
        expect(emojiRegex.hasMatch(failure.message), isFalse);
      },
    );

    test(
      'returns_graceful_failure_on_timeout_without_throwing',
      () async {
        final mockClient = MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          return http.Response('{}', 200);
        });

        final verifier = OnlineAiVerifier(
          client: mockClient,
          timeout: const Duration(milliseconds: 40),
        );
        expect(
          OnlineAiVerifier(timeout: const Duration(seconds: 30)).timeout,
          lessThanOrEqualTo(const Duration(seconds: 10)),
        );

        final result = await verifier.verify(
          upperPhotoPath: upperPhoto.path,
          lowerPhotoPath: null,
          requiredItems: const <ApdItem>{ApdItem.helm},
          endpointUrl: 'https://sik3-verify.vercel.app/api/verify-apd',
        );

        expect(result, isA<VerifyFailure>());
        final failure = result as VerifyFailure;
        expect(failure.isTimeout, isTrue);
        expect(failure.message, isNotEmpty);
        expect(emojiRegex.hasMatch(failure.message), isFalse);
      },
    );

    test(
      'returns_graceful_failure_on_http_500_or_invalid_json',
      () async {
        final serverErrorClient = MockClient(
          (_) async => http.Response(
            jsonEncode(<String, String>{'error': 'Internal Server Error'}),
            500,
          ),
        );
        final verifier500 = OnlineAiVerifier(client: serverErrorClient);
        final res500 = await verifier500.verify(
          upperPhotoPath: upperPhoto.path,
          lowerPhotoPath: null,
          requiredItems: const <ApdItem>{ApdItem.helm},
          endpointUrl: 'https://sik3-verify.vercel.app/api/verify-apd',
        );
        expect(res500, isA<VerifyFailure>());
        expect((res500 as VerifyFailure).isTimeout, isFalse);

        final badJsonClient = MockClient(
          (_) async => http.Response('not-valid-json{{{', 200),
        );
        final verifierBadJson = OnlineAiVerifier(client: badJsonClient);
        final resBadJson = await verifierBadJson.verify(
          upperPhotoPath: upperPhoto.path,
          lowerPhotoPath: null,
          requiredItems: const <ApdItem>{ApdItem.helm},
          endpointUrl: 'https://sik3-verify.vercel.app/api/verify-apd',
        );
        expect(resBadJson, isA<VerifyFailure>());
        expect((resBadJson as VerifyFailure).isTimeout, isFalse);

        // Missing items list in JSON -> VerifyFailure.
        final missingItemsClient = MockClient(
          (_) async => http.Response(jsonEncode(<String, dynamic>{'ok': true}), 200),
        );
        final resMissingItems = await OnlineAiVerifier(
          client: missingItemsClient,
        ).verify(
          upperPhotoPath: upperPhoto.path,
          lowerPhotoPath: null,
          requiredItems: const <ApdItem>{ApdItem.helm},
          endpointUrl: 'https://sik3-verify.vercel.app/api/verify-apd',
        );
        expect(resMissingItems, isA<VerifyFailure>());

        // Invalid endpoint URL & missing photos -> VerifyFailure without throwing.
        final invalidUrlResult = await verifier500.verify(
          upperPhotoPath: upperPhoto.path,
          lowerPhotoPath: null,
          requiredItems: const <ApdItem>{ApdItem.helm},
          endpointUrl: 'ftp://invalid-host',
        );
        expect(invalidUrlResult, isA<VerifyFailure>());

        var networkCalled = false;
        final guardClient = MockClient((_) async {
          networkCalled = true;
          return http.Response('{}', 200);
        });
        final noPhotoResult = await OnlineAiVerifier(client: guardClient).verify(
          upperPhotoPath: null,
          lowerPhotoPath: p.join(tempDir.path, 'does_not_exist.jpg'),
          requiredItems: const <ApdItem>{ApdItem.helm},
          endpointUrl: 'https://sik3-verify.vercel.app/api/verify-apd',
        );
        expect(noPhotoResult, isA<VerifyFailure>());
        expect(networkCalled, isFalse);
      },
    );
  });

  group('ReviewDraftScreen optional Online AI Verification', () {
    Future<AppDatabase> openMemoryDb() {
      return AppDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
    }

    Future<({SchoolClass schoolClass, InspectionSession session})>
    seedSessionWithStudent(
      AppDatabase db, {
      String? upperPath,
      String? lowerPath,
    }) async {
      const requiredApd = <ApdItem>{
        ApdItem.bajuPraktik,
        ApdItem.helm,
        ApdItem.sepatuBengkel,
      };
      final classId = await db.upsertClass(
        const SchoolClass(
          name: 'XI TPM 2',
          homeroomTeacher: 'Dra. Siti Rahmawati',
          homeroomNip: '197905122006042003',
          requiredApd: requiredApd,
        ),
      );
      final sessionDraft = InspectionSession(
        classId: classId,
        subjectName: 'Teknik Pengelasan',
        teacherName: 'Ir. Hendra Wijaya',
        teacherNip: '198003142009021001',
        homeroomTeacher: 'Dra. Siti Rahmawati',
        homeroomNip: '197905122006042003',
        schoolName: 'SMK Negeri 2 Surabaya',
        sessionDate: DateTime(2026, 11, 24, 9, 30),
        requiredApd: requiredApd,
      );
      final sessionId = await db.createSession(sessionDraft);

      await db.upsertScanRecord(
        ScanRecord(
          sessionId: sessionId,
          nisn: '0087776655',
          attendanceNo: '05',
          studentName: 'Bima Saputra',
          apdResults: const <ApdItem, ApdCheckResult>{
            ApdItem.bajuPraktik: ApdCheckResult(
              item: ApdItem.bajuPraktik,
              status: ApdStatus.needsReview,
            ),
            ApdItem.helm: ApdCheckResult(
              item: ApdItem.helm,
              status: ApdStatus.needsReview,
              confidence: 0.55,
            ),
            ApdItem.sepatuBengkel: ApdCheckResult(
              item: ApdItem.sepatuBengkel,
              status: ApdStatus.detected,
              confidence: 0.91,
            ),
          },
          upperPhotoPath: upperPath,
          lowerPhotoPath: lowerPath,
          scannedAt: DateTime(2026, 11, 24, 9, 35),
        ),
      );

      return (
        schoolClass: SchoolClass(
          id: classId,
          name: 'XI TPM 2',
          homeroomTeacher: 'Dra. Siti Rahmawati',
          homeroomNip: '197905122006042003',
          requiredApd: requiredApd,
        ),
        session: sessionDraft.copyWith(id: sessionId),
      );
    }

    testWidgets(
      'failure shows friendly SnackBar and leaves SQLite draft untouched; hides AI button when endpoint is empty',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedSessionWithStudent(
          db,
          upperPath: upperPhoto.path,
          lowerPath: lowerPhoto.path,
        );
        final sessionId = seeded.session.id!;

        // 1. When endpoint is empty and onVerifyWithAi is null, AI button is hidden.
        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ReviewDraftScreen(
              schoolClass: seeded.schoolClass,
              session: seeded.session,
              database: db,
              aiEndpointUrl: '',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('verify_ai_0087776655')),
          findsNothing,
        );

        final failingVerifier = _StubOnlineAiVerifier(
          ({
            required upperPhotoPath,
            required lowerPhotoPath,
            required requiredItems,
            required endpointUrl,
          }) async {
            return const VerifyFailure(
              'Tidak ada koneksi internet untuk Verifikasi AI. Draft lokal Anda tetap aman.',
            );
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ReviewDraftScreen(
              key: const ValueKey<String>('review_screen_with_endpoint'),
              schoolClass: seeded.schoolClass,
              session: seeded.session,
              database: db,
              aiEndpointUrl: 'https://sik3-verify.vercel.app/api/verify-apd',
              aiVerifier: failingVerifier,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final aiButton = find.byKey(
          const ValueKey<String>('verify_ai_0087776655'),
        );
        expect(aiButton, findsOneWidget);
        expect(find.text('Verifikasi AI Tambahan'), findsOneWidget);

        await tester.ensureVisible(aiButton);
        await tester.pumpAndSettle();
        await tester.tap(aiButton);
        await tester.pumpAndSettle();

        expect(failingVerifier.callCount, 1);
        expect(
          find.text(
            'Tidak ada koneksi internet untuk Verifikasi AI. Draft lokal Anda tetap aman.',
          ),
          findsOneWidget,
        );

        // SQLite draft must remain completely unchanged.
        final recordsAfterFailure = await db.getSessionRecords(sessionId);
        expect(recordsAfterFailure.single.isAiVerified, isFalse);
        expect(
          recordsAfterFailure.single.apdResults[ApdItem.bajuPraktik]?.status,
          ApdStatus.needsReview,
        );
        expect(
          recordsAfterFailure.single.apdResults[ApdItem.helm]?.status,
          ApdStatus.needsReview,
        );
      },
    );

    testWidgets(
      'missing evidence photos shows friendly SnackBar without calling network',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedSessionWithStudent(
          db,
          upperPath: null,
          lowerPath: null,
        );

        final noPhotoVerifier = _StubOnlineAiVerifier(
          ({
            required upperPhotoPath,
            required lowerPhotoPath,
            required requiredItems,
            required endpointUrl,
          }) async {
            return const VerifyFailure('Should not be called');
          },
        );

        tester.view.physicalSize = const Size(420, 1000);
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
              aiEndpointUrl: 'https://sik3-verify.vercel.app/api/verify-apd',
              aiVerifier: noPhotoVerifier,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final aiButtonNoPhoto = find.byKey(
          const ValueKey<String>('verify_ai_0087776655'),
        );
        await tester.ensureVisible(aiButtonNoPhoto);
        await tester.pumpAndSettle();
        await tester.tap(aiButtonNoPhoto);
        await tester.pumpAndSettle();

        expect(noPhotoVerifier.callCount, 0);
        expect(
          find.text(
            'Foto bukti siswa belum tersedia atau sudah dibersihkan. Lakukan Scan Ulang terlebih dahulu.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'success shows M3 confirmation dialog with ApdSvgIcon & tabular confidence; cancel preserves SQLite and confirm updates SQLite with isAiVerified = true',
      (tester) async {
        final db = await openMemoryDb();
        addTearDown(db.close);
        final seeded = await seedSessionWithStudent(
          db,
          upperPath: upperPhoto.path,
          lowerPath: lowerPhoto.path,
        );
        final sessionId = seeded.session.id!;

        final prefs = await LocalPrefs.open();
        await prefs.saveTeacherProfile(
          const TeacherProfile(
            name: 'Ir. Hendra Wijaya',
            aiEndpointUrl: 'https://sik3-verify.vercel.app/api/verify-apd',
          ),
        );

        final successVerifier = _StubOnlineAiVerifier(
          ({
            required upperPhotoPath,
            required lowerPhotoPath,
            required requiredItems,
            required endpointUrl,
          }) async {
            return const VerifySuccess(
              <ApdItem, ApdCheckResult>{
                ApdItem.bajuPraktik: ApdCheckResult(
                  item: ApdItem.bajuPraktik,
                  status: ApdStatus.detected,
                  confidence: 0.94,
                  manualOverride: false,
                  note: 'Wearpack biru lengkap.',
                ),
                ApdItem.helm: ApdCheckResult(
                  item: ApdItem.helm,
                  status: ApdStatus.missing,
                  confidence: 0.89,
                  manualOverride: false,
                  note: 'Helm tidak terlihat di kepala.',
                ),
                ApdItem.sepatuBengkel: ApdCheckResult(
                  item: ApdItem.sepatuBengkel,
                  status: ApdStatus.detected,
                  confidence: 0.96,
                  manualOverride: false,
                  note: 'Sepatu safety tertutup.',
                ),
              },
              'Baju dan sepatu sesuai, helm tidak digunakan.',
            );
          },
        );

        tester.view.physicalSize = const Size(420, 1000);
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
              prefs: prefs,
              aiEndpointUrl: prefs.getTeacherProfile().aiEndpointUrl,
              aiVerifier: successVerifier,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final aiButton = find.byKey(
          const ValueKey<String>('verify_ai_0087776655'),
        );
        await tester.ensureVisible(aiButton);
        await tester.pumpAndSettle();

        // 1. Trigger AI verify and tap Batal -> SQLite stays untouched.
        await tester.tap(aiButton);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Konfirmasi Hasil Verifikasi AI'), findsOneWidget);
        expect(
          find.text('Baju dan sepatu sesuai, helm tidak digunakan.'),
          findsOneWidget,
        );
        expect(find.text('Wearpack biru lengkap.'), findsOneWidget);
        expect(find.text('Helm tidak terlihat di kepala.'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ApdSvgIcon),
          ),
          findsNWidgets(3),
        );

        // Confidence percentage inside dialog uses tabular numerals.
        final conf94Finder = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('94%'),
        );
        expect(conf94Finder, findsOneWidget);
        final conf94Widget = tester.widget<Text>(conf94Finder);
        expect(
          conf94Widget.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );

        // Zero emoji in dialog text.
        for (final textWidget in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Text),
          ),
        )) {
          expect(emojiRegex.hasMatch(textWidget.data ?? ''), isFalse);
        }

        await tester.tap(
          find.byKey(const ValueKey<String>('cancel_apply_ai_button')),
        );
        await tester.pumpAndSettle();

        var records = await db.getSessionRecords(sessionId);
        expect(records.single.isAiVerified, isFalse);
        expect(
          records.single.apdResults[ApdItem.bajuPraktik]?.status,
          ApdStatus.needsReview,
        );
        expect(
          records.single.apdResults[ApdItem.helm]?.status,
          ApdStatus.needsReview,
        );

        // 2. Trigger AI verify again and confirm Terapkan Hasil AI -> updates SQLite.
        await tester.tap(aiButton);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('confirm_apply_ai_button')),
        );
        await tester.pumpAndSettle();

        records = await db.getSessionRecords(sessionId);
        expect(records.single.isAiVerified, isTrue);
        expect(
          records.single.apdResults[ApdItem.bajuPraktik]?.status,
          ApdStatus.detected,
        );
        expect(
          records.single.apdResults[ApdItem.bajuPraktik]?.manualOverride,
          isFalse,
        );
        expect(
          records.single.apdResults[ApdItem.helm]?.status,
          ApdStatus.missing,
        );
        expect(
          records.single.apdResults[ApdItem.helm]?.manualOverride,
          isFalse,
        );
        expect(
          records.single.apdResults[ApdItem.sepatuBengkel]?.status,
          ApdStatus.detected,
        );
        expect(find.text('Terverifikasi AI'), findsOneWidget);
      },
    );
  });
}

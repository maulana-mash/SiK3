import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/core/models/inspection_models.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/core/widgets/apd_svg_icon.dart';
import 'package:sik3/data/local_prefs.dart';
import 'package:sik3/data/qr_identity_codec.dart';
import 'package:sik3/features/teacher/class_setup_screen.dart';
import 'package:sik3/features/teacher/qr_scan_screen.dart';

void main() {
  final emojiRegex = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
    unicode: true,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Canonical inspection models', () {
    test('SchoolClass, InspectionSession, and ScanRecord support copyWith and equality', () {
      final initialClass = SchoolClass(
        id: 1,
        name: 'XI TPM 1',
        homeroomTeacher: 'Drs. Budi Santoso',
        homeroomNip: '197801012005011002',
        requiredApd: const <ApdItem>{
          ApdItem.sepatuBengkel,
          ApdItem.bajuPraktik,
          ApdItem.kacamata,
        },
      );

      expect(
        initialClass.orderedRequiredApd,
        equals(const <ApdItem>[
          ApdItem.bajuPraktik,
          ApdItem.kacamata,
          ApdItem.sepatuBengkel,
        ]),
      );
      expect(
        initialClass,
        equals(
          SchoolClass(
            id: 1,
            name: 'XI TPM 1',
            homeroomTeacher: 'Drs. Budi Santoso',
            homeroomNip: '197801012005011002',
            requiredApd: const <ApdItem>{
              ApdItem.kacamata,
              ApdItem.bajuPraktik,
              ApdItem.sepatuBengkel,
            },
          ),
        ),
      );
      expect(
        initialClass.copyWith(clearId: true, name: 'XI TPM 2').id,
        isNull,
      );

      final date = DateTime(2026, 11, 24, 7, 30);
      final session = InspectionSession(
        id: 10,
        classId: 1,
        subjectName: 'Teknik Pemesinan Bubut',
        teacherName: 'Siti Aminah, S.Pd',
        teacherNip: '198505122010012008',
        homeroomTeacher: 'Drs. Budi Santoso',
        homeroomNip: '197801012005011002',
        schoolName: 'SMK Negeri 1',
        sessionDate: date,
        requiredApd: const <ApdItem>{ApdItem.bajuPraktik, ApdItem.helm},
      );
      expect(session.status, 'draft');
      expect(session.copyWith(status: 'exported').status, 'exported');

      final record = ScanRecord(
        id: 99,
        sessionId: 10,
        nisn: '0081234567',
        attendanceNo: '05',
        studentName: 'Ahmad Fauzi',
        apdResults: const <ApdItem, ApdCheckResult>{
          ApdItem.helm: ApdCheckResult(
            item: ApdItem.helm,
            status: ApdStatus.detected,
            confidence: 0.91,
          ),
        },
        upperPhotoPath: '/tmp/upper.jpg',
        lowerPhotoPath: '/tmp/lower.jpg',
        scannedAt: date,
      );

      final cleared = record.copyWith(
        clearUpperPhotoPath: true,
        clearLowerPhotoPath: true,
        isManualOverride: true,
      );
      expect(cleared.upperPhotoPath, isNull);
      expect(cleared.lowerPhotoPath, isNull);
      expect(cleared.isManualOverride, isTrue);
      expect(cleared.apdResults, equals(record.apdResults));
    });
  });

  group('ClassSetupScreen', () {
    testWidgets(
      'toggles all 6 required APD SVG cards and blocks starting a session when 0 APD selected',
      (tester) async {
        final prefs = await LocalPrefs.open();
        var sessionStartCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ClassSetupScreen(
              prefs: prefs,
              onSwitchRole: () {},
              loadClasses: () async => const <SchoolClass>[
                SchoolClass(
                  id: 1,
                  name: 'XI TKR 1',
                  homeroomTeacher: 'Pak Joko',
                  requiredApd: <ApdItem>{
                    ApdItem.bajuPraktik,
                    ApdItem.helm,
                    ApdItem.kacamata,
                    ApdItem.masker,
                    ApdItem.sarungTangan,
                    ApdItem.sepatuBengkel,
                  },
                ),
              ],
              onStartSession: (context, schoolClass, session) async {
                sessionStartCount += 1;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // All 6 APD SVG icons rendered with >= 48dp touch target and zero emoji.
        expect(find.byType(ApdSvgIcon), findsNWidgets(6));
        for (final item in ApdItem.values) {
          final toggle = find.byKey(
            ValueKey<String>('apd_toggle_${item.key}'),
          );
          expect(toggle, findsOneWidget);
          expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48.0));
        }
        for (final textWidget in tester.widgetList<Text>(find.byType(Text))) {
          expect(emojiRegex.hasMatch(textWidget.data ?? ''), isFalse);
        }

        // Default 6/6 active.
        expect(find.text('6/6 Wajib'), findsOneWidget);

        // Toggle all 6 items off one by one.
        for (final item in ApdItem.values) {
          final toggle = find.byKey(
            ValueKey<String>('apd_toggle_${item.key}'),
          );
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
        }

        expect(find.text('0/6 Wajib'), findsOneWidget);
        expect(
          find.text('Pilih minimal 1 APD wajib sebelum memulai sesi inspeksi.'),
          findsOneWidget,
        );

        // Attempt to start session with 0 required APD does not succeed.
        final startButton = find.byKey(
          const ValueKey<String>('start_session_button'),
        );
        await tester.ensureVisible(startButton);
        await tester.tap(startButton);
        await tester.pumpAndSettle();
        expect(sessionStartCount, 0);

        // Re-enable 1 APD item (Sepatu Bengkel) and verify session starts.
        final shoesToggle = find.byKey(
          const ValueKey<String>('apd_toggle_sepatu_bengkel'),
        );
        await tester.ensureVisible(shoesToggle);
        await tester.tap(shoesToggle);
        await tester.pumpAndSettle();

        expect(find.text('1/6 Wajib'), findsOneWidget);

        await tester.ensureVisible(startButton);
        await tester.tap(startButton);
        await tester.pumpAndSettle();
        expect(sessionStartCount, 1);
      },
    );

    testWidgets(
      'adds a class with homeroom teacher and optional NIP, persists teacher profile, and starts session',
      (tester) async {
        final prefs = await LocalPrefs.open();
        final savedClasses = <SchoolClass>[];
        InspectionSession? startedSession;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ClassSetupScreen(
              prefs: prefs,
              onSwitchRole: () {},
              loadClasses: () async => List<SchoolClass>.from(savedClasses),
              saveClass: (schoolClass) async {
                final stored = schoolClass.copyWith(
                  id: schoolClass.id ?? (savedClasses.length + 1),
                );
                savedClasses
                  ..removeWhere((c) => c.id == stored.id)
                  ..add(stored);
                return stored;
              },
              onStartSession: (context, schoolClass, session) async {
                startedSession = session;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Update Teacher Profile & optional AI URL in settings sheet.
        await tester.tap(
          find.byKey(const ValueKey<String>('teacher_profile_settings_button')),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('teacher_profile_name_field')),
          'Ir. Hendra Wijaya',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('teacher_profile_nip_field')),
          '198003142009021001',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('teacher_profile_school_field')),
          'SMK Negeri 2 Surabaya',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('teacher_profile_ai_url_field')),
          'https://sik3.example.vercel.app/api/verify-apd',
        );
        final saveProfileButton = find.byKey(
          const ValueKey<String>('teacher_profile_save_button'),
        );
        await tester.ensureVisible(saveProfileButton);
        await tester.tap(saveProfileButton);
        await tester.pumpAndSettle();

        final savedProfile = prefs.getTeacherProfile();
        expect(savedProfile.name, 'Ir. Hendra Wijaya');
        expect(savedProfile.nip, '198003142009021001');
        expect(savedProfile.schoolName, 'SMK Negeri 2 Surabaya');
        expect(
          savedProfile.aiEndpointUrl,
          'https://sik3.example.vercel.app/api/verify-apd',
        );

        // Open Add Class sheet.
        final addClassButton = find.byKey(
          const ValueKey<String>('add_class_button'),
        );
        await tester.ensureVisible(addClassButton);
        await tester.tap(addClassButton);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('class_name_field')),
          'XII TITL 2',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('homeroom_teacher_field')),
          'Dra. Ratna Dewi',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('homeroom_nip_field')),
          '197511202003122004',
        );

        final saveClassButton = find.byKey(
          const ValueKey<String>('class_form_save_button'),
        );
        await tester.ensureVisible(saveClassButton);
        await tester.tap(saveClassButton);
        await tester.pumpAndSettle();

        expect(find.text('XII TITL 2'), findsWidgets);
        expect(find.textContaining('Dra. Ratna Dewi'), findsWidgets);
        expect(savedClasses, hasLength(1));
        expect(savedClasses.first.name, 'XII TITL 2');
        expect(savedClasses.first.homeroomTeacher, 'Dra. Ratna Dewi');
        expect(savedClasses.first.homeroomNip, '197511202003122004');

        // Start session and verify InspectionSession payload.
        final startButton = find.byKey(
          const ValueKey<String>('start_session_button'),
        );
        await tester.ensureVisible(startButton);
        await tester.tap(startButton);
        await tester.pumpAndSettle();

        expect(startedSession, isNotNull);
        expect(startedSession!.teacherName, 'Ir. Hendra Wijaya');
        expect(startedSession!.homeroomTeacher, 'Dra. Ratna Dewi');
        expect(startedSession!.schoolName, 'SMK Negeri 2 Surabaya');

        // Edit class name & verify updated list.
        await tester.tap(find.byKey(const ValueKey<String>('edit_class_1')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('class_name_field')),
          'XII TITL 2B',
        );
        final updateButton = find.byKey(
          const ValueKey<String>('class_form_save_button'),
        );
        await tester.ensureVisible(updateButton);
        await tester.tap(updateButton);
        await tester.pumpAndSettle();
        expect(find.text('XII TITL 2B'), findsWidgets);

        // Delete class via confirmation dialog.
        await tester.tap(find.byKey(const ValueKey<String>('delete_class_1')));
        await tester.pumpAndSettle();
        expect(find.text('Hapus Kelas?'), findsOneWidget);
        await tester.tap(find.text('Hapus'));
        await tester.pumpAndSettle();
        expect(find.text('XII TITL 2B'), findsNothing);
      },
    );

    testWidgets(
      'renders cleanly on narrow 360px screen with 1.3x font scale and tabular figures',
      (tester) async {
        final prefs = await LocalPrefs.open();
        await prefs.saveTeacherProfile(
          const TeacherProfile(
            name: 'Budi Hartono',
            nip: '198001012010011001',
            schoolName: 'SMK Vokasi',
          ),
        );

        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: MaterialApp(
              theme: buildSik3Theme(),
              home: ClassSetupScreen(
                prefs: prefs,
                onSwitchRole: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final countText = tester.widget<Text>(find.text('6/6 Wajib'));
        expect(
          countText.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      },
    );

    testWidgets(
      'rapid double APD toggle ignores stale saveClass response when first resolves after second',
      (tester) async {
        final prefs = await LocalPrefs.open();
        final completers = <Completer<SchoolClass>>[];
        final payloads = <SchoolClass>[];

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ClassSetupScreen(
              prefs: prefs,
              onSwitchRole: () {},
              loadClasses: () async => <SchoolClass>[
                SchoolClass(
                  id: 1,
                  name: 'XI TPM 1',
                  homeroomTeacher: 'Pak Budi',
                  requiredApd: ApdItem.values.toSet(),
                ),
              ],
              saveClass: (schoolClass) {
                final completer = Completer<SchoolClass>();
                completers.add(completer);
                payloads.add(schoolClass);
                return completer.future;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('6/6 Wajib'), findsOneWidget);

        // Rapidly toggle two APD items before any save resolves.
        final bajuToggle = find.byKey(
          const ValueKey<String>('apd_toggle_baju_praktik'),
        );
        final helmToggle = find.byKey(
          const ValueKey<String>('apd_toggle_helm'),
        );
        await tester.ensureVisible(bajuToggle);
        await tester.tap(bajuToggle);
        await tester.pump();

        await tester.ensureVisible(helmToggle);
        await tester.tap(helmToggle);
        await tester.pump();

        expect(completers, hasLength(2));
        expect(find.text('4/6 Wajib'), findsOneWidget);

        // Resolve the SECOND call first, then the STALE first call later.
        completers[1].complete(payloads[1]);
        await tester.pumpAndSettle();
        expect(find.text('4/6 Wajib'), findsOneWidget);

        completers[0].complete(payloads[0]);
        await tester.pumpAndSettle();

        // Both toggles must remain preserved (4/6 Wajib, NOT reverted to 5/6 Wajib).
        expect(find.text('4/6 Wajib'), findsOneWidget);
        expect(find.text('4/6 APD'), findsOneWidget);
      },
    );

    testWidgets(
      'handles persistence failures cleanly in APD toggle, save class, and delete class without unhandled errors',
      (tester) async {
        final prefs = await LocalPrefs.open();

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ClassSetupScreen(
              prefs: prefs,
              onSwitchRole: () {},
              loadClasses: () async => <SchoolClass>[
                SchoolClass(
                  id: 1,
                  name: 'XI TKR 1',
                  homeroomTeacher: 'Pak Joko',
                  requiredApd: ApdItem.values.toSet(),
                ),
              ],
              saveClass: (_) async {
                throw Exception('SQLite write failed');
              },
              deleteClass: (_) async {
                throw Exception('SQLite delete failed');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. APD toggle failure rolls back optimistic state & shows SnackBar.
        final bajuToggle = find.byKey(
          const ValueKey<String>('apd_toggle_baju_praktik'),
        );
        await tester.ensureVisible(bajuToggle);
        await tester.tap(bajuToggle);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('6/6 Wajib'), findsOneWidget);
        expect(
          find.text('Gagal menyimpan perubahan APD wajib. Perubahan dibatalkan.'),
          findsOneWidget,
        );

        // 2. Save new class failure keeps list unchanged & shows SnackBar.
        final addClassButton = find.byKey(
          const ValueKey<String>('add_class_button'),
        );
        await tester.ensureVisible(addClassButton);
        await tester.tap(addClassButton);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('class_name_field')),
          'XII GAGAL',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('homeroom_teacher_field')),
          'Bu Sari',
        );
        final saveClassButton = find.byKey(
          const ValueKey<String>('class_form_save_button'),
        );
        await tester.ensureVisible(saveClassButton);
        await tester.tap(saveClassButton);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('XII GAGAL'), findsNothing);
        expect(
          find.text('Gagal menyimpan data kelas. Silakan coba lagi.'),
          findsOneWidget,
        );

        // 3. Delete class failure keeps class intact & shows SnackBar.
        final deleteButton = find.byKey(const ValueKey<String>('delete_class_1'));
        await tester.ensureVisible(deleteButton);
        await tester.tap(deleteButton);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Hapus'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('XI TKR 1'), findsWidgets);
        expect(
          find.text('Gagal menghapus kelas. Silakan coba lagi.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'rejects empty-host AI endpoint URLs like https:// and http:///path in teacher profile sheet',
      (tester) async {
        final prefs = await LocalPrefs.open();

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ClassSetupScreen(
              prefs: prefs,
              onSwitchRole: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('teacher_profile_settings_button')),
        );
        await tester.pumpAndSettle();

        final urlField = find.byKey(
          const ValueKey<String>('teacher_profile_ai_url_field'),
        );
        final saveButton = find.byKey(
          const ValueKey<String>('teacher_profile_save_button'),
        );

        for (final invalidUrl in const <String>['https://', 'http:///path']) {
          await tester.enterText(urlField, invalidUrl);
          await tester.ensureVisible(saveButton);
          await tester.tap(saveButton);
          await tester.pumpAndSettle();

          expect(
            find.text('URL harus diawali http:// atau https:// yang valid.'),
            findsOneWidget,
          );
          expect(find.text('Profil Guru & Pengaturan AI'), findsOneWidget);
          expect(prefs.getTeacherProfile().aiEndpointUrl, isEmpty);
        }
      },
    );
  });

  group('QrScanScreen & manual fallback sheet', () {
    testWidgets(
      'showManualStudentInputSheet validates inline and returns a valid StudentIdentity',
      (tester) async {
        StudentIdentity? result;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showManualStudentInputSheet(
                        context,
                        defaultClassName: 'XI TKR 1',
                      );
                    },
                    child: const Text('Buka Input Manual'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka Input Manual'));
        await tester.pumpAndSettle();

        // Class field pre-filled with defaultClassName.
        final classField = tester.widget<TextFormField>(
          find.byKey(const ValueKey<String>('manual_student_class_field')),
        );
        expect(classField.controller?.text, 'XI TKR 1');

        // Empty submit shows inline validation errors.
        final submitButton = find.byKey(
          const ValueKey<String>('manual_student_submit_button'),
        );
        await tester.ensureVisible(submitButton);
        await tester.tap(submitButton);
        await tester.pumpAndSettle();

        expect(find.text('Nama lengkap wajib diisi.'), findsOneWidget);
        expect(find.text('NISN wajib diisi.'), findsOneWidget);
        expect(find.text('No. Presensi wajib diisi.'), findsOneWidget);
        expect(find.text('Jurusan wajib diisi.'), findsOneWidget);
        expect(result, isNull);

        // Fill valid data and submit.
        await tester.enterText(
          find.byKey(const ValueKey<String>('manual_student_name_field')),
          'Bagas Pratama',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('manual_student_nisn_field')),
          '0087654321',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('manual_student_absen_field')),
          '14',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('manual_student_major_field')),
          'Teknik Kendaraan Ringan',
        );

        await tester.ensureVisible(submitButton);
        await tester.tap(submitButton);
        await tester.pumpAndSettle();

        expect(
          result,
          equals(
            const StudentIdentity(
              nisn: '0087654321',
              attendanceNo: '14',
              name: 'Bagas Pratama',
              className: 'XI TKR 1',
              major: 'Teknik Kendaraan Ringan',
            ),
          ),
        );
      },
    );

    testWidgets(
      'QrScanScreen shows dark surface, cooldown snackbar on invalid QR, manual fallback, and pops valid QR identity',
      (tester) async {
        late void Function(String raw) triggerScan;
        var currentTime = DateTime(2026, 11, 24, 8, 0, 0);
        StudentIdentity? scannedStudent;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      scannedStudent = await Navigator.of(context)
                          .push<StudentIdentity>(
                            MaterialPageRoute<StudentIdentity>(
                              builder: (_) => QrScanScreen(
                                defaultClassName: 'XI TPM 1',
                                clock: () => currentTime,
                                scannerBuilder: (ctx, onRawPayload) {
                                  triggerScan = onRawPayload;
                                  return const ColoredBox(
                                    color: Sik3Colors.scannerDark,
                                  );
                                },
                              ),
                            ),
                          );
                    },
                    child: const Text('Buka Scanner'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka Scanner'));
        await tester.pumpAndSettle();

        // Check dark scaffold background & 48dp+ manual fallback button.
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
        expect(scaffold.backgroundColor, Sik3Colors.scannerDark);

        final manualButton = find.byKey(
          const ValueKey<String>('qr_manual_fallback_button'),
        );
        expect(manualButton, findsOneWidget);
        expect(find.text('Siswa Lupa HP? Input Manual'), findsOneWidget);
        expect(tester.getSize(manualButton).height, greaterThanOrEqualTo(48.0));

        // Non-SiK3 QR triggers non-blocking snackbar.
        triggerScan('https://example.com/not-sik3');
        await tester.pump();
        expect(find.text('QR bukan format identitas SiK3.'), findsOneWidget);

        // Within 2s cooldown, another malformed QR is throttled without replacing error immediately.
        currentTime = currentTime.add(const Duration(milliseconds: 500));
        triggerScan('{"v":99}');
        await tester.pump();
        expect(
          find.text('Versi QR SiK3 (99) tidak didukung aplikasi ini.'),
          findsNothing,
        );

        // After 2s cooldown, new invalid QR displays its message.
        currentTime = currentTime.add(const Duration(seconds: 2));
        triggerScan('{"v":99}');
        await tester.pump();
        expect(
          find.text('Versi QR SiK3 (99) tidak didukung aplikasi ini.'),
          findsOneWidget,
        );

        // Valid SiK3 QR payload pops with decoded StudentIdentity.
        const expectedStudent = StudentIdentity(
          nisn: '0081122334',
          attendanceNo: '03',
          name: 'Dewi Lestari',
          className: 'XI TPM 1',
          major: 'Teknik Pemesinan',
        );
        triggerScan(QrIdentityCodec.encode(expectedStudent));
        await tester.pumpAndSettle();

        expect(scannedStudent, equals(expectedStudent));
      },
    );

    testWidgets(
      'QrScanScreen manual fallback button submits and pops StudentIdentity end-to-end',
      (tester) async {
        StudentIdentity? returnedStudent;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      returnedStudent = await Navigator.of(context)
                          .push<StudentIdentity>(
                            MaterialPageRoute<StudentIdentity>(
                              builder: (_) => QrScanScreen(
                                defaultClassName: 'X TKR 2',
                                scannerBuilder: (ctx, onRawPayload) =>
                                    const ColoredBox(
                                      color: Sik3Colors.scannerDark,
                                    ),
                              ),
                            ),
                          );
                    },
                    child: const Text('Buka Scanner'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka Scanner'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('qr_manual_fallback_button')),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('manual_student_name_field')),
          'Andi Wijaya',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('manual_student_nisn_field')),
          '0091234567',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('manual_student_absen_field')),
          '02',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('manual_student_major_field')),
          'Teknik Kendaraan Ringan',
        );

        final submitButton = find.byKey(
          const ValueKey<String>('manual_student_submit_button'),
        );
        await tester.ensureVisible(submitButton);
        await tester.tap(submitButton);
        await tester.pumpAndSettle();

        expect(
          returnedStudent,
          equals(
            const StudentIdentity(
              nisn: '0091234567',
              attendanceNo: '02',
              name: 'Andi Wijaya',
              className: 'X TKR 2',
              major: 'Teknik Kendaraan Ringan',
            ),
          ),
        );
      },
    );
  });
}

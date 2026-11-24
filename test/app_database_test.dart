import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/core/models/inspection_models.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/data/app_database.dart';
import 'package:sik3/data/local_prefs.dart';
import 'package:sik3/features/teacher/class_setup_screen.dart';
import 'package:sik3/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<AppDatabase> openMemoryDb({DatabaseFactory? factory}) {
    return AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: factory ?? databaseFactoryFfi,
    );
  }

  group('AppDatabase schema & CRUD', () {
    test('schema_has_exactly_three_user_tables', () async {
      final db = await openMemoryDb();
      addTearDown(db.close);

      final tableRows = await db.rawDatabase.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      final tableNames = tableRows
          .map((row) => row['name'] as String)
          .toList(growable: false);
      expect(
        tableNames,
        equals(const <String>['classes', 'inspection_sessions', 'scan_records']),
      );

      final fkRows = await db.rawDatabase.rawQuery('PRAGMA foreign_keys');
      expect(fkRows.single.values.first, 1);
    });

    test('upsertClass_and_getClasses_round_trip', () async {
      final db = await openMemoryDb();
      addTearDown(db.close);

      final insertedId = await db.upsertClass(
        const SchoolClass(
          name: 'XI TPM 1',
          homeroomTeacher: 'Drs. Budi Santoso',
          homeroomNip: '197801012005011002',
          requiredApd: <ApdItem>{
            ApdItem.bajuPraktik,
            ApdItem.kacamata,
            ApdItem.sepatuBengkel,
          },
        ),
      );
      expect(insertedId, greaterThan(0));

      final initialClasses = await db.getClasses();
      expect(initialClasses, hasLength(1));
      expect(
        initialClasses.single,
        equals(
          SchoolClass(
            id: insertedId,
            name: 'XI TPM 1',
            homeroomTeacher: 'Drs. Budi Santoso',
            homeroomNip: '197801012005011002',
            requiredApd: const <ApdItem>{
              ApdItem.bajuPraktik,
              ApdItem.kacamata,
              ApdItem.sepatuBengkel,
            },
          ),
        ),
      );

      // Creating a session first ensures updating the class does NOT cascade-delete child sessions.
      final sessionId = await db.createSession(
        InspectionSession(
          classId: insertedId,
          subjectName: 'Teknik Pemesinan Bubut',
          teacherName: 'Siti Aminah, S.Pd',
          teacherNip: '198505122010012008',
          homeroomTeacher: 'Drs. Budi Santoso',
          homeroomNip: '197801012005011002',
          schoolName: 'SMK Negeri 1',
          sessionDate: DateTime(2026, 11, 24, 7, 30),
          requiredApd: const <ApdItem>{
            ApdItem.bajuPraktik,
            ApdItem.kacamata,
            ApdItem.sepatuBengkel,
          },
        ),
      );

      final updatedId = await db.upsertClass(
        initialClasses.single.copyWith(
          name: 'XI TPM 1A',
          homeroomNip: '197801012005011999',
          requiredApd: const <ApdItem>{ApdItem.bajuPraktik, ApdItem.helm},
        ),
      );
      expect(updatedId, insertedId);

      final updatedClasses = await db.getClasses();
      expect(updatedClasses, hasLength(1));
      expect(updatedClasses.single.name, 'XI TPM 1A');
      expect(updatedClasses.single.homeroomNip, '197801012005011999');
      expect(
        updatedClasses.single.requiredApd,
        equals(const <ApdItem>{ApdItem.bajuPraktik, ApdItem.helm}),
      );

      final survivingSession = await db.getSession(sessionId);
      expect(survivingSession, isNotNull);
      expect(survivingSession!.subjectName, 'Teknik Pemesinan Bubut');
    });

    test('createSession, getSessionsForClass, getSession, and updateSessionStatus round-trip', () async {
      final db = await openMemoryDb();
      addTearDown(db.close);

      final classId = await db.upsertClass(
        const SchoolClass(
          name: 'XII TKR 2',
          homeroomTeacher: 'Pak Joko',
          requiredApd: <ApdItem>{ApdItem.bajuPraktik, ApdItem.sepatuBengkel},
        ),
      );

      final sessionDate = DateTime(2026, 11, 24, 8, 15, 30);
      final sessionId = await db.createSession(
        InspectionSession(
          classId: classId,
          subjectName: 'Perawatan Sasis',
          teacherName: 'Ir. Hendra',
          teacherNip: '198001012005011001',
          homeroomTeacher: 'Pak Joko',
          homeroomNip: '197702022004011002',
          schoolName: 'SMK Vokasi Surabaya',
          sessionDate: sessionDate,
          requiredApd: const <ApdItem>{
            ApdItem.bajuPraktik,
            ApdItem.sepatuBengkel,
          },
        ),
      );

      final loaded = await db.getSession(sessionId);
      expect(
        loaded,
        equals(
          InspectionSession(
            id: sessionId,
            classId: classId,
            subjectName: 'Perawatan Sasis',
            teacherName: 'Ir. Hendra',
            teacherNip: '198001012005011001',
            homeroomTeacher: 'Pak Joko',
            homeroomNip: '197702022004011002',
            schoolName: 'SMK Vokasi Surabaya',
            sessionDate: sessionDate,
            requiredApd: const <ApdItem>{
              ApdItem.bajuPraktik,
              ApdItem.sepatuBengkel,
            },
            status: 'draft',
          ),
        ),
      );

      await db.updateSessionStatus(sessionId, 'exported');
      final afterUpdate = await db.getSession(sessionId);
      expect(afterUpdate?.status, 'exported');

      final sessions = await db.getSessionsForClass(classId);
      expect(sessions, hasLength(1));
      expect(sessions.single.status, 'exported');

      expect(await db.getSession(99999), isNull);
    });

    test('upsertScanRecord_replaces_duplicate_student_in_same_session', () async {
      final db = await openMemoryDb();
      addTearDown(db.close);

      final tempDir = await Directory.systemTemp.createTemp('sik3_upsert_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final upperV1 = File(p.join(tempDir.path, 'upper_v1.jpg'))
        ..writeAsBytesSync(<int>[1, 2, 3]);
      final lowerShared = File(p.join(tempDir.path, 'lower_shared.jpg'))
        ..writeAsBytesSync(<int>[4, 5, 6]);
      final upperV2 = File(p.join(tempDir.path, 'upper_v2.jpg'))
        ..writeAsBytesSync(<int>[7, 8, 9]);

      final classId = await db.upsertClass(
        const SchoolClass(
          name: 'XI TPM 1',
          homeroomTeacher: 'Pak Budi',
          requiredApd: <ApdItem>{ApdItem.helm, ApdItem.sepatuBengkel},
        ),
      );
      final session1 = await db.createSession(
        InspectionSession(
          classId: classId,
          subjectName: 'Bubut',
          teacherName: 'Bu Sari',
          homeroomTeacher: 'Pak Budi',
          sessionDate: DateTime(2026, 11, 24, 8, 0),
          requiredApd: const <ApdItem>{ApdItem.helm, ApdItem.sepatuBengkel},
        ),
      );
      final session2 = await db.createSession(
        InspectionSession(
          classId: classId,
          subjectName: 'Frais',
          teacherName: 'Bu Sari',
          homeroomTeacher: 'Pak Budi',
          sessionDate: DateTime(2026, 11, 24, 10, 0),
          requiredApd: const <ApdItem>{ApdItem.helm, ApdItem.sepatuBengkel},
        ),
      );

      final firstId = await db.upsertScanRecord(
        ScanRecord(
          sessionId: session1,
          nisn: '0081234567',
          attendanceNo: '05',
          studentName: 'Ahmad Fauzi',
          apdResults: const <ApdItem, ApdCheckResult>{
            ApdItem.helm: ApdCheckResult(
              item: ApdItem.helm,
              status: ApdStatus.missing,
              confidence: 0.42,
            ),
            ApdItem.sepatuBengkel: ApdCheckResult(
              item: ApdItem.sepatuBengkel,
              status: ApdStatus.detected,
              confidence: 0.88,
            ),
          },
          upperPhotoPath: upperV1.path,
          lowerPhotoPath: lowerShared.path,
          scannedAt: DateTime(2026, 11, 24, 8, 5),
        ),
      );

      final secondId = await db.upsertScanRecord(
        ScanRecord(
          sessionId: session1,
          nisn: '0081234567',
          attendanceNo: '05',
          studentName: 'Ahmad Fauzi',
          apdResults: const <ApdItem, ApdCheckResult>{
            ApdItem.helm: ApdCheckResult(
              item: ApdItem.helm,
              status: ApdStatus.detected,
              confidence: 0.93,
              manualOverride: true,
              note: 'Sudah memakai helm',
            ),
            ApdItem.sepatuBengkel: ApdCheckResult(
              item: ApdItem.sepatuBengkel,
              status: ApdStatus.detected,
              confidence: 0.91,
            ),
          },
          upperPhotoPath: upperV2.path,
          lowerPhotoPath: lowerShared.path,
          isManualOverride: true,
          isAiVerified: true,
          scannedAt: DateTime(2026, 11, 24, 8, 7),
        ),
      );

      // Same row replaced cleanly in-place without duplication.
      expect(secondId, firstId);
      final records = await db.getSessionRecords(session1);
      expect(records, hasLength(1));
      expect(records.single.id, firstId);
      expect(records.single.apdResults[ApdItem.helm]?.status, ApdStatus.detected);
      expect(records.single.apdResults[ApdItem.helm]?.note, 'Sudah memakai helm');
      expect(records.single.isManualOverride, isTrue);
      expect(records.single.isAiVerified, isTrue);
      expect(records.single.upperPhotoPath, upperV2.path);
      expect(records.single.lowerPhotoPath, lowerShared.path);

      // Superseded upperV1 deleted; unchanged lowerShared & new upperV2 kept.
      expect(upperV1.existsSync(), isFalse);
      expect(lowerShared.existsSync(), isTrue);
      expect(upperV2.existsSync(), isTrue);

      // Same NISN in a different session is stored independently.
      final otherSessionRecordId = await db.upsertScanRecord(
        ScanRecord(
          sessionId: session2,
          nisn: '0081234567',
          attendanceNo: '05',
          studentName: 'Ahmad Fauzi',
          apdResults: const <ApdItem, ApdCheckResult>{},
          scannedAt: DateTime(2026, 11, 24, 10, 5),
        ),
      );
      expect(otherSessionRecordId, isNot(firstId));
      expect(await db.getSessionRecords(session2), hasLength(1));
      expect(await db.getSessionRecords(session1), hasLength(1));
    });

    test('getSessionRecords_sorts_by_numeric_attendance_number', () async {
      final db = await openMemoryDb();
      addTearDown(db.close);

      final classId = await db.upsertClass(
        const SchoolClass(
          name: 'XI TITL 1',
          homeroomTeacher: 'Pak Eko',
          requiredApd: <ApdItem>{ApdItem.helm},
        ),
      );
      final sessionId = await db.createSession(
        InspectionSession(
          classId: classId,
          subjectName: 'Instalasi Listrik',
          teacherName: 'Bu Rina',
          homeroomTeacher: 'Pak Eko',
          sessionDate: DateTime(2026, 11, 24, 9, 0),
          requiredApd: const <ApdItem>{ApdItem.helm},
        ),
      );

      final entries = <(String nisn, String absen, String name)>[
        ('0010', '10', 'Dedi'),
        ('0002b', '02', 'Zaki'),
        ('0001', '1', 'Budi'),
        ('00a2', 'a2', 'Rani'),
        ('00b1', 'B1', 'Fajar'),
        ('0002a', '02', 'Andi'),
      ];

      for (final entry in entries) {
        await db.upsertScanRecord(
          ScanRecord(
            sessionId: sessionId,
            nisn: entry.$1,
            attendanceNo: entry.$2,
            studentName: entry.$3,
            apdResults: const <ApdItem, ApdCheckResult>{
              ApdItem.helm: ApdCheckResult(
                item: ApdItem.helm,
                status: ApdStatus.detected,
              ),
            },
            scannedAt: DateTime(2026, 11, 24, 9, 1),
          ),
        );
      }

      final sorted = await db.getSessionRecords(sessionId);
      expect(
        sorted.map((r) => '${r.attendanceNo}:${r.studentName}').toList(),
        equals(const <String>[
          '1:Budi',
          '02:Andi',
          '02:Zaki',
          '10:Dedi',
          'a2:Rani',
          'B1:Fajar',
        ]),
      );
    });

    test(
      'purgeSessionPhotos_deletes_disk_files_and_clears_photo_paths_without_deleting_checklist_data',
      () async {
        final db = await openMemoryDb();
        addTearDown(db.close);

        final tempDir = await Directory.systemTemp.createTemp('sik3_purge_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final s1Upper1 = File(p.join(tempDir.path, 's1_u1.jpg'))
          ..writeAsBytesSync(<int>[10, 20]);
        final s1Lower1 = File(p.join(tempDir.path, 's1_l1.jpg'))
          ..writeAsBytesSync(<int>[30, 40]);
        final s1Upper2 = File(p.join(tempDir.path, 's1_u2.jpg'))
          ..writeAsBytesSync(<int>[50, 60]);
        final s2Upper = File(p.join(tempDir.path, 's2_u1.jpg'))
          ..writeAsBytesSync(<int>[70, 80]);

        final classId = await db.upsertClass(
          const SchoolClass(
            name: 'X TKR 1',
            homeroomTeacher: 'Pak Teguh',
            requiredApd: <ApdItem>{ApdItem.bajuPraktik, ApdItem.sepatuBengkel},
          ),
        );
        final session1 = await db.createSession(
          InspectionSession(
            classId: classId,
            subjectName: 'Dasar Otomotif',
            teacherName: 'Pak Teguh',
            homeroomTeacher: 'Pak Teguh',
            sessionDate: DateTime(2026, 11, 24, 7, 0),
            requiredApd: const <ApdItem>{
              ApdItem.bajuPraktik,
              ApdItem.sepatuBengkel,
            },
          ),
        );
        final session2 = await db.createSession(
          InspectionSession(
            classId: classId,
            subjectName: 'Kelistrikan',
            teacherName: 'Pak Teguh',
            homeroomTeacher: 'Pak Teguh',
            sessionDate: DateTime(2026, 11, 24, 11, 0),
            requiredApd: const <ApdItem>{
              ApdItem.bajuPraktik,
              ApdItem.sepatuBengkel,
            },
          ),
        );

        const expectedResults = <ApdItem, ApdCheckResult>{
          ApdItem.bajuPraktik: ApdCheckResult(
            item: ApdItem.bajuPraktik,
            status: ApdStatus.detected,
            confidence: 0.94,
          ),
          ApdItem.sepatuBengkel: ApdCheckResult(
            item: ApdItem.sepatuBengkel,
            status: ApdStatus.needsReview,
            confidence: 0.55,
          ),
        };

        await db.upsertScanRecord(
          ScanRecord(
            sessionId: session1,
            nisn: '008001',
            attendanceNo: '01',
            studentName: 'Citra Ayu',
            apdResults: expectedResults,
            upperPhotoPath: s1Upper1.path,
            lowerPhotoPath: s1Lower1.path,
            scannedAt: DateTime(2026, 11, 24, 7, 5),
          ),
        );
        await db.upsertScanRecord(
          ScanRecord(
            sessionId: session1,
            nisn: '008002',
            attendanceNo: '02',
            studentName: 'Dimas Putra',
            apdResults: expectedResults,
            upperPhotoPath: s1Upper2.path,
            scannedAt: DateTime(2026, 11, 24, 7, 6),
          ),
        );
        await db.upsertScanRecord(
          ScanRecord(
            sessionId: session2,
            nisn: '008001',
            attendanceNo: '01',
            studentName: 'Citra Ayu',
            apdResults: expectedResults,
            upperPhotoPath: s2Upper.path,
            scannedAt: DateTime(2026, 11, 24, 11, 5),
          ),
        );

        final purgedCount = await db.purgeSessionPhotos(session1);
        expect(purgedCount, 3);

        // Session 1 photos deleted from disk, Session 2 untouched.
        expect(s1Upper1.existsSync(), isFalse);
        expect(s1Lower1.existsSync(), isFalse);
        expect(s1Upper2.existsSync(), isFalse);
        expect(s2Upper.existsSync(), isTrue);

        // Session 1 DB rows preserved with null paths and intact APD results.
        final remainingRecords = await db.getSessionRecords(session1);
        expect(remainingRecords, hasLength(2));
        for (final record in remainingRecords) {
          expect(record.upperPhotoPath, isNull);
          expect(record.lowerPhotoPath, isNull);
          expect(record.apdResults, equals(expectedResults));
        }
      },
    );

    test('deleteScanRecord, deleteSession, and deleteClass clean disk photos and cascade rows', () async {
      final db = await openMemoryDb();
      addTearDown(db.close);

      final tempDir = await Directory.systemTemp.createTemp('sik3_delete_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final r1Photo = File(p.join(tempDir.path, 'r1.jpg'))
        ..writeAsBytesSync(<int>[1]);
      final r2Photo = File(p.join(tempDir.path, 'r2.jpg'))
        ..writeAsBytesSync(<int>[2]);
      final r3Photo = File(p.join(tempDir.path, 'r3.jpg'))
        ..writeAsBytesSync(<int>[3]);

      final classId = await db.upsertClass(
        const SchoolClass(
          name: 'XI TP 1',
          homeroomTeacher: 'Pak Wawan',
          requiredApd: <ApdItem>{ApdItem.helm},
        ),
      );
      final sessionA = await db.createSession(
        InspectionSession(
          classId: classId,
          subjectName: 'Las',
          teacherName: 'Pak Wawan',
          homeroomTeacher: 'Pak Wawan',
          sessionDate: DateTime(2026, 11, 24, 7, 0),
          requiredApd: const <ApdItem>{ApdItem.helm},
        ),
      );
      final sessionB = await db.createSession(
        InspectionSession(
          classId: classId,
          subjectName: 'Gerinda',
          teacherName: 'Pak Wawan',
          homeroomTeacher: 'Pak Wawan',
          sessionDate: DateTime(2026, 11, 24, 9, 0),
          requiredApd: const <ApdItem>{ApdItem.helm},
        ),
      );

      final r1Id = await db.upsertScanRecord(
        ScanRecord(
          sessionId: sessionA,
          nisn: '1001',
          attendanceNo: '1',
          studentName: 'Siswa Satu',
          apdResults: const <ApdItem, ApdCheckResult>{},
          upperPhotoPath: r1Photo.path,
          scannedAt: DateTime(2026, 11, 24, 7, 5),
        ),
      );
      await db.upsertScanRecord(
        ScanRecord(
          sessionId: sessionA,
          nisn: '1002',
          attendanceNo: '2',
          studentName: 'Siswa Dua',
          apdResults: const <ApdItem, ApdCheckResult>{},
          upperPhotoPath: r2Photo.path,
          scannedAt: DateTime(2026, 11, 24, 7, 6),
        ),
      );
      await db.upsertScanRecord(
        ScanRecord(
          sessionId: sessionB,
          nisn: '1003',
          attendanceNo: '3',
          studentName: 'Siswa Tiga',
          apdResults: const <ApdItem, ApdCheckResult>{},
          lowerPhotoPath: r3Photo.path,
          scannedAt: DateTime(2026, 11, 24, 9, 5),
        ),
      );

      // 1. deleteScanRecord removes row & deletes r1.jpg only.
      await db.deleteScanRecord(r1Id);
      expect(r1Photo.existsSync(), isFalse);
      expect(r2Photo.existsSync(), isTrue);
      expect(await db.getSessionRecords(sessionA), hasLength(1));

      // 2. deleteSession purges r2.jpg and cascades sessionA's remaining record.
      await db.deleteSession(sessionA);
      expect(r2Photo.existsSync(), isFalse);
      expect(await db.getSession(sessionA), isNull);
      expect(await db.getSessionRecords(sessionA), isEmpty);
      expect(r3Photo.existsSync(), isTrue);

      // 3. deleteClass purges r3.jpg and cascades sessionB + its records.
      await db.deleteClass(classId);
      expect(r3Photo.existsSync(), isFalse);
      expect(await db.getClasses(), isEmpty);
      expect(await db.getSession(sessionB), isNull);
      expect(await db.getSessionRecords(sessionB), isEmpty);
    });
  });

  group('AppDatabase integration with ClassSetupScreen & Sik3App', () {
    testWidgets(
      'ClassSetupScreen persists classes, APD presets, draft sessions, and deletions in AppDatabase',
      (tester) async {
        final prefs = await LocalPrefs.open();
        final db = await openMemoryDb(factory: databaseFactoryFfiNoIsolate);
        addTearDown(db.close);

        InspectionSession? startedSession;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildSik3Theme(),
            home: ClassSetupScreen(
              prefs: prefs,
              database: db,
              onSwitchRole: () {},
              onStartSession: (context, schoolClass, sessionDraft) async {
                startedSession = sessionDraft;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Add class through UI and verify it writes to SQLite.
        await tester.tap(find.byKey(const ValueKey<String>('add_class_button')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('class_name_field')),
          'XI TKR 3',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('homeroom_teacher_field')),
          'Pak Suryadi',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('homeroom_nip_field')),
          '197905052006041009',
        );
        final saveClassButton = find.byKey(
          const ValueKey<String>('class_form_save_button'),
        );
        await tester.ensureVisible(saveClassButton);
        await tester.tap(saveClassButton);
        await tester.pumpAndSettle();

        final storedClasses = await db.getClasses();
        expect(storedClasses, hasLength(1));
        expect(storedClasses.single.name, 'XI TKR 3');

        // Toggle masker off and confirm it persists to SQLite.
        final maskerToggle = find.byKey(
          const ValueKey<String>('apd_toggle_masker'),
        );
        await tester.ensureVisible(maskerToggle);
        await tester.tap(maskerToggle);
        await tester.pumpAndSettle();

        final afterToggle = await db.getClasses();
        expect(afterToggle.single.requiredApd.contains(ApdItem.masker), isFalse);
        expect(afterToggle.single.requiredApd.length, 5);

        // Start session and verify InspectionSession is created in AppDatabase.
        await tester.enterText(
          find.byKey(const ValueKey<String>('session_subject_field')),
          'Tune Up Engine',
        );
        final startButton = find.byKey(
          const ValueKey<String>('start_session_button'),
        );
        await tester.ensureVisible(startButton);
        await tester.tap(startButton);
        await tester.pumpAndSettle();

        expect(startedSession, isNotNull);
        expect(startedSession!.id, isNotNull);
        expect(startedSession!.subjectName, 'Tune Up Engine');
        final sessionsInDb = await db.getSessionsForClass(storedClasses.single.id!);
        expect(sessionsInDb, hasLength(1));
        expect(sessionsInDb.single.id, startedSession!.id);

        // Rebuild ClassSetupScreen from scratch with same DB -> loads persisted class.
        await tester.pumpWidget(const SizedBox.shrink());
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

        expect(find.text('XI TKR 3'), findsWidgets);
        expect(find.text('5/6 Wajib'), findsOneWidget);

        // Delete class via UI -> removed from SQLite.
        final deleteBtn = find.byKey(
          ValueKey<String>('delete_class_${storedClasses.single.id}'),
        );
        await tester.ensureVisible(deleteBtn);
        await tester.tap(deleteBtn);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hapus'));
        await tester.pumpAndSettle();

        expect(await db.getClasses(), isEmpty);
      },
    );

    testWidgets('Sik3App passes optional AppDatabase to ClassSetupScreen in teacher role', (
      tester,
    ) async {
      final prefs = await LocalPrefs.open();
      await prefs.setRole(AppRole.teacher);
      final db = await openMemoryDb(factory: databaseFactoryFfiNoIsolate);
      addTearDown(db.close);

      await db.upsertClass(
        const SchoolClass(
          name: 'XII TPM 4',
          homeroomTeacher: 'Bu Endang',
          requiredApd: <ApdItem>{ApdItem.bajuPraktik, ApdItem.sepatuBengkel},
        ),
      );

      await tester.pumpWidget(Sik3App(prefs: prefs, database: db));
      await tester.pumpAndSettle();

      expect(find.byType(ClassSetupScreen), findsOneWidget);
      expect(find.text('XII TPM 4'), findsWidgets);
      expect(find.text('2/6 Wajib'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/data/local_prefs.dart';
import 'package:sik3/data/qr_identity_codec.dart';
import 'package:sik3/features/onboarding/role_gate_screen.dart';
import 'package:sik3/features/student/student_qr_screen.dart';
import 'package:sik3/features/teacher/class_setup_screen.dart';
import 'package:sik3/main.dart';

void main() {
  final emojiRegex = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
    unicode: true,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('RoleGateScreen & Sik3App teacher PIN flow', () {
    testWidgets(
      'first-time Mode Guru creates PIN, routes to teacher home, switches role, and verifies PIN on re-entry',
      (tester) async {
        final prefs = await LocalPrefs.open();

        await tester.pumpWidget(Sik3App(prefs: prefs));
        await tester.pumpAndSettle();

        expect(find.byType(RoleGateScreen), findsOneWidget);
        expect(find.text('Mode Guru'), findsOneWidget);
        expect(find.text('Mode Siswa'), findsOneWidget);

        // Verify 48dp+ touch targets on role cards.
        final teacherCardSize = tester.getSize(
          find.byKey(const ValueKey<String>('role_card_teacher')),
        );
        final studentCardSize = tester.getSize(
          find.byKey(const ValueKey<String>('role_card_student')),
        );
        expect(teacherCardSize.height, greaterThanOrEqualTo(48.0));
        expect(studentCardSize.height, greaterThanOrEqualTo(48.0));

        // Verify zero emoji across all visible text widgets.
        for (final textWidget in tester.widgetList<Text>(find.byType(Text))) {
          expect(emojiRegex.hasMatch(textWidget.data ?? ''), isFalse);
        }

        // Open Mode Guru first-time PIN setup sheet.
        await tester.tap(find.byKey(const ValueKey<String>('role_card_teacher')));
        await tester.pumpAndSettle();

        expect(find.text('Buat PIN Mode Guru'), findsOneWidget);

        // Mismatched confirmation shows inline error.
        await tester.enterText(
          find.byKey(const ValueKey<String>('pin_create_field')),
          '1234',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('pin_confirm_field')),
          '9999',
        );
        await tester.tap(find.byKey(const ValueKey<String>('pin_submit_button')));
        await tester.pumpAndSettle();
        expect(find.text('Konfirmasi PIN tidak sama.'), findsOneWidget);

        // Matching 4-digit PIN unlocks teacher placeholder.
        await tester.enterText(
          find.byKey(const ValueKey<String>('pin_confirm_field')),
          '1234',
        );
        await tester.tap(find.byKey(const ValueKey<String>('pin_submit_button')));
        await tester.pumpAndSettle();

        expect(prefs.hasTeacherPin(), isTrue);
        expect(prefs.getRole(), AppRole.teacher);
        expect(find.byType(ClassSetupScreen), findsOneWidget);

        // Switch role returns to RoleGateScreen.
        await tester.tap(
          find.byKey(const ValueKey<String>('teacher_switch_role_button')),
        );
        await tester.pumpAndSettle();

        expect(prefs.getRole(), isNull);
        expect(find.byType(RoleGateScreen), findsOneWidget);

        // Subsequent Mode Guru prompts verification instead of creation.
        await tester.tap(find.byKey(const ValueKey<String>('role_card_teacher')));
        await tester.pumpAndSettle();
        expect(find.text('Masukkan PIN Mode Guru'), findsOneWidget);

        // Wrong PIN rejected.
        await tester.enterText(
          find.byKey(const ValueKey<String>('pin_verify_field')),
          '0000',
        );
        await tester.tap(find.byKey(const ValueKey<String>('pin_submit_button')));
        await tester.pumpAndSettle();
        expect(
          find.text('PIN salah. Periksa kembali PIN 4-6 digit Anda.'),
          findsOneWidget,
        );
        expect(find.byType(ClassSetupScreen), findsNothing);

        // Correct PIN enters teacher mode.
        await tester.enterText(
          find.byKey(const ValueKey<String>('pin_verify_field')),
          '1234',
        );
        await tester.tap(find.byKey(const ValueKey<String>('pin_submit_button')));
        await tester.pumpAndSettle();
        expect(find.byType(ClassSetupScreen), findsOneWidget);
      },
    );

    testWidgets('supports injected teacherHomeBuilder when role is teacher', (
      tester,
    ) async {
      final prefs = await LocalPrefs.open();
      await prefs.setRole(AppRole.teacher);

      await tester.pumpWidget(
        Sik3App(
          prefs: prefs,
          teacherHomeBuilder: (context, p, onSwitchRole) {
            return const Scaffold(body: Center(child: Text('Custom Teacher Home')));
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom Teacher Home'), findsOneWidget);
      expect(find.byType(ClassSetupScreen), findsNothing);
    });
  });

  group('StudentQrScreen validation & high-contrast QR card', () {
    testWidgets(
      'validates form inline, persists profile, renders QrImageView with tabular IDs, and allows editing',
      (tester) async {
        final prefs = await LocalPrefs.open();

        await tester.pumpWidget(Sik3App(prefs: prefs));
        await tester.pumpAndSettle();

        // Enter Mode Siswa (no PIN required).
        await tester.tap(find.byKey(const ValueKey<String>('role_card_student')));
        await tester.pumpAndSettle();

        expect(find.byType(StudentQrScreen), findsOneWidget);
        expect(find.text('Profil Identitas Siswa'), findsOneWidget);

        // Empty submit triggers inline validation errors.
        final saveButton = find.byKey(
          const ValueKey<String>('student_save_button'),
        );
        await tester.ensureVisible(saveButton);
        await tester.tap(saveButton);
        await tester.pumpAndSettle();

        expect(find.text('Nama lengkap wajib diisi.'), findsOneWidget);
        expect(find.text('NISN wajib diisi.'), findsOneWidget);
        expect(find.text('No. Presensi wajib diisi.'), findsOneWidget);
        expect(find.text('Kelas wajib diisi.'), findsOneWidget);
        expect(find.text('Jurusan wajib diisi.'), findsOneWidget);

        // Non-numeric NISN shows specific inline error.
        await tester.enterText(
          find.byKey(const ValueKey<String>('student_name_field')),
          'Rafi Pratama',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('student_nisn_field')),
          'ABC123',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('student_absen_field')),
          '08',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('student_class_field')),
          'XI TPM 1',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('student_major_field')),
          'Teknik Pemesinan',
        );
        await tester.ensureVisible(saveButton);
        await tester.tap(saveButton);
        await tester.pumpAndSettle();
        expect(find.text('NISN harus berupa angka.'), findsOneWidget);

        // Fix NISN and submit.
        await tester.enterText(
          find.byKey(const ValueKey<String>('student_nisn_field')),
          '0081234567',
        );
        await tester.ensureVisible(saveButton);
        await tester.tap(saveButton);
        await tester.pumpAndSettle();

        // High-contrast QR Identity Card rendered.
        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('Rafi Pratama'), findsOneWidget);
        expect(find.text('0081234567'), findsOneWidget);
        expect(find.text('08'), findsOneWidget);

        final qrWidget = tester.widget<QrImageView>(find.byType(QrImageView));
        expect(qrWidget.errorCorrectionLevel, QrErrorCorrectLevel.M);
        expect(qrWidget.backgroundColor, Colors.white);
        expect(qrWidget.eyeStyle.color, Sik3Colors.textPrimary);
        expect(qrWidget.dataModuleStyle.color, Sik3Colors.textPrimary);

        // Zero emoji on Student QR view.
        for (final textWidget in tester.widgetList<Text>(find.byType(Text))) {
          expect(emojiRegex.hasMatch(textWidget.data ?? ''), isFalse);
        }

        // Tabular figures applied on NISN & No. Presensi displays.
        final nisnText = tester.widget<Text>(find.text('0081234567'));
        final absenText = tester.widget<Text>(find.text('08'));
        expect(
          nisnText.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
        expect(
          absenText.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );

        // Persisted in LocalPrefs & round-trips through QrIdentityCodec.
        final saved = prefs.getStudentProfile();
        expect(saved, isNotNull);
        expect(saved!.nisn, '0081234567');
        expect(saved.attendanceNo, '08');
        expect(
          QrIdentityCodec.decode(QrIdentityCodec.encode(saved)),
          equals(saved),
        );

        // Verify 48dp+ touch targets on Edit Profil & Ganti Peran buttons.
        final editButton = find.byKey(
          const ValueKey<String>('student_edit_profile_button'),
        );
        final switchButton = find.byKey(
          const ValueKey<String>('student_switch_role_button'),
        );
        expect(tester.getSize(editButton).height, greaterThanOrEqualTo(48.0));
        expect(tester.getSize(switchButton).height, greaterThanOrEqualTo(48.0));

        // Edit profile & cancel returns cleanly.
        await tester.ensureVisible(editButton);
        await tester.tap(editButton);
        await tester.pumpAndSettle();
        expect(find.text('Profil Identitas Siswa'), findsOneWidget);

        await tester.ensureVisible(find.text('Batal Edit'));
        await tester.tap(find.text('Batal Edit'));
        await tester.pumpAndSettle();
        expect(find.byType(QrImageView), findsOneWidget);

        // Switch role returns to RoleGateScreen.
        await tester.tap(
          find.byKey(const ValueKey<String>('student_switch_role_button')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RoleGateScreen), findsOneWidget);
      },
    );
  });
}

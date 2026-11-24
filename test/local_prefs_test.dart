import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sik3/data/local_prefs.dart';
import 'package:sik3/data/qr_identity_codec.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('LocalPrefs role persistence', () {
    test('returns null initially and persists teacher/student/null roles', () async {
      final prefs = await LocalPrefs.open();
      expect(prefs.getRole(), isNull);

      await prefs.setRole(AppRole.teacher);
      expect(prefs.getRole(), AppRole.teacher);

      await prefs.setRole(AppRole.student);
      expect(prefs.getRole(), AppRole.student);

      await prefs.setRole(null);
      expect(prefs.getRole(), isNull);
    });
  });

  group('LocalPrefs teacher PIN security', () {
    test('sets and verifies 4-6 digit numeric PIN with salted SHA-256 hash', () async {
      final sp = await SharedPreferences.getInstance();
      final prefs = await LocalPrefs.open(sp);

      expect(prefs.hasTeacherPin(), isFalse);
      expect(prefs.verifyTeacherPin('1234'), isFalse);

      await prefs.setTeacherPin('2580');
      expect(prefs.hasTeacherPin(), isTrue);
      expect(prefs.verifyTeacherPin('2580'), isTrue);
      expect(prefs.verifyTeacherPin('0000'), isFalse);
      expect(prefs.verifyTeacherPin('25801'), isFalse);

      // Ensure raw plaintext PIN is never stored in SharedPreferences.
      for (final key in sp.getKeys()) {
        final value = sp.get(key)?.toString() ?? '';
        expect(value, isNot(contains('2580')));
      }

      // Updating to a 6-digit PIN replaces previous PIN.
      await prefs.setTeacherPin('135790');
      expect(prefs.verifyTeacherPin('2580'), isFalse);
      expect(prefs.verifyTeacherPin('135790'), isTrue);
    });

    test('rejects invalid PIN formats', () async {
      final prefs = await LocalPrefs.open();

      for (final badPin in <String>['', '123', '1234567', '12ab', ' 1234']) {
        await expectLater(
          () => prefs.setTeacherPin(badPin),
          throwsFormatException,
        );
      }
      expect(prefs.hasTeacherPin(), isFalse);
    });
  });

  group('LocalPrefs profile round-trips', () {
    test('student profile round-trips cleanly', () async {
      final prefs = await LocalPrefs.open();
      expect(prefs.getStudentProfile(), isNull);

      const student = StudentIdentity(
        nisn: '0098765432',
        attendanceNo: '07',
        name: 'Siti Aminah',
        className: 'XII TPM 2',
        major: 'Teknik Pemesinan',
      );
      await prefs.saveStudentProfile(student);

      expect(prefs.getStudentProfile(), equals(student));
    });

    test('teacher profile returns empty default initially and round-trips', () async {
      final prefs = await LocalPrefs.open();
      final initial = prefs.getTeacherProfile();
      expect(initial.name, isEmpty);
      expect(initial.nip, isEmpty);
      expect(initial.schoolName, isEmpty);
      expect(initial.aiEndpointUrl, isEmpty);

      const profile = TeacherProfile(
        name: 'Ahmad Fauzi, S.Pd.',
        nip: '198504122010011008',
        schoolName: 'SMKN 1 Industri',
        aiEndpointUrl: 'https://sik3-verify.vercel.app/api/verify-apd',
      );
      await prefs.saveTeacherProfile(profile);

      expect(prefs.getTeacherProfile(), equals(profile));
    });
  });
}

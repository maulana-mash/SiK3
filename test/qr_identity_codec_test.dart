import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sik3/data/qr_identity_codec.dart';

void main() {
  const sampleStudent = StudentIdentity(
    nisn: '0081234567',
    attendanceNo: '12',
    name: 'Budi Santoso',
    className: 'XI TKR 1',
    major: 'Teknik Kendaraan Ringan',
  );

  group('StudentIdentity', () {
    test('supports JSON round-trip and value equality', () {
      final jsonMap = sampleStudent.toJson();
      final decoded = StudentIdentity.fromJson(jsonMap);

      expect(decoded, equals(sampleStudent));
      expect(decoded.hashCode, equals(sampleStudent.hashCode));
    });
  });

  group('QrIdentityCodec', () {
    test('encodes_and_decodes_valid_student_identity', () {
      final raw = QrIdentityCodec.encode(sampleStudent);
      final map = jsonDecode(raw) as Map<String, dynamic>;

      expect(map['v'], 1);
      expect(map['nisn'], sampleStudent.nisn);
      expect(map['absen'], sampleStudent.attendanceNo);
      expect(map['nama'], sampleStudent.name);
      expect(map['kelas'], sampleStudent.className);
      expect(map['jurusan'], sampleStudent.major);
      expect(map['chk'], matches(RegExp(r'^[0-9a-f]{4}$')));

      final decoded = QrIdentityCodec.decode(raw);
      expect(decoded, equals(sampleStudent));
    });

    test('throws_QrFormatException_on_corrupted_checksum', () {
      final raw = QrIdentityCodec.encode(sampleStudent);
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final originalChk = map['chk'] as String;
      final tamperedChk = originalChk == '0000' ? 'ffff' : '0000';
      map['chk'] = tamperedChk;

      expect(
        () => QrIdentityCodec.decode(jsonEncode(map)),
        throwsA(isA<QrFormatException>()),
      );

      // Also verify tampering a field without updating checksum fails.
      final tamperedFieldMap = jsonDecode(raw) as Map<String, dynamic>;
      tamperedFieldMap['absen'] = '99';
      expect(
        () => QrIdentityCodec.decode(jsonEncode(tamperedFieldMap)),
        throwsA(isA<QrFormatException>()),
      );
    });

    test('throws_QrFormatException_on_non_sik3_qr_url', () {
      expect(
        () => QrIdentityCodec.decode('https://example.com/siswa/0081234567'),
        throwsA(isA<QrFormatException>()),
      );
      expect(
        () => QrIdentityCodec.decode('{"hello":"world"}'),
        throwsA(isA<QrFormatException>()),
      );
      expect(
        () => QrIdentityCodec.decode('["not","an","object"]'),
        throwsA(isA<QrFormatException>()),
      );
      expect(
        () => QrIdentityCodec.decode('   '),
        throwsA(isA<QrFormatException>()),
      );
    });

    test('throws_QrFormatException_when_required_fields_blank', () {
      final validChkForBlankName = QrIdentityCodec.computeChecksum(
        v: 1,
        nisn: sampleStudent.nisn,
        absen: sampleStudent.attendanceNo,
        nama: '   ',
        kelas: sampleStudent.className,
        jurusan: sampleStudent.major,
      );

      final blankNamePayload = jsonEncode(<String, dynamic>{
        'v': 1,
        'nisn': sampleStudent.nisn,
        'absen': sampleStudent.attendanceNo,
        'nama': '   ',
        'kelas': sampleStudent.className,
        'jurusan': sampleStudent.major,
        'chk': validChkForBlankName,
      });

      expect(
        () => QrIdentityCodec.decode(blankNamePayload),
        throwsA(isA<QrFormatException>()),
      );

      final missingNisnPayload = jsonEncode(<String, dynamic>{
        'v': 1,
        'nisn': '',
        'absen': sampleStudent.attendanceNo,
        'nama': sampleStudent.name,
        'kelas': sampleStudent.className,
        'jurusan': sampleStudent.major,
        'chk': QrIdentityCodec.computeChecksum(
          v: 1,
          nisn: '',
          absen: sampleStudent.attendanceNo,
          nama: sampleStudent.name,
          kelas: sampleStudent.className,
          jurusan: sampleStudent.major,
        ),
      });

      expect(
        () => QrIdentityCodec.decode(missingNisnPayload),
        throwsA(isA<QrFormatException>()),
      );
    });

    test('throws_QrFormatException_on_unsupported_version', () {
      final chkForV2 = QrIdentityCodec.computeChecksum(
        v: 2,
        nisn: sampleStudent.nisn,
        absen: sampleStudent.attendanceNo,
        nama: sampleStudent.name,
        kelas: sampleStudent.className,
        jurusan: sampleStudent.major,
      );

      final v2Payload = jsonEncode(<String, dynamic>{
        'v': 2,
        'nisn': sampleStudent.nisn,
        'absen': sampleStudent.attendanceNo,
        'nama': sampleStudent.name,
        'kelas': sampleStudent.className,
        'jurusan': sampleStudent.major,
        'chk': chkForV2,
      });

      expect(
        () => QrIdentityCodec.decode(v2Payload),
        throwsA(isA<QrFormatException>()),
      );
    });
  });
}

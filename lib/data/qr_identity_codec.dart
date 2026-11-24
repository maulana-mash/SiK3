import 'dart:convert';

/// Offline student identity persisted locally and encoded into QR payloads.
class StudentIdentity {
  const StudentIdentity({
    required this.nisn,
    required this.attendanceNo,
    required this.name,
    required this.className,
    required this.major,
  });

  final String nisn;
  final String attendanceNo;
  final String name;
  final String className;
  final String major;

  StudentIdentity copyWith({
    String? nisn,
    String? attendanceNo,
    String? name,
    String? className,
    String? major,
  }) {
    return StudentIdentity(
      nisn: nisn ?? this.nisn,
      attendanceNo: attendanceNo ?? this.attendanceNo,
      name: name ?? this.name,
      className: className ?? this.className,
      major: major ?? this.major,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'nisn': nisn,
      'attendance_no': attendanceNo,
      'name': name,
      'class_name': className,
      'major': major,
    };
  }

  factory StudentIdentity.fromJson(Map<String, dynamic> json) {
    String readStr(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is String) return value.trim();
      }
      return '';
    }

    return StudentIdentity(
      nisn: readStr(const <String>['nisn']),
      attendanceNo: readStr(const <String>[
        'attendance_no',
        'attendanceNo',
        'absen',
      ]),
      name: readStr(const <String>['name', 'nama']),
      className: readStr(const <String>['class_name', 'className', 'kelas']),
      major: readStr(const <String>['major', 'jurusan']),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is StudentIdentity &&
            runtimeType == other.runtimeType &&
            nisn == other.nisn &&
            attendanceNo == other.attendanceNo &&
            name == other.name &&
            className == other.className &&
            major == other.major;
  }

  @override
  int get hashCode =>
      Object.hash(nisn, attendanceNo, name, className, major);

  @override
  String toString() {
    return 'StudentIdentity(nisn: $nisn, absen: $attendanceNo, name: $name, '
        'className: $className, major: $major)';
  }
}

/// Controlled exception thrown when a scanned QR payload is not valid SiK3 data.
class QrFormatException implements Exception {
  const QrFormatException(this.message);

  final String message;

  @override
  String toString() => 'QrFormatException: $message';
}

/// Encodes and decodes offline SiK3 student identity QR payloads with CRC16.
abstract final class QrIdentityCodec {
  static const int currentVersion = 1;
  static final RegExp _checksumPattern = RegExp(r'^[0-9a-f]{4}$');

  /// Computes a 4-character lowercase hex CRC16-CCITT checksum.
  static String computeChecksum({
    required int v,
    required String nisn,
    required String absen,
    required String nama,
    required String kelas,
    required String jurusan,
  }) {
    final canonical = jsonEncode(<String, dynamic>{
      'v': v,
      'nisn': nisn,
      'absen': absen,
      'nama': nama,
      'kelas': kelas,
      'jurusan': jurusan,
    });
    final crc = _crc16Ccitt(utf8.encode(canonical));
    return crc.toRadixString(16).padLeft(4, '0').toLowerCase();
  }

  static String encode(StudentIdentity student) {
    final nisn = student.nisn.trim();
    final absen = student.attendanceNo.trim();
    final nama = student.name.trim();
    final kelas = student.className.trim();
    final jurusan = student.major.trim();

    final chk = computeChecksum(
      v: currentVersion,
      nisn: nisn,
      absen: absen,
      nama: nama,
      kelas: kelas,
      jurusan: jurusan,
    );

    return jsonEncode(<String, dynamic>{
      'v': currentVersion,
      'nisn': nisn,
      'absen': absen,
      'nama': nama,
      'kelas': kelas,
      'jurusan': jurusan,
      'chk': chk,
    });
  }

  static StudentIdentity decode(String rawPayload) {
    final trimmed = rawPayload.trim();
    if (trimmed.isEmpty) {
      throw const QrFormatException('Kode QR kosong atau tidak valid.');
    }

    final dynamic parsed;
    try {
      parsed = jsonDecode(trimmed);
    } on FormatException {
      throw const QrFormatException('QR bukan format identitas SiK3.');
    }

    if (parsed is! Map<String, dynamic>) {
      throw const QrFormatException('Format QR SiK3 harus berupa objek JSON.');
    }

    final version = parsed['v'];
    if (version is! int) {
      throw const QrFormatException('Versi payload QR SiK3 tidak valid.');
    }
    if (version != currentVersion) {
      throw QrFormatException(
        'Versi QR SiK3 ($version) tidak didukung aplikasi ini.',
      );
    }

    String requireNonBlankString(String field) {
      final value = parsed[field];
      if (value is! String || value.trim().isEmpty) {
        throw QrFormatException(
          'Data identitas siswa ($field) pada QR kosong atau tidak valid.',
        );
      }
      return value;
    }

    final nisn = requireNonBlankString('nisn');
    final absen = requireNonBlankString('absen');
    final nama = requireNonBlankString('nama');
    final kelas = requireNonBlankString('kelas');
    final jurusan = requireNonBlankString('jurusan');

    final chk = parsed['chk'];
    if (chk is! String || !_checksumPattern.hasMatch(chk)) {
      throw const QrFormatException('Format checksum QR SiK3 tidak valid.');
    }

    final expected = computeChecksum(
      v: version,
      nisn: nisn,
      absen: absen,
      nama: nama,
      kelas: kelas,
      jurusan: jurusan,
    );
    if (chk != expected) {
      throw const QrFormatException(
        'Checksum QR tidak cocok. Minta siswa tampilkan ulang Kartu QR.',
      );
    }

    return StudentIdentity(
      nisn: nisn.trim(),
      attendanceNo: absen.trim(),
      name: nama.trim(),
      className: kelas.trim(),
      major: jurusan.trim(),
    );
  }

  static int _crc16Ccitt(List<int> bytes) {
    var crc = 0xFFFF;
    for (final byte in bytes) {
      crc ^= (byte & 0xFF) << 8;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc & 0xFFFF;
  }
}

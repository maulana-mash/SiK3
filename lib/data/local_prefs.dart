import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sik3/data/qr_identity_codec.dart';

/// Active application role on this device.
enum AppRole { teacher, student }

/// Local workshop teacher metadata used for PDF reports and optional AI assist.
class TeacherProfile {
  const TeacherProfile({
    this.name = '',
    this.nip = '',
    this.schoolName = '',
    this.aiEndpointUrl = '',
  });

  final String name;
  final String nip;
  final String schoolName;
  final String aiEndpointUrl;

  TeacherProfile copyWith({
    String? name,
    String? nip,
    String? schoolName,
    String? aiEndpointUrl,
  }) {
    return TeacherProfile(
      name: name ?? this.name,
      nip: nip ?? this.nip,
      schoolName: schoolName ?? this.schoolName,
      aiEndpointUrl: aiEndpointUrl ?? this.aiEndpointUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'nip': nip,
      'school_name': schoolName,
      'ai_endpoint_url': aiEndpointUrl,
    };
  }

  factory TeacherProfile.fromJson(Map<String, dynamic> json) {
    return TeacherProfile(
      name: (json['name'] as String? ?? '').trim(),
      nip: (json['nip'] as String? ?? '').trim(),
      schoolName: (json['school_name'] as String? ?? '').trim(),
      aiEndpointUrl: (json['ai_endpoint_url'] as String? ?? '').trim(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TeacherProfile &&
            runtimeType == other.runtimeType &&
            name == other.name &&
            nip == other.nip &&
            schoolName == other.schoolName &&
            aiEndpointUrl == other.aiEndpointUrl;
  }

  @override
  int get hashCode => Object.hash(name, nip, schoolName, aiEndpointUrl);

  @override
  String toString() {
    return 'TeacherProfile(name: $name, nip: $nip, schoolName: $schoolName)';
  }
}

/// Persistent offline preferences, salted teacher PIN hash, and local profiles.
class LocalPrefs {
  LocalPrefs._(this._prefs);

  static const String _roleKey = 'sik3_app_role';
  static const String _pinSaltKey = 'sik3_teacher_pin_salt';
  static const String _pinHashKey = 'sik3_teacher_pin_hash';
  static const String _studentProfileKey = 'sik3_student_profile';
  static const String _teacherProfileKey = 'sik3_teacher_profile';

  static final RegExp _pinFormat = RegExp(r'^\d{4,6}$');
  static final Random _secureRandom = Random.secure();

  final SharedPreferences _prefs;

  static Future<LocalPrefs> open([SharedPreferences? prefs]) async {
    final resolved = prefs ?? await SharedPreferences.getInstance();
    return LocalPrefs._(resolved);
  }

  static bool isValidPinFormat(String pin) => _pinFormat.hasMatch(pin);

  AppRole? getRole() {
    final raw = _prefs.getString(_roleKey);
    if (raw == AppRole.teacher.name) return AppRole.teacher;
    if (raw == AppRole.student.name) return AppRole.student;
    return null;
  }

  Future<void> setRole(AppRole? role) async {
    if (role == null) {
      await _prefs.remove(_roleKey);
      return;
    }
    await _prefs.setString(_roleKey, role.name);
  }

  bool hasTeacherPin() {
    final salt = _prefs.getString(_pinSaltKey);
    final hash = _prefs.getString(_pinHashKey);
    return salt != null && salt.isNotEmpty && hash != null && hash.isNotEmpty;
  }

  Future<void> setTeacherPin(String pin) async {
    if (!isValidPinFormat(pin)) {
      throw const FormatException(
        'PIN harus terdiri dari 4 hingga 6 digit angka.',
      );
    }

    final saltBytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    final salt = base64UrlEncode(saltBytes);
    final hash = _hashPin(salt, pin);

    await _prefs.setString(_pinSaltKey, salt);
    await _prefs.setString(_pinHashKey, hash);
  }

  bool verifyTeacherPin(String pin) {
    if (!hasTeacherPin() || !isValidPinFormat(pin)) {
      return false;
    }
    final salt = _prefs.getString(_pinSaltKey)!;
    final storedHash = _prefs.getString(_pinHashKey)!;
    final candidateHash = _hashPin(salt, pin);
    return _constantTimeEquals(storedHash, candidateHash);
  }

  StudentIdentity? getStudentProfile() {
    final raw = _prefs.getString(_studentProfileKey);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final identity = StudentIdentity.fromJson(decoded);
      if (identity.nisn.isEmpty && identity.name.isEmpty) return null;
      return identity;
    } on FormatException {
      return null;
    }
  }

  Future<void> saveStudentProfile(StudentIdentity student) async {
    await _prefs.setString(_studentProfileKey, jsonEncode(student.toJson()));
  }

  TeacherProfile getTeacherProfile() {
    final raw = _prefs.getString(_teacherProfileKey);
    if (raw == null || raw.trim().isEmpty) return const TeacherProfile();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const TeacherProfile();
      return TeacherProfile.fromJson(decoded);
    } on FormatException {
      return const TeacherProfile();
    }
  }

  Future<void> saveTeacherProfile(TeacherProfile profile) async {
    await _prefs.setString(_teacherProfileKey, jsonEncode(profile.toJson()));
  }

  static String _hashPin(String salt, String pin) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

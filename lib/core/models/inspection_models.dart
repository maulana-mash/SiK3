import 'package:sik3/core/models/apd_item.dart';

/// Workshop class configuration including homeroom teacher and required APD items.
class SchoolClass {
  const SchoolClass({
    this.id,
    required this.name,
    required this.homeroomTeacher,
    this.homeroomNip = '',
    required this.requiredApd,
  });

  final int? id;
  final String name;
  final String homeroomTeacher;
  final String homeroomNip;
  final Set<ApdItem> requiredApd;

  /// Required APD items sorted in canonical [ApdItem.values] order.
  List<ApdItem> get orderedRequiredApd =>
      ApdItem.values.where(requiredApd.contains).toList(growable: false);

  SchoolClass copyWith({
    int? id,
    bool clearId = false,
    String? name,
    String? homeroomTeacher,
    String? homeroomNip,
    Set<ApdItem>? requiredApd,
  }) {
    return SchoolClass(
      id: clearId ? null : (id ?? this.id),
      name: name ?? this.name,
      homeroomTeacher: homeroomTeacher ?? this.homeroomTeacher,
      homeroomNip: homeroomNip ?? this.homeroomNip,
      requiredApd: requiredApd ?? this.requiredApd,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SchoolClass &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            homeroomTeacher == other.homeroomTeacher &&
            homeroomNip == other.homeroomNip &&
            _setEquals(requiredApd, other.requiredApd);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    homeroomTeacher,
    homeroomNip,
    Object.hashAllUnordered(requiredApd),
  );

  @override
  String toString() {
    return 'SchoolClass(id: $id, name: $name, homeroomTeacher: $homeroomTeacher, '
        'requiredCount: ${requiredApd.length})';
  }
}

/// Workshop K3 inspection session bound to a class, subject, and teacher metadata.
class InspectionSession {
  const InspectionSession({
    this.id,
    required this.classId,
    required this.subjectName,
    required this.teacherName,
    this.teacherNip = '',
    required this.homeroomTeacher,
    this.homeroomNip = '',
    this.schoolName = '',
    required this.sessionDate,
    required this.requiredApd,
    this.status = 'draft',
  });

  final int? id;
  final int classId;
  final String subjectName;
  final String teacherName;
  final String teacherNip;
  final String homeroomTeacher;
  final String homeroomNip;
  final String schoolName;
  final DateTime sessionDate;
  final Set<ApdItem> requiredApd;
  final String status;

  /// Required APD items sorted in canonical [ApdItem.values] order.
  List<ApdItem> get orderedRequiredApd =>
      ApdItem.values.where(requiredApd.contains).toList(growable: false);

  InspectionSession copyWith({
    int? id,
    bool clearId = false,
    int? classId,
    String? subjectName,
    String? teacherName,
    String? teacherNip,
    String? homeroomTeacher,
    String? homeroomNip,
    String? schoolName,
    DateTime? sessionDate,
    Set<ApdItem>? requiredApd,
    String? status,
  }) {
    return InspectionSession(
      id: clearId ? null : (id ?? this.id),
      classId: classId ?? this.classId,
      subjectName: subjectName ?? this.subjectName,
      teacherName: teacherName ?? this.teacherName,
      teacherNip: teacherNip ?? this.teacherNip,
      homeroomTeacher: homeroomTeacher ?? this.homeroomTeacher,
      homeroomNip: homeroomNip ?? this.homeroomNip,
      schoolName: schoolName ?? this.schoolName,
      sessionDate: sessionDate ?? this.sessionDate,
      requiredApd: requiredApd ?? this.requiredApd,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is InspectionSession &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            classId == other.classId &&
            subjectName == other.subjectName &&
            teacherName == other.teacherName &&
            teacherNip == other.teacherNip &&
            homeroomTeacher == other.homeroomTeacher &&
            homeroomNip == other.homeroomNip &&
            schoolName == other.schoolName &&
            sessionDate == other.sessionDate &&
            _setEquals(requiredApd, other.requiredApd) &&
            status == other.status;
  }

  @override
  int get hashCode => Object.hash(
    id,
    classId,
    subjectName,
    teacherName,
    teacherNip,
    homeroomTeacher,
    homeroomNip,
    schoolName,
    sessionDate,
    Object.hashAllUnordered(requiredApd),
    status,
  );

  @override
  String toString() {
    return 'InspectionSession(id: $id, classId: $classId, '
        'subjectName: $subjectName, status: $status)';
  }
}

/// Single student's APD inspection record stored inside a draft session.
class ScanRecord {
  const ScanRecord({
    this.id,
    required this.sessionId,
    required this.nisn,
    required this.attendanceNo,
    required this.studentName,
    required this.apdResults,
    this.upperPhotoPath,
    this.lowerPhotoPath,
    this.isManualOverride = false,
    this.isAiVerified = false,
    required this.scannedAt,
  });

  final int? id;
  final int sessionId;
  final String nisn;
  final String attendanceNo;
  final String studentName;
  final Map<ApdItem, ApdCheckResult> apdResults;
  final String? upperPhotoPath;
  final String? lowerPhotoPath;
  final bool isManualOverride;
  final bool isAiVerified;
  final DateTime scannedAt;

  ScanRecord copyWith({
    int? id,
    bool clearId = false,
    int? sessionId,
    String? nisn,
    String? attendanceNo,
    String? studentName,
    Map<ApdItem, ApdCheckResult>? apdResults,
    String? upperPhotoPath,
    bool clearUpperPhotoPath = false,
    String? lowerPhotoPath,
    bool clearLowerPhotoPath = false,
    bool? isManualOverride,
    bool? isAiVerified,
    DateTime? scannedAt,
  }) {
    return ScanRecord(
      id: clearId ? null : (id ?? this.id),
      sessionId: sessionId ?? this.sessionId,
      nisn: nisn ?? this.nisn,
      attendanceNo: attendanceNo ?? this.attendanceNo,
      studentName: studentName ?? this.studentName,
      apdResults: apdResults ?? this.apdResults,
      upperPhotoPath:
          clearUpperPhotoPath ? null : (upperPhotoPath ?? this.upperPhotoPath),
      lowerPhotoPath:
          clearLowerPhotoPath ? null : (lowerPhotoPath ?? this.lowerPhotoPath),
      isManualOverride: isManualOverride ?? this.isManualOverride,
      isAiVerified: isAiVerified ?? this.isAiVerified,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ScanRecord &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            sessionId == other.sessionId &&
            nisn == other.nisn &&
            attendanceNo == other.attendanceNo &&
            studentName == other.studentName &&
            _mapEquals(apdResults, other.apdResults) &&
            upperPhotoPath == other.upperPhotoPath &&
            lowerPhotoPath == other.lowerPhotoPath &&
            isManualOverride == other.isManualOverride &&
            isAiVerified == other.isAiVerified &&
            scannedAt == other.scannedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    nisn,
    attendanceNo,
    studentName,
    Object.hashAllUnordered(
      apdResults.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    upperPhotoPath,
    lowerPhotoPath,
    isManualOverride,
    isAiVerified,
    scannedAt,
  );

  @override
  String toString() {
    return 'ScanRecord(id: $id, sessionId: $sessionId, nisn: $nisn, '
        'attendanceNo: $attendanceNo, studentName: $studentName)';
  }
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/core/models/inspection_models.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite draft database storing classes, inspection sessions, and scan records.
class AppDatabase {
  AppDatabase._(this._db);

  static const String defaultFileName = 'sik3_draft.db';
  static const int _schemaVersion = 1;

  final Database _db;

  /// Exposes the underlying SQLite handle for schema/pragma verification in tests.
  @visibleForTesting
  Database get rawDatabase => _db;

  /// Opens the local SQLite draft database, enabling foreign keys and creating
  /// the 3 canonical tables (`classes`, `inspection_sessions`, `scan_records`).
  static Future<AppDatabase> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final resolvedFactory = factory ?? databaseFactory;
    final resolvedPath =
        path ?? p.join(await resolvedFactory.getDatabasesPath(), defaultFileName);

    final db = await resolvedFactory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        singleInstance: resolvedPath != inMemoryDatabasePath,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE classes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        homeroom_teacher TEXT NOT NULL,
        homeroom_nip TEXT NOT NULL DEFAULT '',
        required_apd_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE inspection_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
        subject_name TEXT NOT NULL,
        teacher_name TEXT NOT NULL,
        teacher_nip TEXT NOT NULL DEFAULT '',
        homeroom_teacher TEXT NOT NULL,
        homeroom_nip TEXT NOT NULL DEFAULT '',
        school_name TEXT NOT NULL DEFAULT '',
        session_date TEXT NOT NULL,
        required_apd_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft'
      )
    ''');

    await db.execute('''
      CREATE TABLE scan_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL REFERENCES inspection_sessions(id) ON DELETE CASCADE,
        nisn TEXT NOT NULL,
        attendance_no TEXT NOT NULL,
        student_name TEXT NOT NULL,
        apd_results_json TEXT NOT NULL,
        upper_photo_path TEXT,
        lower_photo_path TEXT,
        is_manual_override INTEGER NOT NULL DEFAULT 0,
        is_ai_verified INTEGER NOT NULL DEFAULT 0,
        scanned_at TEXT NOT NULL,
        UNIQUE(session_id, nisn)
      )
    ''');
  }

  Future<void> close() => _db.close();

  /// Inserts or updates a [SchoolClass] without cascading child sessions on update.
  Future<int> upsertClass(SchoolClass schoolClass) async {
    final values = <String, Object?>{
      'name': schoolClass.name,
      'homeroom_teacher': schoolClass.homeroomTeacher,
      'homeroom_nip': schoolClass.homeroomNip,
      'required_apd_json': _encodeApdSet(schoolClass.orderedRequiredApd),
    };

    final existingId = schoolClass.id;
    if (existingId == null) {
      return _db.insert('classes', values);
    }

    return _db.transaction((txn) async {
      final updatedCount = await txn.update(
        'classes',
        values,
        where: 'id = ?',
        whereArgs: <Object?>[existingId],
      );
      if (updatedCount > 0) return existingId;

      return txn.insert(
        'classes',
        <String, Object?>{'id': existingId, ...values},
      );
    });
  }

  /// Returns all saved workshop classes ordered by insertion order.
  Future<List<SchoolClass>> getClasses() async {
    final rows = await _db.query('classes', orderBy: 'id ASC');
    return rows.map(_schoolClassFromRow).toList(growable: false);
  }

  /// Purges any evidence photos under [classId]'s sessions, then deletes the class
  /// (cascading its sessions and scan records).
  Future<void> deleteClass(int classId) async {
    final pathsToDelete = await _db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''
        SELECT sr.upper_photo_path, sr.lower_photo_path
        FROM scan_records sr
        INNER JOIN inspection_sessions s ON s.id = sr.session_id
        WHERE s.class_id = ?
        ''',
        <Object?>[classId],
      );
      final candidates = _collectPhotoPaths(rows);
      await txn.delete(
        'classes',
        where: 'id = ?',
        whereArgs: <Object?>[classId],
      );
      return _filterUnreferencedPaths(txn, candidates);
    });
    await _deleteFilesOnDisk(pathsToDelete);
  }

  /// Inserts a new [InspectionSession] and returns its assigned row id.
  Future<int> createSession(InspectionSession session) async {
    final values = <String, Object?>{
      if (session.id != null) 'id': session.id,
      'class_id': session.classId,
      'subject_name': session.subjectName,
      'teacher_name': session.teacherName,
      'teacher_nip': session.teacherNip,
      'homeroom_teacher': session.homeroomTeacher,
      'homeroom_nip': session.homeroomNip,
      'school_name': session.schoolName,
      'session_date': session.sessionDate.toIso8601String(),
      'required_apd_json': _encodeApdSet(session.orderedRequiredApd),
      'status': session.status,
    };
    return _db.insert('inspection_sessions', values);
  }

  /// Returns all inspection sessions belonging to [classId], newest first.
  Future<List<InspectionSession>> getSessionsForClass(int classId) async {
    final rows = await _db.query(
      'inspection_sessions',
      where: 'class_id = ?',
      whereArgs: <Object?>[classId],
      orderBy: 'session_date DESC, id DESC',
    );
    return rows.map(_sessionFromRow).toList(growable: false);
  }

  /// Returns the session matching [sessionId], or `null` if absent.
  Future<InspectionSession?> getSession(int sessionId) async {
    final rows = await _db.query(
      'inspection_sessions',
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _sessionFromRow(rows.first);
  }

  /// Updates the lifecycle status (e.g. `'draft'` or `'exported'`) of [sessionId].
  Future<void> updateSessionStatus(int sessionId, String status) async {
    await _db.update(
      'inspection_sessions',
      <String, Object?>{'status': status},
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
    );
  }

  /// Inserts or replaces the student's scan record in `(session_id, nisn)`
  /// in-place, removing superseded disk evidence photo files if paths changed.
  Future<int> upsertScanRecord(ScanRecord record) async {
    final values = <String, Object?>{
      'session_id': record.sessionId,
      'nisn': record.nisn,
      'attendance_no': record.attendanceNo,
      'student_name': record.studentName,
      'apd_results_json': _encodeApdResults(record.apdResults),
      'upper_photo_path': _normalizeOptionalPath(record.upperPhotoPath),
      'lower_photo_path': _normalizeOptionalPath(record.lowerPhotoPath),
      'is_manual_override': record.isManualOverride ? 1 : 0,
      'is_ai_verified': record.isAiVerified ? 1 : 0,
      'scanned_at': record.scannedAt.toIso8601String(),
    };

    // Uses explicit lookup + update/insert inside a transaction instead of
    // SQLite `ON CONFLICT DO UPDATE` (unavailable on Android API 24 / SQLite 3.9)
    // and instead of `INSERT OR REPLACE` (which would churn row ids).
    final outcome = await _db.transaction((txn) async {
      final existing = await txn.query(
        'scan_records',
        columns: <String>['id', 'upper_photo_path', 'lower_photo_path'],
        where: 'session_id = ? AND nisn = ?',
        whereArgs: <Object?>[record.sessionId, record.nisn],
        limit: 1,
      );

      if (existing.isEmpty) {
        final insertedId = await txn.insert(
          'scan_records',
          <String, Object?>{
            if (record.id != null) 'id': record.id,
            ...values,
          },
        );
        return _UpsertOutcome(
          recordId: insertedId,
          obsoletePaths: const <String>[],
        );
      }

      final row = existing.first;
      final existingId = row['id'] as int;
      final oldPaths = _collectPhotoPaths(<Map<String, Object?>>[row]);
      final newUpper = values['upper_photo_path'] as String?;
      final newLower = values['lower_photo_path'] as String?;
      final superseded = oldPaths.where(
        (path) => path != newUpper && path != newLower,
      );

      await txn.update(
        'scan_records',
        values,
        where: 'id = ?',
        whereArgs: <Object?>[existingId],
      );

      final obsoletePaths = await _filterUnreferencedPaths(txn, superseded);
      return _UpsertOutcome(
        recordId: existingId,
        obsoletePaths: obsoletePaths,
      );
    });

    await _deleteFilesOnDisk(outcome.obsoletePaths);
    return outcome.recordId;
  }

  /// Returns all scan records for [sessionId], sorted numerically by
  /// `attendanceNo` ascending (with case-insensitive lexicographical fallback
  /// for non-numeric attendance values, then `studentName` A-Z).
  Future<List<ScanRecord>> getSessionRecords(int sessionId) async {
    final rows = await _db.query(
      'scan_records',
      where: 'session_id = ?',
      whereArgs: <Object?>[sessionId],
    );
    final records = rows.map(_scanRecordFromRow).toList(growable: false);
    records.sort(_compareScanRecords);
    return records;
  }

  /// Deletes a single scan record and removes its unreferenced photo files on disk.
  Future<void> deleteScanRecord(int recordId) async {
    final pathsToDelete = await _db.transaction((txn) async {
      final rows = await txn.query(
        'scan_records',
        columns: <String>['upper_photo_path', 'lower_photo_path'],
        where: 'id = ?',
        whereArgs: <Object?>[recordId],
      );
      final candidates = _collectPhotoPaths(rows);
      await txn.delete(
        'scan_records',
        where: 'id = ?',
        whereArgs: <Object?>[recordId],
      );
      return _filterUnreferencedPaths(txn, candidates);
    });
    await _deleteFilesOnDisk(pathsToDelete);
  }

  /// Deletes evidence photo files on disk for [sessionId] and clears
  /// `upper_photo_path` and `lower_photo_path` in SQLite without altering
  /// APD checklist results. Returns the number of photo files deleted from disk.
  Future<int> purgeSessionPhotos(int sessionId) async {
    final pathsToDelete = await _db.transaction((txn) async {
      final rows = await txn.query(
        'scan_records',
        columns: <String>['upper_photo_path', 'lower_photo_path'],
        where: 'session_id = ?',
        whereArgs: <Object?>[sessionId],
      );
      final candidates = _collectPhotoPaths(rows);
      await txn.update(
        'scan_records',
        <String, Object?>{
          'upper_photo_path': null,
          'lower_photo_path': null,
        },
        where: 'session_id = ?',
        whereArgs: <Object?>[sessionId],
      );
      return _filterUnreferencedPaths(txn, candidates);
    });
    return _deleteFilesOnDisk(pathsToDelete);
  }

  /// Purges disk evidence photos for [sessionId], then deletes the session and
  /// its cascaded scan records.
  Future<void> deleteSession(int sessionId) async {
    await purgeSessionPhotos(sessionId);
    await _db.delete(
      'inspection_sessions',
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
    );
  }

  static SchoolClass _schoolClassFromRow(Map<String, Object?> row) {
    return SchoolClass(
      id: row['id'] as int,
      name: row['name'] as String,
      homeroomTeacher: row['homeroom_teacher'] as String,
      homeroomNip: row['homeroom_nip'] as String? ?? '',
      requiredApd: _decodeApdSet(row['required_apd_json'] as String? ?? '[]'),
    );
  }

  static InspectionSession _sessionFromRow(Map<String, Object?> row) {
    return InspectionSession(
      id: row['id'] as int,
      classId: row['class_id'] as int,
      subjectName: row['subject_name'] as String,
      teacherName: row['teacher_name'] as String,
      teacherNip: row['teacher_nip'] as String? ?? '',
      homeroomTeacher: row['homeroom_teacher'] as String,
      homeroomNip: row['homeroom_nip'] as String? ?? '',
      schoolName: row['school_name'] as String? ?? '',
      sessionDate: DateTime.parse(row['session_date'] as String),
      requiredApd: _decodeApdSet(row['required_apd_json'] as String? ?? '[]'),
      status: row['status'] as String? ?? 'draft',
    );
  }

  static ScanRecord _scanRecordFromRow(Map<String, Object?> row) {
    return ScanRecord(
      id: row['id'] as int,
      sessionId: row['session_id'] as int,
      nisn: row['nisn'] as String,
      attendanceNo: row['attendance_no'] as String,
      studentName: row['student_name'] as String,
      apdResults: _decodeApdResults(row['apd_results_json'] as String? ?? '[]'),
      upperPhotoPath: _normalizeOptionalPath(row['upper_photo_path'] as String?),
      lowerPhotoPath: _normalizeOptionalPath(row['lower_photo_path'] as String?),
      isManualOverride: (row['is_manual_override'] as int? ?? 0) != 0,
      isAiVerified: (row['is_ai_verified'] as int? ?? 0) != 0,
      scannedAt: DateTime.parse(row['scanned_at'] as String),
    );
  }

  static String _encodeApdSet(List<ApdItem> orderedItems) {
    return jsonEncode(
      orderedItems.map((item) => item.key).toList(growable: false),
    );
  }

  static Set<ApdItem> _decodeApdSet(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return <ApdItem>{};
      final items = <ApdItem>{};
      for (final entry in decoded) {
        if (entry is String) {
          final item = ApdItem.fromKey(entry);
          if (item != null) items.add(item);
        }
      }
      return items;
    } on FormatException {
      return <ApdItem>{};
    }
  }

  static String _encodeApdResults(Map<ApdItem, ApdCheckResult> results) {
    final encoded = <Map<String, dynamic>>[
      for (final item in ApdItem.values)
        if (results.containsKey(item)) results[item]!.toJson(),
    ];
    return jsonEncode(encoded);
  }

  static Map<ApdItem, ApdCheckResult> _decodeApdResults(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      final out = <ApdItem, ApdCheckResult>{};
      if (decoded is List) {
        for (final entry in decoded) {
          if (entry is Map) {
            final map = Map<String, dynamic>.from(entry);
            final key = map['item'] as String? ?? '';
            if (ApdItem.fromKey(key) != null) {
              final result = ApdCheckResult.fromJson(map);
              out[result.item] = result;
            }
          }
        }
      } else if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.value is Map) {
            final map = Map<String, dynamic>.from(entry.value as Map);
            map.putIfAbsent('item', () => entry.key.toString());
            final key = map['item'] as String? ?? '';
            if (ApdItem.fromKey(key) != null) {
              final result = ApdCheckResult.fromJson(map);
              out[result.item] = result;
            }
          }
        }
      }
      return out;
    } on FormatException {
      return <ApdItem, ApdCheckResult>{};
    }
  }

  static int _compareScanRecords(ScanRecord a, ScanRecord b) {
    final attA = a.attendanceNo.trim();
    final attB = b.attendanceNo.trim();
    final numA = int.tryParse(attA);
    final numB = int.tryParse(attB);

    if (numA != null && numB != null) {
      final numCmp = numA.compareTo(numB);
      if (numCmp != 0) return numCmp;
      final rawCmp = attA.toLowerCase().compareTo(attB.toLowerCase());
      if (rawCmp != 0) return rawCmp;
    } else if (numA != null) {
      return -1;
    } else if (numB != null) {
      return 1;
    } else {
      final textCmp = attA.toLowerCase().compareTo(attB.toLowerCase());
      if (textCmp != 0) return textCmp;
    }

    final nameCmp = a.studentName
        .trim()
        .toLowerCase()
        .compareTo(b.studentName.trim().toLowerCase());
    if (nameCmp != 0) return nameCmp;

    return (a.id ?? 0).compareTo(b.id ?? 0);
  }

  static String? _normalizeOptionalPath(String? path) {
    if (path == null) return null;
    return path.trim().isEmpty ? null : path;
  }

  static Set<String> _collectPhotoPaths(List<Map<String, Object?>> rows) {
    final paths = <String>{};
    for (final row in rows) {
      final upper = _normalizeOptionalPath(row['upper_photo_path'] as String?);
      final lower = _normalizeOptionalPath(row['lower_photo_path'] as String?);
      if (upper != null) paths.add(upper);
      if (lower != null) paths.add(lower);
    }
    return paths;
  }

  static Future<List<String>> _filterUnreferencedPaths(
    Transaction txn,
    Iterable<String> candidates,
  ) async {
    final unique = candidates.toSet();
    if (unique.isEmpty) return const <String>[];

    final unreferenced = <String>[];
    for (final path in unique) {
      final refs = await txn.rawQuery(
        'SELECT 1 FROM scan_records WHERE upper_photo_path = ? OR lower_photo_path = ? LIMIT 1',
        <Object?>[path, path],
      );
      if (refs.isEmpty) {
        unreferenced.add(path);
      }
    }
    return unreferenced;
  }

  static Future<int> _deleteFilesOnDisk(List<String> paths) async {
    var deletedCount = 0;
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          deletedCount += 1;
        }
      } catch (_) {
        // Ignore filesystem deletion failures for missing or locked paths.
      }
    }
    return deletedCount;
  }
}

class _UpsertOutcome {
  const _UpsertOutcome({
    required this.recordId,
    required this.obsoletePaths,
  });

  final int recordId;
  final List<String> obsoletePaths;
}

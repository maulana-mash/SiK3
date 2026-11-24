import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/core/models/inspection_models.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/core/widgets/apd_svg_icon.dart';
import 'package:sik3/data/app_database.dart';
import 'package:sik3/data/local_prefs.dart';
import 'package:sik3/features/teacher/qr_scan_screen.dart';
import 'package:sik3/features/teacher/review_draft_screen.dart';

typedef ClassLoader = Future<List<SchoolClass>> Function();
typedef ClassSaver = Future<SchoolClass> Function(SchoolClass schoolClass);
typedef ClassDeleter = Future<void> Function(int classId);
typedef InspectionSessionStarter = Future<void> Function(
  BuildContext context,
  SchoolClass schoolClass,
  InspectionSession sessionDraft,
);

/// Teacher home screen for managing profile, classes, homeroom metadata, and 6 APD presets.
class ClassSetupScreen extends StatefulWidget {
  const ClassSetupScreen({
    super.key,
    required this.prefs,
    required this.onSwitchRole,
    this.database,
    this.loadClasses,
    this.saveClass,
    this.deleteClass,
    this.onStartSession,
  });

  final LocalPrefs prefs;
  final VoidCallback onSwitchRole;
  final AppDatabase? database;
  final ClassLoader? loadClasses;
  final ClassSaver? saveClass;
  final ClassDeleter? deleteClass;
  final InspectionSessionStarter? onStartSession;

  @override
  State<ClassSetupScreen> createState() => _ClassSetupScreenState();
}

class _ClassSetupScreenState extends State<ClassSetupScreen> {
  final TextEditingController _subjectController = TextEditingController();

  List<SchoolClass> _classes = <SchoolClass>[];
  int? _selectedClassId;
  Set<ApdItem> _draftRequiredApd = ApdItem.values.toSet();
  late TeacherProfile _teacherProfile;

  bool _loading = false;
  bool _loadingSessions = false;
  bool _savingClass = false;
  bool _startingSession = false;
  int _nextMemoryId = 1;
  int _sessionsLoadSeq = 0;
  String? _sessionError;

  List<InspectionSession> _recentSessions = <InspectionSession>[];
  Map<int, int> _sessionRecordCounts = <int, int>{};

  final Map<int, int> _classSaveSeq = <int, int>{};
  final Map<int, int> _lastPersistedSeqByClass = <int, int>{};
  final Map<int, SchoolClass> _lastPersistedByClass = <int, SchoolClass>{};

  ClassLoader? get _effectiveLoadClasses =>
      widget.loadClasses ?? widget.database?.getClasses;

  @override
  void initState() {
    super.initState();
    _teacherProfile = widget.prefs.getTeacherProfile();
    if (_effectiveLoadClasses != null) {
      _loading = true;
      _refreshClasses();
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    super.dispose();
  }

  SchoolClass? get _selectedClass {
    final targetId = _selectedClassId;
    if (targetId == null) return null;
    for (final item in _classes) {
      if (item.id == targetId) return item;
    }
    return null;
  }

  Set<ApdItem> get _activeRequiredApd =>
      _selectedClass?.requiredApd ?? _draftRequiredApd;

  Future<void> _refreshClasses() async {
    final loader = _effectiveLoadClasses;
    if (loader == null) return;
    setState(() => _loading = true);
    try {
      final loaded = await loader();
      if (!mounted) return;
      final normalized = <SchoolClass>[];
      for (final item in loaded) {
        if (item.id == null) {
          normalized.add(item.copyWith(id: _nextMemoryId++));
        } else {
          if (item.id! >= _nextMemoryId) {
            _nextMemoryId = item.id! + 1;
          }
          normalized.add(item);
        }
      }

      int? nextSelected = _selectedClassId;
      if (nextSelected == null ||
          !normalized.any((element) => element.id == nextSelected)) {
        nextSelected = normalized.isNotEmpty ? normalized.first.id : null;
      }

      setState(() {
        _classes = normalized;
        _selectedClassId = nextSelected;
        _loading = false;
        _lastPersistedByClass
          ..clear()
          ..addEntries(
            normalized
                .where((c) => c.id != null)
                .map((c) => MapEntry<int, SchoolClass>(c.id!, c)),
          );
      });
      await _refreshSessionsForSelectedClass();
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshSessionsForSelectedClass() async {
    final db = widget.database;
    final classId = _selectedClassId;
    final seq = ++_sessionsLoadSeq;

    if (db == null || classId == null) {
      if (mounted) {
        setState(() {
          _recentSessions = <InspectionSession>[];
          _sessionRecordCounts = <int, int>{};
          _loadingSessions = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _loadingSessions = true);
    }

    try {
      final sessions = await db.getSessionsForClass(classId);
      final counts = <int, int>{};
      for (final session in sessions) {
        final sid = session.id;
        if (sid != null) {
          final records = await db.getSessionRecords(sid);
          counts[sid] = records.length;
        }
      }
      if (!mounted || seq != _sessionsLoadSeq) return;
      setState(() {
        _recentSessions = sessions;
        _sessionRecordCounts = counts;
        _loadingSessions = false;
      });
    } on Object {
      if (!mounted || seq != _sessionsLoadSeq) return;
      setState(() => _loadingSessions = false);
    }
  }

  Future<SchoolClass> _persistClass(SchoolClass schoolClass) async {
    final saver = widget.saveClass;
    if (saver != null) {
      return saver(schoolClass);
    }
    final db = widget.database;
    if (db != null) {
      final assignedId = await db.upsertClass(schoolClass);
      return schoolClass.copyWith(id: assignedId);
    }
    if (schoolClass.id != null) {
      return schoolClass;
    }
    return schoolClass.copyWith(id: _nextMemoryId++);
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Sik3Colors.statusMissing,
        ),
      );
  }

  Future<void> _toggleApdItem(ApdItem item) async {
    final selected = _selectedClass;
    final nextSet = Set<ApdItem>.from(_activeRequiredApd);
    if (nextSet.contains(item)) {
      nextSet.remove(item);
    } else {
      nextSet.add(item);
    }

    if (selected == null) {
      setState(() {
        _draftRequiredApd = nextSet;
        if (nextSet.isNotEmpty) {
          _sessionError = null;
        }
      });
      return;
    }

    final classId = selected.id;
    final updated = selected.copyWith(requiredApd: nextSet);
    int? seq;
    if (classId != null) {
      _lastPersistedByClass.putIfAbsent(classId, () => selected);
      seq = (_classSaveSeq[classId] ?? 0) + 1;
      _classSaveSeq[classId] = seq;
    }

    setState(() {
      _classes = _classes
          .map((c) => c.id == updated.id ? updated : c)
          .toList(growable: false);
      if (nextSet.isNotEmpty) {
        _sessionError = null;
      }
    });

    try {
      final saved = await _persistClass(updated);
      if (!mounted) return;

      if (classId != null) {
        final persistedSeq = _lastPersistedSeqByClass[classId] ?? 0;
        if (seq != null && seq > persistedSeq) {
          _lastPersistedSeqByClass[classId] = seq;
          _lastPersistedByClass[classId] = saved;
        }
        if (seq != _classSaveSeq[classId]) {
          // A newer toggle has superseded this response; keep newer UI state.
          return;
        }
      }

      if (!_classes.any((c) => c.id == saved.id)) return;

      setState(() {
        _classes = _classes
            .map((c) => c.id == saved.id ? saved : c)
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      if (classId != null && seq != _classSaveSeq[classId]) {
        // Ignore stale failure when a newer mutation is already active/applied.
        return;
      }
      final fallback = classId != null
          ? (_lastPersistedByClass[classId] ?? selected)
          : selected;
      setState(() {
        _classes = _classes
            .map((c) => c.id == fallback.id ? fallback : c)
            .toList(growable: false);
      });
      _showErrorSnackBar(
        'Gagal menyimpan perubahan APD wajib. Perubahan dibatalkan.',
      );
    }
  }

  Future<void> _openTeacherProfileSheet() async {
    final updated = await showModalBottomSheet<TeacherProfile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Sik3Colors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Sik3Radius.outer),
        ),
      ),
      builder: (_) => _TeacherProfileSheet(
        prefs: widget.prefs,
        initial: _teacherProfile,
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        _teacherProfile = updated;
      });
    }
  }

  Future<void> _openClassFormSheet({SchoolClass? existing}) async {
    if (_savingClass) return;

    final draftResult = await showModalBottomSheet<SchoolClass>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Sik3Colors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Sik3Radius.outer),
        ),
      ),
      builder: (_) => _ClassFormSheet(
        existing: existing,
        defaultRequiredApd: _draftRequiredApd.isEmpty
            ? ApdItem.values.toSet()
            : _draftRequiredApd,
      ),
    );

    if (draftResult == null || !mounted) return;

    setState(() {
      _savingClass = true;
      _sessionError = null;
    });
    try {
      final saved = await _persistClass(draftResult);
      if (!mounted) return;
      final savedId = saved.id;
      if (savedId != null) {
        final nextSeq = (_classSaveSeq[savedId] ?? 0) + 1;
        _classSaveSeq[savedId] = nextSeq;
        _lastPersistedSeqByClass[savedId] = nextSeq;
        _lastPersistedByClass[savedId] = saved;
      }
      final nextList = List<SchoolClass>.from(_classes);
      final existingIndex = nextList.indexWhere((c) => c.id == saved.id);
      if (existingIndex >= 0) {
        nextList[existingIndex] = saved;
      } else {
        nextList.add(saved);
      }
      setState(() {
        _classes = nextList;
        _selectedClassId = saved.id;
        _draftRequiredApd = Set<ApdItem>.from(saved.requiredApd);
      });
      await _refreshSessionsForSelectedClass();
    } catch (_) {
      _showErrorSnackBar('Gagal menyimpan data kelas. Silakan coba lagi.');
    } finally {
      if (mounted) {
        setState(() => _savingClass = false);
      }
    }
  }

  Future<void> _confirmDeleteClass(SchoolClass schoolClass) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Kelas?'),
        content: Text(
          'Kelas ${schoolClass.name} beserta pengaturan wali kelasnya akan dihapus dari daftar.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Sik3Colors.statusMissing,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final classId = schoolClass.id;
    final deleter = widget.deleteClass ?? widget.database?.deleteClass;
    try {
      if (classId != null && deleter != null) {
        await deleter(classId);
      }
    } catch (_) {
      _showErrorSnackBar('Gagal menghapus kelas. Silakan coba lagi.');
      return;
    }
    if (!mounted) return;

    if (classId != null) {
      _classSaveSeq.remove(classId);
      _lastPersistedSeqByClass.remove(classId);
      _lastPersistedByClass.remove(classId);
    }

    final nextList = _classes
        .where((c) => c.id != schoolClass.id)
        .toList(growable: false);
    setState(() {
      _classes = nextList;
      if (_selectedClassId == schoolClass.id) {
        _selectedClassId = nextList.isNotEmpty ? nextList.first.id : null;
      }
    });
    await _refreshSessionsForSelectedClass();
  }

  Future<void> _openExistingSession(
    SchoolClass schoolClass,
    InspectionSession session,
  ) async {
    final db = widget.database;
    if (db == null || session.id == null) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReviewDraftScreen(
          schoolClass: schoolClass,
          session: session,
          database: db,
          prefs: widget.prefs,
        ),
      ),
    );

    if (mounted) {
      await _refreshSessionsForSelectedClass();
    }
  }

  Future<void> _confirmDeleteSession(InspectionSession session) async {
    final db = widget.database;
    final sessionId = session.id;
    if (db == null || sessionId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Sesi Inspeksi?'),
        content: Text(
          'Sesi "${session.subjectName}" beserta seluruh catatan siswa dan foto draft-nya akan dihapus permanen.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const ValueKey<String>('confirm_delete_session_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Sik3Colors.statusMissing,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus Sesi'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await db.deleteSession(sessionId);
      if (!mounted) return;
      await _refreshSessionsForSelectedClass();
    } on Object {
      _showErrorSnackBar('Gagal menghapus sesi inspeksi. Silakan coba lagi.');
    }
  }

  Future<String?> _promptSessionSubjectSheet(SchoolClass schoolClass) {
    final prefill = _subjectController.text.trim().isNotEmpty
        ? _subjectController.text.trim()
        : (_recentSessions.isNotEmpty
              ? _recentSessions.first.subjectName
              : '');

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Sik3Colors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Sik3Radius.outer),
        ),
      ),
      builder: (_) => _StartSessionSubjectSheet(
        className: schoolClass.name,
        requiredCount: schoolClass.requiredApd.length,
        initialSubject: prefill,
      ),
    );
  }

  Future<void> _startInspectionSession() async {
    if (_startingSession) return;
    final requiredApd = _activeRequiredApd;
    if (requiredApd.isEmpty) {
      setState(() {
        _sessionError =
            'Pilih minimal 1 APD wajib sebelum memulai sesi inspeksi.';
      });
      return;
    }

    final selectedClass = _selectedClass;
    if (selectedClass == null) {
      setState(() {
        _sessionError = 'Tambahkan dan pilih kelas terlebih dahulu.';
      });
      return;
    }

    final db = widget.database;
    var subjectText = _subjectController.text.trim();

    if (db != null && widget.onStartSession == null) {
      final pickedSubject = await _promptSessionSubjectSheet(selectedClass);
      if (pickedSubject == null || !mounted) return;
      subjectText = pickedSubject.trim();
      _subjectController.text = subjectText;
    }

    setState(() {
      _startingSession = true;
      _sessionError = null;
    });

    try {
      final profile = widget.prefs.getTeacherProfile();
      var sessionDraft = InspectionSession(
        classId: selectedClass.id ?? 0,
        subjectName: subjectText.isEmpty ? 'Praktik Bengkel' : subjectText,
        teacherName: profile.name.isEmpty ? 'Guru Bengkel' : profile.name,
        teacherNip: profile.nip,
        homeroomTeacher: selectedClass.homeroomTeacher,
        homeroomNip: selectedClass.homeroomNip,
        schoolName: profile.schoolName,
        sessionDate: DateTime.now(),
        requiredApd: Set<ApdItem>.unmodifiable(requiredApd),
        status: 'draft',
      );

      if (db != null && selectedClass.id != null) {
        try {
          final sessionId = await db.createSession(sessionDraft);
          sessionDraft = sessionDraft.copyWith(id: sessionId);
        } catch (_) {
          _showErrorSnackBar('Gagal membuat sesi inspeksi. Silakan coba lagi.');
          return;
        }
      }

      if (!mounted) return;

      if (widget.onStartSession != null) {
        await widget.onStartSession!(context, selectedClass, sessionDraft);
        if (mounted && db != null) {
          await _refreshSessionsForSelectedClass();
        }
        return;
      }

      if (db != null && sessionDraft.id != null) {
        await _refreshSessionsForSelectedClass();
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ReviewDraftScreen(
              schoolClass: selectedClass,
              session: sessionDraft,
              database: db,
              prefs: widget.prefs,
            ),
          ),
        );
        if (mounted) {
          await _refreshSessionsForSelectedClass();
        }
        return;
      }

      // Fallback when running without SQLite database (unit tests/preview):
      final scannedStudent = await openStudentQrScanner(
        context,
        defaultClassName: selectedClass.name,
      );
      if (scannedStudent != null && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Identitas siswa terbaca: ${scannedStudent.name} (${scannedStudent.nisn})',
              ),
              backgroundColor: Sik3Colors.statusPassed,
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _startingSession = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedClass = _selectedClass;
    final activeRequiredApd = _activeRequiredApd;
    final motionDuration = Sik3Motion.resolve(context, Sik3Motion.normal);

    return Scaffold(
      backgroundColor: Sik3Colors.surfaceLight,
      appBar: AppBar(
        title: const Text('Mode Guru'),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('teacher_profile_settings_button'),
            tooltip: 'Profil Guru & AI',
            onPressed: _openTeacherProfileSheet,
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
          TextButton.icon(
            key: const ValueKey<String>('teacher_switch_role_button'),
            onPressed: widget.onSwitchRole,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(
                Sik3Spacing.minTouchTarget,
                Sik3Spacing.minTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(horizontal: Sik3Spacing.md),
            ),
            icon: const Icon(Icons.swap_horiz, size: 20),
            label: const Text('Ganti Peran'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Sik3Spacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _TeacherProfileSummaryCard(
                    profile: _teacherProfile,
                    onEditPressed: _openTeacherProfileSheet,
                  ),
                  const SizedBox(height: Sik3Spacing.lg),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Daftar Kelas',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Sik3Colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey<String>('add_class_button'),
                        onPressed:
                            _savingClass ? null : () => _openClassFormSheet(),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Tambah Kelas'),
                      ),
                    ],
                  ),
                  const SizedBox(height: Sik3Spacing.sm),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: Sik3Spacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_classes.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(Sik3Spacing.lg),
                      decoration: BoxDecoration(
                        color: Sik3Colors.cardSurface,
                        borderRadius: BorderRadius.circular(Sik3Radius.outer),
                        border: Border.all(color: Sik3Colors.border),
                      ),
                      child: Text(
                        'Belum ada kelas tersimpan. Tambahkan kelas beserta nama wali kelas untuk memulai sesi inspeksi K3.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Sik3Colors.textSecondary,
                        ),
                      ),
                    )
                  else
                    Column(
                      children: <Widget>[
                        for (var i = 0; i < _classes.length; i++) ...<Widget>[
                          _ClassSelectionCard(
                            schoolClass: _classes[i],
                            isSelected: _classes[i].id == _selectedClassId,
                            onSelect: () {
                              setState(() {
                                _selectedClassId = _classes[i].id;
                                _sessionError = null;
                              });
                              unawaited(_refreshSessionsForSelectedClass());
                            },
                            onEdit: () =>
                                _openClassFormSheet(existing: _classes[i]),
                            onDelete: () => _confirmDeleteClass(_classes[i]),
                          ),
                          if (i < _classes.length - 1)
                            const SizedBox(height: Sik3Spacing.sm),
                        ],
                      ],
                    ),
                  const SizedBox(height: Sik3Spacing.xl),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          selectedClass == null
                              ? 'Preset APD Wajib'
                              : 'APD Wajib — ${selectedClass.name}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Sik3Colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Sik3Spacing.sm,
                          vertical: Sik3Spacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: activeRequiredApd.isEmpty
                              ? Sik3Colors.statusMissing.withValues(alpha: 0.12)
                              : Sik3Colors.navy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(Sik3Radius.chip),
                        ),
                        child: Text(
                          '${activeRequiredApd.length}/6 Wajib',
                          style: Sik3Typography.tabular(
                            theme.textTheme.labelMedium?.copyWith(
                                  color: activeRequiredApd.isEmpty
                                      ? Sik3Colors.statusMissing
                                      : Sik3Colors.navy,
                                  fontWeight: FontWeight.w700,
                                ) ??
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Sik3Spacing.xs),
                  Text(
                    'Ketuk item APD untuk mengatur kewajiban di bengkel pada kelas aktif.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Sik3Colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Sik3Spacing.md),
                  _ApdToggleGrid(
                    selectedApd: activeRequiredApd,
                    onToggle: _toggleApdItem,
                  ),
                  AnimatedSize(
                    duration: motionDuration,
                    curve: Sik3Motion.curve,
                    child: activeRequiredApd.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: Sik3Spacing.sm),
                            child: Text(
                              'Pilih minimal 1 APD wajib sebelum memulai sesi inspeksi.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Sik3Colors.statusMissing,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : (_sessionError != null
                              ? Padding(
                                  padding: const EdgeInsets.only(
                                    top: Sik3Spacing.sm,
                                  ),
                                  child: Text(
                                    _sessionError!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Sik3Colors.statusMissing,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink()),
                  ),
                  const SizedBox(height: Sik3Spacing.xl),
                  TextField(
                    key: const ValueKey<String>('session_subject_field'),
                    controller: _subjectController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Mata Praktik',
                      hintText:
                          'Contoh: Teknik Pemesinan Bubut (default: Praktik Bengkel)',
                    ),
                  ),
                  const SizedBox(height: Sik3Spacing.lg),
                  FilledButton.icon(
                    key: const ValueKey<String>('start_session_button'),
                    onPressed: _startingSession ? null : _startInspectionSession,
                    style: FilledButton.styleFrom(
                      backgroundColor: Sik3Colors.amber,
                      foregroundColor: Sik3Colors.navy,
                      minimumSize: const Size(double.infinity, 52),
                    ),
                    icon: const Icon(Icons.qr_code_scanner_outlined),
                    label: const Text('Mulai Sesi Inspeksi'),
                  ),
                  if (widget.database != null && selectedClass != null) ...<Widget>[
                    const SizedBox(height: Sik3Spacing.xl),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Sesi Inspeksi — ${selectedClass.name}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Sik3Colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Sik3Spacing.sm,
                            vertical: Sik3Spacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: Sik3Colors.navy.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(Sik3Radius.chip),
                          ),
                          child: Text(
                            '${_recentSessions.length} Sesi',
                            style: Sik3Typography.tabular(
                              theme.textTheme.labelMedium?.copyWith(
                                    color: Sik3Colors.navy,
                                    fontWeight: FontWeight.w700,
                                  ) ??
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Sik3Spacing.sm),
                    if (_loadingSessions)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: Sik3Spacing.lg),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_recentSessions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(Sik3Spacing.md),
                        decoration: BoxDecoration(
                          color: Sik3Colors.cardSurface,
                          borderRadius: BorderRadius.circular(Sik3Radius.outer),
                          border: Border.all(color: Sik3Colors.border),
                        ),
                        child: Text(
                          'Belum ada sesi inspeksi untuk kelas ini. Ketuk Mulai Sesi Inspeksi untuk membuat draft baru.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Sik3Colors.textSecondary,
                          ),
                        ),
                      )
                    else
                      Column(
                        children: <Widget>[
                          for (var i = 0; i < _recentSessions.length; i++) ...<Widget>[
                            _SessionHistoryCard(
                              session: _recentSessions[i],
                              studentCount:
                                  _sessionRecordCounts[_recentSessions[i].id] ??
                                  0,
                              onOpen: () => _openExistingSession(
                                selectedClass,
                                _recentSessions[i],
                              ),
                              onDelete: () =>
                                  _confirmDeleteSession(_recentSessions[i]),
                            ),
                            if (i < _recentSessions.length - 1)
                              const SizedBox(height: Sik3Spacing.sm),
                          ],
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TeacherProfileSummaryCard extends StatelessWidget {
  const _TeacherProfileSummaryCard({
    required this.profile,
    required this.onEditPressed,
  });

  final TeacherProfile profile;
  final VoidCallback onEditPressed;

  static String? _buildProfileMeta(TeacherProfile profile) {
    final parts = <String>[
      if (profile.schoolName.isNotEmpty) profile.schoolName,
      if (profile.nip.isNotEmpty) 'NIP ${profile.nip}',
    ];
    return parts.isEmpty ? null : parts.join(' - ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasName = profile.name.isNotEmpty;
    final hasAiUrl = profile.aiEndpointUrl.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(Sik3Spacing.md),
      decoration: BoxDecoration(
        color: Sik3Colors.cardSurface,
        borderRadius: BorderRadius.circular(Sik3Radius.outer),
        border: Border.all(color: Sik3Colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Sik3Colors.navy,
              borderRadius: BorderRadius.circular(Sik3Radius.inner),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.badge_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: Sik3Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  hasName ? profile.name : 'Profil Guru Mapel',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Sik3Colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasName
                      ? (_buildProfileMeta(profile) ??
                          'NIP dan sekolah belum diisi')
                      : 'Lengkapi nama, NIP, sekolah, dan URL AI opsional untuk kop PDF.',
                  style: Sik3Typography.tabular(
                    theme.textTheme.bodySmall?.copyWith(
                          color: Sik3Colors.textSecondary,
                        ) ??
                        const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: Sik3Spacing.xs),
                Text(
                  hasAiUrl ? 'Verifikasi AI Opsional: Aktif' : 'Mode Offline Penuh',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hasAiUrl
                        ? Sik3Colors.statusPassed
                        : Sik3Colors.navy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Sik3Spacing.sm),
          TextButton(
            onPressed: onEditPressed,
            child: Text(hasName ? 'Edit' : 'Atur'),
          ),
        ],
      ),
    );
  }
}

class _ClassSelectionCard extends StatelessWidget {
  const _ClassSelectionCard({
    required this.schoolClass,
    required this.isSelected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final SchoolClass schoolClass;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected
          ? Sik3Colors.navy.withValues(alpha: 0.04)
          : Sik3Colors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sik3Radius.outer),
        side: BorderSide(
          color: isSelected ? Sik3Colors.navy : Sik3Colors.border,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Sik3Spacing.md,
            Sik3Spacing.sm,
            Sik3Spacing.xs,
            Sik3Spacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected ? Sik3Colors.navy : Sik3Colors.textSecondary,
              ),
              const SizedBox(width: Sik3Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            schoolClass.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Sik3Colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: Sik3Spacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Sik3Spacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Sik3Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(
                              Sik3Radius.chip,
                            ),
                          ),
                          child: Text(
                            '${schoolClass.requiredApd.length}/6 APD',
                            style: Sik3Typography.tabular(
                              theme.textTheme.labelSmall?.copyWith(
                                    color: Sik3Colors.navy,
                                    fontWeight: FontWeight.w700,
                                  ) ??
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Wali Kelas: ${schoolClass.homeroomTeacher}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Sik3Colors.textSecondary,
                      ),
                    ),
                    if (schoolClass.homeroomNip.isNotEmpty)
                      Text(
                        'NIP: ${schoolClass.homeroomNip}',
                        style: Sik3Typography.tabular(
                          theme.textTheme.labelSmall?.copyWith(
                                color: Sik3Colors.textSecondary,
                              ) ??
                              const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey<String>('edit_class_${schoolClass.id}'),
                tooltip: 'Edit Kelas',
                onPressed: onEdit,
                icon: const Icon(
                  Icons.edit_outlined,
                  color: Sik3Colors.navy,
                ),
              ),
              IconButton(
                key: ValueKey<String>('delete_class_${schoolClass.id}'),
                tooltip: 'Hapus Kelas',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  color: Sik3Colors.statusMissing,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApdToggleGrid extends StatelessWidget {
  const _ApdToggleGrid({
    required this.selectedApd,
    required this.onToggle,
    this.keyPrefix = 'apd_toggle',
  });

  final Set<ApdItem> selectedApd;
  final ValueChanged<ApdItem> onToggle;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final singleColumn = constraints.maxWidth < 320;
        final items = ApdItem.values;

        if (singleColumn) {
          return Column(
            children: <Widget>[
              for (var i = 0; i < items.length; i++) ...<Widget>[
                _ApdToggleCard(
                  key: ValueKey<String>('${keyPrefix}_${items[i].key}'),
                  item: items[i],
                  isSelected: selectedApd.contains(items[i]),
                  onTap: () => onToggle(items[i]),
                ),
                if (i < items.length - 1) const SizedBox(height: Sik3Spacing.sm),
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += 2) {
          final left = items[i];
          final right = (i + 1 < items.length) ? items[i + 1] : null;
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _ApdToggleCard(
                      key: ValueKey<String>('${keyPrefix}_${left.key}'),
                      item: left,
                      isSelected: selectedApd.contains(left),
                      onTap: () => onToggle(left),
                    ),
                  ),
                  const SizedBox(width: Sik3Spacing.sm),
                  Expanded(
                    child: right == null
                        ? const SizedBox.shrink()
                        : _ApdToggleCard(
                            key: ValueKey<String>('${keyPrefix}_${right.key}'),
                            item: right,
                            isSelected: selectedApd.contains(right),
                            onTap: () => onToggle(right),
                          ),
                  ),
                ],
              ),
            ),
          );
          if (i + 2 < items.length) {
            rows.add(const SizedBox(height: Sik3Spacing.sm));
          }
        }
        return Column(children: rows);
      },
    );
  }
}

class _ApdToggleCard extends StatelessWidget {
  const _ApdToggleCard({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final ApdItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = Sik3Motion.resolve(context, Sik3Motion.fast);

    return Semantics(
      button: true,
      toggled: isSelected,
      label: '${item.labelId}, ${isSelected ? 'Wajib' : 'Nonaktif'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Sik3Radius.cardInner),
          child: AnimatedContainer(
            duration: duration,
            curve: Sik3Motion.curve,
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.all(Sik3Spacing.md),
            decoration: BoxDecoration(
              color: isSelected
                  ? Sik3Colors.cardSurface
                  : Sik3Colors.surfaceLight,
              borderRadius: BorderRadius.circular(Sik3Radius.cardInner),
              border: Border.all(
                color: isSelected ? Sik3Colors.navy : Sik3Colors.border,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Sik3Colors.navy.withValues(alpha: 0.08)
                        : Sik3Colors.border.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(Sik3Radius.inner),
                  ),
                  alignment: Alignment.center,
                  child: ApdSvgIcon(
                    item: item,
                    size: 22,
                    color: isSelected
                        ? Sik3Colors.navy
                        : Sik3Colors.textSecondary,
                  ),
                ),
                const SizedBox(width: Sik3Spacing.sm),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.labelId,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: isSelected
                              ? Sik3Colors.textPrimary
                              : Sik3Colors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isSelected ? 'Wajib' : 'Nonaktif',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isSelected
                              ? Sik3Colors.statusPassed
                              : Sik3Colors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: isSelected
                      ? Sik3Colors.statusPassed
                      : Sik3Colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeacherProfileSheet extends StatefulWidget {
  const _TeacherProfileSheet({
    required this.prefs,
    required this.initial,
  });

  final LocalPrefs prefs;
  final TeacherProfile initial;

  @override
  State<_TeacherProfileSheet> createState() => _TeacherProfileSheetState();
}

class _TeacherProfileSheetState extends State<_TeacherProfileSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _nipController;
  late final TextEditingController _schoolController;
  late final TextEditingController _aiUrlController;

  bool _saving = false;
  bool _submittedOnce = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial.name);
    _nipController = TextEditingController(text: widget.initial.nip);
    _schoolController = TextEditingController(text: widget.initial.schoolName);
    _aiUrlController = TextEditingController(
      text: widget.initial.aiEndpointUrl,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nipController.dispose();
    _schoolController.dispose();
    _aiUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submittedOnce = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final profile = TeacherProfile(
        name: _nameController.text.trim(),
        nip: _nipController.text.trim(),
        schoolName: _schoolController.text.trim(),
        aiEndpointUrl: _aiUrlController.text.trim(),
      );
      await widget.prefs.saveTeacherProfile(profile);
      if (mounted) {
        Navigator.of(context).pop(profile);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Sik3Spacing.lg,
          Sik3Spacing.lg,
          Sik3Spacing.lg,
          Sik3Spacing.xl,
        ),
        child: Form(
          key: _formKey,
          autovalidateMode: _submittedOnce
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Profil Guru & Pengaturan AI',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Sik3Colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Sik3Spacing.xs),
              Text(
                'Digunakan untuk kop dan blok tanda tangan laporan PDF A4. URL AI bersifat opsional.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Sik3Colors.textSecondary,
                ),
              ),
              const SizedBox(height: Sik3Spacing.lg),
              TextFormField(
                key: const ValueKey<String>('teacher_profile_name_field'),
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nama Guru Mapel',
                  hintText: 'Contoh: Ir. Hendra Wijaya',
                ),
              ),
              const SizedBox(height: Sik3Spacing.md),
              TextFormField(
                key: const ValueKey<String>('teacher_profile_nip_field'),
                controller: _nipController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                style: Sik3Typography.tabular(const TextStyle(fontSize: 16)),
                decoration: const InputDecoration(
                  labelText: 'NIP (Opsional)',
                  hintText: 'Contoh: 198003142009021001',
                ),
              ),
              const SizedBox(height: Sik3Spacing.md),
              TextFormField(
                key: const ValueKey<String>('teacher_profile_school_field'),
                controller: _schoolController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nama Sekolah / Jurusan',
                  hintText: 'Contoh: SMK Negeri 2 Surabaya',
                ),
              ),
              const SizedBox(height: Sik3Spacing.md),
              TextFormField(
                key: const ValueKey<String>('teacher_profile_ai_url_field'),
                controller: _aiUrlController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: 'URL Verifikasi AI Tambahan (Opsional)',
                  hintText: 'https://domain-anda.vercel.app/api/verify-apd',
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final uri = Uri.tryParse(trimmed);
                  if (uri == null ||
                      !(uri.scheme == 'http' || uri.scheme == 'https') ||
                      !uri.hasAuthority ||
                      uri.host.trim().isEmpty) {
                    return 'URL harus diawali http:// atau https:// yang valid.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: Sik3Spacing.xl),
              FilledButton(
                key: const ValueKey<String>('teacher_profile_save_button'),
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: Sik3Colors.amber,
                  foregroundColor: Sik3Colors.navy,
                ),
                child: const Text('Simpan Profil Guru'),
              ),
              const SizedBox(height: Sik3Spacing.sm),
              TextButton(
                onPressed:
                    _saving ? null : () => Navigator.of(context).pop(null),
                child: const Text('Batal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassFormSheet extends StatefulWidget {
  const _ClassFormSheet({
    this.existing,
    required this.defaultRequiredApd,
  });

  final SchoolClass? existing;
  final Set<ApdItem> defaultRequiredApd;

  @override
  State<_ClassFormSheet> createState() => _ClassFormSheetState();
}

class _ClassFormSheetState extends State<_ClassFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _classNameController;
  late final TextEditingController _homeroomController;
  late final TextEditingController _homeroomNipController;
  late Set<ApdItem> _requiredApd;

  bool _submittedOnce = false;
  String? _apdError;

  @override
  void initState() {
    super.initState();
    _classNameController = TextEditingController(
      text: widget.existing?.name ?? '',
    );
    _homeroomController = TextEditingController(
      text: widget.existing?.homeroomTeacher ?? '',
    );
    _homeroomNipController = TextEditingController(
      text: widget.existing?.homeroomNip ?? '',
    );
    _requiredApd = Set<ApdItem>.from(
      widget.existing?.requiredApd ?? widget.defaultRequiredApd,
    );
  }

  @override
  void dispose() {
    _classNameController.dispose();
    _homeroomController.dispose();
    _homeroomNipController.dispose();
    super.dispose();
  }

  void _toggleItem(ApdItem item) {
    setState(() {
      if (_requiredApd.contains(item)) {
        _requiredApd.remove(item);
      } else {
        _requiredApd.add(item);
      }
      if (_requiredApd.isNotEmpty) {
        _apdError = null;
      }
    });
  }

  void _submit() {
    setState(() => _submittedOnce = true);
    final formValid = _formKey.currentState?.validate() ?? false;
    if (_requiredApd.isEmpty) {
      setState(() {
        _apdError = 'Pilih minimal 1 APD wajib untuk kelas ini.';
      });
      return;
    }
    if (!formValid) return;

    final result = SchoolClass(
      id: widget.existing?.id,
      name: _classNameController.text.trim(),
      homeroomTeacher: _homeroomController.text.trim(),
      homeroomNip: _homeroomNipController.text.trim(),
      requiredApd: Set<ApdItem>.unmodifiable(_requiredApd),
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Sik3Spacing.lg,
          Sik3Spacing.lg,
          Sik3Spacing.lg,
          Sik3Spacing.xl,
        ),
        child: Form(
          key: _formKey,
          autovalidateMode: _submittedOnce
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                isEdit ? 'Edit Kelas' : 'Tambah Kelas Baru',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Sik3Colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Sik3Spacing.xs),
              Text(
                'Tentukan wali kelas dan preset APD wajib untuk kelas ini.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Sik3Colors.textSecondary,
                ),
              ),
              const SizedBox(height: Sik3Spacing.lg),
              TextFormField(
                key: const ValueKey<String>('class_name_field'),
                controller: _classNameController,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nama Kelas',
                  hintText: 'Contoh: XI TKR 1',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nama kelas wajib diisi.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: Sik3Spacing.md),
              TextFormField(
                key: const ValueKey<String>('homeroom_teacher_field'),
                controller: _homeroomController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nama Wali Kelas',
                  hintText: 'Contoh: Drs. Budi Santoso',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nama wali kelas wajib diisi.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: Sik3Spacing.md),
              TextFormField(
                key: const ValueKey<String>('homeroom_nip_field'),
                controller: _homeroomNipController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                style: Sik3Typography.tabular(const TextStyle(fontSize: 16)),
                decoration: const InputDecoration(
                  labelText: 'NIP Wali Kelas (Opsional)',
                  hintText: 'Contoh: 197801012005011002',
                ),
              ),
              const SizedBox(height: Sik3Spacing.lg),
              Text(
                'APD Wajib Kelas (${_requiredApd.length}/6)',
                style: Sik3Typography.tabular(
                  theme.textTheme.titleSmall?.copyWith(
                        color: Sik3Colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ) ??
                      const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: Sik3Spacing.sm),
              _ApdToggleGrid(
                keyPrefix: 'class_form_apd',
                selectedApd: _requiredApd,
                onToggle: _toggleItem,
              ),
              if (_apdError != null) ...<Widget>[
                const SizedBox(height: Sik3Spacing.sm),
                Text(
                  _apdError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Sik3Colors.statusMissing,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: Sik3Spacing.xl),
              FilledButton(
                key: const ValueKey<String>('class_form_save_button'),
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: Sik3Colors.amber,
                  foregroundColor: Sik3Colors.navy,
                ),
                child: Text(isEdit ? 'Simpan Perubahan' : 'Simpan Kelas'),
              ),
              const SizedBox(height: Sik3Spacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Batal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionHistoryCard extends StatelessWidget {
  const _SessionHistoryCard({
    required this.session,
    required this.studentCount,
    required this.onOpen,
    required this.onDelete,
  });

  final InspectionSession session;
  final int studentCount;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExported = session.status == 'exported';
    final badgeColor =
        isExported ? Sik3Colors.statusPassed : Sik3Colors.statusReview;

    return Material(
      key: ValueKey<String>('resume_session_${session.id}'),
      color: Sik3Colors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sik3Radius.outer),
        side: const BorderSide(color: Sik3Colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Sik3Spacing.md,
            Sik3Spacing.sm,
            Sik3Spacing.xs,
            Sik3Spacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Sik3Colors.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Sik3Radius.inner),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.assignment_outlined,
                  color: Sik3Colors.navy,
                  size: 20,
                ),
              ),
              const SizedBox(width: Sik3Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            session.subjectName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Sik3Colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: Sik3Spacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Sik3Spacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(Sik3Radius.chip),
                          ),
                          child: Text(
                            isExported ? 'Diekspor' : 'Draft',
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatSessionDateTime(session.sessionDate)} · $studentCount Siswa · ${session.requiredApd.length}/6 APD',
                      style: Sik3Typography.tabular(
                        theme.textTheme.bodySmall?.copyWith(
                              color: Sik3Colors.textSecondary,
                            ) ??
                            const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey<String>('delete_session_${session.id}'),
                tooltip: 'Hapus Sesi',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  color: Sik3Colors.statusMissing,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartSessionSubjectSheet extends StatefulWidget {
  const _StartSessionSubjectSheet({
    required this.className,
    required this.requiredCount,
    required this.initialSubject,
  });

  final String className;
  final int requiredCount;
  final String initialSubject;

  @override
  State<_StartSessionSubjectSheet> createState() =>
      _StartSessionSubjectSheetState();
}

class _StartSessionSubjectSheetState extends State<_StartSessionSubjectSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialSubject);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Sik3Spacing.lg,
          Sik3Spacing.lg,
          Sik3Spacing.lg,
          Sik3Spacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Mulai Sesi Inspeksi — ${widget.className}',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Sik3Colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Sik3Spacing.xs),
            Text(
              'Masukkan nama mata praktik untuk kop laporan (${widget.requiredCount}/6 APD wajib aktif).',
              style: Sik3Typography.tabular(
                theme.textTheme.bodyMedium?.copyWith(
                      color: Sik3Colors.textSecondary,
                    ) ??
                    const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: Sik3Spacing.lg),
            TextField(
              key: const ValueKey<String>('start_session_subject_sheet_field'),
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirm(),
              decoration: const InputDecoration(
                labelText: 'Mata Praktik',
                hintText: 'Contoh: Teknik Pemesinan Bubut (default: Praktik Bengkel)',
              ),
            ),
            const SizedBox(height: Sik3Spacing.lg),
            FilledButton.icon(
              key: const ValueKey<String>('confirm_start_session_button'),
              onPressed: _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: Sik3Colors.amber,
                foregroundColor: Sik3Colors.navy,
                minimumSize: const Size(double.infinity, 52),
              ),
              icon: const Icon(Icons.play_arrow_outlined),
              label: const Text('Buka Draft & Mulai Scan'),
            ),
            const SizedBox(height: Sik3Spacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );
  }
}

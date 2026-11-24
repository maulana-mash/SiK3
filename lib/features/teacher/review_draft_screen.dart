import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/core/models/inspection_models.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/core/widgets/apd_svg_icon.dart';
import 'package:sik3/data/app_database.dart';
import 'package:sik3/data/local_prefs.dart';
import 'package:sik3/data/qr_identity_codec.dart';
import 'package:sik3/features/teacher/apd_zone_scan_screen.dart';
import 'package:sik3/features/teacher/pdf_preview_screen.dart';
import 'package:sik3/features/teacher/qr_scan_screen.dart';
import 'package:sik3/ml/online_ai_verifier.dart';

typedef StudentQrScannerOpener = Future<StudentIdentity?> Function(
  BuildContext context, {
  String? defaultClassName,
});

typedef StudentZoneScanOpener = Future<ScanRecord?> Function(
  BuildContext context, {
  required InspectionSession session,
  required StudentIdentity student,
  required AppDatabase database,
});

typedef DraftPdfExportHandler = Future<void> Function(
  BuildContext context,
  SchoolClass schoolClass,
  InspectionSession session,
  List<ScanRecord> records,
);

/// Overall compliance category of a student's inspection record.
enum StudentInspectionStatus {
  complete(labelId: 'Lengkap'),
  needsReview(labelId: 'Perlu Cek'),
  incomplete(labelId: 'Kurang');

  const StudentInspectionStatus({required this.labelId});

  final String labelId;
}

/// Computes a student's aggregate status against the session's [requiredApd].
StudentInspectionStatus computeStudentStatus(
  ScanRecord record,
  Set<ApdItem> requiredApd,
) {
  var hasNeedsReview = false;
  for (final item in requiredApd) {
    final status = record.apdResults[item]?.status ?? ApdStatus.needsReview;
    if (status == ApdStatus.missing) {
      return StudentInspectionStatus.incomplete;
    }
    if (status == ApdStatus.needsReview) {
      hasNeedsReview = true;
    }
  }
  return hasNeedsReview
      ? StudentInspectionStatus.needsReview
      : StudentInspectionStatus.complete;
}

/// 1-tap APD toggle transition:
/// `needsReview -> detected`, `detected -> missing`, `missing -> detected`.
ApdStatus nextApdStatusOnTap(ApdStatus current) {
  switch (current) {
    case ApdStatus.needsReview:
      return ApdStatus.detected;
    case ApdStatus.detected:
      return ApdStatus.missing;
    case ApdStatus.missing:
      return ApdStatus.detected;
  }
}

/// Formats a session timestamp in concise Indonesian numeric form `DD/MM/YYYY · HH:mm`.
String formatSessionDateTime(DateTime dateTime) {
  final day = dateTime.day.toString().padLeft(2, '0');
  final month = dateTime.month.toString().padLeft(2, '0');
  final year = dateTime.year.toString().padLeft(4, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$day/$month/$year · $hour:$minute';
}

/// Teacher local draft validation screen with 1-tap APD overrides, evidence
/// photo viewer, student rescanning, photo cleanup, and PDF export hook.
class ReviewDraftScreen extends StatefulWidget {
  const ReviewDraftScreen({
    super.key,
    required this.schoolClass,
    required this.session,
    required this.database,
    this.prefs,
    this.aiEndpointUrl,
    this.aiVerifier,
    this.openQrScanner,
    this.openZoneScanner,
    this.onVerifyWithAi,
    this.onExportPdf,
  });

  final SchoolClass schoolClass;
  final InspectionSession session;
  final AppDatabase database;
  final LocalPrefs? prefs;
  final String? aiEndpointUrl;
  final OnlineAiVerifier? aiVerifier;
  final StudentQrScannerOpener? openQrScanner;
  final StudentZoneScanOpener? openZoneScanner;
  final Future<void> Function(ScanRecord record)? onVerifyWithAi;
  final DraftPdfExportHandler? onExportPdf;

  @override
  State<ReviewDraftScreen> createState() => _ReviewDraftScreenState();
}

class _ReviewDraftScreenState extends State<ReviewDraftScreen> {
  late InspectionSession _session;
  List<ScanRecord> _records = <ScanRecord>[];
  bool _loading = true;
  bool _busyAction = false;
  String? _verifyingNisn;

  final Map<String, int> _recordSaveSeq = <String, int>{};
  final Map<String, int> _lastPersistedSeqByNisn = <String, int>{};
  final Map<String, ScanRecord> _lastPersistedByNisn = <String, ScanRecord>{};
  final Map<String, Future<void>> _writeQueueByNisn = <String, Future<void>>{};

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    unawaited(_loadSessionData());
  }

  bool get _hasAnyDraftPhotos => _records.any(
    (record) => record.upperPhotoPath != null || record.lowerPhotoPath != null,
  );

  String get _effectiveAiEndpointUrl =>
      (widget.aiEndpointUrl ??
              widget.prefs?.getTeacherProfile().aiEndpointUrl ??
              '')
          .trim();

  bool get _hasAiVerification =>
      widget.onVerifyWithAi != null || _effectiveAiEndpointUrl.isNotEmpty;

  Future<void> _drainPendingWrites() async {
    if (_writeQueueByNisn.isEmpty) return;
    await Future.wait<void>(_writeQueueByNisn.values.toList(growable: false));
  }

  Future<void> _loadSessionData() async {
    final sessionId = _session.id;
    if (sessionId == null) {
      if (mounted) {
        setState(() {
          _records = <ScanRecord>[];
          _loading = false;
        });
      }
      return;
    }

    try {
      await _drainPendingWrites();
      final freshSession = await widget.database.getSession(sessionId);
      final loaded = await widget.database.getSessionRecords(sessionId);
      if (!mounted) return;
      setState(() {
        if (freshSession != null) {
          _session = freshSession;
        }
        _records = loaded;
        _loading = false;
        _lastPersistedByNisn
          ..clear()
          ..addEntries(
            loaded.map((r) => MapEntry<String, ScanRecord>(r.nisn, r)),
          );
      });
    } on Object {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnackBar(
        'Gagal memuat daftar draft siswa.',
        backgroundColor: Sik3Colors.statusMissing,
      );
    }
  }

  void _showSnackBar(
    String message, {
    Color backgroundColor = Sik3Colors.navy,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
        ),
      );
  }

  Future<void> _toggleApdChip(String nisn, ApdItem item) async {
    if (_busyAction || _verifyingNisn == nisn) return;
    final recordIndex = _records.indexWhere((r) => r.nisn == nisn);
    if (recordIndex < 0) return;
    final record = _records[recordIndex];

    final currentCheck =
        record.apdResults[item] ??
        ApdCheckResult(item: item, status: ApdStatus.needsReview);
    final nextStatus = nextApdStatusOnTap(currentCheck.status);

    final updatedResults = Map<ApdItem, ApdCheckResult>.from(record.apdResults);
    updatedResults[item] = currentCheck.copyWith(
      status: nextStatus,
      manualOverride: true,
    );

    final updatedRecord = record.copyWith(
      apdResults: Map<ApdItem, ApdCheckResult>.unmodifiable(updatedResults),
      isManualOverride: true,
    );

    _lastPersistedByNisn.putIfAbsent(nisn, () => record);
    final seq = (_recordSaveSeq[nisn] ?? 0) + 1;
    _recordSaveSeq[nisn] = seq;

    setState(() {
      _records = _records
          .map((r) => r.nisn == nisn ? updatedRecord : r)
          .toList(growable: false);
    });

    final previousWrite = _writeQueueByNisn[nisn] ?? Future<void>.value();
    final queuedWrite = previousWrite.then((_) async {
      try {
        final savedId = await widget.database.upsertScanRecord(updatedRecord);
        final persisted = updatedRecord.copyWith(id: savedId);
        if (!mounted) return;
        final lastSeq = _lastPersistedSeqByNisn[nisn] ?? 0;
        if (seq > lastSeq) {
          _lastPersistedSeqByNisn[nisn] = seq;
          _lastPersistedByNisn[nisn] = persisted;
        }
        if (seq == _recordSaveSeq[nisn]) {
          setState(() {
            _records = _records
                .map((r) => r.nisn == nisn ? persisted : r)
                .toList(growable: false);
          });
        }
      } on Object {
        if (!mounted) return;
        if (seq != _recordSaveSeq[nisn]) return;
        final fallback = _lastPersistedByNisn[nisn] ?? record;
        setState(() {
          _records = _records
              .map((r) => r.nisn == nisn ? fallback : r)
              .toList(growable: false);
        });
        _showSnackBar(
          'Gagal menyimpan perubahan ceklis APD. Perubahan dibatalkan.',
          backgroundColor: Sik3Colors.statusMissing,
        );
      }
    });

    _writeQueueByNisn[nisn] = queuedWrite;
    await queuedWrite;
    if (identical(_writeQueueByNisn[nisn], queuedWrite)) {
      _writeQueueByNisn.remove(nisn);
    }
  }

  Future<void> _scanNewStudent() async {
    if (_loading || _busyAction || _verifyingNisn != null) return;
    setState(() => _busyAction = true);
    try {
      final qrOpener = widget.openQrScanner ?? openStudentQrScanner;
      final identity = await qrOpener(
        context,
        defaultClassName: widget.schoolClass.name,
      );
      if (identity == null || !mounted) return;

      await _runZoneScanForStudent(identity);
    } finally {
      if (mounted) {
        setState(() => _busyAction = false);
      }
    }
  }

  Future<void> _rescanStudent(ScanRecord record) async {
    if (_busyAction || _verifyingNisn != null) return;
    setState(() => _busyAction = true);
    try {
      final identity = StudentIdentity(
        nisn: record.nisn,
        attendanceNo: record.attendanceNo,
        name: record.studentName,
        className: widget.schoolClass.name,
        major: '',
      );
      await _runZoneScanForStudent(identity);
    } finally {
      if (mounted) {
        setState(() => _busyAction = false);
      }
    }
  }

  Future<void> _runZoneScanForStudent(StudentIdentity student) async {
    await _drainPendingWrites();
    if (!mounted) return;
    final zoneOpener = widget.openZoneScanner ?? openApdZoneScanner;
    final savedRecord = await zoneOpener(
      context,
      session: _session,
      student: student,
      database: widget.database,
    );
    if (!mounted || savedRecord == null) return;

    await _loadSessionData();
    if (!mounted) return;
    _showSnackBar(
      'Hasil ${savedRecord.studentName} tersimpan di draft lokal.',
      backgroundColor: Sik3Colors.statusPassed,
    );
  }

  Future<void> _openEvidencePhotos(ScanRecord record) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Sik3Colors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Sik3Radius.outer),
        ),
      ),
      builder: (_) => _EvidencePhotoViewerSheet(record: record),
    );
  }

  Future<void> _verifyStudentWithAi(ScanRecord record) async {
    if (!_hasAiVerification ||
        _loading ||
        _busyAction ||
        _verifyingNisn != null) {
      return;
    }

    final callback = widget.onVerifyWithAi;
    if (callback != null) {
      setState(() => _verifyingNisn = record.nisn);
      try {
        await _drainPendingWrites();
        if (!mounted) return;
        final latestIdx = _records.indexWhere((r) => r.nisn == record.nisn);
        final target = latestIdx >= 0 ? _records[latestIdx] : record;
        await callback(target);
        if (!mounted) return;
        await _loadSessionData();
      } on Object {
        _showSnackBar(
          'Verifikasi AI tambahan gagal. Draft lokal Anda tetap aman.',
          backgroundColor: Sik3Colors.statusMissing,
        );
      } finally {
        if (mounted) {
          setState(() => _verifyingNisn = null);
        }
      }
      return;
    }

    setState(() => _verifyingNisn = record.nisn);
    late final ScanRecord target;
    OnlineVerifyResult? verifyResult;
    try {
      await _drainPendingWrites();
      if (!mounted) return;
      final latestIdx = _records.indexWhere((r) => r.nisn == record.nisn);
      target = latestIdx >= 0 ? _records[latestIdx] : record;

      if (target.upperPhotoPath == null && target.lowerPhotoPath == null) {
        _showSnackBar(
          'Foto bukti siswa belum tersedia atau sudah dibersihkan. Lakukan Scan Ulang terlebih dahulu.',
        );
        return;
      }

      final verifier = widget.aiVerifier ?? OnlineAiVerifier();
      verifyResult = await verifier.verify(
        upperPhotoPath: target.upperPhotoPath,
        lowerPhotoPath: target.lowerPhotoPath,
        requiredItems: _session.requiredApd,
        endpointUrl: _effectiveAiEndpointUrl,
      );
    } on Object {
      verifyResult = const VerifyFailure(
        'Verifikasi AI tambahan gagal. Draft lokal Anda tetap aman.',
      );
    } finally {
      if (mounted) {
        setState(() => _verifyingNisn = null);
      }
    }

    if (!mounted) return;

    switch (verifyResult) {
      case VerifyFailure(:final message):
        _showSnackBar(message, backgroundColor: Sik3Colors.navy);
      case VerifySuccess(:final results, :final summary):
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => _AiVerifyConfirmationDialog(
            record: target,
            requiredApd: _session.orderedRequiredApd,
            aiResults: results,
            summary: summary,
          ),
        );
        if (confirmed != true || !mounted) return;
        await _applyConfirmedAiResults(target, results);
    }
  }

  Future<void> _applyConfirmedAiResults(
    ScanRecord target,
    Map<ApdItem, ApdCheckResult> aiResults,
  ) async {
    if (_busyAction) return;
    setState(() => _busyAction = true);
    try {
      await _drainPendingWrites();
      if (!mounted) return;
      final latestIdx = _records.indexWhere((r) => r.nisn == target.nisn);
      final base = latestIdx >= 0 ? _records[latestIdx] : target;

      final merged = Map<ApdItem, ApdCheckResult>.from(base.apdResults);
      for (final entry in aiResults.entries) {
        merged[entry.key] = entry.value.copyWith(manualOverride: false);
      }
      final stillHasManual = merged.values.any((c) => c.manualOverride);
      final updated = base.copyWith(
        apdResults: Map<ApdItem, ApdCheckResult>.unmodifiable(merged),
        isManualOverride: stillHasManual,
        isAiVerified: true,
      );

      await widget.database.upsertScanRecord(updated);
      if (!mounted) return;
      await _loadSessionData();
      if (!mounted) return;
      _showSnackBar(
        'Hasil Verifikasi AI untuk ${base.studentName} diterapkan ke draft.',
        backgroundColor: Sik3Colors.statusPassed,
      );
    } on Object {
      _showSnackBar(
        'Gagal menerapkan hasil Verifikasi AI. Draft lokal Anda tetap aman.',
        backgroundColor: Sik3Colors.statusMissing,
      );
    } finally {
      if (mounted) {
        setState(() => _busyAction = false);
      }
    }
  }

  Future<void> _confirmPurgeDraftPhotos() async {
    if (_loading || _busyAction || _verifyingNisn != null) return;
    if (!_hasAnyDraftPhotos) {
      _showSnackBar('Belum ada foto draft yang tersimpan pada sesi ini.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bersihkan Foto Draft?'),
        content: const Text(
          'Semua berkas foto bukti sementara pada sesi ini akan dihapus dari penyimpanan HP untuk menghemat ruang. Data ceklis APD siswa tetap tersimpan utuh.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const ValueKey<String>('confirm_purge_photos_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Sik3Colors.statusMissing,
              foregroundColor: Colors.white,
            ),
            child: const Text('Bersihkan Foto'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final sessionId = _session.id;
    if (sessionId == null) return;

    setState(() => _busyAction = true);
    try {
      await _drainPendingWrites();
      final deletedCount = await widget.database.purgeSessionPhotos(sessionId);
      if (!mounted) return;
      await _loadSessionData();
      if (!mounted) return;
      final message = deletedCount > 0
          ? '$deletedCount foto draft dibersihkan. Data ceklis siswa tetap tersimpan.'
          : 'Path foto draft dibersihkan. Data ceklis siswa tetap tersimpan.';
      _showSnackBar(message, backgroundColor: Sik3Colors.statusPassed);
    } on Object {
      _showSnackBar(
        'Gagal membersihkan foto draft. Silakan coba lagi.',
        backgroundColor: Sik3Colors.statusMissing,
      );
    } finally {
      if (mounted) {
        setState(() => _busyAction = false);
      }
    }
  }

  Future<void> _handleExportPdf() async {
    if (_loading || _busyAction || _verifyingNisn != null) return;
    setState(() => _busyAction = true);
    try {
      await _drainPendingWrites();
      if (!mounted) return;

      if (widget.onExportPdf != null) {
        await widget.onExportPdf!(
          context,
          widget.schoolClass,
          _session,
          List<ScanRecord>.unmodifiable(_records),
        );
        if (mounted) {
          await _loadSessionData();
        }
        return;
      }

      final logoData = await rootBundle.load(
        'assets/icons/logo_sik3_transparent.png',
      );
      final logoBytes = logoData.buffer.asUint8List(
        logoData.offsetInBytes,
        logoData.lengthInBytes,
      );
      final sessionId = _session.id;
      if (sessionId != null) {
        await widget.database.updateSessionStatus(sessionId, 'exported');
      }
      final exportedSession = _session.copyWith(status: 'exported');
      if (!mounted) return;
      setState(() => _session = exportedSession);

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewScreen(
            schoolClass: widget.schoolClass,
            session: exportedSession,
            records: List<ScanRecord>.unmodifiable(_records),
            logoBytes: logoBytes,
          ),
        ),
      );
      if (mounted) {
        await _loadSessionData();
      }
    } on Object {
      _showSnackBar(
        'Gagal menyiapkan laporan PDF A4. Silakan coba lagi.',
        backgroundColor: Sik3Colors.statusMissing,
      );
    } finally {
      if (mounted) {
        setState(() => _busyAction = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var completeCount = 0;
    var reviewCount = 0;
    var incompleteCount = 0;

    for (final record in _records) {
      switch (computeStudentStatus(record, _session.requiredApd)) {
        case StudentInspectionStatus.complete:
          completeCount += 1;
        case StudentInspectionStatus.needsReview:
          reviewCount += 1;
        case StudentInspectionStatus.incomplete:
          incompleteCount += 1;
      }
    }

    final isExported = _session.status == 'exported';
    final isActionLocked = _loading || _busyAction || _verifyingNisn != null;

    return Scaffold(
      backgroundColor: Sik3Colors.surfaceLight,
      appBar: AppBar(
        title: const Text('Validasi Draft Inspeksi'),
        actions: <Widget>[
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: Sik3Spacing.md),
              padding: const EdgeInsets.symmetric(
                horizontal: Sik3Spacing.sm + 2,
                vertical: Sik3Spacing.xs,
              ),
              decoration: BoxDecoration(
                color: isExported
                    ? Sik3Colors.statusPassed
                    : Sik3Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(Sik3Radius.chip),
              ),
              child: Text(
                isExported ? 'Diekspor' : 'Draft Lokal',
                style: TextStyle(
                  color: isExported ? Colors.white : Sik3Colors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: CustomScrollView(
                    slivers: <Widget>[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          Sik3Spacing.lg,
                          Sik3Spacing.lg,
                          Sik3Spacing.lg,
                          Sik3Spacing.sm,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _SessionSummaryHeader(
                            schoolClass: widget.schoolClass,
                            session: _session,
                            totalCount: _records.length,
                            completeCount: completeCount,
                            reviewCount: reviewCount,
                            incompleteCount: incompleteCount,
                            hasPhotos: _hasAnyDraftPhotos,
                            busy: isActionLocked,
                            onPurgePhotos: _confirmPurgeDraftPhotos,
                          ),
                        ),
                      ),
                      if (_records.isEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            Sik3Spacing.lg,
                            Sik3Spacing.sm,
                            Sik3Spacing.lg,
                            Sik3Spacing.xl,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: _EmptyDraftStateCard(theme: theme),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            Sik3Spacing.lg,
                            Sik3Spacing.sm,
                            Sik3Spacing.lg,
                            Sik3Spacing.xl,
                          ),
                          sliver: SliverList.separated(
                            itemCount: _records.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: Sik3Spacing.md),
                            itemBuilder: (context, index) {
                              final record = _records[index];
                              final nisn = record.nisn;
                              final isThisVerifying = _verifyingNisn == nisn;
                              final canToggleApd =
                                  !_busyAction && !isThisVerifying;
                              return _StudentDraftCard(
                                record: record,
                                requiredApd: _session.orderedRequiredApd,
                                requiredApdSet: _session.requiredApd,
                                showVerifyAi: _hasAiVerification,
                                isVerifyingAi: isThisVerifying,
                                onToggleApd: canToggleApd
                                    ? (item) => _toggleApdChip(nisn, item)
                                    : null,
                                onViewPhotos:
                                    (record.upperPhotoPath != null ||
                                        record.lowerPhotoPath != null)
                                    ? () => _openEvidencePhotos(record)
                                    : null,
                                onRescan: isActionLocked
                                    ? null
                                    : () => _rescanStudent(record),
                                onVerifyAi:
                                    (_hasAiVerification && !isActionLocked)
                                    ? () => _verifyStudentWithAi(record)
                                    : null,
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
      bottomNavigationBar: _BottomDraftActionBar(
        busy: isActionLocked,
        onExportPdf: _handleExportPdf,
        onScanStudent: _scanNewStudent,
      ),
    );
  }
}

class _SessionSummaryHeader extends StatelessWidget {
  const _SessionSummaryHeader({
    required this.schoolClass,
    required this.session,
    required this.totalCount,
    required this.completeCount,
    required this.reviewCount,
    required this.incompleteCount,
    required this.hasPhotos,
    required this.busy,
    required this.onPurgePhotos,
  });

  final SchoolClass schoolClass;
  final InspectionSession session;
  final int totalCount;
  final int completeCount;
  final int reviewCount;
  final int incompleteCount;
  final bool hasPhotos;
  final bool busy;
  final VoidCallback onPurgePhotos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(Sik3Spacing.lg),
      decoration: BoxDecoration(
        color: Sik3Colors.cardSurface,
        borderRadius: BorderRadius.circular(Sik3Radius.cardOuter),
        border: Border.all(color: Sik3Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      schoolClass.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Sik3Colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.subjectName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Sik3Colors.navy,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatSessionDateTime(session.sessionDate),
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
              const SizedBox(width: Sik3Spacing.sm),
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
                  '${session.requiredApd.length}/6 APD',
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
          const SizedBox(height: Sik3Spacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _SummaryMetricTile(
                  countKey: const ValueKey<String>('summary_count_total'),
                  label: 'Total',
                  count: totalCount,
                  accentColor: Sik3Colors.navy,
                ),
              ),
              const SizedBox(width: Sik3Spacing.sm),
              Expanded(
                child: _SummaryMetricTile(
                  countKey: const ValueKey<String>('summary_count_complete'),
                  label: 'Lengkap',
                  count: completeCount,
                  accentColor: Sik3Colors.statusPassed,
                ),
              ),
              const SizedBox(width: Sik3Spacing.sm),
              Expanded(
                child: _SummaryMetricTile(
                  countKey: const ValueKey<String>('summary_count_review'),
                  label: 'Perlu Cek',
                  count: reviewCount,
                  accentColor: Sik3Colors.statusReview,
                ),
              ),
              const SizedBox(width: Sik3Spacing.sm),
              Expanded(
                child: _SummaryMetricTile(
                  countKey: const ValueKey<String>('summary_count_missing'),
                  label: 'Kurang',
                  count: incompleteCount,
                  accentColor: Sik3Colors.statusMissing,
                ),
              ),
            ],
          ),
          const SizedBox(height: Sik3Spacing.md),
          OutlinedButton.icon(
            key: const ValueKey<String>('purge_draft_photos_button'),
            onPressed: busy ? null : onPurgePhotos,
            style: OutlinedButton.styleFrom(
              foregroundColor: hasPhotos
                  ? Sik3Colors.statusMissing
                  : Sik3Colors.textSecondary,
              side: BorderSide(
                color: hasPhotos
                    ? Sik3Colors.statusMissing.withValues(alpha: 0.45)
                    : Sik3Colors.border,
              ),
            ),
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            label: const Text('Bersihkan Foto Draft'),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetricTile extends StatelessWidget {
  const _SummaryMetricTile({
    required this.countKey,
    required this.label,
    required this.count,
    required this.accentColor,
  });

  final Key countKey;
  final String label;
  final int count;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Sik3Spacing.xs + 2,
        vertical: Sik3Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Sik3Radius.inner),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$count',
            key: countKey,
            style: Sik3Typography.tabular(
              theme.textTheme.titleMedium?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                  ) ??
                  TextStyle(color: accentColor, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Sik3Colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDraftStateCard extends StatelessWidget {
  const _EmptyDraftStateCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sik3Spacing.xl),
      decoration: BoxDecoration(
        color: Sik3Colors.cardSurface,
        borderRadius: BorderRadius.circular(Sik3Radius.cardOuter),
        border: Border.all(color: Sik3Colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Sik3Colors.navy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Sik3Radius.inner),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.qr_code_scanner_outlined,
              size: 28,
              color: Sik3Colors.navy,
            ),
          ),
          const SizedBox(height: Sik3Spacing.md),
          Text(
            'Belum Ada Siswa Diperiksa',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Sik3Colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Sik3Spacing.xs),
          Text(
            'Ketuk tombol Scan Siswa di bawah untuk memindai Kartu QR siswa lalu arahkan kamera ke Zona Atas & Zona Bawah.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Sik3Colors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentDraftCard extends StatelessWidget {
  const _StudentDraftCard({
    required this.record,
    required this.requiredApd,
    required this.requiredApdSet,
    required this.showVerifyAi,
    required this.isVerifyingAi,
    required this.onToggleApd,
    required this.onViewPhotos,
    required this.onRescan,
    required this.onVerifyAi,
  });

  final ScanRecord record;
  final List<ApdItem> requiredApd;
  final Set<ApdItem> requiredApdSet;
  final bool showVerifyAi;
  final bool isVerifyingAi;
  final ValueChanged<ApdItem>? onToggleApd;
  final VoidCallback? onViewPhotos;
  final VoidCallback? onRescan;
  final VoidCallback? onVerifyAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overallStatus = computeStudentStatus(record, requiredApdSet);

    return Container(
      padding: const EdgeInsets.all(Sik3Spacing.md),
      decoration: BoxDecoration(
        color: Sik3Colors.cardSurface,
        borderRadius: BorderRadius.circular(Sik3Radius.cardOuter),
        border: Border.all(color: Sik3Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: Sik3Spacing.sm,
                  vertical: Sik3Spacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Sik3Colors.navy,
                  borderRadius: BorderRadius.circular(Sik3Radius.inner),
                ),
                alignment: Alignment.center,
                child: Text(
                  record.attendanceNo,
                  style: Sik3Typography.tabular(
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Sik3Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      record.studentName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Sik3Colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'NISN ${record.nisn}',
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
              const SizedBox(width: Sik3Spacing.sm),
              _StudentStatusBadge(status: overallStatus),
            ],
          ),
          if (record.isManualOverride || record.isAiVerified) ...<Widget>[
            const SizedBox(height: Sik3Spacing.sm),
            Wrap(
              spacing: Sik3Spacing.sm,
              runSpacing: Sik3Spacing.xs,
              children: <Widget>[
                if (record.isManualOverride)
                  const _MetaTagChip(
                    icon: Icons.edit_outlined,
                    label: 'Edit Manual',
                    color: Sik3Colors.navy,
                  ),
                if (record.isAiVerified)
                  const _MetaTagChip(
                    icon: Icons.verified_outlined,
                    label: 'Terverifikasi AI',
                    color: Sik3Colors.statusPassed,
                  ),
              ],
            ),
          ],
          const SizedBox(height: Sik3Spacing.md),
          Wrap(
            spacing: Sik3Spacing.sm,
            runSpacing: Sik3Spacing.sm,
            children: <Widget>[
              for (final item in requiredApd)
                _ApdStatusChip(
                  key: ValueKey<String>('apd_chip_${record.nisn}_${item.key}'),
                  item: item,
                  result:
                      record.apdResults[item] ??
                      ApdCheckResult(item: item, status: ApdStatus.needsReview),
                  onTap: onToggleApd == null ? null : () => onToggleApd!(item),
                ),
            ],
          ),
          const SizedBox(height: Sik3Spacing.md),
          const Divider(),
          const SizedBox(height: Sik3Spacing.xs),
          Wrap(
            spacing: Sik3Spacing.sm,
            runSpacing: Sik3Spacing.xs,
            children: <Widget>[
              if (onViewPhotos != null)
                TextButton.icon(
                  key: ValueKey<String>('view_photo_${record.nisn}'),
                  onPressed: onViewPhotos,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Lihat Foto'),
                ),
              TextButton.icon(
                key: ValueKey<String>('rescan_student_${record.nisn}'),
                onPressed: onRescan,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Scan Ulang'),
              ),
              if (showVerifyAi)
                TextButton.icon(
                  key: ValueKey<String>('verify_ai_${record.nisn}'),
                  onPressed: onVerifyAi,
                  icon: isVerifyingAi
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_outlined, size: 18),
                  label: Text(
                    isVerifyingAi
                        ? 'Memverifikasi...'
                        : 'Verifikasi AI Tambahan',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StudentStatusBadge extends StatelessWidget {
  const _StudentStatusBadge({required this.status});

  final StudentInspectionStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    switch (status) {
      case StudentInspectionStatus.complete:
        color = Sik3Colors.statusPassed;
        icon = Icons.check_circle_outline;
      case StudentInspectionStatus.needsReview:
        color = Sik3Colors.statusReview;
        icon = Icons.help_outline;
      case StudentInspectionStatus.incomplete:
        color = Sik3Colors.statusMissing;
        icon = Icons.cancel_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Sik3Spacing.sm,
        vertical: Sik3Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Sik3Radius.chip),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: Sik3Spacing.xs),
          Text(
            status.labelId,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaTagChip extends StatelessWidget {
  const _MetaTagChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Sik3Spacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Sik3Radius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApdStatusChip extends StatelessWidget {
  const _ApdStatusChip({
    super.key,
    required this.item,
    required this.result,
    required this.onTap,
  });

  final ApdItem item;
  final ApdCheckResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final duration = Sik3Motion.resolve(context, Sik3Motion.fast);
    final enabled = onTap != null;

    final Color accent;
    final IconData statusIcon;
    switch (result.status) {
      case ApdStatus.detected:
        accent = Sik3Colors.statusPassed;
        statusIcon = Icons.check_circle;
      case ApdStatus.needsReview:
        accent = Sik3Colors.statusReview;
        statusIcon = Icons.help_outline;
      case ApdStatus.missing:
        accent = Sik3Colors.statusMissing;
        statusIcon = Icons.cancel_outlined;
    }

    final confidencePct =
        (!result.manualOverride && result.confidence != null)
        ? ' ${(result.confidence! * 100).round()}%'
        : '';
    final subLabel = '${result.status.labelId}$confidencePct';

    return Semantics(
      button: true,
      enabled: enabled,
      label: '${item.labelId}, $subLabel, ketuk untuk ubah',
      child: AnimatedOpacity(
        duration: duration,
        curve: Sik3Motion.curve,
        opacity: enabled ? 1.0 : 0.6,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Sik3Radius.chip),
            child: AnimatedContainer(
              duration: duration,
              curve: Sik3Motion.curve,
              constraints: const BoxConstraints(
                minHeight: Sik3Spacing.minTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: Sik3Spacing.md,
                vertical: Sik3Spacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(Sik3Radius.chip),
                border: Border.all(color: accent, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ApdSvgIcon(item: item, size: 20, color: accent),
                  const SizedBox(width: Sik3Spacing.sm),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.labelId,
                          style: const TextStyle(
                            color: Sik3Colors.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          subLabel,
                          style: Sik3Typography.tabular(
                            TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Sik3Spacing.sm),
                  Icon(statusIcon, size: 17, color: accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomDraftActionBar extends StatelessWidget {
  const _BottomDraftActionBar({
    required this.busy,
    required this.onExportPdf,
    required this.onScanStudent,
  });

  final bool busy;
  final VoidCallback onExportPdf;
  final VoidCallback onScanStudent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Sik3Colors.cardSurface,
        border: Border(top: BorderSide(color: Sik3Colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Sik3Spacing.md),
          child: Center(
            heightFactor: 1.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 4,
                    child: OutlinedButton(
                      key: const ValueKey<String>('export_pdf_button'),
                      onPressed: busy ? null : onExportPdf,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Sik3Spacing.sm + 2,
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.picture_as_pdf_outlined, size: 20),
                            SizedBox(width: 6),
                            Text('Ekspor PDF'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Sik3Spacing.sm + 2),
                  Expanded(
                    flex: 5,
                    child: FilledButton(
                      key: const ValueKey<String>('scan_student_button'),
                      onPressed: busy ? null : onScanStudent,
                      style: FilledButton.styleFrom(
                        backgroundColor: Sik3Colors.amber,
                        foregroundColor: Sik3Colors.navy,
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Sik3Spacing.sm + 2,
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.qr_code_scanner_outlined, size: 20),
                            SizedBox(width: 6),
                            Text('Scan Siswa'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EvidencePhotoViewerSheet extends StatelessWidget {
  const _EvidencePhotoViewerSheet({required this.record});

  final ScanRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
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
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Foto Bukti — ${record.studentName}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Sik3Colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'No. ${record.attendanceNo} · NISN ${record.nisn}',
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
                tooltip: 'Tutup',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: Sik3Spacing.md),
          if (record.upperPhotoPath != null) ...<Widget>[
            _ZonePhotoPreviewCard(
              title: 'Zona Atas (Badan, Kepala & Tangan)',
              filePath: record.upperPhotoPath!,
            ),
            const SizedBox(height: Sik3Spacing.md),
          ],
          if (record.lowerPhotoPath != null)
            _ZonePhotoPreviewCard(
              title: 'Zona Bawah (Kaki & Sepatu Bengkel)',
              filePath: record.lowerPhotoPath!,
            ),
          if (record.upperPhotoPath == null && record.lowerPhotoPath == null)
            Container(
              padding: const EdgeInsets.all(Sik3Spacing.lg),
              decoration: BoxDecoration(
                color: Sik3Colors.surfaceLight,
                borderRadius: BorderRadius.circular(Sik3Radius.cardInner),
                border: Border.all(color: Sik3Colors.border),
              ),
              child: const Text(
                'Tidak ada foto bukti tersimpan untuk siswa ini.',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
      ),
    );
  }
}

class _ZonePhotoPreviewCard extends StatefulWidget {
  const _ZonePhotoPreviewCard({
    required this.title,
    required this.filePath,
  });

  final String title;
  final String filePath;

  @override
  State<_ZonePhotoPreviewCard> createState() => _ZonePhotoPreviewCardState();
}

class _ZonePhotoPreviewCardState extends State<_ZonePhotoPreviewCard> {
  Uint8List? _bytes;
  bool _loading = true;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPhotoBytes(fromInitState: true));
  }

  @override
  void didUpdateWidget(covariant _ZonePhotoPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      unawaited(_loadPhotoBytes(fromInitState: false));
    }
  }

  Future<void> _loadPhotoBytes({required bool fromInitState}) async {
    final seq = ++_loadSeq;
    if (!fromInitState && mounted) {
      setState(() {
        _loading = true;
        _bytes = null;
      });
    }

    Uint8List? loadedBytes;
    try {
      final file = File(widget.filePath);
      if (await file.exists()) {
        final raw = await file.readAsBytes();
        if (raw.isNotEmpty) {
          loadedBytes = raw;
        }
      }
    } on Object {
      loadedBytes = null;
    }

    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _bytes = loadedBytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _bytes;

    return Container(
      decoration: BoxDecoration(
        color: Sik3Colors.surfaceLight,
        borderRadius: BorderRadius.circular(Sik3Radius.cardInner),
        border: Border.all(color: Sik3Colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Sik3Spacing.md,
              vertical: Sik3Spacing.sm,
            ),
            child: Text(
              widget.title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: Sik3Colors.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_loading)
            const SizedBox(
              height: 140,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (bytes != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const _MissingPhotoPlaceholder(),
              ),
            )
          else
            const _MissingPhotoPlaceholder(),
        ],
      ),
    );
  }
}

class _MissingPhotoPlaceholder extends StatelessWidget {
  const _MissingPhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      color: Sik3Colors.surfaceLight,
      padding: const EdgeInsets.all(Sik3Spacing.lg),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.broken_image_outlined,
            size: 32,
            color: Sik3Colors.textSecondary,
          ),
          SizedBox(height: Sik3Spacing.sm),
          Text(
            'Berkas foto tidak ditemukan atau sudah dibersihkan.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Sik3Colors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _AiVerifyConfirmationDialog extends StatelessWidget {
  const _AiVerifyConfirmationDialog({
    required this.record,
    required this.requiredApd,
    required this.aiResults,
    required this.summary,
  });

  final ScanRecord record;
  final List<ApdItem> requiredApd;
  final Map<ApdItem, ApdCheckResult> aiResults;
  final String summary;

  Color _statusColor(ApdStatus status) {
    switch (status) {
      case ApdStatus.detected:
        return Sik3Colors.statusPassed;
      case ApdStatus.needsReview:
        return Sik3Colors.statusReview;
      case ApdStatus.missing:
        return Sik3Colors.statusMissing;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmedSummary = summary.trim();

    return AlertDialog(
      backgroundColor: Sik3Colors.cardSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sik3Radius.outer),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Konfirmasi Hasil Verifikasi AI',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Sik3Colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: Sik3Spacing.xs),
          Text(
            '${record.studentName} · No. ${record.attendanceNo}',
            style: Sik3Typography.tabular(
              theme.textTheme.bodySmall?.copyWith(
                    color: Sik3Colors.textSecondary,
                  ) ??
                  const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (trimmedSummary.isNotEmpty) ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(Sik3Spacing.md),
                  decoration: BoxDecoration(
                    color: Sik3Colors.navy.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(Sik3Radius.inner),
                    border: Border.all(
                      color: Sik3Colors.navy.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Text(
                    trimmedSummary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Sik3Colors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: Sik3Spacing.md),
              ],
              for (var i = 0; i < requiredApd.length; i++) ...<Widget>[
                _buildComparisonRow(context, requiredApd[i]),
                if (i < requiredApd.length - 1)
                  const SizedBox(height: Sik3Spacing.sm),
              ],
              const SizedBox(height: Sik3Spacing.md),
              Text(
                'Draft lokal hanya diperbarui setelah Anda mengetuk Terapkan Hasil AI.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Sik3Colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('cancel_apply_ai_button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const ValueKey<String>('confirm_apply_ai_button'),
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Sik3Colors.amber,
            foregroundColor: Sik3Colors.navy,
          ),
          child: const Text('Terapkan Hasil AI'),
        ),
      ],
    );
  }

  Widget _buildComparisonRow(BuildContext context, ApdItem item) {
    final theme = Theme.of(context);
    final previousStatus =
        record.apdResults[item]?.status ?? ApdStatus.needsReview;
    final aiResult =
        aiResults[item] ??
        ApdCheckResult(item: item, status: ApdStatus.needsReview);
    final accent = _statusColor(aiResult.status);
    final confidenceText = aiResult.confidence != null
        ? ' ${(aiResult.confidence! * 100).round()}%'
        : '';
    final note = aiResult.note?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(Sik3Spacing.md),
      decoration: BoxDecoration(
        color: Sik3Colors.surfaceLight,
        borderRadius: BorderRadius.circular(Sik3Radius.inner),
        border: Border.all(color: Sik3Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ApdSvgIcon(item: item, size: 20, color: accent),
              const SizedBox(width: Sik3Spacing.sm),
              Expanded(
                child: Text(
                  item.labelId,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Sik3Colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Sik3Spacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Sik3Radius.chip),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Text(
                  '${aiResult.status.labelId}$confidenceText',
                  style: Sik3Typography.tabular(
                    TextStyle(
                      color: accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sik3Spacing.xs),
          Text(
            'Sebelumnya: ${previousStatus.labelId}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Sik3Colors.textSecondary,
              fontSize: 11.5,
            ),
          ),
          if (note.isNotEmpty) ...<Widget>[
            const SizedBox(height: Sik3Spacing.xs),
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Sik3Colors.textPrimary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

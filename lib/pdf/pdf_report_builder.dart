import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/core/models/inspection_models.dart';

/// Offline A4 PDF generator for SiK3 workshop K3 inspection reports.
///
/// Produces multi-page portrait A4 reports with repeating dynamic APD table
/// headers, pure vector status markers (zero emoji / zero missing glyphs),
/// compliance summary metrics, and an unbreakable side-by-side signature block
/// for Guru Mata Pelajaran and Wali Kelas.
class PdfReportBuilder {
  const PdfReportBuilder._();

  static const PdfColor _navy = PdfColor.fromInt(0xFF0D2D4D);
  static const PdfColor _amber = PdfColor.fromInt(0xFFF59E0B);
  static const PdfColor _statusPassed = PdfColor.fromInt(0xFF15803D);
  static const PdfColor _statusReview = PdfColor.fromInt(0xFFD97706);
  static const PdfColor _statusMissing = PdfColor.fromInt(0xFFDC2626);
  static const PdfColor _surfaceTint = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor _passedBg = PdfColor.fromInt(0xFFECFDF5);
  static const PdfColor _reviewBg = PdfColor.fromInt(0xFFFFFBEB);
  static const PdfColor _missingBg = PdfColor.fromInt(0xFFFEF2F2);
  static const PdfColor _border = PdfColor.fromInt(0xFFCBD5E1);
  static const PdfColor _borderLight = PdfColor.fromInt(0xFFE2E8F0);
  static const PdfColor _textPrimary = PdfColor.fromInt(0xFF0F172A);
  static const PdfColor _textSecondary = PdfColor.fromInt(0xFF475569);

  static const List<String> _indonesianMonths = <String>[
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  /// Builds a filesystem-safe PDF filename such as
  /// `Laporan_K3_XI_TKR_1_2026-11-24.pdf`.
  static String buildFileName(SchoolClass schoolClass, DateTime sessionDate) {
    final sanitizedClass = schoolClass.name
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final classToken = sanitizedClass.isEmpty ? 'Kelas' : sanitizedClass;
    final yyyy = sessionDate.year.toString().padLeft(4, '0');
    final mm = sessionDate.month.toString().padLeft(2, '0');
    final dd = sessionDate.day.toString().padLeft(2, '0');
    return 'Laporan_K3_${classToken}_$yyyy-$mm-$dd.pdf';
  }

  /// Generates offline A4 portrait PDF report bytes for the given session.
  static Future<Uint8List> build({
    required InspectionSession session,
    required SchoolClass schoolClass,
    required List<ScanRecord> records,
    required Uint8List logoBytes,
  }) async {
    final requiredApd = session.orderedRequiredApd;
    final requiredApdSet = session.requiredApd;

    var completeCount = 0;
    var reviewCount = 0;
    var incompleteCount = 0;
    final rowStatuses = <_OverallCompliance>[];
    for (final record in records) {
      final overall = _resolveOverallStatus(record, requiredApdSet);
      rowStatuses.add(overall);
      switch (overall) {
        case _OverallCompliance.complete:
          completeCount += 1;
        case _OverallCompliance.needsReview:
          reviewCount += 1;
        case _OverallCompliance.incomplete:
          incompleteCount += 1;
      }
    }

    pw.MemoryImage? logoImage;
    if (logoBytes.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(logoBytes);
      } on Object {
        logoImage = null;
      }
    }

    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    );

    final doc = pw.Document(
      theme: theme,
      title: _safeText('Laporan K3 - ${schoolClass.name}'),
      author: _safeText(
        session.teacherName.trim().isNotEmpty ? session.teacherName : 'SiK3',
      ),
      creator: 'SiK3',
      subject: _safeText(session.subjectName),
    );

    final homeroomName = session.homeroomTeacher.trim().isNotEmpty
        ? session.homeroomTeacher.trim()
        : schoolClass.homeroomTeacher.trim();
    final homeroomNip = session.homeroomNip.trim().isNotEmpty
        ? session.homeroomNip.trim()
        : schoolClass.homeroomNip.trim();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        orientation: pw.PageOrientation.portrait,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
        maxPages: 50,
        footer: _buildFooter,
        build: (context) => <pw.Widget>[
          _buildKopHeader(
            session: session,
            logoImage: logoImage,
          ),
          pw.SizedBox(height: 10),
          _buildMetadataCard(
            session: session,
            schoolClass: schoolClass,
            homeroomName: homeroomName,
            requiredApd: requiredApd,
          ),
          pw.SizedBox(height: 12),
          _buildInspectionTable(
            records: records,
            rowStatuses: rowStatuses,
            requiredApd: requiredApd,
          ),
          if (records.isEmpty) _buildEmptyNotice(),
          pw.SizedBox(height: 8),
          _buildLegendBar(),
          pw.SizedBox(height: 10),
          // Unbreakable closing block so summary metrics and Guru Mapel /
          // Wali Kelas signatures stay together and never split across pages.
          pw.Container(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              mainAxisSize: pw.MainAxisSize.min,
              children: <pw.Widget>[
                _buildSummaryStrip(
                  totalCount: records.length,
                  completeCount: completeCount,
                  reviewCount: reviewCount,
                  incompleteCount: incompleteCount,
                ),
                pw.SizedBox(height: 16),
                _buildSignatureBlock(
                  teacherName: session.teacherName.trim(),
                  teacherNip: session.teacherNip.trim(),
                  homeroomName: homeroomName,
                  homeroomNip: homeroomNip,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildKopHeader({
    required InspectionSession session,
    required pw.MemoryImage? logoImage,
  }) {
    final schoolName = _safeText(session.schoolName.trim()).toUpperCase();

    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: <pw.Widget>[
              if (logoImage != null) ...<pw.Widget>[
                pw.SizedBox(
                  width: 46,
                  height: 46,
                  child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 12),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    if (schoolName.isNotEmpty)
                      pw.Text(
                        schoolName,
                        style: pw.TextStyle(
                          color: _navy,
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 0.4,
                        ),
                      ),
                    pw.Text(
                      'LAPORAN INSPEKSI KESELAMATAN DAN KESEHATAN KERJA (K3)',
                      style: pw.TextStyle(
                        color: _navy,
                        fontSize: 11.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Rekapitulasi Kelengkapan Alat Pelindung Diri (APD) Praktik Bengkel',
                      style: const pw.TextStyle(
                        color: _textSecondary,
                        fontSize: 8.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(height: 2.0, color: _navy),
          pw.SizedBox(height: 1.5),
          pw.Container(height: 0.8, color: _amber),
        ],
      ),
    );
  }

  static pw.Widget _buildMetadataCard({
    required InspectionSession session,
    required SchoolClass schoolClass,
    required String homeroomName,
    required List<ApdItem> requiredApd,
  }) {
    final apdSummary = requiredApd.isEmpty
        ? '-'
        : '${requiredApd.length} item (${requiredApd.map((e) => e.shortLabelId).join(', ')})';

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _surfaceTint,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: _border, width: 0.6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                _metadataRow('Kelas', schoolClass.name),
                pw.SizedBox(height: 3),
                _metadataRow('Mata Praktik', session.subjectName),
                pw.SizedBox(height: 3),
                _metadataRow('Tanggal', _formatIndonesianDate(session.sessionDate)),
              ],
            ),
          ),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                _metadataRow(
                  'Guru Mapel',
                  session.teacherName.trim().isNotEmpty
                      ? session.teacherName.trim()
                      : '-',
                ),
                pw.SizedBox(height: 3),
                _metadataRow(
                  'Wali Kelas',
                  homeroomName.isNotEmpty ? homeroomName : '-',
                ),
                pw.SizedBox(height: 3),
                _metadataRow('APD Wajib', apdSummary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _metadataRow(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.SizedBox(
          width: 62,
          child: pw.Text(
            _safeText(label),
            style: pw.TextStyle(
              color: _textSecondary,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text(
          ': ',
          style: const pw.TextStyle(color: _textSecondary, fontSize: 8),
        ),
        pw.Expanded(
          child: pw.Text(
            _safeText(value),
            style: const pw.TextStyle(color: _textPrimary, fontSize: 8),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildInspectionTable({
    required List<ScanRecord> records,
    required List<_OverallCompliance> rowStatuses,
    required List<ApdItem> requiredApd,
  }) {
    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(24),
      1: const pw.FixedColumnWidth(76),
      2: const pw.FlexColumnWidth(1),
    };
    for (var i = 0; i < requiredApd.length; i++) {
      columnWidths[3 + i] = const pw.FixedColumnWidth(34);
    }
    columnWidths[3 + requiredApd.length] = const pw.FixedColumnWidth(56);

    final rows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: _navy),
        children: <pw.Widget>[
          _headerCell('No', align: pw.TextAlign.center),
          _headerCell('Absen / NISN', align: pw.TextAlign.left),
          _headerCell('Nama Siswa', align: pw.TextAlign.left),
          for (final item in requiredApd)
            _headerCell(item.shortLabelId, align: pw.TextAlign.center),
          _headerCell('Status', align: pw.TextAlign.center),
        ],
      ),
    ];

    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      final overall = rowStatuses[i];
      final isOdd = i.isOdd;

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: isOdd ? _surfaceTint : PdfColors.white,
          ),
          children: <pw.Widget>[
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: pw.Text(
                '${i + 1}',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(color: _textPrimary, fontSize: 7.5),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisSize: pw.MainAxisSize.min,
                children: <pw.Widget>[
                  pw.Text(
                    'Abs. ${_safeText(record.attendanceNo)}',
                    style: pw.TextStyle(
                      color: _textPrimary,
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _safeText(record.nisn),
                    style: const pw.TextStyle(
                      color: _textSecondary,
                      fontSize: 6.8,
                    ),
                  ),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: pw.Text(
                _safeText(record.studentName),
                style: const pw.TextStyle(color: _textPrimary, fontSize: 8),
              ),
            ),
            for (final item in requiredApd)
              pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
                  child: _buildApdStatusVectorIcon(
                    record.apdResults[item]?.status ?? ApdStatus.needsReview,
                    size: 11,
                  ),
                ),
              ),
            pw.Center(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.5),
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: pw.BoxDecoration(
                    color: _overallBgColor(overall),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(3),
                    ),
                  ),
                  child: pw.Text(
                    overall.labelId,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      color: _overallFgColor(overall),
                      fontSize: 7.2,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.55),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: columnWidths,
      children: rows,
    );
  }

  static pw.Widget _headerCell(String text, {required pw.TextAlign align}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5.5),
      child: pw.Text(
        _safeText(text),
        textAlign: align,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _buildEmptyNotice() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: const pw.BoxDecoration(
        color: _surfaceTint,
        border: pw.Border(
          left: pw.BorderSide(color: _border, width: 0.55),
          right: pw.BorderSide(color: _border, width: 0.55),
          bottom: pw.BorderSide(color: _border, width: 0.55),
        ),
      ),
      alignment: pw.Alignment.center,
      child: pw.Text(
        'Belum ada data siswa yang diperiksa pada sesi ini.',
        style: pw.TextStyle(
          color: _textSecondary,
          fontSize: 8.5,
          fontStyle: pw.FontStyle.italic,
        ),
      ),
    );
  }

  /// Pure vector status marker drawn on `PdfGraphics` canvas (bottom-left origin,
  /// Y increasing upward) — zero emoji and zero missing Helvetica glyphs.
  static pw.Widget _buildApdStatusVectorIcon(
    ApdStatus status, {
    double size = 11,
  }) {
    return pw.CustomPaint(
      size: PdfPoint(size, size),
      painter: (PdfGraphics canvas, PdfPoint dims) {
        final w = dims.x;
        final h = dims.y;

        switch (status) {
          case ApdStatus.detected:
            canvas
              ..setStrokeColor(_statusPassed)
              ..setLineWidth(1.65)
              ..setLineCap(PdfLineCap.round)
              ..setLineJoin(PdfLineJoin.round)
              ..moveTo(w * 0.16, h * 0.50)
              ..lineTo(w * 0.42, h * 0.22)
              ..lineTo(w * 0.85, h * 0.78)
              ..strokePath();
          case ApdStatus.needsReview:
            // Outer amber circle ring.
            canvas
              ..setStrokeColor(_statusReview)
              ..setLineWidth(0.85)
              ..drawEllipse(w * 0.50, h * 0.50, w * 0.44, h * 0.44)
              ..strokePath();
            // Vector question mark hook (top curves right-down to stem).
            canvas
              ..setStrokeColor(_statusReview)
              ..setLineWidth(1.2)
              ..setLineCap(PdfLineCap.round)
              ..setLineJoin(PdfLineJoin.round)
              ..moveTo(w * 0.35, h * 0.65)
              ..curveTo(
                w * 0.35,
                h * 0.83,
                w * 0.67,
                h * 0.83,
                w * 0.67,
                h * 0.65,
              )
              ..curveTo(
                w * 0.67,
                h * 0.53,
                w * 0.50,
                h * 0.51,
                w * 0.50,
                h * 0.40,
              )
              ..strokePath();
            // Vector question mark dot.
            canvas
              ..setFillColor(_statusReview)
              ..drawEllipse(w * 0.50, h * 0.24, w * 0.07, h * 0.07)
              ..fillPath();
          case ApdStatus.missing:
            canvas
              ..setStrokeColor(_statusMissing)
              ..setLineWidth(1.65)
              ..setLineCap(PdfLineCap.round)
              ..moveTo(w * 0.22, h * 0.22)
              ..lineTo(w * 0.78, h * 0.78)
              ..moveTo(w * 0.22, h * 0.78)
              ..lineTo(w * 0.78, h * 0.22)
              ..strokePath();
        }
      },
    );
  }

  static pw.Widget _buildLegendBar() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: pw.BoxDecoration(
        color: _surfaceTint,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
        border: pw.Border.all(color: _borderLight, width: 0.6),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Text(
            'Keterangan Simbol:',
            style: pw.TextStyle(
              color: _textSecondary,
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(width: 10),
          _legendItem(ApdStatus.detected, 'Lengkap / Terdeteksi'),
          pw.SizedBox(width: 12),
          _legendItem(ApdStatus.needsReview, 'Perlu Cek'),
          pw.SizedBox(width: 12),
          _legendItem(ApdStatus.missing, 'Kurang / Tidak Terdeteksi'),
        ],
      ),
    );
  }

  static pw.Widget _legendItem(ApdStatus status, String label) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        _buildApdStatusVectorIcon(status, size: 9.5),
        pw.SizedBox(width: 4),
        pw.Text(
          label,
          style: const pw.TextStyle(color: _textPrimary, fontSize: 7.5),
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryStrip({
    required int totalCount,
    required int completeCount,
    required int reviewCount,
    required int incompleteCount,
  }) {
    return pw.Container(
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(
            child: _summaryTile(
              label: 'Total Siswa',
              count: totalCount,
              accent: _navy,
              background: _surfaceTint,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _summaryTile(
              label: 'Lengkap K3',
              count: completeCount,
              accent: _statusPassed,
              background: _passedBg,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _summaryTile(
              label: 'Perlu Cek',
              count: reviewCount,
              accent: _statusReview,
              background: _reviewBg,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _summaryTile(
              label: 'Kurang K3',
              count: incompleteCount,
              accent: _statusMissing,
              background: _missingBg,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryTile({
    required String label,
    required int count,
    required PdfColor accent,
    required PdfColor background,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: _border, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisSize: pw.MainAxisSize.min,
        children: <pw.Widget>[
          pw.Text(
            '$count',
            style: pw.TextStyle(
              color: accent,
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 1.5),
          pw.Text(
            label,
            style: const pw.TextStyle(color: _textSecondary, fontSize: 7.5),
          ),
        ],
      ),
    );
  }

  /// Unbreakable side-by-side signature container so Guru Mata Pelajaran &
  /// Wali Kelas signatures never split across page boundaries.
  static pw.Widget _buildSignatureBlock({
    required String teacherName,
    required String teacherNip,
    required String homeroomName,
    required String homeroomNip,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: _signatureColumn(
              prefix: 'Diperiksa oleh,',
              roleTitle: 'Guru Mata Pelajaran',
              personName: teacherName.isNotEmpty ? teacherName : '-',
              nip: teacherNip,
            ),
          ),
          pw.SizedBox(width: 36),
          pw.Expanded(
            child: _signatureColumn(
              prefix: 'Mengetahui,',
              roleTitle: 'Wali Kelas',
              personName: homeroomName.isNotEmpty ? homeroomName : '-',
              nip: homeroomNip,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatureColumn({
    required String prefix,
    required String roleTitle,
    required String personName,
    required String nip,
  }) {
    final cleanNip = _safeText(nip.trim());
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        pw.Text(
          prefix,
          style: const pw.TextStyle(color: _textSecondary, fontSize: 8),
        ),
        pw.SizedBox(height: 1),
        pw.Text(
          roleTitle,
          style: pw.TextStyle(
            color: _navy,
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 44),
        pw.Container(width: 170, height: 0.7, color: _textPrimary),
        pw.SizedBox(height: 4),
        pw.Text(
          _safeText(personName),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            color: _textPrimary,
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (cleanNip.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 1.5),
          pw.Text(
            'NIP. $cleanNip',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(color: _textSecondary, fontSize: 7.5),
          ),
        ],
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _borderLight, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            'SiK3 - Laporan Inspeksi K3 Bengkel',
            style: const pw.TextStyle(color: _textSecondary, fontSize: 7.5),
          ),
          pw.Text(
            'Halaman ${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(
              color: _textSecondary,
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static _OverallCompliance _resolveOverallStatus(
    ScanRecord record,
    Set<ApdItem> requiredApd,
  ) {
    var hasNeedsReview = false;
    for (final item in requiredApd) {
      final status = record.apdResults[item]?.status ?? ApdStatus.needsReview;
      if (status == ApdStatus.missing) {
        return _OverallCompliance.incomplete;
      }
      if (status == ApdStatus.needsReview) {
        hasNeedsReview = true;
      }
    }
    return hasNeedsReview
        ? _OverallCompliance.needsReview
        : _OverallCompliance.complete;
  }

  static PdfColor _overallFgColor(_OverallCompliance status) {
    switch (status) {
      case _OverallCompliance.complete:
        return _statusPassed;
      case _OverallCompliance.needsReview:
        return _statusReview;
      case _OverallCompliance.incomplete:
        return _statusMissing;
    }
  }

  static PdfColor _overallBgColor(_OverallCompliance status) {
    switch (status) {
      case _OverallCompliance.complete:
        return _passedBg;
      case _OverallCompliance.needsReview:
        return _reviewBg;
      case _OverallCompliance.incomplete:
        return _missingBg;
    }
  }

  static String _formatIndonesianDate(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = _indonesianMonths[dateTime.month - 1];
    final year = dateTime.year.toString().padLeft(4, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day $month $year, $hour:$minute';
  }

  /// Normalizes user strings into WinAnsi-safe text for built-in Helvetica so
  /// PDF generation never drops glyphs or leaks emoji characters.
  static String _safeText(String raw) {
    if (raw.isEmpty) return '';
    final normalized = raw
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2026', '...')
        .replaceAll('\u00A0', ' ');

    final out = StringBuffer();
    for (final rune in normalized.runes) {
      if ((rune >= 0x20 && rune <= 0x7E) || (rune >= 0xA0 && rune <= 0xFF)) {
        out.writeCharCode(rune);
      } else if (rune == 0x09 || rune == 0x0A || rune == 0x0D) {
        out.write(' ');
      }
    }
    return out.toString();
  }
}

enum _OverallCompliance {
  complete('Lengkap'),
  needsReview('Perlu Cek'),
  incomplete('Kurang');

  const _OverallCompliance(this.labelId);

  final String labelId;
}

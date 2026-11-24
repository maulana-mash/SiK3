import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:sik3/core/models/inspection_models.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/pdf/pdf_report_builder.dart';

/// Offline A4 PDF preview screen with native Android print and share actions.
class PdfPreviewScreen extends StatelessWidget {
  const PdfPreviewScreen({
    super.key,
    required this.schoolClass,
    required this.session,
    required this.records,
    required this.logoBytes,
  });

  final SchoolClass schoolClass;
  final InspectionSession session;
  final List<ScanRecord> records;
  final Uint8List logoBytes;

  @override
  Widget build(BuildContext context) {
    final fileName = PdfReportBuilder.buildFileName(
      schoolClass,
      session.sessionDate,
    );

    return Scaffold(
      backgroundColor: Sik3Colors.surfaceLight,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Pratinjau Laporan K3',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${schoolClass.name} (${records.length} siswa)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Sik3Typography.tabular(
                const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: PdfPreview(
          initialPageFormat: PdfPageFormat.a4,
          pdfFileName: fileName,
          allowPrinting: true,
          allowSharing: true,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          dynamicLayout: false,
          maxPageWidth: 700,
          shareActionExtraSubject: 'Laporan Inspeksi K3 - ${schoolClass.name}',
          scrollViewDecoration: const BoxDecoration(
            color: Sik3Colors.surfaceLight,
          ),
          actionBarTheme: const PdfActionBarTheme(
            backgroundColor: Sik3Colors.navy,
            iconColor: Colors.white,
            elevation: 0,
          ),
          build: (_) => PdfReportBuilder.build(
            session: session,
            schoolClass: schoolClass,
            records: records,
            logoBytes: logoBytes,
          ),
          loadingWidget: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(color: Sik3Colors.navy),
                SizedBox(height: Sik3Spacing.md),
                Text(
                  'Menyusun dokumen PDF A4...',
                  style: TextStyle(
                    color: Sik3Colors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          onPrintError: (context, _) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text(
                    'Gagal membuka layanan cetak perangkat. Coba bagikan berkas PDF.',
                  ),
                  backgroundColor: Sik3Colors.statusMissing,
                ),
              );
          },
          onError: (context, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(Sik3Spacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 40,
                    color: Sik3Colors.statusMissing,
                  ),
                  const SizedBox(height: Sik3Spacing.md),
                  Text(
                    'Pratinjau PDF tidak dapat ditampilkan',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Sik3Colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Sik3Spacing.xs),
                  const Text(
                    'Anda tetap dapat mencetak atau membagikan berkas PDF dari tombol aksi di bawah.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Sik3Colors.textSecondary,
                      fontSize: 13,
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

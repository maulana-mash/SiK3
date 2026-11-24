import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/data/local_prefs.dart';
import 'package:sik3/data/qr_identity_codec.dart';

/// Student offline profile form and high-contrast QR Identity Card screen.
class StudentQrScreen extends StatefulWidget {
  const StudentQrScreen({
    super.key,
    required this.prefs,
    required this.onSwitchRole,
  });

  final LocalPrefs prefs;
  final VoidCallback onSwitchRole;

  @override
  State<StudentQrScreen> createState() => _StudentQrScreenState();
}

class _StudentQrScreenState extends State<StudentQrScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _nisnController;
  late final TextEditingController _absenController;
  late final TextEditingController _classController;
  late final TextEditingController _majorController;

  StudentIdentity? _savedStudent;
  bool _isEditing = true;
  bool _submittedOnce = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _savedStudent = widget.prefs.getStudentProfile();
    _isEditing = _savedStudent == null;

    _nameController = TextEditingController(text: _savedStudent?.name ?? '');
    _nisnController = TextEditingController(text: _savedStudent?.nisn ?? '');
    _absenController = TextEditingController(
      text: _savedStudent?.attendanceNo ?? '',
    );
    _classController = TextEditingController(
      text: _savedStudent?.className ?? '',
    );
    _majorController = TextEditingController(text: _savedStudent?.major ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nisnController.dispose();
    _absenController.dispose();
    _classController.dispose();
    _majorController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    setState(() => _submittedOnce = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final identity = StudentIdentity(
        nisn: _nisnController.text.trim(),
        attendanceNo: _absenController.text.trim(),
        name: _nameController.text.trim(),
        className: _classController.text.trim(),
        major: _majorController.text.trim(),
      );
      await widget.prefs.saveStudentProfile(identity);
      if (mounted) {
        setState(() {
          _savedStudent = identity;
          _isEditing = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _startEditing() {
    final student = _savedStudent;
    if (student != null) {
      _nameController.text = student.name;
      _nisnController.text = student.nisn;
      _absenController.text = student.attendanceNo;
      _classController.text = student.className;
      _majorController.text = student.major;
    }
    setState(() {
      _isEditing = true;
      _submittedOnce = false;
    });
  }

  void _cancelEditing() {
    if (_savedStudent == null) return;
    setState(() {
      _isEditing = false;
      _submittedOnce = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final motionDuration = Sik3Motion.resolve(context, Sik3Motion.normal);

    return Scaffold(
      backgroundColor: Sik3Colors.surfaceLight,
      appBar: AppBar(
        title: const Text('Kartu QR Siswa'),
        actions: <Widget>[
          TextButton.icon(
            key: const ValueKey<String>('student_switch_role_button'),
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
              constraints: const BoxConstraints(maxWidth: 460),
              child: AnimatedSwitcher(
                duration: motionDuration,
                switchInCurve: Sik3Motion.curve,
                switchOutCurve: Sik3Motion.curve,
                child: _isEditing || _savedStudent == null
                    ? _buildProfileForm(context)
                    : _buildQrCardView(context, _savedStudent!),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileForm(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey<String>('student_profile_form_view'),
      padding: const EdgeInsets.all(Sik3Spacing.lg),
      decoration: BoxDecoration(
        color: Sik3Colors.cardSurface,
        borderRadius: BorderRadius.circular(Sik3Radius.outer),
        border: Border.all(color: Sik3Colors.border),
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: _submittedOnce
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Profil Identitas Siswa',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Sik3Colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Sik3Spacing.xs),
            Text(
              'Data disimpan lokal di perangkat ini untuk membuat Kartu QR K3 offline.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Sik3Colors.textSecondary,
              ),
            ),
            const SizedBox(height: Sik3Spacing.lg),
            TextFormField(
              key: const ValueKey<String>('student_name_field'),
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nama Lengkap',
                hintText: 'Contoh: Budi Santoso',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Nama lengkap wajib diisi.';
                }
                return null;
              },
            ),
            const SizedBox(height: Sik3Spacing.md),
            TextFormField(
              key: const ValueKey<String>('student_nisn_field'),
              controller: _nisnController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              style: Sik3Typography.tabular(const TextStyle(fontSize: 16)),
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(20),
              ],
              decoration: const InputDecoration(
                labelText: 'NISN',
                hintText: 'Contoh: 0081234567',
              ),
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) {
                  return 'NISN wajib diisi.';
                }
                if (!RegExp(r'^\d+$').hasMatch(trimmed)) {
                  return 'NISN harus berupa angka.';
                }
                return null;
              },
            ),
            const SizedBox(height: Sik3Spacing.md),
            TextFormField(
              key: const ValueKey<String>('student_absen_field'),
              controller: _absenController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              style: Sik3Typography.tabular(const TextStyle(fontSize: 16)),
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(
                labelText: 'No. Presensi',
                hintText: 'Contoh: 12',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'No. Presensi wajib diisi.';
                }
                return null;
              },
            ),
            const SizedBox(height: Sik3Spacing.md),
            TextFormField(
              key: const ValueKey<String>('student_class_field'),
              controller: _classController,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Kelas',
                hintText: 'Contoh: XI TKR 1',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Kelas wajib diisi.';
                }
                return null;
              },
            ),
            const SizedBox(height: Sik3Spacing.md),
            TextFormField(
              key: const ValueKey<String>('student_major_field'),
              controller: _majorController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _saveProfile(),
              decoration: const InputDecoration(
                labelText: 'Jurusan',
                hintText: 'Contoh: Teknik Kendaraan Ringan',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Jurusan wajib diisi.';
                }
                return null;
              },
            ),
            const SizedBox(height: Sik3Spacing.xl),
            FilledButton(
              key: const ValueKey<String>('student_save_button'),
              onPressed: _saving ? null : _saveProfile,
              style: FilledButton.styleFrom(
                backgroundColor: Sik3Colors.amber,
                foregroundColor: Sik3Colors.navy,
              ),
              child: const Text('Simpan & Buat Kartu QR'),
            ),
            if (_savedStudent != null) ...<Widget>[
              const SizedBox(height: Sik3Spacing.sm),
              OutlinedButton(
                onPressed: _saving ? null : _cancelEditing,
                child: const Text('Batal Edit'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQrCardView(BuildContext context, StudentIdentity student) {
    final theme = Theme.of(context);
    final payload = QrIdentityCodec.encode(student);

    return Column(
      key: const ValueKey<String>('student_qr_card_view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: Sik3Colors.cardSurface,
            borderRadius: BorderRadius.circular(Sik3Radius.outer),
            border: Border.all(color: Sik3Colors.navy, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                color: Sik3Colors.navy,
                padding: const EdgeInsets.symmetric(
                  horizontal: Sik3Spacing.lg,
                  vertical: Sik3Spacing.md,
                ),
                child: Row(
                  children: <Widget>[
                    Image.asset(
                      'assets/icons/logo_sik3_transparent.png',
                      width: 28,
                      height: 28,
                      semanticLabel: 'Logo SiK3',
                    ),
                    const SizedBox(width: Sik3Spacing.sm),
                    Expanded(
                      child: Text(
                        'KARTU IDENTITAS K3',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Sik3Spacing.sm,
                        vertical: Sik3Spacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: Sik3Colors.amber,
                        borderRadius: BorderRadius.circular(Sik3Radius.chip),
                      ),
                      child: Text(
                        student.className,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Sik3Colors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Sik3Spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final qrSize = math.max(
                          168.0,
                          math.min(240.0, constraints.maxWidth - 32),
                        );
                        return Center(
                          child: Container(
                            padding: const EdgeInsets.all(Sik3Spacing.sm),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(
                                Sik3Radius.inner,
                              ),
                              border: Border.all(
                                color: Sik3Colors.textPrimary,
                                width: 1.5,
                              ),
                            ),
                            child: QrImageView(
                              data: payload,
                              version: QrVersions.auto,
                              size: qrSize,
                              errorCorrectionLevel: QrErrorCorrectLevel.M,
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.all(Sik3Spacing.lg),
                              semanticsLabel:
                                  'Kode QR Identitas ${student.name}',
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Sik3Colors.textPrimary,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Sik3Colors.textPrimary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: Sik3Spacing.md),
                    Text(
                      'Tunjukkan QR ini ke kamera guru sebelum masuk bengkel',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Sik3Colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: Sik3Spacing.lg),
                    const Divider(),
                    const SizedBox(height: Sik3Spacing.md),
                    Text(
                      student.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Sik3Colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Sik3Spacing.xs),
                    Text(
                      student.major,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Sik3Colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: Sik3Spacing.md),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _IdentityMetric(
                            label: 'NISN',
                            value: student.nisn,
                          ),
                        ),
                        const SizedBox(width: Sik3Spacing.md),
                        Expanded(
                          child: _IdentityMetric(
                            label: 'No. Presensi',
                            value: student.attendanceNo,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sik3Spacing.lg),
        OutlinedButton.icon(
          key: const ValueKey<String>('student_edit_profile_button'),
          onPressed: _startEditing,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit Profil'),
        ),
      ],
    );
  }
}

class _IdentityMetric extends StatelessWidget {
  const _IdentityMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Sik3Spacing.md,
        vertical: Sik3Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: Sik3Colors.surfaceLight,
        borderRadius: BorderRadius.circular(Sik3Radius.inner),
        border: Border.all(color: Sik3Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Sik3Colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Sik3Spacing.xs),
          Text(
            value,
            style: Sik3Typography.tabular(
              theme.textTheme.titleMedium?.copyWith(
                    color: Sik3Colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ) ??
                  const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Sik3Colors.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

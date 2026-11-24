import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/data/local_prefs.dart';

/// Offline 2-role entry gate: Teacher (protected by local 4-6 digit PIN) & Student.
class RoleGateScreen extends StatefulWidget {
  const RoleGateScreen({
    super.key,
    required this.prefs,
    required this.onRoleSelected,
  });

  final LocalPrefs prefs;
  final ValueChanged<AppRole> onRoleSelected;

  @override
  State<RoleGateScreen> createState() => _RoleGateScreenState();
}

class _RoleGateScreenState extends State<RoleGateScreen> {
  bool _busy = false;

  Future<void> _selectStudent() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.prefs.setRole(AppRole.student);
      if (mounted) {
        widget.onRoleSelected(AppRole.student);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openTeacherPinSheet() async {
    if (_busy) return;
    final hasPin = widget.prefs.hasTeacherPin();
    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Sik3Colors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Sik3Radius.outer),
        ),
      ),
      builder: (sheetContext) {
        return _TeacherPinSheet(
          prefs: widget.prefs,
          isSettingNewPin: !hasPin,
        );
      },
    );

    if (verified == true && mounted) {
      widget.onRoleSelected(AppRole.teacher);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPin = widget.prefs.hasTeacherPin();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Sik3Colors.surfaceLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: Sik3Spacing.lg,
              vertical: Sik3Spacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Image.asset(
                      'assets/icons/logo_sik3_transparent.png',
                      width: 88,
                      height: 88,
                      semanticLabel: 'Logo SiK3',
                    ),
                  ),
                  const SizedBox(height: Sik3Spacing.md),
                  Text(
                    'SiK3',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Sik3Colors.navy,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: Sik3Spacing.xs),
                  Text(
                    'Sistem Inspeksi K3 Bengkel Sekolah',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Sik3Colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Sik3Spacing.xs),
                  Text(
                    'Pilih peran di perangkat ini. Seluruh fitur inti berjalan offline.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Sik3Colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Sik3Spacing.xl),
                  _RoleActionCard(
                    key: const ValueKey<String>('role_card_teacher'),
                    title: 'Mode Guru',
                    description:
                        'Kelola kelas, pindai QR dan APD 2-zona, koreksi draft, dan ekspor PDF A4.',
                    statusText: hasPin
                        ? 'Dilindungi PIN lokal'
                        : 'Buat PIN lokal 4-6 digit saat masuk pertama',
                    icon: Icons.fact_check_outlined,
                    iconBackground: Sik3Colors.navy,
                    iconForeground: Colors.white,
                    onTap: _busy ? null : _openTeacherPinSheet,
                  ),
                  const SizedBox(height: Sik3Spacing.md),
                  _RoleActionCard(
                    key: const ValueKey<String>('role_card_student'),
                    title: 'Mode Siswa',
                    description:
                        'Isi profil lokal dan tampilkan Kartu QR Identitas untuk dipindai guru.',
                    statusText: 'Tanpa login dan tanpa koneksi internet',
                    icon: Icons.qr_code_2_outlined,
                    iconBackground: Sik3Colors.amber,
                    iconForeground: Sik3Colors.navy,
                    onTap: _busy ? null : _selectStudent,
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

class _RoleActionCard extends StatelessWidget {
  const _RoleActionCard({
    super.key,
    required this.title,
    required this.description,
    required this.statusText,
    required this.icon,
    required this.iconBackground,
    required this.iconForeground,
    required this.onTap,
  });

  final String title;
  final String description;
  final String statusText;
  final IconData icon;
  final Color iconBackground;
  final Color iconForeground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Sik3Colors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sik3Radius.outer),
        side: const BorderSide(color: Sik3Colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: Padding(
            padding: const EdgeInsets.all(Sik3Spacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(Sik3Radius.inner),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconForeground, size: 28),
                ),
                const SizedBox(width: Sik3Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Sik3Colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: Sik3Spacing.xs),
                      Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Sik3Colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: Sik3Spacing.sm),
                      Text(
                        statusText,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Sik3Colors.navy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sik3Spacing.sm),
                const Icon(
                  Icons.chevron_right,
                  color: Sik3Colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeacherPinSheet extends StatefulWidget {
  const _TeacherPinSheet({
    required this.prefs,
    required this.isSettingNewPin,
  });

  final LocalPrefs prefs;
  final bool isSettingNewPin;

  @override
  State<_TeacherPinSheet> createState() => _TeacherPinSheetState();
}

class _TeacherPinSheetState extends State<_TeacherPinSheet> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscurePin = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final pin = _pinController.text.trim();

    if (!LocalPrefs.isValidPinFormat(pin)) {
      setState(() {
        _errorText = 'PIN harus terdiri dari 4 hingga 6 digit angka.';
      });
      return;
    }

    if (widget.isSettingNewPin) {
      final confirm = _confirmController.text.trim();
      if (pin != confirm) {
        setState(() {
          _errorText = 'Konfirmasi PIN tidak sama.';
        });
        return;
      }
      setState(() {
        _submitting = true;
        _errorText = null;
      });
      try {
        await widget.prefs.setTeacherPin(pin);
        await widget.prefs.setRole(AppRole.teacher);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } finally {
        if (mounted) {
          setState(() => _submitting = false);
        }
      }
      return;
    }

    if (!widget.prefs.verifyTeacherPin(pin)) {
      setState(() {
        _errorText = 'PIN salah. Periksa kembali PIN 4-6 digit Anda.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await widget.prefs.setRole(AppRole.teacher);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final motionDuration = Sik3Motion.resolve(context, Sik3Motion.normal);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
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
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Sik3Colors.navy,
                    borderRadius: BorderRadius.circular(Sik3Radius.inner),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.lock_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: Sik3Spacing.md),
                Expanded(
                  child: Text(
                    widget.isSettingNewPin
                        ? 'Buat PIN Mode Guru'
                        : 'Masukkan PIN Mode Guru',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Sik3Colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Sik3Spacing.sm),
            Text(
              widget.isSettingNewPin
                  ? 'Masukkan 4 hingga 6 digit angka untuk mengunci akses guru secara lokal di perangkat ini.'
                  : 'Verifikasi PIN lokal Anda untuk membuka daftar kelas dan sesi inspeksi.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Sik3Colors.textSecondary,
              ),
            ),
            const SizedBox(height: Sik3Spacing.lg),
            TextField(
              key: ValueKey<String>(
                widget.isSettingNewPin ? 'pin_create_field' : 'pin_verify_field',
              ),
              controller: _pinController,
              autofocus: true,
              obscureText: _obscurePin,
              keyboardType: TextInputType.number,
              textInputAction: widget.isSettingNewPin
                  ? TextInputAction.next
                  : TextInputAction.done,
              style: Sik3Typography.tabular(const TextStyle(fontSize: 16)),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              onSubmitted: widget.isSettingNewPin ? null : (_) => _submit(),
              decoration: InputDecoration(
                labelText: widget.isSettingNewPin
                    ? 'PIN Baru (4-6 digit)'
                    : 'PIN Guru (4-6 digit)',
                suffixIcon: IconButton(
                  tooltip: _obscurePin ? 'Tampilkan PIN' : 'Sembunyikan PIN',
                  icon: Icon(
                    _obscurePin
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () {
                    setState(() => _obscurePin = !_obscurePin);
                  },
                ),
              ),
            ),
            if (widget.isSettingNewPin) ...<Widget>[
              const SizedBox(height: Sik3Spacing.md),
              TextField(
                key: const ValueKey<String>('pin_confirm_field'),
                controller: _confirmController,
                obscureText: _obscureConfirm,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                style: Sik3Typography.tabular(const TextStyle(fontSize: 16)),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (_) {
                  if (_errorText != null) {
                    setState(() => _errorText = null);
                  }
                },
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Konfirmasi PIN',
                  suffixIcon: IconButton(
                    tooltip:
                        _obscureConfirm ? 'Tampilkan PIN' : 'Sembunyikan PIN',
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscureConfirm = !_obscureConfirm);
                    },
                  ),
                ),
              ),
            ],
            AnimatedSize(
              duration: motionDuration,
              curve: Sik3Motion.curve,
              child: _errorText == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: Sik3Spacing.sm),
                      child: Text(
                        _errorText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Sik3Colors.statusMissing,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: Sik3Spacing.lg),
            FilledButton(
              key: const ValueKey<String>('pin_submit_button'),
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: Sik3Colors.amber,
                foregroundColor: Sik3Colors.navy,
              ),
              child: Text(
                widget.isSettingNewPin
                    ? 'Simpan PIN & Masuk'
                    : 'Masuk Mode Guru',
              ),
            ),
            const SizedBox(height: Sik3Spacing.sm),
            TextButton(
              onPressed:
                  _submitting ? null : () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

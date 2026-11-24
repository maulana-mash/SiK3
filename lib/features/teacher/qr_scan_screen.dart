import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/data/qr_identity_codec.dart';

typedef QrScannerViewBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onRawPayload,
);

/// Opens the offline QR student scanner screen with manual input fallback.
Future<StudentIdentity?> openStudentQrScanner(
  BuildContext context, {
  String? defaultClassName,
}) {
  return Navigator.of(context).push<StudentIdentity>(
    MaterialPageRoute<StudentIdentity>(
      builder: (_) => QrScanScreen(defaultClassName: defaultClassName),
    ),
  );
}

/// Opens a keyboard-safe modal bottom sheet to enter a student identity manually.
Future<StudentIdentity?> showManualStudentInputSheet(
  BuildContext context, {
  String? defaultClassName,
}) {
  return showModalBottomSheet<StudentIdentity>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Sik3Colors.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(Sik3Radius.outer),
      ),
    ),
    builder: (_) => _ManualStudentInputSheet(defaultClassName: defaultClassName),
  );
}

/// Offline QR identity scanner on dark `#0B192C` surface with 4-corner Navy/Amber viewfinder.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({
    super.key,
    this.defaultClassName,
    this.scannerBuilder,
    this.errorCooldown = const Duration(seconds: 2),
    this.clock,
  });

  final String? defaultClassName;
  final QrScannerViewBuilder? scannerBuilder;
  final Duration errorCooldown;
  final DateTime Function()? clock;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _completed = false;
  bool _manualSheetOpen = false;
  DateTime? _lastErrorAt;

  @override
  void initState() {
    super.initState();
    if (widget.scannerBuilder == null) {
      WidgetsBinding.instance.addObserver(this);
      _controller = MobileScannerController(
        formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.normal,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.hasCameraPermission) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        if (!_completed && !_manualSheetOpen) {
          unawaited(_safeControllerAction(controller.start));
        }
      case AppLifecycleState.inactive:
        unawaited(_safeControllerAction(controller.stop));
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  void dispose() {
    if (_controller != null) {
      WidgetsBinding.instance.removeObserver(this);
      unawaited(_controller!.dispose());
    }
    super.dispose();
  }

  Future<void> _safeControllerAction(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Camera lifecycle errors should never crash the scanner screen.
    }
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  void _handleBarcodeCapture(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue ?? barcode.displayValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _handleRawPayload(raw);
        return;
      }
    }
  }

  Future<void> _popWithIdentity(StudentIdentity identity) async {
    _completed = true;
    final controller = _controller;
    if (controller == null) {
      if (mounted) {
        Navigator.of(context).pop(identity);
      }
      return;
    }
    await _safeControllerAction(controller.stop);
    if (mounted) {
      Navigator.of(context).pop(identity);
    }
  }

  void _handleRawPayload(String rawPayload) {
    if (!mounted || _completed || _manualSheetOpen) return;

    try {
      final identity = QrIdentityCodec.decode(rawPayload);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      unawaited(_popWithIdentity(identity));
    } on QrFormatException catch (error) {
      final now = _now();
      if (_lastErrorAt != null &&
          now.difference(_lastErrorAt!) < widget.errorCooldown) {
        return;
      }
      _lastErrorAt = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: Sik3Colors.statusMissing,
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    final state = controller.value;
    if (!state.isInitialized ||
        !state.isRunning ||
        state.torchState == TorchState.unavailable) {
      return;
    }
    try {
      await controller.toggleTorch();
    } on MobileScannerException {
      // Ignore torch hardware errors gracefully.
    }
  }

  Future<void> _openManualFallback() async {
    if (!mounted || _completed || _manualSheetOpen) return;
    setState(() => _manualSheetOpen = true);

    final controller = _controller;
    if (controller != null && controller.value.isRunning) {
      await _safeControllerAction(controller.stop);
    }
    if (!mounted) return;

    StudentIdentity? manualIdentity;
    try {
      manualIdentity = await showManualStudentInputSheet(
        context,
        defaultClassName: widget.defaultClassName,
      );
    } finally {
      if (mounted) {
        setState(() => _manualSheetOpen = false);
      }
    }

    if (!mounted) return;

    if (manualIdentity != null) {
      await _popWithIdentity(manualIdentity);
      return;
    }

    if (controller != null &&
        controller.value.hasCameraPermission &&
        !_completed) {
      await _safeControllerAction(controller.start);
    }
  }

  String _describeScannerError(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Izin kamera belum diberikan. Anda tetap dapat memasukkan identitas siswa secara manual.';
      case MobileScannerErrorCode.unsupported:
        return 'Pemindai kamera tidak didukung pada perangkat ini. Gunakan input manual di bawah.';
      case MobileScannerErrorCode.controllerUninitialized:
      case MobileScannerErrorCode.controllerDisposed:
      case MobileScannerErrorCode.controllerAlreadyInitialized:
      case MobileScannerErrorCode.controllerNotAttached:
      case MobileScannerErrorCode.controllerInitializing:
      case MobileScannerErrorCode.genericError:
        return 'Kamera tidak tersedia saat ini. Gunakan tombol input manual di bawah untuk melanjutkan.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sik3Colors.scannerDark,
      appBar: AppBar(
        backgroundColor: Sik3Colors.scannerDark,
        foregroundColor: Colors.white,
        title: const Text('Pindai Kartu QR Siswa'),
        actions: <Widget>[
          _buildTorchAction(),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _buildCameraLayer(),
                  IgnorePointer(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final boxSize = math.max(
                          180.0,
                          math.min(
                            264.0,
                            math.min(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                ) *
                                0.68,
                          ),
                        );
                        return CustomPaint(
                          size: constraints.biggest,
                          painter: _QrViewfinderPainter(boxSize: boxSize),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    left: Sik3Spacing.lg,
                    right: Sik3Spacing.lg,
                    bottom: Sik3Spacing.lg,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Sik3Spacing.lg,
                            vertical: Sik3Spacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: Sik3Colors.navy.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(
                              Sik3Radius.pill,
                            ),
                            border: Border.all(
                              color: Sik3Colors.amber.withValues(alpha: 0.45),
                            ),
                          ),
                          child: const Text(
                            'Posisikan Kartu QR Identitas SiK3 di dalam bingkai',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                Sik3Spacing.lg,
                Sik3Spacing.md,
                Sik3Spacing.lg,
                Sik3Spacing.lg,
              ),
              decoration: const BoxDecoration(
                color: Sik3Colors.scannerDark,
                border: Border(
                  top: BorderSide(color: Color(0xFF1E3A5F)),
                ),
              ),
              child: FilledButton.icon(
                key: const ValueKey<String>('qr_manual_fallback_button'),
                onPressed: _openManualFallback,
                style: FilledButton.styleFrom(
                  backgroundColor: Sik3Colors.amber,
                  foregroundColor: Sik3Colors.navy,
                  minimumSize: const Size(double.infinity, 52),
                ),
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('Siswa Lupa HP? Input Manual'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTorchAction() {
    final controller = _controller;
    if (controller == null) {
      return IconButton(
        key: const ValueKey<String>('qr_torch_button'),
        tooltip: 'Lampu kilat',
        onPressed: null,
        icon: const Icon(Icons.flash_off_outlined, color: Colors.white54),
      );
    }

    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final unavailable =
            !state.isInitialized ||
            !state.isRunning ||
            state.torchState == TorchState.unavailable;
        final isOn = state.torchState == TorchState.on;

        return IconButton(
          key: const ValueKey<String>('qr_torch_button'),
          tooltip: unavailable
              ? 'Lampu kilat tidak tersedia'
              : (isOn ? 'Matikan lampu kilat' : 'Nyalakan lampu kilat'),
          onPressed: unavailable ? null : _toggleTorch,
          icon: Icon(
            isOn ? Icons.flash_on : Icons.flash_off_outlined,
            color: unavailable
                ? Colors.white38
                : (isOn ? Sik3Colors.amber : Colors.white),
          ),
        );
      },
    );
  }

  Widget _buildCameraLayer() {
    final customBuilder = widget.scannerBuilder;
    if (customBuilder != null) {
      return customBuilder(context, _handleRawPayload);
    }

    return MobileScanner(
      controller: _controller,
      fit: BoxFit.cover,
      onDetect: _handleBarcodeCapture,
      placeholderBuilder: (_) => const ColoredBox(
        color: Sik3Colors.scannerDark,
        child: Center(
          child: CircularProgressIndicator(color: Sik3Colors.amber),
        ),
      ),
      errorBuilder: (context, error) => _ScannerErrorFallback(
        message: _describeScannerError(error),
        onManualInput: _openManualFallback,
      ),
    );
  }
}

class _ScannerErrorFallback extends StatelessWidget {
  const _ScannerErrorFallback({
    required this.message,
    required this.onManualInput,
  });

  final String message;
  final VoidCallback onManualInput;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Sik3Colors.scannerDark,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Sik3Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Sik3Colors.navy,
                  borderRadius: BorderRadius.circular(Sik3Radius.inner),
                  border: Border.all(
                    color: Sik3Colors.amber.withValues(alpha: 0.6),
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.no_photography_outlined,
                  color: Sik3Colors.amber,
                  size: 28,
                ),
              ),
              const SizedBox(height: Sik3Spacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: Sik3Spacing.lg),
              OutlinedButton.icon(
                onPressed: onManualInput,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Sik3Colors.amber),
                ),
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('Input Manual Sekarang'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrViewfinderPainter extends CustomPainter {
  const _QrViewfinderPainter({required this.boxSize});

  final double boxSize;

  @override
  void paint(Canvas canvas, Size size) {
    final cutoutRect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: boxSize,
      height: boxSize,
    );
    final rrect = RRect.fromRectAndRadius(
      cutoutRect,
      const Radius.circular(Sik3Radius.outer),
    );

    final scrimPath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      scrimPath,
      Paint()..color = Sik3Colors.scannerDark.withValues(alpha: 0.64),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Sik3Colors.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    const cornerLen = 28.0;
    final cornerPaint = Paint()
      ..color = Sik3Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final left = cutoutRect.left;
    final right = cutoutRect.right;
    final top = cutoutRect.top;
    final bottom = cutoutRect.bottom;

    // Top-left bracket
    canvas.drawPath(
      Path()
        ..moveTo(left, top + cornerLen)
        ..lineTo(left, top)
        ..lineTo(left + cornerLen, top),
      cornerPaint,
    );
    // Top-right bracket
    canvas.drawPath(
      Path()
        ..moveTo(right - cornerLen, top)
        ..lineTo(right, top)
        ..lineTo(right, top + cornerLen),
      cornerPaint,
    );
    // Bottom-left bracket
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom - cornerLen)
        ..lineTo(left, bottom)
        ..lineTo(left + cornerLen, bottom),
      cornerPaint,
    );
    // Bottom-right bracket
    canvas.drawPath(
      Path()
        ..moveTo(right - cornerLen, bottom)
        ..lineTo(right, bottom)
        ..lineTo(right, bottom - cornerLen),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _QrViewfinderPainter oldDelegate) {
    return oldDelegate.boxSize != boxSize;
  }
}

class _ManualStudentInputSheet extends StatefulWidget {
  const _ManualStudentInputSheet({this.defaultClassName});

  final String? defaultClassName;

  @override
  State<_ManualStudentInputSheet> createState() =>
      _ManualStudentInputSheetState();
}

class _ManualStudentInputSheetState extends State<_ManualStudentInputSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _nisnController;
  late final TextEditingController _absenController;
  late final TextEditingController _classController;
  late final TextEditingController _majorController;

  bool _submittedOnce = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _nisnController = TextEditingController();
    _absenController = TextEditingController();
    _classController = TextEditingController(
      text: widget.defaultClassName?.trim() ?? '',
    );
    _majorController = TextEditingController();
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

  void _submit() {
    setState(() => _submittedOnce = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final identity = StudentIdentity(
      nisn: _nisnController.text.trim(),
      attendanceNo: _absenController.text.trim(),
      name: _nameController.text.trim(),
      className: _classController.text.trim(),
      major: _majorController.text.trim(),
    );
    Navigator.of(context).pop(identity);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

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
          child: Form(
            key: _formKey,
            autovalidateMode: _submittedOnce
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
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
                        Icons.person_add_alt_1_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: Sik3Spacing.md),
                    Expanded(
                      child: Text(
                        'Input Manual Identitas Siswa',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Sik3Colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Sik3Spacing.xs),
                Text(
                  'Gunakan bila siswa lupa membawa HP atau Kartu QR tidak terbaca.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Sik3Colors.textSecondary,
                  ),
                ),
                const SizedBox(height: Sik3Spacing.lg),
                TextFormField(
                  key: const ValueKey<String>('manual_student_name_field'),
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nama Lengkap',
                    hintText: 'Contoh: Bagas Pratama',
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
                  key: const ValueKey<String>('manual_student_nisn_field'),
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
                  key: const ValueKey<String>('manual_student_absen_field'),
                  controller: _absenController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  style: Sik3Typography.tabular(const TextStyle(fontSize: 16)),
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'No. Presensi',
                    hintText: 'Contoh: 14',
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
                  key: const ValueKey<String>('manual_student_class_field'),
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
                  key: const ValueKey<String>('manual_student_major_field'),
                  controller: _majorController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
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
                  key: const ValueKey<String>('manual_student_submit_button'),
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Sik3Colors.amber,
                    foregroundColor: Sik3Colors.navy,
                  ),
                  child: const Text('Gunakan Identitas Siswa'),
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
      ),
    );
  }
}

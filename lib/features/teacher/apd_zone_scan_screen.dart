import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/core/models/inspection_models.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/core/widgets/apd_svg_icon.dart';
import 'package:sik3/data/app_database.dart';
import 'package:sik3/data/qr_identity_codec.dart';
import 'package:sik3/ml/apd_evaluator.dart';
import 'package:sik3/ml/ppe_label_config.dart';
import 'package:sik3/ml/tflite_ppe_detector.dart';

typedef ZoneCameraPreviewBuilder = Widget Function(
  BuildContext context,
  ScanZone activeZone,
);

typedef ZonePhotoBytesCapturer = Future<Uint8List> Function(ScanZone activeZone);

typedef EvidenceDirectoryResolver = Future<Directory> Function();

typedef AvailableCamerasProvider = Future<List<CameraDescription>> Function();

/// Returns the ordered scan zones required by [requiredApd].
///
/// Automatically skips [ScanZone.upper] when no upper-body item is required and
/// skips [ScanZone.lower] when [ApdItem.sepatuBengkel] is not required.
List<ScanZone> resolveRequiredScanZones(Set<ApdItem> requiredApd) {
  final zones = <ScanZone>[];
  if (requiredApd.any((item) => item.scanZone == ScanZone.upper)) {
    zones.add(ScanZone.upper);
  }
  if (requiredApd.contains(ApdItem.sepatuBengkel)) {
    zones.add(ScanZone.lower);
  }
  return List<ScanZone>.unmodifiable(zones);
}

/// Decodes [rawBytes], bakes EXIF orientation, shrinks longest edge to at most
/// [maxDimension] pixels without upscaling, and encodes JPEG at [quality].
Uint8List compressEvidencePhotoBytes(
  Uint8List rawBytes, {
  int maxDimension = 800,
  int quality = 80,
}) {
  final decoded = img.decodeImage(rawBytes);
  if (decoded == null) {
    throw const FormatException('Gagal membaca data foto bukti.');
  }

  final oriented = img.bakeOrientation(decoded);
  final longestEdge = math.max(oriented.width, oriented.height);

  final img.Image outputImage;
  if (maxDimension > 0 && longestEdge > maxDimension) {
    final scale = maxDimension / longestEdge;
    final targetWidth = math.max(1, (oriented.width * scale).round());
    final targetHeight = math.max(1, (oriented.height * scale).round());
    outputImage = img.copyResize(
      oriented,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear,
    );
  } else {
    outputImage = oriented;
  }

  return Uint8List.fromList(img.encodeJpg(outputImage, quality: quality));
}

/// Opens [ApdZoneScanScreen] for a scanned/selected student in an inspection session.
Future<ScanRecord?> openApdZoneScanner(
  BuildContext context, {
  required InspectionSession session,
  required StudentIdentity student,
  required AppDatabase database,
}) {
  return Navigator.of(context).push<ScanRecord>(
    MaterialPageRoute<ScanRecord>(
      builder: (_) => ApdZoneScanScreen(
        session: session,
        student: student,
        database: database,
      ),
    ),
  );
}

/// Guided 2-zone workshop camera screen (Upper Zone -> Lower Zone) with local
/// JPEG compression, offline TFLite evaluation, and manual fallback.
class ApdZoneScanScreen extends StatefulWidget {
  const ApdZoneScanScreen({
    super.key,
    required this.session,
    required this.student,
    required this.database,
    this.detector,
    this.labelConfig,
    this.cameraPreviewBuilder,
    this.capturePhotoBytes,
    this.evidenceDirectoryResolver,
    this.availableCamerasProvider,
  });

  final InspectionSession session;
  final StudentIdentity student;
  final AppDatabase database;
  final PpeDetector? detector;
  final PpeLabelConfig? labelConfig;
  final ZoneCameraPreviewBuilder? cameraPreviewBuilder;
  final ZonePhotoBytesCapturer? capturePhotoBytes;
  final EvidenceDirectoryResolver? evidenceDirectoryResolver;
  final AvailableCamerasProvider? availableCamerasProvider;

  @override
  State<ApdZoneScanScreen> createState() => _ApdZoneScanScreenState();
}

class _ApdZoneScanScreenState extends State<ApdZoneScanScreen>
    with WidgetsBindingObserver {
  late final List<ScanZone> _zones;

  CameraController? _cameraController;
  bool _initializingCamera = false;
  bool _torchOn = false;
  String? _cameraError;

  PpeDetector? _detector;
  PpeLabelConfig? _labelConfig;
  bool _ownsDetector = false;
  bool _detectorReady = false;
  Future<void>? _detectorInitFuture;

  int _zoneIndex = 0;
  bool _isProcessing = false;
  String _processingMessage = 'Mengompresi foto & mengevaluasi APD...';
  bool _savedRecord = false;
  String? _capturedUpperPath;
  String? _capturedLowerPath;

  ScanZone get _activeZone =>
      _zones.isEmpty ? ScanZone.upper : _zones[_zoneIndex];

  bool get _hasCustomPreview => widget.cameraPreviewBuilder != null;

  bool get _cameraReady {
    if (_hasCustomPreview) return true;
    final controller = _cameraController;
    return controller != null && controller.value.isInitialized;
  }

  List<ApdItem> get _activeZoneItems => widget.session.orderedRequiredApd
      .where((item) => item.scanZone == _activeZone)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _zones = resolveRequiredScanZones(widget.session.requiredApd);
    if (widget.detector != null &&
        (widget.labelConfig != null || widget.detector is TflitePpeDetector)) {
      _detector = widget.detector;
      _ownsDetector = false;
      _labelConfig =
          widget.labelConfig ?? (widget.detector as TflitePpeDetector).labelConfig;
      _detectorReady = true;
    } else {
      _detectorInitFuture = _initDetectorAndConfig();
    }

    if (!_hasCustomPreview) {
      WidgetsBinding.instance.addObserver(this);
      _initializingCamera = true;
      unawaited(_initCamera(fromInitState: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_hasCustomPreview) return;

    if (state == AppLifecycleState.inactive) {
      final controller = _cameraController;
      if (mounted) {
        setState(() {
          _cameraController = null;
          _torchOn = false;
        });
      } else {
        _cameraController = null;
        _torchOn = false;
      }
      if (controller != null) {
        unawaited(_disposeCameraSafely(controller));
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!_savedRecord && !_initializingCamera && _cameraController == null) {
        unawaited(_initCamera());
      }
    }
  }

  @override
  void dispose() {
    if (!_hasCustomPreview) {
      WidgetsBinding.instance.removeObserver(this);
    }
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      unawaited(_disposeCameraSafely(controller));
    }
    final detector = _detector;
    _detector = null;
    if (_ownsDetector && detector != null) {
      unawaited(detector.dispose());
    }
    if (!_savedRecord) {
      unawaited(_deleteTempFileSafely(_capturedUpperPath));
      unawaited(_deleteTempFileSafely(_capturedLowerPath));
    }
    super.dispose();
  }

  Future<void> _disposeCameraSafely(CameraController controller) async {
    try {
      await controller.dispose();
    } on Object {
      // Ignore hardware disposal errors during screen teardown.
    }
  }

  Future<void> _deleteTempFileSafely(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Best-effort cleanup of abandoned evidence photo.
    }
  }

  Future<void> _initDetectorAndConfig() async {
    try {
      if (widget.detector != null) {
        _detector = widget.detector;
        _ownsDetector = false;
        if (widget.labelConfig != null) {
          _labelConfig = widget.labelConfig;
        } else if (widget.detector is TflitePpeDetector) {
          _labelConfig = (widget.detector as TflitePpeDetector).labelConfig;
        } else {
          _labelConfig = await _loadLabelConfigSafely();
        }
      } else {
        _ownsDetector = true;
        final created = await TflitePpeDetector.create(
          labelConfig: widget.labelConfig,
        );
        if (!mounted) {
          unawaited(created.dispose());
          return;
        }
        _detector = created;
        _labelConfig = widget.labelConfig ?? created.labelConfig;
      }
    } on Object {
      _labelConfig ??= const PpeLabelConfig(
        modelClassNames: <String>[],
        labelToApd: <String, ApdItem>{},
      );
    } finally {
      if (mounted) {
        setState(() {
          _detectorReady = true;
        });
      } else {
        _detectorReady = true;
      }
    }
  }

  Future<PpeLabelConfig> _loadLabelConfigSafely() async {
    try {
      return await PpeLabelConfig.loadFromAsset();
    } on Object {
      return const PpeLabelConfig(
        modelClassNames: <String>[],
        labelToApd: <String, ApdItem>{},
      );
    }
  }

  Future<void> _initCamera({bool fromInitState = false}) async {
    if (_hasCustomPreview) return;
    if (!fromInitState) {
      if (_initializingCamera) return;
      setState(() {
        _initializingCamera = true;
        _cameraError = null;
        _torchOn = false;
      });
    }

    final previous = _cameraController;
    _cameraController = null;
    if (previous != null) {
      await _disposeCameraSafely(previous);
    }

    CameraController? candidate;
    try {
      final cameras = await (widget.availableCamerasProvider ?? availableCameras)();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _initializingCamera = false;
          _cameraError =
              'Kamera tidak ditemukan pada perangkat ini. Lanjutkan penilaian manual tanpa foto.';
        });
        return;
      }

      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      candidate = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await candidate.initialize();

      try {
        await candidate.setFlashMode(FlashMode.off);
      } on Object {
        // Flash mode may be unsupported on some devices.
      }

      if (!mounted) {
        await _disposeCameraSafely(candidate);
        return;
      }

      setState(() {
        _cameraController = candidate;
        _initializingCamera = false;
        _cameraError = null;
      });
    } on CameraException catch (error) {
      if (candidate != null) {
        await _disposeCameraSafely(candidate);
      }
      if (!mounted) return;
      final code = error.code.toLowerCase();
      final denied =
          code.contains('access') ||
          code.contains('denied') ||
          code.contains('permission');
      setState(() {
        _initializingCamera = false;
        _cameraError = denied
            ? 'Izin kamera belum diberikan. Berikan izin kamera atau lanjutkan penilaian manual tanpa foto.'
            : 'Kamera gagal diinisialisasi (${error.code}). Anda tetap dapat melanjutkan penilaian manual tanpa foto.';
      });
    } on Object {
      if (candidate != null) {
        await _disposeCameraSafely(candidate);
      }
      if (!mounted) return;
      setState(() {
        _initializingCamera = false;
        _cameraError =
            'Kamera tidak tersedia pada perangkat ini. Coba lagi atau lanjutkan penilaian manual tanpa foto.';
      });
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final nextTorch = !_torchOn;
    try {
      await controller.setFlashMode(
        nextTorch ? FlashMode.torch : FlashMode.off,
      );
      if (mounted) {
        setState(() => _torchOn = nextTorch);
      }
    } on Object {
      _showSnackBar('Lampu kilat tidak didukung pada kamera ini.');
    }
  }

  void _showSnackBar(
    String message, {
    Color backgroundColor = Sik3Colors.navy,
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: duration,
          action: action,
        ),
      );
  }

  Future<String> _saveCompressedEvidenceFile(
    Uint8List rawBytes,
    ScanZone zone,
  ) async {
    final compressed = compressEvidencePhotoBytes(rawBytes);
    final baseDir =
        await (widget.evidenceDirectoryResolver ??
            getApplicationDocumentsDirectory)();
    final sessionId = widget.session.id ?? 0;
    final sessionDir = Directory(
      p.join(baseDir.path, 'sik3_evidence', 'session_$sessionId'),
    );
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }

    final safeNisn = widget.student.nisn.replaceAll(
      RegExp(r'[^0-9A-Za-z_-]'),
      '_',
    );
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(
      sessionDir.path,
      '${safeNisn}_${zone.name}_$timestamp.jpg',
    );
    await File(filePath).writeAsBytes(compressed, flush: true);
    return filePath;
  }

  Future<void> _captureActiveZone() async {
    if (_isProcessing || _savedRecord) return;
    if (_zones.isEmpty) {
      await _continueManualWithoutPhoto();
      return;
    }
    if (widget.capturePhotoBytes == null && !_cameraReady) return;

    final currentZone = _activeZone;
    setState(() {
      _isProcessing = true;
      _processingMessage = currentZone == ScanZone.upper
          ? 'Menyimpan foto Zona Atas...'
          : 'Menyimpan foto Zona Bawah...';
    });

    try {
      Uint8List rawBytes;
      if (widget.capturePhotoBytes != null) {
        rawBytes = await widget.capturePhotoBytes!(currentZone);
      } else {
        final controller = _cameraController;
        if (controller == null || !controller.value.isInitialized) {
          throw StateError('Kamera belum siap.');
        }
        final captured = await controller.takePicture();
        rawBytes = await captured.readAsBytes();
        // Best-effort cleanup of raw unresized camera cache file.
        unawaited(_deleteTempFileSafely(captured.path));
      }

      final savedPath = await _saveCompressedEvidenceFile(rawBytes, currentZone);
      if (!mounted) {
        unawaited(_deleteTempFileSafely(savedPath));
        return;
      }

      if (currentZone == ScanZone.upper) {
        final previous = _capturedUpperPath;
        _capturedUpperPath = savedPath;
        if (previous != null && previous != savedPath) {
          unawaited(_deleteTempFileSafely(previous));
        }
      } else {
        final previous = _capturedLowerPath;
        _capturedLowerPath = savedPath;
        if (previous != null && previous != savedPath) {
          unawaited(_deleteTempFileSafely(previous));
        }
      }

      if (_zoneIndex + 1 < _zones.length) {
        setState(() {
          _zoneIndex += 1;
          _isProcessing = false;
        });
        return;
      }

      await _evaluateAndSave(usePhotos: true);
    } on Object {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnackBar(
        'Gagal mengambil foto. Coba lagi atau gunakan penilaian manual tanpa foto.',
        backgroundColor: Sik3Colors.statusMissing,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Manual',
          textColor: Sik3Colors.amber,
          onPressed: _continueManualWithoutPhoto,
        ),
      );
    }
  }

  Future<void> _retakeUpperZone() async {
    if (_isProcessing || _zoneIndex == 0) return;
    setState(() {
      _zoneIndex = 0;
    });
  }

  Future<void> _continueManualWithoutPhoto() async {
    if (_isProcessing || _savedRecord) return;
    setState(() {
      _isProcessing = true;
      _processingMessage = 'Menyiapkan lembar penilaian manual...';
    });
    await _evaluateAndSave(usePhotos: false);
  }

  Future<void> _evaluateAndSave({required bool usePhotos}) async {
    final sessionId = widget.session.id;
    if (sessionId == null) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _showSnackBar(
          'Sesi inspeksi belum tersimpan di basis data.',
          backgroundColor: Sik3Colors.statusMissing,
        );
      }
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _processingMessage = usePhotos
              ? 'Mengevaluasi APD & menyimpan ke draft...'
              : 'Menyimpan draft penilaian manual...';
        });
      }

      if (_detectorInitFuture != null) {
        await _detectorInitFuture;
      }

      final detector = _detector;
      final config =
          _labelConfig ??
          const PpeLabelConfig(
            modelClassNames: <String>[],
            labelToApd: <String, ApdItem>{},
          );
      final modelAvailable = usePhotos && (detector?.isModelLoaded ?? false);

      List<RawDetection> upperDetections = const <RawDetection>[];
      List<RawDetection> lowerDetections = const <RawDetection>[];

      if (modelAvailable) {
        if (_capturedUpperPath != null) {
          upperDetections = await detector!.detectFile(_capturedUpperPath!);
        }
        if (_capturedLowerPath != null) {
          lowerDetections = await detector!.detectFile(_capturedLowerPath!);
        }
      }

      final apdResults = ApdEvaluator.evaluate(
        upperDetections: upperDetections,
        lowerDetections: lowerDetections,
        requiredItems: widget.session.requiredApd,
        config: config,
        threshold: config.confidenceThreshold,
        modelAvailable: modelAvailable,
      );

      String? upperPath = _capturedUpperPath;
      String? lowerPath = _capturedLowerPath;
      if (!usePhotos) {
        unawaited(_deleteTempFileSafely(upperPath));
        unawaited(_deleteTempFileSafely(lowerPath));
        _capturedUpperPath = null;
        _capturedLowerPath = null;
        upperPath = null;
        lowerPath = null;
      }

      final record = ScanRecord(
        sessionId: sessionId,
        nisn: widget.student.nisn,
        attendanceNo: widget.student.attendanceNo,
        studentName: widget.student.name,
        apdResults: apdResults,
        upperPhotoPath: upperPath,
        lowerPhotoPath: lowerPath,
        isManualOverride: false,
        isAiVerified: false,
        scannedAt: DateTime.now(),
      );

      final savedId = await widget.database.upsertScanRecord(record);
      _savedRecord = true;

      if (!mounted) return;
      Navigator.of(context).pop(record.copyWith(id: savedId));
    } on Object {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnackBar(
        'Gagal menyimpan hasil inspeksi ke draft lokal. Silakan coba lagi.',
        backgroundColor: Sik3Colors.statusMissing,
      );
    }
  }

  String _zonePrompt(ScanZone zone) {
    return zone == ScanZone.upper
        ? 'Arahkan ke badan atas — angkat kedua tangan di depan dada'
        : 'Arahkan ke area kaki & sepatu bengkel';
  }

  String _captureButtonLabel() {
    if (_zones.isEmpty) return 'Lanjut Penilaian Manual';
    final isLast = _zoneIndex + 1 >= _zones.length;
    if (_activeZone == ScanZone.upper) {
      return isLast ? 'Ambil Foto & Proses' : 'Ambil Foto Zona Atas (1/2)';
    }
    return _zones.length > 1
        ? 'Ambil Foto Zona Bawah (2/2)'
        : 'Ambil Foto & Proses';
  }

  @override
  Widget build(BuildContext context) {
    final totalSteps = math.max(1, _zones.length);
    final currentStep = math.min(_zoneIndex + 1, totalSteps);
    final modelUnavailable =
        _detectorReady && !(_detector?.isModelLoaded ?? false);
    final motionDuration = Sik3Motion.resolve(context, Sik3Motion.fast);

    return PopScope(
      canPop: !_isProcessing,
      child: Scaffold(
        backgroundColor: Sik3Colors.scannerDark,
      appBar: AppBar(
        backgroundColor: Sik3Colors.scannerDark,
        foregroundColor: Colors.white,
        title: const Text('Inspeksi 2-Zona APD'),
        actions: <Widget>[
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: Sik3Spacing.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: Sik3Spacing.sm,
                vertical: Sik3Spacing.xs,
              ),
              decoration: BoxDecoration(
                color: Sik3Colors.navy,
                borderRadius: BorderRadius.circular(Sik3Radius.chip),
                border: Border.all(
                  color: Sik3Colors.amber.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                'Zona $currentStep/$totalSteps',
                style: Sik3Typography.tabular(
                  const TextStyle(
                    color: Sik3Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          if (!_hasCustomPreview && _cameraReady)
            IconButton(
              key: const ValueKey<String>('zone_torch_button'),
              tooltip: _torchOn ? 'Matikan lampu kilat' : 'Nyalakan lampu kilat',
              onPressed: _isProcessing ? null : _toggleTorch,
              icon: Icon(
                _torchOn ? Icons.flash_on : Icons.flash_off_outlined,
                color: _torchOn ? Sik3Colors.amber : Colors.white,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildStudentIdentityStrip(modelUnavailable: modelUnavailable),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _buildCameraCanvas(),
                  if (_cameraReady && _cameraError == null)
                    IgnorePointer(
                      child: AnimatedSwitcher(
                        duration: motionDuration,
                        switchInCurve: Sik3Motion.curve,
                        switchOutCurve: Sik3Motion.curve,
                        child: CustomPaint(
                          key: ValueKey<ScanZone>(_activeZone),
                          size: Size.infinite,
                          painter: _ZoneSilhouettePainter(zone: _activeZone),
                        ),
                      ),
                    ),
                  if (_cameraReady && _cameraError == null)
                    Positioned(
                      left: Sik3Spacing.lg,
                      right: Sik3Spacing.lg,
                      bottom: Sik3Spacing.md,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Sik3Spacing.lg,
                              vertical: Sik3Spacing.sm,
                            ),
                            decoration: BoxDecoration(
                              color: Sik3Colors.navy.withValues(alpha: 0.90),
                              borderRadius: BorderRadius.circular(
                                Sik3Radius.pill,
                              ),
                              border: Border.all(
                                color: Sik3Colors.amber.withValues(alpha: 0.55),
                              ),
                            ),
                            child: Text(
                              _zonePrompt(_activeZone),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_isProcessing)
                    ColoredBox(
                      color: Sik3Colors.scannerDark.withValues(alpha: 0.82),
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.all(Sik3Spacing.xl),
                          padding: const EdgeInsets.all(Sik3Spacing.lg),
                          decoration: BoxDecoration(
                            color: Sik3Colors.navy,
                            borderRadius: BorderRadius.circular(
                              Sik3Radius.outer,
                            ),
                            border: Border.all(
                              color: Sik3Colors.amber.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const CircularProgressIndicator(
                                color: Sik3Colors.amber,
                              ),
                              const SizedBox(height: Sik3Spacing.md),
                              Text(
                                _processingMessage,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_cameraReady && _cameraError == null) _buildBottomControls(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildStudentIdentityStrip({required bool modelUnavailable}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        Sik3Spacing.lg,
        Sik3Spacing.sm,
        Sik3Spacing.lg,
        Sik3Spacing.md,
      ),
      decoration: const BoxDecoration(
        color: Sik3Colors.scannerDark,
        border: Border(bottom: BorderSide(color: Color(0xFF1E3A5F))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
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
                  'No. ${widget.student.attendanceNo}',
                  style: Sik3Typography.tabular(
                    const TextStyle(
                      color: Sik3Colors.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Sik3Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.student.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'NISN ${widget.student.nisn}',
                      style: Sik3Typography.tabular(
                        const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (modelUnavailable) ...<Widget>[
            const SizedBox(height: Sik3Spacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: Sik3Spacing.md,
                vertical: Sik3Spacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: Sik3Colors.statusReview.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(Sik3Radius.chip),
                border: Border.all(
                  color: Sik3Colors.amber.withValues(alpha: 0.5),
                ),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Sik3Colors.amber,
                  ),
                  SizedBox(width: Sik3Spacing.sm),
                  Expanded(
                    child: Text(
                      'Deteksi offline belum aktif — ceklis ditandai Perlu Cek',
                      style: TextStyle(
                        color: Color(0xFFFEF3C7),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraCanvas() {
    if (_hasCustomPreview) {
      return widget.cameraPreviewBuilder!(context, _activeZone);
    }

    if (_initializingCamera) {
      return const ColoredBox(
        color: Sik3Colors.scannerDark,
        child: Center(
          child: CircularProgressIndicator(color: Sik3Colors.amber),
        ),
      );
    }

    if (_cameraError != null) {
      return _buildCameraRecoveryCard(_cameraError!);
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return _buildCameraRecoveryCard(
        'Kamera belum siap digunakan. Coba lagi atau lanjutkan penilaian manual tanpa foto.',
      );
    }

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height ?? 720,
          height: controller.value.previewSize?.width ?? 1280,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildCameraRecoveryCard(String message) {
    return ColoredBox(
      color: Sik3Colors.scannerDark,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Sik3Spacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(Sik3Spacing.lg),
              decoration: BoxDecoration(
                color: Sik3Colors.navy,
                borderRadius: BorderRadius.circular(Sik3Radius.outer),
                border: Border.all(
                  color: Sik3Colors.amber.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Sik3Colors.scannerDark,
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
                  ),
                  const SizedBox(height: Sik3Spacing.md),
                  const Text(
                    'Kamera Tidak Tersedia',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Sik3Spacing.sm),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: Sik3Spacing.lg),
                  FilledButton.icon(
                    key: const ValueKey<String>('manual_without_photo_button'),
                    onPressed:
                        _isProcessing ? null : _continueManualWithoutPhoto,
                    style: FilledButton.styleFrom(
                      backgroundColor: Sik3Colors.amber,
                      foregroundColor: Sik3Colors.navy,
                      minimumSize: const Size(double.infinity, 52),
                    ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Lanjut Penilaian Manual Tanpa Foto'),
                  ),
                  const SizedBox(height: Sik3Spacing.sm),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('retry_camera_button'),
                    onPressed: _isProcessing ? null : _initCamera,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF334155)),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final activeItems = _activeZoneItems;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        Sik3Spacing.lg,
        Sik3Spacing.md,
        Sik3Spacing.lg,
        Sik3Spacing.lg,
      ),
      decoration: const BoxDecoration(
        color: Sik3Colors.scannerDark,
        border: Border(top: BorderSide(color: Color(0xFF1E3A5F))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (activeItems.isNotEmpty) ...<Widget>[
            Wrap(
              spacing: Sik3Spacing.sm,
              runSpacing: Sik3Spacing.xs,
              children: <Widget>[
                for (final item in activeItems)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Sik3Spacing.sm,
                      vertical: Sik3Spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: Sik3Colors.navy,
                      borderRadius: BorderRadius.circular(Sik3Radius.chip),
                      border: Border.all(color: const Color(0xFF1E3A5F)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ApdSvgIcon(
                          item: item,
                          size: 16,
                          color: Sik3Colors.amber,
                        ),
                        const SizedBox(width: Sik3Spacing.xs + 2),
                        Text(
                          item.labelId,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Sik3Spacing.md),
          ],
          Row(
            children: <Widget>[
              if (_zoneIndex > 0) ...<Widget>[
                OutlinedButton.icon(
                  key: const ValueKey<String>('retake_upper_zone_button'),
                  onPressed: _isProcessing ? null : _retakeUpperZone,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF334155)),
                    minimumSize: const Size(Sik3Spacing.minTouchTarget, 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Sik3Spacing.md,
                    ),
                  ),
                  icon: const Icon(Icons.replay, size: 20),
                  label: const Text('Ulangi Atas'),
                ),
                const SizedBox(width: Sik3Spacing.sm),
              ],
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey<String>('zone_capture_button'),
                  onPressed: _isProcessing ? null : _captureActiveZone,
                  style: FilledButton.styleFrom(
                    backgroundColor: Sik3Colors.amber,
                    foregroundColor: Sik3Colors.navy,
                    minimumSize: const Size(double.infinity, 52),
                  ),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(
                    _captureButtonLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Custom silhouette overlay guiding upper-body (head, shoulders, raised hands)
/// or lower-body (safety shoes) framing inside the dark scanner canvas.
class _ZoneSilhouettePainter extends CustomPainter {
  const _ZoneSilhouettePainter({required this.zone});

  final ScanZone zone;

  @override
  void paint(Canvas canvas, Size size) {
    final horizontalMargin = math.max(24.0, size.width * 0.10);
    final verticalMargin = math.max(28.0, size.height * 0.12);
    final frameRect = Rect.fromLTRB(
      horizontalMargin,
      verticalMargin,
      size.width - horizontalMargin,
      size.height - verticalMargin - 28.0,
    );
    if (frameRect.width <= 40 || frameRect.height <= 40) return;

    final rrect = RRect.fromRectAndRadius(
      frameRect,
      const Radius.circular(Sik3Radius.outer),
    );

    final scrimPath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      scrimPath,
      Paint()..color = Sik3Colors.scannerDark.withValues(alpha: 0.45),
    );

    // Subtle frame outline + high-contrast amber corner brackets.
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final cornerPaint = Paint()
      ..color = Sik3Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const cornerLen = 24.0;
    final l = frameRect.left;
    final r = frameRect.right;
    final t = frameRect.top;
    final b = frameRect.bottom;

    canvas.drawPath(
      Path()
        ..moveTo(l, t + cornerLen)
        ..lineTo(l, t)
        ..lineTo(l + cornerLen, t),
      cornerPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(r - cornerLen, t)
        ..lineTo(r, t)
        ..lineTo(r, t + cornerLen),
      cornerPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(l, b - cornerLen)
        ..lineTo(l, b)
        ..lineTo(l + cornerLen, b),
      cornerPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(r - cornerLen, b)
        ..lineTo(r, b)
        ..lineTo(r, b - cornerLen),
      cornerPaint,
    );

    final guidePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (zone == ScanZone.upper) {
      _paintUpperSilhouette(canvas, frameRect, guidePaint);
    } else {
      _paintLowerSilhouette(canvas, frameRect, guidePaint);
    }
  }

  void _paintUpperSilhouette(Canvas canvas, Rect rect, Paint paint) {
    final cx = rect.center.dx;
    final w = rect.width;
    final h = rect.height;

    // Head outline (top center).
    final headRadius = math.min(w * 0.14, h * 0.12);
    final headCenter = Offset(cx, rect.top + h * 0.22);
    canvas.drawOval(
      Rect.fromCenter(
        center: headCenter,
        width: headRadius * 1.85,
        height: headRadius * 2.1,
      ),
      paint,
    );

    // Shoulders & upper torso contour.
    final shoulderY = headCenter.dy + headRadius * 1.35;
    final torsoBottomY = rect.bottom - h * 0.08;
    final shoulderHalfW = w * 0.34;
    final torsoPath = Path()
      ..moveTo(cx - shoulderHalfW, torsoBottomY)
      ..lineTo(cx - shoulderHalfW, shoulderY + h * 0.08)
      ..quadraticBezierTo(
        cx - shoulderHalfW,
        shoulderY,
        cx - headRadius * 0.7,
        shoulderY,
      )
      ..moveTo(cx + headRadius * 0.7, shoulderY)
      ..quadraticBezierTo(
        cx + shoulderHalfW,
        shoulderY,
        cx + shoulderHalfW,
        shoulderY + h * 0.08,
      )
      ..lineTo(cx + shoulderHalfW, torsoBottomY);
    canvas.drawPath(torsoPath, paint);

    // Two raised hands in front of chest (for glove inspection).
    final handPaint = Paint()
      ..color = Sik3Colors.amber.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final handW = math.min(w * 0.14, 42.0);
    final handH = math.min(h * 0.17, 56.0);
    final handY = shoulderY + h * 0.16;

    for (final sign in const <double>[-1.0, 1.0]) {
      final handCenterX = cx + sign * (w * 0.14);
      final palmRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(handCenterX, handY + handH * 0.35),
          width: handW,
          height: handH,
        ),
        Radius.circular(handW * 0.38),
      );
      canvas.drawRRect(palmRect, handPaint);
    }
  }

  void _paintLowerSilhouette(Canvas canvas, Rect rect, Paint paint) {
    final cx = rect.center.dx;
    final w = rect.width;
    final h = rect.height;

    final baselineY = rect.bottom - h * 0.16;
    final ankleTopY = rect.top + h * 0.24;
    final bootSpread = w * 0.18;
    final bootWidth = math.min(w * 0.20, 68.0);

    // Ground line guide.
    canvas.drawLine(
      Offset(rect.left + w * 0.12, baselineY + 8),
      Offset(rect.right - w * 0.12, baselineY + 8),
      Paint()
        ..color = Sik3Colors.amber.withValues(alpha: 0.75)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // Left and right safety shoe silhouettes.
    for (final sign in const <double>[-1.0, 1.0]) {
      final xCenter = cx + sign * bootSpread;
      final bootPath = Path()
        ..moveTo(xCenter - bootWidth * 0.38, ankleTopY)
        ..lineTo(xCenter - bootWidth * 0.38, baselineY - h * 0.12)
        ..quadraticBezierTo(
          xCenter - bootWidth * 0.52,
          baselineY,
          xCenter - bootWidth * 0.10,
          baselineY,
        )
        ..lineTo(xCenter + bootWidth * 0.45, baselineY)
        ..quadraticBezierTo(
          xCenter + bootWidth * 0.56,
          baselineY,
          xCenter + bootWidth * 0.42,
          baselineY - h * 0.10,
        )
        ..lineTo(xCenter + bootWidth * 0.32, ankleTopY);
      canvas.drawPath(bootPath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ZoneSilhouettePainter oldDelegate) {
    return oldDelegate.zone != zone;
  }
}

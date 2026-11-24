import 'package:flutter/material.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/data/local_prefs.dart';
import 'package:sik3/features/onboarding/role_gate_screen.dart';
import 'package:sik3/features/student/student_qr_screen.dart';

typedef TeacherHomeBuilder = Widget Function(
  BuildContext context,
  LocalPrefs prefs,
  VoidCallback onSwitchRole,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await LocalPrefs.open();
  runApp(Sik3App(prefs: prefs));
}

/// Root SiK3 application routing offline between Role Gate, Student QR, & Teacher Home.
class Sik3App extends StatefulWidget {
  const Sik3App({
    super.key,
    required this.prefs,
    this.teacherHomeBuilder,
  });

  final LocalPrefs prefs;
  final TeacherHomeBuilder? teacherHomeBuilder;

  @override
  State<Sik3App> createState() => _Sik3AppState();
}

class _Sik3AppState extends State<Sik3App> {
  late AppRole? _role;

  @override
  void initState() {
    super.initState();
    _role = widget.prefs.getRole();
  }

  void _handleRoleSelected(AppRole role) {
    setState(() {
      _role = role;
    });
  }

  Future<void> _handleSwitchRole() async {
    await widget.prefs.setRole(null);
    if (mounted) {
      setState(() {
        _role = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SiK3',
      debugShowCheckedModeBanner: false,
      theme: buildSik3Theme(),
      home: Builder(
        builder: (innerContext) {
          final duration = Sik3Motion.resolve(innerContext, Sik3Motion.normal);
          return AnimatedSwitcher(
            duration: duration,
            switchInCurve: Sik3Motion.curve,
            switchOutCurve: Sik3Motion.curve,
            child: _buildActiveScreen(innerContext),
          );
        },
      ),
    );
  }

  Widget _buildActiveScreen(BuildContext context) {
    switch (_role) {
      case AppRole.student:
        return StudentQrScreen(
          key: const ValueKey<String>('screen_student_qr'),
          prefs: widget.prefs,
          onSwitchRole: _handleSwitchRole,
        );
      case AppRole.teacher:
        return widget.teacherHomeBuilder?.call(
              context,
              widget.prefs,
              _handleSwitchRole,
            ) ??
            TeacherHomePlaceholder(
              key: const ValueKey<String>('screen_teacher_placeholder'),
              prefs: widget.prefs,
              onSwitchRole: _handleSwitchRole,
            );
      case null:
        return RoleGateScreen(
          key: const ValueKey<String>('screen_role_gate'),
          prefs: widget.prefs,
          onRoleSelected: _handleRoleSelected,
        );
    }
  }
}

/// Temporary Teacher Home view until ClassSetupScreen replaces it in Task 3.
class TeacherHomePlaceholder extends StatelessWidget {
  const TeacherHomePlaceholder({
    super.key,
    required this.prefs,
    required this.onSwitchRole,
  });

  final LocalPrefs prefs;
  final VoidCallback onSwitchRole;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teacherName = prefs.getTeacherProfile().name;

    return Scaffold(
      backgroundColor: Sik3Colors.surfaceLight,
      appBar: AppBar(
        title: const Text('Mode Guru — SiK3'),
        actions: <Widget>[
          TextButton.icon(
            key: const ValueKey<String>('teacher_switch_role_button'),
            onPressed: onSwitchRole,
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
              child: Container(
                padding: const EdgeInsets.all(Sik3Spacing.xl),
                decoration: BoxDecoration(
                  color: Sik3Colors.cardSurface,
                  borderRadius: BorderRadius.circular(Sik3Radius.outer),
                  border: Border.all(color: Sik3Colors.border),
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
                          color: Sik3Colors.navy,
                          borderRadius: BorderRadius.circular(Sik3Radius.inner),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.verified_user_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(height: Sik3Spacing.md),
                    Text(
                      teacherName.isEmpty
                          ? 'Mode Guru Aktif'
                          : 'Mode Guru Aktif — $teacherName',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Sik3Colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Sik3Spacing.sm),
                    Text(
                      'PIN lokal telah terverifikasi. Halaman pengelolaan kelas dan sesi inspeksi akan aktif pada tahap integrasi berikutnya.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Sik3Colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

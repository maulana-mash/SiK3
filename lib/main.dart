import 'package:flutter/material.dart';
import 'package:sik3/core/theme/sik3_theme.dart';
import 'package:sik3/data/local_prefs.dart';
import 'package:sik3/features/onboarding/role_gate_screen.dart';
import 'package:sik3/features/student/student_qr_screen.dart';
import 'package:sik3/features/teacher/class_setup_screen.dart';

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
            ClassSetupScreen(
              key: const ValueKey<String>('screen_class_setup'),
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

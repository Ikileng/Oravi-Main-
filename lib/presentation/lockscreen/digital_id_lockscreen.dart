import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui' as ui;
import '../admin/dev_admin_dashboard_screen.dart';
import '../communications/staff_communications_screen.dart';
import '../providers/auth_providers.dart';
import '../ward_board_screen.dart';

/// Credential-first hospital sign-in. The backend determines role and access.
class DigitalIdLockscreen extends ConsumerStatefulWidget {
  const DigitalIdLockscreen({super.key});
  @override
  ConsumerState<DigitalIdLockscreen> createState() =>
      _DigitalIdLockscreenState();
}

class _DigitalIdLockscreenState extends ConsumerState<DigitalIdLockscreen> {
  static const hospitalName = String.fromEnvironment(
    'ORAVI_FACILITY_NAME',
    defaultValue: 'Oravi Hospital',
  );
  static const ssoEnabled = bool.fromEnvironment('ORAVI_SSO_ENABLED');
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _showDeveloperPanel = false;
  String _connectionState = 'Online';

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final identifier = _identifier.text.trim();
    final password = _password.text;
    if (identifier.isEmpty || password.isEmpty) return;
    final success = await ref
        .read(authControllerProvider.notifier)
        .verifyAndLogin(identifier, password);
    if (!mounted) return;
    final profile = ref.read(authenticatedStaffProvider);
    if (!success || profile == null) {
      final error = ref.read(authControllerProvider).errorMessage ?? '';
      if (error.contains('unavailable') || error.contains('configured')) {
        setState(() => _connectionState = 'Offline mode');
      }
      return;
    }
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm your identity'),
        content: Text('${profile.name} · ${profile.formattedRole}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not me'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (!mounted || proceed != true) {
      ref.read(authControllerProvider.notifier).logout();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => profile.role == 'dev_admin'
            ? const DevAdminDashboardScreen()
            : profile.isClinical
            ? const WardBoardScreen()
            : const StaffCommunicationsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: const Color(0xFF031B33),
      body: SafeArea(
        child: Stack(
          children: [
            const _HospitalBackdrop(),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    children: [
                      GestureDetector(
                        onLongPress: kDebugMode
                            ? () => setState(
                                () =>
                                    _showDeveloperPanel = !_showDeveloperPanel,
                              )
                            : null,
                        child: const _OraviBrand(),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        hospitalName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB6C9DF),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _LoginCard(
                        identifier: _identifier,
                        password: _password,
                        obscurePassword: _obscurePassword,
                        onTogglePassword: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        onSubmit: _signIn,
                        isLoading: authState.isLoading,
                        error: authState.errorMessage,
                        width: width,
                      ),
                      if (ssoEnabled) ...[
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.local_hospital_outlined),
                          label: const Text('Sign in with Hospital SSO'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(58),
                            foregroundColor: const Color(0xFF5BF4E7),
                            side: const BorderSide(
                              color: Color(0xFF36E6DC),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Available when enabled by your hospital',
                          style: TextStyle(color: Color(0xFF9FB6CF)),
                        ),
                      ],
                      if (_showDeveloperPanel) const _DeveloperPanel(),
                      const SizedBox(height: 32),
                      _ConnectionStatus(state: _connectionState),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HospitalBackdrop extends StatelessWidget {
  const _HospitalBackdrop();
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(size: Size.infinite, painter: _BackdropPainter()),
  );
}

class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF052744), Color(0xFF03152A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
    final wave = Paint()
      ..color = const Color(0xFF0BD4D0).withValues(alpha: .12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 40;
    final path = Path()
      ..moveTo(-40, size.height * .92)
      ..quadraticBezierTo(
        size.width * .48,
        size.height * .82,
        size.width + 60,
        size.height * .9,
      );
    canvas.drawPath(path, wave);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OraviBrand extends StatelessWidget {
  const _OraviBrand();
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ORAVI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          Text(
            'HOSPITAL WARD MANAGEMENT',
            style: TextStyle(
              color: Color(0xFFA7C0D9),
              fontSize: 11,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    ],
  );
}

class _LoginCard extends StatelessWidget {
  final TextEditingController identifier, password;
  final bool obscurePassword, isLoading;
  final VoidCallback onTogglePassword, onSubmit;
  final String? error;
  final double width;
  const _LoginCard({
    required this.identifier,
    required this.password,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.isLoading,
    required this.error,
    required this.width,
  });
  @override
  Widget build(BuildContext context) {
    final useGlass =
        width >= 360 && !MediaQuery.accessibleNavigationOf(context);
    final panel = Container(
      padding: EdgeInsets.all(width < 420 ? 22 : 38),
      decoration: BoxDecoration(
        color: const Color(0xFF133651).withValues(alpha: useGlass ? .68 : .96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF7096B8), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Welcome back',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sign in to coordinate your ward',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFAFC2D7), fontSize: 18),
          ),
          const SizedBox(height: 28),
          _Field(
            controller: identifier,
            hint: 'Work email or staff ID',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          _Field(
            controller: password,
            hint: 'Password or PIN',
            icon: Icons.lock_outline,
            obscure: obscurePassword,
            suffix: IconButton(
              onPressed: onTogglePassword,
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0xFFC2D1E2),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              child: const Text(
                'Forgot password?',
                style: TextStyle(color: Color(0xFF32E3D8), fontSize: 15),
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFFB4AB)),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF43E0D2), Color(0xFF1FC6C3)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: FilledButton(
              onPressed: isLoading ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.black,
                shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(58),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Sign in',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
    if (!useGlass) return panel;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: panel,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
  });
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    obscureText: obscure,
    keyboardType: keyboardType,
    style: const TextStyle(color: Colors.white, fontSize: 17),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFAFC2D7)),
      prefixIcon: Icon(icon, color: const Color(0xFFC2D1E2)),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFF102E49).withValues(alpha: .72),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF7096B8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF7096B8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF39E6DA), width: 2),
      ),
    ),
  );
}

class _ConnectionStatus extends StatelessWidget {
  final String state;
  const _ConnectionStatus({required this.state});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(
        state == 'Online'
            ? Icons.verified_user_outlined
            : Icons.cloud_off_outlined,
        size: 18,
        color: state == 'Online'
            ? const Color(0xFF5BF4E7)
            : const Color(0xFFFFC857),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          state == 'Online'
              ? 'Secure clinical workspace  •  Offline access available after first sign-in'
              : state,
          style: const TextStyle(color: Color(0xFFB6C9DF), fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}

class _DeveloperPanel extends StatelessWidget {
  const _DeveloperPanel();
  static const nurse = String.fromEnvironment('ORAVI_DEBUG_NURSE');
  static const charge = String.fromEnvironment('ORAVI_DEBUG_CHARGE_NURSE');
  static const manager = String.fromEnvironment('ORAVI_DEBUG_WARD_MANAGER');
  static const admin = String.fromEnvironment('ORAVI_DEBUG_ADMIN');
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 18),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.black26,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      'Developer quick sign-in: Nurse ${nurse.isEmpty ? 'not configured' : 'ready'} · Charge Nurse ${charge.isEmpty ? 'not configured' : 'ready'} · Ward Manager ${manager.isEmpty ? 'not configured' : 'ready'} · Admin ${admin.isEmpty ? 'not configured' : 'ready'}',
      style: const TextStyle(color: Color(0xFFB6C9DF), fontSize: 12),
      textAlign: TextAlign.center,
    ),
  );
}

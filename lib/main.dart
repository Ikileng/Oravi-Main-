import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/lockscreen/digital_id_lockscreen.dart';
import 'presentation/providers/auth_providers.dart';
import 'presentation/theme/clinical_theme.dart';
import 'presentation/ward_board_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: OraviApp(),
    ),
  );
}

class OraviApp extends ConsumerWidget {
  final Widget? home;
  const OraviApp({super.key, this.home});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authStaff = ref.watch(authenticatedStaffProvider);

    return MaterialApp(
      title: 'Oravi Clinical Operating System',
      debugShowCheckedModeBanner: false,
      theme: ClinicalTheme.darkTheme,
      home: home ?? (authStaff == null ? const DigitalIdLockscreen() : const WardBoardScreen()),
    );
  }
}

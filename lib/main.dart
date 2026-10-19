import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/theme/clinical_theme.dart';
import 'presentation/ward_board_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: OraviApp(),
    ),
  );
}

class OraviApp extends StatelessWidget {
  const OraviApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oravi Clinical Operating System',
      debugShowCheckedModeBanner: false,
      theme: ClinicalTheme.darkTheme,
      home: const WardBoardScreen(),
    );
  }
}

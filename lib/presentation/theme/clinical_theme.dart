import 'package:flutter/material.dart';
import '../../domain/models/loop_enums.dart';

/// Clinical UI Theme adhering to PRD Section 10 & FR-55:
/// - High contrast for low-light night shifts.
/// - Clear distinct severity indicators using shape & text as well as color (FR-18 & FR-25).
/// - Role and Cadre Color Coding (FR-55): Nurses in Blue, Doctors in Pink/Rose, Pharmacy/Lab in distinct hues.
/// - Large accessible tap targets.
class ClinicalTheme {
  static const Color background = Color(0xFF0F172A); // Slate 900
  static const Color surface = Color(0xFF1E293B);    // Slate 800
  static const Color surfaceElevated = Color(0xFF334155); // Slate 700
  static const Color border = Color(0xFF475569);     // Slate 600

  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Severity tiers
  static const Color criticalRed = Color(0xFFEF4444);
  static const Color urgentAmber = Color(0xFFF59E0B);
  static const Color routineTeal = Color(0xFF0D9488);
  static const Color successGreen = Color(0xFF10B981);

  // Cadre Color Palette (PRD FR-55)
  static const Color nurseBlue = Color(0xFF38BDF8);      // Sky 400 - Clinical Blue
  static const Color doctorPink = Color(0xFFF472B6);     // Rose/Pink 400 - Physicians & Consultants
  static const Color pharmacyEmerald = Color(0xFF34D399);// Emerald 400 - Pharmacy
  static const Color labAmber = Color(0xFFFBBF24);        // Amber 400 - Laboratory
  static const Color inChargePurple = Color(0xFFA78BFA);  // Purple 400 - Matron / Nurse-in-charge

  static Color urgencyColor(LoopUrgency urgency) {
    switch (urgency) {
      case LoopUrgency.critical:
        return criticalRed;
      case LoopUrgency.urgent:
        return urgentAmber;
      case LoopUrgency.routine:
        return routineTeal;
    }
  }

  /// Returns the standardized cadre color based on role string or clinician name (FR-55)
  static Color cadreColor(String roleOrName) {
    final lower = roleOrName.toLowerCase();
    if (lower.contains('dr') || lower.contains('doctor') || lower.contains('consultant') || lower.contains('medical_officer') || lower.contains('gynaecologist') || lower.contains('physician')) {
      return doctorPink;
    }
    if (lower.contains('nurse') || lower.contains('rn')) {
      return nurseBlue;
    }
    if (lower.contains('pharm') || lower.contains('pharmacist')) {
      return pharmacyEmerald;
    }
    if (lower.contains('lab')) {
      return labAmber;
    }
    if (lower.contains('in_charge') || lower.contains('matron')) {
      return inChargePurple;
    }
    return textSecondary;
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: routineTeal,
      colorScheme: const ColorScheme.dark(
        primary: routineTeal,
        secondary: urgentAmber,
        surface: surface,
        error: criticalRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border, width: 0.8),
        ),
      ),
    );
  }
}

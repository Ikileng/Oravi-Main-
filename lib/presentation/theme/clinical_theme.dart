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
  static const Color border = Color(0xFF475569); // Slate 600
  static const Color canvas = Color(0xFF070C18);
  static const Color surfaceSoft = Color(0xFF10192E);
  static const Color surfaceAccent = Color(0xFF123047);
  static const Color clinicalBlue = Color(0xFF38BDF8);

  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 16;
  static const double minimumTapTarget = 48;

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

  /// Returns the standardized cadre color based on role string, staff ID, or clinician name (FR-55)
  static Color cadreColor(String roleOrName) {
    final lower = roleOrName.toLowerCase();
    if (lower.startsWith('doc-') || lower.contains('dr') || lower.contains('doctor') || lower.contains('consultant') || lower.contains('medical_officer') || lower.contains('physician')) {
      return doctorPink;
    }
    if (lower == 'nur-402' || lower.contains('in_charge') || lower.contains('charge') || lower.contains('matron') || lower.contains('sister')) {
      return inChargePurple;
    }
    if (lower.startsWith('nur-') || lower.contains('nurse') || lower.contains('rn')) {
      return nurseBlue;
    }
    if (lower.contains('pharm') || lower.contains('pharmacist')) {
      return pharmacyEmerald;
    }
    if (lower.contains('lab')) {
      return labAmber;
    }
    return textSecondary;
  }

  /// Formats author identity to uppercase clinical display name (e.g. "NURSE NJERI", "DR. KAMAU")
  static String formatAuthorDisplayName(String authorId) {
    final trimmed = authorId.trim();

    // Canonical Ward 4B staff mapping
    switch (trimmed.toUpperCase()) {
      case 'NUR-401':
        return 'NURSE WANJIKU';
      case 'NUR-402':
        return 'SISTER ACHIENG';
      case 'NUR-403':
        return 'NURSE NJERI';
      case 'DOC-401':
        return 'DR. KAMAU';
      case 'NUR-404':
        return 'NURSE OTIENO';
      case 'NUR-405':
        return 'NURSE MUTHONI';
      case 'DOC-OTIENO':
        return 'DR. OTIENO';
      case 'NURSE-01':
      case 'NURSE-02':
        return 'WARD NURSE';
    }

    final lower = trimmed.toLowerCase();
    if (lower.startsWith('doc-') || lower.startsWith('dr') || lower.startsWith('doctor-')) {
      final clean = trimmed
          .replaceAll(RegExp(r'^(doctor|doc|dr)[\.\s\-_]*', caseSensitive: false), '')
          .replaceAll(',', '')
          .trim();
      final parts = clean.split(RegExp(r'[\s\-_]+'));
      final lastName = parts.isNotEmpty ? parts.last.toUpperCase() : 'DOCTOR';
      return 'DR. $lastName';
    } else if (lower.contains('in_charge') || lower.contains('charge') || lower.contains('matron') || lower.contains('sister')) {
      final clean = trimmed
          .replaceAll(RegExp(r'(in_charge|charge|matron|sister)[\s\-_]*', caseSensitive: false), '')
          .replaceAll(',', '')
          .trim();
      final parts = clean.split(RegExp(r'[\s\-_]+'));
      final candidate = parts.isNotEmpty ? parts.last.toUpperCase() : 'IN-CHARGE';
      return 'SISTER $candidate';
    } else if (lower.contains('nurse') || lower.contains('rn') || lower.startsWith('nur')) {
      final clean = trimmed
          .replaceAll(RegExp(r'(nurse|rn|nur)[\s\-_]*', caseSensitive: false), '')
          .replaceAll(',', '')
          .trim();
      final parts = clean.split(RegExp(r'[\s\-_]+'));
      final candidate = parts.isNotEmpty ? parts.last.toUpperCase() : 'NURSE';
      return 'NURSE $candidate';
    }

    return trimmed.toUpperCase();
  }

  static ThemeData get darkTheme {
    final scheme = const ColorScheme.dark(
      primary: routineTeal,
      secondary: urgentAmber,
      surface: surface,
      error: criticalRed,
      onPrimary: Colors.white,
      onSurface: textPrimary,
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: routineTeal,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: const BorderSide(color: border, width: 0.8),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 0.8),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceSoft,
        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: clinicalBlue, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceSoft,
        selectedColor: clinicalBlue.withValues(alpha: 0.18),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ClinicalTheme.radiusLarge),
        ),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, minimumTapTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(minimumTapTarget, minimumTapTarget),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minTileHeight: 64,
        iconColor: textSecondary,
        textColor: textPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceElevated,
        contentTextStyle: TextStyle(color: textPrimary),
      ),
    );
  }
}

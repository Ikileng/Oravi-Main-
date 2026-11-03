/// Rules for the patient label used in the nurse workflow.
///
/// New records must provide initials. Legacy event labels are reduced to
///initials when read, so older records never expose full names in projections.
class PatientIdentity {
  static final RegExp _suffix = RegExp(
    r'\s*\((?:snr|senior|jnr|junior)\)\s*$',
    caseSensitive: false,
  );

  static String requireInitials(String value) {
    final normalized = _normalizeTokens(value);
    final tokens = _tokens(normalized);
    if (tokens.length < 2 || tokens.any((token) => token.length != 1)) {
      throw ArgumentError.value(
        value,
        'patientInitials',
        'Provide initials only, such as J.K.',
      );
    }
    return '${tokens.map((token) => token.toUpperCase()).join('.')}.';
  }

  /// Converts a legacy name or initials label into initials for safe display.
  static String initialsFromLegacy(String value) {
    final normalized = _normalizeTokens(value);
    final tokens = _tokens(normalized);
    if (tokens.isEmpty) return '—';
    return '${tokens.map((token) => token[0].toUpperCase()).join('.')}.';
  }

  static String _normalizeTokens(String value) => value
      .replaceFirst(_suffix, '')
      .replaceAll(RegExp(r'[^A-Za-z]+'), ' ')
      .trim();

  static List<String> _tokens(String value) => value
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
}

import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import '../database/database.dart';
import '../../domain/models/staff_profile.dart';

class AuthResult {
  final bool success;
  final StaffProfile? staff;
  final String? token;
  final String? error;

  const AuthResult({
    required this.success,
    this.staff,
    this.token,
    this.error,
  });
}

/// Baseline canonical staff for offline-first resilience.
const List<StaffProfile> kDefaultWardStaff = [
  StaffProfile(
    staffId: 'NUR-401',
    name: 'Mary Wanjiku, RN',
    role: 'ward_nurse',
    wardId: 'WARD-4B',
    avatarColor: '#059669',
    initials: 'MW',
  ),
  StaffProfile(
    staffId: 'NUR-402',
    name: 'Grace Achieng, RN',
    role: 'charge_nurse',
    wardId: 'WARD-4B',
    avatarColor: '#2563EB',
    initials: 'GA',
  ),
  StaffProfile(
    staffId: 'NUR-403',
    name: 'Faith Njeri, RN',
    role: 'ward_nurse',
    wardId: 'WARD-4B',
    avatarColor: '#0D9488',
    initials: 'FN',
  ),
  StaffProfile(
    staffId: 'DOC-401',
    name: 'Dr. James Kamau',
    role: 'doctor_on_call',
    wardId: 'WARD-4B',
    avatarColor: '#7C3AED',
    initials: 'JK',
  ),
  StaffProfile(
    staffId: 'NUR-404',
    name: 'Sarah Otieno, RN',
    role: 'ward_nurse',
    wardId: 'WARD-4B',
    avatarColor: '#D97706',
    initials: 'SO',
  ),
  StaffProfile(
    staffId: 'NUR-405',
    name: 'Jane Muthoni, RN',
    role: 'ward_nurse',
    wardId: 'WARD-4B',
    avatarColor: '#E11D48',
    initials: 'JM',
  ),
];

const Map<String, String> kOfflineCanonicalPins = {
  'NUR-401': '1234',
  'NUR-402': '5678',
  'NUR-403': '1111',
  'DOC-401': '9090',
  'NUR-404': '2222',
  'NUR-405': '3333',
};

class StaffAuthService {
  static OraviLocalDatabase? db;
  static final Map<String, String> dynamicPins = Map.from(kOfflineCanonicalPins);
  static final List<StaffProfile> dynamicStaff = List.from(kDefaultWardStaff);

  static void setDatabase(OraviLocalDatabase database) {
    db = database;
  }

  static void addStaffUser(StaffProfile staff, String pin, {String? email}) {
    dynamicStaff.removeWhere((s) => s.staffId == staff.staffId);
    dynamicStaff.add(staff);
    dynamicPins[staff.staffId] = pin;

    db?.upsertStaff(LocalStaffCompanion.insert(
      staffId: staff.staffId,
      name: staff.name,
      role: staff.role,
      wardId: Value(staff.wardId),
      pin: pin,
      isActive: Value(staff.isActive),
      avatarColor: Value(staff.avatarColor),
      initials: staff.initials,
      email: Value(email),
    ));
  }

  static void updateStaffPin(String staffId, String newPin) {
    dynamicPins[staffId] = newPin;
    db?.updateStaffPin(staffId, newPin);
  }

  static void toggleStaffActive(String staffId) {
    final idx = dynamicStaff.indexWhere((s) => s.staffId == staffId);
    if (idx != -1) {
      final current = dynamicStaff[idx];
      dynamicStaff[idx] = current.copyWith(isActive: !current.isActive);
    }
    db?.toggleStaffActive(staffId);
  }

  static void deleteStaff(String staffId) {
    dynamicStaff.removeWhere((s) => s.staffId == staffId);
    dynamicPins.remove(staffId);
    db?.deleteStaff(staffId);
  }

  static const List<String> defaultCandidateUrls = [
    'http://127.0.0.1:8000',
    'http://172.16.20.186:8000',
    'http://10.0.96.95:8000',
  ];

  final List<String> candidateUrls;
  String _activeBaseUrl;
  final Duration timeout;

  // Optional mock handlers for unit testing
  final Future<List<StaffProfile>> Function(String wardId)? mockGetStaffHandler;
  final Future<AuthResult> Function(String staffId, String pin)? mockVerifyPinHandler;

  StaffAuthService({
    String? baseUrl,
    List<String>? candidateUrls,
    this.timeout = const Duration(seconds: 4),
    this.mockGetStaffHandler,
    this.mockVerifyPinHandler,
  })  : candidateUrls = candidateUrls ??
            (baseUrl != null ? [baseUrl, ...defaultCandidateUrls] : defaultCandidateUrls),
        _activeBaseUrl = baseUrl ?? defaultCandidateUrls.first;

  Future<T> _executeWithFallback<T>(Future<T> Function(String base) request) async {
    final ordered = [
      _activeBaseUrl,
      ...candidateUrls.where((u) => u != _activeBaseUrl),
    ];
    dynamic lastError;
    for (final base in ordered) {
      try {
        final result = await request(base);
        _activeBaseUrl = base;
        return result;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('All candidate auth servers unreachable');
  }

  /// Fetches the roster of staff on the given ward.
  /// Automatically falls back to offline canonical staff on network unavailability.
  Future<List<StaffProfile>> getStaffForWard(String wardId) async {
    if (mockGetStaffHandler != null) {
      return mockGetStaffHandler!(wardId);
    }

    try {
      return await _executeWithFallback((base) async {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
        try {
          final cleanBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
          final uri = Uri.parse('$cleanBase/api/v1/auth/staff?ward_id=$wardId');

          final request = await client.getUrl(uri).timeout(timeout);
          request.headers.set(HttpHeaders.acceptHeader, 'application/json');

          final response = await request.close().timeout(timeout);
          if (response.statusCode == 200) {
            final body = await response.transform(utf8.decoder).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            final rawList = (json['staff'] as List<dynamic>?) ?? [];
            return rawList.map((e) => StaffProfile.fromJson(e as Map<String, dynamic>)).toList();
          }
          throw Exception('Backend returned HTTP ${response.statusCode}');
        } finally {
          client.close();
        }
      });
    } catch (_) {
      // Offline fallback: check SQLite database first
      if (db != null) {
        final rows = await db!.getAllStaff();
        if (rows.isNotEmpty) {
          return rows
              .where((r) => r.wardId == wardId || wardId == 'WARD-4B')
              .map((r) => StaffProfile(
                    staffId: r.staffId,
                    name: r.name,
                    role: r.role,
                    wardId: r.wardId,
                    avatarColor: r.avatarColor,
                    initials: r.initials,
                    isActive: r.isActive,
                  ))
              .toList();
        }
      }
      return dynamicStaff.where((s) => s.wardId == wardId || wardId == 'WARD-4B').toList();
    }
  }

  /// Verifies a 4-digit PIN for the selected staff member.
  /// Falls back to local offline validation if server is unreachable.
  Future<AuthResult> verifyPin(String staffId, String pin) async {
    if (mockVerifyPinHandler != null) {
      return mockVerifyPinHandler!(staffId, pin);
    }

    try {
      return await _executeWithFallback((base) async {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
        try {
          final cleanBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
          final uri = Uri.parse('$cleanBase/api/v1/auth/verify-pin');

          final request = await client.postUrl(uri).timeout(timeout);
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode({
            'staff_id': staffId,
            'pin': pin,
          }));

          final response = await request.close().timeout(timeout);
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;

          final success = json['success'] as bool? ?? false;
          final staffMap = json['staff'] as Map<String, dynamic>?;
          final token = json['token'] as String?;
          final error = json['error'] as String?;

          return AuthResult(
            success: success,
            staff: staffMap != null ? StaffProfile.fromJson(staffMap) : null,
            token: token,
            error: error,
          );
        } finally {
          client.close();
        }
      });
    } catch (_) {
      // Offline fallback: check persistent Drift SQLite database
      if (db != null) {
        final rows = await db!.getAllStaff();
        final match = rows.where((r) => r.staffId == staffId).firstOrNull;
        if (match != null) {
          if (!match.isActive) {
            return const AuthResult(
              success: false,
              error: 'Account is deactivated. Contact dev administrator.',
            );
          }
          if (match.pin == pin) {
            return AuthResult(
              success: true,
              staff: StaffProfile(
                staffId: match.staffId,
                name: match.name,
                role: match.role,
                wardId: match.wardId,
                avatarColor: match.avatarColor,
                initials: match.initials,
                isActive: match.isActive,
              ),
              token: 'offline_token_$staffId',
            );
          } else {
            return const AuthResult(
              success: false,
              error: 'Invalid PIN. (Offline mode active)',
            );
          }
        }
      }

      // Memory fallback if DB is uninitialized
      final staff = dynamicStaff.firstWhere(
        (s) => s.staffId == staffId,
        orElse: () => kDefaultWardStaff.firstWhere(
          (s) => s.staffId == staffId,
          orElse: () => StaffProfile(
            staffId: staffId,
            name: 'Ward Staff',
            role: 'ward_nurse',
            wardId: 'WARD-4B',
            avatarColor: '#059669',
            initials: 'RN',
          ),
        ),
      );

      if (!staff.isActive) {
        return const AuthResult(
          success: false,
          error: 'Account is deactivated. Contact dev administrator.',
        );
      }

      final expectedPin = dynamicPins[staffId] ?? kOfflineCanonicalPins[staffId];
      if (expectedPin != null && expectedPin == pin) {
        return AuthResult(
          success: true,
          staff: staff,
          token: 'offline_token_$staffId',
        );
      } else {
        return const AuthResult(
          success: false,
          error: 'Invalid PIN. (Offline mode active)',
        );
      }
    }
  }
}

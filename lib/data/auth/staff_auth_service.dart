import 'dart:convert';
import 'dart:io';
import 'dart:async';
import '../api_configuration.dart';
import '../../domain/models/staff_profile.dart';
import '../../domain/models/hospital_ward.dart';

class AuthResult {
  final bool success;
  final StaffProfile? staff;
  final String? token;
  final String? error;

  const AuthResult({required this.success, this.staff, this.token, this.error});
}

class StaffAuthService {
  static List<String> get defaultCandidateUrls =>
      OraviApiConfiguration.candidateUrls;

  final List<String> candidateUrls;
  String _activeBaseUrl;
  final Duration timeout;

  // Optional mock handlers for unit testing
  final Future<List<StaffProfile>> Function(String wardId)? mockGetStaffHandler;
  final Future<AuthResult> Function(String staffId, String pin)?
  mockVerifyPinHandler;

  StaffAuthService({
    String? baseUrl,
    List<String>? candidateUrls,
    this.timeout = const Duration(seconds: 4),
    this.mockGetStaffHandler,
    this.mockVerifyPinHandler,
  }) : candidateUrls =
           candidateUrls ??
           (baseUrl != null
               ? [baseUrl, ...defaultCandidateUrls]
               : defaultCandidateUrls),
       _activeBaseUrl =
           baseUrl ??
           ((candidateUrls ?? defaultCandidateUrls).isEmpty
               ? ''
               : (candidateUrls ?? defaultCandidateUrls).first) {
    for (final url in this.candidateUrls) {
      OraviApiConfiguration.validateBaseUrl(url);
    }
  }

  Future<T> _executeWithFallback<T>(
    Future<T> Function(String base) request,
  ) async {
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

  /// Fetches provisioned staff identity cards for the sign-in screen.
  Future<List<StaffProfile>> getStaffForWard(String wardId) async {
    if (mockGetStaffHandler != null) {
      return mockGetStaffHandler!(wardId);
    }

    return _executeWithFallback((base) async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        final cleanBase = base.endsWith('/')
            ? base.substring(0, base.length - 1)
            : base;
        final uri = Uri.parse('$cleanBase/api/v1/auth/directory');
        final request = await client.getUrl(uri).timeout(timeout);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close().timeout(timeout);
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode != 200) {
          throw HttpException(
            'Staff directory unavailable (HTTP ${response.statusCode}).',
            uri: uri,
          );
        }
        final rawList = jsonDecode(body) as List<dynamic>;
        return rawList
            .map((item) => StaffProfile.fromJson(item as Map<String, dynamic>))
            .toList();
      } finally {
        client.close();
      }
    });
  }

  Future<List<StaffProfile>> getProvisionedStaff(String token) async {
    return _executeWithFallback((base) async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        final cleanBase = base.endsWith('/')
            ? base.substring(0, base.length - 1)
            : base;
        final request = await client
            .getUrl(Uri.parse('$cleanBase/api/v1/admin/staff'))
            .timeout(timeout);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final response = await request.close().timeout(timeout);
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode != 200) {
          throw Exception(
            'Admin directory unavailable (${response.statusCode}).',
          );
        }
        return (jsonDecode(body) as List<dynamic>)
            .map((item) => StaffProfile.fromJson(item as Map<String, dynamic>))
            .toList();
      } finally {
        client.close();
      }
    });
  }

  Future<StaffProfile> createClinicalStaff({
    required String token,
    required String staffId,
    required String name,
    required String role,
    required String pin,
  }) async {
    return _executeWithFallback((base) async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        final cleanBase = base.endsWith('/')
            ? base.substring(0, base.length - 1)
            : base;
        final request = await client
            .postUrl(Uri.parse('$cleanBase/api/v1/admin/staff'))
            .timeout(timeout);
        request.headers.contentType = ContentType.json;
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        request.write(
          jsonEncode({
            'staff_id': staffId,
            'name': name,
            'role': role,
            'pin': pin,
          }),
        );
        final response = await request.close().timeout(timeout);
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        if (response.statusCode != 200) {
          throw Exception(
            decoded['detail'] ?? 'Could not create staff account.',
          );
        }
        return StaffProfile.fromJson(decoded);
      } finally {
        client.close();
      }
    });
  }

  Future<List<HospitalWard>> getHospitalWards(String token) async {
    return _executeWithFallback((base) async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        final cleanBase = base.endsWith('/')
            ? base.substring(0, base.length - 1)
            : base;
        final request = await client
            .getUrl(Uri.parse('$cleanBase/api/v1/wards'))
            .timeout(timeout);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final response = await request.close().timeout(timeout);
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode != 200) {
          throw Exception('Ward list unavailable.');
        }
        return (jsonDecode(body) as List<dynamic>)
            .map((item) => HospitalWard.fromMap(item as Map<String, dynamic>))
            .toList();
      } finally {
        client.close();
      }
    });
  }

  Future<void> selectChargeNurseWard(String token, String wardId) async {
    await _executeWithFallback((base) async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        final cleanBase = base.endsWith('/')
            ? base.substring(0, base.length - 1)
            : base;
        final request = await client
            .postUrl(
              Uri.parse(
                '$cleanBase/api/v1/auth/select-ward/${Uri.encodeComponent(wardId)}',
              ),
            )
            .timeout(timeout);
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final response = await request.close().timeout(timeout);
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode != 200) {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          throw Exception(decoded['detail'] ?? 'Could not select ward.');
        }
        return true;
      } finally {
        client.close();
      }
    });
  }

  /// Verifies a staff PIN with the configured authentication service.
  Future<AuthResult> verifyPin(String staffId, String pin) async {
    if (mockVerifyPinHandler != null) {
      return mockVerifyPinHandler!(staffId, pin);
    }

    try {
      return await _executeWithFallback((base) async {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        try {
          final cleanBase = base.endsWith('/')
              ? base.substring(0, base.length - 1)
              : base;
          final uri = Uri.parse('$cleanBase/api/v1/auth/verify-pin');

          final request = await client.postUrl(uri).timeout(timeout);
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode({'staff_id': staffId, 'pin': pin}));

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
      return const AuthResult(
        success: false,
        error:
            'Sign-in service unavailable. Connect to the configured Oravi service.',
      );
    }
  }

}

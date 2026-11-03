import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../domain/models/hospital_ward.dart';
import '../domain/models/staff_profile.dart';
import '../domain/models/whiteboard_models.dart';
import 'api_configuration.dart';

class WardBoardService {
  final String? Function() getAccessToken;
  final List<String> candidateUrls;
  String? _activeBaseUrl;
  final Duration timeout;

  WardBoardService({
    required this.getAccessToken,
    List<String>? candidateUrls,
    this.timeout = const Duration(seconds: 8),
  }) : candidateUrls = candidateUrls ?? OraviApiConfiguration.candidateUrls {
    for (final url in this.candidateUrls) {
      OraviApiConfiguration.validateBaseUrl(url);
    }
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, dynamic>? payload,
    Map<String, String>? extraHeaders,
  }) async {
    final token = getAccessToken();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in to load or update the ward board.');
    }
    final ordered = [...candidateUrls];
    final activeBaseUrl = _activeBaseUrl;
    if (activeBaseUrl != null) {
      ordered
        ..remove(activeBaseUrl)
        ..insert(0, activeBaseUrl);
    }
    Object? lastError;
    for (final base in ordered) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        final cleanBase = base.endsWith('/')
            ? base.substring(0, base.length - 1)
            : base;
        final uri = Uri.parse('$cleanBase$path');
        final request = await client.openUrl(method, uri).timeout(timeout);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        extraHeaders?.forEach(request.headers.set);
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        if (payload != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(payload));
        }
        final response = await request.close().timeout(timeout);
        final body = await response.transform(utf8.decoder).join();
        final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final detail = decoded is Map<String, dynamic>
              ? decoded['detail'] ?? decoded['error']
              : null;
          throw HttpException(
            detail is String ? detail : 'Ward service returned HTTP ${response.statusCode}.',
            uri: uri,
          );
        }
        _activeBaseUrl = base;
        return decoded;
      } on SocketException catch (error) {
        lastError = error;
      } on TimeoutException catch (error) {
        lastError = error;
      } on HandshakeException catch (error) {
        lastError = error;
      } on HttpException {
        rethrow;
      } finally {
        client.close(force: true);
      }
    }
    throw HttpException(
      'Could not reach the Oravi service. Check the connection and try again. $lastError',
    );
  }

  Future<List<HospitalWard>> getWards() async {
    final token = getAccessToken();
    if (token == null) throw StateError('Sign in to load configured wards.');
    final response = await _request('GET', '/api/v1/wards');
    if (response is! List) {
      throw const FormatException('Ward service returned an invalid ward list.');
    }
    return response
        .map((item) => HospitalWard.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  Future<HospitalWard?> getPreferredWard() async {
    final response = await _request('GET', '/api/v1/staff/me/ward-context');
    if (response is! Map<String, dynamic>) {
      throw const FormatException('Ward service returned an invalid ward context.');
    }
    final ward = response['ward'];
    return ward is Map<String, dynamic> ? HospitalWard.fromMap(ward) : null;
  }

  Future<void> setPreferredWard(String wardId) async {
    await _request(
      'PUT',
      '/api/v1/staff/me/ward-context',
      payload: {'ward_id': wardId},
    );
  }

  Future<Map<String, dynamic>?> getActiveAssignment({
    required String date,
    required String shiftType,
  }) async {
    final query = Uri(queryParameters: {'date': date, 'shift_type': shiftType});
    final response = await _request(
      'GET',
      '/api/v1/staff/me/active-assignment?${query.query}',
    );
    if (response is! Map<String, dynamic>) {
      throw const FormatException('Ward service returned an invalid assignment.');
    }
    final assignment = response['active_assignment'];
    return assignment is Map<String, dynamic> ? assignment : null;
  }

  Future<Map<String, dynamic>> getBoard({
    required String wardId,
    required String date,
    required String shiftType,
  }) async {
    final query = Uri(queryParameters: {'date': date, 'shift_type': shiftType});
    final response = await _request(
      'GET',
      '/api/v1/wards/${Uri.encodeComponent(wardId)}/board?${query.query}',
    );
    if (response is! Map<String, dynamic>) {
      throw const FormatException('Ward service returned an invalid board.');
    }
    return response;
  }

  Future<List<StaffProfile>> getStaffForWard(
    String wardId, {
    required String date,
    required String shiftType,
  }) async {
    final query = Uri(queryParameters: {'date': date, 'shift_type': shiftType});
    final response = await _request(
      'GET',
      '/api/v1/wards/${Uri.encodeComponent(wardId)}/staff?${query.query}',
    );
    if (response is! Map<String, dynamic>) {
      throw const FormatException('Ward service returned an invalid staff list.');
    }
    final raw = response['staff'];
    if (raw is! List) return [];
    return raw
        .map((item) => StaffProfile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> acceptHandoffBeds({
    required String allocationId,
    required String outgoingStaffId,
    required String incomingAccessToken,
    required List<String> bedNumbers,
  }) async {
    await _request(
      'POST',
      '/api/v1/allocations/${Uri.encodeComponent(allocationId)}/handoff/accept',
      payload: {
        'outgoing_nurse_id': outgoingStaffId,
        'beds': bedNumbers,
      },
      extraHeaders: {
        'X-Incoming-Authorization': 'Bearer $incomingAccessToken',
      },
    );
  }

  Future<void> publishBoard({
    required String wardId,
    required String date,
    required String shiftType,
    required String staffId,
    required List<WhiteboardBedAssignment> assignments,
    required Map<String, dynamic> supportRoster,
  }) async {
    await _request(
      'POST',
      '/api/v1/allocations/publish',
      payload: {
        'allocation_id': 'ALLOC-${const Uuid().v7()}',
        'ward_id': wardId,
        'shift_type': shiftType,
        'date': date,
        'published_by': staffId,
        'published_at': DateTime.now().toUtc().toIso8601String(),
        'support_roster': supportRoster,
        'bed_assignments': assignments.map((assignment) {
          return {
            'bed_number': assignment.bedNumber,
            'patient_id': assignment.patientId,
            'patient_initials': assignment.patientInitials,
            'admission_number': assignment.patientId,
            'admitting_doctor': assignment.admittingDoctor,
            'assigned_nurse_id': shiftType == 'day'
                ? assignment.dayShiftNurseId
                : assignment.nightShiftNurseId,
            'status': assignment.status,
          };
        }).toList(),
      },
    );
  }
}

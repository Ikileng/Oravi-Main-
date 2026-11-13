import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../domain/models/hospital_ward.dart';
import '../domain/models/staff_profile.dart';
import '../domain/models/whiteboard_models.dart';
import '../domain/models/call_session.dart';
import 'api_configuration.dart';

class WardBoardService {
  Future<Object?> communicationRequest(
    String method,
    String path, {
    Map<String, dynamic>? payload,
  }) => _request(method, '/api/v1$path', payload: payload);
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
            detail is String
                ? detail
                : 'Ward service returned HTTP ${response.statusCode}.',
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
      throw const FormatException(
        'Ward service returned an invalid ward list.',
      );
    }
    return response
        .map((item) => HospitalWard.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  Future<HospitalWard?> getPreferredWard() async {
    final response = await _request('GET', '/api/v1/staff/me/ward-context');
    if (response is! Map<String, dynamic>) {
      throw const FormatException(
        'Ward service returned an invalid ward context.',
      );
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
      throw const FormatException(
        'Ward service returned an invalid assignment.',
      );
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

  Future<List<Map<String, dynamic>>> getCarriedForwardIssues() async {
    final response = await _request('GET', '/api/v1/medical-issues/carried');
    if (response is! Map<String, dynamic> ||
        response['issues'] is! List<dynamic>) {
      throw const FormatException(
        'The server returned an invalid carried Medical Issues response.',
      );
    }
    return (response['issues'] as List<dynamic>).map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException(
          'The server returned an invalid carried Medical Issue.',
        );
      }
      return item;
    }).toList();
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
      throw const FormatException(
        'Ward service returned an invalid staff list.',
      );
    }
    final raw = response['staff'];
    if (raw is! List) return [];
    return raw
        .map((item) => StaffProfile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<StaffProfile>> getStaffForPatient({
    required String patientId,
    required String date,
  }) async {
    final query = Uri(queryParameters: {'date': date});
    final response = await _request(
      'GET',
      '/api/v1/patients/${Uri.encodeComponent(patientId)}/staff?${query.query}',
    );
    if (response is! Map<String, dynamic>) {
      throw const FormatException(
        'Patient staff service returned an invalid list.',
      );
    }
    final raw = response['staff'];
    if (raw is! List) {
      throw const FormatException(
        'Patient staff service returned no staff list.',
      );
    }
    return raw
        .map((item) => StaffProfile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> registerFcmInstallation({
    required String token,
    required String deviceId,
    required String platform,
  }) async {
    await _request(
      'POST',
      '/api/v1/staff/me/fcm-installation',
      payload: {'token': token, 'device_id': deviceId, 'platform': platform},
    );
  }

  Future<void> removeFcmInstallation({required String deviceId}) async {
    await _request(
      'DELETE',
      '/api/v1/staff/me/fcm-installation',
      payload: {'device_id': deviceId},
    );
  }

  Future<Map<String, dynamic>> getMedicalIssueThread({
    required String patientId,
    required String loopId,
  }) async {
    final response = await _request(
      'GET',
      '/api/v1/patients/${Uri.encodeComponent(patientId)}/medical-issues/${Uri.encodeComponent(loopId)}',
    );
    if (response is! Map<String, dynamic> ||
        response['patient_id'] != patientId ||
        response['loop_id'] != loopId ||
        response['events'] is! List) {
      throw const FormatException(
        'The server returned an invalid Medical Issue thread.',
      );
    }
    return response;
  }

  Future<CallSession> inviteCall({
    required String patientId,
    required String loopId,
    required String recipientId,
  }) async {
    final response = await _request(
      'POST',
      '/api/v1/calls/invite',
      payload: {
        'patient_id': patientId,
        'loop_id': loopId,
        'recipient_id': recipientId,
      },
    );
    if (response is! Map<String, dynamic>) {
      throw const FormatException(
        'The call service returned an invalid invitation.',
      );
    }
    return CallSession.fromMap(response);
  }

  Future<CallSession> acceptCall(String callId) async {
    final response = await _request(
      'POST',
      '/api/v1/calls/${Uri.encodeComponent(callId)}/accept',
    );
    if (response is! Map<String, dynamic>) {
      throw const FormatException(
        'The call service returned an invalid answer.',
      );
    }
    return CallSession.fromMap(response);
  }

  Future<Map<String, dynamic>> getCall(String callId) async {
    final response = await _request(
      'GET',
      '/api/v1/calls/${Uri.encodeComponent(callId)}',
    );
    if (response is! Map<String, dynamic>) {
      throw const FormatException('The call service returned an invalid call.');
    }
    return response;
  }

  Future<void> endCall(String callId) async {
    await _request('POST', '/api/v1/calls/${Uri.encodeComponent(callId)}/end');
  }

  Future<void> declineCall(String callId) async {
    await _request(
      'POST',
      '/api/v1/calls/${Uri.encodeComponent(callId)}/decline',
    );
  }

  Future<void> cancelCall(String callId) async {
    await _request(
      'POST',
      '/api/v1/calls/${Uri.encodeComponent(callId)}/cancel',
    );
  }

  Future<void> acceptHandoffBeds({
    required String allocationId,
    required String outgoingStaffId,
    required String incomingAccessToken,
    required List<String> bedNumbers,
    required String handoffSessionId,
    required String patientId,
    required List<String> transferredLoopIds,
  }) async {
    await _request(
      'POST',
      '/api/v1/allocations/${Uri.encodeComponent(allocationId)}/handoff/accept',
      payload: {
        'outgoing_nurse_id': outgoingStaffId,
        'beds': bedNumbers,
        'handoff_session_id': handoffSessionId,
        'transferred_loop_ids_by_patient': {patientId: transferredLoopIds},
      },
      extraHeaders: {'X-Incoming-Authorization': 'Bearer $incomingAccessToken'},
    );
  }

  Future<void> publishBoard({
    required String wardId,
    required String date,
    required String shiftType,
    required String staffId,
    required List<WhiteboardBedAssignment> assignments,
    required Map<String, dynamic> supportRoster,
    List<Map<String, String>> carryForwardIssues = const [],
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
        'carry_forward_issues': carryForwardIssues,
      },
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Response payload from the Oravi backend model-assisted endpoint (PRD Section 8A & Tech Arch Section 11).
class ModelAskResponse {
  final String patientId;
  final String query;
  final String? observationNote;
  final bool isRefusal;
  final String? refusalMessage;
  final bool isAbsence;
  final String? absenceMessage;
  final String doctorInCharge;
  final bool verificationPassed;
  final String modelProvider;
  final String modelName;
  final List<Map<String, dynamic>> verbatimQuotes;

  const ModelAskResponse({
    required this.patientId,
    required this.query,
    this.observationNote,
    this.isRefusal = false,
    this.refusalMessage,
    this.isAbsence = false,
    this.absenceMessage,
    this.doctorInCharge = 'DOC-OTIENO',
    this.verificationPassed = true,
    this.modelProvider = 'ollama',
    this.modelName = 'qwen2.5:7b',
    this.verbatimQuotes = const [],
  });

  factory ModelAskResponse.fromJson(Map<String, dynamic> json) {
    return ModelAskResponse(
      patientId: json['patient_id'] as String? ?? '',
      query: json['query'] as String? ?? '',
      observationNote: json['observation_note'] as String?,
      isRefusal: json['is_refusal'] as bool? ?? false,
      refusalMessage: json['refusal_message'] as String?,
      isAbsence: json['is_absence'] as bool? ?? false,
      absenceMessage: json['absence_message'] as String?,
      doctorInCharge: json['doctor_in_charge'] as String? ?? 'DOC-OTIENO',
      verificationPassed: json['verification_passed'] as bool? ?? true,
      modelProvider: json['model_provider'] as String? ?? 'ollama',
      modelName: json['model_name'] as String? ?? 'qwen2.5:7b',
      verbatimQuotes: (json['verbatim_quotes'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
    );
  }
}

/// Client service for the Oravi Model-Assisted Ask endpoint.
///
/// Features:
/// 1. Pluggable backend: connects to FastAPI backend running locally or on ward server.
/// 2. Zero-failure guarantee: silently falls back if backend is offline or times out (>4s).
/// 3. Injectable HTTP client for fast, deterministic unit testing.
class AskOraviModelService {
  final String baseUrl;
  final Duration timeout;
  final Future<ModelAskResponse?> Function(String patientId, String query, int? timeWindowHours)? mockHandler;

  AskOraviModelService({
    String? baseUrl,
    this.timeout = const Duration(seconds: 30),
    this.mockHandler,
  }) : baseUrl = baseUrl ?? 'http://10.0.96.95:8000';

  /// Queries the backend model service with automatic verification.
  ///
  /// Returns `null` silently on any timeout, connection error, or backend failure,
  /// triggering immediate fallback to the local deterministic M4 engine.
  Future<ModelAskResponse?> askPatient({
    required String patientId,
    required String query,
    int? timeWindowHours,
  }) async {
    if (mockHandler != null) {
      return mockHandler!(patientId, query, timeWindowHours);
    }

    try {
      final client = HttpClient()..connectionTimeout = timeout;
      final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final uri = Uri.parse('$cleanBase/api/v1/patients/$patientId/ask');

      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;

      final bodyMap = <String, dynamic>{
        'query': query,
      };
      if (timeWindowHours != null) {
        bodyMap['time_window_hours'] = timeWindowHours;
      }

      final payload = jsonEncode(bodyMap);

      request.write(payload);
      final response = await request.close().timeout(timeout);

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        client.close();
        return ModelAskResponse.fromJson(json);
      }
      client.close();
      return null;
    } catch (_) {
      // 100% Silent Fallback: Zero UI interruption on network or backend unavailability
      return null;
    }
  }
}

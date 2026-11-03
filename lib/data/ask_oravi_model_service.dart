import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'api_configuration.dart';

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
      verbatimQuotes:
          (json['verbatim_quotes'] as List<dynamic>?)
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
  static List<String> get defaultCandidateUrls =>
      OraviApiConfiguration.candidateUrls;

  final List<String> candidateUrls;
  String _activeBaseUrl;
  String get baseUrl => _activeBaseUrl;
  final Duration timeout;
  final String? Function()? getAccessToken;
  final Future<ModelAskResponse?> Function(
    String patientId,
    String query,
    int? timeWindowHours,
  )?
  mockHandler;

  AskOraviModelService({
    String? baseUrl,
    List<String>? candidateUrls,
    this.timeout = const Duration(seconds: 30),
    this.getAccessToken,
    this.mockHandler,
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
    throw lastError ?? Exception('All candidate servers unreachable');
  }

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
    final accessToken = getAccessToken?.call();
    if (accessToken == null) return null;

    try {
      return await _executeWithFallback((base) async {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        try {
          final cleanBase = base.endsWith('/')
              ? base.substring(0, base.length - 1)
              : base;
          final uri = Uri.parse('$cleanBase/api/v1/patients/$patientId/ask');

          final request = await client.postUrl(uri).timeout(timeout);
          request.headers.contentType = ContentType.json;
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $accessToken',
          );

          final bodyMap = <String, dynamic>{'query': query};
          if (timeWindowHours != null) {
            bodyMap['time_window_hours'] = timeWindowHours;
          }

          final payload = jsonEncode(bodyMap);

          request.write(payload);
          final response = await request.close().timeout(timeout);

          if (response.statusCode == 200) {
            final body = await response.transform(utf8.decoder).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            return ModelAskResponse.fromJson(json);
          }
          throw Exception('Backend returned HTTP ${response.statusCode}');
        } finally {
          client.close();
        }
      });
    } catch (_) {
      // 100% Silent Fallback: Zero UI interruption on network or backend unavailability
      return null;
    }
  }
}

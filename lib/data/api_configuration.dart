import 'package:flutter/foundation.dart';

/// Central configuration for the Oravi API.
///
/// Non-debug builds only use an explicitly configured HTTPS endpoint. The
/// private-network defaults are intentionally available only for local demos.
class OraviApiConfiguration {
  static const String configuredBaseUrl = String.fromEnvironment(
    'ORAVI_API_BASE_URL',
  );

  static List<String> get candidateUrls {
    if (configuredBaseUrl.isNotEmpty) return [configuredBaseUrl];
    if (kDebugMode) {
      return const [
        'http://127.0.0.1:8000',
        'http://172.16.20.186:8000',
        'http://10.0.96.95:8000',
      ];
    }
    return const [];
  }

  static void validateBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasAuthority) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'Must be a valid URL.');
    }

    final isLoopback = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (!kDebugMode && (uri.scheme != 'https' || isLoopback)) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Production API endpoints must use HTTPS.',
      );
    }
  }
}

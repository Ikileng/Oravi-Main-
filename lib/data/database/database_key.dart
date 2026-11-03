import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores a random database encryption key in Android Keystore / Apple Keychain.
class DatabaseKey {
  static const _storageKey = 'oravi_local_database_key_v1';
  static const _secureStorage = FlutterSecureStorage();

  static Future<String> loadOrCreate() async {
    final existing = await _secureStorage.read(key: _storageKey);
    if (existing != null && _isValidKey(existing)) return existing;
    if (existing != null) {
      throw StateError('The saved local database key is invalid.');
    }

    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64UrlEncode(keyBytes);
    await _secureStorage.write(key: _storageKey, value: key);
    return key;
  }

  static bool _isValidKey(String key) {
    try {
      return base64Url.decode(base64Url.normalize(key)).length == 32;
    } on FormatException {
      return false;
    }
  }
}

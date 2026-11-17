import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../domain/models/hospital_ward.dart';
import '../../domain/models/staff_profile.dart';
import '../database/database.dart';

const _offlinePinIterations = 310000;
const _offlineSessionLifetime = Duration(hours: 8);

class OfflineLogin {
  final StaffProfile staff;
  final HospitalWard ward;
  final String shiftType;

  const OfflineLogin({
    required this.staff,
    required this.ward,
    required this.shiftType,
  });
}

class OfflineAuthStore {
  final OraviLocalDatabase database;

  const OfflineAuthStore(this.database);

  /// Enrolls this clinician for local unlock after the server has verified the PIN.
  /// The PIN itself is never persisted; only a salted PBKDF2 verifier is stored
  /// inside the encrypted local database.
  Future<void> rememberSuccessfulOnlineLogin({
    required StaffProfile staff,
    required String identifier,
    required String pin,
    required HospitalWard ward,
    required String shiftType,
  }) async {
    if (!staff.isClinical || pin.isEmpty) return;

    final previous = await _readCredential(staff.staffId);
    final cachedWard = ward.wardId.isNotEmpty
        ? ward
        : previous == null
        ? ward
        : HospitalWard.fromMap(
            Map<String, dynamic>.from(previous['ward'] as Map),
          );
    final cachedShift = ward.wardId.isNotEmpty
        ? shiftType
        : previous?['shift_type'] as String? ?? shiftType;
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final verifier = await Isolate.run(
      () => _derivePinVerifier(pin, salt, _offlinePinIterations),
    );
    final credential = <String, dynamic>{
      'staff': staff.toJson(),
      'pin_salt': base64Encode(salt),
      'pin_verifier': base64Encode(verifier),
      'pin_iterations': _offlinePinIterations,
      'online_authenticated_at': DateTime.now().toUtc().toIso8601String(),
      'ward': cachedWard.toMap(),
      'shift_type': cachedShift,
      'failed_attempts': 0,
      'locked_until': null,
      'offline_disabled': false,
    };
    await database.saveLocalValue(
      _credentialKey(staff.staffId),
      jsonEncode(credential),
    );
    await database.saveLocalValue(_lookupKey(identifier), staff.staffId);
    await database.saveLocalValue(_lookupKey(staff.staffId), staff.staffId);
  }

  /// Updates the cached ward scope after a successful online refresh.
  Future<void> updateWardContext({
    required StaffProfile staff,
    required HospitalWard ward,
    required String shiftType,
  }) async {
    final credential = await _readCredential(staff.staffId);
    if (credential == null) return;
    credential['ward'] = ward.toMap();
    credential['shift_type'] = shiftType;
    credential['online_authenticated_at'] = DateTime.now()
        .toUtc()
        .toIso8601String();
    await database.saveLocalValue(
      _credentialKey(staff.staffId),
      jsonEncode(credential),
    );
  }

  Future<OfflineLogin?> verify(String identifier, String pin) async {
    final staffId = await database.readLocalValue(_lookupKey(identifier));
    if (staffId == null) return null;
    final credential = await _readCredential(staffId);
    if (credential == null || credential['offline_disabled'] == true) {
      return null;
    }

    final staff = StaffProfile.fromJson(
      Map<String, dynamic>.from(credential['staff'] as Map),
    );
    final lastOnline = DateTime.tryParse(
      credential['online_authenticated_at'] as String? ?? '',
    );
    final lastObserved = DateTime.tryParse(
      credential['last_offline_verified_at'] as String? ?? '',
    );
    final now = DateTime.now().toUtc();
    if (lastOnline == null ||
        now.isBefore(lastOnline.toUtc()) ||
        (lastObserved != null && now.isBefore(lastObserved.toUtc())) ||
        now.difference(lastOnline.toUtc()) > _offlineSessionLifetime ||
        !staff.isActive) {
      return null;
    }

    final lockedUntil = DateTime.tryParse(
      credential['locked_until'] as String? ?? '',
    );
    if (lockedUntil != null && now.isBefore(lockedUntil.toUtc())) {
      return null;
    }

    final salt = base64Decode(credential['pin_salt'] as String);
    final iterations = credential['pin_iterations'] as int;
    final candidate = await Isolate.run(
      () => _derivePinVerifier(pin, salt, iterations),
    );
    final expected = base64Decode(credential['pin_verifier'] as String);
    if (!_constantTimeEquals(candidate, expected)) {
      final attempts = (credential['failed_attempts'] as int? ?? 0) + 1;
      final offlineDisabled = attempts >= 10;
      final lockout = attempts >= 5
          ? now.add(Duration(minutes: min(30, 1 << (attempts - 5))))
          : null;
      credential['failed_attempts'] = attempts;
      credential['locked_until'] = lockout?.toUtc().toIso8601String();
      credential['offline_disabled'] = offlineDisabled;
      await database.saveLocalValue(
        _credentialKey(staffId),
        jsonEncode(credential),
      );
      return null;
    }

    final ward = HospitalWard.fromMap(
      Map<String, dynamic>.from(credential['ward'] as Map),
    );
    credential['failed_attempts'] = 0;
    credential['locked_until'] = null;
    credential['last_offline_verified_at'] = now.toIso8601String();
    await database.saveLocalValue(
      _credentialKey(staffId),
      jsonEncode(credential),
    );
    return OfflineLogin(
      staff: staff,
      ward: ward,
      shiftType: credential['shift_type'] as String? ?? 'day',
    );
  }

  Future<Map<String, dynamic>?> _readCredential(String staffId) async {
    final raw = await database.readLocalValue(_credentialKey(staffId));
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  String _lookupKey(String identifier) =>
      'offline_auth_lookup:${identifier.trim().toLowerCase()}';

  String _credentialKey(String staffId) => 'offline_auth_staff:$staffId';
}

List<int> _derivePinVerifier(String pin, List<int> salt, int iterations) {
  final password = utf8.encode(pin);
  final input = [...salt, 0, 0, 0, 1];
  var block = Hmac(sha256, password).convert(input).bytes;
  final result = List<int>.from(block);
  for (var round = 1; round < iterations; round++) {
    block = Hmac(sha256, password).convert(block).bytes;
    for (var index = 0; index < result.length; index++) {
      result[index] ^= block[index];
    }
  }
  return result;
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../data/notifications/medical_issue_push_service.dart';
import '../../data/auth/offline_auth_store.dart';
import '../../data/auth/staff_auth_service.dart';
import '../../data/database/database_provider.dart';
import '../../data/ward_board_service.dart';
import '../../domain/models/staff_profile.dart';
import '../../domain/models/hospital_ward.dart';
import 'ward_context_providers.dart';

final localDeviceIdProvider = Provider<String>(
  (ref) =>
      throw StateError('The app device identity has not been initialized.'),
);

class MedicalIssuePushController extends Notifier<String?> {
  Future<void> _pendingOperation = Future<void>.value();

  @override
  String? build() => null;

  Future<void> register({
    required String accessToken,
    required String deviceId,
  }) => _queue(() async {
    try {
      await ref
          .read(medicalIssuePushServiceProvider)
          .register(
            accessToken: accessToken,
            deviceId: deviceId,
            onError: (message) {
              if (ref.mounted) state = message;
            },
          );
      if (!ref.mounted) return;
      state = null;
    } catch (error) {
      if (!ref.mounted) return;
      state =
          'Oravi notifications could not be enabled (${error.runtimeType}). Check Firebase setup and notification permission.';
    }
  });

  Future<void> unregister({
    required String accessToken,
    required String deviceId,
  }) => _queue(() async {
    try {
      await ref
          .read(medicalIssuePushServiceProvider)
          .unregister(accessToken: accessToken, deviceId: deviceId);
      if (!ref.mounted) return;
      state = null;
    } catch (error) {
      if (!ref.mounted) return;
      state =
          'Medical Issue alerts could not be fully disabled (${error.runtimeType}).';
    }
  });

  Future<void> _queue(Future<void> Function() operation) {
    final next = _pendingOperation.then((_) => operation());
    _pendingOperation = next;
    return next;
  }
}

final medicalIssuePushServiceProvider = Provider<MedicalIssuePushService>((
  ref,
) {
  final service = MedicalIssuePushService();
  ref.onDispose(service.dispose);
  return service;
});

final medicalIssuePushControllerProvider =
    NotifierProvider<MedicalIssuePushController, String?>(
      MedicalIssuePushController.new,
    );

/// Provider for backend staff authentication and account management.
final staffAuthServiceProvider = Provider<StaffAuthService>(
  (ref) => StaffAuthService(),
);

/// Roster of staff members for the current ward.
final wardStaffListProvider = FutureProvider<List<StaffProfile>>((ref) async {
  final service = ref.watch(staffAuthServiceProvider);
  return service.getStaffForWard('');
});

final patientStaffListProvider =
    FutureProvider.family<List<StaffProfile>, String>((ref, patientId) async {
      final token = ref.watch(authAccessTokenProvider);
      final offline = ref.watch(offlineSessionProvider);
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final cacheKey = 'patient_staff:$patientId:$date';
      final db = ref.read(localDatabaseProvider);
      if (offline || token == null) {
        final cached = await db.readCachedJson(cacheKey);
        return (cached?['staff'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  StaffProfile.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
      }
      final service = WardBoardService(
        getAccessToken: () => ref.read(authAccessTokenProvider),
      );
      try {
        final staff = await service.getStaffForPatient(
          patientId: patientId,
          date: date,
        );
        await db.cacheJson(cacheKey, {
          'staff': staff.map((member) => member.toJson()).toList(),
        });
        return staff;
      } catch (_) {
        final cached = await db.readCachedJson(cacheKey);
        if (cached == null) rethrow;
        return (cached['staff'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  StaffProfile.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
      }
    });

/// Currently authenticated clinical staff member on this device.
class AuthenticatedStaffNotifier extends Notifier<StaffProfile?> {
  @override
  StaffProfile? build() => null;

  void setStaff(StaffProfile? staff) => state = staff;
}

final authenticatedStaffProvider =
    NotifierProvider<AuthenticatedStaffNotifier, StaffProfile?>(
      AuthenticatedStaffNotifier.new,
    );

/// Short-lived access token returned by the trusted API; held only in memory.
class AuthAccessTokenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setToken(String? token) => state = token;
}

final authAccessTokenProvider =
    NotifierProvider<AuthAccessTokenNotifier, String?>(
      AuthAccessTokenNotifier.new,
    );

class OfflineSessionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setOffline(bool value) => state = value;
}

final offlineSessionProvider = NotifierProvider<OfflineSessionNotifier, bool>(
  OfflineSessionNotifier.new,
);

/// Last loaded server preference. The profile fetches it before enabling edits;
/// sign-in, logout, and connection changes never overwrite the preference.
class ClinicianAvailabilityNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setAvailable(bool value) => state = value;
}

final clinicianAvailabilityProvider =
    NotifierProvider<ClinicianAvailabilityNotifier, bool>(
      ClinicianAvailabilityNotifier.new,
    );

const _sessionCredentialStorage = FlutterSecureStorage();
const _sessionCredentialKey = 'oravi_authenticated_session_v1';
const _sessionTokenLifetime = Duration(hours: 8);

class AuthState {
  final bool isLoading;
  final String? errorMessage;
  final int failedAttempts;

  const AuthState({
    this.isLoading = false,
    this.errorMessage,
    this.failedAttempts = 0,
  });

  AuthState copyWith({
    bool? isLoading,
    String? errorMessage,
    int? failedAttempts,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      failedAttempts: failedAttempts ?? this.failedAttempts,
    );
  }
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Future<bool> verifyAndLogin(String identifier, String pin) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final service = ref.read(staffAuthServiceProvider);
    final result = await service.verifyPin(identifier, pin);

    if (!result.success && result.networkUnavailable) {
      try {
        final offline = await OfflineAuthStore(
          ref.read(localDatabaseProvider),
        ).verify(identifier, pin);
        if (offline != null) {
          ref.read(authenticatedStaffProvider.notifier).setStaff(offline.staff);
          final savedSession = await _readSavedSession(offline.staff.staffId);
          ref.read(authAccessTokenProvider.notifier).setToken(savedSession);
          ref.read(offlineSessionProvider.notifier).setOffline(true);
          ref.read(selectedWardProvider.notifier).selectWard(offline.ward);
          ref
              .read(selectedShiftTypeProvider.notifier)
              .select(offline.shiftType);
          ref
              .read(wardContextNeedsConfirmationProvider.notifier)
              .setNeedsConfirmation(false);
          ref.read(wardContextErrorProvider.notifier).setError(null);
          state = const AuthState();
          return true;
        }
      } catch (_) {
        // If local unlock is unavailable, preserve the normal sign-in error.
      }
    }

    final authenticatedStaff = result.staff;
    final token = result.token;

    if (result.success &&
        authenticatedStaff != null &&
        authenticatedStaff.isActive &&
        token != null &&
        token.isNotEmpty) {
      ref
          .read(authenticatedStaffProvider.notifier)
          .setStaff(authenticatedStaff);
      ref
          .read(authAccessTokenProvider.notifier)
          .setToken(!token.startsWith('offline_token_') ? token : null);
      if (!token.startsWith('offline_token_')) {
        try {
          await _saveSessionCredential(authenticatedStaff.staffId, token);
        } catch (_) {
          // The online session remains valid if secure persistence is unavailable.
        }
      }
      ref.read(offlineSessionProvider.notifier).setOffline(false);
      if (authenticatedStaff.role != 'dev_admin' &&
          !token.startsWith('offline_token_')) {
        unawaited(
          ref
              .read(medicalIssuePushControllerProvider.notifier)
              .register(
                accessToken: token,
                deviceId: ref.read(localDeviceIdProvider),
              ),
        );
      }
      final boardService = WardBoardService(
        getAccessToken: () => ref.read(authAccessTokenProvider),
      );
      ref.read(wardContextErrorProvider.notifier).setError(null);
      if (!authenticatedStaff.isClinical) {
        ref.read(selectedWardProvider.notifier).selectWard(_noWard());
        state = const AuthState();
        return true;
      }
      try {
        if (authenticatedStaff.role == 'charge_nurse') {
          final preferredWard = await boardService.getPreferredWard();
          ref
              .read(selectedWardProvider.notifier)
              .selectWard(preferredWard ?? _noWard());
          ref
              .read(wardContextNeedsConfirmationProvider.notifier)
              .setNeedsConfirmation(preferredWard != null);
        } else {
          final date = DateTime.now().toIso8601String().substring(0, 10);
          var shiftType = ref.read(selectedShiftTypeProvider);
          var assignment = await boardService.getActiveAssignment(
            date: date,
            shiftType: shiftType,
          );
          if (assignment == null) {
            shiftType = shiftType == 'day' ? 'night' : 'day';
            assignment = await boardService.getActiveAssignment(
              date: date,
              shiftType: shiftType,
            );
          }
          ref.read(selectedShiftTypeProvider.notifier).select(shiftType);
          ref
              .read(selectedWardProvider.notifier)
              .selectWard(
                assignment == null
                    ? _noWard()
                    : HospitalWard(
                        wardId: assignment['ward_id'] as String,
                        name: assignment['ward_name'] as String,
                        bedCount: 0,
                        bedNumbers: const [],
                        department: '',
                        description: '',
                      ),
              );
        }
      } catch (error) {
        ref.read(selectedWardProvider.notifier).selectWard(_noWard());
        ref
            .read(wardContextErrorProvider.notifier)
            .setError('Could not load your ward assignment: $error');
      }
      try {
        await OfflineAuthStore(
          ref.read(localDatabaseProvider),
        ).rememberSuccessfulOnlineLogin(
          staff: authenticatedStaff,
          identifier: identifier,
          pin: pin,
          ward: ref.read(selectedWardProvider),
          shiftType: ref.read(selectedShiftTypeProvider),
        );
      } catch (_) {
        // Online sign-in remains valid if local offline enrollment fails.
      }
      state = const AuthState(
        isLoading: false,
        errorMessage: null,
        failedAttempts: 0,
      );
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        errorMessage: result.networkUnavailable
            ? 'Oravi cannot reach sign-in. If you have signed in on this device recently, enter your PIN to unlock saved offline data.'
            : result.error ?? 'Authentication failed or session was invalid.',
        failedAttempts: state.failedAttempts + 1,
      );
      return false;
    }
  }

  void logout() {
    // Keep the device registered for call availability after clinical logout.
    ref.read(authenticatedStaffProvider.notifier).setStaff(null);
    ref.read(authAccessTokenProvider.notifier).setToken(null);
    unawaited(_sessionCredentialStorage.delete(key: _sessionCredentialKey));
    ref.read(offlineSessionProvider.notifier).setOffline(false);
    ref.read(selectedWardProvider.notifier).selectWard(_noWard());
    ref
        .read(wardContextNeedsConfirmationProvider.notifier)
        .setNeedsConfirmation(false);
    ref.read(wardContextErrorProvider.notifier).setError(null);
    state = const AuthState();
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  HospitalWard _noWard() => const HospitalWard(
    wardId: '',
    name: 'No ward assigned',
    bedCount: 0,
    bedNumbers: [],
    department: '',
    description: '',
  );
}

Future<void> _saveSessionCredential(String staffId, String token) async {
  await _sessionCredentialStorage.write(
    key: _sessionCredentialKey,
    value: jsonEncode({
      'staff_id': staffId,
      'token': token,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
    }),
  );
}

Future<String?> _readSavedSession(String staffId) async {
  final raw = await _sessionCredentialStorage.read(key: _sessionCredentialKey);
  if (raw == null) return null;
  try {
    final saved = jsonDecode(raw) as Map<String, dynamic>;
    final savedAt = DateTime.tryParse(saved['saved_at'] as String? ?? '');
    final token = saved['token'] as String?;
    final now = DateTime.now().toUtc();
    if (saved['staff_id'] != staffId ||
        token == null ||
        token.isEmpty ||
        savedAt == null ||
        now.isBefore(savedAt.toUtc()) ||
        now.difference(savedAt.toUtc()) > _sessionTokenLifetime) {
      return null;
    }
    return token;
  } catch (_) {
    return null;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

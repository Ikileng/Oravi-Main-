import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/notifications/medical_issue_push_service.dart';
import '../../data/auth/staff_auth_service.dart';
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
          'Medical Issue alerts could not be enabled (${error.runtimeType}). Check Firebase setup and notification permission.';
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
      final service = WardBoardService(
        getAccessToken: () => ref.read(authAccessTokenProvider),
      );
      final date = DateTime.now().toIso8601String().substring(0, 10);
      return service.getStaffForPatient(patientId: patientId, date: date);
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

  Future<bool> verifyAndLogin(String staffId, String pin) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final service = ref.read(staffAuthServiceProvider);
    final result = await service.verifyPin(staffId, pin);

    final authenticatedStaff = result.staff;
    final token = result.token;

    if (result.success &&
        authenticatedStaff != null &&
        authenticatedStaff.staffId == staffId &&
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
      state = const AuthState(
        isLoading: false,
        errorMessage: null,
        failedAttempts: 0,
      );
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            result.error ?? 'Authentication failed or session was invalid.',
        failedAttempts: state.failedAttempts + 1,
      );
      return false;
    }
  }

  void logout() {
    final token = ref.read(authAccessTokenProvider);
    if (token != null) {
      unawaited(
        ref
            .read(medicalIssuePushControllerProvider.notifier)
            .unregister(
              accessToken: token,
              deviceId: ref.read(localDeviceIdProvider),
            ),
      );
    }
    ref.read(authenticatedStaffProvider.notifier).setStaff(null);
    ref.read(authAccessTokenProvider.notifier).setToken(null);
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

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

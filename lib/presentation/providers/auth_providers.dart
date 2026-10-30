import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/auth/staff_auth_service.dart';
import '../../domain/models/staff_profile.dart';

/// Provider for staff authentication service with multi-host auto-fallback.
final staffAuthServiceProvider = Provider<StaffAuthService>((ref) {
  return StaffAuthService();
});

/// Roster of staff members for the current ward.
final wardStaffListProvider = FutureProvider<List<StaffProfile>>((ref) async {
  final service = ref.watch(staffAuthServiceProvider);
  return service.getStaffForWard('WARD-4B');
});

/// Currently authenticated clinical staff member on this device.
class AuthenticatedStaffNotifier extends Notifier<StaffProfile?> {
  @override
  StaffProfile? build() => null;

  void setStaff(StaffProfile? staff) => state = staff;
}

final authenticatedStaffProvider =
    NotifierProvider<AuthenticatedStaffNotifier, StaffProfile?>(AuthenticatedStaffNotifier.new);

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

    if (result.success && result.staff != null) {
      ref.read(authenticatedStaffProvider.notifier).setStaff(result.staff);
      state = const AuthState(isLoading: false, errorMessage: null, failedAttempts: 0);
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        errorMessage: result.error ?? 'Authentication failed',
        failedAttempts: state.failedAttempts + 1,
      );
      return false;
    }
  }

  void logout() {
    ref.read(authenticatedStaffProvider.notifier).setStaff(null);
    state = const AuthState();
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

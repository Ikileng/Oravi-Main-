import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/auth/staff_auth_service.dart';
import 'package:oravi_app/domain/models/staff_profile.dart';
import 'package:oravi_app/presentation/providers/auth_providers.dart';

void main() {
  test('offline sign-in fails closed without loading or accepting demo staff', () async {
    final service = StaffAuthService(
      candidateUrls: const ['http://127.0.0.1:1'],
      timeout: const Duration(milliseconds: 300),
    );

    await expectLater(
      service.getStaffForWard('WARD-4B'),
      throwsA(anything),
    );

    final result = await service.verifyPin('NUR-401', '1234');
    expect(result.success, isFalse);
    expect(result.staff, isNull);
    expect(result.token, isNull);
    expect(result.error, contains('unavailable'));
  });

  test('sign-in rejects a mismatched or inactive staff identity', () async {
    final returnedStaff = StaffProfile(
      staffId: 'NUR-402',
      name: 'Grace Achieng, RN',
      role: 'charge_nurse',
      wardId: 'WARD-4B',
      avatarColor: '#2563EB',
      initials: 'GA',
    );
    final service = StaffAuthService(
      mockVerifyPinHandler: (_, _) async => AuthResult(
        success: true,
        staff: returnedStaff,
        token: 'server-session-token',
      ),
    );
    final container = ProviderContainer(
      overrides: [staffAuthServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    expect(
      await container
          .read(authControllerProvider.notifier)
          .verifyAndLogin('NUR-401', '1234'),
      isFalse,
    );
    expect(container.read(authenticatedStaffProvider), isNull);
    expect(container.read(authAccessTokenProvider), isNull);

    final inactiveService = StaffAuthService(
      mockVerifyPinHandler: (_, _) async => AuthResult(
        success: true,
        staff: returnedStaff.copyWith(isActive: false),
        token: 'server-session-token',
      ),
    );
    final inactiveContainer = ProviderContainer(
      overrides: [staffAuthServiceProvider.overrideWithValue(inactiveService)],
    );
    addTearDown(inactiveContainer.dispose);
    expect(
      await inactiveContainer
          .read(authControllerProvider.notifier)
          .verifyAndLogin('NUR-402', '5678'),
      isFalse,
    );
    expect(inactiveContainer.read(authenticatedStaffProvider), isNull);
  });

  test(
    'valid sign-in holds token only for the active session and clears on logout',
    () async {
      final staff = StaffProfile(
        staffId: 'NUR-401',
        name: 'Mary Wanjiku, RN',
        role: 'ward_nurse',
        wardId: 'WARD-4B',
        avatarColor: '#059669',
        initials: 'MW',
      );
      final service = StaffAuthService(
        mockVerifyPinHandler: (_, _) async => AuthResult(
          success: true,
          staff: staff,
          token: 'server-session-token',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          staffAuthServiceProvider.overrideWithValue(service),
          localDeviceIdProvider.overrideWithValue('DEVICE-auth-test'),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container
            .read(authControllerProvider.notifier)
            .verifyAndLogin('NUR-401', '1234'),
        isTrue,
      );
      expect(container.read(authenticatedStaffProvider)?.staffId, 'NUR-401');
      expect(container.read(authAccessTokenProvider), 'server-session-token');

      container.read(authControllerProvider.notifier).logout();
      expect(container.read(authenticatedStaffProvider), isNull);
      expect(container.read(authAccessTokenProvider), isNull);
    },
  );
}

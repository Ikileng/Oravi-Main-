import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/database_provider.dart';
import '../../data/ward_board_service.dart';
import '../../domain/models/staff_profile.dart';
import '../../domain/models/whiteboard_models.dart';
import 'auth_providers.dart';
import 'ward_context_providers.dart';

String activeWardShiftDate() =>
    DateTime.now().toIso8601String().substring(0, 10);

class WardBoardData {
  final String? allocationId;
  final List<WhiteboardBedAssignment> assignments;
  final WardSupportRoster supportRoster;
  final List<String> availableNurseIds;

  const WardBoardData({
    this.allocationId,
    this.assignments = const [],
    this.supportRoster = const WardSupportRoster(),
    this.availableNurseIds = const [],
  });

  factory WardBoardData.fromMap(Map<String, dynamic> map) {
    final assignments = map['bed_assignments'];
    final responsibilities = map['responsibilities'];
    return WardBoardData(
      allocationId: map['allocation_id'] as String?,
      availableNurseIds: List<String>.from(
        map['available_nurse_ids'] ?? const [],
      ),
      assignments: assignments is List
          ? assignments
                .map(
                  (item) => WhiteboardBedAssignment.fromMap(
                    item as Map<String, dynamic>,
                  ),
                )
                .toList()
          : const [],
      supportRoster: responsibilities is Map<String, dynamic>
          ? WardSupportRoster.fromMap(responsibilities)
          : const WardSupportRoster(),
    );
  }
}

final wardBoardServiceProvider = Provider<WardBoardService>((ref) {
  return WardBoardService(
    getAccessToken: () => ref.read(authAccessTokenProvider),
  );
});

final carriedForwardIssuesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, _) {
      ref.watch(authAccessTokenProvider);
      return ref.read(wardBoardServiceProvider).getCarriedForwardIssues();
    });

class WardBoardNotifier extends AsyncNotifier<WardBoardData> {
  @override
  Future<WardBoardData> build() async {
    final ward = ref.watch(selectedWardProvider);
    final shift = ref.watch(selectedShiftTypeProvider);
    final token = ref.watch(authAccessTokenProvider);
    final offline = ref.watch(offlineSessionProvider);
    final staff = ref.watch(authenticatedStaffProvider);
    final needsConfirmation = ref.watch(wardContextNeedsConfirmationProvider);
    if (ward.wardId.isEmpty || staff?.isClinical != true) {
      return const WardBoardData();
    }
    if (staff?.role == 'charge_nurse' && needsConfirmation) {
      return const WardBoardData();
    }
    final cacheKey = _boardCacheKey(ward.wardId, activeWardShiftDate(), shift);
    if (token == null || offline) {
      final cached = await ref
          .read(localDatabaseProvider)
          .readCachedJson(cacheKey);
      return cached == null
          ? const WardBoardData()
          : WardBoardData.fromMap(cached);
    }
    try {
      final response = await ref
          .read(wardBoardServiceProvider)
          .getBoard(
            wardId: ward.wardId,
            date: activeWardShiftDate(),
            shiftType: shift,
          );
      await ref
          .read(localDatabaseProvider)
          .cacheJson(cacheKey, Map<String, dynamic>.from(response as Map));
      return WardBoardData.fromMap(Map<String, dynamic>.from(response as Map));
    } catch (_) {
      final cached = await ref
          .read(localDatabaseProvider)
          .readCachedJson(cacheKey);
      if (cached != null) return WardBoardData.fromMap(cached);
      rethrow;
    }
  }

  String get _shiftType => ref.read(selectedShiftTypeProvider);

  Future<void> changeDoctor(
    WhiteboardBedAssignment bed,
    String doctorId,
  ) async {
    final ward = ref.read(selectedWardProvider);
    if (ref.read(authAccessTokenProvider) == null ||
        ref.read(offlineSessionProvider)) {
      final current = state.asData?.value ?? const WardBoardData();
      final assignments = current.assignments
          .map(
            (item) => item.bedNumber == bed.bedNumber
                ? item.copyWith(admittingDoctor: doctorId)
                : item,
          )
          .toList();
      await _save(assignments, current.supportRoster);
      return;
    }
    try {
      await ref
          .read(wardBoardServiceProvider)
          .communicationRequest(
            'PUT',
            '/wards/${Uri.encodeComponent(ward.wardId)}/beds/${Uri.encodeComponent(bed.bedNumber)}/doctor',
            payload: {
              'date': activeWardShiftDate(),
              'patient_id': bed.patientId,
              'expected_doctor_id': bed.admittingDoctor,
              'doctor_id': doctorId,
            },
          );
    } catch (error) {
      if (!error.toString().contains('Could not reach the Oravi service')) {
        rethrow;
      }
      final current = state.asData?.value ?? const WardBoardData();
      final assignments = current.assignments
          .map(
            (item) => item.bedNumber == bed.bedNumber
                ? item.copyWith(admittingDoctor: doctorId)
                : item,
          )
          .toList();
      await _save(assignments, current.supportRoster);
      return;
    }
    ref.invalidateSelf();
  }

  Future<void> updateAssignment(
    String bedNumber, {
    String? nurseId,
    String? doctor,
    String? patientInitials,
    String? patientId,
    String? status,
    List<Map<String, String>> carryForwardIssues = const [],
  }) async {
    final current = state.asData?.value ?? const WardBoardData();
    final assignments = current.assignments.map((bed) {
      if (bed.bedNumber != bedNumber) return bed;
      final initials = patientInitials ?? bed.patientInitials;
      final suppliedPatientId = patientId?.trim();
      final resolvedPatientId = initials.trim().isEmpty
          ? null
          : suppliedPatientId != null && suppliedPatientId.isNotEmpty
          ? suppliedPatientId
          : initials == bed.patientInitials
          ? bed.patientId ?? 'PAT-${const Uuid().v7()}'
          : 'PAT-${const Uuid().v7()}';
      return bed.copyWith(
        patientId: resolvedPatientId,
        clearPatientId: resolvedPatientId == null,
        patientInitials: initials,
        admittingDoctor: doctor ?? bed.admittingDoctor,
        dayShiftNurseId: _shiftType == 'day'
            ? nurseId ?? bed.dayShiftNurseId
            : bed.dayShiftNurseId,
        nightShiftNurseId: _shiftType == 'night'
            ? nurseId ?? bed.nightShiftNurseId
            : bed.nightShiftNurseId,
        status: status ?? bed.status,
      );
    }).toList();
    await _save(
      assignments,
      current.supportRoster,
      carryForwardIssues: carryForwardIssues,
    );
  }

  Future<void> batchAssignBeds(List<String> bedNumbers, String staffId) async {
    final current = state.asData?.value ?? const WardBoardData();
    final assignments = current.assignments.map((bed) {
      if (!bedNumbers.contains(bed.bedNumber)) return bed;
      return bed.copyWith(
        dayShiftNurseId: _shiftType == 'day' ? staffId : bed.dayShiftNurseId,
        nightShiftNurseId: _shiftType == 'night'
            ? staffId
            : bed.nightShiftNurseId,
      );
    }).toList();
    await _save(assignments, current.supportRoster);
  }

  Future<void> acceptBeds(List<String> bedNumbers, String staffId) async {
    final current = state.asData?.value ?? const WardBoardData();
    final assignments = current.assignments.map((bed) {
      final owner = _shiftType == 'day'
          ? bed.dayShiftNurseId
          : bed.nightShiftNurseId;
      if (bedNumbers.contains(bed.bedNumber) && owner == staffId) {
        return bed.copyWith(status: 'accepted');
      }
      return bed;
    }).toList();
    await _save(assignments, current.supportRoster);
  }

  Future<void> acceptHandoffBeds({
    required List<String> bedNumbers,
    required String outgoingStaffId,
    required String incomingAccessToken,
    required String handoffSessionId,
    required String patientId,
    required List<String> transferredLoopIds,
  }) async {
    final current = state.asData?.value ?? const WardBoardData();
    final ward = ref.read(selectedWardProvider);
    final shift = ref.read(selectedShiftTypeProvider);
    final allocationId = current.allocationId;
    if (ward.wardId.isEmpty || allocationId == null) {
      throw StateError('The current ward has no published allocation.');
    }
    state = const AsyncLoading();
    try {
      await ref
          .read(wardBoardServiceProvider)
          .acceptHandoffBeds(
            allocationId: allocationId,
            outgoingStaffId: outgoingStaffId,
            incomingAccessToken: incomingAccessToken,
            bedNumbers: bedNumbers,
            handoffSessionId: handoffSessionId,
            patientId: patientId,
            transferredLoopIds: transferredLoopIds,
          );
      final response = await ref
          .read(wardBoardServiceProvider)
          .getBoard(
            wardId: ward.wardId,
            date: activeWardShiftDate(),
            shiftType: shift,
          );
      state = AsyncData(WardBoardData.fromMap(response));
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> updateRoster(WardSupportRoster roster) async {
    final current = state.asData?.value ?? const WardBoardData();
    await _save(current.assignments, roster);
  }

  Future<void> _save(
    List<WhiteboardBedAssignment> assignments,
    WardSupportRoster roster, {
    List<Map<String, String>> carryForwardIssues = const [],
  }) async {
    final ward = ref.read(selectedWardProvider);
    final staff = ref.read(authenticatedStaffProvider);
    if (staff?.isChargeNurse != true) {
      throw StateError('Only the Charge Nurse can edit the ward board.');
    }
    if (ward.wardId.isEmpty || staff == null) {
      throw StateError('Select a ward and sign in before publishing changes.');
    }
    final isOffline =
        ref.read(authAccessTokenProvider) == null ||
        ref.read(offlineSessionProvider);
    if (isOffline && carryForwardIssues.isNotEmpty) {
      throw StateError(
        'Carrying Medical Issues forward needs a connection. The board was not changed.',
      );
    }
    final current = state.asData?.value ?? const WardBoardData();
    final date = activeWardShiftDate();
    final service = ref.read(wardBoardServiceProvider);
    final allocationId = 'ALLOC-${const Uuid().v7()}';
    final payload = service.buildPublishBoardPayload(
      wardId: ward.wardId,
      date: date,
      shiftType: _shiftType,
      staffId: staff.staffId,
      assignments: assignments,
      supportRoster: roster.toMap(),
      carryForwardIssues: carryForwardIssues,
      allocationId: allocationId,
    );
    final cacheKey = _boardCacheKey(ward.wardId, date, _shiftType);
    final localData = <String, dynamic>{
      'allocation_id': allocationId,
      'available_nurse_ids': current.availableNurseIds,
      'bed_assignments': assignments.map((item) => item.toMap()).toList(),
      'responsibilities': roster.toMap(),
    };
    state = const AsyncLoading();
    try {
      await ref.read(localDatabaseProvider).cacheJson(cacheKey, localData);
      if (isOffline) {
        await ref
            .read(localDatabaseProvider)
            .enqueueApiOperation(
              operationId: allocationId,
              method: 'POST',
              path: '/api/v1/allocations/publish',
              payload: payload,
            );
        state = AsyncData(WardBoardData.fromMap(localData));
        return;
      }
      await service.publishBoard(
        wardId: ward.wardId,
        date: date,
        shiftType: _shiftType,
        staffId: staff.staffId,
        assignments: assignments,
        supportRoster: roster.toMap(),
        carryForwardIssues: carryForwardIssues,
        allocationId: allocationId,
      );
      final response = await service.getBoard(
        wardId: ward.wardId,
        date: date,
        shiftType: _shiftType,
      );
      await ref
          .read(localDatabaseProvider)
          .cacheJson(cacheKey, Map<String, dynamic>.from(response as Map));
      state = AsyncData(
        WardBoardData.fromMap(Map<String, dynamic>.from(response as Map)),
      );
    } catch (error, stackTrace) {
      if (!isOffline &&
          error.toString().contains('Could not reach the Oravi service')) {
        await ref
            .read(localDatabaseProvider)
            .enqueueApiOperation(
              operationId: allocationId,
              method: 'POST',
              path: '/api/v1/allocations/publish',
              payload: payload,
            );
        state = AsyncData(WardBoardData.fromMap(localData));
        return;
      }
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

String _boardCacheKey(String wardId, String date, String shift) =>
    'ward_board:$wardId:$date:$shift';

final wardBoardProvider =
    AsyncNotifierProvider<WardBoardNotifier, WardBoardData>(
      WardBoardNotifier.new,
    );

final whiteboardAssignmentsProvider = Provider<List<WhiteboardBedAssignment>>(
  (ref) => ref.watch(wardBoardProvider).asData?.value.assignments ?? const [],
);

class WardSupportRosterNotifier extends Notifier<WardSupportRoster> {
  @override
  WardSupportRoster build() {
    return ref.watch(
          wardBoardProvider.select(
            (board) => board.asData?.value.supportRoster,
          ),
        ) ??
        const WardSupportRoster();
  }

  Future<void> updateRoster(WardSupportRoster roster) =>
      ref.read(wardBoardProvider.notifier).updateRoster(roster);
}

final wardSupportRosterProvider =
    NotifierProvider<WardSupportRosterNotifier, WardSupportRoster>(
      WardSupportRosterNotifier.new,
    );

final boardStaffListProvider = FutureProvider<List<StaffProfile>>((ref) async {
  final wardId = ref.watch(selectedWardProvider).wardId;
  if (wardId.isEmpty) return const [];
  final shift = ref.watch(selectedShiftTypeProvider);
  final key = 'ward_staff:$wardId:${activeWardShiftDate()}:$shift';
  final db = ref.read(localDatabaseProvider);
  if (ref.watch(offlineSessionProvider) ||
      ref.watch(authAccessTokenProvider) == null) {
    final cached = await db.readCachedJson(key);
    return (cached?['staff'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              StaffProfile.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }
  try {
    final staff = await ref
        .read(wardBoardServiceProvider)
        .getStaffForWard(wardId, date: activeWardShiftDate(), shiftType: shift);
    await db.cacheJson(key, {
      'staff': staff.map((item) => item.toJson()).toList(),
    });
    return staff;
  } catch (_) {
    final cached = await db.readCachedJson(key);
    if (cached == null) rethrow;
    return (cached['staff'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              StaffProfile.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }
});

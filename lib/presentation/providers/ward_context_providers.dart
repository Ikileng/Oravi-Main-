import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/hospital_ward.dart';

class SelectedWardNotifier extends Notifier<HospitalWard> {
  @override
  HospitalWard build() => const HospitalWard(
    wardId: '',
    name: 'No ward assigned',
    bedCount: 0,
    bedNumbers: [],
    department: '',
    description: '',
  );

  void selectWard(HospitalWard ward) => state = ward;
}

final selectedWardProvider =
    NotifierProvider<SelectedWardNotifier, HospitalWard>(
      SelectedWardNotifier.new,
    );

class SelectedShiftTypeNotifier extends Notifier<String> {
  @override
  String build() => 'day';

  void select(String shiftType) {
    if (shiftType == 'day' || shiftType == 'night') state = shiftType;
  }
}

final selectedShiftTypeProvider =
    NotifierProvider<SelectedShiftTypeNotifier, String>(
      SelectedShiftTypeNotifier.new,
    );

class WardContextConfirmationNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setNeedsConfirmation(bool value) => state = value;
}

final wardContextNeedsConfirmationProvider =
    NotifierProvider<WardContextConfirmationNotifier, bool>(
      WardContextConfirmationNotifier.new,
    );

class WardContextErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setError(String? value) => state = value;
}

final wardContextErrorProvider =
    NotifierProvider<WardContextErrorNotifier, String?>(
      WardContextErrorNotifier.new,
    );

class WhiteboardBedAssignment {
  final String bedNumber;
  final String? patientId;
  final String patientInitials;
  final String admittingDoctor;
  final String? dayShiftNurseId;
  final String? nightShiftNurseId;
  final String status; // 'pending' | 'accepted' | 'disputed'

  const WhiteboardBedAssignment({
    required this.bedNumber,
    this.patientId,
    required this.patientInitials,
    required this.admittingDoctor,
    this.dayShiftNurseId,
    this.nightShiftNurseId,
    this.status = 'pending',
  });

  WhiteboardBedAssignment copyWith({
    String? bedNumber,
    String? patientId,
    bool clearPatientId = false,
    String? patientInitials,
    String? admittingDoctor,
    String? dayShiftNurseId,
    String? nightShiftNurseId,
    String? status,
  }) {
    return WhiteboardBedAssignment(
      bedNumber: bedNumber ?? this.bedNumber,
      patientId: clearPatientId ? null : patientId ?? this.patientId,
      patientInitials: patientInitials ?? this.patientInitials,
      admittingDoctor: admittingDoctor ?? this.admittingDoctor,
      dayShiftNurseId: dayShiftNurseId ?? this.dayShiftNurseId,
      nightShiftNurseId: nightShiftNurseId ?? this.nightShiftNurseId,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() => {
    'bed_number': bedNumber,
    'patient_id': patientId,
    'patient_initials': patientInitials,
    'admitting_doctor': admittingDoctor,
    'day_shift_nurse_id': dayShiftNurseId,
    'night_shift_nurse_id': nightShiftNurseId,
    'status': status,
  };

  factory WhiteboardBedAssignment.fromMap(Map<String, dynamic> map) {
    return WhiteboardBedAssignment(
      bedNumber: map['bed_number'] as String,
      patientId: map['patient_id'] as String?,
      patientInitials: map['patient_initials'] as String? ?? '',
      admittingDoctor: map['admitting_doctor'] as String? ?? '',
      dayShiftNurseId: map['day_shift_nurse_id'] as String?,
      nightShiftNurseId: map['night_shift_nurse_id'] as String?,
      status: map['status'] as String? ?? 'pending',
    );
  }
}

class WardSupportRoster {
  final String wardManager;
  final String teamLeader;
  final String dutyLeader;
  final String dischargeNurse;
  final String shiftLeader;
  final String inchargeNurseDay;
  final String inchargeNurseNight;
  final String pcaDay;
  final String pcaNight;
  final String housekeeperDay;
  final String housekeeperNight;
  final String cateringDayPhone;
  final String cateringNightPhone;
  final String fireMarshall;

  const WardSupportRoster({
    this.wardManager = '',
    this.teamLeader = '',
    this.dutyLeader = '',
    this.dischargeNurse = '',
    this.shiftLeader = '',
    this.inchargeNurseDay = '',
    this.inchargeNurseNight = '',
    this.pcaDay = '',
    this.pcaNight = '',
    this.housekeeperDay = '',
    this.housekeeperNight = '',
    this.cateringDayPhone = '',
    this.cateringNightPhone = '',
    this.fireMarshall = '',
  });

  WardSupportRoster copyWith({
    String? wardManager,
    String? teamLeader,
    String? dutyLeader,
    String? dischargeNurse,
    String? shiftLeader,
    String? inchargeNurseDay,
    String? inchargeNurseNight,
    String? pcaDay,
    String? pcaNight,
    String? housekeeperDay,
    String? housekeeperNight,
    String? cateringDayPhone,
    String? cateringNightPhone,
    String? fireMarshall,
  }) {
    return WardSupportRoster(
      wardManager: wardManager ?? this.wardManager,
      teamLeader: teamLeader ?? this.teamLeader,
      dutyLeader: dutyLeader ?? this.dutyLeader,
      dischargeNurse: dischargeNurse ?? this.dischargeNurse,
      shiftLeader: shiftLeader ?? this.shiftLeader,
      inchargeNurseDay: inchargeNurseDay ?? this.inchargeNurseDay,
      inchargeNurseNight: inchargeNurseNight ?? this.inchargeNurseNight,
      pcaDay: pcaDay ?? this.pcaDay,
      pcaNight: pcaNight ?? this.pcaNight,
      housekeeperDay: housekeeperDay ?? this.housekeeperDay,
      housekeeperNight: housekeeperNight ?? this.housekeeperNight,
      cateringDayPhone: cateringDayPhone ?? this.cateringDayPhone,
      cateringNightPhone: cateringNightPhone ?? this.cateringNightPhone,
      fireMarshall: fireMarshall ?? this.fireMarshall,
    );
  }

  Map<String, dynamic> toMap() => {
    'ward_manager': wardManager,
    'team_leader': teamLeader,
    'duty_leader': dutyLeader,
    'discharge_nurse': dischargeNurse,
    'shift_leader': shiftLeader,
    'incharge_nurse_day': inchargeNurseDay,
    'incharge_nurse_night': inchargeNurseNight,
    'pca_day': pcaDay,
    'pca_night': pcaNight,
    'housekeeper_day': housekeeperDay,
    'housekeeper_night': housekeeperNight,
    'catering_day_phone': cateringDayPhone,
    'catering_night_phone': cateringNightPhone,
    'fire_marshall': fireMarshall,
  };

  factory WardSupportRoster.fromMap(Map<String, dynamic> map) {
    return WardSupportRoster(
      wardManager: map['ward_manager'] as String? ?? '',
      teamLeader: map['team_leader'] as String? ?? '',
      dutyLeader: map['duty_leader'] as String? ?? '',
      dischargeNurse: map['discharge_nurse'] as String? ?? '',
      shiftLeader: map['shift_leader'] as String? ?? '',
      inchargeNurseDay: map['incharge_nurse_day'] as String? ?? '',
      inchargeNurseNight: map['incharge_nurse_night'] as String? ?? '',
      pcaDay: map['pca_day'] as String? ?? '',
      pcaNight: map['pca_night'] as String? ?? '',
      housekeeperDay: map['housekeeper_day'] as String? ?? '',
      housekeeperNight: map['housekeeper_night'] as String? ?? '',
      cateringDayPhone: map['catering_day_phone'] as String? ?? '',
      cateringNightPhone: map['catering_night_phone'] as String? ?? '',
      fireMarshall: map['fire_marshall'] as String? ?? '',
    );
  }
}

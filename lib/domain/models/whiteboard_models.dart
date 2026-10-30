class WhiteboardBedAssignment {
  final String bedNumber;
  final String patientInitials;
  final String admissionNumber;
  final String admittingDoctor;
  final String? dayShiftNurseId;
  final String? nightShiftNurseId;
  final String status; // 'pending' | 'accepted' | 'disputed'

  const WhiteboardBedAssignment({
    required this.bedNumber,
    required this.patientInitials,
    required this.admissionNumber,
    required this.admittingDoctor,
    this.dayShiftNurseId,
    this.nightShiftNurseId,
    this.status = 'pending',
  });

  Map<String, dynamic> toMap() => {
        'bed_number': bedNumber,
        'patient_initials': patientInitials,
        'admission_number': admissionNumber,
        'admitting_doctor': admittingDoctor,
        'day_shift_nurse_id': dayShiftNurseId,
        'night_shift_nurse_id': nightShiftNurseId,
        'status': status,
      };

  factory WhiteboardBedAssignment.fromMap(Map<String, dynamic> map) {
    return WhiteboardBedAssignment(
      bedNumber: map['bed_number'] as String,
      patientInitials: map['patient_initials'] as String? ?? '',
      admissionNumber: map['admission_number'] as String? ?? '',
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
    this.wardManager = 'CAPRICE A',
    this.teamLeader = '',
    this.dutyLeader = '',
    this.dischargeNurse = '',
    this.shiftLeader = '',
    this.inchargeNurseDay = 'SISTER ACHIENG',
    this.inchargeNurseNight = '',
    this.pcaDay = 'FAITH / MAUREEN',
    this.pcaNight = 'RITAH',
    this.housekeeperDay = 'MATILDA',
    this.housekeeperNight = '072411528',
    this.cateringDayPhone = '0721299472',
    this.cateringNightPhone = '0792777972',
    this.fireMarshall = 'MWATAKU',
  });

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

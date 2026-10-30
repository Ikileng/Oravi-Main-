import '../../domain/models/whiteboard_models.dart';

class SeededGertrudeWhiteboardData {
  static const String ward3Id = 'ward-3';
  static const String ward3Name = 'Ward 3';
  static const String jacarandaWardId = 'ward-jacaranda';
  static const String jacarandaWardName = 'Jacaranda Ward (Pediatrics)';

  static WardSupportRoster getGertrudeSupportRoster() {
    return const WardSupportRoster(
      wardManager: 'Nurse E',
      teamLeader: 'Nurse A',
      dutyLeader: 'Nurse B',
      dischargeNurse: 'Nurse C',
      shiftLeader: 'Nurse A',
      inchargeNurseDay: 'Nurse E',
      inchargeNurseNight: 'Nurse B',
      pcaDay: 'Nurse D',
      pcaNight: 'RITAH',
      housekeeperDay: 'MATILDA',
      housekeeperNight: '072411528',
      cateringDayPhone: '0721299472',
      cateringNightPhone: '0792777972',
      fireMarshall: 'MWATAKU',
    );
  }

  /// Initial assignments for Beds 1 to 10 strictly matching design
  static List<WhiteboardBedAssignment> getInitialWard3Assignments() {
    return const [
      WhiteboardBedAssignment(
        bedNumber: '1',
        patientInitials: 'J.N',
        admissionNumber: 'ADM-2026-0001',
        admittingDoctor: 'Dr. Mbita',
        dayShiftNurseId: 'Nurse A',
        nightShiftNurseId: 'Nurse C',
        status: 'accepted',
      ),
      WhiteboardBedAssignment(
        bedNumber: '2',
        patientInitials: 'M.G',
        admissionNumber: 'ADM-2026-0002',
        admittingDoctor: 'Dr. Lageti',
        dayShiftNurseId: 'Nurse B',
        nightShiftNurseId: 'Nurse D',
        status: 'accepted',
      ),
      WhiteboardBedAssignment(
        bedNumber: '3',
        patientInitials: 'R.A',
        admissionNumber: 'ADM-2026-0003',
        admittingDoctor: 'Dr. Dawkins',
        dayShiftNurseId: 'Nurse C',
        nightShiftNurseId: 'Nurse E',
        status: 'pending',
      ),
      WhiteboardBedAssignment(
        bedNumber: '4',
        patientInitials: 'M.M',
        admissionNumber: 'ADM-2026-0004',
        admittingDoctor: 'Dr. Mbei',
        dayShiftNurseId: 'Nurse A',
        nightShiftNurseId: 'Nurse D',
        status: 'accepted',
      ),
      WhiteboardBedAssignment(
        bedNumber: '5',
        patientInitials: 'G.W',
        admissionNumber: 'ADM-2026-0005',
        admittingDoctor: 'Dr. Kimani',
        dayShiftNurseId: 'Nurse E',
        nightShiftNurseId: 'Nurse B',
        status: 'accepted',
      ),
      WhiteboardBedAssignment(
        bedNumber: '6',
        patientInitials: 'A.K',
        admissionNumber: 'ADM-2026-0006',
        admittingDoctor: 'Dr. Osundina',
        dayShiftNurseId: 'Nurse B',
        nightShiftNurseId: 'Nurse C',
        status: 'accepted',
      ),
      WhiteboardBedAssignment(
        bedNumber: '7',
        patientInitials: 'A.M',
        admissionNumber: 'ADM-2026-0007',
        admittingDoctor: 'Dr. Khasong',
        dayShiftNurseId: 'Nurse D',
        nightShiftNurseId: 'Nurse A',
        status: 'accepted',
      ),
      WhiteboardBedAssignment(
        bedNumber: '8',
        patientInitials: 'T.M',
        admissionNumber: 'ADM-2026-0008',
        admittingDoctor: 'Dr. Ravel',
        dayShiftNurseId: 'Nurse C',
        nightShiftNurseId: 'Nurse E',
        status: 'accepted',
      ),
      WhiteboardBedAssignment(
        bedNumber: '9',
        patientInitials: '-',
        admissionNumber: '',
        admittingDoctor: '-',
        dayShiftNurseId: 'Nurse A',
        nightShiftNurseId: 'Nurse D',
        status: 'available',
      ),
      WhiteboardBedAssignment(
        bedNumber: '10',
        patientInitials: 'Y.M',
        admissionNumber: 'ADM-2026-0010',
        admittingDoctor: 'Dr. J. Martins',
        dayShiftNurseId: 'Nurse E',
        nightShiftNurseId: 'Nurse B',
        status: 'accepted',
      ),
    ];
  }

  /// Alias for backward compatibility
  static List<WhiteboardBedAssignment> getInitialJacarandaAssignments() => getInitialWard3Assignments();
}

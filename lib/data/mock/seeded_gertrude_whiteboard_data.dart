import '../../domain/models/whiteboard_models.dart';

class SeededGertrudeWhiteboardData {
  static const String jacarandaWardId = 'ward-jacaranda';
  static const String jacarandaWardName = 'Jacaranda Ward (Pediatrics)';

  static WardSupportRoster getGertrudeSupportRoster() {
    return const WardSupportRoster(
      wardManager: 'CAPRICE A',
      teamLeader: '',
      shiftLeader: '',
      inchargeNurseDay: 'SISTER ACHIENG',
      inchargeNurseNight: '',
      pcaDay: 'FAITH / MAUREEN',
      pcaNight: 'RITAH',
      housekeeperDay: 'MATILDA',
      housekeeperNight: '072411528',
      cateringDayPhone: '0721299472',
      cateringNightPhone: '0792777972',
      fireMarshall: 'MWATAKU',
    );
  }

  /// Exact replica of the physical Gertrude's Children's Hospital whiteboard
  static List<WhiteboardBedAssignment> getInitialJacarandaAssignments() {
    return const [
      WhiteboardBedAssignment(
        bedNumber: '25',
        patientInitials: 'J.M.H.',
        admissionNumber: 'ADM-2026-9925',
        admittingDoctor: 'DR. MBIATA',
        dayShiftNurseId: 'NUR-403', // Glory D. / Faith Njeri
        nightShiftNurseId: 'NUR-405', // Phenina I
        status: 'pending',
      ),
      WhiteboardBedAssignment(
        bedNumber: '26',
        patientInitials: 'N.G.H.',
        admissionNumber: 'ADM-2026-9926',
        admittingDoctor: 'DR. KAGENI',
        dayShiftNurseId: 'NUR-403',
        nightShiftNurseId: 'NUR-405',
        status: 'pending',
      ),
      WhiteboardBedAssignment(
        bedNumber: '27',
        patientInitials: 'R.A.M.',
        admissionNumber: 'ADM-2026-9927',
        admittingDoctor: 'DR. ODHIAMBO',
        dayShiftNurseId: 'NUR-403',
        nightShiftNurseId: 'NUR-405',
        status: 'pending',
      ),
      WhiteboardBedAssignment(
        bedNumber: '28',
        patientInitials: 'M.N.S.',
        admissionNumber: 'ADM-2026-9928',
        admittingDoctor: 'DR. NDERU',
        dayShiftNurseId: 'NUR-403',
        nightShiftNurseId: 'NUR-405',
        status: 'pending',
      ),
      WhiteboardBedAssignment(
        bedNumber: '29',
        patientInitials: 'G.W.K.',
        admissionNumber: 'ADM-2026-9929',
        admittingDoctor: 'DR. J.K. MWANGI',
        dayShiftNurseId: 'NUR-403',
        nightShiftNurseId: 'NUR-405',
        status: 'pending',
      ),
      WhiteboardBedAssignment(
        bedNumber: '30',
        patientInitials: 'A.K.T.',
        admissionNumber: 'ADM-2026-9930',
        admittingDoctor: 'DR. OSURANA',
        dayShiftNurseId: 'NUR-401', // S. Barasa
        nightShiftNurseId: 'NUR-404', // Okema
        status: 'accepted',
      ),
      WhiteboardBedAssignment(
        bedNumber: '31',
        patientInitials: 'A.N.K.',
        admissionNumber: 'ADM-2026-9931',
        admittingDoctor: 'DR. KAHOMU',
        dayShiftNurseId: 'NUR-401',
        nightShiftNurseId: 'NUR-404',
        status: 'accepted',
      ),
      WhiteboardBedAssignment(
        bedNumber: '43',
        patientInitials: 'T.N.',
        admissionNumber: 'ADM-2026-9943',
        admittingDoctor: 'DR. RACHEL',
        dayShiftNurseId: 'NUR-403',
        nightShiftNurseId: 'NUR-404',
        status: 'pending',
      ),
      WhiteboardBedAssignment(
        bedNumber: '44',
        patientInitials: '',
        admissionNumber: '',
        admittingDoctor: '',
        dayShiftNurseId: 'NUR-403',
        nightShiftNurseId: 'NUR-404',
        status: 'pending',
      ),
      WhiteboardBedAssignment(
        bedNumber: '45',
        patientInitials: 'Y.N.I.',
        admissionNumber: 'ADM-2026-9945',
        admittingDoctor: 'DR. J.K. MBIATA',
        dayShiftNurseId: 'NUR-403',
        nightShiftNurseId: 'NUR-404',
        status: 'pending',
      ),
    ];
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/domain/models/hospital_ward.dart';
import 'package:oravi_app/domain/models/whiteboard_models.dart';

void main() {
  group('M8: Digital Whiteboard & Hospital Ward Domain Models', () {
    test('HospitalWard serializes explicit configured ward metadata', () {
      const ward = HospitalWard(
        wardId: 'WARD-TEST',
        name: 'Test Ward',
        bedCount: 2,
        bedNumbers: ['1', '2'],
        department: 'Testing',
        description: '',
      );
      final restored = HospitalWard.fromMap(ward.toMap());
      expect(restored.wardId, 'WARD-TEST');
      expect(restored.bedNumbers, ['1', '2']);
    });

    test('WhiteboardBedAssignment serializes only workflow identifiers', () {
      const assignment = WhiteboardBedAssignment(
        bedNumber: '25',
        patientId: 'PATIENT-TEST',
        patientInitials: 'J.M.H.',
        admittingDoctor: 'DOC-TEST',
        dayShiftNurseId: 'NUR-403',
        status: 'pending',
      );

      final map = assignment.toMap();
      final reconstructed = WhiteboardBedAssignment.fromMap(map);

      expect(reconstructed.bedNumber, '25');
      expect(reconstructed.patientId, 'PATIENT-TEST');
      expect(reconstructed.patientInitials, 'J.M.H.');
      expect(map.containsKey('admission_number'), isFalse);
      expect(reconstructed.admittingDoctor, 'DOC-TEST');
      expect(reconstructed.dayShiftNurseId, 'NUR-403');
      expect(reconstructed.status, 'pending');
    });

    test('WardSupportRoster defaults empty and round-trips board assignments', () {
      const empty = WardSupportRoster();
      expect(empty.wardManager, isEmpty);
      expect(empty.pcaDay, isEmpty);

      const roster = WardSupportRoster(
        wardManager: 'NURSE-TEST',
        pcaDay: 'PCA-TEST',
      );

      final map = roster.toMap();
      final reconstructed = WardSupportRoster.fromMap(map);
      expect(reconstructed.wardManager, 'NURSE-TEST');
      expect(reconstructed.pcaDay, 'PCA-TEST');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/domain/models/hospital_ward.dart';
import 'package:oravi_app/domain/models/whiteboard_models.dart';

void main() {
  group('M8: Digital Whiteboard & Hospital Ward Domain Models', () {
    test('HospitalWard catalog initializes with canonical Gertrude wards', () {
      expect(kDefaultHospitalWards.length, greaterThanOrEqualTo(4));
      
      final jacaranda = kDefaultHospitalWards.firstWhere((w) => w.wardId == 'ward-jacaranda');
      expect(jacaranda.name, contains('Jacaranda'));
      expect(jacaranda.department, 'Pediatrics');
      expect(jacaranda.bedNumbers, contains('25'));
      expect(jacaranda.bedNumbers, contains('29'));
      expect(jacaranda.bedNumbers, contains('30'));
    });

    test('WhiteboardBedAssignment serialization round-trip', () {
      const assignment = WhiteboardBedAssignment(
        bedNumber: '25',
        patientInitials: 'J.M.H.',
        admissionNumber: 'ADM-2026-9901',
        admittingDoctor: 'DR. MBIATA',
        dayShiftNurseId: 'NUR-403',
        status: 'pending',
      );

      final map = assignment.toMap();
      final reconstructed = WhiteboardBedAssignment.fromMap(map);

      expect(reconstructed.bedNumber, '25');
      expect(reconstructed.patientInitials, 'J.M.H.');
      expect(reconstructed.admittingDoctor, 'DR. MBIATA');
      expect(reconstructed.dayShiftNurseId, 'NUR-403');
      expect(reconstructed.status, 'pending');
    });

    test('WardSupportRoster captures exact Gertrude contacts sidebar', () {
      const roster = WardSupportRoster();
      expect(roster.wardManager, 'CAPRICE A');
      expect(roster.pcaDay, 'FAITH / MAUREEN');
      expect(roster.pcaNight, 'RITAH');
      expect(roster.housekeeperDay, 'MATILDA');
      expect(roster.cateringDayPhone, '0721299472');
      expect(roster.fireMarshall, 'MWATAKU');

      final map = roster.toMap();
      final reconstructed = WardSupportRoster.fromMap(map);
      expect(reconstructed.wardManager, 'CAPRICE A');
      expect(reconstructed.housekeeperDay, 'MATILDA');
    });
  });
}

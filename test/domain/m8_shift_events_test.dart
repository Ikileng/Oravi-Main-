import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/domain/events/domain_events.dart';

void main() {
  group('M8: Shift Allocation Canonical Events', () {
    test('ShiftAllocationPublishedEvent serializes and deserializes correctly', () {
      final event = ShiftAllocationPublishedEvent(
        eventId: 'evt-alloc-101',
        patientId: 'ward-jacaranda',
        authorId: 'NUR-402',
        deviceId: 'station-tablet-01',
        allocationId: 'alloc-2026-10-30-day',
        wardId: 'ward-jacaranda',
        shiftType: 'day',
        date: '2026-10-30',
        bedAssignments: [
          {
            'bed_number': '25',
            'patient_initials': 'J.M.H.',
            'admission_number': 'ADM-2026-9901',
            'admitting_doctor': 'DR. MBIATA',
            'day_shift_nurse_id': 'NUR-403',
            'night_shift_nurse_id': 'NUR-405',
            'status': 'pending',
          },
          {
            'bed_number': '26',
            'patient_initials': 'N.G.H.',
            'admission_number': 'ADM-2026-9902',
            'admitting_doctor': 'DR. KAGENI',
            'day_shift_nurse_id': 'NUR-403',
            'status': 'pending',
          },
        ],
        supportRoster: {
          'ward_manager': 'CAPRICE A',
          'pca_day': 'FAITH / MAUREEN',
          'housekeeper_day': 'MATILDA',
          'catering_day_phone': '0721299472',
        },
      );

      final map = event.toMap();
      final roundTrip = deserializeOraviEvent(map);

      expect(roundTrip, isA<ShiftAllocationPublishedEvent>());
      final published = roundTrip as ShiftAllocationPublishedEvent;
      expect(published.wardId, 'ward-jacaranda');
      expect(published.shiftType, 'day');
      expect(published.bedAssignments.length, 2);
      expect(published.bedAssignments[0]['admitting_doctor'], 'DR. MBIATA');
      expect(published.supportRoster['housekeeper_day'], 'MATILDA');
    });

    test('ShiftAllocationAcceptedEvent round-trip through deserializeOraviEvent', () {
      final event = ShiftAllocationAcceptedEvent(
        eventId: 'evt-accept-201',
        patientId: 'ward-jacaranda',
        authorId: 'NUR-403',
        deviceId: 'phone-galaxy-a06',
        allocationId: 'alloc-2026-10-30-day',
        wardId: 'ward-jacaranda',
        nurseId: 'NUR-403',
        acceptedBeds: ['25', '26', '27', '28', '29'],
      );

      final map = event.toMap();
      final roundTrip = deserializeOraviEvent(map);

      expect(roundTrip, isA<ShiftAllocationAcceptedEvent>());
      final accepted = roundTrip as ShiftAllocationAcceptedEvent;
      expect(accepted.nurseId, 'NUR-403');
      expect(accepted.acceptedBeds, contains('25'));
      expect(accepted.acceptedBeds.length, 5);
    });

    test('ShiftAllocationDisputedEvent round-trip through deserializeOraviEvent', () {
      final event = ShiftAllocationDisputedEvent(
        eventId: 'evt-dispute-301',
        patientId: 'ward-jacaranda',
        authorId: 'NUR-403',
        deviceId: 'phone-galaxy-a06',
        allocationId: 'alloc-2026-10-30-day',
        wardId: 'ward-jacaranda',
        nurseId: 'NUR-403',
        bedNumber: '28',
        disputeReason: 'Patient transferred to Theatre earlier this morning',
      );

      final map = event.toMap();
      final roundTrip = deserializeOraviEvent(map);

      expect(roundTrip, isA<ShiftAllocationDisputedEvent>());
      final disputed = roundTrip as ShiftAllocationDisputedEvent;
      expect(disputed.bedNumber, '28');
      expect(disputed.disputeReason, contains('Theatre'));
    });
  });
}

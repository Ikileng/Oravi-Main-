import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/local_ward_repository.dart';
import '../fixtures/seeded_ward_data.dart';
import 'package:oravi_app/domain/models/loop_enums.dart';
import 'package:oravi_app/domain/search/ward_lexicon.dart';
import 'package:oravi_app/domain/timeline/patient_timeline_entry.dart';

void main() {
  group(
    'M4: Ask Oravi Timeline & Local Ward Search (PRD Section 8A & Tech Arch Section 14)',
    () {
      late LocalWardRepository repository;

      setUp(() async {
        repository = LocalWardRepository();
        await repository.appendEvents(SeededWardData.getInitialEvents());
      });

      test(
        '1. Ward Lexicon expands English & Kiswahili medical terminology (FR-41 & FR-192)',
        () {
          final urineTerms = WardLexicon.expandSearchTerms('urine');
          expect(urineTerms.contains('mkojo'), isTrue);
          expect(urineTerms.contains('uo'), isTrue);
          expect(urineTerms.contains('catheter'), isTrue);

          final oxygenTerms = WardLexicon.expandSearchTerms('hewa ya oksijeni');
          expect(oxygenTerms.contains('spo2'), isTrue);
          expect(oxygenTerms.contains('sats'), isTrue);
          expect(oxygenTerms.contains('oxygen'), isTrue);

          final bloodTerms = WardLexicon.expandSearchTerms('damu');
          expect(bloodTerms.contains('blood'), isTrue);
          expect(bloodTerms.contains('cross-match'), isTrue);
          expect(bloodTerms.contains('hb'), isTrue);

          final allergyTerms = WardLexicon.expandSearchTerms('mzio');
          expect(allergyTerms.contains('allergy'), isTrue);
          expect(allergyTerms.contains('allergic'), isTrue);
        },
      );

      test(
        '2. Diagnostic Boundary Handler triggers refusal on prediction/diagnosis (FR-40 & Example 8)',
        () {
          expect(
            WardLexicon.isDiagnosticOrPredictiveQuery(
              'Is he going into kidney failure?',
            ),
            isTrue,
          );
          expect(
            WardLexicon.isDiagnosticOrPredictiveQuery('Does he have sepsis?'),
            isTrue,
          );
          expect(
            WardLexicon.isDiagnosticOrPredictiveQuery(
              'What should I prescribe?',
            ),
            isTrue,
          );
          expect(
            WardLexicon.isDiagnosticOrPredictiveQuery(
              'How has his urine output been?',
            ),
            isFalse,
          );

          final result = repository.askOravi(
            patientId: 'PAT-4B-01',
            queryString: 'Is he going into kidney failure?',
          );

          expect(result.isRefusal, isTrue);
          expect(
            result.refusalMessage,
            contains('I cannot diagnose or predict'),
          );
          expect(result.doctorInChargeId, isNotEmpty);
        },
      );

      test(
        '3. Chronological Verbatim Timeline accurately projects patient events (FR-35)',
        () {
          final timeline = repository.getPatientTimeline('PAT-4B-01');
          expect(timeline, isNotEmpty);

          // Verify chronological ordering
          for (int i = 0; i < timeline.length - 1; i++) {
            expect(
              timeline[i].timestamp.isBefore(timeline[i + 1].timestamp) ||
                  timeline[i].timestamp.isAtSameMomentAs(
                    timeline[i + 1].timestamp,
                  ),
              isTrue,
            );
          }

          // Verify verbatim content exists
          final messageEntry = timeline.firstWhere(
            (e) => e.entryType == TimelineEntryType.message,
          );
          expect(
            messageEntry.verbatimText,
            contains('SpO2 stable at 94% on 2L nasal prongs'),
          );
          expect(messageEntry.authorRole, equals('ward_nurse'));
          expect(messageEntry.loopUrgency, equals(LoopUrgency.urgent));
        },
      );

      test(
        '4. Positive Keyword Query returns verbatim quotes with coverage line (FR-35 & FR-36)',
        () {
          final result = repository.askOravi(
            patientId: 'PAT-4B-01',
            queryString: 'How has his oxygen and SpO2 been?',
          );

          expect(result.isAbsence, isFalse);
          expect(result.verbatimQuotes, isNotEmpty);
          expect(
            result.verbatimQuotes.any((q) => q.verbatimText.contains('SpO2')),
            isTrue,
          );

          // Verify mandatory Coverage Line (FR-36)
          final coverage = result.coverage;
          expect(coverage.termsSearched, isNotEmpty);
          expect(coverage.messageCount, greaterThan(0));
          expect(coverage.threadCount, greaterThan(0));
          expect(coverage.formattedLine, contains('Searched:'));
          expect(
            coverage.formattedLine,
            contains(
              'in ${coverage.messageCount} messages across ${coverage.threadCount} threads',
            ),
          );
        },
      );

      test(
        '5. Absence Handling states "no record in Oravi", never "no record exists" (FR-37 & Example 4)',
        () {
          final result = repository.askOravi(
            patientId: 'PAT-4B-01',
            queryString: 'Any mention of abdominal surgery?',
          );

          expect(result.isAbsence, isTrue);
          expect(result.verbatimQuotes, isEmpty);
          expect(result.absenceMessage, isNotNull);
          expect(
            result.absenceMessage,
            contains('No record in Oravi mentions'),
          );
          expect(
            result.absenceMessage,
            contains(
              'Absence of a mention does not mean there was no change or that all is well',
            ),
          );
          // Must NOT state "no record exists"
          expect(result.absenceMessage, isNot(contains('no record exists')));
        },
      );

      test(
        '6. Repeating Thread & Unacknowledged Escalation system pattern counts (FR-39 & Example 5)',
        () async {
          // Reopen Bed 4's closed Ceftriaxone loop
          await repository.reopenLoop(
            patientId: 'PAT-4B-04',
            loopId: 'LOOP-4B-04-A',
            authorId: 'NURSE-MWANGI',
            deviceId: SeededWardData.testDeviceId,
            reopenReason: 'Redness spreading past demarcation line',
          );

          final result = repository.askOravi(
            patientId: 'PAT-4B-04',
            queryString: 'Has anything been raised repeatedly?',
          );

          expect(
            result.systemPatterns.any(
              (p) => p.label.contains('System count: Repeated loop'),
            ),
            isTrue,
          );
          final repeatedPattern = result.systemPatterns.firstWhere(
            (p) => p.label.contains('System count: Repeated loop'),
          );
          expect(repeatedPattern.count, equals(1));
          expect(repeatedPattern.description, contains('reopened 1 time'));

          // Check Bed 2 which has an unacknowledged STAT escalation (Hb 7.1)
          final bed2Result = repository.askOravi(
            patientId: 'PAT-4B-02',
            queryString: 'Any urgent escalations?',
          );
          expect(
            bed2Result.systemPatterns.any(
              (p) => p.label.contains('Unacknowledged Escalation'),
            ),
            isTrue,
          );
        },
      );

      test(
        '7. Time window parsing filters query results (e.g. last 8 hours) (FR-43 & Example 2)',
        () {
          final result = repository.askOravi(
            patientId: 'PAT-4B-01',
            queryString: 'What should I know about the last 8 hours?',
          );

          expect(result.verbatimQuotes, isNotEmpty);
          final now = DateTime.now();
          for (final quote in result.verbatimQuotes) {
            expect(
              quote.timestamp.isAfter(now.subtract(const Duration(hours: 9))),
              isTrue,
            );
          }
        },
      );

      test(
        '8. Kiswahili Query returns matching quotes (FR-41 & Example 7)',
        () {
          final result = repository.askOravi(
            patientId: 'PAT-4B-01',
            queryString: 'Hewa ya oksijeni ilikuwaje leo?',
          );

          expect(result.isAbsence, isFalse);
          expect(
            result.verbatimQuotes.any(
              (q) =>
                  q.verbatimText.contains('SpO2') ||
                  q.verbatimText.contains('nasal'),
            ),
            isTrue,
          );
        },
      );

      test(
        '9. Ward-wide Search matches beds, initials, alerts, and clinical notes without exposing admission numbers',
        () {
          // Search by bed
          final bedResults = repository.searchWard(
            wardId: SeededWardData.wardId,
            query: 'Bed 2',
          );
          expect(bedResults.length, equals(1));
          expect(bedResults.first.patient.patientId, equals('PAT-4B-02'));

          // Admission numbers are not supported as search identifiers.
          final admissionNumberResults = repository.searchWard(
            wardId: SeededWardData.wardId,
            query: '8834',
          );
          expect(admissionNumberResults, isEmpty);

          // Search by initials
          final initialsResults = repository.searchWard(
            wardId: SeededWardData.wardId,
            query: 'J.K.',
          );
          expect(initialsResults.length, greaterThanOrEqualTo(1));

          // Search by clinical term 'cross-match' (should find Bed 2 STAT loop)
          final topicResults = repository.searchWard(
            wardId: SeededWardData.wardId,
            query: 'cross-match',
          );
          expect(
            topicResults.any((r) => r.patient.patientId == 'PAT-4B-02'),
            isTrue,
          );

          // Search by key alert 'Penicillin' (should find Bed 1)
          final alertResults = repository.searchWard(
            wardId: SeededWardData.wardId,
            query: 'penicillin',
          );
          expect(
            alertResults.any((r) => r.patient.patientId == 'PAT-4B-01'),
            isTrue,
          );
        },
      );
    },
  );
}

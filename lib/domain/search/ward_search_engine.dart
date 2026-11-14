import '../models/loop_enums.dart';
import '../projections/projections.dart';
import '../timeline/patient_timeline_entry.dart';
import 'ward_lexicon.dart';

enum WardSearchMatchType {
  bedNumber,
  patientInitials,
  keyAlert,
  loopTitle,
  verbatimQuote,
}

class WardSearchResult {
  final PatientStateProjection patient;
  final LoopUrgency? highestUrgency;
  final WardSearchMatchType matchType;
  final String matchSnippet;
  final List<LoopStateProjection> matchingLoops;
  final List<PatientTimelineEntry> matchingQuotes;

  const WardSearchResult({
    required this.patient,
    this.highestUrgency,
    required this.matchType,
    required this.matchSnippet,
    this.matchingLoops = const [],
    this.matchingQuotes = const [],
  });
}

/// Offline ward-wide search engine across beds, patients, loops, and clinical notes.
class WardSearchEngine {
  /// Searches across all patients, loops, and timeline entries in a ward.
  static List<WardSearchResult> searchWard({
    required List<PatientStateProjection> patients,
    required Map<String, List<LoopStateProjection>> patientLoopsMap,
    required Map<String, List<PatientTimelineEntry>> patientTimelineMap,
    required String query,
  }) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final expandedTerms = WardLexicon.expandSearchTerms(cleanQuery);
    final results = <WardSearchResult>[];

    for (final patient in patients) {
      final loops = patientLoopsMap[patient.patientId] ?? [];
      final timeline = patientTimelineMap[patient.patientId] ?? [];

      LoopUrgency? highestUrgency;
      final openLoops = loops.where((l) => l.isOpen).toList();
      if (openLoops.any((l) => l.urgency == LoopUrgency.critical)) {
        highestUrgency = LoopUrgency.critical;
      } else if (openLoops.any((l) => l.urgency == LoopUrgency.urgent)) {
        highestUrgency = LoopUrgency.urgent;
      } else if (openLoops.isNotEmpty) {
        highestUrgency = LoopUrgency.routine;
      }

      // 1. Bed Number Match
      if (patient.bedNumber.toLowerCase().contains(cleanQuery)) {
        results.add(
          WardSearchResult(
            patient: patient,
            highestUrgency: highestUrgency,
            matchType: WardSearchMatchType.bedNumber,
            matchSnippet: 'Bed: ${patient.bedNumber}',
            matchingLoops: loops,
          ),
        );
        continue;
      }

      // 2. Patient Initials Match
      if (patient.patientInitials.toLowerCase().contains(cleanQuery)) {
        results.add(
          WardSearchResult(
            patient: patient,
            highestUrgency: highestUrgency,
            matchType: WardSearchMatchType.patientInitials,
            matchSnippet: 'Initials: ${patient.patientInitials}',
            matchingLoops: loops,
          ),
        );
        continue;
      }

      // 4. Key Alerts Match
      final matchingAlert = patient.keyAlerts.firstWhere(
        (a) =>
            a.toLowerCase().contains(cleanQuery) ||
            expandedTerms.any((t) => a.toLowerCase().contains(t)),
        orElse: () => '',
      );
      if (matchingAlert.isNotEmpty) {
        results.add(
          WardSearchResult(
            patient: patient,
            highestUrgency: highestUrgency,
            matchType: WardSearchMatchType.keyAlert,
            matchSnippet: 'Key Alert: "$matchingAlert"',
            matchingLoops: loops,
          ),
        );
        continue;
      }

      // 5. Loop Title / Description Match
      final matchedLoops = loops.where((l) {
        final text = '${l.title} ${l.description}'.toLowerCase();
        return text.contains(cleanQuery) ||
            expandedTerms.any((t) => text.contains(t));
      }).toList();

      if (matchedLoops.isNotEmpty) {
        results.add(
          WardSearchResult(
            patient: patient,
            highestUrgency: highestUrgency,
            matchType: WardSearchMatchType.loopTitle,
            matchSnippet: 'Loop: "${matchedLoops.first.title}"',
            matchingLoops: matchedLoops,
          ),
        );
        continue;
      }

      // 6. Timeline Quotes Match
      final matchedQuotes = timeline.where((q) {
        final text = '${q.verbatimText} ${q.loopTitle}'.toLowerCase();
        return text.contains(cleanQuery) ||
            expandedTerms.any((t) => text.contains(t));
      }).toList();

      if (matchedQuotes.isNotEmpty) {
        results.add(
          WardSearchResult(
            patient: patient,
            highestUrgency: highestUrgency,
            matchType: WardSearchMatchType.verbatimQuote,
            matchSnippet: 'Record: "${matchedQuotes.first.verbatimText}"',
            matchingQuotes: matchedQuotes,
            matchingLoops: loops,
          ),
        );
      }
    }

    return results;
  }
}

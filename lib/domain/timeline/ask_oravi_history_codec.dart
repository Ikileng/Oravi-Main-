import '../models/loop_enums.dart';
import '../projections/projections.dart';
import 'ask_oravi_engine.dart';
import 'patient_timeline_entry.dart';

/// Snapshots preserve the evidence actually displayed, not a fresh query.
class AskOraviHistoryCodec {
  static Map<String, dynamic> quoteToJson(PatientTimelineEntry q) => {
    'id': q.id,
    'patientId': q.patientId,
    'loopId': q.loopId,
    'loopTitle': q.loopTitle,
    'urgency': q.loopUrgency.name,
    'state': q.loopState.name,
    'type': q.entryType.name,
    'authorId': q.authorId,
    'authorRole': q.authorRole,
    'text': q.verbatimText,
    'timestamp': q.timestamp.toIso8601String(),
    'metadata': q.metadata,
  };

  static PatientTimelineEntry quoteFromJson(Map<String, dynamic> q) =>
      PatientTimelineEntry(
        id: q['id'],
        patientId: q['patientId'],
        loopId: q['loopId'],
        loopTitle: q['loopTitle'],
        loopUrgency: LoopUrgency.values.byName(q['urgency']),
        loopState: LoopState.values.byName(q['state']),
        entryType: TimelineEntryType.values.byName(q['type']),
        authorId: q['authorId'],
        authorRole: q['authorRole'],
        verbatimText: q['text'],
        timestamp: DateTime.parse(q['timestamp']),
        metadata: Map<String, dynamic>.from(q['metadata'] as Map),
      );

  static Map<String, dynamic> issueToJson(LoopStateProjection q) => {
    'id': q.loopId,
    'patientId': q.patientId,
    'title': q.title,
    'description': q.description,
    'type': q.loopType.name,
    'urgency': q.urgency.name,
    'state': q.state.name,
    'ownerId': q.currentOwnerId,
    'ownerRole': q.currentOwnerRole,
    'openedBy': q.openedByUserId,
    'createdAt': q.createdAt.toIso8601String(),
    'updatedAt': q.updatedAt.toIso8601String(),
  };

  static LoopStateProjection issueFromJson(Map<String, dynamic> q) =>
      LoopStateProjection(
        loopId: q['id'],
        patientId: q['patientId'],
        title: q['title'],
        description: q['description'],
        loopType: LoopType.values.byName(q['type']),
        urgency: LoopUrgency.values.byName(q['urgency']),
        state: LoopState.values.byName(q['state']),
        currentOwnerId: q['ownerId'],
        currentOwnerRole: q['ownerRole'],
        openedByUserId: q['openedBy'],
        createdAt: DateTime.parse(q['createdAt']),
        updatedAt: DateTime.parse(q['updatedAt']),
      );

  static Map<String, dynamic> resultToJson(AskOraviResult r) => {
    'patientId': r.patientId,
    'query': r.queryString,
    'quotes': r.verbatimQuotes.map(quoteToJson).toList(),
    'patterns': r.systemPatterns
        .map(
          (p) => {
            'label': p.label,
            'description': p.description,
            'count': p.count,
            'quotes': p.supportingQuotes.map(quoteToJson).toList(),
          },
        )
        .toList(),
    'terms': r.coverage.termsSearched,
    'messageCount': r.coverage.messageCount,
    'threadCount': r.coverage.threadCount,
    'start': r.coverage.startTime?.toIso8601String(),
    'end': r.coverage.endTime?.toIso8601String(),
    'isRefusal': r.isRefusal,
    'refusal': r.refusalMessage,
    'isAbsence': r.isAbsence,
    'absence': r.absenceMessage,
    'doctorId': r.doctorInChargeId,
    'observation': r.observationNote,
    'modelAssisted': r.isModelAssisted,
    'modelProvider': r.modelProvider,
    'modelName': r.modelName,
    'verified': r.verificationPassed,
  };

  static AskOraviResult resultFromJson(Map<String, dynamic> r) =>
      AskOraviResult(
        patientId: r['patientId'],
        queryString: r['query'],
        verbatimQuotes: (r['quotes'] as List)
            .map((q) => quoteFromJson(Map<String, dynamic>.from(q)))
            .toList(),
        systemPatterns: (r['patterns'] as List)
            .map(
              (p) => SystemPatternCount(
                label: p['label'],
                description: p['description'],
                count: p['count'],
                supportingQuotes: (p['quotes'] as List)
                    .map((q) => quoteFromJson(Map<String, dynamic>.from(q)))
                    .toList(),
              ),
            )
            .toList(),
        coverage: CoverageMetadata(
          termsSearched: List<String>.from(r['terms']),
          messageCount: r['messageCount'],
          threadCount: r['threadCount'],
          startTime: r['start'] == null ? null : DateTime.parse(r['start']),
          endTime: r['end'] == null ? null : DateTime.parse(r['end']),
        ),
        isRefusal: r['isRefusal'],
        refusalMessage: r['refusal'],
        isAbsence: r['isAbsence'],
        absenceMessage: r['absence'],
        doctorInChargeId: r['doctorId'],
        observationNote: r['observation'],
        isModelAssisted: r['modelAssisted'],
        modelProvider: r['modelProvider'],
        modelName: r['modelName'],
        verificationPassed: r['verified'],
      );
}

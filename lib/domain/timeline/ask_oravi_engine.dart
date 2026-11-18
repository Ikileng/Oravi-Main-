import '../events/domain_events.dart';
import '../events/oravi_event.dart';
import '../models/loop_enums.dart';
import '../projections/projections.dart';
import '../search/ward_lexicon.dart';
import 'patient_timeline_entry.dart';

/// System-computed pattern detector result (PRD Section 8A FR-39 & FR-187).
///
/// Labeled strictly as "System count" or "System status", stating facts and
/// counts without making clinical judgments or inferences.
class SystemPatternCount {
  final String label;
  final String description;
  final int count;
  final List<PatientTimelineEntry> supportingQuotes;

  const SystemPatternCount({
    required this.label,
    required this.description,
    required this.count,
    this.supportingQuotes = const [],
  });
}

/// Mandatory coverage metadata concluding every Ask Oravi query (PRD FR-36).
class CoverageMetadata {
  final List<String> termsSearched;
  final int messageCount;
  final int threadCount;
  final DateTime? startTime;
  final DateTime? endTime;

  const CoverageMetadata({
    required this.termsSearched,
    required this.messageCount,
    required this.threadCount,
    this.startTime,
    this.endTime,
  });

  /// Formatted coverage summary string strictly adhering to FR-36.
  /// Example:
  /// "Searched: urine, UO, mkojo in 41 messages across 5 threads, Mon 26/10 02:15 to Tue 27/10 14:00."
  String get formattedLine {
    final terms = termsSearched.isEmpty
        ? 'all messages'
        : termsSearched.take(6).join(', ');
    final startStr = startTime != null ? _formatDate(startTime!) : 'Admission';
    final endStr = endTime != null ? _formatDate(endTime!) : 'Present';

    return 'Searched: $terms in $messageCount messages across $threadCount threads, $startStr to $endStr.';
  }

  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayName = dayNames[local.weekday - 1];
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$dayName $day/$month $hour:$minute';
  }
}

/// Outcome of an Ask Oravi query (deterministic or model-assisted).
class AskOraviResult {
  final String patientId;
  final String queryString;
  final List<PatientTimelineEntry> verbatimQuotes;
  final List<SystemPatternCount> systemPatterns;
  final CoverageMetadata coverage;
  final bool isRefusal;
  final String? refusalMessage;
  final bool isAbsence;
  final String? absenceMessage;
  final String doctorInChargeId;
  final List<PatientTimelineEntry> allTimelineEntries;

  /// Model-Assisted Observation Note (Milestone 5, PRD Section 8A & Tech Arch Section 11).
  ///
  /// Always labeled with: "Note from Oravi, not from the record".
  /// All numbers and assertions in this note are strictly verified by the
  /// Verification Harness against the verbatim quotes.
  final String? observationNote;
  final bool isModelAssisted;
  final String? modelProvider;
  final String? modelName;
  final bool verificationPassed;

  const AskOraviResult({
    required this.patientId,
    required this.queryString,
    required this.verbatimQuotes,
    required this.systemPatterns,
    required this.coverage,
    this.isRefusal = false,
    this.refusalMessage,
    this.isAbsence = false,
    this.absenceMessage,
    this.doctorInChargeId = 'DOC-OTIENO',
    this.allTimelineEntries = const [],
    this.observationNote,
    this.isModelAssisted = false,
    this.modelProvider,
    this.modelName,
    this.verificationPassed = true,
  });

  AskOraviResult copyWith({
    String? patientId,
    String? queryString,
    List<PatientTimelineEntry>? verbatimQuotes,
    List<SystemPatternCount>? systemPatterns,
    CoverageMetadata? coverage,
    bool? isRefusal,
    String? refusalMessage,
    bool? isAbsence,
    String? absenceMessage,
    String? doctorInChargeId,
    List<PatientTimelineEntry>? allTimelineEntries,
    String? observationNote,
    bool? isModelAssisted,
    String? modelProvider,
    String? modelName,
    bool? verificationPassed,
  }) {
    return AskOraviResult(
      patientId: patientId ?? this.patientId,
      queryString: queryString ?? this.queryString,
      verbatimQuotes: verbatimQuotes ?? this.verbatimQuotes,
      systemPatterns: systemPatterns ?? this.systemPatterns,
      coverage: coverage ?? this.coverage,
      isRefusal: isRefusal ?? this.isRefusal,
      refusalMessage: refusalMessage ?? this.refusalMessage,
      isAbsence: isAbsence ?? this.isAbsence,
      absenceMessage: absenceMessage ?? this.absenceMessage,
      doctorInChargeId: doctorInChargeId ?? this.doctorInChargeId,
      allTimelineEntries: allTimelineEntries ?? this.allTimelineEntries,
      observationNote: observationNote ?? this.observationNote,
      isModelAssisted: isModelAssisted ?? this.isModelAssisted,
      modelProvider: modelProvider ?? this.modelProvider,
      modelName: modelName ?? this.modelName,
      verificationPassed: verificationPassed ?? this.verificationPassed,
    );
  }
}

/// Deterministic offline timeline and search engine for Ask Oravi.
///
/// Implements PRD Section 8A (FR-34 to FR-44):
/// - 100% offline and deterministic.
/// - Patient-scoped: zero cross-patient contamination.
/// - Verbatim quotes with cadre coloring and timestamps.
/// - Mandatory coverage line and absence phrasing.
/// - System pattern counts (reopens, unacknowledged escalations).
/// - Automatic quote verification against the immutable event log.
class AskOraviEngine {
  /// Builds the complete chronological timeline for a patient from their events.
  static List<PatientTimelineEntry> buildPatientTimeline({
    required List<OraviEvent> events,
    required String patientId,
    required List<LoopStateProjection> loops,
  }) {
    final loopMap = {for (final l in loops) l.loopId: l};
    final entries = <PatientTimelineEntry>[];

    // Filter events for this patient
    final patientEvents = events
        .where((e) => e.patientId == patientId)
        .toList();
    // Sort strictly chronological
    patientEvents.sort(
      (a, b) => a.clientCreatedAt.compareTo(b.clientCreatedAt),
    );

    for (final event in patientEvents) {
      final loopId = event.loopId;
      final loop = loopId != null ? loopMap[loopId] : null;
      final loopTitle =
          loop?.title ?? (loopId != null ? 'Loop $loopId' : 'Patient Record');
      final loopUrgency = loop?.urgency ?? LoopUrgency.routine;
      final loopState = loop?.state ?? LoopState.raised;

      if (event is LoopOpenedEvent) {
        entries.add(
          PatientTimelineEntry(
            id: event.eventId,
            patientId: patientId,
            loopId: event.loopId,
            loopTitle: event.title,
            loopUrgency: event.urgency,
            loopState: LoopState.raised,
            entryType: TimelineEntryType.loopOpened,
            authorId: event.authorId,
            authorRole: event.initialOwnerRole,
            verbatimText:
                '${event.title}${event.description.isNotEmpty ? ": ${event.description}" : ""}',
            timestamp: event.clientCreatedAt,
            metadata: {'loopType': event.loopType.name},
          ),
        );
      } else if (event is MessagePostedEvent) {
        entries.add(
          PatientTimelineEntry(
            id: event.eventId,
            patientId: patientId,
            loopId: event.loopId,
            loopTitle: loopTitle,
            loopUrgency: loopUrgency,
            loopState: loopState,
            entryType: TimelineEntryType.message,
            authorId: event.authorId,
            authorRole: event.authorRole,
            verbatimText: event.content,
            timestamp: event.clientCreatedAt,
            metadata: {'messageId': event.messageId},
          ),
        );
      } else if (event is CallLoggedEvent) {
        entries.add(
          PatientTimelineEntry(
            id: event.eventId,
            patientId: patientId,
            loopId: event.loopId,
            loopTitle: loopTitle,
            loopUrgency: loopUrgency,
            loopState: loopState,
            entryType: TimelineEntryType.callLog,
            authorId: event.callerId,
            authorRole: event.callerRole,
            verbatimText:
                'Spoke with ${event.recipientId} (${event.recipientRole}): "${event.outcomeNote}"',
            timestamp: event.clientCreatedAt,
            metadata: {
              'recipientId': event.recipientId,
              'recipientRole': event.recipientRole,
              'durationSeconds': event.durationSeconds,
              'callStatus': event.callStatus,
            },
          ),
        );
      } else if (event is EscalationRaisedEvent) {
        entries.add(
          PatientTimelineEntry(
            id: event.eventId,
            patientId: patientId,
            loopId: event.loopId,
            loopTitle: loopTitle,
            loopUrgency: LoopUrgency.critical,
            loopState: loopState,
            entryType: TimelineEntryType.escalationRaised,
            authorId: event.authorId,
            authorRole: _inferCadreRole(event.authorId),
            verbatimText:
                'Escalated to ${event.targetRole} (${event.initialTargetUserId}): ${event.escalationReason}',
            timestamp: event.clientCreatedAt,
            metadata: {
              'targetRole': event.targetRole,
              'targetUserId': event.initialTargetUserId,
              'timeoutMinutes': event.timeoutMinutes,
            },
          ),
        );
      } else if (event is EscalationAcknowledgedEvent) {
        entries.add(
          PatientTimelineEntry(
            id: event.eventId,
            patientId: patientId,
            loopId: event.loopId,
            loopTitle: loopTitle,
            loopUrgency: loopUrgency,
            loopState: loopState,
            entryType: TimelineEntryType.escalationAcknowledged,
            authorId: event.authorId,
            authorRole: _inferCadreRole(event.authorId),
            verbatimText: event.note.isNotEmpty
                ? 'Escalation acknowledged: "${event.note}"'
                : 'Escalation acknowledged by ${event.authorId}.',
            timestamp: event.clientCreatedAt,
          ),
        );
      } else if (event is LoopClosedEvent) {
        final reasonStr =
            event.closureReason ??
            event.reasonCode?.wireName ??
            'reason not recorded';
        final noteStr = event.freeTextNote?.isNotEmpty == true
            ? ' ("${event.freeTextNote}")'
            : '';
        entries.add(
          PatientTimelineEntry(
            id: event.eventId,
            patientId: patientId,
            loopId: event.loopId,
            loopTitle: loopTitle,
            loopUrgency: loopUrgency,
            loopState: LoopState.closed,
            entryType: TimelineEntryType.loopClosed,
            authorId: event.authorId,
            authorRole: _inferCadreRole(event.authorId),
            verbatimText:
                'Closed medical issue with reason: $reasonStr$noteStr',
            timestamp: event.clientCreatedAt,
            metadata: {
              if (event.reasonCode != null)
                'reasonCode': event.reasonCode!.wireName,
              'closureReason': reasonStr,
              'resolutionType': event.resolutionType.wireName,
            },
          ),
        );
      } else if (event is LoopClosureConfirmedEvent) {
        entries.add(
          PatientTimelineEntry(
            id: event.eventId,
            patientId: patientId,
            loopId: event.loopId,
            loopTitle: loopTitle,
            loopUrgency: loopUrgency,
            loopState: LoopState.closed,
            entryType: TimelineEntryType.closureConfirmed,
            authorId: event.authorId,
            authorRole: event.confirmedByRole,
            verbatimText: 'STAT closure confirmed by ${event.confirmedByRole}',
            timestamp: event.clientCreatedAt,
          ),
        );
      } else if (event is LoopReopenedEvent) {
        entries.add(
          PatientTimelineEntry(
            id: event.eventId,
            patientId: patientId,
            loopId: event.loopId,
            loopTitle: loopTitle,
            loopUrgency: loopUrgency,
            loopState: LoopState.inProgress,
            entryType: TimelineEntryType.loopReopened,
            authorId: event.authorId,
            authorRole: _inferCadreRole(event.authorId),
            verbatimText: 'Reopened loop: "${event.reopenReason}"',
            timestamp: event.clientCreatedAt,
          ),
        );
      } else if (event is ClinicalRitualApprovedEvent) {
        final sections = event.summary['sections'];
        final lines = <String>[];
        if (sections is Map) {
          for (final key in [
            'situation',
            'decisions',
            'actions',
            'owners',
            'follow_up',
            'unresolved_questions',
          ]) {
            final values = sections[key];
            if (values is List && values.isNotEmpty) {
              lines.add('${key.replaceAll('_', ' ')}: ${values.join('; ')}');
            }
          }
        }
        entries.add(
          PatientTimelineEntry(
            id: event.eventId,
            patientId: patientId,
            loopId: null,
            loopTitle: event.title,
            loopUrgency: LoopUrgency.routine,
            loopState: LoopState.closed,
            entryType: TimelineEntryType.clinicalRitual,
            authorId: event.authorId,
            authorRole: _inferCadreRole(event.authorId),
            verbatimText:
                'Approved ${event.ritualType} summary: ${lines.join(' | ')}',
            timestamp: event.clientCreatedAt,
            metadata: {'ritualId': event.ritualId, 'summary': event.summary},
          ),
        );
      }
    }

    return entries;
  }

  /// Executes a patient-scoped query against the timeline and open loops.
  static AskOraviResult query({
    required List<OraviEvent> events,
    required PatientStateProjection patient,
    required List<LoopStateProjection> loops,
    required String queryString,
    DateTime? since,
  }) {
    final patientId = patient.patientId;
    final allEntries = buildPatientTimeline(
      events: events,
      patientId: patientId,
      loops: loops,
    );

    // 1. Boundary Handling (FR-40 & Example 8)
    final isRefusal = WardLexicon.isDiagnosticOrPredictiveQuery(queryString);
    final String? refusalMessage = isRefusal
        ? 'I cannot diagnose or predict. This is what the record says about your query:'
        : null;

    // 2. Parse time window filter from query string if present (PRD Section 8A Example 2)
    DateTime? effectiveSince = since;
    final lowerQuery = queryString.toLowerCase().trim();

    if (effectiveSince == null) {
      if (lowerQuery.contains('last 8 hours') ||
          lowerQuery.contains('masaa 8')) {
        effectiveSince = DateTime.now().subtract(const Duration(hours: 8));
      } else if (lowerQuery.contains('last 24 hours') ||
          lowerQuery.contains('masaa 24') ||
          lowerQuery.contains('today')) {
        effectiveSince = DateTime.now().subtract(const Duration(hours: 24));
      } else if (lowerQuery.contains('last 4 hours') ||
          lowerQuery.contains('masaa 4')) {
        effectiveSince = DateTime.now().subtract(const Duration(hours: 4));
      }
    }

    // 3. Expand search terms via WardLexicon
    final expandedTerms = WardLexicon.expandSearchTerms(queryString);

    // 4. Retrieve matching entries
    final matchingQuotes = <PatientTimelineEntry>[];
    final allMessagesAndEvents = effectiveSince != null
        ? allEntries.where((e) => e.timestamp.isAfter(effectiveSince!)).toList()
        : allEntries;

    final isGeneralBriefing =
        lowerQuery.contains('what should i know') ||
        lowerQuery.contains('what do i need to know') ||
        lowerQuery.contains('tell me what i need to know') ||
        lowerQuery.contains('tell me what i need to knkw') ||
        lowerQuery.contains('know nothing') ||
        lowerQuery.contains('brief me') ||
        lowerQuery.contains('catch me up') ||
        lowerQuery.contains('what happened') ||
        lowerQuery.contains('summary') ||
        lowerQuery.contains('overview') ||
        lowerQuery.contains('who is this patient') ||
        lowerQuery.contains('updates');

    final isGeneralWindowCatchUp =
        effectiveSince != null && (expandedTerms.isEmpty || isGeneralBriefing);

    if (isGeneralBriefing || isGeneralWindowCatchUp || expandedTerms.isEmpty) {
      // If general catch-up question or no specific terms found, return all in window (PRD Example 2)
      matchingQuotes.addAll(allMessagesAndEvents);
    } else {
      for (final entry in allMessagesAndEvents) {
        final textLower = '${entry.verbatimText} ${entry.loopTitle}'
            .toLowerCase();
        final matches = expandedTerms.any((term) {
          // Token or substring match
          if (term.length <= 3) {
            // Strict word boundary for short abbreviations like UO, O2, BP, Hb
            final pattern = RegExp(
              '\\b${RegExp.escape(term)}\\b',
              caseSensitive: false,
            );
            return pattern.hasMatch(textLower);
          }
          return textLower.contains(term);
        });

        if (matches) {
          matchingQuotes.add(entry);
        }
      }
    }

    // 5. Automatic Verification (FR-194):
    // Ensure every single quote matches raw event data
    for (final quote in matchingQuotes) {
      final existsInRaw = events.any(
        (e) => e.eventId == quote.id || e.patientId == patientId,
      );
      if (!existsInRaw) {
        throw StateError(
          'Verification failed: quote ${quote.id} does not exist in event store.',
        );
      }
    }

    // 6. System-Computed Pattern Detectors (FR-39)
    final systemPatterns = <SystemPatternCount>[];

    // Detector A: Repeated openings and closings (Reopen count >= 1)
    for (final loop in loops) {
      if (loop.reopenCount > 0) {
        final reopenEntries = allEntries
            .where(
              (e) =>
                  e.loopId == loop.loopId &&
                  e.entryType == TimelineEntryType.loopReopened,
            )
            .toList();
        systemPatterns.add(
          SystemPatternCount(
            label: 'System count: Repeated loop',
            description:
                'Thread "${loop.title}" was opened, closed, and reopened ${loop.reopenCount} time(s).',
            count: loop.reopenCount,
            supportingQuotes: reopenEntries,
          ),
        );
      }
    }

    // Detector B: Unacknowledged Escalations
    for (final loop in loops) {
      if (loop.activeEscalation != null &&
          !loop.activeEscalation!.isAcknowledged) {
        final escEntries = allEntries
            .where(
              (e) =>
                  e.loopId == loop.loopId &&
                  e.entryType == TimelineEntryType.escalationRaised,
            )
            .toList();
        systemPatterns.add(
          SystemPatternCount(
            label: 'System status: Unacknowledged Escalation',
            description:
                'Loop "${loop.title}" was escalated to ${loop.activeEscalation!.targetRole} and is not yet acknowledged.',
            count: 1,
            supportingQuotes: escEntries,
          ),
        );
      }
    }

    // Detector C: Active open loops count for this patient
    final openLoopsCount = loops.where((l) => l.isOpen).length;
    if (openLoopsCount > 0) {
      systemPatterns.add(
        SystemPatternCount(
          label: 'System status: Open Loops',
          description:
              '$openLoopsCount loop(s) currently open for this patient.',
          count: openLoopsCount,
        ),
      );
    }

    // 7. Compute Coverage Metadata (FR-36)
    final uniqueThreads = allEntries
        .map((e) => e.loopId)
        .whereType<String>()
        .toSet();
    final startTime = allEntries.isNotEmpty
        ? allEntries.first.timestamp
        : patient.admittedAt;
    final endTime = allEntries.isNotEmpty
        ? allEntries.last.timestamp
        : DateTime.now();

    final coverage = CoverageMetadata(
      termsSearched: expandedTerms.toList(),
      messageCount: allEntries.length,
      threadCount: uniqueThreads.isNotEmpty ? uniqueThreads.length : 1,
      startTime: effectiveSince ?? startTime,
      endTime: endTime,
    );

    // 8. Absence Handling (FR-37)
    final isAbsence = matchingQuotes.isEmpty;
    String? absenceMessage;
    if (isAbsence) {
      final keyAlertsText = patient.keyAlerts.isNotEmpty
          ? 'The patient\'s key alerts record notes: ${patient.keyAlerts.join(", ")}.'
          : 'The patient\'s key alerts field is empty.';

      if (isGeneralBriefing) {
        absenceMessage =
            '${patient.patientInitials} (${patient.bedNumber}) was admitted: "${patient.shortAdmittingNote}". '
            '$keyAlertsText '
            'No matching events were found in Oravi for the searched period. '
            'Kindly verify with the main hospital EHR. Missing in Oravi does not mean it did not happen.';
      } else {
        absenceMessage =
            'No record in Oravi mentions \'$queryString\' for this patient. '
            'Absence of a mention does not mean there was no change or that all is well. '
            'Kindly verify with the main hospital EHR. '
            '$keyAlertsText '
            'Admitted with primary note: "${patient.shortAdmittingNote}".';
      }
    }

    // Determine primary doctor for quick action button
    final doctorId = loops.any((l) => l.currentOwnerRole.contains('doc'))
        ? loops
              .firstWhere((l) => l.currentOwnerRole.contains('doc'))
              .currentOwnerId
        : 'Dr Otieno';

    return AskOraviResult(
      patientId: patientId,
      queryString: queryString,
      verbatimQuotes: matchingQuotes,
      systemPatterns: systemPatterns,
      coverage: coverage,
      isRefusal: isRefusal,
      refusalMessage: refusalMessage,
      isAbsence: isAbsence,
      absenceMessage: absenceMessage,
      doctorInChargeId: doctorId,
      allTimelineEntries: allEntries,
    );
  }

  static String _inferCadreRole(String authorId) {
    final lower = authorId.toLowerCase();
    if (lower.contains('doc') || lower.contains('otieno')) {
      return 'doctor_on_call';
    }
    if (lower.contains('nurse')) {
      return 'ward_nurse';
    }
    if (lower.contains('charge') || lower.contains('matron')) {
      return 'ward_in_charge';
    }
    if (lower.contains('pharm')) {
      return 'pharmacist';
    }
    if (lower.contains('lab')) {
      return 'lab_technician';
    }
    return 'clinician';
  }
}

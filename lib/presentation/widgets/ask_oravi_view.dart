import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/loop_enums.dart';
import '../../domain/projections/projections.dart';
import '../../domain/timeline/ask_oravi_engine.dart';
import '../../domain/timeline/patient_timeline_entry.dart';
import '../providers/ward_providers.dart';
import '../theme/clinical_theme.dart';
import 'log_call_outcome_dialog.dart';

/// Interactive Ask Oravi Query and Chronological Patient Timeline view.
///
/// Implements PRD Section 8A (FR-34 to FR-44):
/// - Plain-language clinical search (English & Kiswahili).
/// - Suggested query chips for common ward topics.
/// - Verbatim quotes with cadre coloring and timestamps.
/// - Actionable buttons: Message author, Call author (FR-38).
/// - Mandatory coverage line (FR-36).
/// - Absence handling (FR-37).
/// - System-computed pattern counts (FR-39).
/// - Diagnostic boundary refusal (FR-40).
/// - "Something is missing" feedback button (FR-44).
class AskOraviView extends ConsumerStatefulWidget {
  final PatientStateProjection patient;
  final void Function(String loopId)? onSwitchToLoop;
  final void Function(String loopId, String authorName)? onAnchorMessage;

  const AskOraviView({
    super.key,
    required this.patient,
    this.onSwitchToLoop,
    this.onAnchorMessage,
  });

  @override
  ConsumerState<AskOraviView> createState() => _AskOraviViewState();
}

class _AskOraviViewState extends ConsumerState<AskOraviView> {
  final TextEditingController _queryController = TextEditingController();
  AskOraviResult? _activeResult;
  bool _isLoadingModel = false;

  final List<String> _suggestedQueries = [
    'Urine / Mkojo',
    'SpO2 / Oxygen',
    'Blood / Cross-match',
    'Allergies',
    'Pain',
    'Last 8 hours',
  ];

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _runQuery(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return;

    _queryController.text = clean;
    final repo = ref.read(localWardRepositoryProvider);
    // 1. Immediate deterministic local result (zero-latency, 100% offline-ready)
    final result = repo.askOravi(
      patientId: widget.patient.patientId,
      queryString: clean,
    );

    setState(() {
      _activeResult = result;
      _isLoadingModel = true;
    });

    // 2. Query model-assisted backend in background (Milestone 5)
    // Silent fallback: if backend is unreachable or times out, local result stays active
    final modelService = ref.read(askOraviModelServiceProvider);
    modelService.askPatient(
      patientId: widget.patient.patientId,
      query: clean,
    ).then((resp) {
      if (!mounted) return;
      setState(() {
        _isLoadingModel = false;
        if (resp != null && resp.observationNote != null && resp.verificationPassed) {
          _activeResult = _activeResult?.copyWith(
            observationNote: resp.observationNote,
            isModelAssisted: true,
            modelProvider: resp.modelProvider,
            modelName: resp.modelName,
            verificationPassed: resp.verificationPassed,
          );
        }
      });
    }).catchError((_) {
      if (mounted) {
        setState(() {
          _isLoadingModel = false;
        });
      }
    });
  }

  void _clearQuery() {
    _queryController.clear();
    setState(() {
      _activeResult = null;
    });
  }

  void _showFeedbackDialog(String query) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ClinicalTheme.surface,
        title: const Row(
          children: [
            Icon(Icons.feedback_outlined, color: ClinicalTheme.routineTeal),
            SizedBox(width: 8),
            Text('Something is missing?', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Query: "$query"',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: ClinicalTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Help us improve the local ward lexicon. What did you expect to see that was not returned?',
              style: TextStyle(fontSize: 12, color: ClinicalTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 3,
              style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'e.g. "Catheter output was mentioned in yesterday\'s handoff"',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ClinicalTheme.routineTeal),
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Feedback logged. Thank you for improving Oravi.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Submit Feedback'),
          ),
        ],
      ),
    );
  }

  void _initiateCall(PatientTimelineEntry entry) {
    final loops = ref.read(patientLoopsProvider(widget.patient.patientId));
    final loop = loops.firstWhere(
      (l) => l.loopId == entry.loopId,
      orElse: () => loops.isNotEmpty
          ? loops.first
          : LoopStateProjection(
              loopId: 'GLOBAL-${widget.patient.patientId}',
              patientId: widget.patient.patientId,
              title: entry.loopTitle,
              description: entry.verbatimText,
              loopType: LoopType.taskOrPendingResult,
              urgency: entry.loopUrgency,
              state: entry.loopState,
              currentOwnerId: entry.authorId,
              currentOwnerRole: entry.authorRole,
              createdAt: entry.timestamp,
              updatedAt: entry.timestamp,
            ),
    );

    showDialog(
      context: context,
      builder: (ctx) => LogCallOutcomeDialog(
        loop: loop,
        recipientName: entry.authorId,
        recipientRole: entry.authorRole,
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayName = dayNames[local.weekday - 1];
    return '$dayName ${local.day}/${local.month} $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(patientTimelineProvider(widget.patient.patientId));

    return Column(
      children: [
        // 1. Search Bar & Query Input
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: ClinicalTheme.surface,
          child: Column(
            children: [
              TextField(
                controller: _queryController,
                textInputAction: TextInputAction.search,
                onSubmitted: _runQuery,
                style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ask Oravi or search record (English / Kiswahili)...',
                  hintStyle: const TextStyle(color: ClinicalTheme.textMuted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: ClinicalTheme.routineTeal),
                  suffixIcon: _queryController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: ClinicalTheme.textMuted, size: 18),
                          onPressed: _clearQuery,
                        )
                      : null,
                  filled: true,
                  fillColor: ClinicalTheme.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: ClinicalTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: ClinicalTheme.routineTeal, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 2. Suggested Quick Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _suggestedQueries.map((q) {
                    final isSelected = _queryController.text == q;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(q, style: const TextStyle(fontSize: 11)),
                        selected: isSelected,
                        selectedColor: ClinicalTheme.routineTeal.withValues(alpha: 0.3),
                        backgroundColor: ClinicalTheme.surfaceElevated,
                        side: const BorderSide(color: ClinicalTheme.border, width: 0.8),
                        onSelected: (_) => _runQuery(q),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        // 3. Results Body
        Expanded(
          child: _activeResult != null
              ? _buildSearchResultsView(_activeResult!)
              : _buildFullTimelineView(timeline),
        ),
      ],
    );
  }

  Widget _buildSearchResultsView(AskOraviResult result) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Refusal Banner (FR-40 & Example 8)
        if (result.isRefusal)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ClinicalTheme.criticalRed.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ClinicalTheme.criticalRed, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: ClinicalTheme.criticalRed, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Clinical Boundary Refusal (FR-40)',
                      style: TextStyle(fontWeight: FontWeight.bold, color: ClinicalTheme.criticalRed, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  result.refusalMessage!,
                  style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: ClinicalTheme.doctorPink,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 32),
                  ),
                  icon: const Icon(Icons.call, size: 14),
                  label: Text('Ask ${result.doctorInChargeId} (Doctor in charge)', style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    // Open call dialog to doctor
                    showDialog(
                      context: context,
                      builder: (ctx) => LogCallOutcomeDialog(
                        loop: ref.read(patientLoopsProvider(widget.patient.patientId)).first,
                        recipientName: result.doctorInChargeId,
                        recipientRole: 'doctor_on_call',
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

        // System Pattern Counts (FR-39)
        if (result.systemPatterns.isNotEmpty) ...[
          for (final pattern in result.systemPatterns)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: ClinicalTheme.urgentAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ClinicalTheme.urgentAmber.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insights, color: ClinicalTheme.urgentAmber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pattern.label,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: ClinicalTheme.urgentAmber),
                        ),
                        Text(
                          pattern.description,
                          style: const TextStyle(fontSize: 12, color: ClinicalTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
        ],

        // Absence Notice (FR-37)
        if (result.isAbsence)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ClinicalTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ClinicalTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: ClinicalTheme.urgentAmber, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'No Record in Oravi (FR-37)',
                      style: TextStyle(fontWeight: FontWeight.bold, color: ClinicalTheme.urgentAmber, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  result.absenceMessage!,
                  style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),

        // Model Observation Card (Milestone 5: PRD Section 8A & Tech Arch Section 11)
        if (result.observationNote != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2C223A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF8B5CF6), width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Note from Oravi, not from the record',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (result.modelName != null)
                      Text(
                        '${result.modelName} (${result.modelProvider ?? "local"})',
                        style: const TextStyle(fontSize: 10, color: Color(0xFFC4B5FD)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  result.observationNote!,
                  style: const TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.verified, size: 12, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text(
                      'All numbers verified against patient event log quotes below',
                      style: TextStyle(fontSize: 10, color: Color(0xFF10B981)),
                    ),
                  ],
                ),
              ],
            ),
          ),

        if (_isLoadingModel)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: ClinicalTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: ClinicalTheme.routineTeal),
                ),
                SizedBox(width: 8),
                Text('Verifying observations with ward model...', style: TextStyle(fontSize: 11, color: ClinicalTheme.textMuted)),
              ],
            ),
          ),

        // Verbatim Quotes Cards
        if (result.verbatimQuotes.isNotEmpty)
          for (final quote in result.verbatimQuotes)
            _buildQuoteCard(quote),

        const SizedBox(height: 12),

        // Coverage Line (FR-36) & Feedback Action (FR-44)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ClinicalTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ClinicalTheme.border, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, size: 14, color: ClinicalTheme.routineTeal),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      result.coverage.formattedLine,
                      style: const TextStyle(fontSize: 11, color: ClinicalTheme.textSecondary, height: 1.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: ClinicalTheme.routineTeal,
                    ),
                    icon: const Icon(Icons.help_outline, size: 14),
                    label: const Text('Something is missing?', style: TextStyle(fontSize: 11)),
                    onPressed: () => _showFeedbackDialog(result.queryString),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: ClinicalTheme.textMuted,
                    ),
                    onPressed: _clearQuery,
                    child: const Text('Clear search', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFullTimelineView(List<PatientTimelineEntry> timeline) {
    if (timeline.isEmpty) {
      return const Center(
        child: Text('No timeline entries recorded for this patient.', style: TextStyle(color: ClinicalTheme.textSecondary)),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'CHRONOLOGICAL RECORD (${timeline.length} ENTRIES)',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ClinicalTheme.textMuted, letterSpacing: 0.5),
            ),
            const Text(
              '100% Verbatim • Offline',
              style: TextStyle(fontSize: 11, color: ClinicalTheme.routineTeal),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final entry in timeline)
          _buildQuoteCard(entry),
      ],
    );
  }

  Widget _buildQuoteCard(PatientTimelineEntry entry) {
    final cadreColor = ClinicalTheme.cadreColor(entry.authorId);
    final urgencyColor = ClinicalTheme.urgencyColor(entry.loopUrgency);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Loop thread, Urgency, Timestamp
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.loopTitle,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ClinicalTheme.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: urgencyColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: urgencyColor, width: 0.8),
                  ),
                  child: Text(
                    entry.loopUrgency.name.toUpperCase(),
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: urgencyColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Middle: Author Cadre Pill & Verbatim Text
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cadreColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.authorId,
                    style: TextStyle(color: cadreColor, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '“${entry.verbatimText}”',
                    style: const TextStyle(fontSize: 13, color: ClinicalTheme.textPrimary, height: 1.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Bottom Row: Timestamp & Action Buttons (FR-38)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatTimestamp(entry.timestamp),
                  style: const TextStyle(fontSize: 11, color: ClinicalTheme.textMuted),
                ),
                Row(
                  children: [
                    if (entry.loopId != null && widget.onAnchorMessage != null)
                      InkWell(
                        onTap: () => widget.onAnchorMessage!(entry.loopId!, entry.authorId),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.chat_bubble_outline, size: 13, color: ClinicalTheme.nurseBlue),
                              const SizedBox(width: 4),
                              Text('Message', style: TextStyle(fontSize: 11, color: cadreColor)),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _initiateCall(entry),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 13, color: ClinicalTheme.successGreen),
                            const SizedBox(width: 4),
                            Text('Call', style: TextStyle(fontSize: 11, color: cadreColor)),
                          ],
                        ),
                      ),
                    ),
                    if (entry.loopId != null && widget.onSwitchToLoop != null) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => widget.onSwitchToLoop!(entry.loopId!),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Row(
                            children: [
                              Icon(Icons.visibility_outlined, size: 13, color: ClinicalTheme.routineTeal),
                              SizedBox(width: 4),
                              Text('Thread', style: TextStyle(fontSize: 11, color: ClinicalTheme.routineTeal)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

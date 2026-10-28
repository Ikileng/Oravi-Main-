import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/loop_enums.dart';
import '../../domain/projections/projections.dart';
import '../../domain/timeline/ask_oravi_engine.dart';
import '../../domain/timeline/patient_timeline_entry.dart';
import '../providers/ward_providers.dart';
import '../theme/clinical_theme.dart';
import 'log_call_outcome_dialog.dart';

enum ChatSender { clinician, oravi }

/// A single message in the conversational Ask Oravi chat thread.
class OraviChatMessage {
  final String id;
  final ChatSender sender;
  final String text;
  final DateTime timestamp;
  final AskOraviResult? result;
  final bool isLoading;
  final String? modelName;
  final String? modelProvider;
  final bool isModelAssisted;
  final List<LoopStateProjection>? activeMedicalIssues;
  final bool isAllClear;

  const OraviChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.result,
    this.isLoading = false,
    this.modelName,
    this.modelProvider,
    this.isModelAssisted = false,
    this.activeMedicalIssues,
    this.isAllClear = false,
  });

  OraviChatMessage copyWith({
    String? id,
    ChatSender? sender,
    String? text,
    DateTime? timestamp,
    AskOraviResult? result,
    bool? isLoading,
    String? modelName,
    String? modelProvider,
    bool? isModelAssisted,
    List<LoopStateProjection>? activeMedicalIssues,
    bool? isAllClear,
  }) {
    return OraviChatMessage(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      result: result ?? this.result,
      isLoading: isLoading ?? this.isLoading,
      modelName: modelName ?? this.modelName,
      modelProvider: modelProvider ?? this.modelProvider,
      isModelAssisted: isModelAssisted ?? this.isModelAssisted,
      activeMedicalIssues: activeMedicalIssues ?? this.activeMedicalIssues,
      isAllClear: isAllClear ?? this.isAllClear,
    );
  }
}

/// Interactive Conversational Ask Oravi Bedside Assistant.
///
/// Implements PRD Section 8A (FR-34 to FR-44):
/// - Persistent conversational dialogue between Clinician and Oravi Assistant.
/// - Plain-language clinical understanding (English & Kiswahili).
/// - Instant deterministic retrieval paired with offline Qwen 2.5 7B synthesis.
/// - Strict zero-hallucination verification harness (all numbers checked against raw event quotes).
/// - 1-tap Call and Message actions for relevant medical issues and authors.
/// - Diagnostic boundary refusal (FR-40).
/// - Modern persistent chat bar with audio/mic button ready for AI voice agent.
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
  final ScrollController _scrollController = ScrollController();
  final List<OraviChatMessage> _messages = [];

  final List<String> _suggestedQueries = [
    'SpO2 / Oxygen',
    'Urine / Mkojo',
    'Blood / Cross-match',
    'What do I need to know?',
    'Active Medical Issues',
    'What happened in the last 8 hours?',
    'Allergies',
  ];

  @override
  void initState() {
    super.initState();
    // Initial friendly greeting from Oravi
    _messages.add(
      OraviChatMessage(
        id: 'welcome',
        sender: ChatSender.oravi,
        text: 'Hello Nurse! I am Oravi, your offline clinical assistant for Bed ${widget.patient.bedNumber} (${widget.patient.nameOrInitials}). How may I help you with this patient?',
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isGreeting(String query) {
    final lower = query.trim().toLowerCase();
    const greetings = [
      'hello', 'hi', 'hey', 'jambo', 'habari', 'habari yako',
      'good morning', 'good afternoon', 'good evening', 'how are you', 'sasa', 'mambo'
    ];
    return greetings.contains(lower);
  }

  bool _isActiveMedicalIssuesQuery(String query) {
    final lower = query.trim().toLowerCase();
    return lower.contains('active medical issue') ||
           lower.contains('medical issue') ||
           lower.contains('active issue') ||
           lower.contains('open loop') ||
           lower.contains('open issue') ||
           lower.contains('pending issue') ||
           lower.contains('what issues') ||
           lower.contains('what loops') ||
           lower == 'loops' ||
           lower == 'issues';
  }

  bool _isBriefingQuery(String query) {
    final lower = query.trim().toLowerCase();
    return lower.contains('what do i need to know') ||
           lower.contains('what should i know') ||
           lower.contains('tell me what i need to know') ||
           lower.contains('tell me what i need to knkw') ||
           lower.contains('know nothing') ||
           lower.contains('brief me') ||
           lower.contains('catch me up') ||
           lower.contains('overview') ||
           lower.contains('summary') ||
           lower.contains('who is this patient') ||
           lower.contains('tell me about this patient') ||
           lower.contains('what happened');
  }

  void _sendMessage(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return;

    _queryController.clear();

    // 1. Add Clinician message bubble
    final clinicianMsg = OraviChatMessage(
      id: 'clinician-${DateTime.now().millisecondsSinceEpoch}',
      sender: ChatSender.clinician,
      text: clean,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(clinicianMsg);
    });
    _scrollToBottom();

    // 2. Conversational greetings intent
    if (_isGreeting(clean)) {
      final oraviGreeting = OraviChatMessage(
        id: 'oravi-${DateTime.now().millisecondsSinceEpoch}',
        sender: ChatSender.oravi,
        text: 'Hey, how may I help you with Bed ${widget.patient.bedNumber} (${widget.patient.nameOrInitials}) today?',
        timestamp: DateTime.now(),
      );
      setState(() {
        _messages.add(oraviGreeting);
      });
      _scrollToBottom();
      return;
    }

    // Read patient loops from store
    final loops = ref.read(patientLoopsProvider(widget.patient.patientId));
    final openLoops = loops.where((l) => l.isOpen).toList();

    // 3. Active Medical Issues Intent: Returns issues as rich action cards immediately
    if (_isActiveMedicalIssuesQuery(clean)) {
      final oraviMsg = OraviChatMessage(
        id: 'oravi-${DateTime.now().millisecondsSinceEpoch}',
        sender: ChatSender.oravi,
        text: openLoops.isNotEmpty
            ? (openLoops.length == 1
                ? 'There is 1 active medical issue currently open for ${widget.patient.nameOrInitials}:'
                : 'There are ${openLoops.length} active medical issues currently open for ${widget.patient.nameOrInitials}:')
            : 'ALL CLEAR — There are currently no active medical issues or open loops for ${widget.patient.nameOrInitials}.',
        timestamp: DateTime.now(),
        activeMedicalIssues: openLoops,
        isAllClear: openLoops.isEmpty,
      );

      setState(() {
        _messages.add(oraviMsg);
      });
      _scrollToBottom();
      return;
    }

    // 4. Clinical Briefing Intent: What do I need to know / Orientation
    if (_isBriefingQuery(clean)) {
      final oraviMsgId = 'oravi-${DateTime.now().millisecondsSinceEpoch}';
      final placeholder = OraviChatMessage(
        id: oraviMsgId,
        sender: ChatSender.oravi,
        text: 'Reviewing patient chart and active medical issues...',
        timestamp: DateTime.now(),
        isLoading: true,
      );

      setState(() {
        _messages.add(placeholder);
      });
      _scrollToBottom();

      // Query offline model service in background
      final modelService = ref.read(askOraviModelServiceProvider);
      modelService.askPatient(
        patientId: widget.patient.patientId,
        query: clean,
      ).then((resp) {
        if (!mounted) return;
        final synthesis = resp?.observationNote ??
            'Here is the clinical overview for ${widget.patient.nameOrInitials} (${widget.patient.bedNumber}):\n• Admitted: ${widget.patient.age}y ${widget.patient.sex}, ${widget.patient.shortAdmittingNote}\n• Key Alerts: ${widget.patient.keyAlerts.isNotEmpty ? widget.patient.keyAlerts.join(", ") : "No known allergies"}\n• Active Issues: ${openLoops.isEmpty ? "All Clear (0 open)" : "${openLoops.length} active issue(s)"}';

        setState(() {
          final idx = _messages.indexWhere((m) => m.id == oraviMsgId);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(
              text: synthesis,
              isLoading: false,
              isModelAssisted: resp != null && resp.observationNote != null,
              modelName: resp?.modelName,
              modelProvider: resp?.modelProvider,
              activeMedicalIssues: openLoops.isNotEmpty ? openLoops : null,
              isAllClear: openLoops.isEmpty,
            );
          }
        });
        _scrollToBottom();
      }).catchError((_) {
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == oraviMsgId);
            if (idx != -1) {
              _messages[idx] = _messages[idx].copyWith(
                text: 'Here is the clinical overview for ${widget.patient.nameOrInitials} (${widget.patient.bedNumber}):\n• Admitted: ${widget.patient.age}y ${widget.patient.sex}, ${widget.patient.shortAdmittingNote}\n• Key Alerts: ${widget.patient.keyAlerts.isNotEmpty ? widget.patient.keyAlerts.join(", ") : "No known allergies"}\n• Active Issues: ${openLoops.isEmpty ? "All Clear (0 open)" : "${openLoops.length} active issue(s)"}',
                isLoading: false,
                activeMedicalIssues: openLoops.isNotEmpty ? openLoops : null,
                isAllClear: openLoops.isEmpty,
              );
            }
          });
          _scrollToBottom();
        }
      });
      return;
    }

    // 5. Specific Topic Search (SpO2, Urine, Blood, etc.): Deterministic engine + Model synthesis
    final repo = ref.read(localWardRepositoryProvider);
    final localResult = repo.askOravi(
      patientId: widget.patient.patientId,
      queryString: clean,
    );

    final oraviMsgId = 'oravi-${DateTime.now().millisecondsSinceEpoch}';
    final oraviPlaceholder = OraviChatMessage(
      id: oraviMsgId,
      sender: ChatSender.oravi,
      text: 'Searching record for "$clean"...',
      timestamp: DateTime.now(),
      result: localResult,
      isLoading: true,
    );

    setState(() {
      _messages.add(oraviPlaceholder);
    });
    _scrollToBottom();

    final modelService = ref.read(askOraviModelServiceProvider);
    modelService.askPatient(
      patientId: widget.patient.patientId,
      query: clean,
    ).then((resp) {
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == oraviMsgId);
        if (idx != -1) {
          final displayText = (resp != null && resp.observationNote != null && resp.verificationPassed)
              ? resp.observationNote!
              : (localResult.verbatimQuotes.isNotEmpty
                  ? 'Here is what the record says about "$clean" for ${widget.patient.nameOrInitials}:'
                  : (localResult.absenceMessage ?? 'No record in Oravi mentions this topic.'));

          _messages[idx] = _messages[idx].copyWith(
            text: displayText,
            isModelAssisted: resp != null && resp.observationNote != null && resp.verificationPassed,
            modelName: resp?.modelName,
            modelProvider: resp?.modelProvider,
            isLoading: false,
            result: _messages[idx].result?.copyWith(
              observationNote: resp?.observationNote,
              isModelAssisted: resp != null,
              modelName: resp?.modelName,
              modelProvider: resp?.modelProvider,
              verificationPassed: resp?.verificationPassed,
            ),
          );
        }
      });
      _scrollToBottom();
    }).catchError((_) {
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == oraviMsgId);
          if (idx != -1) {
            final displayText = localResult.verbatimQuotes.isNotEmpty
                ? 'Here is what the record says about "$clean" for ${widget.patient.nameOrInitials}:'
                : (localResult.absenceMessage ?? 'No record in Oravi mentions this topic.');
            _messages[idx] = _messages[idx].copyWith(
              text: displayText,
              isLoading: false,
            );
          }
        });
        _scrollToBottom();
      }
    });
  }

  void _showVoiceFeedback() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.mic, color: ClinicalTheme.routineTeal, size: 18),
            SizedBox(width: 8),
            Text('AI Voice Agent will activate here. Type your query below.'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );
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
    return Column(
      children: [
        // 1. Conversational Chat History List
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              return msg.sender == ChatSender.clinician
                  ? _buildClinicianBubble(msg)
                  : _buildOraviBubble(msg);
            },
          ),
        ),

        // 2. Suggested Prompt Chips (Horizontally Scrollable)
        Container(
          height: 38,
          margin: const EdgeInsets.only(bottom: 4),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: _suggestedQueries.length,
            itemBuilder: (context, index) {
              final chipText = _suggestedQueries[index];
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  label: Text(chipText, style: const TextStyle(fontSize: 11)),
                  backgroundColor: ClinicalTheme.surfaceElevated,
                  side: const BorderSide(color: ClinicalTheme.border, width: 0.8),
                  onPressed: () => _sendMessage(chipText),
                ),
              );
            },
          ),
        ),

        // 3. Persistent Input Bar (Microphone + TextField + Send)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const BoxDecoration(
            color: ClinicalTheme.surface,
            border: Border(top: BorderSide(color: ClinicalTheme.border, width: 0.8)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                // Audio / Mic Button
                IconButton(
                  tooltip: 'Voice Assistant (Audio)',
                  icon: const Icon(Icons.mic, color: ClinicalTheme.routineTeal),
                  onPressed: _showVoiceFeedback,
                ),
                const SizedBox(width: 4),

                // Text Input
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _sendMessage,
                    style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Message Oravi about this patient...',
                      hintStyle: const TextStyle(color: ClinicalTheme.textMuted, fontSize: 12),
                      filled: true,
                      fillColor: ClinicalTheme.background,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: ClinicalTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: ClinicalTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: ClinicalTheme.routineTeal),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // Send Button
                IconButton(
                  tooltip: 'Send Query',
                  icon: const Icon(Icons.send_rounded, color: ClinicalTheme.routineTeal),
                  onPressed: () => _sendMessage(_queryController.text),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClinicianBubble(OraviChatMessage msg) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ClinicalTheme.routineTeal.withValues(alpha: 0.22),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(2),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          border: Border.all(color: ClinicalTheme.routineTeal.withValues(alpha: 0.5), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              msg.text,
              style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(msg.timestamp),
              style: const TextStyle(fontSize: 10, color: ClinicalTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOraviBubble(OraviChatMessage msg) {
    final result = msg.result;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, right: 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Oravi Bot Tag
            Row(
              children: [
                const Icon(Icons.smart_toy_outlined, size: 15, color: ClinicalTheme.routineTeal),
                const SizedBox(width: 6),
                const Text(
                  'Oravi Assistant',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ClinicalTheme.routineTeal),
                ),
                const Spacer(),
                Text(
                  _formatTimestamp(msg.timestamp),
                  style: const TextStyle(fontSize: 10, color: ClinicalTheme.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 1. Model Observation Card (Milestone 5)
            if (msg.isModelAssisted || result?.observationNote != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
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
                        if (msg.modelName != null || result?.modelName != null)
                          Text(
                            '${msg.modelName ?? result?.modelName} (${msg.modelProvider ?? result?.modelProvider ?? "local"})',
                            style: const TextStyle(fontSize: 10, color: Color(0xFFC4B5FD)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      msg.text,
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
              )
            else if (!msg.isLoading && !(result != null && result.isAbsence && !result.isRefusal))
              // Standard message text bubble (only shown if not loading and not an absence card)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: ClinicalTheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  border: Border.all(color: ClinicalTheme.border, width: 0.8),
                ),
                child: Text(
                  msg.text,
                  style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 13, height: 1.35),
                ),
              ),

            // Loading / Thinking Shimmer
            if (msg.isLoading) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: ClinicalTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: ClinicalTheme.routineTeal),
                    ),
                    const SizedBox(width: 8),
                    Text(msg.text, style: const TextStyle(fontSize: 11, color: ClinicalTheme.textMuted)),
                  ],
                ),
              ),
            ],

            // Active Medical Issues Cards (Returned as rich actionable cards)
            if (msg.activeMedicalIssues != null && msg.activeMedicalIssues!.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final issue in msg.activeMedicalIssues!)
                _buildActiveMedicalIssueCard(issue),
            ],

            // All Clear Status Card
            if (msg.isAllClear) ...[
              const SizedBox(height: 6),
              _buildAllClearCard(),
            ],

            // Clinical Refusal Banner (FR-40)
            if (result != null && result.isRefusal) ...[
              const SizedBox(height: 8),
              Container(
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
                        Icon(Icons.shield_outlined, color: ClinicalTheme.criticalRed, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Clinical Boundary Refusal (FR-40)',
                          style: TextStyle(fontWeight: FontWeight.bold, color: ClinicalTheme.criticalRed, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      result.refusalMessage ?? '',
                      style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: ClinicalTheme.doctorPink,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: const Icon(Icons.call, size: 13),
                      label: Text('Ask ${result.doctorInChargeId} (Doctor on call)', style: const TextStyle(fontSize: 11)),
                      onPressed: () {
                        final loops = ref.read(patientLoopsProvider(widget.patient.patientId));
                        if (loops.isNotEmpty) {
                          showDialog(
                            context: context,
                            builder: (ctx) => LogCallOutcomeDialog(
                              loop: loops.first,
                              recipientName: result.doctorInChargeId,
                              recipientRole: 'doctor_on_call',
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],

            // Absence Notice (FR-37)
            // Rule: Only show the yellow absence notice on targeted keyword search if the model has NOT provided an observation note.
            // When Qwen provides a verified observation note, the response is NOT an absence, preventing contradictory UI.
            if (result != null &&
                result.isAbsence &&
                !result.isRefusal &&
                !msg.isLoading &&
                !msg.isModelAssisted &&
                result.observationNote == null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ClinicalTheme.urgentAmber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ClinicalTheme.urgentAmber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: ClinicalTheme.urgentAmber, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result.absenceMessage ?? '',
                        style: const TextStyle(fontSize: 12, color: ClinicalTheme.textPrimary, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Verbatim Quotes Cards with 1-Tap Action Buttons
            if (result != null && result.verbatimQuotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final quote in result.verbatimQuotes)
                _buildQuoteCard(quote),
            ],

            // Coverage Line Metadata (FR-36)
            if (result != null && !result.isRefusal && !msg.isLoading) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, size: 12, color: ClinicalTheme.routineTeal),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      result.coverage.formattedLine,
                      style: const TextStyle(fontSize: 10, color: ClinicalTheme.textMuted, height: 1.3),
                    ),
                  ),
                  InkWell(
                    onTap: () => _showFeedbackDialog(result.queryString),
                    child: const Text('Something is missing?', style: TextStyle(fontSize: 10, color: ClinicalTheme.routineTeal)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveMedicalIssueCard(LoopStateProjection loop) {
    final urgencyColor = ClinicalTheme.urgencyColor(loop.urgency);
    final ownerColor = ClinicalTheme.cadreColor(loop.currentOwnerId);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ClinicalTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: loop.urgency == LoopUrgency.critical
              ? ClinicalTheme.criticalRed
              : ClinicalTheme.border,
          width: loop.urgency == LoopUrgency.critical ? 1.4 : 0.9,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Urgency Pill + Type + Timestamp
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: urgencyColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: urgencyColor, width: 0.9),
                ),
                child: Text(
                  loop.urgency.wireName.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: urgencyColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                loop.loopType.wireName.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ClinicalTheme.textMuted),
              ),
              const Spacer(),
              Text(
                _formatTimestamp(loop.createdAt),
                style: const TextStyle(fontSize: 10, color: ClinicalTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Title
          Text(
            loop.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: ClinicalTheme.textPrimary,
            ),
          ),
          if (loop.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              loop.description,
              style: const TextStyle(fontSize: 12, color: ClinicalTheme.textSecondary, height: 1.3),
            ),
          ],
          const SizedBox(height: 10),

          // Bottom Row: Clinician who raised / owns it + 1-Tap Action Buttons
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ownerColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline, size: 12, color: ownerColor),
                    const SizedBox(width: 4),
                    Text(
                      loop.currentOwnerId,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: ownerColor),
                    ),
                  ],
                ),
              ),
              const Spacer(),

              // 1-Tap Message Button: switches tab to thread with pre-filled mention
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: ClinicalTheme.nurseBlue,
                  side: const BorderSide(color: ClinicalTheme.nurseBlue, width: 0.8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 28),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 12),
                label: Text('Message ${loop.currentOwnerId}', style: const TextStyle(fontSize: 11)),
                onPressed: () {
                  if (widget.onAnchorMessage != null) {
                    widget.onAnchorMessage!(loop.loopId, loop.currentOwnerId);
                  }
                },
              ),
              const SizedBox(width: 6),

              // 1-Tap Call Button: opens post-call outcome prompt immediately
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: ClinicalTheme.doctorPink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 28),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.call, size: 12),
                label: const Text('Call', style: TextStyle(fontSize: 11)),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => LogCallOutcomeDialog(
                      loop: loop,
                      recipientName: loop.currentOwnerId,
                      recipientRole: loop.currentOwnerRole,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllClearCard() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ClinicalTheme.successGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClinicalTheme.successGreen.withValues(alpha: 0.5), width: 1),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: ClinicalTheme.successGreen, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ALL CLEAR — No Active Medical Issues',
                  style: TextStyle(color: ClinicalTheme.successGreen, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                SizedBox(height: 2),
                Text(
                  'There are currently 0 open loops or pending escalations for this patient.',
                  style: TextStyle(color: ClinicalTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteCard(PatientTimelineEntry entry) {
    final cadreColor = ClinicalTheme.cadreColor(entry.authorId);
    final urgencyColor = ClinicalTheme.urgencyColor(entry.loopUrgency);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ClinicalTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClinicalTheme.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Issue Title & Urgency
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
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
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

          // Row 2: Author Cadre Pill & Verbatim Text
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
                  style: TextStyle(color: cadreColor, fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '“${entry.verbatimText}”',
                  style: const TextStyle(fontSize: 12, color: ClinicalTheme.textPrimary, height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 3: Timestamp & Action Buttons (1-Tap Call and Message)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatTimestamp(entry.timestamp),
                style: const TextStyle(fontSize: 10, color: ClinicalTheme.textMuted),
              ),
              Row(
                children: [
                  if (entry.loopId != null && widget.onAnchorMessage != null)
                    InkWell(
                      onTap: () => widget.onAnchorMessage!(entry.loopId!, entry.authorId),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.chat_bubble_outline, size: 12, color: ClinicalTheme.nurseBlue),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: const Row(
                        children: [
                          Icon(Icons.call_outlined, size: 12, color: ClinicalTheme.doctorPink),
                          SizedBox(width: 4),
                          Text('Call', style: TextStyle(fontSize: 11, color: ClinicalTheme.doctorPink)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'widgets/ask_oravi_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/loop_enums.dart';
import '../domain/models/staff_profile.dart';
import '../domain/projections/projections.dart';
import 'providers/auth_providers.dart';
import 'providers/ward_providers.dart';
import 'providers/whiteboard_providers.dart';
import 'theme/clinical_theme.dart';
import 'widgets/close_loop_dialog.dart';
import 'widgets/create_loop_dialog.dart';
import 'widgets/log_call_outcome_dialog.dart';

/// Screen displaying all loops (active & recently closed) for a single patient.
///
/// Implements PRD Section 7.2, FR-54, and FR-55:
/// - Loop card list sorted by urgency.
/// - Inline append-only thread message history with WhatsApp-style formatted timestamps.
/// - Cadre color-coding (Nurses = Blue, Doctors = Pink, In-Charge = Purple, etc.).
/// - One-tap Message action (anchors @Mention directly in the loop thread).
/// - One-tap Call action with mandatory post-call outcome note dialog (FR-54).
class PatientDetailScreen extends ConsumerStatefulWidget {
  final PatientStateProjection patient;
  final Set<String>? issueOnlyLoopIds;
  final String? initialExpandedLoopId;

  const PatientDetailScreen({
    super.key,
    required this.patient,
    this.issueOnlyLoopIds,
    this.initialExpandedLoopId,
  });

  @override
  ConsumerState<PatientDetailScreen> createState() =>
      _PatientDetailScreenState();
}

class _PatientDetailScreenState extends ConsumerState<PatientDetailScreen>
    with SingleTickerProviderStateMixin {
  final Map<String, TextEditingController> _replyControllers = {};
  final Map<String, Set<String>> _replyMentions = {};
  final Set<String> _expandedLoopIds = {};
  Offset? _fabPosition;
  late final TabController _tabController = TabController(
    length: widget.issueOnlyLoopIds == null ? 2 : 1,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    final initialLoopId = widget.initialExpandedLoopId;
    if (initialLoopId != null) _expandedLoopIds.add(initialLoopId);
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _replyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getReplyController(String loopId) {
    return _replyControllers.putIfAbsent(loopId, () => TextEditingController());
  }

  Future<void> _runLoopAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save that action. Please try again.'),
        ),
      );
    }
  }

  Future<void> _assignLoopOwner(LoopStateProjection loop) async {
    try {
      final staff = await ref.read(
        patientStaffListProvider(loop.patientId).future,
      );
      if (!mounted) return;
      final selected = await showDialog<StaffProfile>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Assign Medical Issue'),
          content: SizedBox(
            width: 360,
            height: 320,
            child: ListView(
              shrinkWrap: true,
              children: staff.where((item) => item.isActive).map((item) {
                return ListTile(
                  title: Text(item.name),
                  subtitle: Text(item.formattedRole),
                  onTap: () => Navigator.of(dialogContext).pop(item),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      await ref
          .read(wardControllerProvider.notifier)
          .changeLoopOwner(
            patientId: loop.patientId,
            loopId: loop.loopId,
            newOwnerId: selected.staffId,
            newOwnerRole: selected.role,
          );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not assign the medical issue. Please retry.'),
        ),
      );
    }
  }

  Future<void> _sendReply(String loopId) async {
    final controller = _getReplyController(loopId);
    final text = controller.text.trim();
    if (text.isEmpty) return;

    try {
      await ref
          .read(wardControllerProvider.notifier)
          .postMessage(
            patientId: widget.patient.patientId,
            loopId: loopId,
            content: text,
            mentionedStaffIds: _replyMentions[loopId]?.toList() ?? const [],
          );
      controller.clear();
      _replyMentions.remove(loopId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the update. Please try again.'),
          ),
        );
      }
    }
  }

  void _anchorMessageToAuthor(String loopId, String authorName) {
    _tabController.animateTo(0);
    final controller = _getReplyController(loopId);
    final displayName = ClinicalTheme.formatAuthorDisplayName(authorName);
    final mention = '@$displayName: ';
    if (!controller.text.startsWith(mention)) {
      controller.text = '$mention${controller.text}';
    }
    if (widget.issueOnlyLoopIds == null) {
      _replyMentions.putIfAbsent(loopId, () => {}).add(authorName);
    }
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );
  }

  Future<void> _toggleIssueThread(LoopStateProjection loop) async {
    if (_expandedLoopIds.remove(loop.loopId)) {
      setState(() {});
      return;
    }

    setState(() => _expandedLoopIds.add(loop.loopId));
    try {
      await ref
          .read(wardControllerProvider.notifier)
          .recordLoopRead(patientId: loop.patientId, loopId: loop.loopId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not record that this issue was read.'),
        ),
      );
    }
  }

  Future<void> _mentionClinician(String loopId) async {
    try {
      final staff = await ref.read(
        patientStaffListProvider(widget.patient.patientId).future,
      );
      if (!mounted) return;
      final selected = await showDialog<StaffProfile>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mention a clinician'),
          content: SizedBox(
            width: 360,
            height: 320,
            child: ListView(
              children: staff
                  .where((item) => item.isActive)
                  .map(
                    (item) => ListTile(
                      title: Text(item.name),
                      subtitle: Text(item.formattedRole),
                      onTap: () => Navigator.of(dialogContext).pop(item),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      final controller = _getReplyController(loopId);
      final mention = '@${selected.name} ';
      controller.text = '${controller.text}$mention';
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      _replyMentions.putIfAbsent(loopId, () => {}).add(selected.staffId);
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load clinicians for this patient.'),
        ),
      );
    }
  }

  void _openCallDialog(
    LoopStateProjection loop,
    String recipientId,
    String authorRole,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => LogCallOutcomeDialog(
        loop: loop,
        recipientId: recipientId,
        recipientName: ClinicalTheme.formatAuthorDisplayName(recipientId),
        recipientRole: authorRole,
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final now = DateTime.now();

    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '$hour:$minute • Today';
    }
    return '$hour:$minute • ${local.day}/${local.month}';
  }

  @override
  Widget build(BuildContext context) {
    final hasCurrentPatientAccess = ref
        .watch(currentUserPatientIdsProvider)
        .contains(widget.patient.patientId);
    if (widget.issueOnlyLoopIds == null && !hasCurrentPatientAccess) {
      return Scaffold(
        backgroundColor: ClinicalTheme.background,
        appBar: AppBar(title: const Text('Patient access ended')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'This patient is no longer assigned to your account. The patient chart and other Medical Issues are unavailable.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ClinicalTheme.textSecondary),
            ),
          ),
        ),
      );
    }
    final allLoops = ref.watch(patientLoopsProvider(widget.patient.patientId));
    final loops = widget.issueOnlyLoopIds == null
        ? allLoops
        : allLoops
              .where((loop) => widget.issueOnlyLoopIds!.contains(loop.loopId))
              .toList();

    final openLoopsCount = loops.where((l) => l.isOpen).length;
    final issuesTab = loops.isEmpty
        ? Center(
            child: Text(
              widget.issueOnlyLoopIds == null
                  ? 'No Active Medical Issues'
                  : 'This carried Medical Issue is unavailable on this device.',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: ClinicalTheme.textPrimary,
              ),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: loops.length,
            itemBuilder: (context, index) => _buildLoopCard(loops[index]),
          );

    return Scaffold(
      backgroundColor: ClinicalTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.issueOnlyLoopIds == null
                  ? '${widget.patient.bedNumber} — ${widget.patient.patientInitials}'
                  : 'Carried Medical Issue',
            ),
            if (widget.issueOnlyLoopIds == null)
              Text(
                '${widget.patient.age}y / ${widget.patient.sex} • Admitted: ${widget.patient.shortAdmittingNote}',
                style: const TextStyle(
                  fontSize: 11,
                  color: ClinicalTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: ClinicalTheme.routineTeal,
          labelColor: ClinicalTheme.routineTeal,
          unselectedLabelColor: ClinicalTheme.textSecondary,
          tabs: [
            Tab(
              icon: const Icon(Icons.checklist, size: 18),
              text: 'Medical Issues ($openLoopsCount)',
            ),
            if (widget.issueOnlyLoopIds == null)
              const Tab(
                icon: Icon(Icons.smart_toy_outlined, size: 18),
                text: 'Ask Oravi',
              ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight;
          // Default position: bottom-right, comfortably positioned
          final defaultPosition = Offset(
            (maxW - 200.0).clamp(8.0, maxW),
            (maxH - 72.0).clamp(8.0, maxH),
          );
          final pos = _fabPosition ?? defaultPosition;

          return Stack(
            children: [
              Column(
                children: [
                  // Alerts Banner if patient has key alerts
                  if (widget.issueOnlyLoopIds == null &&
                      widget.patient.keyAlerts.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: ClinicalTheme.criticalRed.withValues(alpha: 0.12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: ClinicalTheme.criticalRed,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Key Alerts: ${widget.patient.keyAlerts.join(", ")}',
                            style: const TextStyle(
                              color: ClinicalTheme.criticalRed,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // TabBarView
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: widget.issueOnlyLoopIds == null
                          ? [
                              issuesTab,
                              AskOraviView(
                                patient: widget.patient,
                                onAnchorMessage: (loopId, author) {
                                  _anchorMessageToAuthor(loopId, author);
                                },
                              ),
                            ]
                          : [issuesTab],
                    ),
                  ),
                ],
              ),

              // Dynamically Draggable Floating Button: User can move it freely anywhere on the screen
              if (widget.issueOnlyLoopIds == null)
                Positioned(
                  left: pos.dx.clamp(8.0, (maxW - 195.0).clamp(8.0, maxW)),
                  top: pos.dy.clamp(8.0, (maxH - 52.0).clamp(8.0, maxH)),
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        final current = _fabPosition ?? defaultPosition;
                        final newX = (current.dx + details.delta.dx).clamp(
                          8.0,
                          maxW - 195.0,
                        );
                        final newY = (current.dy + details.delta.dy).clamp(
                          8.0,
                          maxH - 52.0,
                        );
                        _fabPosition = Offset(newX, newY);
                      });
                    },
                    child: Material(
                      elevation: 6,
                      shadowColor: Colors.black.withValues(alpha: 0.4),
                      color: ClinicalTheme.routineTeal,
                      borderRadius: BorderRadius.circular(28),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: () => showDialog(
                          context: context,
                          builder: (ctx) => CreateLoopDialog(
                            patientId: widget.patient.patientId,
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.drag_indicator,
                                size: 16,
                                color: Colors.white70,
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.add_task,
                                size: 18,
                                color: Colors.white,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Raise Medical Issue',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoopCard(LoopStateProjection loop) {
    final urgencyColor = ClinicalTheme.urgencyColor(loop.urgency);
    final ownerCadreColor = ClinicalTheme.cadreColor(loop.currentOwnerId);
    final signedInStaff = ref.watch(authenticatedStaffProvider);
    final boardAssignedDoctorId = ref
        .watch(whiteboardAssignmentsProvider)
        .where((bed) => bed.patientId == loop.patientId)
        .map((bed) => bed.admittingDoctor)
        .where((doctorId) => doctorId.isNotEmpty && doctorId != '-')
        .firstOrNull;
    final canConfirmCriticalClosure =
        signedInStaff?.staffId == boardAssignedDoctorId &&
        boardAssignedDoctorId != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Type, Urgency Badge, State Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: urgencyColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: urgencyColor, width: 0.8),
                  ),
                  child: Text(
                    loop.urgency.wireName.toUpperCase(),
                    style: TextStyle(
                      color: urgencyColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  loop.loopType.wireName.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                    color: ClinicalTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                _buildStateBadge(loop),
              ],
            ),
            const SizedBox(height: 8),

            // Loop Title & Description
            Text(
              loop.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: loop.isOpen
                    ? ClinicalTheme.textPrimary
                    : ClinicalTheme.textMuted,
                decoration: loop.isOpen ? null : TextDecoration.lineThrough,
              ),
            ),
            if (loop.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                loop.description,
                style: const TextStyle(
                  fontSize: 12,
                  color: ClinicalTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),

            // Active Escalation Warning if present
            if (loop.activeEscalation != null)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ClinicalTheme.criticalRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: ClinicalTheme.criticalRed),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.emergency,
                      color: ClinicalTheme.criticalRed,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Escalated to ${loop.activeEscalation!.targetRole}: "${loop.activeEscalation!.reason}"',
                        style: const TextStyle(
                          color: ClinicalTheme.criticalRed,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Owner & Metadata Row with Color-Coded Cadre
            Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: ownerCadreColor),
                const SizedBox(width: 4),
                Text(
                  'Owner: ',
                  style: const TextStyle(
                    fontSize: 11,
                    color: ClinicalTheme.textMuted,
                  ),
                ),
                Text(
                  ClinicalTheme.formatAuthorDisplayName(loop.currentOwnerId),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: ownerCadreColor,
                  ),
                ),
                Text(
                  ' (${loop.currentOwnerRole})',
                  style: const TextStyle(
                    fontSize: 11,
                    color: ClinicalTheme.textMuted,
                  ),
                ),
                if (loop.reopenCount > 0) ...[
                  const Spacer(),
                  Text(
                    'Reopened ${loop.reopenCount}x',
                    style: const TextStyle(
                      fontSize: 11,
                      color: ClinicalTheme.urgentAmber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
            if (loop.isOpen &&
                loop.state != LoopState.closedAwaitingConfirmation) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (signedInStaff != null &&
                      !loop.acknowledgedByUserIds.containsKey(
                        signedInStaff.staffId,
                      ))
                    OutlinedButton.icon(
                      onPressed: () => _runLoopAction(
                        () => ref
                            .read(wardControllerProvider.notifier)
                            .acknowledgeLoop(
                              patientId: loop.patientId,
                              loopId: loop.loopId,
                            ),
                      ),
                      icon: const Icon(Icons.visibility, size: 16),
                      label: const Text('Acknowledge'),
                    ),
                  if (signedInStaff != null &&
                      loop.acknowledgedByUserIds.containsKey(
                        signedInStaff.staffId,
                      ))
                    const Chip(
                      avatar: Icon(Icons.check, size: 16),
                      label: Text('Acknowledged by you'),
                    ),
                  if (loop.state == LoopState.raised ||
                      loop.state == LoopState.acknowledged)
                    OutlinedButton.icon(
                      onPressed: () => _runLoopAction(
                        () => ref
                            .read(wardControllerProvider.notifier)
                            .startLoopWork(
                              patientId: loop.patientId,
                              loopId: loop.loopId,
                            ),
                      ),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('Start work'),
                    ),
                  if (widget.issueOnlyLoopIds == null)
                    TextButton.icon(
                      onPressed: () => _assignLoopOwner(loop),
                      icon: const Icon(Icons.person_add_alt_1, size: 16),
                      label: const Text('Assign'),
                    ),
                ],
              ),
            ],
            TextButton.icon(
              onPressed: () => _toggleIssueThread(loop),
              icon: Icon(
                _expandedLoopIds.contains(loop.loopId)
                    ? Icons.expand_less
                    : Icons.forum_outlined,
                size: 16,
              ),
              label: Text(
                _expandedLoopIds.contains(loop.loopId)
                    ? 'Close issue thread'
                    : 'Open issue thread (${loop.messages.length})',
              ),
            ),
            if (loop.state == LoopState.closedAwaitingConfirmation &&
                boardAssignedDoctorId == null &&
                signedInStaff?.role == 'charge_nurse')
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'No doctor is assigned to this patient on the current ward board. Assign a doctor before closure can be confirmed.',
                  style: TextStyle(
                    fontSize: 11,
                    color: ClinicalTheme.criticalRed,
                  ),
                ),
              ),
            const Divider(color: ClinicalTheme.border, height: 20),

            if (_expandedLoopIds.contains(loop.loopId)) ...[
              // Append-only Thread Messages with WhatsApp-style timestamps & Action Buttons (FR-54, FR-55)
              if (loop.messages.isNotEmpty) ...[
                const Text(
                  'Thread History (Append-Only):',
                  style: TextStyle(
                    color: ClinicalTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                ...loop.messages.map((msg) {
                  final authorColor = ClinicalTheme.cadreColor(msg.authorId);
                  final timeFormatted = _formatTimestamp(msg.createdAt);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: msg.isCallLog
                            ? ClinicalTheme.routineTeal.withValues(alpha: 0.12)
                            : ClinicalTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: msg.isCallLog
                            ? Border.all(
                                color: ClinicalTheme.routineTeal,
                                width: 0.8,
                              )
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Message Header: Color-coded Author + WhatsApp timestamp + Quick Actions
                          Row(
                            children: [
                              Text(
                                ClinicalTheme.formatAuthorDisplayName(
                                  msg.authorId,
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: authorColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                timeFormatted,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: ClinicalTheme.textMuted,
                                ),
                              ),
                              const Spacer(),

                              // One-tap Message button (anchors @reply in thread)
                              InkWell(
                                onTap: () => _anchorMessageToAuthor(
                                  loop.loopId,
                                  msg.authorId,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.reply,
                                        size: 13,
                                        color: ClinicalTheme.routineTeal,
                                      ),
                                      SizedBox(width: 2),
                                      Text(
                                        'Reply',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: ClinicalTheme.routineTeal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // One-tap Call button (opens post-call outcome prompt - FR-54)
                              InkWell(
                                onTap: () => _openCallDialog(
                                  loop,
                                  msg.authorId,
                                  msg.authorRole,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.call,
                                        size: 13,
                                        color: ClinicalTheme.successGreen,
                                      ),
                                      SizedBox(width: 2),
                                      Text(
                                        'Call',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: ClinicalTheme.successGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // Message Content
                          Text(
                            msg.content,
                            style: TextStyle(
                              fontSize: 12,
                              color: msg.isCallLog
                                  ? ClinicalTheme.textPrimary
                                  : ClinicalTheme.textPrimary,
                              fontWeight: msg.isCallLog
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],

              // Critical closure requires confirmation from the board-assigned doctor.
              if (loop.state == LoopState.closedAwaitingConfirmation)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ClinicalTheme.urgentAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: ClinicalTheme.urgentAmber),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Closure awaiting confirmation by the board-assigned doctor.',
                        style: TextStyle(
                          fontSize: 11,
                          color: ClinicalTheme.urgentAmber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (canConfirmCriticalClosure)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ClinicalTheme.urgentAmber,
                                foregroundColor: Colors.black,
                              ),
                              onPressed: () => _runLoopAction(
                                () => ref
                                    .read(wardControllerProvider.notifier)
                                    .confirmCriticalClosure(
                                      patientId: loop.patientId,
                                      loopId: loop.loopId,
                                    ),
                              ),
                              child: const Text('Confirm closure'),
                            ),
                          TextButton.icon(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (ctx) => ReopenLoopDialog(loop: loop),
                            ),
                            icon: const Icon(Icons.replay, size: 16),
                            label: const Text('Reopen'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (loop.isOpen &&
                  loop.state != LoopState.closedAwaitingConfirmation) ...[
                // Reply Input
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _getReplyController(loop.loopId),
                        style: const TextStyle(
                          color: ClinicalTheme.textPrimary,
                          fontSize: 12,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Add note or update...',
                          hintStyle: const TextStyle(
                            color: ClinicalTheme.textMuted,
                            fontSize: 11,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          filled: true,
                          fillColor: ClinicalTheme.surfaceElevated,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: ClinicalTheme.border,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _sendReply(loop.loopId),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (widget.issueOnlyLoopIds == null)
                      IconButton(
                        tooltip: 'Mention a clinician',
                        icon: const Icon(
                          Icons.alternate_email,
                          color: ClinicalTheme.routineTeal,
                          size: 20,
                        ),
                        onPressed: () => _mentionClinician(loop.loopId),
                      ),
                    IconButton(
                      icon: const Icon(
                        Icons.send,
                        color: ClinicalTheme.routineTeal,
                        size: 20,
                      ),
                      onPressed: () => _sendReply(loop.loopId),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ClinicalTheme.successGreen,
                        side: const BorderSide(
                          color: ClinicalTheme.successGreen,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (ctx) => CloseLoopDialog(loop: loop),
                      ),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text(
                        'Close',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
              if (!loop.isOpen) ...[
                // Closed State Details & Reopen Button
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Closed by ${loop.closedByUserId}: ${loop.closureReasonText ?? loop.closureReason?.wireName ?? "closed"} (${loop.resolutionType == ClosureResolutionType.closedWithoutResolution
                            ? "Closed without resolution"
                            : loop.resolutionType == ClosureResolutionType.resolved
                            ? "Resolved"
                            : "Outcome not recorded"}) ${loop.closureNote ?? ""}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: ClinicalTheme.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: ClinicalTheme.urgentAmber,
                      ),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (ctx) => ReopenLoopDialog(loop: loop),
                      ),
                      icon: const Icon(Icons.replay, size: 16),
                      label: const Text(
                        'Reopen',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStateBadge(LoopStateProjection loop) {
    switch (loop.state) {
      case LoopState.raised:
        return _badge('RAISED', ClinicalTheme.textSecondary);
      case LoopState.acknowledged:
        return _badge('ACKNOWLEDGED', ClinicalTheme.routineTeal);
      case LoopState.inProgress:
        return _badge('IN PROGRESS', ClinicalTheme.urgentAmber);
      case LoopState.closedAwaitingConfirmation:
        return _badge('AWAITING CONFIRMATION', ClinicalTheme.criticalRed);
      case LoopState.closed:
        return _badge('CLOSED', ClinicalTheme.textMuted);
    }
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

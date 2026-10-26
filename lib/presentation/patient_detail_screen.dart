import 'widgets/ask_oravi_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/loop_enums.dart';
import '../domain/projections/projections.dart';
import 'providers/ward_providers.dart';
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

  const PatientDetailScreen({super.key, required this.patient});

  @override
  ConsumerState<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends ConsumerState<PatientDetailScreen> {
  final Map<String, TextEditingController> _replyControllers = {};

  @override
  void dispose() {
    for (final c in _replyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getReplyController(String loopId) {
    return _replyControllers.putIfAbsent(loopId, () => TextEditingController());
  }

  void _sendReply(String loopId) {
    final controller = _getReplyController(loopId);
    final text = controller.text.trim();
    if (text.isEmpty) return;

    ref.read(wardControllerProvider.notifier).postMessage(
          patientId: widget.patient.patientId,
          loopId: loopId,
          content: text,
        );
    controller.clear();
  }

  void _anchorMessageToAuthor(String loopId, String authorName) {
    final controller = _getReplyController(loopId);
    final mention = '@$authorName: ';
    if (!controller.text.startsWith(mention)) {
      controller.text = '$mention${controller.text}';
    }
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );
  }

  void _openCallDialog(LoopStateProjection loop, String authorName, String authorRole) {
    showDialog(
      context: context,
      builder: (ctx) => LogCallOutcomeDialog(
        loop: loop,
        recipientName: authorName,
        recipientRole: authorRole,
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final now = DateTime.now();

    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return '$hour:$minute • Today';
    }
    return '$hour:$minute • ${local.day}/${local.month}';
  }

  @override
  Widget build(BuildContext context) {
    final loops = ref.watch(patientLoopsProvider(widget.patient.patientId));

    final openLoopsCount = loops.where((l) => l.isOpen).length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: ClinicalTheme.background,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.patient.bedNumber} — ${widget.patient.nameOrInitials} (${widget.patient.admissionNumber})'),
              Text(
                '${widget.patient.age}y / ${widget.patient.sex} • Admitted: ${widget.patient.shortAdmittingNote}',
                style: const TextStyle(fontSize: 11, color: ClinicalTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          bottom: TabBar(
            indicatorColor: ClinicalTheme.routineTeal,
            labelColor: ClinicalTheme.routineTeal,
            unselectedLabelColor: ClinicalTheme.textSecondary,
            tabs: [
              Tab(
                icon: const Icon(Icons.checklist, size: 18),
                text: 'Medical Issues ($openLoopsCount)',
              ),
              const Tab(
                icon: Icon(Icons.smart_toy_outlined, size: 18),
                text: 'Ask Oravi',
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            // Alerts Banner if patient has key alerts
            if (widget.patient.keyAlerts.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: ClinicalTheme.criticalRed.withValues(alpha: 0.12),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: ClinicalTheme.criticalRed, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Key Alerts: ${widget.patient.keyAlerts.join(", ")}',
                      style: const TextStyle(color: ClinicalTheme.criticalRed, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

            // TabBarView
            Expanded(
              child: TabBarView(
                children: [
                  // Tab 1: Loops List
                  loops.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 48, color: ClinicalTheme.successGreen),
                        const SizedBox(height: 12),
                        const Text(
                          'No Active Medical Issues',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ClinicalTheme.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'All pending issues are closed or nothing was entered.',
                          style: TextStyle(fontSize: 12, color: ClinicalTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: ClinicalTheme.routineTeal),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (ctx) => CreateLoopDialog(patientId: widget.patient.patientId),
                          ),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Raise Medical Issue'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: loops.length,
                    itemBuilder: (context, index) {
                      return _buildLoopCard(loops[index]);
                    },
                  ),

                  // Tab 2: Ask Oravi & Timeline
                  AskOraviView(
                    patient: widget.patient,
                    onAnchorMessage: (loopId, author) {
                      _anchorMessageToAuthor(loopId, author);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
        backgroundColor: ClinicalTheme.routineTeal,
        foregroundColor: Colors.white,
        onPressed: () => showDialog(
          context: context,
          builder: (ctx) => CreateLoopDialog(patientId: widget.patient.patientId),
        ),
        icon: const Icon(Icons.add_task),
        label: const Text('Raise Medical Issue'),
      ),
    ),
  );
  }

  Widget _buildLoopCard(LoopStateProjection loop) {
    final urgencyColor = ClinicalTheme.urgencyColor(loop.urgency);
    final ownerCadreColor = ClinicalTheme.cadreColor(loop.currentOwnerId);

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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: urgencyColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: urgencyColor, width: 0.8),
                  ),
                  child: Text(
                    loop.urgency.wireName.toUpperCase(),
                    style: TextStyle(color: urgencyColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  loop.loopType.wireName.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(color: ClinicalTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
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
                color: loop.isOpen ? ClinicalTheme.textPrimary : ClinicalTheme.textMuted,
                decoration: loop.isOpen ? null : TextDecoration.lineThrough,
              ),
            ),
            if (loop.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                loop.description,
                style: const TextStyle(fontSize: 12, color: ClinicalTheme.textSecondary),
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
                    const Icon(Icons.emergency, color: ClinicalTheme.criticalRed, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Escalated to ${loop.activeEscalation!.targetRole}: "${loop.activeEscalation!.reason}"',
                        style: const TextStyle(color: ClinicalTheme.criticalRed, fontSize: 11, fontWeight: FontWeight.bold),
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
                  style: const TextStyle(fontSize: 11, color: ClinicalTheme.textMuted),
                ),
                Text(
                  loop.currentOwnerId,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ownerCadreColor),
                ),
                Text(
                  ' (${loop.currentOwnerRole})',
                  style: const TextStyle(fontSize: 11, color: ClinicalTheme.textMuted),
                ),
                if (loop.reopenCount > 0) ...[
                  const Spacer(),
                  Text(
                    'Reopened ${loop.reopenCount}x',
                    style: const TextStyle(fontSize: 11, color: ClinicalTheme.urgentAmber, fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
            const Divider(color: ClinicalTheme.border, height: 20),

            // Append-only Thread Messages with WhatsApp-style timestamps & Action Buttons (FR-54, FR-55)
            if (loop.messages.isNotEmpty) ...[
              const Text(
                'Thread History (Append-Only):',
                style: TextStyle(color: ClinicalTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              ...loop.messages.map((msg) {
                final authorColor = ClinicalTheme.cadreColor(msg.authorId);
                final timeFormatted = _formatTimestamp(msg.createdAt);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: msg.isCallLog
                          ? ClinicalTheme.routineTeal.withValues(alpha: 0.12)
                          : ClinicalTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: msg.isCallLog
                          ? Border.all(color: ClinicalTheme.routineTeal, width: 0.8)
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Message Header: Color-coded Author + WhatsApp timestamp + Quick Actions
                        Row(
                          children: [
                            Text(
                              msg.authorId,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: authorColor,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              timeFormatted,
                              style: const TextStyle(fontSize: 10, color: ClinicalTheme.textMuted),
                            ),
                            const Spacer(),

                            // One-tap Message button (anchors @reply in thread)
                            InkWell(
                              onTap: () => _anchorMessageToAuthor(loop.loopId, msg.authorId),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Row(
                                  children: [
                                    Icon(Icons.reply, size: 13, color: ClinicalTheme.routineTeal),
                                    SizedBox(width: 2),
                                    Text('Reply', style: TextStyle(fontSize: 10, color: ClinicalTheme.routineTeal)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),

                            // One-tap Call button (opens post-call outcome prompt - FR-54)
                            InkWell(
                              onTap: () => _openCallDialog(loop, msg.authorId, msg.authorRole),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Row(
                                  children: [
                                    Icon(Icons.call, size: 13, color: ClinicalTheme.successGreen),
                                    SizedBox(width: 2),
                                    Text('Call', style: TextStyle(fontSize: 10, color: ClinicalTheme.successGreen)),
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
                            color: msg.isCallLog ? ClinicalTheme.textPrimary : ClinicalTheme.textPrimary,
                            fontWeight: msg.isCallLog ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],

            // Action Row: Close, Confirm, Reopen, Reply
            if (loop.isOpen) ...[
              if (loop.state == LoopState.closedAwaitingConfirmation)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ClinicalTheme.urgentAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: ClinicalTheme.urgentAmber),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Closed awaiting senior/opener confirmation.',
                          style: TextStyle(fontSize: 11, color: ClinicalTheme.urgentAmber, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ClinicalTheme.urgentAmber,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                        onPressed: () => ref
                            .read(wardControllerProvider.notifier)
                            .confirmCriticalClosure(patientId: loop.patientId, loopId: loop.loopId),
                        child: const Text('Confirm', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),

              // Reply Input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _getReplyController(loop.loopId),
                      style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Add note or update...',
                        hintStyle: const TextStyle(color: ClinicalTheme.textMuted, fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        filled: true,
                        fillColor: ClinicalTheme.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: ClinicalTheme.border),
                        ),
                      ),
                      onSubmitted: (_) => _sendReply(loop.loopId),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.send, color: ClinicalTheme.routineTeal, size: 20),
                    onPressed: () => _sendReply(loop.loopId),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ClinicalTheme.successGreen,
                      side: const BorderSide(color: ClinicalTheme.successGreen),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (ctx) => CloseLoopDialog(loop: loop),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Close', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ] else ...[
              // Closed State Details & Reopen Button
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Closed by ${loop.closedByUserId}: [${loop.closureReason?.wireName ?? "closed"}] ${loop.closureNote ?? ""}',
                      style: const TextStyle(fontSize: 11, color: ClinicalTheme.textMuted, fontStyle: FontStyle.italic),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: ClinicalTheme.urgentAmber),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (ctx) => ReopenLoopDialog(loop: loop),
                    ),
                    icon: const Icon(Icons.replay, size: 16),
                    label: const Text('Reopen', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
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
      child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

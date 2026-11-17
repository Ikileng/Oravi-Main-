import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database_provider.dart';
import '../../domain/projections/projections.dart';
import '../providers/auth_providers.dart';
import '../providers/ward_providers.dart';
import '../providers/whiteboard_providers.dart';
import '../patient_detail_screen.dart';
import '../call_screen.dart';
import '../theme/clinical_theme.dart';
import '../widgets/log_call_outcome_dialog.dart';
import 'staff_communications_screen.dart';

final personalInboxProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final staff = ref.watch(authenticatedStaffProvider);
  final token = ref.watch(authAccessTokenProvider);
  if (token == null ||
      staff == null ||
      (!staff.isClinical && !staff.isSupport)) {
    return {'items': <dynamic>[], 'unread_count': 0};
  }
  var timer = Timer(const Duration(seconds: 5), ref.invalidateSelf);
  ref.onCancel(() => timer.cancel());
  ref.onResume(() {
    timer = Timer(const Duration(seconds: 5), ref.invalidateSelf);
  });
  ref.onDispose(() => timer.cancel());
  final result = await ref
      .read(wardBoardServiceProvider)
      .communicationRequest('GET', '/inbox');
  return Map<String, dynamic>.from(result as Map);
});

Future<void> markInboxRead(WidgetRef ref, List<String> ids) async {
  if (ids.isEmpty) return;
  for (var start = 0; start < ids.length; start += 500) {
    await ref
        .read(wardBoardServiceProvider)
        .communicationRequest(
          'POST',
          '/inbox/read',
          payload: {'ids': ids.skip(start).take(500).toList()},
        );
  }
  ref.invalidate(personalInboxProvider);
  ref.invalidate(staffInboxProvider);
}

Future<void> markLoadedIssueRead(
  WidgetRef ref,
  String patientId,
  String loopId,
) async {
  final eventIds = ref
      .read(localWardRepositoryProvider)
      .getAllEvents()
      .where((e) => e.patientId == patientId && e.loopId == loopId)
      .map((e) => e.eventId)
      .toSet();
  final result = await ref
      .read(wardBoardServiceProvider)
      .communicationRequest('GET', '/inbox');
  final items = (result as Map)['items'] as List;
  await markInboxRead(
    ref,
    items
        .where((i) => i['kind'] == 'issue' && eventIds.contains(i['event_id']))
        .map((i) => i['id'] as String)
        .toList(),
  );
}

class InboxBadge extends ConsumerWidget {
  const InboxBadge({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(personalInboxProvider);
    return Badge(
      label: Text(
        inbox.hasError ? '!' : '${inbox.asData?.value['unread_count'] ?? '…'}',
      ),
      child: const Icon(Icons.chat_bubble_outline),
    );
  }
}

class ReceivedInbox extends ConsumerWidget {
  const ReceivedInbox({super.key});

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> item,
  ) async {
    try {
      final api = ref.read(wardBoardServiceProvider);
      if (item['kind'] == 'issue') {
        final response = await api.getMedicalIssueThread(
          patientId: item['patient_id'],
          loopId: item['loop_id'],
        );
        final events = (response['events'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        await ref.read(localDatabaseProvider).insertRemoteEvents(events);
        await ref.read(localWardRepositoryProvider).reloadFromDatabase();
        ref.read(wardControllerProvider.notifier).refresh();
        final loop = ref
            .read(localWardRepositoryProvider)
            .getLoopsForPatient(item['patient_id'])
            .firstWhere((l) => l.loopId == item['loop_id']);
        final eventIds = events.map((e) => e['event_id']).toSet();
        final visibleItems =
            ref.read(personalInboxProvider).asData?.value['items'] as List? ??
            [];
        await markInboxRead(
          ref,
          visibleItems
              .where(
                (i) =>
                    i['kind'] == 'issue' &&
                    i['patient_id'] == item['patient_id'] &&
                    i['loop_id'] == item['loop_id'] &&
                    eventIds.contains(i['event_id']),
              )
              .map((i) => i['id'] as String)
              .toList(),
        );
        if (!context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PatientDetailScreen(
              patient: PatientStateProjection(
                patientId: item['patient_id'],
                wardId: response['ward_id'] ?? '',
                bedNumber: 'Medical Issue',
                patientInitials: '',
                age: 0,
                sex: '',
                shortAdmittingNote: '',
                admittedAt: loop.createdAt,
                updatedAt: loop.updatedAt,
              ),
              issueOnlyLoopIds: {item['loop_id'] as String},
              initialExpandedLoopId: item['loop_id'],
            ),
          ),
        );
      } else if (item['kind'] == 'message') {
        if (!context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                StaffChatScreen(staffId: item['staff_id'], name: item['title']),
          ),
        );
      } else if (item['status'] == 'ringing') {
        final answer = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Call from ${item['title']}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Answer'),
              ),
            ],
          ),
        );
        if (answer == null) return;
        if (!answer) {
          await api.declineCall(item['call_id']);
        } else {
          final session = await api.acceptCall(item['call_id']);
          if (!context.mounted) return;
          final duration = await Navigator.push<int>(
            context,
            MaterialPageRoute<int>(
              builder: (_) => CallScreen(session: session, api: api),
            ),
          );
          if (duration != null && session.patientId.isNotEmpty) {
            final thread = await api.getMedicalIssueThread(
              patientId: session.patientId,
              loopId: session.loopId,
            );
            await ref
                .read(localDatabaseProvider)
                .insertRemoteEvents(
                  (thread['events'] as List)
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList(),
                );
            await ref.read(localWardRepositoryProvider).reloadFromDatabase();
            ref.read(wardControllerProvider.notifier).refresh();
            final loop = ref
                .read(localWardRepositoryProvider)
                .getLoopsForPatient(session.patientId)
                .firstWhere((l) => l.loopId == session.loopId);
            if (!context.mounted) return;
            await showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => LogCallOutcomeDialog(
                loop: loop,
                recipientId: session.callerId,
                recipientName: session.callerName,
                recipientRole: session.callerRole,
                durationSeconds: duration,
                callId: session.callId,
              ),
            );
          }
        }
        ref.invalidate(personalInboxProvider);
      } else {
        await markInboxRead(ref, [item['id'] as String]);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This update could not be opened. Check your connection and current access.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(personalInboxProvider)
      .when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: LinearProgressIndicator(),
        ),
        error: (_, _) => _InboxStateCard(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load received activity',
          message: 'Check your connection and pull to refresh.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(personalInboxProvider),
        ),
        data: (inbox) {
          final items = (inbox['items'] as List).cast<Map<String, dynamic>>()
            ..sort((left, right) {
              final unreadOrder = (right['unread'] == true ? 1 : 0).compareTo(
                left['unread'] == true ? 1 : 0,
              );
              if (unreadOrder != 0) return unreadOrder;
              return (right['created_at'] as String? ?? '').compareTo(
                left['created_at'] as String? ?? '',
              );
            });
          final unread = inbox['unread_count'] as int? ?? 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InboxSectionHeader(
                title: 'Received',
                countLabel: unread == 0 ? null : '$unread unread',
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const _InboxStateCard(
                  icon: Icons.mark_chat_read_outlined,
                  title: 'No received messages or calls yet',
                  message: 'New clinical updates will appear here.',
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: ClinicalTheme.surface,
                    borderRadius: BorderRadius.circular(
                      ClinicalTheme.radiusLarge,
                    ),
                    border: Border.all(color: ClinicalTheme.border),
                  ),
                  child: Column(
                    children: [
                      for (var index = 0; index < items.length; index++) ...[
                        _InboxActivityTile(
                          item: items[index],
                          onTap: () => _open(context, ref, items[index]),
                        ),
                        if (index != items.length - 1)
                          const Divider(height: 1, indent: 68),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      );
}

class _InboxSectionHeader extends StatelessWidget {
  const _InboxSectionHeader({required this.title, this.countLabel});
  final String title;
  final String? countLabel;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: ClinicalTheme.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (countLabel != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: ClinicalTheme.clinicalBlue.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            countLabel!,
            style: const TextStyle(
              color: ClinicalTheme.clinicalBlue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
    ],
  );
}

class _InboxActivityTile extends StatelessWidget {
  const _InboxActivityTile({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = item['kind'] as String? ?? 'message';
    final unread = item['unread'] == true;
    final urgent = item['urgency'] == 'urgent' ||
        item['urgency'] == 'critical' ||
        (item['title'] as String? ?? '').toLowerCase().contains('medical issue');
    final visual = switch (kind) {
      'call' => (Icons.call_received_rounded, ClinicalTheme.successGreen),
      'issue' => (Icons.monitor_heart_outlined, ClinicalTheme.urgentAmber),
      _ => (Icons.chat_bubble_outline_rounded, ClinicalTheme.clinicalBlue),
    };
    final contextLabel = [
      item['patient_label'],
      item['bed_number'] == null ? null : 'Bed ${item['bed_number']}',
    ].whereType<Object>().map((value) => '$value').join(' · ');

    return Semantics(
      button: true,
      label: '${unread ? 'Unread ' : ''}${item['title'] ?? 'Clinical update'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ClinicalTheme.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: visual.$2.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(visual.$1, color: visual.$2, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['title'] as String? ?? 'Clinical update',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ClinicalTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _relativeInboxTime(item['created_at']),
                          style: const TextStyle(
                            color: ClinicalTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    if (contextLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            size: 13,
                            color: ClinicalTheme.clinicalBlue,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              contextLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ClinicalTheme.clinicalBlue,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      item['body'] as String? ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ClinicalTheme.textSecondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                    if (urgent) ...[
                      const SizedBox(height: 7),
                      const _UrgencyLabel(),
                    ],
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: const BoxDecoration(
                    color: ClinicalTheme.clinicalBlue,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UrgencyLabel extends StatelessWidget {
  const _UrgencyLabel();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: ClinicalTheme.urgentAmber.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: ClinicalTheme.urgentAmber.withValues(alpha: 0.5),
      ),
    ),
    child: const Text(
      'NEEDS ATTENTION',
      style: TextStyle(
        color: ClinicalTheme.urgentAmber,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    ),
  );
}

class _InboxStateCard extends StatelessWidget {
  const _InboxStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: ClinicalTheme.surfaceSoft,
      borderRadius: BorderRadius.circular(ClinicalTheme.radiusLarge),
      border: Border.all(color: ClinicalTheme.border),
    ),
    child: Column(
      children: [
        Icon(icon, color: ClinicalTheme.textSecondary, size: 28),
        const SizedBox(height: 9),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ClinicalTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        if (onAction != null) ...[
          const SizedBox(height: 10),
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

String _relativeInboxTime(Object? raw) {
  final parsed = raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
  if (parsed == null) return '';
  final difference = DateTime.now().difference(parsed);
  if (difference.inMinutes < 1) return 'Now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m';
  if (difference.inHours < 24) return '${difference.inHours}h';
  if (difference.inDays < 7) return '${difference.inDays}d';
  return '${parsed.day}/${parsed.month}';
}

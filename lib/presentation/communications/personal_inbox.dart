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
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => const ListTile(
          title: Text('Could not load received activity. Please retry.'),
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Received (${inbox['unread_count']} unread)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (items.isEmpty)
                const ListTile(
                  title: Text('No received messages or calls yet'),
                ),
              for (final item in items)
                ListTile(
                  leading: Icon(
                    item['kind'] == 'call'
                        ? Icons.call_received
                        : item['kind'] == 'issue'
                        ? Icons.medical_information_outlined
                        : Icons.chat_bubble_outline,
                  ),
                  title: Text(
                    item['title'],
                    style: TextStyle(
                      fontWeight: item['unread'] == true
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    item['body'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: item['unread'] == true
                      ? const Icon(Icons.circle, size: 9, color: Colors.blue)
                      : null,
                  onTap: () => _open(context, ref, item),
                ),
              const Divider(),
            ],
          );
        },
      );
}

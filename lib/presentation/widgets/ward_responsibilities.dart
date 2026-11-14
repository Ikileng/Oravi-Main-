import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_providers.dart';
import '../providers/ward_context_providers.dart';
import '../providers/whiteboard_providers.dart';
import '../communications/staff_communications_screen.dart';

final wardResponsibilitiesProvider = FutureProvider<List<dynamic>>((ref) async {
  final ward = ref.watch(selectedWardProvider).wardId;
  final shift = ref.watch(selectedShiftTypeProvider);
  final staff = ref.watch(authenticatedStaffProvider);
  ref.watch(authAccessTokenProvider);
  if (ward.isEmpty || staff?.isClinical != true) return [];
  return await ref
          .read(wardBoardServiceProvider)
          .communicationRequest(
            'GET',
            '/wards/${Uri.encodeComponent(ward)}/responsibilities?duty_date=${activeWardShiftDate()}&shift_type=$shift',
          )
      as List;
});

class WardResponsibilities extends ConsumerWidget {
  const WardResponsibilities({super.key});
  Future<void> _assign(BuildContext context, WidgetRef ref, Map duty) async {
    final ward = ref.read(selectedWardProvider).wardId;
    final shift = ref.read(selectedShiftTypeProvider);
    final day = activeWardShiftDate();
    final api = ref.read(wardBoardServiceProvider);
    try {
      final candidates =
          await api.communicationRequest(
                'GET',
                '/wards/${Uri.encodeComponent(ward)}/responsibility-candidates?responsibility=${duty['key']}',
              )
              as List;
      if (!context.mounted) return;
      String search = '';
      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text('Assign ${duty['label']}'),
            content: SizedBox(
              width: 400,
              height: 360,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search name or staff ID',
                    ),
                    onChanged: (value) =>
                        update(() => search = value.toLowerCase()),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final person in candidates.where(
                          (p) => '${p['name']} ${p['staff_id']}'
                              .toLowerCase()
                              .contains(search),
                        ))
                          ListTile(
                            title: Text(person['name'] as String),
                            subtitle: Text(person['staff_id'] as String),
                            onTap: () => Navigator.pop(
                              dialogContext,
                              person['staff_id'] as String,
                            ),
                          ),
                        if (candidates.isEmpty)
                          const ListTile(
                            title: Text(
                              'No eligible users. Ask Admin to provision an account.',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              if (duty['staff'] != null)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, ''),
                  child: const Text('Unassign'),
                ),
            ],
          ),
        ),
      );
      if (selected == null) return;
      await api.communicationRequest(
        'PUT',
        '/wards/${Uri.encodeComponent(ward)}/responsibilities/${duty['key']}?duty_date=$day&shift_type=$shift',
        payload: {'staff_id': selected},
      );
      ref.invalidate(wardResponsibilitiesProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not assign responsibility: $error')),
        );
      }
    }
  }

  Future<void> _contact(BuildContext context, WidgetRef ref, Map person) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(person['name'] as String)),
            ListTile(
              leading: const Icon(Icons.call),
              title: const Text('Call'),
              onTap: () => Navigator.pop(sheetContext, 'call'),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Message'),
              onTap: () => Navigator.pop(sheetContext, 'message'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'call') {
      await startStaffCall(context, ref, person['staff_id'] as String);
    } else if (action == 'message') {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => StaffChatScreen(
            staffId: person['staff_id'] as String,
            name: person['name'] as String,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(authenticatedStaffProvider);
    if (staff?.isClinical != true) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ward Responsibilities',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh responsibilities',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(wardResponsibilitiesProvider),
                ),
              ],
            ),
            Text(
              'For the selected ${ref.watch(selectedShiftTypeProvider)} shift',
            ),
            ref
                .watch(wardResponsibilitiesProvider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) =>
                      Text('Could not load responsibilities: $error'),
                  data: (duties) => Column(
                    children: [
                      for (final duty in duties)
                        ListTile(
                          title: Text(duty['label'] as String),
                          subtitle: Text(
                            duty['staff']?['name'] as String? ?? 'Not assigned',
                          ),
                          onTap:
                              duty['staff'] == null ||
                                  duty['staff']['staff_id'] == staff!.staffId
                              ? null
                              : () => _contact(
                                  context,
                                  ref,
                                  duty['staff'] as Map,
                                ),
                          trailing: staff!.isChargeNurse
                              ? IconButton(
                                  tooltip: 'Assign ${duty['label']}',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () =>
                                      _assign(context, ref, duty as Map),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/hospital_ward.dart';
import '../../domain/models/staff_profile.dart';
import '../../domain/models/whiteboard_models.dart';
import '../providers/auth_providers.dart';
import '../providers/whiteboard_providers.dart';
import '../providers/ward_context_providers.dart';

final wardTransfersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final staff = ref.watch(authenticatedStaffProvider);
      ref.watch(authAccessTokenProvider);
      ref.watch(selectedWardProvider);
      if (staff?.isClinical != true) return [];
      final result = await ref
          .read(wardBoardServiceProvider)
          .communicationRequest('GET', '/ward-transfers');
      return (result as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    });

Future<bool> confirmWardAction(
  BuildContext context,
  String title,
  String message,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<void> requestWardTransfer(
  BuildContext context,
  WidgetRef ref,
  String nurseId,
  String source,
  String target,
  String shift,
) async {
  if (!await confirmWardAction(
    context,
    'Request ward transfer?',
    'The nurse will be notified. They remain in their current ward until their replacement accepts the patient handoff.',
    'Request transfer',
  )) {
    return;
  }
  await ref
      .read(wardBoardServiceProvider)
      .communicationRequest(
        'POST',
        '/ward-transfers',
        payload: {
          'nurse_id': nurseId,
          'source_ward': source,
          'target_ward': target,
          'date': activeWardShiftDate(),
          'shift_type': shift,
        },
      );
  ref.invalidate(wardTransfersProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transfer requested. Awaiting patient handoff.'),
      ),
    );
  }
}

Future<void> showNurseAssignmentEditor(
  BuildContext context,
  WidgetRef ref,
  WhiteboardBedAssignment bed,
  List<StaffProfile> nurses,
  bool isDay,
) async {
  final ward = ref.read(selectedWardProvider);
  final shift = isDay ? 'day' : 'night';
  final current = isDay ? bed.dayShiftNurseId : bed.nightShiftNurseId;
  final opposite = isDay ? bed.nightShiftNurseId : bed.dayShiftNurseId;
  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _NurseChoices(
      bed: bed.bedNumber,
      shift: shift,
      current: current,
      canMove: opposite == null || opposite.isEmpty,
      nurses: nurses,
    ),
  );
  if (choice == null || !context.mounted) return;
  try {
    final api = ref.read(wardBoardServiceProvider);
    if (choice == '!transfer') {
      final wards = await api.getWards();
      if (!context.mounted) return;
      final target = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Transfer to ward'),
          children: [
            for (final w in wards.where((w) => w.wardId != ward.wardId))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, w.wardId),
                child: Text(w.name),
              ),
          ],
        ),
      );
      if (target != null && context.mounted) {
        await requestWardTransfer(
          context,
          ref,
          current!,
          ward.wardId,
          target,
          shift,
        );
      }
      return;
    }
    final moving = choice == '!move';
    final selected = choice == '!clear'
        ? null
        : moving
        ? current
        : choice;
    final targetShift = moving ? (isDay ? 'night' : 'day') : shift;
    bool confirmed = false;
    if (moving || selected == null) {
      if (!await confirmWardAction(
        context,
        moving ? 'Move to $targetShift?' : 'Remove assignment?',
        moving
            ? 'Move this bed’s nurse to $targetShift. Other bed assignments stay unchanged; confirm that the nurse may cover both shifts if other assignments remain.'
            : 'Remove the $shift nurse from bed ${bed.bedNumber}? This corrects the board; it does not complete a patient handoff.',
        moving ? 'Confirm move' : 'Remove',
      )) {
        return;
      }
      confirmed = moving;
    }
    if (selected != null && !moving) {
      final result = await api.communicationRequest(
        'GET',
        '/nurses/${Uri.encodeComponent(selected)}/assignments?date=${activeWardShiftDate()}',
      );
      final existing = (result as List).cast<Map>();
      final conflict = existing
          .where((r) => r['shift_type'] == shift && r['ward_id'] != ward.wardId)
          .toList();
      if (!context.mounted) return;
      if (conflict.isNotEmpty) {
        final other = conflict.first;
        final proceed = await confirmWardAction(
          context,
          'Already in ${other['ward_name']}',
          'This nurse is assigned to ${other['ward_name']} for $shift. A transfer and accepted patient handoff are required before they can join ${ward.name}.',
          'Continue to transfer',
        );
        if (proceed && context.mounted) {
          await requestWardTransfer(
            context,
            ref,
            selected,
            other['ward_id'] as String,
            ward.wardId,
            shift,
          );
        }
        return;
      }
      if (existing.any((r) => r['shift_type'] != shift)) {
        confirmed = await confirmWardAction(
          context,
          'Assign both shifts?',
          'This nurse already has ${isDay ? 'night' : 'day'} assignments. Also assign them to $shift on ${activeWardShiftDate()}?',
          'Confirm both shifts',
        );
        if (!confirmed) return;
      }
    }
    await api.communicationRequest(
      'PUT',
      '/wards/${Uri.encodeComponent(ward.wardId)}/beds/${Uri.encodeComponent(bed.bedNumber)}/nurse',
      payload: {
        'date': activeWardShiftDate(),
        'shift_type': targetShift,
        'nurse_id': selected,
        'expected_nurse_id': moving ? opposite : current,
        'move_from_other_shift': moving,
        'confirm_both_shifts': confirmed,
      },
    );
    ref.invalidate(wardBoardProvider);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update assignment: $error')),
      );
    }
  }
}

class _NurseChoices extends StatefulWidget {
  final String bed, shift;
  final String? current;
  final bool canMove;
  final List<StaffProfile> nurses;
  const _NurseChoices({
    required this.bed,
    required this.shift,
    required this.current,
    required this.canMove,
    required this.nurses,
  });
  @override
  State<_NurseChoices> createState() => _NurseChoicesState();
}

class _NurseChoicesState extends State<_NurseChoices> {
  String query = '';
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: 400,
        child: Column(
          children: [
            Text(
              'Bed ${widget.bed} · ${widget.shift} nurse',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (widget.current?.isNotEmpty == true)
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, '!clear'),
                    child: const Text('Remove assignment'),
                  ),
                  if (widget.canMove)
                    TextButton(
                      onPressed: () => Navigator.pop(context, '!move'),
                      child: Text(
                        'Move to ${widget.shift == 'day' ? 'night' : 'day'}',
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, '!transfer'),
                    child: const Text('Request ward transfer'),
                  ),
                ],
              ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search nurse name or staff ID',
              ),
              onChanged: (v) => setState(() => query = v.toLowerCase()),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final n in widget.nurses.where(
                    (n) =>
                        '${n.name} ${n.staffId}'.toLowerCase().contains(query),
                  ))
                    ListTile(
                      title: Text(n.name),
                      subtitle: Text(n.staffId),
                      trailing: n.staffId == widget.current
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, n.staffId),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class WardTransferNotice extends ConsumerStatefulWidget {
  const WardTransferNotice({super.key});
  @override
  ConsumerState<WardTransferNotice> createState() => _WardTransferNoticeState();
}

class _WardTransferNoticeState extends ConsumerState<WardTransferNotice> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      ref.invalidate(wardTransfersProvider);
      ref.invalidate(wardBoardProvider);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transfers = ref.watch(wardTransfersProvider).asData?.value ?? [];
    final pending = transfers
        .where((t) => t['status'] == 'pending' || t['status'] == 'handoff')
        .length;
    return TextButton.icon(
      icon: const Icon(Icons.compare_arrows),
      label: Text(
        pending > 0
            ? 'Transfers · $pending awaiting handoff'
            : 'Transfers & handoffs',
      ),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const WardTransferScreen()),
      ),
    );
  }
}

class WardTransferScreen extends ConsumerStatefulWidget {
  const WardTransferScreen({super.key});
  @override
  ConsumerState<WardTransferScreen> createState() => _WardTransferScreenState();
}

class _WardTransferScreenState extends ConsumerState<WardTransferScreen> {
  bool busy = false;
  Future<void> action(Future<void> Function() work) async {
    setState(() => busy = true);
    try {
      await work();
      ref.invalidate(wardTransfersProvider);
      ref.invalidate(wardBoardProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review(Map<String, dynamic> t, bool outgoing) async {
    final api = ref.read(wardBoardServiceProvider);
    final detail = Map<String, dynamic>.from(
      await api.communicationRequest(
            'GET',
            '/ward-transfers/${t['id']}/handoff',
          )
          as Map,
    );
    final candidates = outgoing
        ? (await api.communicationRequest(
                'GET',
                '/ward-transfers/${t['id']}/replacements',
              )
              as List)
        : <dynamic>[];
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _TransferHandoffDialog(
        transfer: t,
        detail: detail,
        candidates: candidates,
        outgoing: outgoing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(authenticatedStaffProvider);
    if (staff?.isClinical != true) {
      return const Scaffold(
        body: Center(child: Text('Clinician sign-in required.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers & handoffs'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(wardTransfersProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ref
          .watch(wardTransfersProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Could not load transfers: $e')),
            data: (items) => items.isEmpty
                ? const Center(child: Text('No ward transfers.'))
                : ListView(
                    children: [
                      for (final t in items)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${t['nurse_name']}: ${t['source_name']} → ${t['target_name']}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  '${t['date']} · ${t['shift_type']} · ${t['status']}',
                                ),
                                if (t['status'] == 'pending' ||
                                    t['status'] == 'handoff')
                                  const Text(
                                    'Source assignments stay in place until the replacement accepts all patients and open Medical Issues.',
                                  ),
                                Wrap(
                                  children: [
                                    if (staff!.staffId == t['nurse_id'] &&
                                        [
                                          'pending',
                                          'handoff',
                                        ].contains(t['status']))
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () =>
                                                  action(() => review(t, true)),
                                        child: const Text(
                                          'Prepare patient handoff',
                                        ),
                                      ),
                                    if (staff.staffId == t['replacement_id'] &&
                                        t['status'] == 'handoff')
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => action(
                                                () => review(t, false),
                                              ),
                                        child: const Text(
                                          'Review and accept handoff',
                                        ),
                                      ),
                                    if (staff.isChargeNurse &&
                                        [
                                          'pending',
                                          'handoff',
                                        ].contains(t['status']))
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => action(() async {
                                                if (await confirmWardAction(
                                                  context,
                                                  'Cancel transfer?',
                                                  'The nurse and their patients will stay in the source ward.',
                                                  'Cancel transfer',
                                                )) {
                                                  await ref
                                                      .read(
                                                        wardBoardServiceProvider,
                                                      )
                                                      .communicationRequest(
                                                        'POST',
                                                        '/ward-transfers/${t['id']}/cancel',
                                                      );
                                                }
                                              }),
                                        child: const Text('Cancel transfer'),
                                      ),
                                    if (staff.staffId == t['nurse_id'] &&
                                        t['status'] == 'completed')
                                      TextButton(
                                        onPressed: () {
                                          ref
                                              .read(
                                                selectedShiftTypeProvider
                                                    .notifier,
                                              )
                                              .select(
                                                t['shift_type'] as String,
                                              );
                                          ref
                                              .read(
                                                selectedWardProvider.notifier,
                                              )
                                              .selectWard(
                                                HospitalWard(
                                                  wardId:
                                                      t['target_ward']
                                                          as String,
                                                  name:
                                                      t['target_name']
                                                          as String,
                                                  bedCount: 0,
                                                  bedNumbers: const [],
                                                  department: '',
                                                  description: '',
                                                ),
                                              );
                                          Navigator.pop(context);
                                        },
                                        child: const Text(
                                          'Open destination ward',
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
    );
  }
}

class _TransferHandoffDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> transfer, detail;
  final List<dynamic> candidates;
  final bool outgoing;
  const _TransferHandoffDialog({
    required this.transfer,
    required this.detail,
    required this.candidates,
    required this.outgoing,
  });
  @override
  ConsumerState<_TransferHandoffDialog> createState() =>
      _TransferHandoffDialogState();
}

class _TransferHandoffDialogState
    extends ConsumerState<_TransferHandoffDialog> {
  final notes = TextEditingController();
  String? replacement, error;
  bool accepted = false, busy = false;
  @override
  void initState() {
    super.initState();
    notes.text = widget.detail['notes'] as String? ?? '';
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> save(String action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(wardBoardServiceProvider)
          .communicationRequest(
            'POST',
            '/ward-transfers/${widget.transfer['id']}/$action',
            payload: action == 'handoff'
                ? {'replacement_id': replacement, 'notes': notes.text}
                : action == 'accept'
                ? {'revision': widget.detail['revision']}
                : null,
          );
      ref.invalidate(wardTransfersProvider);
      ref.invalidate(wardBoardProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        widget.outgoing
            ? 'Prepare patient handoff'
            : 'Accept patient responsibility',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final b in widget.detail['beds'] as List) ...[
                Text(
                  'Bed ${b['bed_number']} · ${b['patient_initials']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if ((b['issues'] as List).isEmpty)
                  const Text('No open Medical Issues.'),
                for (final issue in b['issues'] as List)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                    child: Text(
                      '${issue['type']} · ${issue['client_created_at']}\n${(issue['payload'] as Map).entries.where((e) => !e.key.toString().endsWith('_id') && !e.key.toString().endsWith('_ids')).map((e) => '${e.key.toString().replaceAll('_', ' ')}: ${e.value}').join('\n')}',
                    ),
                  ),
                const Divider(),
              ],
              if ((widget.detail['beds'] as List).isEmpty)
                const Text(
                  'No patients currently assigned. The replacement must still acknowledge this handoff before transfer.',
                ),
              if (widget.outgoing) ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Designated replacement nurse',
                  ),
                  items: [
                    for (final c in widget.candidates)
                      DropdownMenuItem(
                        value: c['staff_id'] as String,
                        child: Text('${c['name']} (${c['staff_id']})'),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => replacement = v),
                ),
                if (widget.candidates.isEmpty)
                  const Text(
                    'The charge nurse must assign the replacement to this ward and shift first.',
                  ),
                TextField(
                  controller: notes,
                  enabled: !busy,
                  maxLines: 3,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: 'Handoff notes'),
                ),
              ] else ...[
                Text('Handoff notes: ${widget.detail['notes']}'),
                CheckboxListTile(
                  value: accepted,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => accepted = v ?? false),
                  title: const Text(
                    'I have reviewed the handoff and accept responsibility for every listed patient and open Medical Issue.',
                  ),
                ),
              ],
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (!widget.outgoing)
          TextButton(
            onPressed: busy ? null : () => save('decline'),
            child: const Text('Decline handoff'),
          ),
        FilledButton(
          onPressed: busy || (widget.outgoing ? replacement == null : !accepted)
              ? null
              : () => save(widget.outgoing ? 'handoff' : 'accept'),
          child: Text(
            widget.outgoing
                ? 'Send for acceptance'
                : 'Accept and complete transfer',
          ),
        ),
      ],
    ),
  );
}

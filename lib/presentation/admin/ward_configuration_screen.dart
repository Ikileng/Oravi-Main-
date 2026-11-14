import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/hospital_ward.dart';
import '../providers/auth_providers.dart';

final adminWardsProvider = FutureProvider<List<HospitalWard>>((ref) {
  final token = ref.watch(authAccessTokenProvider);
  if (token == null ||
      ref.watch(authenticatedStaffProvider)?.role != 'dev_admin') {
    return [];
  }
  return ref.watch(staffAuthServiceProvider).getConfiguredWards(token);
});

class WardConfigurationScreen extends ConsumerWidget {
  const WardConfigurationScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    HospitalWard? ward,
  ) async {
    final name = TextEditingController(text: ward?.name);
    final department = TextEditingController(text: ward?.department);
    final description = TextEditingController(text: ward?.description);
    final beds = TextEditingController(text: ward?.bedNumbers.join(', '));
    final form = GlobalKey<FormState>();
    bool saving = false;
    String? error;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(ward == null ? 'Create ward' : 'Edit ${ward.name}'),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Form(
                    key: form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: name,
                          decoration: const InputDecoration(
                            labelText: 'Ward name',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter a ward name'
                              : null,
                        ),
                        TextFormField(
                          controller: department,
                          decoration: const InputDecoration(
                            labelText: 'Department',
                          ),
                        ),
                        TextFormField(
                          controller: description,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                          ),
                        ),
                        TextFormField(
                          controller: beds,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Bed labels',
                            helperText:
                                'Separate labels with commas or new lines.\nLeave empty for a ward without beds.',
                          ),
                          validator: (value) {
                            final labels = _labels(value ?? '');
                            return labels
                                        .map((e) => e.toLowerCase())
                                        .toSet()
                                        .length !=
                                    labels.length
                                ? 'Each bed label must be unique'
                                : null;
                          },
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!form.currentState!.validate()) return;
                          final labels = _labels(beds.text);
                          final removed =
                              ward?.bedNumbers
                                  .where((bed) => !labels.contains(bed))
                                  .toList() ??
                              <String>[];
                          if (removed.isNotEmpty) {
                            final confirmed = await showDialog<bool>(
                              context: dialogContext,
                              builder: (confirmContext) => AlertDialog(
                                title: const Text('Remove bed labels?'),
                                content: Text(
                                  'Remove ${removed.join(', ')} from this ward? Historical records will be retained. Beds referenced by current or upcoming allocations cannot be removed.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(confirmContext, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(confirmContext, true),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                          }
                          setState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await ref
                                .read(staffAuthServiceProvider)
                                .saveConfiguredWard(
                                  ref.read(authAccessTokenProvider)!,
                                  HospitalWard(
                                    wardId: ward?.wardId ?? '',
                                    name: name.text.trim(),
                                    bedCount: labels.length,
                                    bedNumbers: labels,
                                    department: department.text.trim(),
                                    description: description.text.trim(),
                                  ),
                                  expectedBeds: ward?.bedNumbers,
                                );
                            ref.invalidate(adminWardsProvider);
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (exception) {
                            if (dialogContext.mounted) {
                              setState(() {
                                error = exception.toString();
                                saving = false;
                              });
                            }
                          }
                        },
                  child: Text(saving ? 'Saving…' : 'Save'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      // Wait until the dialog's closing animation releases its text fields.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      name.dispose();
      department.dispose();
      description.dispose();
      beds.dispose();
    }
  }

  static List<String> _labels(String text) => text
      .split(RegExp(r'[,\n]'))
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authenticatedStaffProvider)?.role != 'dev_admin') {
      return const Scaffold(
        body: Center(child: Text('Dev Admin sign-in required.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configure wards'),
        actions: [
          IconButton(
            tooltip: 'Refresh wards',
            onPressed: () => ref.invalidate(adminWardsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ref
          .watch(adminWardsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load wards: $error'),
                  TextButton(
                    onPressed: () => ref.invalidate(adminWardsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (wards) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Configure ward names and bed labels. Patient allocations are managed by the charge nurse.',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => _edit(context, ref, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Create ward'),
                  ),
                ),
                if (wards.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No wards configured.'),
                  ),
                for (final ward in wards)
                  Card(
                    child: ListTile(
                      title: Text(ward.name),
                      subtitle: Text(
                        '${ward.bedNumbers.length} beds${ward.department.isEmpty ? '' : ' · ${ward.department}'}\n${ward.bedNumbers.isEmpty ? 'No bed labels configured' : ward.bedNumbers.join(', ')}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: 'Edit ${ward.name}',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit(context, ref, ward),
                      ),
                    ),
                  ),
              ],
            ),
          ),
    );
  }
}

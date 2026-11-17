import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/hospital_ward.dart';
import '../providers/whiteboard_providers.dart';
import '../providers/auth_providers.dart';
import '../providers/ward_context_providers.dart';
import '../theme/clinical_theme.dart';

class WardSelectionDialog extends ConsumerStatefulWidget {
  const WardSelectionDialog({super.key});

  @override
  ConsumerState<WardSelectionDialog> createState() =>
      _WardSelectionDialogState();
}

class _WardSelectionDialogState extends ConsumerState<WardSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';
  late final Future<List<HospitalWard>> _wardsFuture;

  @override
  void initState() {
    super.initState();
    _wardsFuture = ref.read(authenticatedStaffProvider)?.isChargeNurse == true
        ? ref.read(wardBoardServiceProvider).getWards()
        : Future.value(const <HospitalWard>[]);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentWard = ref.watch(selectedWardProvider);
    final staff = ref.watch(authenticatedStaffProvider);

    if (staff?.isChargeNurse != true) {
      return AlertDialog(
        title: const Text('Ward assigned by the central board'),
        content: const Text(
          'Your ward follows your clinical assignment. '
          'Contact the Charge Nurse to arrange a ward transfer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: ClinicalTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.apartment, color: ClinicalTheme.nurseBlue, size: 22),
          SizedBox(width: 8),
          Text(
            'Select Hospital Ward',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search field with real-time autofilter
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search hospital wards...',
                  hintStyle: const TextStyle(
                    color: ClinicalTheme.textMuted,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 18,
                    color: ClinicalTheme.textMuted,
                  ),
                  suffixIcon: _filter.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            size: 16,
                            color: ClinicalTheme.textMuted,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _filter = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onChanged: (val) => setState(() => _filter = val),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<List<HospitalWard>>(
                future: _wardsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Could not load the configured ward list.',
                        style: TextStyle(
                          color: ClinicalTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }
                  final q = _filter.trim().toLowerCase();
                  final filteredWards =
                      (snapshot.data ?? const <HospitalWard>[])
                          .where(
                            (ward) =>
                                q.isEmpty ||
                                ward.name.toLowerCase().contains(q) ||
                                ward.department.toLowerCase().contains(q),
                          )
                          .toList();
                  if (filteredWards.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No wards are configured for this hospital yet.',
                        style: TextStyle(
                          color: ClinicalTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: filteredWards.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Color(0xFF334155), height: 1),
                    itemBuilder: (ctx, i) {
                      final ward = filteredWards[i];
                      final isSelected = ward.wardId == currentWard.wardId;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        title: Text(
                          ward.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? ClinicalTheme.nurseBlue
                                : Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          ward.department,
                          style: const TextStyle(
                            fontSize: 12,
                            color: ClinicalTheme.textMuted,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: ClinicalTheme.nurseBlue,
                                size: 20,
                              )
                            : null,
                        onTap: staff?.isChargeNurse == true
                            ? () async {
                                try {
                                  await ref
                                      .read(wardBoardServiceProvider)
                                      .setPreferredWard(ward.wardId);
                                  if (!mounted ||
                                      ref
                                              .read(authenticatedStaffProvider)
                                              ?.staffId !=
                                          staff?.staffId ||
                                      ref
                                              .read(authenticatedStaffProvider)
                                              ?.isChargeNurse !=
                                          true)
                                    return;
                                  ref
                                      .read(selectedWardProvider.notifier)
                                      .selectWard(ward);
                                  ref
                                      .read(
                                        wardContextNeedsConfirmationProvider
                                            .notifier,
                                      )
                                      .setNeedsConfirmation(false);
                                  ref.invalidate(wardBoardProvider);
                                  ref.invalidate(boardStaffListProvider);
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$error')),
                                    );
                                  }
                                }
                              }
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: ClinicalTheme.textMuted),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/hospital_ward.dart';
import '../providers/whiteboard_providers.dart';
import '../theme/clinical_theme.dart';

class WardSelectionDialog extends ConsumerWidget {
  const WardSelectionDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentWard = ref.watch(selectedWardProvider);

    return AlertDialog(
      backgroundColor: ClinicalTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.apartment, color: ClinicalTheme.nurseBlue, size: 22),
          SizedBox(width: 8),
          Text(
            'Select Hospital Ward',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: kDefaultHospitalWards.length,
          separatorBuilder: (_, _) => const Divider(color: Color(0xFF334155), height: 1),
          itemBuilder: (ctx, i) {
            final ward = kDefaultHospitalWards[i];
            final isSelected = ward.wardId == currentWard.wardId;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              title: Text(
                ward.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? ClinicalTheme.nurseBlue : Colors.white,
                ),
              ),
              subtitle: Text(
                '${ward.department} • ${ward.bedCount} Beds (${ward.bedNumbers.first}-${ward.bedNumbers.last})',
                style: const TextStyle(fontSize: 12, color: ClinicalTheme.textMuted),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: ClinicalTheme.nurseBlue, size: 20)
                  : null,
              onTap: () {
                ref.read(selectedWardProvider.notifier).selectWard(ward);
                Navigator.of(context).pop();
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: ClinicalTheme.textMuted)),
        ),
      ],
    );
  }
}

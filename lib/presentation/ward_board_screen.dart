import 'widgets/ward_search_sheet.dart';
import 'handoff_wizard_screen.dart';
import 'whiteboard/digital_whiteboard_screen.dart';
import 'widgets/ward_selection_dialog.dart';
import 'providers/whiteboard_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/loop_enums.dart';
import '../domain/models/staff_profile.dart';
import '../domain/projections/projections.dart';
import 'patient_detail_screen.dart';
import 'providers/ward_providers.dart';
import 'providers/auth_providers.dart';
import 'lockscreen/digital_id_lockscreen.dart';
import 'theme/clinical_theme.dart';

/// The core clinical home screen strictly implementing PRD Section 7.1:
/// - One row per bed matching the ward round order (FR-1).
/// - Minimal patient record showing two required identifiers: Bed + Admission No (FR-2 & FR-3).
/// - Open-loop count and most urgent state badge displayed prominently (FR-1).
/// - High contrast and glanceable for night shifts.
class WardBoardScreen extends ConsumerWidget {
  const WardBoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patients = ref.watch(wardPatientsProvider);

    return Scaffold(
      backgroundColor: ClinicalTheme.background,
      appBar: AppBar(
        titleSpacing: 12,
        title: InkWell(
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => const WardSelectionDialog(),
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  "ORAVI · ${ref.watch(selectedWardProvider).name.split(' ').first.toUpperCase()}",
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: ClinicalTheme.nurseBlue, size: 18),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Ward Board & Nurse Allocation',
            icon: const Icon(Icons.dashboard_customize_outlined, color: ClinicalTheme.nurseBlue),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DigitalWhiteboardScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Ward Search (Tech Arch Section 9)',
            icon: const Icon(Icons.search, color: ClinicalTheme.routineTeal),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const WardSearchSheet(),
              );
            },
          ),
          IconButton(
            tooltip: 'Start Shift Handoff (PRD FR-11)',
            icon: const Icon(Icons.swap_horiz, color: ClinicalTheme.nurseBlue),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HandoffWizardScreen()),
              );
            },
          ),
          Consumer(
            builder: (context, ref, _) {
              final authStaff = ref.watch(authenticatedStaffProvider);
              if (authStaff == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => _showLockDialog(context, ref, authStaff),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.3),
                          child: Text(
                            authStaff.initials,
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.lock_outline, size: 14, color: Color(0xFF94A3B8)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: patients.isEmpty
          ? const Center(
              child: Text(
                'No active patients in this ward.',
                style: TextStyle(color: ClinicalTheme.textSecondary),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: patients.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.4)),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const DigitalWhiteboardScreen()),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.dashboard_customize, color: Color(0xFF38BDF8), size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ward Management & Nurse Allocation',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Tap to view Beds 1–10, Doctors & Nurse assignments',
                                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios, color: Color(0xFF38BDF8), size: 14),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return _WardBedRow(patient: patients[index - 1]);
              },
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: ClinicalTheme.surface,
          border: Border(top: BorderSide(color: ClinicalTheme.border)),
        ),
        child: SafeArea(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: ClinicalTheme.nurseBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Start Shift Handoff (PRD FR-11)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HandoffWizardScreen()),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showLockDialog(BuildContext context, WidgetRef ref, StaffProfile staff) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.3),
              child: Text(
                staff.initials,
                style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                staff.name,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Role: ${staff.formattedRole} • Staff ID: ${staff.staffId}\n\nWould you like to lock this station or switch to another nurse?',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            icon: const Icon(Icons.lock, size: 16, color: Colors.white),
            label: const Text('Lock Station', style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(authControllerProvider.notifier).logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const DigitalIdLockscreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WardBedRow extends ConsumerWidget {
  final PatientStateProjection patient;

  const _WardBedRow({required this.patient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loops = ref.watch(patientLoopsProvider(patient.patientId));
    final openLoops = loops.where((l) => l.isOpen).toList();

    // Determine highest urgency among open loops
    LoopUrgency? highestUrgency;
    if (openLoops.any((l) => l.urgency == LoopUrgency.critical)) {
      highestUrgency = LoopUrgency.critical;
    } else if (openLoops.any((l) => l.urgency == LoopUrgency.urgent)) {
      highestUrgency = LoopUrgency.urgent;
    } else if (openLoops.isNotEmpty) {
      highestUrgency = LoopUrgency.routine;
    }

    final hasCriticalStat = highestUrgency == LoopUrgency.critical;
    final rowBorderColor = hasCriticalStat ? ClinicalTheme.criticalRed : ClinicalTheme.border;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: rowBorderColor, width: hasCriticalStat ? 1.5 : 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (ctx) => PatientDetailScreen(patient: patient),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Bed Number Box
              Container(
                width: 56,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: hasCriticalStat
                      ? ClinicalTheme.criticalRed.withValues(alpha: 0.2)
                      : ClinicalTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasCriticalStat ? ClinicalTheme.criticalRed : ClinicalTheme.border,
                  ),
                ),
                child: Center(
                  child: Text(
                    patient.bedNumber,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: hasCriticalStat ? ClinicalTheme.criticalRed : ClinicalTheme.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Patient Identifiers & Short Note (FR-2 & FR-3)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (patient.nameOrInitials.isNotEmpty)
                          Text(
                            patient.nameOrInitials,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: ClinicalTheme.textPrimary,
                            ),
                          ),
                        Text(
                          '(${patient.admissionNumber})',
                          style: const TextStyle(
                            fontSize: 11,
                            color: ClinicalTheme.textMuted,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          '${patient.age}y/${patient.sex}',
                          style: const TextStyle(fontSize: 11, color: ClinicalTheme.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      patient.shortAdmittingNote,
                      style: const TextStyle(fontSize: 12, color: ClinicalTheme.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Open Loops Badge (FR-1: Open-loop count and most urgent state)
              if (openLoops.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: ClinicalTheme.successGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: ClinicalTheme.successGreen, width: 0.8),
                  ),
                  child: const Text(
                    'ALL CLEAR',
                    style: TextStyle(
                      color: ClinicalTheme.successGreen,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: ClinicalTheme.urgencyColor(highestUrgency!).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ClinicalTheme.urgencyColor(highestUrgency), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasCriticalStat ? Icons.warning_rounded : Icons.pending_actions,
                        size: 14,
                        color: ClinicalTheme.urgencyColor(highestUrgency),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${openLoops.length} OPEN',
                        style: TextStyle(
                          color: ClinicalTheme.urgencyColor(highestUrgency),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: ClinicalTheme.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

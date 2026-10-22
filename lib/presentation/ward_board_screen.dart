import '../data/sync/sync_engine.dart';
import 'handoff_wizard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock/seeded_ward_data.dart';
import '../domain/models/loop_enums.dart';
import '../domain/projections/projections.dart';
import 'patient_detail_screen.dart';
import 'providers/ward_providers.dart';
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
    final syncStatus = ref.watch(syncStatusProvider).asData?.value ?? const SyncStatus();

    return Scaffold(
      backgroundColor: ClinicalTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ORAVI — WARD BOARD'),
            Text(
              '${SeededWardData.wardName} • Offline Mode',
              style: TextStyle(fontSize: 11, color: ClinicalTheme.routineTeal, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Start Shift Handoff (PRD FR-11)',
            icon: const Icon(Icons.swap_horiz, color: ClinicalTheme.nurseBlue),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HandoffWizardScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Outbox Sync: ${syncStatus.pendingCount} pending',
            icon: Icon(
              syncStatus.state == SyncState.syncing
                  ? Icons.sync
                  : (syncStatus.pendingCount > 0 ? Icons.cloud_upload : Icons.cloud_done),
              color: syncStatus.state == SyncState.syncing
                  ? ClinicalTheme.nurseBlue
                  : (syncStatus.pendingCount > 0 ? ClinicalTheme.urgentAmber : ClinicalTheme.textMuted),
            ),
            onPressed: () async {
              final synced = await ref.read(syncEngineProvider).syncOutbox();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(synced > 0
                        ? 'Synced $synced pending event(s) to server.'
                        : 'Outbox up to date. Local SQLite event log persistent.'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
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
              itemCount: patients.length,
              itemBuilder: (context, index) {
                return _WardBedRow(patient: patients[index]);
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
                    Row(
                      children: [
                        Text(
                          patient.nameOrInitials,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: ClinicalTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${patient.admissionNumber})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: ClinicalTheme.textMuted,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${patient.age}y/${patient.sex}',
                          style: const TextStyle(fontSize: 12, color: ClinicalTheme.textSecondary),
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

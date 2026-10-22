import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock/seeded_ward_data.dart';
import '../domain/models/loop_enums.dart';
import '../domain/projections/projections.dart';
import 'handover_print_sheet_screen.dart';
import 'providers/ward_providers.dart';
import 'theme/clinical_theme.dart';

/// Shift Handoff Wizard strictly implementing PRD Section 7.3:
/// - FR-11: Pairs outgoing and incoming nurse and walks the board bed by bed.
/// - FR-12: Bulk acceptance for Routine loops; mandatory individual acceptance for Critical loops.
/// - FR-13: SBAR summary automatically compiled from structured entries.
/// - FR-14: Explicit timestamped confirmation per bed ('nothing pending' or 'N loops transferred').
/// - FR-16: Completed handoff is locked; corrections are appended.
class HandoffWizardScreen extends ConsumerStatefulWidget {
  const HandoffWizardScreen({super.key});

  @override
  ConsumerState<HandoffWizardScreen> createState() => _HandoffWizardScreenState();
}

class _HandoffWizardScreenState extends ConsumerState<HandoffWizardScreen> {
  // Step tracking: 0 = Pairing, 1 = Bed Stepper, 2 = Summary & Lock
  int _currentStep = 0;
  int _currentBedIndex = 0;

  String _outgoingNurse = 'Nurse Mwangi, RN';
  String _incomingNurse = 'Nurse Achieng, RN';

  // Per-bed review state during stepper
  final Set<String> _selectedLoopIds = {};
  final Set<String> _acknowledgedCriticalLoopIds = {};

  final List<String> _availableNurses = [
    'Nurse Mwangi, RN',
    'Nurse Achieng, RN',
    'Nurse Wanjiku, KRCHN',
    'Nurse Otieno, BSN',
    'Sister Mary, In-Charge',
  ];

  void _onStartHandoff() {
    ref.read(wardControllerProvider.notifier).startHandoffSession(
          outgoingNurseId: _outgoingNurse,
          incomingNurseId: _incomingNurse,
        );
    setState(() {
      _currentStep = 1;
      _currentBedIndex = 0;
      _resetBedSelection();
    });
  }

  void _resetBedSelection() {
    _selectedLoopIds.clear();
    _acknowledgedCriticalLoopIds.clear();
  }

  @override
  Widget build(BuildContext context) {
    final patients = ref.watch(wardPatientsProvider);
    final session = ref.watch(activeHandoffSessionProvider);

    return Scaffold(
      backgroundColor: ClinicalTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SHIFT HANDOFF SESSION'),
            Text(
              '${SeededWardData.wardName} • PRD FR-11 to FR-17',
              style: const TextStyle(fontSize: 11, color: ClinicalTheme.routineTeal, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: _buildCurrentStep(patients, session),
    );
  }

  Widget _buildCurrentStep(List<PatientStateProjection> patients, HandoffSessionProjection? session) {
    if (_currentStep == 0) {
      return _buildPairingView();
    } else if (_currentStep == 1) {
      if (patients.isEmpty || _currentBedIndex >= patients.length) {
        return _buildSummaryLockView(session);
      }
      return _buildBedWalkthrough(patients[_currentBedIndex], patients.length, session);
    } else {
      return _buildSummaryLockView(session);
    }
  }

  // ==========================================
  // Step 1: Nurse Pairing View (FR-11)
  // ==========================================
  Widget _buildPairingView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ClinicalTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ClinicalTheme.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz, color: ClinicalTheme.nurseBlue, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Shift Handover Protocol',
                        style: TextStyle(color: ClinicalTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Pairs outgoing and incoming nurses to walk the board bed by bed. No patient is left unconfirmed.',
                        style: TextStyle(color: ClinicalTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('OUTGOING NURSE (Handing Over)',
              style: TextStyle(color: ClinicalTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _outgoingNurse,
            dropdownColor: ClinicalTheme.surface,
            decoration: InputDecoration(
              filled: true,
              fillColor: ClinicalTheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: _availableNurses
                .map((n) => DropdownMenuItem(
                      value: n,
                      child: Text(n, style: const TextStyle(color: ClinicalTheme.nurseBlue, fontWeight: FontWeight.w600)),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _outgoingNurse = val);
            },
          ),
          const SizedBox(height: 20),
          const Text('INCOMING NURSE (Taking Over)',
              style: TextStyle(color: ClinicalTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _incomingNurse,
            dropdownColor: ClinicalTheme.surface,
            decoration: InputDecoration(
              filled: true,
              fillColor: ClinicalTheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: _availableNurses
                .map((n) => DropdownMenuItem(
                      value: n,
                      child: Text(n, style: const TextStyle(color: ClinicalTheme.doctorPink, fontWeight: FontWeight.w600)),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _incomingNurse = val);
            },
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: ClinicalTheme.nurseBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Begin Bed-by-Bed Walkthrough', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              onPressed: _onStartHandoff,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Step 2: Bed Walkthrough View (FR-11 to FR-14)
  // ==========================================
  Widget _buildBedWalkthrough(
    PatientStateProjection patient,
    int totalBeds,
    HandoffSessionProjection? session,
  ) {
    final loops = ref.watch(patientLoopsProvider(patient.patientId));
    final openLoops = loops.where((l) => l.isOpen).toList();
    final criticalLoops = openLoops.where((l) => l.urgency == LoopUrgency.critical).toList();
    final routineLoops = openLoops.where((l) => l.urgency != LoopUrgency.critical).toList();

    final sbar = SbarSummary.fromPatientAndLoops(patient: patient, loops: loops);

    final allCriticalAcknowledged = criticalLoops.isEmpty ||
        criticalLoops.every((l) => _acknowledgedCriticalLoopIds.contains(l.loopId));

    return Column(
      children: [
        // Stepper Progress Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: ClinicalTheme.surfaceElevated,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Bed ${_currentBedIndex + 1} of $totalBeds: ${patient.bedNumber}',
                    style: const TextStyle(color: ClinicalTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    '${((_currentBedIndex + 1) / totalBeds * 100).toInt()}% Complete',
                    style: const TextStyle(color: ClinicalTheme.textMuted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: (_currentBedIndex + 1) / totalBeds,
                backgroundColor: ClinicalTheme.surface,
                color: ClinicalTheme.nurseBlue,
              ),
            ],
          ),
        ),

        // Scrollable Bed Content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // Patient Banner (FR-3: Two required identifiers)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ClinicalTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ClinicalTheme.border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: ClinicalTheme.nurseBlue.withValues(alpha: 0.15),
                      child: Text(
                        patient.bedNumber,
                        style: const TextStyle(color: ClinicalTheme.nurseBlue, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${patient.nameOrInitials} (${patient.age}y ${patient.sex})',
                            style: const TextStyle(color: ClinicalTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            'Admission: ${patient.admissionNumber}',
                            style: const TextStyle(color: ClinicalTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // SBAR Structured Summary Card (FR-13)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ClinicalTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ClinicalTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.assignment_outlined, size: 16, color: ClinicalTheme.routineTeal),
                        SizedBox(width: 6),
                        Text(
                          'SBAR SUMMARY (Compiled without AI)',
                          style: TextStyle(color: ClinicalTheme.routineTeal, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                    const Divider(height: 16, color: ClinicalTheme.border),
                    _buildSbarRow('S (Situation)', sbar.situation),
                    const SizedBox(height: 6),
                    _buildSbarRow('B (Background)', sbar.background),
                    const SizedBox(height: 6),
                    _buildSbarRow('A (Assessment)', sbar.assessment),
                    const SizedBox(height: 6),
                    _buildSbarRow('R (Recommendation)', sbar.recommendation),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Open Loops & Acceptance Protocol (FR-12)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'OPEN LOOPS (${openLoops.length})',
                    style: const TextStyle(color: ClinicalTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  if (routineLoops.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      icon: const Icon(Icons.select_all, size: 16),
                      label: const Text('Bulk Accept Routine', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        setState(() {
                          _selectedLoopIds.addAll(routineLoops.map((l) => l.loopId));
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),

              if (openLoops.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ClinicalTheme.successGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ClinicalTheme.successGreen),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: ClinicalTheme.successGreen),
                      SizedBox(width: 10),
                      Text(
                        'ALL CLEAR: No open items pending on this bed.',
                        style: TextStyle(color: ClinicalTheme.successGreen, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )
              else ...[
                // Critical Loops: Individual Mandatory Acceptance (FR-12)
                ...criticalLoops.map((loop) {
                  final isAcked = _acknowledgedCriticalLoopIds.contains(loop.loopId);
                  return Card(
                    color: ClinicalTheme.surface,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isAcked ? ClinicalTheme.successGreen : ClinicalTheme.criticalRed,
                        width: 1.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: ClinicalTheme.criticalRed.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'CRITICAL / STAT',
                                  style: TextStyle(color: ClinicalTheme.criticalRed, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  loop.title,
                                  style: const TextStyle(color: ClinicalTheme.textPrimary, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(loop.description, style: const TextStyle(color: ClinicalTheme.textSecondary, fontSize: 12)),
                          const Divider(height: 16, color: ClinicalTheme.border),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: isAcked,
                            activeColor: ClinicalTheme.successGreen,
                            title: const Text(
                              'I have verbally discussed this STAT item and accept individual ownership (FR-12)',
                              style: TextStyle(color: ClinicalTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _acknowledgedCriticalLoopIds.add(loop.loopId);
                                  _selectedLoopIds.add(loop.loopId);
                                } else {
                                  _acknowledgedCriticalLoopIds.remove(loop.loopId);
                                  _selectedLoopIds.remove(loop.loopId);
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                // Routine & Urgent Loops
                ...routineLoops.map((loop) {
                  final isSelected = _selectedLoopIds.contains(loop.loopId);
                  return Card(
                    color: ClinicalTheme.surface,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: isSelected ? ClinicalTheme.nurseBlue : ClinicalTheme.border),
                    ),
                    child: CheckboxListTile(
                      dense: true,
                      value: isSelected,
                      activeColor: ClinicalTheme.nurseBlue,
                      title: Text(
                        '[${loop.urgency.name.toUpperCase()}] ${loop.title}',
                        style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(loop.description, style: const TextStyle(color: ClinicalTheme.textSecondary, fontSize: 11)),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedLoopIds.add(loop.loopId);
                          } else {
                            _selectedLoopIds.remove(loop.loopId);
                          }
                        });
                      },
                    ),
                  );
                }),
              ],
            ],
          ),
        ),

        // Bottom Action Bar: Explicit Bed Confirmation (FR-14)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: ClinicalTheme.surface,
            border: Border(top: BorderSide(color: ClinicalTheme.border)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: openLoops.isEmpty
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: ClinicalTheme.successGreen,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text('Confirm: Nothing Pending (${patient.bedNumber})',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _confirmBed(patient, session, nothingPending: true),
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: allCriticalAcknowledged ? ClinicalTheme.urgentAmber : Colors.grey[700],
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(
                      allCriticalAcknowledged
                          ? 'Confirm: Transfer ${_selectedLoopIds.length} Loop(s) (${patient.bedNumber})'
                          : 'Acknowledge Critical STAT Loop First',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: allCriticalAcknowledged
                        ? () => _confirmBed(patient, session, nothingPending: false)
                        : null,
                  ),
          ),
        ),
      ],
    );
  }

  void _confirmBed(PatientStateProjection patient, HandoffSessionProjection? session, {required bool nothingPending}) {
    final sessionId = session?.handoffSessionId ?? 'HANDOFF-ACTIVE';

    ref.read(wardControllerProvider.notifier).acceptBedInHandoff(
          handoffSessionId: sessionId,
          bedNumber: patient.bedNumber,
          patientId: patient.patientId,
          incomingNurseId: _incomingNurse,
          nothingPendingConfirmed: nothingPending,
          transferredLoopIds: nothingPending ? const [] : _selectedLoopIds.toList(),
        );

    final patients = ref.read(wardPatientsProvider);
    if (_currentBedIndex + 1 < patients.length) {
      setState(() {
        _currentBedIndex++;
        _resetBedSelection();
      });
    } else {
      setState(() {
        _currentStep = 2; // Jump to Summary
      });
    }
  }

  Widget _buildSbarRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: ClinicalTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 11.5)),
        ),
      ],
    );
  }

  // ==========================================
  // Step 3: Shift Summary & Cryptographic Lock (FR-14 to FR-16)
  // ==========================================
  Widget _buildSummaryLockView(HandoffSessionProjection? session) {
    final patients = ref.watch(wardPatientsProvider);
    final isLocked = session?.isLocked ?? false;

    final totalTransferred = session?.totalLoopsTransferred ?? 0;
    final totalBeds = session?.totalBedsHandedOver ?? patients.length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ClinicalTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isLocked ? ClinicalTheme.successGreen : ClinicalTheme.border),
            ),
            child: Column(
              children: [
                Icon(
                  isLocked ? Icons.lock : Icons.task_alt,
                  color: isLocked ? ClinicalTheme.successGreen : ClinicalTheme.nurseBlue,
                  size: 44,
                ),
                const SizedBox(height: 10),
                Text(
                  isLocked ? 'Handoff Locked & Finalized' : 'Handoff Walkthrough Complete',
                  style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '${session?.outgoingNurseId ?? _outgoingNurse} ➔ ${session?.incomingNurseId ?? _incomingNurse}',
                  style: const TextStyle(color: ClinicalTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Statistics Card
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ClinicalTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ClinicalTheme.border),
                  ),
                  child: Column(
                    children: [
                      Text('$totalBeds / ${patients.length}',
                          style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Beds Reviewed', style: TextStyle(color: ClinicalTheme.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ClinicalTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ClinicalTheme.border),
                  ),
                  child: Column(
                    children: [
                      Text('$totalTransferred',
                          style: const TextStyle(color: ClinicalTheme.urgentAmber, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Loops Transferred', style: TextStyle(color: ClinicalTheme.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // PRD FR-16 notice
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'PRD FR-16: A completed handoff record is locked. Corrections are appended, never overwritten.',
                    style: TextStyle(color: Colors.amber, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),

          // Secondary Action: 1-Page Printable Sheet (FR-15)
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: ClinicalTheme.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.print_outlined, color: ClinicalTheme.textPrimary),
              label: const Text('View 1-Page Handover Sheet (FR-15)', style: TextStyle(color: ClinicalTheme.textPrimary)),
              onPressed: session == null
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => HandoverPrintSheetScreen(session: session)),
                      );
                    },
            ),
          ),
          const SizedBox(height: 10),

          // Primary Action: Lock Record
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: isLocked ? ClinicalTheme.border : ClinicalTheme.successGreen,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(isLocked ? Icons.check : Icons.lock_outline),
              label: Text(
                isLocked ? 'Handoff Locked & Completed' : 'Sign & Lock Shift Handover',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              onPressed: isLocked || session == null
                  ? null
                  : () {
                      ref.read(wardControllerProvider.notifier).completeHandoffSession(
                            handoffSessionId: session.handoffSessionId,
                            authorId: _incomingNurse,
                            totalBedsHandedOver: totalBeds,
                            totalLoopsTransferred: totalTransferred,
                          );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Shift handoff locked and signed. Record is immutable.'),
                          backgroundColor: ClinicalTheme.successGreen,
                        ),
                      );
                    },
            ),
          ),
        ],
      ),
    );
  }
}

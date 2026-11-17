import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/loop_enums.dart';
import '../domain/models/staff_profile.dart';
import '../domain/projections/projections.dart';
import 'handover_print_sheet_screen.dart';
import 'providers/auth_providers.dart';
import 'providers/ward_providers.dart';
import 'providers/whiteboard_providers.dart';
import 'providers/ward_context_providers.dart';
import 'theme/clinical_theme.dart';

/// Shift Handoff Wizard strictly implementing PRD Section 7.3:
/// - FR-11: Pairs outgoing and incoming nurse and walks the board bed by bed.
/// - FR-12: Transfers every unfinished Medical Issue; critical issues require individual acceptance.
/// - FR-13: SBAR summary automatically compiled from structured entries.
/// - FR-14: Explicit timestamped confirmation per bed ('nothing pending' or 'N loops transferred').
/// - FR-16: Completed handoff is locked; corrections are appended.
class HandoffWizardScreen extends ConsumerStatefulWidget {
  const HandoffWizardScreen({super.key});

  @override
  ConsumerState<HandoffWizardScreen> createState() =>
      _HandoffWizardScreenState();
}

class _HandoffWizardScreenState extends ConsumerState<HandoffWizardScreen> {
  // Step tracking: 0 = Pairing, 1 = Bed Stepper, 2 = Summary & Lock
  int _currentStep = 0;
  int _currentBedIndex = 0;

  String _outgoingNurse = '';
  String _incomingNurse = '';
  String? _incomingAcceptanceToken;

  // Per-bed review state during stepper
  final Set<String> _acknowledgedCriticalLoopIds = {};

  @override
  void initState() {
    super.initState();
    _outgoingNurse = ref.read(authenticatedStaffProvider)?.staffId ?? '';
  }

  Future<void> _onStartHandoff() async {
    final pin = await _requestIncomingPin();
    if (pin == null) return;
    final result = await ref
        .read(staffAuthServiceProvider)
        .verifyPin(_incomingNurse, pin);
    final incomingToken = result.token;
    if (!result.success ||
        result.staff?.staffId != _incomingNurse ||
        result.staff?.isWardNurse != true ||
        incomingToken == null ||
        incomingToken.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.error ?? 'Incoming nurse verification failed.',
            ),
          ),
        );
      }
      return;
    }
    _incomingAcceptanceToken = incomingToken;
    try {
      await ref
          .read(wardControllerProvider.notifier)
          .startHandoffSession(
            outgoingNurseId: _outgoingNurse,
            incomingNurseId: _incomingNurse,
          );
    } catch (error) {
      _showHandoffError('Could not save the handoff: $error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _currentStep = 1;
      _currentBedIndex = 0;
      _resetBedSelection();
    });
  }

  Future<String?> _requestIncomingPin() async {
    var enteredPin = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Incoming nurse verification'),
        content: TextField(
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          onChanged: (value) => enteredPin = value,
          decoration: const InputDecoration(
            labelText: 'Enter the incoming nurse PIN',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final pin = enteredPin.trim();
              if (pin.length >= 4 &&
                  pin.length <= 8 &&
                  int.tryParse(pin) != null) {
                Navigator.of(dialogContext).pop(pin);
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  void _showHandoffError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _resetBedSelection() {
    _acknowledgedCriticalLoopIds.clear();
  }

  @override
  Widget build(BuildContext context) {
    final patients = ref.watch(currentNurseShiftPatientsProvider);
    final session = ref.watch(activeHandoffSessionProvider);
    final ward = ref.watch(selectedWardProvider);
    final boardState = ref.watch(wardBoardProvider);
    final currentStaff = ref.watch(authenticatedStaffProvider);
    final nurses =
        (ref.watch(boardStaffListProvider).asData?.value ??
                const <StaffProfile>[])
            .where((staff) => staff.isWardNurse || staff.isChargeNurse)
            .toList();

    return Scaffold(
      backgroundColor: ClinicalTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SHIFT HANDOFF SESSION'),
            Text(
              '${ward.name} • Guided nurse-to-nurse transfer',
              style: const TextStyle(
                fontSize: 11,
                color: ClinicalTheme.routineTeal,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: ward.wardId.isEmpty
          ? _handoffMessage('No ward is assigned for this shift.')
          : ref.watch(wardContextNeedsConfirmationProvider)
          ? _handoffMessage('Confirm your ward before starting handoff.')
          : boardState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : boardState.hasError
          ? _handoffMessage(
              'The ward board could not be loaded: ${boardState.error}',
            )
          : _currentStep == 0 && patients.isEmpty
          ? _handoffMessage(
              'There are no patients assigned to hand over for this shift.',
            )
          : _buildCurrentStep(patients, session, nurses, currentStaff),
    );
  }

  Widget _handoffMessage(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: ClinicalTheme.textSecondary),
      ),
    ),
  );

  Widget _buildCurrentStep(
    List<PatientStateProjection> patients,
    HandoffSessionProjection? session,
    List<StaffProfile> nurses,
    StaffProfile? currentStaff,
  ) {
    if (_currentStep == 0) {
      return _buildPairingView(nurses, currentStaff);
    } else if (_currentStep == 1) {
      if (patients.isEmpty || _currentBedIndex >= patients.length) {
        return _buildSummaryLockView(session);
      }
      return _buildBedWalkthrough(
        patients[_currentBedIndex],
        patients.length,
        session,
      );
    } else {
      return _buildSummaryLockView(session);
    }
  }

  // ==========================================
  // Step 1: Nurse Pairing View (FR-11)
  // ==========================================
  Widget _buildPairingView(
    List<StaffProfile> nurses,
    StaffProfile? currentStaff,
  ) {
    final availableIncoming = nurses
        .where((staff) => staff.staffId != currentStaff?.staffId)
        .toList();
    final incomingValue =
        availableIncoming.any((staff) => staff.staffId == _incomingNurse)
        ? _incomingNurse
        : null;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ClinicalTheme.surfaceAccent,
                    borderRadius: BorderRadius.circular(
                      ClinicalTheme.radiusMedium,
                    ),
                    border: Border.all(
                      color: ClinicalTheme.clinicalBlue.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.swap_horiz,
                        color: ClinicalTheme.nurseBlue,
                        size: 32,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Shift Handover Protocol',
                              style: TextStyle(
                                color: ClinicalTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Verify both nurses, then review every assigned patient and transfer all unfinished medical issues.',
                              style: TextStyle(
                                color: ClinicalTheme.textSecondary,
                                fontSize: 14,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const _HandoffSectionLabel(
                  step: '1',
                  label: 'Outgoing nurse',
                  detail: 'Handing over this shift',
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ClinicalTheme.surface,
                    borderRadius: BorderRadius.circular(
                      ClinicalTheme.radiusMedium,
                    ),
                    border: Border.all(color: ClinicalTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        color: ClinicalTheme.nurseBlue,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          currentStaff == null
                              ? 'Sign in as the outgoing nurse.'
                              : '${currentStaff.name} · ${currentStaff.staffId}',
                          style: const TextStyle(
                            color: ClinicalTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const _HandoffSectionLabel(
                  step: '2',
                  label: 'Incoming nurse',
                  detail: 'Taking ownership of the shift',
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: incomingValue,
                  isExpanded: true,
                  dropdownColor: ClinicalTheme.surface,
                  decoration: const InputDecoration(
                    labelText: 'Select incoming nurse',
                    prefixIcon: Icon(Icons.person_add_alt_1_outlined),
                  ),
                  hint: const Text('Choose a nurse'),
                  items: availableIncoming
                      .map(
                        (staff) => DropdownMenuItem(
                          value: staff.staffId,
                          child: Text(
                            '${staff.name} · ${staff.staffId}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ClinicalTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _incomingNurse = value);
                    }
                  },
                ),
                if (availableIncoming.isEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'No other ward nurse is available to receive this handoff.',
                    style: TextStyle(color: ClinicalTheme.urgentAmber),
                  ),
                ],
                const Spacer(),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: ClinicalTheme.nurseBlue,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(56),
                    ),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text(
                      'Begin Bed-by-Bed Walkthrough',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15),
                    ),
                    onPressed:
                        incomingValue == null ||
                            currentStaff?.isWardNurse != true
                        ? null
                        : _onStartHandoff,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    final criticalLoops = openLoops
        .where((l) => l.urgency == LoopUrgency.critical)
        .toList();
    final routineLoops = openLoops
        .where((l) => l.urgency != LoopUrgency.critical)
        .toList();

    final sbar = SbarSummary.fromPatientAndLoops(
      patient: patient,
      loops: loops,
    );

    final allCriticalAcknowledged =
        criticalLoops.isEmpty ||
        criticalLoops.every(
          (l) => _acknowledgedCriticalLoopIds.contains(l.loopId),
        );

    return Column(
      children: [
        // Stepper Progress Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: ClinicalTheme.surfaceElevated,
          child: Column(
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runAlignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    'Bed ${_currentBedIndex + 1} of $totalBeds: ${patient.bedNumber}',
                    style: const TextStyle(
                      color: ClinicalTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '${((_currentBedIndex + 1) / totalBeds * 100).toInt()}% complete',
                    style: const TextStyle(
                      color: ClinicalTheme.textSecondary,
                      fontSize: 13,
                    ),
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
                      backgroundColor: ClinicalTheme.nurseBlue.withValues(
                        alpha: 0.15,
                      ),
                      child: Text(
                        patient.bedNumber,
                        style: const TextStyle(
                          color: ClinicalTheme.nurseBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${patient.patientInitials} (${patient.age}y ${patient.sex})',
                            style: const TextStyle(
                              color: ClinicalTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
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
                        Icon(
                          Icons.assignment_outlined,
                          size: 16,
                          color: ClinicalTheme.routineTeal,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'SBAR SUMMARY (Compiled without AI)',
                            style: TextStyle(
                              color: ClinicalTheme.routineTeal,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
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

              // Every unfinished issue transfers with the patient.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ACTIVE MEDICAL ISSUES (${openLoops.length})',
                    style: const TextStyle(
                      color: ClinicalTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
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
                      Icon(
                        Icons.check_circle,
                        color: ClinicalTheme.successGreen,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ALL CLEAR: No open items pending on this bed.',
                          style: TextStyle(
                            color: ClinicalTheme.successGreen,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                // Critical issues still require individual verbal acceptance.
                ...criticalLoops.map((loop) {
                  final isAcked = _acknowledgedCriticalLoopIds.contains(
                    loop.loopId,
                  );
                  return Card(
                    color: ClinicalTheme.surface,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isAcked
                            ? ClinicalTheme.successGreen
                            : ClinicalTheme.criticalRed,
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: ClinicalTheme.criticalRed.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'CRITICAL / STAT',
                                  style: TextStyle(
                                    color: ClinicalTheme.criticalRed,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  loop.title,
                                  style: const TextStyle(
                                    color: ClinicalTheme.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            loop.description,
                            style: const TextStyle(
                              color: ClinicalTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const Divider(
                            height: 16,
                            color: ClinicalTheme.border,
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: isAcked,
                            activeColor: ClinicalTheme.successGreen,
                            title: const Text(
                              'I have verbally discussed this STAT item and accept individual ownership (FR-12)',
                              style: TextStyle(
                                color: ClinicalTheme.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _acknowledgedCriticalLoopIds.add(loop.loopId);
                                } else {
                                  _acknowledgedCriticalLoopIds.remove(
                                    loop.loopId,
                                  );
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                // Routine and urgent issues transfer automatically with the bed.
                ...routineLoops.map((loop) {
                  return Card(
                    color: ClinicalTheme.surface,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: ClinicalTheme.border),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.medical_services_outlined,
                        color: ClinicalTheme.nurseBlue,
                      ),
                      title: Text(
                        '[${loop.urgency.name.toUpperCase()}] ${loop.title}',
                        style: const TextStyle(
                          color: ClinicalTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        loop.description,
                        style: const TextStyle(
                          color: ClinicalTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
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
            child: openLoops.isEmpty
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: ClinicalTheme.successGreen,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      'Confirm: Nothing Pending (${patient.bedNumber})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () =>
                        _confirmBed(patient, session, nothingPending: true),
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: allCriticalAcknowledged
                          ? ClinicalTheme.urgentAmber
                          : Colors.grey[700],
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(
                      allCriticalAcknowledged
                          ? 'Confirm: Transfer ${openLoops.length} Issue(s) (${patient.bedNumber})'
                          : 'Acknowledge Critical Medical Issue First',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: allCriticalAcknowledged
                        ? () => _confirmBed(
                            patient,
                            session,
                            nothingPending: false,
                          )
                        : null,
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmBed(
    PatientStateProjection patient,
    HandoffSessionProjection? session, {
    required bool nothingPending,
  }) async {
    final sessionId = session?.handoffSessionId ?? 'HANDOFF-ACTIVE';
    final incomingToken = _incomingAcceptanceToken;
    if (incomingToken == null) {
      _showHandoffError('Verify the incoming nurse before accepting beds.');
      return;
    }

    try {
      await ref
          .read(wardBoardProvider.notifier)
          .acceptHandoffBeds(
            bedNumbers: [patient.bedNumber],
            outgoingStaffId: _outgoingNurse,
            incomingAccessToken: incomingToken,
            handoffSessionId: sessionId,
            patientId: patient.patientId,
            transferredLoopIds: ref
                .read(patientLoopsProvider(patient.patientId))
                .where((loop) => loop.isOpen)
                .map((loop) => loop.loopId)
                .toList(),
          );
      await ref
          .read(wardControllerProvider.notifier)
          .acceptBedInHandoff(
            handoffSessionId: sessionId,
            bedNumber: patient.bedNumber,
            patientId: patient.patientId,
            incomingNurseId: _incomingNurse,
            nothingPendingConfirmed: nothingPending,
          );
    } catch (error) {
      _showHandoffError('Could not save this bed handoff: $error');
      return;
    }
    if (!mounted) return;

    final patients = ref.read(currentNurseShiftPatientsProvider);
    if (patients.isNotEmpty) {
      setState(() {
        _currentBedIndex = 0;
        _resetBedSelection();
      });
    } else {
      setState(() {
        _currentStep = 2; // Jump to Summary
      });
    }
  }

  Widget _buildSbarRow(String label, String value) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Text(
          value,
          style: const TextStyle(
            color: ClinicalTheme.textPrimary,
            fontSize: 13,
            height: 1.35,
          ),
        );
        final heading = Text(
          label,
          style: const TextStyle(
            color: ClinicalTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        );
        if (constraints.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 3), content],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 112, child: heading),
            Expanded(child: content),
          ],
        );
      },
    );
  }

  // ==========================================
  // Step 3: Shift Summary & Cryptographic Lock (FR-14 to FR-16)
  // ==========================================
  Widget _buildSummaryLockView(HandoffSessionProjection? session) {
    final patients = ref.watch(currentNurseShiftPatientsProvider);
    final isLocked = session?.isLocked ?? false;
    final totalTransferred = session?.totalLoopsTransferred ?? 0;
    final totalBedsHandedOver = session?.totalBedsHandedOver ?? 0;
    final totalBeds = totalBedsHandedOver + patients.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isLocked
                ? ClinicalTheme.successGreen.withValues(alpha: 0.08)
                : ClinicalTheme.surfaceAccent,
            borderRadius: BorderRadius.circular(ClinicalTheme.radiusMedium),
            border: Border.all(
              color: isLocked
                  ? ClinicalTheme.successGreen
                  : ClinicalTheme.clinicalBlue.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              Icon(
                isLocked ? Icons.lock : Icons.task_alt,
                color: isLocked
                    ? ClinicalTheme.successGreen
                    : ClinicalTheme.nurseBlue,
                size: 44,
              ),
              const SizedBox(height: 10),
              Text(
                isLocked
                    ? 'Handoff Locked & Finalized'
                    : 'Handoff Walkthrough Complete',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ClinicalTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${session?.outgoingNurseId ?? _outgoingNurse} → ${session?.incomingNurseId ?? _incomingNurse}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ClinicalTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              _HandoffStatCard(
                value: '$totalBedsHandedOver / $totalBeds',
                label: 'Beds reviewed',
                color: ClinicalTheme.clinicalBlue,
              ),
              _HandoffStatCard(
                value: '$totalTransferred',
                label: 'Medical issues transferred',
                color: ClinicalTheme.urgentAmber,
              ),
            ];
            if (constraints.maxWidth < 390) {
              return Column(
                children: [cards.first, const SizedBox(height: 10), cards.last],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cards.first),
                const SizedBox(width: 12),
                Expanded(child: cards.last),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ClinicalTheme.urgentAmber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(ClinicalTheme.radiusMedium),
            border: Border.all(
              color: ClinicalTheme.urgentAmber.withValues(alpha: 0.45),
            ),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                color: ClinicalTheme.urgentAmber,
                size: 22,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Once completed, this handoff record is locked. Any corrections are appended and the original record is preserved.',
                  style: TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          icon: const Icon(Icons.print_outlined),
          label: const Text('View printable handover sheet'),
          onPressed: session == null
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          HandoverPrintSheetScreen(session: session),
                    ),
                  );
                },
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: isLocked
                ? ClinicalTheme.border
                : ClinicalTheme.successGreen,
            foregroundColor: Colors.black,
          ),
          icon: Icon(isLocked ? Icons.check : Icons.lock_outline),
          label: Text(
            isLocked
                ? 'Handoff Locked & Completed'
                : 'End Shift & Lock Handover',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
          onPressed: isLocked || session == null || patients.isNotEmpty
              ? null
              : () async {
                  try {
                    await ref
                        .read(wardControllerProvider.notifier)
                        .completeHandoffSession(
                          handoffSessionId: session.handoffSessionId,
                          authorId: _outgoingNurse,
                          totalBedsHandedOver: totalBedsHandedOver,
                          totalLoopsTransferred: totalTransferred,
                        );
                  } catch (error) {
                    _showHandoffError(
                      'Could not save the completed handoff: $error',
                    );
                    return;
                  }
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Shift handoff locked and signed. Record is immutable.',
                      ),
                      backgroundColor: ClinicalTheme.successGreen,
                    ),
                  );
                },
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _HandoffSectionLabel extends StatelessWidget {
  const _HandoffSectionLabel({
    required this.step,
    required this.label,
    required this.detail,
  });

  final String step;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 13,
        backgroundColor: ClinicalTheme.clinicalBlue.withValues(alpha: 0.18),
        child: Text(
          step,
          style: const TextStyle(
            color: ClinicalTheme.clinicalBlue,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: ClinicalTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              detail,
              style: const TextStyle(
                color: ClinicalTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _HandoffStatCard extends StatelessWidget {
  const _HandoffStatCard({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ClinicalTheme.surface,
      borderRadius: BorderRadius.circular(ClinicalTheme.radiusMedium),
      border: Border.all(color: ClinicalTheme.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ClinicalTheme.textSecondary,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}

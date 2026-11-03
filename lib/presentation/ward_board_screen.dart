import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/loop_enums.dart';
import '../domain/models/staff_profile.dart';
import '../domain/models/whiteboard_models.dart';
import '../domain/projections/projections.dart';
import 'handoff_wizard_screen.dart';
import 'lockscreen/digital_id_lockscreen.dart';
import 'patient_detail_screen.dart';
import 'providers/auth_providers.dart';
import 'providers/ward_providers.dart';
import 'providers/whiteboard_providers.dart';
import 'providers/ward_context_providers.dart';
import 'whiteboard/digital_whiteboard_screen.dart';
import 'widgets/ward_search_sheet.dart';
import 'widgets/ward_selection_dialog.dart';

/// Pixel-perfect implementation of the Nurse Dashboard designed to eliminate clutter:
/// - Clean Header with hospital name, sync status, notifications, and profile avatar.
/// - At-a-glance shift overview KPI cards (My Patients, Pending Tasks, Completed Today).
/// - Quick filter pills (All, Pending, Completed) with search and filter.
/// - Prioritized patient list with status indicator stripes, bed numbers, diagnoses, doctors, and urgency badges.
/// - 6-card Ward Responsibilities grid with one-tap Call or Message action.
/// - Prominent Shift Handoff action banner.
/// - 5-tab Bottom Navigation bar.
class WardBoardScreen extends ConsumerStatefulWidget {
  const WardBoardScreen({super.key});

  @override
  ConsumerState<WardBoardScreen> createState() => _WardBoardScreenState();
}

class _WardBoardScreenState extends ConsumerState<WardBoardScreen> {
  int _activeNavIndex = 0;
  int _activeFilterIndex = 0; // 0: All, 1: Pending, 2: Completed

  @override
  Widget build(BuildContext context) {
    final patients = ref.watch(wardPatientsProvider);
    final currentWard = ref.watch(selectedWardProvider);
    final authStaff = ref.watch(authenticatedStaffProvider);
    final roster = ref.watch(wardSupportRosterProvider);
    final whiteboardBeds = ref.watch(whiteboardAssignmentsProvider);
    final boardState = ref.watch(wardBoardProvider);
    final staffState = ref.watch(boardStaffListProvider);
    final staffNames = {
      for (final member in staffState.asData?.value ?? const <StaffProfile>[])
        member.staffId: member.name,
    };

    // Map doctor names from whiteboard assignments
    final doctorMap = <String, String>{};
    for (final b in whiteboardBeds) {
      if (b.admittingDoctor.isNotEmpty && b.admittingDoctor != '-') {
        doctorMap[b.bedNumber] =
            staffNames[b.admittingDoctor] ?? b.admittingDoctor;
      }
    }

    // Nurse name
    final nurseName = authStaff?.name ?? 'Your shift';

    // Calculate dynamic counts
    final totalPatients = patients.length;
    // Calculate pending tasks and completed tasks from patient loops
    int pendingTasksCount = 0;
    int completedTasksCount = 0;

    for (final p in patients) {
      final loops = ref.watch(patientLoopsProvider(p.patientId));
      pendingTasksCount += loops.where((l) => l.isOpen).length;
    }

    // Filtered patient list
    final filteredPatients = patients.where((p) {
      final loops = ref.watch(patientLoopsProvider(p.patientId));
      final hasOpen = loops.any((l) => l.isOpen);
      if (_activeFilterIndex == 1) return hasOpen;
      if (_activeFilterIndex == 2) return !hasOpen;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF070C18),
      body: SafeArea(
        child: Column(
          children: [
            // Top Clean Header
            _buildCleanHeader(context, currentWard.name, authStaff),

            // Scrollable Dashboard Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGreetingSection(nurseName),
                    const SizedBox(height: 14),
                    if (currentWard.wardId.isEmpty)
                      _buildNoWardPanel(authStaff)
                    else if (ref.watch(wardContextNeedsConfirmationProvider))
                      _buildWardConfirmationPanel(currentWard.name)
                    else if (boardState.isLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (boardState.hasError)
                      _buildBoardLoadError(boardState.error)
                    else ...[
                      _buildAtAGlanceCards(
                        totalPatients,
                        pendingTasksCount,
                        completedTasksCount,
                      ),
                      const SizedBox(height: 14),
                      _buildFilterRow(totalPatients, pendingTasksCount, 3),
                      const SizedBox(height: 14),
                      _buildPatientListSection(
                        filteredPatients,
                        doctorMap,
                        hasAnyPatients: patients.isNotEmpty,
                      ),
                      const SizedBox(height: 18),
                      _buildWardResponsibilitiesGrid(roster),
                      const SizedBox(height: 18),
                      _buildShiftHandoffBanner(context),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),

            // 5-Tab Bottom Navigation Bar
            _buildBottomNavigation(context),
          ],
        ),
      ),
    );
  }

  Widget _buildNoWardPanel(StaffProfile? staff) {
    final isChargeNurse = staff?.isChargeNurse ?? false;
    return _contextPanel(
      title: 'No ward assigned for this shift',
      message: isChargeNurse
          ? 'Choose the ward you are coordinating to load its board.'
          : 'You do not have a ward assignment for this shift. Please contact the Charge Nurse.',
      action: isChargeNurse
          ? OutlinedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const WardSelectionDialog(),
              ),
              child: const Text('Choose ward'),
            )
          : null,
    );
  }

  Widget _buildWardConfirmationPanel(String wardName) => _contextPanel(
    title: 'Confirm $wardName',
    message: 'Confirm this saved ward before viewing its current board.',
    action: Wrap(
      spacing: 10,
      children: [
        OutlinedButton(
          onPressed: () => ref
              .read(wardContextNeedsConfirmationProvider.notifier)
              .setNeedsConfirmation(false),
          child: const Text('Confirm ward'),
        ),
        TextButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const WardSelectionDialog(),
          ),
          child: const Text('Change ward'),
        ),
      ],
    ),
  );

  Widget _buildBoardLoadError(Object? error) => _contextPanel(
    title: 'Ward board unavailable',
    message: 'The current board could not be loaded. Please try again.\n$error',
    action: TextButton(
      onPressed: () => ref.invalidate(wardBoardProvider),
      child: const Text('Try again'),
    ),
  );

  Widget _contextPanel({
    required String title,
    required String message,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1425),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2C48)),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action,
          ],
        ],
      ),
    );
  }

  // ==========================================
  // 1. CLEAN HEADER
  // ==========================================
  Widget _buildCleanHeader(
    BuildContext context,
    String wardName,
    StaffProfile? authStaff,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1224),
        border: Border(bottom: BorderSide(color: Color(0xFF16233B), width: 1)),
      ),
      child: Row(
        children: [
          // ORAVI Logo Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.monitor_heart,
              color: Color(0xFF38BDF8),
              size: 18,
            ),
          ),
          const SizedBox(width: 8),

          // Title & Hospital Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ORAVI',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Jaramanda Hospital · $wardName',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Profile Avatar with Quick Lock Station
          InkWell(
            onTap: () => _showLockDialog(context, ref, authStaff),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: CircleAvatar(
                radius: 13,
                backgroundColor: const Color(0xFF1E293B),
                child: Text(
                  authStaff?.initials ?? 'NX',
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 2. GREETING & SHIFT SECTION
  // ==========================================
  Widget _buildGreetingSection(String nurseName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Good morning, $nurseName',
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          "You've got this. Here's your shift overview.",
          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Date Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF10192E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E2C48), width: 0.8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 13,
                    color: Color(0xFF38BDF8),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Fri, 30 Oct 2026',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFCBD5E1),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Shift Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF10192E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E2C48), width: 0.8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wb_sunny_outlined,
                    size: 13,
                    color: Color(0xFFFBBF24),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Day Shift  07:00 – 19:00',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFCBD5E1),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // 3. AT A GLANCE KPI CARDS
  // ==========================================
  Widget _buildAtAGlanceCards(
    int patientCount,
    int pendingTasks,
    int completedToday,
  ) {
    return Row(
      children: [
        // My Patients
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1A33),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF1E3A8A).withValues(alpha: 0.6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.people,
                      size: 16,
                      color: Color(0xFF38BDF8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$patientCount',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Text(
                      'My Patients',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF38BDF8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: 12,
                      color: Color(0xFF38BDF8),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Pending Tasks
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF191E2A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFEAB308).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$pendingTasks',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Text(
                      'Pending Tasks',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: 12,
                      color: Color(0xFFF59E0B),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Completed Today
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D2122),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Color(0xFF10B981),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$completedToday',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Text(
                      'Completed',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF34D399),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: 12,
                      color: Color(0xFF34D399),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 4. FILTER PILLS & SEARCH / FILTER ROW
  // ==========================================
  Widget _buildFilterRow(int allCount, int pendingCount, int completedCount) {
    return Row(
      children: [
        // All Filter Pill
        _buildFilterPill(
          label: 'All ($allCount)',
          isSelected: _activeFilterIndex == 0,
          onTap: () => setState(() => _activeFilterIndex = 0),
        ),
        const SizedBox(width: 6),
        // Pending Filter Pill
        _buildFilterPill(
          label: 'Pending ($pendingCount)',
          isSelected: _activeFilterIndex == 1,
          onTap: () => setState(() => _activeFilterIndex = 1),
        ),
        const SizedBox(width: 6),
        // Completed Filter Pill
        _buildFilterPill(
          label: 'Completed ($completedCount)',
          isSelected: _activeFilterIndex == 2,
          onTap: () => setState(() => _activeFilterIndex = 2),
        ),

        const Spacer(),

        // Search Button
        InkWell(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const WardSearchSheet(),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF10192E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E2C48)),
            ),
            child: const Icon(Icons.search, size: 16, color: Color(0xFF94A3B8)),
          ),
        ),
        const SizedBox(width: 6),

        // Filter / Sort Options Button
        InkWell(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Filtering by assigned shift: Day Shift (Beds 1–10)',
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF10192E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E2C48)),
            ),
            child: const Icon(Icons.tune, size: 16, color: Color(0xFF94A3B8)),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF10192E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF38BDF8)
                : const Color(0xFF1E2C48),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 5. MY PATIENTS LIST
  // ==========================================
  Widget _buildPatientListSection(
    List<PatientStateProjection> patients,
    Map<String, String> doctorMap,
    {
    required bool hasAnyPatients,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'My Patients',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Row(
              children: [
                const Text(
                  'Sort by Bed',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 14,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (patients.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0C1425),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E2C48)),
            ),
            child: Text(
              hasAnyPatients
                  ? 'No patients match the selected filter.'
                  : 'You have no patients assigned to your ward for this shift.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
          )
        else
          ...patients.map((patient) {
            final rawBed = patient.bedNumber.replaceAll(RegExp(r'[^0-9]'), '');
            final bedDisplay = rawBed.isEmpty
                ? patient.bedNumber
                : rawBed.padLeft(2, '0');
            final doctor =
                doctorMap[patient.bedNumber] ??
                doctorMap[rawBed] ??
                'Doctor not assigned';
            return _buildPatientCard(patient, bedDisplay, doctor);
          }),
      ],
    );
  }

  Widget _buildPatientCard(
    PatientStateProjection patient,
    String bedDisplay,
    String doctor,
  ) {
    final loops = ref.watch(patientLoopsProvider(patient.patientId));
    final openLoops = loops.where((l) => l.isOpen).toList();

    // Determine status indicators matching the user's uploaded mockup:
    // Red for Attention (critical open loops or postoperative)
    // Amber for Pending (routine/urgent open loops)
    // Green for All Clear (zero open loops)
    Color stripeColor;
    Widget statusBadge;

    if (openLoops.any((l) => l.urgency == LoopUrgency.critical)) {
      stripeColor = const Color(0xFFEF4444);
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF450A0A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.6),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning, size: 11, color: Color(0xFFEF4444)),
            SizedBox(width: 4),
            Text(
              'Attention',
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFFFCA5A5),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else if (openLoops.isNotEmpty) {
      stripeColor = const Color(0xFFF59E0B);
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF451A03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, size: 6, color: Color(0xFFF59E0B)),
            const SizedBox(width: 4),
            Text(
              '${openLoops.length} pending',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFFFDE68A),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else {
      stripeColor = const Color(0xFF10B981);
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF064E3B).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.5),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 11, color: Color(0xFF34D399)),
            SizedBox(width: 4),
            Text(
              'All clear',
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFF34D399),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1729),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1B2B48), width: 1.0),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PatientDetailScreen(patient: patient),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                // Left Vertical Status Indicator Stripe
                Container(
                  width: 3.5,
                  height: 48,
                  decoration: BoxDecoration(
                    color: stripeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),

                // 2-Digit Bed Box
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF16233B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF293B5C),
                      width: 0.8,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Semantics(
                    label: patient.bedNumber,
                    child: Text(
                      bedDisplay,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Patient Info (Initials, Age/Sex, Diagnosis, Attending Doctor)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            patient.patientInitials,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${patient.age}y / ${patient.sex}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const SizedBox(height: 2),
                      Text(
                        patient.shortAdmittingNote,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFCBD5E1),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 12,
                            color: Color(0xFF38BDF8),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            doctor,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF38BDF8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Right Status Badge + Navigation Arrow
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    statusBadge,
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 6. WARD RESPONSIBILITIES (2-COLUMN GRID WITH 1-TAP CALL/MESSAGE)
  // ==========================================
  Widget _buildWardResponsibilitiesGrid(WardSupportRoster roster) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        const Row(
          children: [
            Icon(Icons.assignment_outlined, size: 16, color: Color(0xFF38BDF8)),
            SizedBox(width: 6),
            Text(
              'Ward Responsibilities',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 2x3 Grid of Responsibilities
        Row(
          children: [
            Expanded(
              child: _buildResponsibilityCard(
                title: 'Ward Manager',
                nurseName: roster.wardManager.isNotEmpty ? roster.wardManager : '-',
                icon: Icons.person,
                iconColor: const Color(0xFF38BDF8),
                phone: '',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildResponsibilityCard(
                title: 'Team Leader',
                nurseName: roster.teamLeader.isNotEmpty ? roster.teamLeader : '-',
                icon: Icons.people_outline,
                iconColor: const Color(0xFFA855F7),
                phone: '',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildResponsibilityCard(
                title: 'Duty Leader',
                nurseName: roster.dutyLeader.isNotEmpty ? roster.dutyLeader : '-',
                icon: Icons.person_outline,
                iconColor: const Color(0xFFF97316),
                phone: '',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildResponsibilityCard(
                title: 'Discharge Nurse',
                nurseName: roster.dischargeNurse.isNotEmpty ? roster.dischargeNurse : '-',
                icon: Icons.assignment_turned_in_outlined,
                iconColor: const Color(0xFF34D399),
                phone: '',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildResponsibilityCard(
                title: 'Patient Care Attendant',
                nurseName: roster.pcaDay.isNotEmpty ? roster.pcaDay : '-',
                icon: Icons.person_pin_outlined,
                iconColor: const Color(0xFF2DD4BF),
                phone: '',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildResponsibilityCard(
                title: 'Nurse In-Charge',
                nurseName: roster.inchargeNurseDay.isNotEmpty ? roster.inchargeNurseDay : '-',
                icon: Icons.shield_outlined,
                iconColor: const Color(0xFF818CF8),
                phone: '',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResponsibilityCard({
    required String title,
    required String nurseName,
    required IconData icon,
    required Color iconColor,
    required String phone,
  }) {
    return InkWell(
      onTap: phone.isEmpty ? null : () => _showContactActionSheet(
        roleTitle: title,
        nurseName: nurseName,
        icon: icon,
        iconColor: iconColor,
        phoneNumber: phone,
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1729),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1B2B48), width: 0.8),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 14, color: iconColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    nurseName,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // ONE-TAP CALL OR MESSAGE MODAL SHEET
  // ==========================================
  void _showContactActionSheet({
    required String roleTitle,
    required String nurseName,
    required IconData icon,
    required Color iconColor,
    required String phoneNumber,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: Color(0xFF1E293B), width: 1.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF475569),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Staff Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: iconColor.withValues(alpha: 0.15),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nurseName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          roleTitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: iconColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF064E3B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'On Duty',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF34D399),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Full-Width One-Tap Call Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.call, size: 18),
                  label: Text(
                    'Call $nurseName ($phoneNumber)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Connecting call to $nurseName ($roleTitle)...',
                        ),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),

              // Full-Width One-Tap Message Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(
                      color: Color(0xFF38BDF8),
                      width: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text(
                    'Message $nurseName',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _showQuickMessageDialog(nurseName, roleTitle);
                  },
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showQuickMessageDialog(String nurseName, String roleTitle) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF1E293B)),
        ),
        title: Row(
          children: [
            const Icon(Icons.message, color: Color(0xFF38BDF8), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Message $nurseName',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To $roleTitle on duty:',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Type clinical query or handover note...',
                hintStyle: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                ),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Quick preset pills
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  label: const Text(
                    'Bed 2 review',
                    style: TextStyle(fontSize: 10, color: Color(0xFF38BDF8)),
                  ),
                  backgroundColor: const Color(0xFF1E293B),
                  onPressed: () => controller.text =
                      'Please assist with Bed 2 urgent review.',
                ),
                ActionChip(
                  label: const Text(
                    'Meds sign-off',
                    style: TextStyle(fontSize: 10, color: Color(0xFF38BDF8)),
                  ),
                  backgroundColor: const Color(0xFF1E293B),
                  onPressed: () => controller.text =
                      'Need second sign-off on IV antibiotics.',
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Message sent to $nurseName!')),
              );
            },
            child: const Text(
              'Send Message',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 7. SHIFT HANDOFF ACTION BANNER
  // ==========================================
  Widget _buildShiftHandoffBanner(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HandoffWizardScreen()),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.swap_horiz, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shift Handoff',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Review outstanding tasks and prepare for the next shift',
                        style: TextStyle(
                          color: Color(0xFFBAE6FD),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 8. 5-TAB BOTTOM NAVIGATION
  // ==========================================
  Widget _buildBottomNavigation(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B1224),
        border: Border(top: BorderSide(color: Color(0xFF16233B), width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _activeNavIndex,
        onTap: (index) {
          setState(() => _activeNavIndex = index);
          if (index == 1) {
            // Patients tab
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Displaying active ward patients.')),
            );
          } else if (index == 2) {
            // Tasks tab
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('2 open tasks across your beds.')),
            );
          } else if (index == 3) {
            // Handoff tab
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HandoffWizardScreen()),
            );
          } else if (index == 4) {
            // More tab (Access Central Whiteboard & Ward Switcher)
            _showMoreMenu(context);
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: const Color(0xFF38BDF8),
        unselectedItemColor: const Color(0xFF64748B),
        selectedFontSize: 10,
        unselectedFontSize: 10,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          const BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: 'Patients',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.assignment_outlined),
                Positioned(
                  top: -2,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '2',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            label: 'Tasks',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.swap_horiz),
            label: 'Handoff',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: Color(0xFF1E293B))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.dashboard_customize,
                color: Color(0xFF38BDF8),
              ),
              title: const Text(
                'Ward Management & Nurse Allocation Board',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              subtitle: const Text(
                'View master whiteboard beds 1–10 and shift roster',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: Color(0xFF94A3B8),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DigitalWhiteboardScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.apartment, color: Color(0xFF34D399)),
              title: const Text(
                'Switch Active Hospital Ward',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              subtitle: const Text(
                'Select another ward with search autofilter',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: Color(0xFF94A3B8),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                showDialog(
                  context: context,
                  builder: (_) => const WardSelectionDialog(),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Color(0xFFEF4444)),
              title: const Text(
                'Lock Station',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              subtitle: const Text(
                'Return to Digital ID badge screen',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                ref.read(authControllerProvider.notifier).logout();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const DigitalIdLockscreen(),
                  ),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLockDialog(
    BuildContext context,
    WidgetRef ref,
    StaffProfile? staff,
  ) {
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
                staff?.initials ?? 'NX',
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                staff?.name ?? 'Nurse',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Role: ${staff?.formattedRole ?? 'Ward Nurse'} • Staff ID: ${staff?.staffId ?? '-'}\n\nLock station or switch to another nurse?',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
            ),
            icon: const Icon(Icons.lock, size: 16, color: Colors.white),
            label: const Text(
              'Lock Station',
              style: TextStyle(color: Colors.white),
            ),
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

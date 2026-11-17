import 'dart:async';

import 'package:flutter/material.dart';

import 'admin/dev_admin_dashboard_screen.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/loop_enums.dart';
import '../domain/models/staff_profile.dart';
import 'communications/staff_communications_screen.dart';
import 'communications/personal_inbox.dart';
import 'notebook/personal_notebook_screen.dart';
import 'whiteboard/ward_transfer_screen.dart';
import '../domain/projections/projections.dart';
import '../domain/models/clinical_ritual.dart';
import '../data/database/database_provider.dart';
import '../data/sync/sync_engine.dart';
import 'handoff_wizard_screen.dart';
import 'lockscreen/digital_id_lockscreen.dart';
import 'patient_detail_screen.dart';
import 'providers/auth_providers.dart';
import 'providers/ward_providers.dart';
import 'providers/whiteboard_providers.dart';
import 'providers/ward_context_providers.dart';
import 'providers/clinical_assignment_provider.dart';
import 'providers/dashboard_issue_summary.dart';
import 'whiteboard/digital_whiteboard_screen.dart';
import 'widgets/ward_search_sheet.dart';
import 'widgets/ward_selection_dialog.dart';
import '../data/clinical_ritual_service.dart';
import '../data/ward_board_service.dart';
import 'clinical_ritual_room_screen.dart';
import 'clinical_ritual_review_screen.dart';

final clinicalRitualAlertsProvider =
    FutureProvider.autoDispose<List<ClinicalRitual>>((ref) async {
      final token = ref.watch(authAccessTokenProvider);
      if (token == null) return const [];
      return ClinicalRitualService(
        WardBoardService(
          getAccessToken: () => ref.read(authAccessTokenProvider),
        ),
      ).activeAlerts();
    });

/// Pixel-perfect implementation of the Nurse Dashboard designed to eliminate clutter:
/// - Clean Header with hospital name, sync status, notifications, and profile avatar.
/// - At-a-glance shift overview KPI cards (My Patients, Pending Tasks, Completed Today).
/// - Quick filter pills (All, Pending, Completed) with search and filter.
/// - Prioritized patient list with status indicator stripes, bed numbers, diagnoses, doctors, and urgency badges.
/// - Prominent Shift Handoff action banner.
/// - 5-tab Bottom Navigation bar.
class WardBoardScreen extends ConsumerStatefulWidget {
  const WardBoardScreen({super.key});

  @override
  ConsumerState<WardBoardScreen> createState() => _WardBoardScreenState();
}

class _WardBoardScreenState extends ConsumerState<WardBoardScreen>
    with WidgetsBindingObserver {
  Timer? _assignmentTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAssignment());
    _assignmentTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshAssignment(),
    );
  }

  void _refreshAssignment() {
    if (!mounted ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    setState(
      () {},
    ); // Refresh local date and greeting independently of the assigned shift.
    unawaited(ref.read(clinicalAssignmentRefreshProvider.notifier).refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAssignment();
  }

  @override
  void dispose() {
    _assignmentTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  int _activeNavIndex = 0;
  int _activeFilterIndex = 0; // 0: All, 1: Pending, 2: Completed

  @override
  Widget build(BuildContext context) {
    final authStaff = ref.watch(authenticatedStaffProvider);
    final offlineSession = ref.watch(offlineSessionProvider);
    if (authStaff?.role == 'dev_admin') {
      return const DevAdminDashboardScreen();
    }
    if (authStaff?.isClinical != true) {
      return const StaffCommunicationsScreen();
    }
    final patients = ref.watch(wardPatientsProvider);
    final currentWard = ref.watch(selectedWardProvider);
    final accessiblePatientIds = ref.watch(
      personallyAssignedPatientIdsProvider,
    );
    final whiteboardBeds = ref.watch(whiteboardAssignmentsProvider);
    final boardState = ref.watch(wardBoardProvider);
    final staffState = ref.watch(boardStaffListProvider);
    final carriedIssuesState = ref.watch(carriedForwardIssuesProvider('owned'));
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
    final myPatients = patients
        .where((patient) => accessiblePatientIds.contains(patient.patientId))
        .toList();
    final totalPatients = myPatients.length;
    final summary = DashboardIssueSummary({
      for (final p in myPatients)
        p.patientId: ref.watch(patientLoopsProvider(p.patientId)),
    });

    // Filtered patient list
    final filteredPatients = myPatients.where((p) {
      if (_activeFilterIndex == 1) {
        return summary.pendingPatients.contains(p.patientId);
      }
      if (_activeFilterIndex == 2) {
        return summary.completedPatients.contains(p.patientId);
      }
      return true;
    }).toList();

    final homeIssues =
        <({PatientStateProjection patient, LoopStateProjection issue})>[
          for (final patient in myPatients)
            for (final issue in ref.watch(
              patientLoopsProvider(patient.patientId),
            ))
              if (issue.isOpen) (patient: patient, issue: issue),
        ]..sort((left, right) {
          final urgencyOrder = _urgencyRank(
            right.issue.urgency,
          ).compareTo(_urgencyRank(left.issue.urgency));
          if (urgencyOrder != 0) return urgencyOrder;
          return right.issue.updatedAt.compareTo(left.issue.updatedAt);
        });
    final pendingPersonalTasks = ref.watch(pendingPersonalTasksProvider);

    final wardDestination = SafeArea(
      child: Column(
        children: [
          _buildCleanHeader(context, currentWard.name, authStaff),
          if (offlineSession) _buildOfflineSessionBanner(),
          Expanded(
            child: SingleChildScrollView(
              key: PageStorageKey('clinician-tab-$_activeNavIndex'),
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 8.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_activeNavIndex == 0) ...[
                    _buildGreetingSection(nurseName, currentWard.name),
                    const SizedBox(height: 18),
                    _buildNeedsAttention(homeIssues),
                    const SizedBox(height: 18),
                  ] else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'My Patients',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (currentWard.wardId.isEmpty) ...[
                    if (_activeNavIndex == 0) _buildHomeEmptyState(),
                    _buildNoWardPanel(authStaff),
                  ] else if (authStaff?.isChargeNurse == true &&
                      ref.watch(wardContextNeedsConfirmationProvider))
                    _buildWardConfirmationPanel(currentWard.name)
                  else if (boardState.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (boardState.hasError)
                    _buildBoardLoadError(boardState.error)
                  else ...[
                    if (_activeNavIndex == 0 && totalPatients == 0)
                      _buildHomeEmptyState(),
                    if (_activeNavIndex == 0) ...[
                      _buildAtAGlanceCards(
                        totalPatients,
                        summary.openIssues,
                        pendingPersonalTasks,
                      ),
                      const SizedBox(height: 20),
                      _sectionHeading(
                        'Shift workflow',
                        'Prepare, coordinate, and hand over safely',
                      ),
                      const SizedBox(height: 10),
                      _buildShiftHandoffBanner(context),
                      const SizedBox(height: 8),
                      const WardTransferNotice(),
                      const SizedBox(height: 18),
                      _buildClinicalRitualNotifications(context),
                      const NotebookReminderBanner(),
                      _buildCarriedForwardIssues(carriedIssuesState),
                    ] else if (_activeNavIndex == 1) ...[
                      if (totalPatients > 0)
                        _buildFilterRow(
                          totalPatients,
                          summary.pendingPatients.length,
                          summary.completedPatients.length,
                        ),
                      const SizedBox(height: 14),
                      _buildPatientListSection(
                        filteredPatients,
                        doctorMap,
                        hasAnyPatients: myPatients.isNotEmpty,
                      ),
                      const SizedBox(height: 18),
                    ],
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF070C18),
      body: switch (_activeNavIndex) {
        2 => const StaffCommunicationsScreen(),
        3 => const PersonalNotebookScreen(),
        4 => _buildMoreDestination(context, authStaff),
        _ => wardDestination,
      },
      bottomNavigationBar: _buildBottomNavigation(context),
    );
  }

  Widget _buildOfflineSessionBanner() => Container(
    width: double.infinity,
    color: const Color(0xFF78350F),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: const Row(
      children: [
        Icon(Icons.cloud_off, color: Color(0xFFFDE68A), size: 19),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            'Offline access · showing saved data. Calls, rituals, and server actions need a connection.',
            style: TextStyle(color: Color(0xFFFFFBEB), fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _buildCarriedForwardIssues(
    AsyncValue<List<Map<String, dynamic>>> state,
  ) {
    if (state.isLoading) return const SizedBox.shrink();
    if (state.hasError) {
      return Card(
        child: ListTile(
          title: const Text('Carried Medical Issues could not be loaded'),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(carriedForwardIssuesProvider('owned')),
          ),
        ),
      );
    }

    final issues = (state.asData?.value ?? const [])
        .where((issue) => issue['is_open'] == true)
        .toList();
    if (issues.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Medical Issues assigned to you',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final issue in issues)
              ListTile(
                leading: const Icon(Icons.assignment_late_outlined),
                title: Text(issue['title'] as String? ?? 'Medical Issue'),
                subtitle: Text(
                  'Assigned issue · ${issue['urgency']} urgency · issue thread access only',
                ),
                onTap: () => _openCarriedForwardIssue(issue),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCarriedForwardIssue(Map<String, dynamic> issue) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final patientId = issue['patient_id'] as String;
      final loopId = issue['loop_id'] as String;
      final carriedIssues = await ref
          .read(wardBoardServiceProvider)
          .getCarriedForwardIssues();
      final carriedIssue = carriedIssues
          .where((candidate) => candidate['loop_id'] == loopId)
          .firstOrNull;
      if (carriedIssue == null || carriedIssue['patient_id'] != patientId) {
        throw StateError(
          'This Medical Issue is no longer assigned to your account.',
        );
      }

      final rawEvents = carriedIssue['events'];
      if (rawEvents is! List) {
        throw const FormatException(
          'The server returned an invalid carried Medical Issue thread.',
        );
      }
      final issueEvents = rawEvents.map((event) {
        if (event is! Map<String, dynamic>) {
          throw const FormatException(
            'The server returned an invalid Medical Issue event.',
          );
        }
        return event;
      }).toList();
      await ref.read(localDatabaseProvider).insertRemoteEvents(issueEvents);
      await ref.read(localWardRepositoryProvider).reloadFromDatabase();
      ref.read(wardControllerProvider.notifier).refresh();
      final loop = ref
          .read(localWardRepositoryProvider)
          .getLoopsForPatient(patientId)
          .where((candidate) => candidate.loopId == loopId)
          .firstOrNull;
      if (loop == null) {
        throw StateError(
          'The assigned Medical Issue thread is not available on this device yet. Try again when online.',
        );
      }
      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => PatientDetailScreen(
            patient: PatientStateProjection(
              patientId: patientId,
              wardId: issue['ward_id'] as String? ?? '',
              bedNumber: 'Carried issue',
              patientInitials: '',
              age: 0,
              sex: '',
              shortAdmittingNote: '',
              admittedAt: loop.createdAt,
              updatedAt: loop.updatedAt,
            ),
            issueOnlyLoopIds: {loopId},
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open the assigned issue: $error')),
      );
    }
  }

  Widget _buildHomeEmptyState() => _contextPanel(
    title: 'Nothing on your Home page yet',
    message:
        'Your patient overview will appear here when patients are assigned. '
        'Reminders and team updates appear above when available.',
    action: TextButton(
      onPressed: () => setState(() => _activeNavIndex = 1),
      child: const Text('View my patients'),
    ),
  );

  Widget _buildNoWardPanel(StaffProfile? staff) {
    final isChargeNurse = staff?.isChargeNurse ?? false;
    return _contextPanel(
      title: _activeNavIndex == 1
          ? 'You have no patients'
          : staff?.isDoctorOnCall == true
          ? 'No patients assigned to you'
          : 'No ward assigned for this shift',
      message: isChargeNurse
          ? 'Choose the ward you are coordinating to load its board.'
          : staff?.isDoctorOnCall == true
          ? 'Patients will appear here when the Charge Nurse assigns them to you.'
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
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    );
  }

  Widget _buildClinicalRitualNotifications(BuildContext context) {
    return ref
        .watch(clinicalRitualAlertsProvider)
        .when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (alerts) {
            if (alerts.isEmpty) return const SizedBox.shrink();
            final rituals = alerts.take(3).toList();
            return Card(
              color: const Color(0xFF123047),
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(
                      Icons.groups_2_outlined,
                      color: Color(0xFF67E8F9),
                    ),
                    title: Text(
                      'Clinical Rituals',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'Invitations, active rituals, and summaries to review',
                      style: TextStyle(color: Color(0xFFBAE6FD)),
                    ),
                  ),
                  ...rituals.map(
                    (ritual) => ListTile(
                      dense: true,
                      title: Text(
                        ritual.title,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        ritual.alertType == 'review'
                            ? 'Summary ready for your review'
                            : ritual.alertType == 'invitation'
                            ? 'Invitation to join · ${ritual.ritualType.toUpperCase()}'
                            : '${ritual.ritualType.toUpperCase()} · ${ritual.status}',
                        style: const TextStyle(color: Color(0xFFBAE6FD)),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Color(0xFFBAE6FD),
                      ),
                      onTap: () => _openRitual(context, ritual),
                    ),
                  ),
                ],
              ),
            );
          },
        );
  }

  Future<void> _openRitual(BuildContext context, ClinicalRitual ritual) async {
    final scheduledFor = DateTime.tryParse(ritual.scheduledFor ?? '');
    if (scheduledFor != null && scheduledFor.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This ritual is scheduled for ${scheduledFor.toLocal()}',
          ),
        ),
      );
      return;
    }
    if (ritual.alertType == 'review' ||
        ritual.status == 'draft_ready' ||
        ritual.status == 'approved' ||
        ritual.recordingStatus == 'transcribed') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClinicalRitualReviewScreen(ritualId: ritual.ritualId),
        ),
      );
      ref.invalidate(clinicalRitualAlertsProvider);
      return;
    }
    if (ritual.status == 'requested' ||
        ritual.status == 'in_progress' ||
        ritual.recordingStatus == 'not_started') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClinicalRitualRoomScreen(
            ritualId: ritual.ritualId,
            invitation: ritual.participantStatus == 'invited',
          ),
        ),
      );
      ref.invalidate(clinicalRitualAlertsProvider);
    }
  }

  // ==========================================
  // 1. CLEAN HEADER
  // ==========================================
  Widget _buildCleanHeader(
    BuildContext context,
    String wardName,
    StaffProfile? authStaff,
  ) {
    final syncStatus = ref.watch(syncStatusProvider).asData?.value;
    final isOffline =
        syncStatus?.networkAvailable == false ||
        syncStatus?.state == SyncState.offline;
    final syncLabel = syncStatus?.networkAvailable == null
        ? 'Checking connection'
        : syncStatus?.state == SyncState.syncing
        ? 'Syncing'
        : isOffline
        ? 'Offline'
        : syncStatus?.state == SyncState.error
        ? 'Sync issue'
        : 'Online';
    final syncColor = syncStatus?.networkAvailable == null
        ? const Color(0xFF94A3B8)
        : isOffline
        ? const Color(0xFFFBBF24)
        : syncStatus?.state == SyncState.error
        ? const Color(0xFFF87171)
        : const Color(0xFF4ADE80);
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
                  'Oravi Hospital · $wardName',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.circle, size: 7, color: syncColor),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '$syncLabel · Last synced ${_formatSyncTime(syncStatus?.lastSyncedAt)}${(syncStatus?.pendingCount ?? 0) > 0 ? ' · ${syncStatus!.pendingCount} pending' : ''}',
                        style: TextStyle(color: syncColor, fontSize: 9),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sync now',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          unawaited(ref.read(syncEngineProvider).syncAll()),
                      icon: const Icon(
                        Icons.sync,
                        size: 17,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'Open inbox',
            onPressed: () => setState(() => _activeNavIndex = 2),
            icon: const InboxBadge(),
          ),
          const SizedBox(width: 2),

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

  String _formatSyncTime(DateTime? value) {
    if (value == null) return 'never';
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    final today = DateTime.now();
    if (local.year == today.year &&
        local.month == today.month &&
        local.day == today.day) {
      return '$hour:$minute $period';
    }
    return '${local.day}/${local.month} $hour:$minute $period';
  }

  // ==========================================
  // 2. GREETING & SHIFT SECTION
  // ==========================================
  int _urgencyRank(LoopUrgency urgency) => switch (urgency) {
    LoopUrgency.critical => 3,
    LoopUrgency.urgent => 2,
    LoopUrgency.routine => 1,
  };

  Widget _buildGreetingSection(String nurseName, String wardName) {
    final now = DateTime.now();
    final shift = ref.watch(selectedShiftTypeProvider);
    final hasWard = ref.watch(selectedWardProvider).wardId.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MaterialLocalizations.of(context).formatFullDate(now).toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${clinicalGreeting(now)}, $nurseName',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 22,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF101D33),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1D3552)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  shift == 'night'
                      ? Icons.nights_stay_outlined
                      : Icons.medical_services_outlined,
                  color: const Color(0xFF38BDF8),
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ON SHIFT',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${clinicalShiftLabel(shift, hasWard: hasWard)} · ${wardName.isEmpty ? 'Ward not selected' : wardName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 7, color: Color(0xFF4ADE80)),
                  SizedBox(width: 5),
                  Text(
                    'Active',
                    style: TextStyle(
                      color: Color(0xFF86EFAC),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNeedsAttention(
    List<({PatientStateProjection patient, LoopStateProjection issue})> items,
  ) {
    final top = items.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Needs attention',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (items.length > 1)
              TextButton(
                onPressed: () => setState(() {
                  _activeNavIndex = 1;
                  _activeFilterIndex = 1;
                }),
                child: Text('View all (${items.length})'),
              ),
          ],
        ),
        const SizedBox(height: 9),
        if (top == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D2122),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.35),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Color(0xFF34D399)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No open clinical issues need your attention.',
                    style: TextStyle(
                      color: Color(0xFFD1FAE5),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          _attentionCard(top.patient, top.issue),
      ],
    );
  }

  Widget _attentionCard(
    PatientStateProjection patient,
    LoopStateProjection issue,
  ) {
    final critical = issue.urgency == LoopUrgency.critical;
    final accent = critical
        ? const Color(0xFFEF4444)
        : issue.urgency == LoopUrgency.urgent
        ? const Color(0xFFF59E0B)
        : const Color(0xFF38BDF8);
    final label = critical
        ? 'CRITICAL'
        : issue.urgency == LoopUrgency.urgent
        ? 'URGENT'
        : 'OPEN';

    return Container(
      decoration: BoxDecoration(
        color: critical ? const Color(0xFF231318) : const Color(0xFF211C14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PatientDetailScreen(
                patient: patient,
                initialExpandedLoopId: issue.loopId,
              ),
            ),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        critical
                            ? Icons.warning_amber_rounded
                            : Icons.monitor_heart_outlined,
                        color: accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${patient.bedNumber} · ${patient.patientInitials}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            patient.shortAdmittingNote,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: accent,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  issue.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (issue.description.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    issue.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${issue.currentOwnerRole.replaceAll('_', ' ')} · Updated ${_relativeTime(issue.updatedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'View issue',
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.chevron_right, color: accent, size: 18),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime value) {
    final difference = DateTime.now().difference(value.toLocal());
    if (difference.inMinutes < 1) return 'now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  Widget _sectionHeading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
      ),
    ],
  );

  Widget _buildAtAGlanceCards(
    int patientCount,
    int openIssues,
    int pendingTasks,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeading('At a glance', 'Your current clinical workload'),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _summaryCard(
              icon: Icons.people_outline_rounded,
              value: patientCount,
              label: 'Patients',
              color: const Color(0xFF38BDF8),
              onTap: () => setState(() => _activeNavIndex = 1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _summaryCard(
              icon: Icons.error_outline_rounded,
              value: openIssues,
              label: 'Open issues',
              color: const Color(0xFFF59E0B),
              onTap: () => setState(() {
                _activeNavIndex = 1;
                _activeFilterIndex = 1;
              }),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _summaryCard(
              icon: Icons.checklist_rounded,
              value: pendingTasks,
              label: 'Tasks',
              color: const Color(0xFF34D399),
              onTap: () => setState(() => _activeNavIndex = 3),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _summaryCard({
    required IconData icon,
    required int value,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) => Material(
    color: const Color(0xFF10192E),
    borderRadius: BorderRadius.circular(13),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        height: 96,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 19),
            const Spacer(),
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );

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
              SnackBar(
                content: Text(
                  'Filtering by assigned shift: ${clinicalShiftLabel(ref.read(selectedShiftTypeProvider), hasWard: ref.read(selectedWardProvider).wardId.isNotEmpty)}',
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
    Map<String, String> doctorMap, {
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
                  : 'You have no patients',
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
    final pendingTasks = ref.watch(pendingPersonalTasksProvider);
    final inbox = ref.watch(personalInboxProvider);
    final unread = inbox.asData?.value['unread_count'] as int? ?? 0;

    return NavigationBar(
      selectedIndex: _activeNavIndex,
      onDestinationSelected: (index) => setState(() => _activeNavIndex = index),
      backgroundColor: const Color(0xFF0B1224),
      indicatorColor: const Color(0xFF123047),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        const NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people_rounded),
          label: 'Patients',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const Icon(Icons.chat_bubble_outline_rounded),
          ),
          selectedIcon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const Icon(Icons.chat_bubble_rounded),
          ),
          label: 'Inbox',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: pendingTasks > 0,
            label: Text(pendingTasks > 99 ? '99+' : '$pendingTasks'),
            child: const Icon(Icons.checklist_outlined),
          ),
          selectedIcon: Badge(
            isLabelVisible: pendingTasks > 0,
            label: Text(pendingTasks > 99 ? '99+' : '$pendingTasks'),
            child: const Icon(Icons.checklist_rounded),
          ),
          label: 'Tasks',
        ),
        const NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view_rounded),
          label: 'More',
        ),
      ],
    );
  }

  Widget _buildMoreDestination(BuildContext context, StaffProfile? staff) =>
      Scaffold(
        backgroundColor: const Color(0xFF070C18),
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('More'),
              Text(
                'Ward tools and account',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _moreSectionLabel('Clinical workflows'),
            _moreDestinationTile(
              icon: Icons.swap_horiz_rounded,
              color: const Color(0xFF38BDF8),
              title: 'Shift handoff',
              subtitle: 'Review outstanding work and hand over safely',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const HandoffWizardScreen(),
                ),
              ),
            ),
            _moreDestinationTile(
              icon: Icons.dashboard_customize_outlined,
              color: const Color(0xFFA78BFA),
              title: 'Ward Management & Nurse Allocation Board',
              subtitle: 'Beds, assignments, and shift roster',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DigitalWhiteboardScreen(),
                ),
              ),
            ),
            if (staff?.isChargeNurse == true)
              _moreDestinationTile(
                icon: Icons.apartment_rounded,
                color: const Color(0xFF34D399),
                title: 'Switch Active Hospital Ward',
                subtitle: 'Choose another ward you coordinate',
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => const WardSelectionDialog(),
                ),
              ),
            const SizedBox(height: 22),
            _moreSectionLabel('Account and security'),
            _moreDestinationTile(
              icon: Icons.lock_outline_rounded,
              color: const Color(0xFFF87171),
              title: 'Lock Station',
              subtitle: 'Secure Oravi and return to Digital ID',
              onTap: () => _showLockDialog(context, ref, staff),
            ),
          ],
        ),
      );

  Widget _moreSectionLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    ),
  );

  Widget _moreDestinationTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      onTap: onTap,
      minTileHeight: 74,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );

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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/staff_profile.dart';
import '../../domain/models/whiteboard_models.dart';
import '../../domain/projections/projections.dart';
import '../providers/whiteboard_providers.dart';
import '../providers/auth_providers.dart';
import '../providers/ward_context_providers.dart';
import '../providers/ward_providers.dart';
import '../widgets/ward_support_roster_sheet.dart';
import '../widgets/ward_selection_dialog.dart';

/// Pixel-perfect implementation of the user's Ward Management & Nurse Allocation Board design
class DigitalWhiteboardScreen extends ConsumerStatefulWidget {
  const DigitalWhiteboardScreen({super.key});

  @override
  ConsumerState<DigitalWhiteboardScreen> createState() =>
      _DigitalWhiteboardScreenState();
}

class _DigitalWhiteboardScreenState
    extends ConsumerState<DigitalWhiteboardScreen> {
  int _activeNavIndex = 0;

  // Precise Column Widths & Grid Line styling matching user reference design
  static const double _kColBedWidth = 64.0;
  static const double _kColInitialsWidth = 72.0;
  static const double _kColDoctorWidth = 112.0;
  static const double _kColDayShiftWidth = 84.0;
  static const double _kColNightShiftWidth = 84.0;
  static const double _kTotalTableWidth =
      _kColBedWidth +
      _kColInitialsWidth +
      _kColDoctorWidth +
      _kColDayShiftWidth +
      _kColNightShiftWidth;

  static const Color _kGridBorderColor = Color(0xFF1E2C48);

  @override
  Widget build(BuildContext context) {
    final currentWard = ref.watch(selectedWardProvider);
    final beds = ref.watch(whiteboardAssignmentsProvider);
    final roster = ref.watch(wardSupportRosterProvider);
    final currentStaff = ref.watch(authenticatedStaffProvider);
    final boardState = ref.watch(wardBoardProvider);
    final staffState = ref.watch(boardStaffListProvider);
    final staff = staffState.asData?.value ?? const <StaffProfile>[];
    final isDayShift = ref.watch(selectedShiftTypeProvider) == 'day';
    final staffNames = {
      for (final member in staff) member.staffId: member.name,
    };

    // ONLY the Charge Nurse (or Ward Manager) has write permissions.
    // Everyone else has strictly one-tap read-only access.
    final hasWriteAccess = currentStaff?.isChargeNurse ?? false;

    // Calculate dynamic KPI counters
    final occupiedCount = beds
        .where(
          (b) =>
              b.patientInitials.trim().isNotEmpty &&
              b.patientInitials.trim() != '-',
        )
        .length;
    final availableCount = beds.length - occupiedCount;
    final dayNursesCount = beds
        .map((b) => b.dayShiftNurseId)
        .where((id) => id != null && id.isNotEmpty)
        .toSet()
        .length;
    final nightNursesCount = beds
        .map((b) => b.nightShiftNurseId)
        .where((id) => id != null && id.isNotEmpty)
        .toSet()
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Header
            _buildTopHeader(context, currentWard, hasWriteAccess, isDayShift),

            // 2. Scrollable Body: Table + KPI Cards + Responsibilities + Update Button
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (currentWard.wardId.isEmpty)
                        _buildNoWardMessage()
                      else if (ref.watch(wardContextNeedsConfirmationProvider))
                        _buildWardConfirmation(currentWard)
                      else if (boardState.isLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (boardState.hasError)
                        _buildBoardError(boardState.error)
                      else ...[
                        _buildMainTable(
                          beds,
                          roster,
                          hasWriteAccess,
                          staffNames,
                        ),
                        const SizedBox(height: 16),
                        _buildKpiCardsRow(
                          occupiedCount,
                          availableCount,
                          dayNursesCount,
                          nightNursesCount,
                        ),
                        const SizedBox(height: 16),
                        _buildBottomResponsibilitiesCard(
                          roster,
                          hasWriteAccess,
                          staffNames,
                        ),
                        const SizedBox(height: 16),
                        _buildUpdateAssignmentsButton(hasWriteAccess),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // 3. Bottom 5-Tab Navigation Bar
            _buildBottomNavigationBar(),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TOP HEADER
  // ==========================================
  Widget _buildTopHeader(
    BuildContext context,
    dynamic currentWard,
    bool hasWriteAccess,
    bool isDayShift,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Back Button
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Title and Tappable Ward Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ward Board',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Tappable Ward Switcher with search & autofilter
                    InkWell(
                      onTap: hasWriteAccess
                          ? () {
                              showDialog(
                                context: context,
                                builder: (_) => const WardSelectionDialog(),
                              );
                            }
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              currentWard.name,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            size: 16,
                            color: Color(0xFF94A3B8),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Sync Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF059669).withValues(alpha: 0.5),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 6, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text(
                      'Synced',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF34D399),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 13,
                      color: Color(0xFF34D399),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Date & Shift Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Date with Calendar Icon
              Row(
                children: [
                  Text(
                    DateTime.now().toLocal().toString().split(' ').first,
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 15,
                    color: Color(0xFF38BDF8),
                  ),
                ],
              ),

              // Shift Dropdown Toggle
              InkWell(
                onTap: () => ref
                    .read(selectedShiftTypeProvider.notifier)
                    .select(isDayShift ? 'night' : 'day'),
                child: Row(
                  children: [
                    Icon(
                      isDayShift
                          ? Icons.wb_sunny_outlined
                          : Icons.nightlight_round,
                      size: 14,
                      color: isDayShift
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF818CF8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isDayShift ? 'Day Shift' : 'Night Shift',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoWardMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1425),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGridBorderColor),
      ),
      child: const Text(
        'No ward is assigned to your account for this shift. Please contact the Charge Nurse.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
      ),
    );
  }

  Widget _buildWardConfirmation(dynamic currentWard) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1425),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGridBorderColor),
      ),
      child: Column(
        children: [
          Text(
            'Confirm ${currentWard.name} for this shift',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
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
        ],
      ),
    );
  }

  Widget _buildBoardError(Object? error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1425),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB91C1C)),
      ),
      child: Text(
        'The ward board could not be loaded. Please try again.\n$error',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
      ),
    );
  }

  // ==========================================
  // MAIN TABLE WITH BED ROWS & RESPONSIBILITIES
  // ==========================================
  Widget _buildMainTable(
    List<WhiteboardBedAssignment> beds,
    WardSupportRoster roster,
    bool hasWriteAccess,
    Map<String, String> staffNames,
  ) {
    final displayBeds = beds;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C1425),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGridBorderColor, width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _kTotalTableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Table Header Row with Crisp Grid Lines
                _buildTableHeader(),

                if (displayBeds.isNotEmpty &&
                    displayBeds.every(
                      (bed) =>
                          bed.patientId == null &&
                          bed.patientInitials.trim().isEmpty,
                    ))
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'No patients are assigned to this ward yet. The Charge Nurse can add patients to the board.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ),
                if (displayBeds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No beds are configured for this ward. Ask an administrator to configure the ward.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ),
                ...displayBeds.asMap().entries.map((entry) {
                  final index = entry.key;
                  final bed = entry.value;
                  final isLast = index == displayBeds.length - 1;
                  return _buildBedRow(
                    index,
                    bed,
                    hasWriteAccess,
                    isLast,
                    staffNames,
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: Color(0xFF94A3B8),
    );
    const subHeaderStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: Color(0xFF64748B),
    );

    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFF111C33),
        border: Border(
          bottom: BorderSide(color: _kGridBorderColor, width: 1.0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Bed / Room
          Container(
            width: _kColBedWidth,
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: _kGridBorderColor, width: 1.0),
              ),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Bed /\nRoom',
              textAlign: TextAlign.center,
              style: headerStyle,
            ),
          ),

          // 2. Patient Initials
          Container(
            width: _kColInitialsWidth,
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: _kGridBorderColor, width: 1.0),
              ),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Patient\nInitials',
              textAlign: TextAlign.center,
              style: headerStyle,
            ),
          ),

          // 3. Doctor
          Container(
            width: _kColDoctorWidth,
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: _kGridBorderColor, width: 1.0),
              ),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 12),
            child: const Text('Doctor', style: headerStyle),
          ),

          // 4 & 5. Nurses (Overarching header with Day Shift / Night Shift sub-columns)
          Container(
            width: _kColDayShiftWidth + _kColNightShiftWidth,
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: _kGridBorderColor, width: 1.0),
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _kGridBorderColor,
                          width: 1.0,
                        ),
                      ),
                    ),
                    child: const Text('Nurses', style: headerStyle),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: _kGridBorderColor,
                                width: 1.0,
                              ),
                            ),
                          ),
                          child: const Text('Day Shift', style: subHeaderStyle),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          alignment: Alignment.center,
                          child: const Text(
                            'Night Shift',
                            style: subHeaderStyle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBedRow(
    int index,
    WhiteboardBedAssignment bed,
    bool hasWriteAccess,
    bool isLastRow,
    Map<String, String> staffNames,
  ) {
    // Determine vertical status stripe color
    // Green = Occupied & Assigned, Yellow = Pending/Review, Dark Slate = Available
    final isAvailable =
        bed.patientInitials.trim() == '-' || bed.patientInitials.trim().isEmpty;
    final isPending = bed.status == 'pending';
    final stripeColor = isAvailable
        ? const Color(0xFF334155)
        : (isPending ? const Color(0xFFEAB308) : const Color(0xFF10B981));

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: index % 2 == 0
            ? const Color(0xFF0C1425)
            : const Color(0xFF0F182E),
        border: isLastRow
            ? null
            : const Border(
                bottom: BorderSide(color: _kGridBorderColor, width: 1.0),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Bed / Room (with Vertical Stripe & Pill)
          Container(
            width: _kColBedWidth,
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: _kGridBorderColor, width: 1.0),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Vertical Color Stripe Indicator
                Container(
                  width: 3.5,
                  height: 24,
                  decoration: BoxDecoration(
                    color: stripeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                // Bed Pill
                Container(
                  width: 32,
                  height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF334155),
                      width: 0.8,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      bed.bedNumber,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Patient Initials (Strictly Typed)
          Container(
            width: _kColInitialsWidth,
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: _kGridBorderColor, width: 1.0),
              ),
            ),
            child: InkWell(
              onTap: hasWriteAccess
                  ? () => _showStrictInitialsDialog(bed)
                  : () => _notifyReadOnly(),
              child: Center(
                child: Text(
                  bed.patientInitials.isNotEmpty ? bed.patientInitials : '-',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // 3. Doctor (Type / Autofilter)
          Container(
            width: _kColDoctorWidth,
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: _kGridBorderColor, width: 1.0),
              ),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: InkWell(
              onTap: hasWriteAccess
                  ? () => _showDoctorSelectionSheet(bed)
                  : () => _notifyReadOnly(),
              child: Text(
                bed.admittingDoctor.isNotEmpty
                    ? staffNames[bed.admittingDoctor] ?? bed.admittingDoctor
                    : '-',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFCBD5E1),
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // 4. Day Shift Nurse Pill
          Container(
            width: _kColDayShiftWidth,
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: _kGridBorderColor, width: 1.0),
              ),
            ),
            alignment: Alignment.center,
            child: _buildNursePill(
              nurseName: bed.dayShiftNurseId == null
                  ? null
                  : staffNames[bed.dayShiftNurseId] ?? bed.dayShiftNurseId,
              hasWriteAccess: hasWriteAccess,
              onTap: () => _showNurseSelectionSheet(bed, isDay: true),
            ),
          ),

          // 5. Night Shift Nurse Pill
          Container(
            width: _kColNightShiftWidth,
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: _kGridBorderColor, width: 1.0),
              ),
            ),
            alignment: Alignment.center,
            child: _buildNursePill(
              nurseName: bed.nightShiftNurseId == null
                  ? null
                  : staffNames[bed.nightShiftNurseId] ?? bed.nightShiftNurseId,
              hasWriteAccess: hasWriteAccess,
              onTap: () => _showNurseSelectionSheet(bed, isDay: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNursePill({
    required String? nurseName,
    required bool hasWriteAccess,
    required VoidCallback onTap,
  }) {
    final hasNurse =
        nurseName != null && nurseName.isNotEmpty && nurseName != '-';
    return InkWell(
      onTap: hasWriteAccess ? onTap : () => _notifyReadOnly(),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2D4B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2E4068), width: 0.8),
        ),
        child: Text(
          hasNurse ? nurseName : '-',
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF7DD3FC),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // KPI SUMMARY CARDS ROW
  // ==========================================
  Widget _buildKpiCardsRow(
    int occupied,
    int available,
    int dayNurses,
    int nightNurses,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildKpiCard(
            'Occupied Beds',
            '$occupied',
            Icons.bed,
            const Color(0xFF38BDF8),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildKpiCard(
            'Available Beds',
            '$available',
            Icons.bed_outlined,
            const Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildKpiCard(
            'Day Nurses',
            '$dayNurses',
            Icons.people_outline,
            const Color(0xFF38BDF8),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildKpiCard(
            'Night Nurses',
            '$nightNurses',
            Icons.people_outline,
            const Color(0xFF818CF8),
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // BOTTOM WARD RESPONSIBILITIES BANNER
  // ==========================================
  Widget _buildBottomResponsibilitiesCard(
    WardSupportRoster roster,
    bool hasWriteAccess,
    Map<String, String> staffNames,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 15,
                    color: Color(0xFF38BDF8),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Ward Responsibilities',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              // Preserve Ward Support Team contacts dialer
              InkWell(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => WardSupportRosterSheet(
                      roster: roster,
                      hasWriteAccess: hasWriteAccess,
                    ),
                  );
                },
                child: const Row(
                  children: [
                    Icon(
                      Icons.phone_in_talk,
                      size: 13,
                      color: Color(0xFF34D399),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Support Team',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF34D399),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildResponsibilityChip(
                  title: 'Ward Manager',
                  nurse: staffNames[roster.wardManager] ?? roster.wardManager,
                  icon: Icons.manage_accounts,
                  color: const Color(0xFF38BDF8),
                  roleKey: 'ward_manager',
                  hasWriteAccess: hasWriteAccess,
                ),
                _buildResponsibilityChip(
                  title: 'Team Leader',
                  nurse: staffNames[roster.teamLeader] ?? roster.teamLeader,
                  icon: Icons.person,
                  color: const Color(0xFF38BDF8),
                  roleKey: 'team_leader',
                  hasWriteAccess: hasWriteAccess,
                ),
                _buildResponsibilityChip(
                  title: 'Duty Leader',
                  nurse: staffNames[roster.dutyLeader] ?? roster.dutyLeader,
                  icon: Icons.assignment,
                  color: const Color(0xFFA855F7),
                  roleKey: 'duty_leader',
                  hasWriteAccess: hasWriteAccess,
                ),
                _buildResponsibilityChip(
                  title: 'Discharge Nurse',
                  nurse:
                      staffNames[roster.dischargeNurse] ??
                      roster.dischargeNurse,
                  icon: Icons.assignment_turned_in,
                  color: const Color(0xFF34D399),
                  roleKey: 'discharge_nurse',
                  hasWriteAccess: hasWriteAccess,
                ),
                _buildResponsibilityChip(
                  title: 'Patient Care Attendant',
                  nurse: staffNames[roster.pcaDay] ?? roster.pcaDay,
                  icon: Icons.person_pin,
                  color: const Color(0xFF2DD4BF),
                  roleKey: 'pca',
                  hasWriteAccess: hasWriteAccess,
                ),
                _buildResponsibilityChip(
                  title: 'Nurse In-Charge',
                  nurse:
                      staffNames[roster.inchargeNurseDay] ??
                      roster.inchargeNurseDay,
                  icon: Icons.person,
                  color: const Color(0xFF93C5FD),
                  roleKey: 'incharge',
                  hasWriteAccess: hasWriteAccess,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsibilityChip({
    required String title,
    required String nurse,
    required IconData icon,
    required Color color,
    required String roleKey,
    required bool hasWriteAccess,
  }) {
    return InkWell(
      onTap: hasWriteAccess
          ? () => _showRoleAssignmentSheet(title, roleKey)
          : () => _notifyReadOnly(),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF334155), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
                ),
                Text(
                  nurse.isNotEmpty ? nurse : '-',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // UPDATE WARD ASSIGNMENTS BUTTON
  // ==========================================
  Widget _buildUpdateAssignmentsButton(bool hasWriteAccess) {
    if (!hasWriteAccess) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 16, color: Color(0xFF94A3B8)),
              SizedBox(width: 8),
              Text(
                'Read-Only Mode • Maintained by Nurse In-Charge',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0284C7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 2,
        ),
        icon: const Icon(Icons.swap_horiz, color: Colors.white, size: 20),
        label: const Text(
          'Update Ward Assignments',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ward assignments successfully published and updated!',
              ),
              backgroundColor: Color(0xFF059669),
            ),
          );
        },
      ),
    );
  }

  // ==========================================
  // 5-TAB BOTTOM NAVIGATION BAR
  // ==========================================
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _activeNavIndex,
        onTap: (idx) {
          if (idx != 0) {
            Navigator.of(context).pop();
          } else {
            setState(() => _activeNavIndex = idx);
          }
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF0284C7),
        unselectedItemColor: const Color(0xFF64748B),
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_customize),
            label: 'Ward Board',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: 'Patients',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            label: 'Tasks',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Messages',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }

  // ==========================================
  // INPUT MODALS & AUTO-FILTER SHEETS
  // ==========================================

  void _notifyReadOnly() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Read-Only View: Only the Nurse In-Charge has writing capabilities on the board.',
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Strictly typed manual initials dialog (no autofill)
  void _showStrictInitialsDialog(WhiteboardBedAssignment bed) {
    final controller = TextEditingController(
      text: bed.patientInitials == '-' ? '' : bed.patientInitials,
    );
    final patientIdController = TextEditingController(
      text: bed.patientId ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Bed ${bed.bedNumber}: Patient',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                labelText: 'Patient initials',
                hintText: 'e.g. J.N or M.G',
                hintStyle: TextStyle(color: Color(0xFF64748B)),
                helperText: 'Do not enter a full patient name.',
                helperStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
            ),
            TextField(
              controller: patientIdController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Internal patient ID (optional)',
                helperText:
                    'Reuse an existing ID for transfers; leave blank to generate a new one.',
                helperStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
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
            onPressed: () async {
              final initials = controller.text.trim().toUpperCase();
              try {
                var carryForwardIssues = <Map<String, String>>[];
                final suppliedPatientId = patientIdController.text.trim();
                final removesCurrentPatient =
                    initials.isEmpty ||
                    initials == '-' ||
                    (suppliedPatientId.isNotEmpty &&
                        suppliedPatientId != bed.patientId) ||
                    (suppliedPatientId.isEmpty &&
                        initials != bed.patientInitials);
                if (removesCurrentPatient && bed.patientId != null) {
                  final selected = await _prepareCarryForwardIssues(bed);
                  if (selected == null) return;
                  carryForwardIssues = selected;
                }
                await ref
                    .read(wardBoardProvider.notifier)
                    .updateAssignment(
                      bed.bedNumber,
                      patientInitials: initials == '-' ? '' : initials,
                      patientId: patientIdController.text.trim(),
                      status: initials.isEmpty || initials == '-'
                          ? 'available'
                          : 'accepted',
                      carryForwardIssues: carryForwardIssues,
                    );
                if (ctx.mounted) Navigator.of(ctx).pop();
              } catch (error) {
                _showSaveError(error);
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, String>>?> _prepareCarryForwardIssues(
    WhiteboardBedAssignment bed,
  ) async {
    final ward = ref.read(selectedWardProvider);
    final shift = ref.read(selectedShiftTypeProvider);
    final otherBoard = await ref
        .read(wardBoardServiceProvider)
        .getBoard(
          wardId: ward.wardId,
          date: activeWardShiftDate(),
          shiftType: shift == 'day' ? 'night' : 'day',
        );
    final otherAssignments = otherBoard['bed_assignments'];
    if (otherAssignments is! List) {
      throw const FormatException(
        'The other shift board could not be verified before removing this patient.',
      );
    }
    if (otherAssignments.any(
      (assignment) =>
          assignment is Map<String, dynamic> &&
          assignment['patient_id'] == bed.patientId,
    )) {
      return [];
    }

    final openIssues = ref
        .read(patientLoopsProvider(bed.patientId!))
        .where((issue) => issue.isOpen)
        .toList();
    if (openIssues.isEmpty) return [];

    final clinicians = (await ref.read(wardStaffListProvider.future))
        .where(
          (staff) =>
              staff.isActive &&
              {
                'ward_nurse',
                'charge_nurse',
                'doctor_on_call',
              }.contains(staff.role),
        )
        .toList();
    if (clinicians.isEmpty) {
      throw StateError(
        'No active clinician is available to own the patient’s open Medical Issues.',
      );
    }
    return _showCarryForwardOwnerDialog(openIssues, clinicians, bed.patientId!);
  }

  Future<List<Map<String, String>>?> _showCarryForwardOwnerDialog(
    List<LoopStateProjection> issues,
    List<StaffProfile> clinicians,
    String patientId,
  ) async {
    final owners = <String, String?>{};
    final reasons = {
      for (final issue in issues) issue.loopId: TextEditingController(),
    };
    try {
      return await showDialog<List<Map<String, String>>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Assign owners before removing patient'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This is the patient’s last board assignment. Every open Medical Issue needs a named clinician owner. The owner will have access to that issue thread only.',
                    ),
                    const SizedBox(height: 12),
                    for (final issue in issues) ...[
                      Text(
                        issue.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: owners[issue.loopId],
                        decoration: const InputDecoration(
                          labelText: 'Named owner',
                        ),
                        items: clinicians
                            .map(
                              (staff) => DropdownMenuItem(
                                value: staff.staffId,
                                child: Text(
                                  '${staff.name} — ${staff.formattedRole}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => owners[issue.loopId] = value),
                      ),
                      TextField(
                        controller: reasons[issue.loopId],
                        decoration: const InputDecoration(
                          labelText: 'Reason (optional)',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed:
                    owners.length == issues.length &&
                        owners.values.every((owner) => owner != null)
                    ? () {
                        Navigator.of(dialogContext).pop([
                          for (final issue in issues)
                            {
                              'patient_id': patientId,
                              'loop_id': issue.loopId,
                              'owner_id': owners[issue.loopId]!,
                              'reason': reasons[issue.loopId]!.text.trim(),
                            },
                        ]);
                      }
                    : null,
                child: const Text('Assign and remove'),
              ),
            ],
          ),
        ),
      );
    } finally {
      for (final controller in reasons.values) {
        controller.dispose();
      }
    }
  }

  /// Doctor selection sheet with real-time autofilter
  void _showDoctorSelectionSheet(WhiteboardBedAssignment bed) {
    final doctors = _availableStaff(doctorOnly: true);
    if (doctors.isEmpty) {
      _showSaveError(
        StateError('No active doctors are available for this ward.'),
      );
      return;
    }
    _showAutofilterSelectionSheet(
      title: 'Select Doctor for Bed ${bed.bedNumber}',
      options: doctors.map(_staffOptionLabel).toList(),
      currentValue: _staffLabelForId(doctors, bed.admittingDoctor),
      onSelect: (selected) {
        final doctor = doctors.firstWhere(
          (member) => _staffOptionLabel(member) == selected,
        );
        _saveBoardChange(
          () => ref
              .read(wardBoardProvider.notifier)
              .updateAssignment(bed.bedNumber, doctor: doctor.staffId),
        );
      },
    );
  }

  /// Nurse selection sheet with real-time autofilter
  void _showNurseSelectionSheet(
    WhiteboardBedAssignment bed, {
    required bool isDay,
  }) {
    final nurses = _availableStaff();
    if (nurses.isEmpty) {
      _showSaveError(
        StateError('No active nurses are available for this ward.'),
      );
      return;
    }
    _showAutofilterSelectionSheet(
      title: 'Select ${isDay ? "Day" : "Night"} Nurse (Bed ${bed.bedNumber})',
      options: nurses.map(_staffOptionLabel).toList(),
      currentValue: _staffLabelForId(
        nurses,
        isDay ? bed.dayShiftNurseId : bed.nightShiftNurseId,
      ),
      onSelect: (selected) {
        final nurse = nurses.firstWhere(
          (member) => _staffOptionLabel(member) == selected,
        );
        _saveBoardChange(
          () => ref
              .read(wardBoardProvider.notifier)
              .updateAssignment(bed.bedNumber, nurseId: nurse.staffId),
        );
      },
    );
  }

  /// Ward responsibility role selection
  void _showRoleAssignmentSheet(String title, String roleKey) {
    final nurses = _availableStaff();
    if (nurses.isEmpty) {
      _showSaveError(
        StateError('No active nurses are available for this ward.'),
      );
      return;
    }
    _showAutofilterSelectionSheet(
      title: 'Assign $title',
      options: nurses.map(_staffOptionLabel).toList(),
      currentValue: '',
      onSelect: (selected) {
        final nurse = nurses.firstWhere(
          (member) => _staffOptionLabel(member) == selected,
        );
        final currentRoster = ref.read(wardSupportRosterProvider);
        late final WardSupportRoster updatedRoster;
        switch (roleKey) {
          case 'team_leader':
            updatedRoster = WardSupportRoster(
              wardManager: currentRoster.wardManager,
              teamLeader: nurse.staffId,
              dutyLeader: currentRoster.dutyLeader,
              dischargeNurse: currentRoster.dischargeNurse,
              inchargeNurseDay: currentRoster.inchargeNurseDay,
              pcaDay: currentRoster.pcaDay,
            );
            break;
          case 'duty_leader':
            updatedRoster = WardSupportRoster(
              wardManager: currentRoster.wardManager,
              teamLeader: currentRoster.teamLeader,
              dutyLeader: nurse.staffId,
              dischargeNurse: currentRoster.dischargeNurse,
              inchargeNurseDay: currentRoster.inchargeNurseDay,
              pcaDay: currentRoster.pcaDay,
            );
            break;
          case 'discharge_nurse':
            updatedRoster = WardSupportRoster(
              wardManager: currentRoster.wardManager,
              teamLeader: currentRoster.teamLeader,
              dutyLeader: currentRoster.dutyLeader,
              dischargeNurse: nurse.staffId,
              inchargeNurseDay: currentRoster.inchargeNurseDay,
              pcaDay: currentRoster.pcaDay,
            );
            break;
          case 'pca':
            updatedRoster = WardSupportRoster(
              wardManager: currentRoster.wardManager,
              teamLeader: currentRoster.teamLeader,
              dutyLeader: currentRoster.dutyLeader,
              dischargeNurse: currentRoster.dischargeNurse,
              inchargeNurseDay: currentRoster.inchargeNurseDay,
              pcaDay: nurse.staffId,
            );
            break;
          case 'incharge':
            updatedRoster = WardSupportRoster(
              wardManager: currentRoster.wardManager,
              teamLeader: currentRoster.teamLeader,
              dutyLeader: currentRoster.dutyLeader,
              dischargeNurse: currentRoster.dischargeNurse,
              inchargeNurseDay: nurse.staffId,
              pcaDay: currentRoster.pcaDay,
            );
            break;
          default:
            return;
        }
        _saveBoardChange(
          () => ref
              .read(wardSupportRosterProvider.notifier)
              .updateRoster(updatedRoster),
        );
      },
    );
  }

  List<StaffProfile> _availableStaff({bool doctorOnly = false}) {
    final staff = ref.read(boardStaffListProvider).asData?.value ?? const [];
    return staff.where((member) {
      if (doctorOnly) return member.isDoctorOnCall;
      return member.isWardNurse || member.isChargeNurse;
    }).toList();
  }

  String _staffOptionLabel(StaffProfile staff) =>
      '${staff.name} (${staff.staffId})';

  String? _staffLabelForId(List<StaffProfile> staff, String? staffId) {
    if (staffId == null) return null;
    for (final member in staff) {
      if (member.staffId == staffId) return _staffOptionLabel(member);
    }
    return staffId;
  }

  Future<void> _saveBoardChange(Future<void> Function() save) async {
    try {
      await save();
    } catch (error) {
      _showSaveError(error);
    }
  }

  void _showSaveError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save ward board changes: $error')),
    );
  }

  /// General modal sheet with real-time search autofilter
  void _showAutofilterSelectionSheet({
    required String title,
    required List<String> options,
    required String? currentValue,
    required Function(String selected) onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = options
                .where(
                  (opt) => opt.toLowerCase().contains(filter.toLowerCase()),
                )
                .toList();
            return Padding(
              padding: EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Autofilter Search TextField
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: TextField(
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Type to filter...',
                        hintStyle: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Color(0xFF94A3B8),
                          size: 18,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (val) {
                        setModalState(() => filter = val);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Options List
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final opt = filtered[i];
                        final isSelected = opt == currentValue;
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          title: Text(
                            opt,
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF38BDF8)
                                  : Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Color(0xFF38BDF8),
                                  size: 18,
                                )
                              : null,
                          onTap: () {
                            onSelect(opt);
                            Navigator.of(ctx).pop();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

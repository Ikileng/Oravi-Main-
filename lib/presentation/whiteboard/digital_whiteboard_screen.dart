import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/whiteboard_models.dart';
import '../providers/whiteboard_providers.dart';
import '../providers/auth_providers.dart';
import '../widgets/ward_support_roster_sheet.dart';
import '../widgets/ward_selection_dialog.dart';

/// Pixel-perfect implementation of the user's Ward Management & Nurse Allocation Board design
class DigitalWhiteboardScreen extends ConsumerStatefulWidget {
  const DigitalWhiteboardScreen({super.key});

  @override
  ConsumerState<DigitalWhiteboardScreen> createState() => _DigitalWhiteboardScreenState();
}

class _DigitalWhiteboardScreenState extends ConsumerState<DigitalWhiteboardScreen> {
  int _activeNavIndex = 0;
  bool _isDayShift = true;

  // Registered doctors for fast autofilter selection
  static const List<String> _kCandidateDoctors = [
    'Dr. Mbita',
    'Dr. Lageti',
    'Dr. Dawkins',
    'Dr. Mbei',
    'Dr. Kimani',
    'Dr. Osundina',
    'Dr. Khasong',
    'Dr. Ravel',
    'Dr. J. Martins',
    'Dr. James Kamau',
    'Dr. Lucy Wangari',
  ];

  // Registered nurses for fast autofilter selection
  static const List<String> _kCandidateNurses = [
    'Nurse A',
    'Nurse B',
    'Nurse C',
    'Nurse D',
    'Nurse E',
    'Faith Njeri, RN',
    'Mary Wanjiku, RN',
    'Grace Achieng, RN',
    'Sarah Otieno, RN',
    'Jane Muthoni, RN',
  ];

  @override
  Widget build(BuildContext context) {
    final currentWard = ref.watch(selectedWardProvider);
    final beds = ref.watch(whiteboardAssignmentsProvider);
    final roster = ref.watch(wardSupportRosterProvider);
    final currentStaff = ref.watch(authenticatedStaffProvider);

    // ONLY the Charge Nurse (or Ward Manager) has write permissions.
    // Everyone else has strictly one-tap read-only access.
    final hasWriteAccess = currentStaff?.isChargeNurse ?? false;

    // Calculate dynamic KPI counters
    final occupiedCount = beds.where((b) => b.patientInitials.trim().isNotEmpty && b.patientInitials.trim() != '-').length;
    final availableCount = beds.length - occupiedCount;
    final dayNursesCount = beds.map((b) => b.dayShiftNurseId).where((id) => id != null && id.isNotEmpty).toSet().length;
    final nightNursesCount = beds.map((b) => b.nightShiftNurseId).where((id) => id != null && id.isNotEmpty).toSet().length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Header
            _buildTopHeader(context, currentWard, hasWriteAccess),

            // 2. Scrollable Body: Table + KPI Cards + Responsibilities + Update Button
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Main Table with Horizontal & Vertical Scroll
                      _buildMainTable(beds, roster, hasWriteAccess),

                      const SizedBox(height: 16),

                      // KPI Cards Row (Occupied Beds, Available Beds, Day Nurses, Night Nurses)
                      _buildKpiCardsRow(occupiedCount, availableCount, dayNursesCount, nightNursesCount),

                      const SizedBox(height: 16),

                      // Bottom Ward Responsibilities Card
                      _buildBottomResponsibilitiesCard(roster, hasWriteAccess),

                      const SizedBox(height: 16),

                      // Primary Action Button: "⇄ Update Ward Assignments"
                      _buildUpdateAssignmentsButton(hasWriteAccess),

                      const SizedBox(height: 16),
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
  Widget _buildTopHeader(BuildContext context, dynamic currentWard, bool hasWriteAccess) {
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
                  child: Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    // Tappable Ward Switcher with search & autofilter
                    InkWell(
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
                              'Jaramanda Hospital · ${currentWard.name}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF94A3B8)),
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
                  border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 6, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text(
                      'Synced',
                      style: TextStyle(fontSize: 11, color: Color(0xFF34D399), fontWeight: FontWeight.bold),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.cloud_upload_outlined, size: 13, color: Color(0xFF34D399)),
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
              const Row(
                children: [
                  Text(
                    'Fri, 30 Oct 2026',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.calendar_month_outlined, size: 15, color: Color(0xFF38BDF8)),
                ],
              ),

              // Shift Dropdown Toggle
              InkWell(
                onTap: () {
                  setState(() => _isDayShift = !_isDayShift);
                },
                child: Row(
                  children: [
                    Icon(
                      _isDayShift ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                      size: 14,
                      color: _isDayShift ? const Color(0xFFFBBF24) : const Color(0xFF818CF8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isDayShift ? 'Day Shift' : 'Night Shift',
                      style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down, size: 14, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MAIN TABLE WITH BED ROWS & RESPONSIBILITIES
  // ==========================================
  Widget _buildMainTable(List<WhiteboardBedAssignment> beds, WardSupportRoster roster, bool hasWriteAccess) {
    // 10 beds strictly
    final displayBeds = beds.take(10).toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 600, // Exact comfortable width for all columns
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Table Header Row
                _buildTableHeader(),

                // 10 Bed Rows
                ...displayBeds.asMap().entries.map((entry) {
                  final index = entry.key;
                  final bed = entry.value;
                  return _buildBedRow(index, bed, roster, hasWriteAccess);
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF131D33),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 55,
            child: Text(
              'Bed /\nRoom',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
            ),
          ),
          SizedBox(
            width: 65,
            child: Text(
              'Patient\nInitials',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
            ),
          ),
          SizedBox(
            width: 105,
            child: Text(
              'Doctor',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
            ),
          ),
          SizedBox(
            width: 175,
            child: Column(
              children: [
                Text(
                  'Nurses',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                ),
                SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text('Day Shift', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                    Text('Night Shift', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 170,
            child: Text(
              'Ward Responsibilities',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBedRow(int index, WhiteboardBedAssignment bed, WardSupportRoster roster, bool hasWriteAccess) {
    // Determine vertical status stripe color
    // Green = Occupied & Assigned, Yellow = Pending/Review, Grey = Available
    final isAvailable = bed.patientInitials.trim() == '-' || bed.patientInitials.trim().isEmpty;
    final isPending = bed.status == 'pending';
    final stripeColor = isAvailable
        ? const Color(0xFF334155)
        : (isPending ? const Color(0xFFEAB308) : const Color(0xFF10B981));

    // Map right-hand ward responsibilities stack based on row index
    Widget? responsibilityWidget;
    switch (index) {
      case 0:
        responsibilityWidget = _buildSidebarRole(
          title: 'Team Leader',
          nurse: roster.teamLeader.isNotEmpty ? roster.teamLeader : 'Nurse A',
          icon: Icons.person,
          iconColor: const Color(0xFF38BDF8),
          roleKey: 'team_leader',
          hasWriteAccess: hasWriteAccess,
        );
        break;
      case 1:
        responsibilityWidget = _buildSidebarRole(
          title: 'Duty Leader',
          nurse: roster.dutyLeader.isNotEmpty ? roster.dutyLeader : 'Nurse B',
          icon: Icons.assignment_outlined,
          iconColor: const Color(0xFFA855F7),
          roleKey: 'duty_leader',
          hasWriteAccess: hasWriteAccess,
        );
        break;
      case 2:
        responsibilityWidget = _buildSidebarRole(
          title: 'Discharge Nurse',
          nurse: roster.dischargeNurse.isNotEmpty ? roster.dischargeNurse : 'Nurse C',
          icon: Icons.assignment_turned_in_outlined,
          iconColor: const Color(0xFF34D399),
          roleKey: 'discharge_nurse',
          hasWriteAccess: hasWriteAccess,
        );
        break;
      case 3:
        responsibilityWidget = _buildSidebarRole(
          title: 'Patient Care Attendant',
          nurse: roster.pcaDay.isNotEmpty ? roster.pcaDay : 'Nurse D',
          icon: Icons.person_pin_outlined,
          iconColor: const Color(0xFF2DD4BF),
          roleKey: 'pca',
          hasWriteAccess: hasWriteAccess,
        );
        break;
      case 5:
        responsibilityWidget = _buildSidebarRole(
          title: 'Nurse In-Charge',
          nurse: roster.inchargeNurseDay.isNotEmpty ? roster.inchargeNurseDay : 'Nurse E',
          icon: Icons.person,
          iconColor: const Color(0xFF93C5FD),
          roleKey: 'incharge',
          hasWriteAccess: hasWriteAccess,
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: index % 2 == 0 ? Colors.transparent : const Color(0xFF0B132B).withValues(alpha: 0.5),
        border: const Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 0.8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Bed / Room with Vertical Stripe
          SizedBox(
            width: 55,
            child: Row(
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
                    border: Border.all(color: const Color(0xFF334155), width: 0.8),
                  ),
                  child: Center(
                    child: Text(
                      bed.bedNumber,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Patient Initials (Strictly Typed)
          SizedBox(
            width: 65,
            child: InkWell(
              onTap: hasWriteAccess ? () => _showStrictInitialsDialog(bed) : () => _notifyReadOnly(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  bed.patientInitials.isNotEmpty ? bed.patientInitials : '-',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
          ),

          // Doctor (Type / Autofilter)
          SizedBox(
            width: 105,
            child: InkWell(
              onTap: hasWriteAccess ? () => _showDoctorSelectionSheet(bed) : () => _notifyReadOnly(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  bed.admittingDoctor.isNotEmpty ? bed.admittingDoctor : '-',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1), fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),

          // Nurses: Day Shift Pill & Night Shift Pill
          SizedBox(
            width: 175,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Day Shift Nurse Pill
                _buildNursePill(
                  nurseName: bed.dayShiftNurseId,
                  hasWriteAccess: hasWriteAccess,
                  onTap: () => _showNurseSelectionSheet(bed, isDay: true),
                ),
                // Night Shift Nurse Pill
                _buildNursePill(
                  nurseName: bed.nightShiftNurseId,
                  hasWriteAccess: hasWriteAccess,
                  onTap: () => _showNurseSelectionSheet(bed, isDay: false),
                ),
              ],
            ),
          ),

          // Ward Responsibilities (Right Sidebar Column)
          SizedBox(
            width: 170,
            child: responsibilityWidget ?? const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildNursePill({required String? nurseName, required bool hasWriteAccess, required VoidCallback onTap}) {
    final hasNurse = nurseName != null && nurseName.isNotEmpty && nurseName != '-';
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
          style: const TextStyle(fontSize: 11, color: Color(0xFF7DD3FC), fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildSidebarRole({
    required String title,
    required String nurse,
    required IconData icon,
    required Color iconColor,
    required String roleKey,
    required bool hasWriteAccess,
  }) {
    return InkWell(
      onTap: hasWriteAccess ? () => _showRoleAssignmentSheet(title, roleKey) : () => _notifyReadOnly(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 5),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  nurse,
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // KPI SUMMARY CARDS ROW
  // ==========================================
  Widget _buildKpiCardsRow(int occupied, int available, int dayNurses, int nightNurses) {
    return Row(
      children: [
        Expanded(child: _buildKpiCard('Occupied Beds', '$occupied', Icons.bed, const Color(0xFF38BDF8))),
        const SizedBox(width: 8),
        Expanded(child: _buildKpiCard('Available Beds', '$available', Icons.bed_outlined, const Color(0xFF94A3B8))),
        const SizedBox(width: 8),
        Expanded(child: _buildKpiCard('Day Nurses', '$dayNurses', Icons.people_outline, const Color(0xFF38BDF8))),
        const SizedBox(width: 8),
        Expanded(child: _buildKpiCard('Night Nurses', '$nightNurses', Icons.people_outline, const Color(0xFF818CF8))),
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
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // BOTTOM WARD RESPONSIBILITIES BANNER
  // ==========================================
  Widget _buildBottomResponsibilitiesCard(WardSupportRoster roster, bool hasWriteAccess) {
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
                  Icon(Icons.assignment_outlined, size: 15, color: Color(0xFF38BDF8)),
                  SizedBox(width: 6),
                  Text(
                    'Ward Responsibilities',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
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
                    builder: (_) => WardSupportRosterSheet(roster: roster),
                  );
                },
                child: const Row(
                  children: [
                    Icon(Icons.phone_in_talk, size: 13, color: Color(0xFF34D399)),
                    SizedBox(width: 4),
                    Text(
                      'Support Team',
                      style: TextStyle(fontSize: 11, color: Color(0xFF34D399), fontWeight: FontWeight.bold),
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
                _buildResponsibilityChip('Ward Manager', roster.wardManager, Icons.manage_accounts, const Color(0xFF38BDF8)),
                _buildResponsibilityChip('Team Leader', roster.teamLeader, Icons.person, const Color(0xFF38BDF8)),
                _buildResponsibilityChip('Duty Leader', roster.dutyLeader, Icons.assignment, const Color(0xFFA855F7)),
                _buildResponsibilityChip('Discharge Nurse', roster.dischargeNurse, Icons.assignment_turned_in, const Color(0xFF34D399)),
                _buildResponsibilityChip('Patient Care Attendant', roster.pcaDay, Icons.person_pin, const Color(0xFF2DD4BF)),
                _buildResponsibilityChip('Nurse In-Charge', roster.inchargeNurseDay, Icons.person, const Color(0xFF93C5FD)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsibilityChip(String title, String nurse, IconData icon, Color color) {
    return Container(
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
              Text(title, style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
              Text(nurse.isNotEmpty ? nurse : '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
        ],
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
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
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
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ward assignments successfully published and updated!'),
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
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
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
        content: Text('Read-Only View: Only the Nurse In-Charge has writing capabilities on the board.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Strictly typed manual initials dialog (no autofill)
  void _showStrictInitialsDialog(WhiteboardBedAssignment bed) {
    final controller = TextEditingController(text: bed.patientInitials == '-' ? '' : bed.patientInitials);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Bed ${bed.bedNumber}: Patient Initials', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            hintText: 'e.g. J.N or M.G',
            hintStyle: TextStyle(color: Color(0xFF64748B)),
            helperText: 'Strictly manual typing. No autofill.',
            helperStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () {
              final val = controller.text.trim();
              ref.read(whiteboardAssignmentsProvider.notifier).updateAssignment(
                bed.bedNumber,
                status: val.isEmpty || val == '-' ? 'available' : 'accepted',
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Doctor selection sheet with real-time autofilter
  void _showDoctorSelectionSheet(WhiteboardBedAssignment bed) {
    _showAutofilterSelectionSheet(
      title: 'Select Doctor for Bed ${bed.bedNumber}',
      options: _kCandidateDoctors,
      currentValue: bed.admittingDoctor,
      onSelect: (doc) {
        ref.read(whiteboardAssignmentsProvider.notifier).updateAssignment(bed.bedNumber, doctor: doc);
      },
    );
  }

  /// Nurse selection sheet with real-time autofilter
  void _showNurseSelectionSheet(WhiteboardBedAssignment bed, {required bool isDay}) {
    _showAutofilterSelectionSheet(
      title: 'Select ${isDay ? "Day" : "Night"} Nurse (Bed ${bed.bedNumber})',
      options: _kCandidateNurses,
      currentValue: isDay ? bed.dayShiftNurseId : bed.nightShiftNurseId,
      onSelect: (nurse) {
        if (isDay) {
          ref.read(whiteboardAssignmentsProvider.notifier).updateAssignment(bed.bedNumber, nurseId: nurse);
        } else {
          // Night nurse assignment
          ref.read(whiteboardAssignmentsProvider.notifier).updateAssignment(bed.bedNumber, status: 'accepted');
        }
      },
    );
  }

  /// Ward responsibility role selection
  void _showRoleAssignmentSheet(String title, String roleKey) {
    _showAutofilterSelectionSheet(
      title: 'Assign $title',
      options: _kCandidateNurses,
      currentValue: '',
      onSelect: (nurse) {
        final currentRoster = ref.read(wardSupportRosterProvider);
        switch (roleKey) {
          case 'team_leader':
            ref.read(wardSupportRosterProvider.notifier).updateRoster(WardSupportRoster(
              wardManager: currentRoster.wardManager,
              teamLeader: nurse,
              dutyLeader: currentRoster.dutyLeader,
              dischargeNurse: currentRoster.dischargeNurse,
              inchargeNurseDay: currentRoster.inchargeNurseDay,
              pcaDay: currentRoster.pcaDay,
            ));
            break;
          case 'duty_leader':
            ref.read(wardSupportRosterProvider.notifier).updateRoster(WardSupportRoster(
              wardManager: currentRoster.wardManager,
              teamLeader: currentRoster.teamLeader,
              dutyLeader: nurse,
              dischargeNurse: currentRoster.dischargeNurse,
              inchargeNurseDay: currentRoster.inchargeNurseDay,
              pcaDay: currentRoster.pcaDay,
            ));
            break;
          case 'discharge_nurse':
            ref.read(wardSupportRosterProvider.notifier).updateRoster(WardSupportRoster(
              wardManager: currentRoster.wardManager,
              teamLeader: currentRoster.teamLeader,
              dutyLeader: currentRoster.dutyLeader,
              dischargeNurse: nurse,
              inchargeNurseDay: currentRoster.inchargeNurseDay,
              pcaDay: currentRoster.pcaDay,
            ));
            break;
          case 'pca':
            ref.read(wardSupportRosterProvider.notifier).updateRoster(WardSupportRoster(
              wardManager: currentRoster.wardManager,
              teamLeader: currentRoster.teamLeader,
              dutyLeader: currentRoster.dutyLeader,
              dischargeNurse: currentRoster.dischargeNurse,
              inchargeNurseDay: currentRoster.inchargeNurseDay,
              pcaDay: nurse,
            ));
            break;
          case 'incharge':
            ref.read(wardSupportRosterProvider.notifier).updateRoster(WardSupportRoster(
              wardManager: currentRoster.wardManager,
              teamLeader: currentRoster.teamLeader,
              dutyLeader: currentRoster.dutyLeader,
              dischargeNurse: currentRoster.dischargeNurse,
              inchargeNurseDay: nurse,
              pcaDay: currentRoster.pcaDay,
            ));
            break;
        }
      },
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = options.where((opt) => opt.toLowerCase().contains(filter.toLowerCase())).toList();
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
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 20),
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
                        hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        prefixIcon: Icon(Icons.search, color: Color(0xFF94A3B8), size: 18),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          title: Text(
                            opt,
                            style: TextStyle(
                              color: isSelected ? const Color(0xFF38BDF8) : Colors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF38BDF8), size: 18) : null,
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

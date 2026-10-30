import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/auth/staff_auth_service.dart';
import '../../domain/models/staff_profile.dart';
import '../providers/auth_providers.dart';
import '../whiteboard/digital_whiteboard_screen.dart';

/// Representation of a managed user for the Dev Admin Dashboard.
class DevUserItem {
  final String staffId;
  final String name;
  final String email;
  final String role; // 'Nurse' | 'Doctor' | 'Ward Manager' | 'Administrator'
  final String ward;
  final bool isActive;
  final String lastLogin;
  final String pin;

  const DevUserItem({
    required this.staffId,
    required this.name,
    required this.email,
    required this.role,
    this.ward = 'Medical',
    this.isActive = true,
    this.lastLogin = 'Today, 09:12 AM',
    this.pin = '1234',
  });

  DevUserItem copyWith({
    String? name,
    String? email,
    String? role,
    String? ward,
    bool? isActive,
    String? lastLogin,
    String? pin,
  }) {
    return DevUserItem(
      staffId: staffId,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      ward: ward ?? this.ward,
      isActive: isActive ?? this.isActive,
      lastLogin: lastLogin ?? this.lastLogin,
      pin: pin ?? this.pin,
    );
  }
}

/// State notifier managing the list of development users.
class DevUsersNotifier extends Notifier<List<DevUserItem>> {
  @override
  List<DevUserItem> build() {
    return [
      const DevUserItem(
        staffId: 'NUR-403',
        name: 'Nurse X (Faith Njeri)',
        email: 'nurse.x@oravi.dev',
        role: 'Nurse',
        ward: 'Medical',
        isActive: true,
        lastLogin: 'Today, 09:12 AM',
        pin: '1111',
      ),
      const DevUserItem(
        staffId: 'NUR-401',
        name: 'Nurse Y (Mary Wanjiku)',
        email: 'nurse.y@oravi.dev',
        role: 'Nurse',
        ward: 'Surgical',
        isActive: true,
        lastLogin: 'Today, 08:47 AM',
        pin: '1234',
      ),
      const DevUserItem(
        staffId: 'DOC-401',
        name: 'Dr. A (Dr. James Kamau)',
        email: 'doctor.a@oravi.dev',
        role: 'Doctor',
        ward: 'Medical',
        isActive: true,
        lastLogin: 'Today, 08:20 AM',
        pin: '9090',
      ),
      const DevUserItem(
        staffId: 'NUR-402',
        name: 'Manager (Grace Achieng)',
        email: 'manager@oravi.dev',
        role: 'Ward Manager',
        ward: 'Both',
        isActive: true,
        lastLogin: 'Today, 07:55 AM',
        pin: '5678',
      ),
      const DevUserItem(
        staffId: 'ADM-001',
        name: 'Admin',
        email: 'admin@oravi.dev',
        role: 'Administrator',
        ward: 'N/A',
        isActive: true,
        lastLogin: 'Today, 07:32 AM',
        pin: '0000',
      ),
    ];
  }

  void addUser(DevUserItem user) {
    state = [...state, user];

    // Map role to clinical domain role
    String domainRole = 'ward_nurse';
    if (user.role == 'Doctor') domainRole = 'doctor_on_call';
    if (user.role == 'Ward Manager') domainRole = 'charge_nurse';

    // Sync to clinical auth service
    StaffAuthService.addStaffUser(
      StaffProfile(
        staffId: user.staffId,
        name: user.name,
        role: domainRole,
        wardId: 'WARD-4B',
        avatarColor: user.role == 'Doctor'
            ? '#7C3AED'
            : (user.role == 'Ward Manager' ? '#EA580C' : '#059669'),
        initials: user.name
            .split(' ')
            .take(2)
            .map((e) => e.isNotEmpty ? e[0] : '')
            .join()
            .toUpperCase(),
        isActive: user.isActive,
      ),
      user.pin,
    );
  }

  void resetPin(String staffId, String newPin) {
    state = state.map((u) {
      if (u.staffId == staffId) {
        return u.copyWith(pin: newPin);
      }
      return u;
    }).toList();

    StaffAuthService.updateStaffPin(staffId, newPin);
  }

  void toggleActive(String staffId) {
    state = state.map((u) {
      if (u.staffId == staffId) {
        final updated = u.copyWith(isActive: !u.isActive);
        return updated;
      }
      return u;
    }).toList();

    StaffAuthService.toggleStaffActive(staffId);
  }

  void deleteUser(String staffId) {
    state = state.where((u) => u.staffId != staffId).toList();
    StaffAuthService.deleteStaff(staffId);
  }
}

final devUsersProvider =
    NotifierProvider<DevUsersNotifier, List<DevUserItem>>(DevUsersNotifier.new);

/// Full implementation of the Dev Admin Dashboard matching user mockup.
class DevAdminDashboardScreen extends ConsumerStatefulWidget {
  const DevAdminDashboardScreen({super.key});

  @override
  ConsumerState<DevAdminDashboardScreen> createState() =>
      _DevAdminDashboardScreenState();
}

class _DevAdminDashboardScreenState
    extends ConsumerState<DevAdminDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(devUsersProvider);

    // Calculate metrics
    final totalUsers = users.length;
    final activeUsers = users.where((u) => u.isActive).length;
    final inactiveUsers = totalUsers - activeUsers;

    final nurses = users.where((u) => u.role == 'Nurse').toList();
    final doctors = users.where((u) => u.role == 'Doctor').toList();
    final wardManagers = users.where((u) => u.role == 'Ward Manager').toList();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF070E1E),
      drawer: _buildSidebarDrawer(context),
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar with Search & Profile
            _buildTopNavBar(context),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dashboard Title Bar
                    _buildTitleSection(),

                    const SizedBox(height: 14),

                    // Top 5 KPI Metric Cards
                    _buildKpiMetricsRow(
                      totalUsers: totalUsers,
                      activeUsers: activeUsers,
                      inactiveUsers: inactiveUsers,
                      nurseCount: nurses.length,
                      nurseActive: nurses.where((n) => n.isActive).length,
                      doctorCount: doctors.length,
                      doctorActive: doctors.where((d) => d.isActive).length,
                      managerCount: wardManagers.length,
                      managerActive: wardManagers.where((m) => m.isActive).length,
                    ),

                    const SizedBox(height: 14),

                    // Middle Section: System Overview & Recent Activity
                    _buildOverviewAndActivityRow(),

                    const SizedBox(height: 14),

                    // Quick Actions Row
                    _buildQuickActionsRow(context),

                    const SizedBox(height: 14),

                    // Recent Users Table
                    _buildRecentUsersTable(users),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TOP NAV BAR
  // ==========================================
  Widget _buildTopNavBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1426),
        border: Border(bottom: BorderSide(color: Color(0xFF162540), width: 1)),
      ),
      child: Row(
        children: [
          // Drawer Menu Button (Sidebar on mobile)
          IconButton(
            icon: const Icon(Icons.menu, color: Color(0xFF94A3B8), size: 20),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          const SizedBox(width: 4),

          // Search Bar
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF101C33),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E2E4E)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 16, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Search users, patients, wards...',
                        hintStyle: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Online Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF064E3B).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.5)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 6, color: Color(0xFF10B981)),
                SizedBox(width: 4),
                Text('Online', style: TextStyle(fontSize: 10, color: Color(0xFF34D399), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Bell with Badge 3
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF101C33),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.notifications_none, size: 16, color: Color(0xFF94A3B8)),
              ),
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  child: const Text('3', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),

          // Dev Admin Profile Avatar
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF1E293B),
            child: const Icon(Icons.person, size: 16, color: Color(0xFF38BDF8)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TITLE SECTION
  // ==========================================
  Widget _buildTitleSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Dev Admin Dashboard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            SizedBox(height: 2),
            Text(
              'Manage users, hospital data and system settings',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF101C33),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF1E2E4E)),
          ),
          child: const Row(
            children: [
              Icon(Icons.calendar_month_outlined, size: 12, color: Color(0xFF38BDF8)),
              SizedBox(width: 4),
              Text(
                'Fri, 30 Oct 2026',
                style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 5 KPI METRIC CARDS
  // ==========================================
  Widget _buildKpiMetricsRow({
    required int totalUsers,
    required int activeUsers,
    required int inactiveUsers,
    required int nurseCount,
    required int nurseActive,
    required int doctorCount,
    required int doctorActive,
    required int managerCount,
    required int managerActive,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Total Users
          _buildKpiCard(
            title: 'Total Users',
            value: '$totalUsers',
            subText: '● Active: $activeUsers  |  ● Inactive: $inactiveUsers',
            icon: Icons.person_outline,
            iconBgColor: const Color(0xFF0284C7).withValues(alpha: 0.2),
            iconColor: const Color(0xFF38BDF8),
          ),
          const SizedBox(width: 8),

          // Nurses
          _buildKpiCard(
            title: 'Nurses',
            value: '$nurseCount',
            subText: '● Active: $nurseActive',
            icon: Icons.people_outline,
            iconBgColor: const Color(0xFF059669).withValues(alpha: 0.2),
            iconColor: const Color(0xFF10B981),
          ),
          const SizedBox(width: 8),

          // Doctors
          _buildKpiCard(
            title: 'Doctors',
            value: '$doctorCount',
            subText: '● Active: $doctorActive',
            icon: Icons.medical_services_outlined,
            iconBgColor: const Color(0xFFA855F7).withValues(alpha: 0.2),
            iconColor: const Color(0xFFA855F7),
          ),
          const SizedBox(width: 8),

          // Ward Manager
          _buildKpiCard(
            title: 'Ward Manager',
            value: '$managerCount',
            subText: '● Active: $managerActive',
            icon: Icons.shield_outlined,
            iconBgColor: const Color(0xFFEA580C).withValues(alpha: 0.2),
            iconColor: const Color(0xFFF97316),
          ),
          const SizedBox(width: 8),

          // Hospital
          _buildKpiCard(
            title: 'Hospital',
            value: '1',
            subText: 'Jaramanda Hospital',
            icon: Icons.local_hospital_outlined,
            iconBgColor: const Color(0xFF0D9488).withValues(alpha: 0.2),
            iconColor: const Color(0xFF14B8A6),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subText,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
  }) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1426),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF162540)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: iconBgColor,
            child: Icon(icon, size: 14, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            subText,
            style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SYSTEM OVERVIEW & RECENT ACTIVITY
  // ==========================================
  Widget _buildOverviewAndActivityRow() {
    return Column(
      children: [
        // System Overview Panel
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1426),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF162540)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.insights, size: 15, color: Color(0xFF38BDF8)),
                  SizedBox(width: 6),
                  Text('System Overview', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildTile(icon: Icons.people, title: 'Patients', value: '15', sub: 'Admitted ↑ 2 today', color: const Color(0xFF38BDF8))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildTile(icon: Icons.bed, title: 'Beds', value: '10', sub: '8 occupied · 2 available', color: const Color(0xFFA855F7))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildTile(icon: Icons.apartment, title: 'Wards', value: '2', sub: 'Medical Ward · Surgical Ward', color: const Color(0xFF10B981))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildTile(icon: Icons.access_time, title: 'Active Shifts', value: '2', sub: 'Day | Night', color: const Color(0xFFF59E0B))),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Recent Activity Panel
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1426),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF162540)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bolt, size: 15, color: Color(0xFF38BDF8)),
                      SizedBox(width: 6),
                      Text('Recent Activity', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  Text('View all', style: TextStyle(fontSize: 10, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              _buildActivityItem(icon: Icons.person_add, iconColor: const Color(0xFF10B981), title: 'New user created', detail: 'Nurse Y (nurse.y@oravi.dev)', time: '10:12 AM'),
              _buildActivityItem(icon: Icons.swap_horiz, iconColor: const Color(0xFFA855F7), title: 'Ward assignment updated', detail: 'Bed 26 → Nurse X', time: '09:45 AM'),
              _buildActivityItem(icon: Icons.chat_bubble_outline, iconColor: const Color(0xFF38BDF8), title: 'New message', detail: 'From Dr. A to Nurse X', time: '09:32 AM'),
              _buildActivityItem(icon: Icons.person_pin, iconColor: const Color(0xFFF97316), title: 'Patient admitted', detail: 'J.K. (Bed 25)', time: '08:50 AM'),
              _buildActivityItem(icon: Icons.cloud_done, iconColor: const Color(0xFF14B8A6), title: 'System backup completed', detail: 'Database and local cache', time: '06:20 AM'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTile({required IconData icon, required String title, required String value, required String sub, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF101C33),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E2E4E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(title, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildActivityItem({required IconData icon, required Color iconColor, required String title, required String detail, required String time}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: iconColor.withValues(alpha: 0.15),
            child: Icon(icon, size: 12, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                Text(detail, style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8)), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Text(time, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B))),
        ],
      ),
    );
  }

  // ==========================================
  // QUICK ACTIONS BAR
  // ==========================================
  Widget _buildQuickActionsRow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.flash_on, size: 14, color: Color(0xFF38BDF8)),
            SizedBox(width: 4),
            Text('Quick Actions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Add User Button
            Expanded(
              child: _buildActionCard(
                title: 'Add User',
                sub: 'Create new staff account',
                icon: Icons.person_add,
                gradient: const [Color(0xFF0284C7), Color(0xFF0369A1)],
                onTap: () => _showAddUserDialog(context),
              ),
            ),
            const SizedBox(width: 8),

            // Manage Wards Button
            Expanded(
              child: _buildActionCard(
                title: 'Manage Wards',
                sub: 'Edit wards & beds',
                icon: Icons.bed,
                gradient: const [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DigitalWhiteboardScreen()),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Add Patient Button
            Expanded(
              child: _buildActionCard(
                title: 'Add Patient',
                sub: 'Register new patient',
                icon: Icons.person,
                gradient: const [Color(0xFF059669), Color(0xFF047857)],
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Patient registration: Managed via Clinical Intake.')),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),

            // System Settings Button
            Expanded(
              child: _buildActionCard(
                title: 'System Settings',
                sub: 'Configure application',
                icon: Icons.settings,
                gradient: const [Color(0xFFD97706), Color(0xFFB45309)],
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Dev System Settings: Multi-host active, Offline Drift enabled.')),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required String title,
    required String sub,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(sub, style: const TextStyle(fontSize: 9, color: Color(0xFFE2E8F0)), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 14, color: Colors.white),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // RECENT USERS TABLE
  // ==========================================
  Widget _buildRecentUsersTable(List<DevUserItem> users) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1426),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF162540)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.people_outline, size: 15, color: Color(0xFF38BDF8)),
                    SizedBox(width: 6),
                    Text('Recent Users', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                Text('View all users →', style: TextStyle(fontSize: 10, color: const Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(color: Color(0xFF162540), height: 1),

          // Scrollable Table for horizontal fidelity
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 580,
              child: Column(
                children: [
                  // Table Header
                  Container(
                    color: const Color(0xFF0F1A30),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: const Row(
                      children: [
                        SizedBox(width: 140, child: Text('Name', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)))),
                        SizedBox(width: 130, child: Text('Email', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)))),
                        SizedBox(width: 90, child: Text('Role', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)))),
                        SizedBox(width: 65, child: Text('Status', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)))),
                        SizedBox(width: 95, child: Text('Last Login', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)))),
                        SizedBox(width: 50, child: Text('Actions', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)))),
                      ],
                    ),
                  ),
                  const Divider(color: Color(0xFF162540), height: 1),

                  // Rows
                  ...users.map((user) => _buildUserRow(user)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserRow(DevUserItem user) {
    // Role pill color
    Color roleBg = const Color(0xFF0284C7).withValues(alpha: 0.2);
    Color roleText = const Color(0xFF38BDF8);
    if (user.role == 'Doctor') {
      roleBg = const Color(0xFFA855F7).withValues(alpha: 0.2);
      roleText = const Color(0xFFC084FC);
    } else if (user.role == 'Ward Manager') {
      roleBg = const Color(0xFFEA580C).withValues(alpha: 0.2);
      roleText = const Color(0xFFFB923C);
    } else if (user.role == 'Administrator') {
      roleBg = const Color(0xFF475569).withValues(alpha: 0.3);
      roleText = const Color(0xFF94A3B8);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF162540), width: 0.8)),
      ),
      child: Row(
        children: [
          // Name & Staff ID
          SizedBox(
            width: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white), overflow: TextOverflow.ellipsis),
                Text('PIN: ${user.pin} · ID: ${user.staffId}', style: const TextStyle(fontSize: 9, color: Color(0xFF64748B))),
              ],
            ),
          ),

          // Email
          SizedBox(
            width: 130,
            child: Text(user.email, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)), overflow: TextOverflow.ellipsis),
          ),

          // Role Badge
          SizedBox(
            width: 90,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: roleBg, borderRadius: BorderRadius.circular(12)),
                child: Text(user.role, style: TextStyle(fontSize: 9, color: roleText, fontWeight: FontWeight.bold)),
              ),
            ),
          ),

          // Status Badge (Active/Inactive)
          SizedBox(
            width: 65,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: user.isActive ? const Color(0xFF064E3B) : const Color(0xFF450A0A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  user.isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                    fontSize: 9,
                    color: user.isActive ? const Color(0xFF34D399) : const Color(0xFFFCA5A5),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

          // Last Login
          SizedBox(
            width: 95,
            child: Text(user.lastLogin, style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
          ),

          // Actions (...) Button
          SizedBox(
            width: 50,
            child: IconButton(
              icon: const Icon(Icons.more_horiz, size: 16, color: Color(0xFF94A3B8)),
              onPressed: () => _showUserActionModal(user),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // USER ACTIONS MODAL (PIN RESET, ACTIVE TOGGLE, DELETE)
  // ==========================================
  void _showUserActionModal(DevUserItem user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Role: ${user.role} · Staff ID: ${user.staffId}', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              const SizedBox(height: 14),

              // Reset PIN Option
              ListTile(
                leading: const Icon(Icons.password, color: Color(0xFF38BDF8)),
                title: const Text('Reset 4-Digit Quick PIN', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text('Current PIN: ${user.pin}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showResetPinDialog(user);
                },
              ),

              // Toggle Active/Inactive Status Option
              ListTile(
                leading: Icon(user.isActive ? Icons.block : Icons.check_circle, color: user.isActive ? const Color(0xFFEF4444) : const Color(0xFF10B981)),
                title: Text(user.isActive ? 'Deactivate Account' : 'Activate Account', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text(user.isActive ? 'Temporarily lock account from login' : 'Restore full login capabilities', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref.read(devUsersProvider.notifier).toggleActive(user.staffId);
                  ref.invalidate(wardStaffListProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${user.name} is now ${user.isActive ? 'Deactivated' : 'Active'}')),
                  );
                },
              ),

              // Delete User Option
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                title: const Text('Delete User Account', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text('Remove account from dev directory', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref.read(devUsersProvider.notifier).deleteUser(user.staffId);
                  ref.invalidate(wardStaffListProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Deleted ${user.name}')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // RESET PIN DIALOG
  // ==========================================
  void _showResetPinDialog(DevUserItem user) {
    final pinController = TextEditingController(text: user.pin);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF1E293B))),
        title: Text('Reset PIN for ${user.name}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter new 4-digit development PIN:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 4),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFF1E293B),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () {
              final newPin = pinController.text.trim();
              if (newPin.length == 4) {
                ref.read(devUsersProvider.notifier).resetPin(user.staffId, newPin);
                ref.invalidate(wardStaffListProvider);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('PIN updated to $newPin for ${user.name}')),
                );
              }
            },
            child: const Text('Save PIN', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // CREATE / ADD USER DIALOG
  // ==========================================
  void _showAddUserDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final pinCtrl = TextEditingController(text: '1234');
    String selectedRole = 'Nurse';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF1E293B))),
              title: const Row(
                children: [
                  Icon(Icons.person_add, color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 8),
                  Text('Create Staff Account', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Full Name
                    const Text('Staff Full Name', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Brenda Mwangi, RN',
                        hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        filled: true,
                        fillColor: Color(0xFF1E293B),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Email / Handle
                    const Text('Email / Dev Handle', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: emailCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'e.g. brenda.m@oravi.dev',
                        hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        filled: true,
                        fillColor: Color(0xFF1E293B),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Role Selector
                    const Text('Staff Role', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: ['Nurse', 'Doctor', 'Ward Manager'].map((role) {
                        final isSel = selectedRole == role;
                        return Expanded(
                          child: InkWell(
                            onTap: () => setDialogState(() => selectedRole = role),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: isSel ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isSel ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                role,
                                style: TextStyle(fontSize: 10, color: isSel ? Colors.white : const Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    // 4-Digit Quick PIN
                    const Text('4-Digit Quick PIN', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: pinCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      style: const TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 4),
                      decoration: const InputDecoration(
                        hintText: '1234',
                        filled: true,
                        fillColor: Color(0xFF1E293B),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final email = emailCtrl.text.trim();
                    final pin = pinCtrl.text.trim();

                    if (name.isNotEmpty && pin.length == 4) {
                      final generatedId = 'DEV-${DateTime.now().millisecondsSinceEpoch % 10000}';
                      ref.read(devUsersProvider.notifier).addUser(
                            DevUserItem(
                              staffId: generatedId,
                              name: name,
                              email: email.isNotEmpty ? email : '${name.toLowerCase().replaceAll(' ', '.')}@oravi.dev',
                              role: selectedRole,
                              ward: 'Medical',
                              isActive: true,
                              lastLogin: 'Just now',
                              pin: pin,
                            ),
                          );
                      ref.invalidate(wardStaffListProvider);
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Created $selectedRole: $name (PIN: $pin)')),
                      );
                    }
                  },
                  child: const Text('Create User', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // SIDEBAR DRAWER (MATCHING USER MOCKUP SIDEBAR)
  // ==========================================
  Widget _buildSidebarDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF070E1E),
      child: SafeArea(
        child: Column(
          children: [
            // Brand Logo & Title
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.monitor_heart, color: Color(0xFF38BDF8), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ORAVI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.0)),
                      Text('Better Workflows. Safer Care.', style: TextStyle(fontSize: 9, color: Color(0xFF64748B))),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF162540), height: 1),

            // Navigation Links
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                children: [
                  _buildSidebarItem(icon: Icons.dashboard, title: 'Dashboard', isSelected: true),
                  _buildSidebarItem(icon: Icons.people_outline, title: 'User Management'),
                  _buildSidebarItem(icon: Icons.local_hospital_outlined, title: 'Hospital Setup'),
                  _buildSidebarItem(
                    icon: Icons.bed_outlined,
                    title: 'Wards & Beds',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DigitalWhiteboardScreen()),
                      );
                    },
                  ),
                  _buildSidebarItem(icon: Icons.groups_outlined, title: 'Patients'),
                  _buildSidebarItem(icon: Icons.assignment_ind_outlined, title: 'Assignments'),
                  _buildSidebarItem(icon: Icons.chat_bubble_outline, title: 'Messages'),
                  _buildSidebarItem(icon: Icons.settings_outlined, title: 'System Settings'),
                ],
              ),
            ),

            // Environment Banner Footer
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1426),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF162540)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Icon(Icons.circle, size: 6, color: Color(0xFF10B981)),
                      SizedBox(width: 6),
                      Text('Development Environment', style: TextStyle(fontSize: 10, color: Color(0xFF34D399), fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SizedBox(height: 2),
                  Text('You are using dev data', style: TextStyle(fontSize: 9, color: Color(0xFF64748B))),
                  SizedBox(height: 6),
                  Text('ORAVI v1.0.0-dev · Build 2026.10.29', style: TextStyle(fontSize: 8, color: Color(0xFF475569))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem({required IconData icon, required String title, bool isSelected = false, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF0284C7).withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isSelected ? Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.5)) : null,
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 16, color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8)),
        title: Text(
          title,
          style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? Colors.white : const Color(0xFF94A3B8)),
        ),
        onTap: onTap,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/staff_profile.dart';
import '../providers/auth_providers.dart';
import '../ward_board_screen.dart';
import '../admin/dev_admin_dashboard_screen.dart';

/// Digital ID Lockscreen with 4-Digit Quick PIN Unlock (Milestone 7).
/// Implements clinical bedside authentication with zero role selection.
class DigitalIdLockscreen extends ConsumerStatefulWidget {
  const DigitalIdLockscreen({super.key});

  @override
  ConsumerState<DigitalIdLockscreen> createState() => _DigitalIdLockscreenState();
}

class _DigitalIdLockscreenState extends ConsumerState<DigitalIdLockscreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openPinModal(BuildContext context, StaffProfile staff) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PinKeypadModal(staff: staff),
    );
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(wardStaffListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Deep Slate Clinical Navy
      body: SafeArea(
        child: Column(
          children: [
            // --- Ward Brand Header ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
                        ),
                        child: const Icon(Icons.badge_outlined, color: Color(0xFF38BDF8), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ORAVI CLINICAL STATION',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Text(
                                'Ward 4B',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF059669).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF059669)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(radius: 3, backgroundColor: Color(0xFF10B981)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Active Shift',
                                      style: TextStyle(
                                        color: Color(0xFF34D399),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      // One-tap button on login screen to access Dev Admin Dashboard
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const DevAdminDashboardScreen()),
                          );
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.8), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.admin_panel_settings_outlined, size: 14, color: Color(0xFF38BDF8)),
                              SizedBox(width: 5),
                              Text(
                                'Dev Admin',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF38BDF8),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select your Digital ID badge to resume charting:',
                    style: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // --- Fast Search Filter ---
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Search by name, initials, or staff ID...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8), size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Color(0xFF94A3B8), size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- Digital ID Cards Grid ---
            Expanded(
              child: staffAsync.when(
                data: (staffList) {
                  final filtered = staffList.where((s) {
                    if (_searchQuery.isEmpty) return true;
                    final nameMatch = s.name.toLowerCase().contains(_searchQuery);
                    final idMatch = s.staffId.toLowerCase().contains(_searchQuery);
                    final initialsMatch = s.initials.toLowerCase().contains(_searchQuery);
                    return nameMatch || idMatch || initialsMatch;
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_search_outlined, size: 48, color: Color(0xFF64748B)),
                          const SizedBox(height: 12),
                          Text(
                            'No staff member matching "$_searchQuery"',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.92,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final staff = filtered[index];
                      return _DigitalIdCard(
                        staff: staff,
                        onTap: () => _openPinModal(context, staff),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
                ),
                error: (err, _) => Center(
                  child: Text('Error loading staff: $err', style: const TextStyle(color: Colors.red)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Clinical Badge Card styling.
class _DigitalIdCard extends StatelessWidget {
  final StaffProfile staff;
  final VoidCallback onTap;

  const _DigitalIdCard({
    required this.staff,
    required this.onTap,
  });

  Color _parseAvatarColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return const Color(0xFF059669);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarColor = _parseAvatarColor(staff.avatarColor);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF334155), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Top Badge Clip Hole (Lanyard effect)
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),

            // Nurse Avatar with Initials
            CircleAvatar(
              radius: 26,
              backgroundColor: avatarColor.withValues(alpha: 0.2),
              child: Text(
                staff.initials,
                style: TextStyle(
                  color: avatarColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Nurse Name
            Text(
              staff.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),

            // Role Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: staff.isDoctorOnCall
                    ? const Color(0xFF7C3AED).withValues(alpha: 0.2)
                    : staff.isChargeNurse
                        ? const Color(0xFF2563EB).withValues(alpha: 0.2)
                        : const Color(0xFF059669).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                staff.formattedRole,
                style: TextStyle(
                  color: staff.isDoctorOnCall
                      ? const Color(0xFFA78BFA)
                      : staff.isChargeNurse
                          ? const Color(0xFF60A5FA)
                          : const Color(0xFF34D399),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Staff ID
            Text(
              staff.staffId,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 4-Digit Quick PIN Keypad Modal.
class _PinKeypadModal extends ConsumerStatefulWidget {
  final StaffProfile staff;

  const _PinKeypadModal({required this.staff});

  @override
  ConsumerState<_PinKeypadModal> createState() => _PinKeypadModalState();
}

class _PinKeypadModalState extends ConsumerState<_PinKeypadModal> {
  String _enteredPin = '';
  String? _localError;

  void _handleKeyTap(String key) {
    if (_enteredPin.length < 4) {
      setState(() {
        _enteredPin += key;
        _localError = null;
      });

      if (_enteredPin.length == 4) {
        _submitPin();
      }
    }
  }

  void _handleBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _localError = null;
      });
    }
  }

  Future<void> _submitPin() async {
    final authCtrl = ref.read(authControllerProvider.notifier);
    final success = await authCtrl.verifyAndLogin(widget.staff.staffId, _enteredPin);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(); // Close modal
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WardBoardScreen()),
      );
    } else {
      final state = ref.read(authControllerProvider);
      setState(() {
        _localError = state.errorMessage ?? 'Invalid PIN';
        _enteredPin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFF334155), width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Close drag indicator
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF475569),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Selected Staff Info
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.2),
                child: Text(
                  widget.staff.initials,
                  style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.staff.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    '${widget.staff.formattedRole} • ${widget.staff.staffId}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          const Text(
            'Enter 4-Digit Quick PIN',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),

          // 4 Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final isFilled = index < _enteredPin.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled ? const Color(0xFF38BDF8) : Colors.transparent,
                  border: Border.all(
                    color: isFilled ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                    width: 2,
                  ),
                ),
              );
            }),
          ),

          if (_localError != null) ...[
            const SizedBox(height: 12),
            Text(
              _localError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFF87171), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],

          if (authState.isLoading) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: Color(0xFF38BDF8), strokeWidth: 2),
          ] else ...[
            const SizedBox(height: 20),
            // Numpad Keypad (1 - 9, 0, Backspace)
            _buildNumpad(),
          ],
        ],
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['1', '2', '3'].map((k) => _buildKey(k)).toList(),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['4', '5', '6'].map((k) => _buildKey(k)).toList(),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['7', '8', '9'].map((k) => _buildKey(k)).toList(),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 72, height: 56), // Placeholder
            _buildKey('0'),
            InkWell(
              onTap: _handleBackspace,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 72,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.backspace_outlined, color: Color(0xFF94A3B8), size: 22),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKey(String text) {
    return InkWell(
      onTap: () => _handleKeyTap(text),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 72,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

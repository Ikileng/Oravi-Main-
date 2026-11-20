import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/staff_profile.dart';
import '../../data/ward_board_service.dart';
import '../providers/auth_providers.dart';

/// Profile and contactability settings for the signed-in clinician.
class ProfileScreen extends ConsumerStatefulWidget {
  final StaffProfile staff;

  const ProfileScreen({required this.staff, super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late bool _available;
  bool _updatingAvailability = true;
  String? _availabilityError;

  @override
  void initState() {
    super.initState();
    _available = ref.read(clinicianAvailabilityProvider);
    _loadAvailability();
  }

  WardBoardService get _api =>
      WardBoardService(getAccessToken: () => ref.read(authAccessTokenProvider));

  Future<void> _loadAvailability() async {
    try {
      final value = await _api.availability();
      if (!mounted) return;
      ref.read(clinicianAvailabilityProvider.notifier).setAvailable(value);
      setState(() {
        _available = value;
        _updatingAvailability = false;
        _availabilityError = null;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _availabilityError =
              'Connect to Oravi to load availability. Tap to retry.';
          _updatingAvailability = false;
        });
    }
  }

  Future<void> _setAvailability(bool value) async {
    if (_updatingAvailability || value == _available) return;
    setState(() {
      _updatingAvailability = true;
    });
    try {
      final token = ref.read(authAccessTokenProvider);
      if (token == null || token.isEmpty) {
        throw StateError('Your Oravi session is no longer active.');
      }
      await _api.availability(value: value);
      if (!mounted) return;
      ref.read(clinicianAvailabilityProvider.notifier).setAvailable(value);
      setState(() {
        _available = value;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Availability could not be updated: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingAvailability = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.staff;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14527C),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Profile'),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildIdentityHeader(staff),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              children: [
                if (_availabilityError != null)
                  TextButton(
                    onPressed: _loadAvailability,
                    child: Text(_availabilityError!),
                  )
                else
                  _buildAvailabilityCard(),
                const SizedBox(height: 14),
                _buildSettingsCard(),
                const SizedBox(height: 18),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 15,
                      color: Color(0xFF94A3B8),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Protected by hospital security policies',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityHeader(StaffProfile staff) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
    decoration: const BoxDecoration(
      color: Color(0xFF14527C),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
    ),
    child: Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'PROFILE',
            style: TextStyle(
              color: Color(0xFFB9D8EA),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 62,
          height: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFE5EEF6),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            staff.initials,
            style: const TextStyle(
              color: Color(0xFF1D557D),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          staff.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${staff.formattedRole} · ${staff.wardId.isEmpty ? 'Oravi' : staff.wardId}',
          style: const TextStyle(color: Color(0xFFC6DCEB), fontSize: 12),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_user_outlined, color: Colors.white, size: 14),
              SizedBox(width: 5),
              Text(
                'Identity verified',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildAvailabilityCard() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: _cardDecoration(),
    child: Row(
      children: [
        _settingIcon(Icons.person_outline, const Color(0xFF2B9474)),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Available',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF17324D),
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Colleagues can contact you',
                style: TextStyle(color: Color(0xFF8A9AAF), fontSize: 11),
              ),
            ],
          ),
        ),
        _updatingAvailability
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Switch.adaptive(
                value: _available,
                onChanged: _setAvailability,
                activeTrackColor: const Color(0xFF2B9474),
              ),
      ],
    ),
  );

  Widget _buildSettingsCard() => Container(
    decoration: _cardDecoration(),
    child: Column(
      children: [
        _settingRow(
          Icons.person_outline,
          'Personal information',
          'Name, role, contact details',
        ),
        _settingRow(
          Icons.notifications_none_outlined,
          'Notifications',
          'Messages, tasks, and escalation',
        ),
        _settingRow(
          Icons.shield_outlined,
          'Privacy & security',
          'Passcode, Face ID, devices',
        ),
        _settingRow(
          Icons.assignment_outlined,
          'Shift preferences',
          'Units and handoff settings',
          last: true,
        ),
      ],
    ),
  );

  Widget _settingRow(
    IconData icon,
    String title,
    String subtitle, {
    bool last = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _settingIcon(icon, const Color(0xFF9AAABD)),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF17324D),
              fontSize: 13,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF8A9AAF), fontSize: 10),
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: Color(0xFF9AAABD),
            size: 20,
          ),
        ),
        if (!last) const Divider(height: 1, color: Color(0xFFE8EDF2)),
      ],
    ),
  );

  Widget _settingIcon(IconData icon, Color color) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Icon(icon, color: color, size: 21),
  );

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xFFE4EAF0)),
  );
}

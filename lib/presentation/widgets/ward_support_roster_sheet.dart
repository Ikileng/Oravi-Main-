import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/whiteboard_models.dart';
import '../providers/whiteboard_providers.dart';

/// Interactive modal sheet displaying and editing the Ward Support Team duty roster.
/// When [hasWriteAccess] is true (Nurse In-Charge), contacts can be edited in real-time.
class WardSupportRosterSheet extends ConsumerWidget {
  final WardSupportRoster roster;
  final bool hasWriteAccess;

  const WardSupportRosterSheet({
    super.key,
    required this.roster,
    this.hasWriteAccess = false,
  });

  static const List<String> _kCandidateNurses = [
    'Nurse A',
    'Nurse B',
    'Nurse C',
    'Nurse D',
    'Nurse E',
    'Grace Achieng, RN',
    'Faith Njeri, RN',
    'Mary Wanjiku, RN',
    'Sarah Otieno, RN',
    'Jane Muthoni, RN',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch live roster so any edits update the UI reactively
    final liveRoster = ref.watch(wardSupportRosterProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF475569),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header with Badge
          Row(
            children: [
              const Icon(Icons.contact_phone, color: Color(0xFF38BDF8), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Ward Support Team on Duty',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasWriteAccess
                      ? const Color(0xFF0284C7).withValues(alpha: 0.2)
                      : const Color(0xFF334155).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasWriteAccess ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  hasWriteAccess ? '✏ Editable' : '🔒 Read-Only',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: hasWriteAccess ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasWriteAccess
                ? 'Tap any cadre to edit contacts or phone numbers.'
                : 'Physical whiteboard duty roster contacts (Read-only for bedside staff).',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 16),

          // Scrollable list of roster contacts
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildContactCard(
                    context: context,
                    ref: ref,
                    cadre: 'WARD MANAGER',
                    dayContact: liveRoster.wardManager,
                    nightContact: '',
                    icon: Icons.admin_panel_settings,
                    cadreColor: const Color(0xFFA855F7),
                    isNurseRole: true,
                    onSave: (day, night) {
                      ref.read(wardSupportRosterProvider.notifier).updateRoster(
                            liveRoster.copyWith(wardManager: day),
                          );
                    },
                  ),
                  _buildContactCard(
                    context: context,
                    ref: ref,
                    cadre: 'IN-CHARGE NURSE',
                    dayContact: liveRoster.inchargeNurseDay,
                    nightContact: liveRoster.inchargeNurseNight,
                    icon: Icons.local_hospital,
                    cadreColor: const Color(0xFF38BDF8),
                    isNurseRole: true,
                    onSave: (day, night) {
                      ref.read(wardSupportRosterProvider.notifier).updateRoster(
                            liveRoster.copyWith(
                              inchargeNurseDay: day,
                              inchargeNurseNight: night,
                            ),
                          );
                    },
                  ),
                  _buildContactCard(
                    context: context,
                    ref: ref,
                    cadre: 'TEAM LEADER',
                    dayContact: liveRoster.teamLeader,
                    nightContact: '',
                    icon: Icons.person,
                    cadreColor: const Color(0xFF38BDF8),
                    isNurseRole: true,
                    onSave: (day, night) {
                      ref.read(wardSupportRosterProvider.notifier).updateRoster(
                            liveRoster.copyWith(teamLeader: day),
                          );
                    },
                  ),
                  _buildContactCard(
                    context: context,
                    ref: ref,
                    cadre: 'DUTY LEADER',
                    dayContact: liveRoster.dutyLeader,
                    nightContact: '',
                    icon: Icons.assignment_outlined,
                    cadreColor: const Color(0xFFA855F7),
                    isNurseRole: true,
                    onSave: (day, night) {
                      ref.read(wardSupportRosterProvider.notifier).updateRoster(
                            liveRoster.copyWith(dutyLeader: day),
                          );
                    },
                  ),
                  _buildContactCard(
                    context: context,
                    ref: ref,
                    cadre: 'DISCHARGE NURSE',
                    dayContact: liveRoster.dischargeNurse,
                    nightContact: '',
                    icon: Icons.assignment_turned_in_outlined,
                    cadreColor: const Color(0xFF34D399),
                    isNurseRole: true,
                    onSave: (day, night) {
                      ref.read(wardSupportRosterProvider.notifier).updateRoster(
                            liveRoster.copyWith(dischargeNurse: day),
                          );
                    },
                  ),
                  _buildContactCard(
                    context: context,
                    ref: ref,
                    cadre: 'PATIENT CARE ATTENDANT (PCA)',
                    dayContact: liveRoster.pcaDay,
                    nightContact: liveRoster.pcaNight,
                    icon: Icons.person_pin,
                    cadreColor: const Color(0xFF2DD4BF),
                    isNurseRole: true,
                    onSave: (day, night) {
                      ref.read(wardSupportRosterProvider.notifier).updateRoster(
                            liveRoster.copyWith(
                              pcaDay: day,
                              pcaNight: night,
                            ),
                          );
                    },
                  ),
                  _buildContactCard(
                    context: context,
                    ref: ref,
                    cadre: 'HOUSEKEEPER',
                    dayContact: liveRoster.housekeeperDay,
                    nightContact: liveRoster.housekeeperNight,
                    icon: Icons.cleaning_services,
                    cadreColor: const Color(0xFFF59E0B),
                    isNurseRole: false,
                    onSave: (day, night) {
                      ref.read(wardSupportRosterProvider.notifier).updateRoster(
                            liveRoster.copyWith(
                              housekeeperDay: day,
                              housekeeperNight: night,
                            ),
                          );
                    },
                  ),
                  _buildContactCard(
                    context: context,
                    ref: ref,
                    cadre: 'CATERING (KITCHEN & MEALS)',
                    dayContact: liveRoster.cateringDayPhone,
                    nightContact: liveRoster.cateringNightPhone,
                    icon: Icons.restaurant,
                    cadreColor: const Color(0xFF10B981),
                    isNurseRole: false,
                    isPhone: true,
                    onSave: (day, night) {
                      ref.read(wardSupportRosterProvider.notifier).updateRoster(
                            liveRoster.copyWith(
                              cateringDayPhone: day,
                              cateringNightPhone: night,
                            ),
                          );
                    },
                  ),
                  _buildContactCard(
                    context: context,
                    ref: ref,
                    cadre: 'FIRE MARSHALL',
                    dayContact: liveRoster.fireMarshall,
                    nightContact: '',
                    icon: Icons.local_fire_department,
                    cadreColor: const Color(0xFFEF4444),
                    isNurseRole: false,
                    onSave: (day, night) {
                      ref.read(wardSupportRosterProvider.notifier).updateRoster(
                            liveRoster.copyWith(fireMarshall: day),
                          );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard({
    required BuildContext context,
    required WidgetRef ref,
    required String cadre,
    required String dayContact,
    required String nightContact,
    required IconData icon,
    required Color cadreColor,
    required bool isNurseRole,
    bool isPhone = false,
    required void Function(String day, String night) onSave,
  }) {
    final hasNight = nightContact.isNotEmpty ||
        cadre.contains('IN-CHARGE') ||
        cadre.contains('PCA') ||
        cadre.contains('HOUSEKEEPER') ||
        cadre.contains('CATERING');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF131D33),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.0),
      ),
      child: InkWell(
        onTap: () {
          if (hasWriteAccess) {
            _showEditContactDialog(
              context: context,
              cadre: cadre,
              initialDay: dayContact,
              initialNight: nightContact,
              hasNight: hasNight,
              isNurseRole: isNurseRole,
              isPhone: isPhone,
              onSave: onSave,
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Read-Only: Only Nurse In-Charge has write permissions to edit the roster.'),
                backgroundColor: Color(0xFF475569),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: cadreColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: cadreColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cadre,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cadreColor),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dayContact.isNotEmpty ? 'Day: $dayContact' : 'Day: —',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    if (hasNight)
                      Text(
                        nightContact.isNotEmpty ? 'Night: $nightContact' : 'Night: —',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                  ],
                ),
              ),
              if (hasWriteAccess)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF38BDF8)),
                )
              else if (isPhone && dayContact.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.call, color: Color(0xFF10B981), size: 18),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Dialing $dayContact ($cadre)...')),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditContactDialog({
    required BuildContext context,
    required String cadre,
    required String initialDay,
    required String initialNight,
    required bool hasNight,
    required bool isNurseRole,
    required bool isPhone,
    required void Function(String day, String night) onSave,
  }) {
    final dayController = TextEditingController(text: initialDay);
    final nightController = TextEditingController(text: initialNight);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF1E293B), width: 1.2),
              ),
              title: Row(
                children: [
                  const Icon(Icons.edit, size: 18, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit $cadre',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasNight ? 'Day Shift Contact / Phone' : 'Contact / Phone',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: dayController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: isPhone ? 'e.g. 0721299472' : 'Enter name or contact',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF334155)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                        ),
                      ),
                    ),

                    if (isNurseRole) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Quick Select Staff:',
                        style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _kCandidateNurses.take(5).map((nurse) {
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                dayController.text = nurse;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                nurse,
                                style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8), fontWeight: FontWeight.w600),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    if (hasNight) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Night Shift Contact / Phone',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nightController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: isPhone ? 'e.g. 0792777972' : 'Enter night contact',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    onSave(dayController.text.trim(), nightController.text.trim());
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Updated $cadre on duty roster'),
                        backgroundColor: const Color(0xFF0284C7),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: const Text('Save Contact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

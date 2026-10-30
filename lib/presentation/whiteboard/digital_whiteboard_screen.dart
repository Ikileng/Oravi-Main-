import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/whiteboard_models.dart';
import '../providers/whiteboard_providers.dart';
import '../providers/auth_providers.dart';
import '../theme/clinical_theme.dart';
import '../widgets/ward_support_roster_sheet.dart';
import '../widgets/ward_selection_dialog.dart';

/// The Digital Whiteboard replicating the physical Gertrude's Children's Hospital board
class DigitalWhiteboardScreen extends ConsumerStatefulWidget {
  const DigitalWhiteboardScreen({super.key});

  @override
  ConsumerState<DigitalWhiteboardScreen> createState() => _DigitalWhiteboardScreenState();
}

class _DigitalWhiteboardScreenState extends ConsumerState<DigitalWhiteboardScreen> {
  final Set<String> _selectedBeds = {};

  void _toggleBedSelection(String bedNumber) {
    setState(() {
      if (_selectedBeds.contains(bedNumber)) {
        _selectedBeds.remove(bedNumber);
      } else {
        _selectedBeds.add(bedNumber);
      }
    });
  }

  void selectBracket(String startBed, String endBed, List<WhiteboardBedAssignment> beds) {
    final startIdx = beds.indexWhere((b) => b.bedNumber == startBed);
    final endIdx = beds.indexWhere((b) => b.bedNumber == endBed);
    if (startIdx != -1 && endIdx != -1) {
      final low = startIdx < endIdx ? startIdx : endIdx;
      final high = startIdx > endIdx ? startIdx : endIdx;
      setState(() {
        for (int i = low; i <= high; i++) {
          _selectedBeds.add(beds[i].bedNumber);
        }
      });
    }
  }

  void _openNurseAssignSheet(List<String> bedNumbers) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ClinicalTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return _NurseAssignmentSheet(
          selectedBeds: bedNumbers,
          onAssigned: (nurseId) {
            ref.read(whiteboardAssignmentsProvider.notifier).batchAssignBeds(bedNumbers, nurseId);
            setState(() => _selectedBeds.clear());
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Assigned ${bedNumbers.length} beds to ${ClinicalTheme.formatAuthorDisplayName(nurseId)}'),
                backgroundColor: ClinicalTheme.nurseBlue,
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ward = ref.watch(selectedWardProvider);
    final beds = ref.watch(whiteboardAssignmentsProvider);
    final roster = ref.watch(wardSupportRosterProvider);
    final currentStaff = ref.watch(authenticatedStaffProvider);

    return Scaffold(
      backgroundColor: ClinicalTheme.background,
      appBar: AppBar(
        titleSpacing: 12,
        title: InkWell(
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
                  ward.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, color: ClinicalTheme.nurseBlue, size: 20),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Ward Support Team (Sidebar Contacts)',
            icon: const Icon(Icons.contacts, color: ClinicalTheme.routineTeal),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => WardSupportRosterSheet(roster: roster),
              );
            },
          ),
          IconButton(
            tooltip: 'Accept My Assigned Beds',
            icon: const Icon(Icons.check_circle_outline, color: ClinicalTheme.successGreen),
            onPressed: () {
              if (currentStaff != null) {
                final myBeds = beds
                    .where((b) => b.dayShiftNurseId == currentStaff.staffId && b.status == 'pending')
                    .map((b) => b.bedNumber)
                    .toList();
                if (myBeds.isNotEmpty) {
                  ref.read(whiteboardAssignmentsProvider.notifier).acceptBeds(myBeds, currentStaff.staffId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Accepted care for ${myBeds.length} beds: ${myBeds.join(", ")}'),
                      backgroundColor: ClinicalTheme.successGreen,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No pending bed assignments for you.')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Subheader: Shift info & Gertrude Date Stamping
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xFF1E293B),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: ClinicalTheme.successGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'DAY SHIFT (07:00 – 19:00)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ClinicalTheme.textPrimary),
                    ),
                  ],
                ),
                Text(
                  'DATE: 30/10/26 • WARD MGR: ${roster.wardManager}',
                  style: const TextStyle(fontSize: 10, color: ClinicalTheme.textMuted, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),

          // Gertrude Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1)),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text('ROOM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ClinicalTheme.textMuted)),
                ),
                SizedBox(
                  width: 56,
                  child: Text('PATIENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ClinicalTheme.textMuted)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('DOCTOR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ClinicalTheme.textMuted)),
                ),
                Expanded(
                  flex: 4,
                  child: Text('NURSE (DAY / NIGHT)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ClinicalTheme.textMuted)),
                ),
                SizedBox(
                  width: 48,
                  child: Text('STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ClinicalTheme.textMuted)),
                ),
              ],
            ),
          ),

          // Gertrude Table Rows
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: beds.length,
              separatorBuilder: (_, _) => const Divider(color: Color(0xFF1E293B), height: 1),
              itemBuilder: (ctx, i) {
                final b = beds[i];
                final isSelected = _selectedBeds.contains(b.bedNumber);
                final isAccepted = b.status == 'accepted';

                return InkWell(
                  onTap: () => _toggleBedSelection(b.bedNumber),
                  child: Container(
                    color: isSelected
                        ? ClinicalTheme.nurseBlue.withValues(alpha: 0.15)
                        : (i % 2 == 0 ? Colors.transparent : const Color(0xFF0B132B).withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        // Room Number
                        SizedBox(
                          width: 44,
                          child: Text(
                            b.bedNumber,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? ClinicalTheme.nurseBlue : Colors.white,
                            ),
                          ),
                        ),

                        // Patient Initials
                        SizedBox(
                          width: 56,
                          child: Text(
                            b.patientInitials.isNotEmpty ? b.patientInitials : '—',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ClinicalTheme.textPrimary),
                          ),
                        ),

                        // Doctor
                        Expanded(
                          flex: 3,
                          child: Text(
                            b.admittingDoctor.isNotEmpty
                                ? ClinicalTheme.formatAuthorDisplayName(b.admittingDoctor)
                                : '—',
                            style: const TextStyle(fontSize: 11, color: ClinicalTheme.doctorPink, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // Nurse Day / Night (Curly Bracket visualization)
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.dayShiftNurseId != null
                                    ? ClinicalTheme.formatAuthorDisplayName(b.dayShiftNurseId!)
                                    : 'UNASSIGNED',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: b.dayShiftNurseId != null ? ClinicalTheme.nurseBlue : ClinicalTheme.urgentAmber,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (b.nightShiftNurseId != null)
                                Text(
                                  'Night: ${ClinicalTheme.formatAuthorDisplayName(b.nightShiftNurseId!)}',
                                  style: const TextStyle(fontSize: 9, color: ClinicalTheme.textMuted),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),

                        // Status Badge
                        SizedBox(
                          width: 48,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: isAccepted
                                  ? ClinicalTheme.successGreen.withValues(alpha: 0.2)
                                  : ClinicalTheme.urgentAmber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Center(
                              child: Text(
                                isAccepted ? 'ACTIVE' : 'PENDING',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: isAccepted ? ClinicalTheme.successGreen : ClinicalTheme.urgentAmber,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Floating Batch Selection Bar
          if (_selectedBeds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFF1E293B),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selectedBeds.length} Beds Selected: ${_selectedBeds.join(", ")}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedBeds.clear()),
                    child: const Text('Clear', style: TextStyle(color: ClinicalTheme.textMuted, fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ClinicalTheme.nurseBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.person_add, size: 16, color: Colors.white),
                    label: const Text('Assign Nurse', style: TextStyle(fontSize: 12, color: Colors.white)),
                    onPressed: () => _openNurseAssignSheet(_selectedBeds.toList()),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NurseAssignmentSheet extends StatefulWidget {
  final List<String> selectedBeds;
  final ValueChanged<String> onAssigned;

  const _NurseAssignmentSheet({required this.selectedBeds, required this.onAssigned});

  @override
  State<_NurseAssignmentSheet> createState() => _NurseAssignmentSheetState();
}

class _NurseAssignmentSheetState extends State<_NurseAssignmentSheet> {
  String _searchQuery = '';

  // Canonical registered Ward Nurses
  final List<Map<String, String>> _nurses = [
    {'id': 'NUR-403', 'name': 'Glory D., RN (Faith Njeri)', 'role': 'Ward Nurse'},
    {'id': 'NUR-401', 'name': 'Mary Wanjiku, RN (S. Barasa)', 'role': 'Ward Nurse'},
    {'id': 'NUR-402', 'name': 'Grace Achieng, RN', 'role': 'Charge Nurse'},
    {'id': 'NUR-404', 'name': 'Sarah Otieno, RN (Okema)', 'role': 'Ward Nurse'},
    {'id': 'NUR-405', 'name': 'Jane Muthoni, RN (Phenina I)', 'role': 'Ward Nurse'},
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _nurses.where((n) {
      final q = _searchQuery.toLowerCase();
      return n['name']!.toLowerCase().contains(q) || n['id']!.toLowerCase().contains(q);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Assign ${widget.selectedBeds.length} Beds (${widget.selectedBeds.join(", ")})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: ClinicalTheme.nurseBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Ratio: 1:${widget.selectedBeds.length}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ClinicalTheme.nurseBlue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search Field
          TextField(
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 18, color: ClinicalTheme.textMuted),
              hintText: 'Search nurse by name or staff ID...',
              hintStyle: const TextStyle(color: ClinicalTheme.textMuted, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 12),

          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(color: Color(0xFF334155), height: 1),
              itemBuilder: (ctx, i) {
                final nurse = filtered[i];
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    nurse['name']!,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  subtitle: Text(
                    '${nurse['role']} • ${nurse['id']}',
                    style: const TextStyle(fontSize: 11, color: ClinicalTheme.textMuted),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: ClinicalTheme.nurseBlue),
                  onTap: () => widget.onAssigned(nurse['id']!),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../domain/models/whiteboard_models.dart';
import '../theme/clinical_theme.dart';

class WardSupportRosterSheet extends StatelessWidget {
  final WardSupportRoster roster;

  const WardSupportRosterSheet({super.key, required this.roster});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: ClinicalTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const Row(
            children: [
              Icon(Icons.contact_phone, color: ClinicalTheme.nurseBlue, size: 20),
              SizedBox(width: 8),
              Text(
                'Ward Support Team on Duty',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Physical whiteboard duty roster contacts (Gertrude\'s Sidebar)',
            style: TextStyle(fontSize: 12, color: ClinicalTheme.textMuted),
          ),
          const SizedBox(height: 16),

          _buildContactRow(
            cadre: 'WARD MANAGER',
            dayContact: roster.wardManager,
            nightContact: '',
            icon: Icons.admin_panel_settings,
            cadreColor: ClinicalTheme.inChargePurple,
          ),
          _buildContactRow(
            cadre: 'IN-CHARGE NURSE',
            dayContact: roster.inchargeNurseDay,
            nightContact: roster.inchargeNurseNight,
            icon: Icons.local_hospital,
            cadreColor: ClinicalTheme.nurseBlue,
          ),
          _buildContactRow(
            cadre: 'PATIENT CARE ATTENDANT (PCA)',
            dayContact: roster.pcaDay,
            nightContact: roster.pcaNight,
            icon: Icons.person_pin,
            cadreColor: ClinicalTheme.routineTeal,
          ),
          _buildContactRow(
            cadre: 'HOUSEKEEPER',
            dayContact: roster.housekeeperDay,
            nightContact: roster.housekeeperNight,
            icon: Icons.cleaning_services,
            cadreColor: ClinicalTheme.urgentAmber,
          ),
          _buildContactRow(
            cadre: 'CATERING (KITCHEN & MEALS)',
            dayContact: roster.cateringDayPhone,
            nightContact: roster.cateringNightPhone,
            icon: Icons.restaurant,
            cadreColor: ClinicalTheme.successGreen,
            isPhone: true,
          ),
          _buildContactRow(
            cadre: 'FIRE MARSHALL',
            dayContact: roster.fireMarshall,
            nightContact: '',
            icon: Icons.local_fire_department,
            cadreColor: ClinicalTheme.criticalRed,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildContactRow({
    required String cadre,
    required String dayContact,
    required String nightContact,
    required IconData icon,
    required Color cadreColor,
    bool isPhone = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cadreColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: cadreColor),
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
                if (nightContact.isNotEmpty)
                  Text(
                    'Night: $nightContact',
                    style: const TextStyle(fontSize: 11, color: ClinicalTheme.textMuted),
                  ),
              ],
            ),
          ),
          if (isPhone && dayContact.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.call, color: ClinicalTheme.successGreen, size: 18),
              onPressed: () {},
            ),
        ],
      ),
    );
  }
}

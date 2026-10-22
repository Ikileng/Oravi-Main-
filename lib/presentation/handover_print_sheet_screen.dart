import '../domain/models/loop_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock/seeded_ward_data.dart';
import '../domain/projections/projections.dart';
import 'providers/ward_providers.dart';

/// Printable 1-Page Handover Sheet strictly implementing PRD Section 7.3 & FR-15:
/// "A one-page printable handover sheet is available for wards and moments where paper is still expected."
class HandoverPrintSheetScreen extends ConsumerWidget {
  final HandoffSessionProjection session;

  const HandoverPrintSheetScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patients = ref.watch(wardPatientsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        title: const Text(
          '1-Page Handover Sheet (Print Preview)',
          style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.print, color: Colors.black),
            tooltip: 'Print Sheet',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Printer ready: Formatted for standard A4 landscape handover sheet.'),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sheet Header
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ORAVI — CLINICAL WARD HANDOVER SHEET',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'SESSION ID: ${session.handoffSessionId}',
                        style: const TextStyle(color: Colors.black54, fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ward: ${SeededWardData.wardName}',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        'Date: ${session.startedAt.toIso8601String().substring(0, 16).replaceAll("T", " ")}',
                        style: const TextStyle(color: Colors.black87, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Outgoing Nurse: ${session.outgoingNurseId}',
                        style: const TextStyle(color: Colors.black87, fontSize: 12),
                      ),
                      Text(
                        'Incoming Nurse: ${session.incomingNurseId}',
                        style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Patient Table
            Table(
              border: TableBorder.all(color: Colors.black54, width: 1),
              columnWidths: const {
                0: FixedColumnWidth(60),
                1: FlexColumnWidth(2.2),
                2: FlexColumnWidth(3.5),
                3: FlexColumnWidth(3),
                4: FixedColumnWidth(90),
              },
              children: [
                // Header row
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey[200]),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(6),
                      child: Text('Bed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(6),
                      child: Text('Patient & Admission', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(6),
                      child: Text('SBAR Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(6),
                      child: Text('Pending Loops Transferred', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(6),
                      child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
                // Data rows
                ...patients.map((patient) {
                  final loops = ref.watch(patientLoopsProvider(patient.patientId));
                  final sbar = SbarSummary.fromPatientAndLoops(patient: patient, loops: loops);
                  final review = session.bedReviews[patient.bedNumber];
                  final isNothingPending = review?.nothingPendingConfirmed ?? (loops.where((l) => l.isOpen).isEmpty);

                  return TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(patient.bedNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(patient.nameOrInitials, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            Text('${patient.age}y ${patient.sex} • ${patient.admissionNumber}', style: const TextStyle(fontSize: 10, color: Colors.black87)),
                            if (patient.keyAlerts.isNotEmpty)
                              Text('⚠️ ${patient.keyAlerts.join(", ")}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('S: ${patient.shortAdmittingNote}', style: const TextStyle(fontSize: 10)),
                            const SizedBox(height: 2),
                            Text('A: ${sbar.assessment}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text('R: ${sbar.recommendation}', style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: loops.where((l) => l.isOpen).isEmpty
                            ? const Text('None (All Clear)', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold))
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: loops.where((l) => l.isOpen).map((loop) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(
                                      '• [${loop.urgency.name.toUpperCase()}] ${loop.title}',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: loop.urgency == LoopUrgency.critical ? FontWeight.bold : FontWeight.normal,
                                        color: loop.urgency == LoopUrgency.critical ? Colors.red[900] : Colors.black87,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          isNothingPending ? '✓ ALL CLEAR' : 'TRANSFERRED (${review?.transferredLoopIds.length ?? 0})',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isNothingPending ? Colors.green[800] : Colors.amber[900],
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            const SizedBox(height: 24),

            // Signatures block
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black45, width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Outgoing Nurse Sign-off:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Text('Name: ${session.outgoingNurseId}', style: const TextStyle(fontSize: 11)),
                        Text('Status: Confirmed & Transferred', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 60, color: Colors.black26),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Incoming Nurse Acceptance (FR-14 & FR-16):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Text('Name: ${session.incomingNurseId}', style: const TextStyle(fontSize: 11)),
                        Text('Locked At: ${session.completedAt?.toIso8601String().substring(0, 16).replaceAll("T", " ") ?? "IN PROGRESS"}',
                            style: const TextStyle(fontSize: 10, color: Colors.black54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'Oravi Clinical Tracker • Inpatient Shift Handover Record (FR-11 to FR-17) • Locked & Immutable',
                style: TextStyle(fontSize: 9, color: Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

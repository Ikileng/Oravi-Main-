import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/projections/projections.dart';
import '../providers/ward_providers.dart';
import '../theme/clinical_theme.dart';

/// Modal dialog strictly implementing PRD FR-54:
/// - A Call action prompts for a mandatory one-line outcome note (e.g., 'Agreed to hold dose').
/// - Prevents verbal decision silos by appending the agreed outcome directly into the thread.
class LogCallOutcomeDialog extends StatefulWidget {
  final LoopStateProjection loop;
  final String recipientName;
  final String recipientRole;

  const LogCallOutcomeDialog({
    super.key,
    required this.loop,
    required this.recipientName,
    required this.recipientRole,
  });

  @override
  State<LogCallOutcomeDialog> createState() => _LogCallOutcomeDialogState();
}

class _LogCallOutcomeDialogState extends State<LogCallOutcomeDialog> {
  final TextEditingController _noteController = TextEditingController();
  String? _error;

  final List<String> _quickOutcomes = [
    'Agreed to hold current dose until repeat labs',
    'Order confirmed as charted; monitor vitals 1-hrly',
    'Doctor requested urgent blood gas and will review',
    'No answer; left urgent ward message',
    'Verbally approved dose titration',
  ];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submit(WidgetRef ref) {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      setState(() => _error = 'A one-line outcome note is mandatory to eliminate verbal silos.');
      return;
    }

    ref.read(wardControllerProvider.notifier).logCallOutcome(
          patientId: widget.loop.patientId,
          loopId: widget.loop.loopId,
          recipientId: widget.recipientName,
          recipientRole: widget.recipientRole,
          outcomeNote: note,
        );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        return AlertDialog(
          backgroundColor: ClinicalTheme.surface,
          title: Row(
            children: [
              const Icon(Icons.phone_in_talk, color: ClinicalTheme.routineTeal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Call with ${widget.recipientName}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ClinicalTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: ClinicalTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_clock, size: 16, color: ClinicalTheme.routineTeal),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Target: ${widget.loop.title}',
                          style: const TextStyle(fontSize: 11, color: ClinicalTheme.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Verbal Outcome Summary (Mandatory - FR-54):',
                  style: TextStyle(color: ClinicalTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g., Agreed to hold dose until repeat Hb at 16:00...',
                    hintStyle: const TextStyle(color: ClinicalTheme.textMuted, fontSize: 12),
                    filled: true,
                    fillColor: ClinicalTheme.surfaceElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: ClinicalTheme.border),
                    ),
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(_error!, style: const TextStyle(color: ClinicalTheme.criticalRed, fontSize: 11)),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Quick Outcome Chips:',
                  style: TextStyle(color: ClinicalTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _quickOutcomes.map((text) {
                    return ActionChip(
                      label: Text(text, style: const TextStyle(fontSize: 10)),
                      backgroundColor: ClinicalTheme.surfaceElevated,
                      onPressed: () {
                        setState(() {
                          _noteController.text = text;
                          _error = null;
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: ClinicalTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ClinicalTheme.routineTeal,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _submit(ref),
              child: const Text('Save Outcome to Thread'),
            ),
          ],
        );
      },
    );
  }
}

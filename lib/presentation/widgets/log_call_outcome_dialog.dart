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
  final String recipientId;
  final String recipientName;
  final String recipientRole;
  final int durationSeconds;
  final String? callId;
  final String callStatus;

  const LogCallOutcomeDialog({
    super.key,
    required this.loop,
    required this.recipientId,
    required this.recipientName,
    required this.recipientRole,
    this.durationSeconds = 0,
    this.callId,
    this.callStatus = 'completed',
  });

  @override
  State<LogCallOutcomeDialog> createState() => _LogCallOutcomeDialogState();
}

class _LogCallOutcomeDialogState extends State<LogCallOutcomeDialog> {
  final TextEditingController _noteController = TextEditingController();
  String? _error;
  bool _isSaving = false;

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

  Future<void> _submit(WidgetRef ref) async {
    if (_isSaving) return;
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      setState(
        () => _error = 'Add the agreed outcome before saving to the thread.',
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(wardControllerProvider.notifier)
          .logCallOutcome(
            patientId: widget.loop.patientId,
            loopId: widget.loop.loopId,
            recipientId: widget.recipientId,
            recipientRole: widget.recipientRole,
            outcomeNote: note,
            durationSeconds: widget.durationSeconds,
            callId: widget.callId,
            callStatus: widget.callStatus,
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save the outcome. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: ClinicalTheme.surface,
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ClinicalTheme.routineTeal.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.phone_in_talk,
                color: ClinicalTheme.routineTeal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Document call outcome',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.recipientName,
                    style: const TextStyle(
                      color: ClinicalTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ClinicalTheme.surfaceAccent,
                    borderRadius: BorderRadius.circular(
                      ClinicalTheme.radiusMedium,
                    ),
                    border: Border.all(color: ClinicalTheme.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.medical_information_outlined,
                        size: 19,
                        color: ClinicalTheme.clinicalBlue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Related medical issue',
                              style: TextStyle(
                                color: ClinicalTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.loop.title,
                              style: const TextStyle(
                                color: ClinicalTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'What was agreed?',
                  style: TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Required. This note is added to the medical issue thread so the verbal decision is visible to the care team.',
                  style: TextStyle(
                    color: ClinicalTheme.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteController,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Call outcome',
                    hintText: 'State the decision, action, and any follow-up…',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 18,
                        color: ClinicalTheme.criticalRed,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: ClinicalTheme.criticalRed,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                const Text(
                  'Common outcomes',
                  style: TextStyle(
                    color: ClinicalTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: _quickOutcomes
                      .map(
                        (text) => ActionChip(
                          label: Text(text),
                          onPressed: _isSaving
                              ? null
                              : () {
                                  setState(() {
                                    _noteController.text = text;
                                    _noteController.selection =
                                        TextSelection.collapsed(
                                          offset: text.length,
                                        );
                                    _error = null;
                                  });
                                },
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: ClinicalTheme.routineTeal,
              foregroundColor: Colors.white,
            ),
            onPressed: _isSaving ? null : () => _submit(ref),
            icon: const Icon(Icons.add_comment_outlined),
            label: Text(_isSaving ? 'Saving…' : 'Save to thread'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/loop_enums.dart';
import '../../domain/projections/projections.dart';
import '../providers/ward_providers.dart';
import '../theme/clinical_theme.dart';

/// Modal dialog strictly implementing PRD FR-46 & FR-47:
/// - Closing requires a reason chosen from a short list that depends on thread type.
/// - Mandatory free-text note strictly enforced for 'medication given', 'action taken', and 'other'.
/// - Reason chips never carry clinical judgment ('result received', not 'result normal').
class CloseLoopDialog extends StatefulWidget {
  final LoopStateProjection loop;

  const CloseLoopDialog({super.key, required this.loop});

  @override
  State<CloseLoopDialog> createState() => _CloseLoopDialogState();
}

class _CloseLoopDialogState extends State<CloseLoopDialog> {
  ClosureReasonCode _selectedReason = ClosureReasonCode.resultReceived;
  final TextEditingController _noteController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submitClosure(WidgetRef ref) {
    if (_selectedReason.requiresFreeTextNote && _noteController.text.trim().isEmpty) {
      setState(() {
        _validationError = 'A clinical note is mandatory when selecting "${_selectedReason.wireName}".';
      });
      return;
    }

    ref.read(wardControllerProvider.notifier).closeLoop(
          patientId: widget.loop.patientId,
          loopId: widget.loop.loopId,
          reasonCode: _selectedReason,
          freeTextNote: _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : null,
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
              const Icon(Icons.check_circle_outline, color: ClinicalTheme.successGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Close Loop: ${widget.loop.title}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 1,
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
                if (widget.loop.isCritical)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ClinicalTheme.criticalRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ClinicalTheme.criticalRed),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: ClinicalTheme.criticalRed, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'STAT Critical Loop: Will require confirmation by the opener or senior in charge (PRD FR-51).',
                            style: TextStyle(color: ClinicalTheme.criticalRed, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Text(
                  'Select Closure Reason (FR-46):',
                  style: TextStyle(color: ClinicalTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: ClosureReasonCode.values.map((reason) {
                    final isSelected = _selectedReason == reason;
                    return ChoiceChip(
                      label: Text(
                        _reasonLabel(reason),
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? Colors.white : ClinicalTheme.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: ClinicalTheme.routineTeal,
                      backgroundColor: ClinicalTheme.surfaceElevated,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedReason = reason;
                            _validationError = null;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  _selectedReason.requiresFreeTextNote
                      ? 'Clinical Action Note (Mandatory):'
                      : 'Clinical Action Note (Optional):',
                  style: TextStyle(
                    color: _selectedReason.requiresFreeTextNote ? ClinicalTheme.urgentAmber : ClinicalTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g., 2g IV Ceftriaxone given, site clean...',
                    hintStyle: const TextStyle(color: ClinicalTheme.textMuted, fontSize: 12),
                    filled: true,
                    fillColor: ClinicalTheme.surfaceElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: ClinicalTheme.border),
                    ),
                  ),
                  onChanged: (_) {
                    if (_validationError != null) {
                      setState(() => _validationError = null);
                    }
                  },
                ),
                if (_validationError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _validationError!,
                    style: const TextStyle(color: ClinicalTheme.criticalRed, fontSize: 12),
                  ),
                ],
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
              onPressed: () => _submitClosure(ref),
              child: const Text('Confirm Closure'),
            ),
          ],
        );
      },
    );
  }

  String _reasonLabel(ClosureReasonCode reason) {
    switch (reason) {
      case ClosureReasonCode.medicationGiven:
        return 'Medication Given *';
      case ClosureReasonCode.resultReceived:
        return 'Result Received';
      case ClosureReasonCode.doctorReviewed:
        return 'Doctor Reviewed';
      case ClosureReasonCode.actionTaken:
        return 'Action Taken *';
      case ClosureReasonCode.duplicateOrCreatedInError:
        return 'Duplicate / Error';
      case ClosureReasonCode.other:
        return 'Other *';
    }
  }
}

/// Modal dialog strictly implementing PRD FR-50 & FR-53:
/// - Reopening requires an explicit non-empty clinical reason.
class ReopenLoopDialog extends StatefulWidget {
  final LoopStateProjection loop;

  const ReopenLoopDialog({super.key, required this.loop});

  @override
  State<ReopenLoopDialog> createState() => _ReopenLoopDialogState();
}

class _ReopenLoopDialogState extends State<ReopenLoopDialog> {
  final TextEditingController _reasonController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _submitReopen(WidgetRef ref) {
    final text = _reasonController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'A clinical reason is strictly required to reopen a closed loop.');
      return;
    }

    ref.read(wardControllerProvider.notifier).reopenLoop(
          patientId: widget.loop.patientId,
          loopId: widget.loop.loopId,
          reopenReason: text,
        );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        return AlertDialog(
          backgroundColor: ClinicalTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.replay, color: ClinicalTheme.urgentAmber),
              SizedBox(width: 8),
              Text('Reopen Closed Loop', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Previous closure: ${widget.loop.closureReason?.wireName ?? "closed"}',
                style: const TextStyle(color: ClinicalTheme.textMuted, fontSize: 12),
              ),
              if (widget.loop.closureNote != null)
                Text(
                  'Note: "${widget.loop.closureNote}"',
                  style: const TextStyle(color: ClinicalTheme.textSecondary, fontSize: 12),
                ),
              const SizedBox(height: 12),
              const Text(
                'Why is this loop being reopened? (Mandatory)',
                style: TextStyle(color: ClinicalTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g., Symptoms recurred after 2 hours...',
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
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: ClinicalTheme.criticalRed, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: ClinicalTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ClinicalTheme.urgentAmber,
                foregroundColor: Colors.black,
              ),
              onPressed: () => _submitReopen(ref),
              child: const Text('Reopen Loop'),
            ),
          ],
        );
      },
    );
  }
}

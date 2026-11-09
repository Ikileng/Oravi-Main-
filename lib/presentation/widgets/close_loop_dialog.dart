import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/loop_enums.dart';
import '../../domain/projections/projections.dart';
import '../providers/ward_providers.dart';
import '../theme/clinical_theme.dart';

/// Requires a typed closure reason and an explicit resolution outcome.
class CloseLoopDialog extends StatefulWidget {
  final LoopStateProjection loop;

  const CloseLoopDialog({super.key, required this.loop});

  @override
  State<CloseLoopDialog> createState() => _CloseLoopDialogState();
}

class _CloseLoopDialogState extends State<CloseLoopDialog> {
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  ClosureResolutionType _resolutionType = ClosureResolutionType.resolved;
  String? _validationError;
  bool _isSaving = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitClosure(WidgetRef ref) async {
    if (_isSaving) return;
    if (_reasonController.text.trim().isEmpty) {
      setState(() {
        _validationError = 'Enter a reason before closing this medical issue.';
      });
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(wardControllerProvider.notifier)
          .closeLoop(
            patientId: widget.loop.patientId,
            loopId: widget.loop.loopId,
            closureReason: _reasonController.text.trim(),
            resolutionType: _resolutionType,
            freeTextNote: _noteController.text.trim().isNotEmpty
                ? _noteController.text.trim()
                : null,
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _validationError =
              'Could not save the closure. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        return AlertDialog(
          backgroundColor: ClinicalTheme.surface,
          title: Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: ClinicalTheme.successGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Close Medical Issue: ${widget.loop.title}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
                        Icon(
                          Icons.shield_outlined,
                          color: ClinicalTheme.criticalRed,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Critical medical issues require confirmation by the doctor assigned to this patient on the ward board.',
                            style: TextStyle(
                              color: ClinicalTheme.criticalRed,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Text(
                  'Closure reason (required):',
                  style: TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _reasonController,
                  maxLines: 3,
                  style: const TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Describe why this issue is being closed...',
                    hintStyle: const TextStyle(
                      color: ClinicalTheme.textMuted,
                      fontSize: 12,
                    ),
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
                const SizedBox(height: 14),
                const Text(
                  'Outcome (required):',
                  style: TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ClosureResolutionType.values.map((outcome) {
                    final selected = outcome == _resolutionType;
                    return ChoiceChip(
                      label: Text(
                        outcome == ClosureResolutionType.resolved
                            ? 'Resolved'
                            : 'Closed without resolution',
                      ),
                      selected: selected,
                      selectedColor: ClinicalTheme.routineTeal,
                      backgroundColor: ClinicalTheme.surfaceElevated,
                      labelStyle: TextStyle(
                        color: selected
                            ? Colors.white
                            : ClinicalTheme.textSecondary,
                      ),
                      onSelected: (value) {
                        if (value) setState(() => _resolutionType = outcome);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Additional clinical note (optional):',
                  style: TextStyle(
                    color: ClinicalTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  style: const TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Add relevant clinical context...',
                    hintStyle: const TextStyle(
                      color: ClinicalTheme.textMuted,
                      fontSize: 12,
                    ),
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
                    style: const TextStyle(
                      color: ClinicalTheme.criticalRed,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: ClinicalTheme.textMuted),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ClinicalTheme.routineTeal,
                foregroundColor: Colors.white,
              ),
              onPressed: _isSaving ? null : () => _submitClosure(ref),
              child: Text(_isSaving ? 'Saving…' : 'Confirm Closure'),
            ),
          ],
        );
      },
    );
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
  bool _isSaving = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitReopen(WidgetRef ref) async {
    if (_isSaving) return;
    final text = _reasonController.text.trim();
    if (text.isEmpty) {
      setState(
        () => _error =
            'A clinical reason is required to reopen a closed medical issue.',
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(wardControllerProvider.notifier)
          .reopenLoop(
            patientId: widget.loop.patientId,
            loopId: widget.loop.loopId,
            reopenReason: text,
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not reopen the medical issue. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
              Text(
                'Reopen Closed Medical Issue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Previous closure: ${widget.loop.closureReasonText ?? widget.loop.closureReason?.wireName ?? "closed"}',
                style: const TextStyle(
                  color: ClinicalTheme.textMuted,
                  fontSize: 12,
                ),
              ),
              if (widget.loop.closureNote != null)
                Text(
                  'Note: "${widget.loop.closureNote}"',
                  style: const TextStyle(
                    color: ClinicalTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Why is this medical issue being reopened? (Required)',
                style: TextStyle(
                  color: ClinicalTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                style: const TextStyle(
                  color: ClinicalTheme.textPrimary,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g., Symptoms recurred after 2 hours...',
                  hintStyle: const TextStyle(
                    color: ClinicalTheme.textMuted,
                    fontSize: 12,
                  ),
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
                Text(
                  _error!,
                  style: const TextStyle(
                    color: ClinicalTheme.criticalRed,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: ClinicalTheme.textMuted),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ClinicalTheme.urgentAmber,
                foregroundColor: Colors.black,
              ),
              onPressed: _isSaving ? null : () => _submitReopen(ref),
              child: Text(_isSaving ? 'Saving…' : 'Reopen Medical Issue'),
            ),
          ],
        );
      },
    );
  }
}

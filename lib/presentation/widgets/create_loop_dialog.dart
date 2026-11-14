import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/loop_enums.dart';
import '../providers/ward_providers.dart';
import '../theme/clinical_theme.dart';
import 'close_loop_dialog.dart';

enum _RecurrenceChoice { reopen, createLinked }

/// Modal dialog strictly implementing PRD FR-4:
/// - Create a loop in two taps or fewer from a short menu of common templates.
/// - Sensible defaults for type, urgency, and owner.
class CreateLoopDialog extends StatefulWidget {
  final String patientId;
  final String? patientLabel;

  const CreateLoopDialog({
    super.key,
    required this.patientId,
    this.patientLabel,
  });

  @override
  State<CreateLoopDialog> createState() => _CreateLoopDialogState();
}

class _CreateLoopDialogState extends State<CreateLoopDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  LoopType _type = LoopType.taskOrPendingResult;
  LoopUrgency _urgency = LoopUrgency.routine;
  String? _error;
  bool _isSaving = false;

  final List<Map<String, dynamic>> _quickTemplates = [
    {
      'label': 'Fluid Titration',
      'title': 'Titrate IV fluids according to urine output',
      'desc': 'Keep MAP > 65 and urine output > 30ml/hr.',
      'type': LoopType.taskOrPendingResult,
      'urgency': LoopUrgency.routine,
    },
    {
      'label': 'Stat Blood Draw',
      'title': 'STAT: Draw urgent lab test & notify doctor',
      'desc': 'Call lab if results not back in 45 minutes.',
      'type': LoopType.escalation,
      'urgency': LoopUrgency.critical,
    },
    {
      'label': 'Oxygen Weaning',
      'title': 'Wean oxygen therapy as tolerated',
      'desc': 'Maintain SpO2 between 92% - 96%.',
      'type': LoopType.taskOrPendingResult,
      'urgency': LoopUrgency.urgent,
    },
    {
      'label': 'Medication Review',
      'title': 'Consult: Review antibiotic coverage with doctor',
      'desc': 'Day 3 of current antibiotic; check blood cultures.',
      'type': LoopType.consultRequest,
      'urgency': LoopUrgency.routine,
    },
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _applyTemplate(Map<String, dynamic> template) {
    setState(() {
      _titleController.text = template['title'];
      _descController.text = template['desc'];
      _type = template['type'];
      _urgency = template['urgency'];
      _error = null;
    });
  }

  Future<void> _submit(WidgetRef ref) async {
    if (_isSaving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Please enter a title or select a template.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final previousIssue =
          ref
              .read(patientLoopsProvider(widget.patientId))
              .where(
                (issue) =>
                    issue.title.trim().toLowerCase() == title.toLowerCase() &&
                    !issue.isOpen &&
                    issue.closedAt != null &&
                    !issue.closedAt!.isAfter(now) &&
                    now.difference(issue.closedAt!) <=
                        const Duration(hours: 24),
              )
              .toList()
            ..sort((a, b) => b.closedAt!.compareTo(a.closedAt!));
      String? linkedLoopId;
      if (previousIssue.isNotEmpty) {
        final existing = previousIssue.first;
        final choice = await showDialog<_RecurrenceChoice>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Similar issue closed recently'),
            content: const Text(
              'An issue with this exact title was closed within the last 24 hours. Reopen it or create a new linked issue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_RecurrenceChoice.reopen),
                child: const Text('Reopen previous issue'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_RecurrenceChoice.createLinked),
                child: const Text('Create linked issue'),
              ),
            ],
          ),
        );
        if (choice == null || !mounted) return;
        if (choice == _RecurrenceChoice.reopen) {
          final reopened = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => ReopenLoopDialog(loop: existing),
          );
          if (reopened == true && mounted) Navigator.of(context).pop();
          return;
        }
        linkedLoopId = existing.loopId;
      }

      await ref
          .read(wardControllerProvider.notifier)
          .openLoop(
            patientId: widget.patientId,
            title: title,
            description: _descController.text.trim(),
            loopType: _type,
            urgency: _urgency,
            linkedLoopId: linkedLoopId,
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save the medical issue. Please try again.',
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
              Icon(Icons.add_circle_outline, color: ClinicalTheme.routineTeal),
              SizedBox(width: 8),
              Text(
                'Raise Medical Issue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.patientLabel != null) ...[
                  Text(
                    'Patient: ${widget.patientLabel}',
                    style: const TextStyle(
                      color: ClinicalTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Quick Templates (2-Tap Entry):',
                  style: TextStyle(
                    color: ClinicalTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _quickTemplates.map((tpl) {
                    return ActionChip(
                      label: Text(
                        tpl['label'],
                        style: const TextStyle(fontSize: 11),
                      ),
                      backgroundColor: ClinicalTheme.surfaceElevated,
                      onPressed: () => _applyTemplate(tpl),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Issue Title:',
                  style: TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _titleController,
                  style: const TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g., Check wound dressing after surgery',
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
                ),
                const SizedBox(height: 12),
                const Text(
                  'Instructions / Clinical Context:',
                  style: TextStyle(
                    color: ClinicalTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _descController,
                  maxLines: 2,
                  style: const TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Details, thresholds, or doctor instructions...',
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
                ),
                const SizedBox(height: 12),
                const Text(
                  'Urgency Tier:',
                  style: TextStyle(
                    color: ClinicalTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: LoopUrgency.values.map((urg) {
                    final isSel = _urgency == urg;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(
                          urg.wireName.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSel
                                ? Colors.white
                                : ClinicalTheme.urgencyColor(urg),
                          ),
                        ),
                        selected: isSel,
                        selectedColor: ClinicalTheme.urgencyColor(urg),
                        backgroundColor: ClinicalTheme.surfaceElevated,
                        onSelected: (val) {
                          if (val) setState(() => _urgency = urg);
                        },
                      ),
                    );
                  }).toList(),
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
              onPressed: _isSaving ? null : () => _submit(ref),
              child: Text(_isSaving ? 'Saving…' : 'Raise Medical Issue'),
            ),
          ],
        );
      },
    );
  }
}

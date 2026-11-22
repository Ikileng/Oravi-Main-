import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/clinical_ritual_service.dart';
import '../data/ward_board_service.dart';
import '../domain/models/clinical_ritual.dart';
import 'providers/auth_providers.dart';
import 'theme/clinical_theme.dart';

class ClinicalRitualReviewScreen extends ConsumerStatefulWidget {
  final String ritualId;

  const ClinicalRitualReviewScreen({super.key, required this.ritualId});

  @override
  ConsumerState<ClinicalRitualReviewScreen> createState() =>
      _ClinicalRitualReviewScreenState();
}

class _ClinicalRitualReviewScreenState
    extends ConsumerState<ClinicalRitualReviewScreen> {
  ClinicalRitual? _ritual;
  final Map<String, TextEditingController> _sectionControllers = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Timer? _processingRefresh;

  static const _sections = <String, String>{
    'situation': 'Situation',
    'decisions': 'Decisions',
    'actions': 'Actions',
    'owners': 'Owners',
    'follow_up': 'Follow-up',
    'unresolved_questions': 'Unresolved questions',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _processingRefresh?.cancel();
    for (final controller in _sectionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  ClinicalRitualService _service() {
    return ClinicalRitualService(
      WardBoardService(getAccessToken: () => ref.read(authAccessTokenProvider)),
    );
  }

  Future<void> _load() async {
    _processingRefresh?.cancel();
    try {
      final ritual = await _service().get(widget.ritualId);
      if (!mounted) return;
      _setRitual(ritual);
      if (ritual.summary == null && ritual.recordingStatus == 'processing') {
        _processingRefresh = Timer(const Duration(seconds: 10), _load);
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load this ritual.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setRitual(ClinicalRitual ritual) {
    _ritual = ritual;
    final sections = ritual.summary?['sections'];
    for (final entry in _sections.keys) {
      final values = sections is Map ? sections[entry] : null;
      _sectionControllers[entry] ??= TextEditingController();
      _sectionControllers[entry]!.text = values is List
          ? values.join('\n')
          : '';
    }
    setState(() {});
  }

  Map<String, dynamic> _summary() {
    return {
      'ritual_type': _ritual!.ritualType,
      'title': _ritual!.title,
      'sections': {
        for (final entry in _sections.keys)
          entry: _sectionControllers[entry]!.text
              .split('\n')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(),
      },
      'draft_status': 'clinician_reviewed',
    };
  }

  Future<void> _generateDraft() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _setRitual(await _service().generateDraft(widget.ritualId));
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not generate the draft.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _approve() async {
    if (_ritual == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _setRitual(await _service().approve(widget.ritualId, _summary()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clinical Ritual approved and saved.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not approve the ritual.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _print() async {
    try {
      final ritual = _ritual;
      if (ritual == null ||
          ritual.status != 'approved' ||
          ritual.summary == null) {
        return;
      }
      final document = pw.Document();
      final sections = ritual.summary!['sections'] is Map
          ? Map<String, dynamic>.from(ritual.summary!['sections'] as Map)
          : <String, dynamic>{};
      document.addPage(
        pw.MultiPage(
          build: (_) => [
            pw.Text(
              ritual.title,
              style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Clinical ${ritual.ritualType} | Patient ${ritual.patientId ?? ''}',
            ),
            pw.SizedBox(height: 18),
            for (final entry in _sections.entries) ...[
              pw.Text(
                entry.value,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              for (final item in (sections[entry.key] as List? ?? const []))
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8, bottom: 3),
                  child: pw.Text('- $item'),
                ),
              pw.SizedBox(height: 10),
            ],
          ],
        ),
      );
      await Printing.layoutPdf(onLayout: (_) async => document.save());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the print preview.')),
        );
      }
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft_ready':
        return 'Draft ready for review';
      case 'approved':
        return 'Approved and saved';
      case 'processing':
        return 'Preparing transcript';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ritual review')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final ritual = _ritual;
    final canManage =
        ritual?.creatorId == ref.read(authenticatedStaffProvider)?.staffId;
    final editable = ritual?.status == 'draft_ready' && canManage;

    return Scaffold(
      backgroundColor: ClinicalTheme.background,
      appBar: AppBar(title: const Text('Ritual review')),
      body: ritual == null
          ? _RitualLoadError(
              message: _error ?? 'Ritual unavailable.',
              onRetry: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: ClinicalTheme.surfaceAccent,
                      borderRadius: BorderRadius.circular(
                        ClinicalTheme.radiusMedium,
                      ),
                      border: Border.all(
                        color: ClinicalTheme.clinicalBlue.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _RitualMetaBadge(
                              icon: Icons.groups_outlined,
                              label: ritual.ritualType
                                  .replaceAll('_', ' ')
                                  .toUpperCase(),
                              color: ClinicalTheme.clinicalBlue,
                            ),
                            _RitualMetaBadge(
                              icon: ritual.status == 'approved'
                                  ? Icons.verified_outlined
                                  : Icons.rate_review_outlined,
                              label: _statusLabel(ritual.status),
                              color: ritual.status == 'approved'
                                  ? ClinicalTheme.successGreen
                                  : ClinicalTheme.urgentAmber,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          ritual.title,
                          style: const TextStyle(
                            color: ClinicalTheme.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        if (ritual.patientId?.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          const Row(
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 16,
                                color: ClinicalTheme.textSecondary,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Linked to the patient record and visible to authorized care-team members.',
                                  style: TextStyle(
                                    color: ClinicalTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ClinicalTheme.criticalRed.withValues(
                          alpha: 0.08,
                        ),
                        borderRadius: BorderRadius.circular(
                          ClinicalTheme.radiusMedium,
                        ),
                        border: Border.all(
                          color: ClinicalTheme.criticalRed.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: ClinicalTheme.criticalRed,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!)),
                        ],
                      ),
                    ),
                  ],
                  if (ritual.transcript != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: ExpansionTile(
                        leading: const Icon(Icons.article_outlined),
                        title: const Text(
                          'Source transcript',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Original transcription used to prepare this review',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: SelectableText(
                              ritual.transcript!,
                              style: const TextStyle(
                                color: ClinicalTheme.textSecondary,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (ritual.summary == null &&
                      ritual.recordingStatus == 'processing') ...[
                    const SizedBox(height: 20),
                    const _ReviewGuidanceCard(
                      icon: Icons.hourglass_top,
                      title: 'Preparing your summary',
                      message:
                          'Oravi is processing the recording in the background. You can leave this screen and return to Review summaries later.',
                    ),
                  ] else if (ritual.summary == null &&
                      ritual.recordingStatus == 'failed') ...[
                    const SizedBox(height: 20),
                    const _ReviewGuidanceCard(
                      icon: Icons.error_outline,
                      title: 'Transcription could not be completed',
                      message:
                          'No summary is ready. The recording needs to be checked before processing can be retried.',
                    ),
                  ] else if (ritual.summary == null &&
                      ritual.transcript != null &&
                      canManage) ...[
                    const SizedBox(height: 20),
                    const _ReviewGuidanceCard(
                      icon: Icons.auto_awesome_outlined,
                      title: 'Prepare a structured draft',
                      message:
                          'Oravi will organize the transcript into situation, decisions, actions, owners, follow-up, and unresolved questions. You must review it before approval.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      onPressed: _saving ? null : _generateDraft,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(
                        _saving ? 'Preparing draft…' : 'Generate draft summary',
                      ),
                    ),
                  ] else if (ritual.summary == null && !canManage) ...[
                    const SizedBox(height: 20),
                    const _ReviewGuidanceCard(
                      icon: Icons.hourglass_top,
                      title: 'Waiting for the initiator',
                      message:
                          'The ritual initiator is preparing the review summary. It will appear here when ready.',
                    ),
                  ] else if (ritual.summary == null) ...[
                    const SizedBox(height: 20),
                    const _ReviewGuidanceCard(
                      icon: Icons.mic_off_outlined,
                      title: 'No transcript available',
                      message:
                          'This ritual has no audio summary. Recording may have been declined or unavailable.',
                    ),
                  ] else ...[
                    const SizedBox(height: 20),
                    _ReviewGuidanceCard(
                      icon: ritual.status == 'approved'
                          ? Icons.verified_outlined
                          : Icons.fact_check_outlined,
                      title: ritual.status == 'approved'
                          ? 'Approved clinical summary'
                          : 'Review every section before approval',
                      message: ritual.status == 'approved'
                          ? 'This summary is saved to the patient record and is read-only.'
                          : 'Edit the generated draft for clinical accuracy. Approval is the clinician’s responsibility.',
                      color: ritual.status == 'approved'
                          ? ClinicalTheme.successGreen
                          : ClinicalTheme.urgentAmber,
                    ),
                    ..._sections.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          controller: _sectionControllers[entry.key],
                          readOnly: !editable,
                          minLines: 2,
                          maxLines: 7,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(
                            color: ClinicalTheme.textPrimary,
                            fontSize: 14,
                            height: 1.4,
                          ),
                          decoration: InputDecoration(
                            labelText: entry.value,
                            helperText: editable
                                ? 'Use one item per line'
                                : null,
                            alignLabelWithHint: true,
                            prefixIcon: Icon(
                              _sectionIcon(entry.key),
                              color: ClinicalTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (canManage)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: ClinicalTheme.successGreen,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: editable && !_saving ? _approve : null,
                        icon: const Icon(Icons.verified),
                        label: Text(
                          _saving
                              ? 'Saving approved summary…'
                              : 'Approve and save to patient record',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (ritual.status == 'approved') ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: _print,
                        icon: const Icon(Icons.print),
                        label: const Text('Print approved summary'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  IconData _sectionIcon(String section) {
    switch (section) {
      case 'situation':
        return Icons.info_outline;
      case 'decisions':
        return Icons.gavel_outlined;
      case 'actions':
        return Icons.checklist;
      case 'owners':
        return Icons.person_outline;
      case 'follow_up':
        return Icons.update;
      default:
        return Icons.help_outline;
    }
  }
}

class _RitualMetaBadge extends StatelessWidget {
  const _RitualMetaBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(ClinicalTheme.radiusLarge),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _ReviewGuidanceCard extends StatelessWidget {
  const _ReviewGuidanceCard({
    required this.icon,
    required this.title,
    required this.message,
    this.color = ClinicalTheme.clinicalBlue,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(ClinicalTheme.radiusMedium),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: const TextStyle(
                  color: ClinicalTheme.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RitualLoadError extends StatelessWidget {
  const _RitualLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: ClinicalTheme.textSecondary,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

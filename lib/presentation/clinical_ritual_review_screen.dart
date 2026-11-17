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
    try {
      final ritual = await _service().get(widget.ritualId);
      if (!mounted) return;
      _setRitual(ritual);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load this ritual.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setRitual(ClinicalRitual ritual) {
    _ritual = ritual;
    final sections = ritual.summary?['sections'];
    if (sections is Map) {
      for (final entry in _sections.keys) {
        final values = sections[entry];
        _sectionControllers[entry] ??= TextEditingController();
        _sectionControllers[entry]!.text = values is List
            ? values.join('\n')
            : '';
      }
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final ritual = _ritual;
    final canManage =
        ritual?.creatorId == ref.read(authenticatedStaffProvider)?.staffId;
    final editable = ritual?.status == 'draft_ready' && canManage;
    return Scaffold(
      backgroundColor: ClinicalTheme.background,
      appBar: AppBar(title: const Text('Clinical Ritual review')),
      body: ritual == null
          ? Center(child: Text(_error ?? 'Ritual unavailable.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  ritual.title,
                  style: const TextStyle(
                    color: ClinicalTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${ritual.ritualType.toUpperCase()} • ${ritual.status}',
                  style: const TextStyle(color: ClinicalTheme.textSecondary),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: ClinicalTheme.criticalRed),
                  ),
                ],
                if (ritual.transcript != null) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Source transcript',
                    style: TextStyle(
                      color: ClinicalTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    ritual.transcript!,
                    style: const TextStyle(color: ClinicalTheme.textSecondary),
                  ),
                ],
                if (ritual.summary == null &&
                    ritual.transcript != null &&
                    canManage)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _generateDraft,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Generate draft summary'),
                    ),
                  )
                else if (ritual.summary == null && !canManage)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Text(
                      'The initiator is preparing the review summary.',
                    ),
                  )
                else if (ritual.summary == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Text(
                      'No transcript is available. If recording was declined, this ritual has no audio summary.',
                    ),
                  )
                else ...[
                  const SizedBox(height: 20),
                  Text(
                    ritual.status == 'approved'
                        ? 'Approved summary'
                        : 'AI draft — review before approval',
                    style: TextStyle(
                      color: ritual.status == 'approved'
                          ? ClinicalTheme.routineTeal
                          : ClinicalTheme.urgentAmber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ..._sections.entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextField(
                        controller: _sectionControllers[entry.key],
                        readOnly: !editable,
                        minLines: 1,
                        maxLines: 5,
                        style: const TextStyle(
                          color: ClinicalTheme.textPrimary,
                        ),
                        decoration: InputDecoration(
                          labelText: entry.value,
                          labelStyle: const TextStyle(
                            color: ClinicalTheme.textSecondary,
                          ),
                          filled: true,
                          fillColor: ClinicalTheme.surfaceElevated,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (canManage)
                    FilledButton.icon(
                      onPressed: editable && !_saving ? _approve : null,
                      icon: const Icon(Icons.verified),
                      label: const Text(
                        'Save approved summary to patient record',
                      ),
                    ),
                  if (ritual.status == 'approved')
                    OutlinedButton.icon(
                      onPressed: _print,
                      icon: const Icon(Icons.print),
                      label: const Text('Print approved summary'),
                    ),
                ],
              ],
            ),
    );
  }
}

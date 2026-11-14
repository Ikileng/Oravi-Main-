import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final ritual = _ritual;
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
                if (ritual.summary == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _generateDraft,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Generate draft summary'),
                    ),
                  )
                else ...[
                  const SizedBox(height: 20),
                  const Text(
                    'AI draft — review before approval',
                    style: TextStyle(
                      color: ClinicalTheme.urgentAmber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ..._sections.entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextField(
                        controller: _sectionControllers[entry.key],
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
                  FilledButton.icon(
                    onPressed: _saving ? null : _approve,
                    icon: const Icon(Icons.verified),
                    label: const Text('Approve and save to record'),
                  ),
                ],
              ],
            ),
    );
  }
}

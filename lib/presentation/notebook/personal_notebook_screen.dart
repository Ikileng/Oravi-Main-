import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/clinical_ritual_service.dart';
import '../../domain/models/clinical_ritual.dart';
import '../clinical_ritual_review_screen.dart';
import '../providers/auth_providers.dart';
import '../providers/whiteboard_providers.dart';
import '../providers/ward_providers.dart';
import '../theme/clinical_theme.dart';

class PersonalEntry {
  final String id, body, kind;
  final bool completed;
  final DateTime createdAt;
  final DateTime? reminderAt, completedAt;
  const PersonalEntry({
    required this.id,
    required this.body,
    required this.kind,
    required this.completed,
    required this.createdAt,
    this.reminderAt,
    this.completedAt,
  });
  factory PersonalEntry.fromMap(Map<String, dynamic> m) => PersonalEntry(
    id: m['id'] as String,
    body: m['body'] as String,
    kind: m['kind'] as String,
    completed: m['completed'] == 1 || m['completed'] == true,
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    reminderAt: DateTime.tryParse(m['reminder_at'] as String? ?? '')?.toLocal(),
    completedAt: DateTime.tryParse(
      m['completed_at'] as String? ?? '',
    )?.toLocal(),
  );
  Map<String, dynamic> get payload => {
    'body': body,
    'kind': kind,
    'completed': completed,
    'reminder_at': reminderAt?.toUtc().toIso8601String(),
  };
}

final personalNotebookProvider =
    FutureProvider.autoDispose<List<PersonalEntry>>((ref) async {
      final staff = ref.watch(authenticatedStaffProvider);
      ref.watch(authAccessTokenProvider);
      if (staff?.isClinical != true) return [];
      final result = await ref
          .watch(wardBoardServiceProvider)
          .communicationRequest('GET', '/notebook');
      return (result as List)
          .map(
            (e) => PersonalEntry.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    });

final clinicalRitualReviewProvider =
    FutureProvider.autoDispose<List<ClinicalRitual>>((ref) async {
      final staff = ref.watch(authenticatedStaffProvider);
      ref.watch(authAccessTokenProvider);
      if (staff?.isClinical != true) return const [];
      final rituals = await ClinicalRitualService(
        ref.watch(wardBoardServiceProvider),
      ).list();
      return rituals
          .where(
            (ritual) =>
                ritual.status == 'draft_ready' ||
                ritual.status == 'approved' ||
                (ritual.status == 'ended' &&
                    ritual.recordingStatus != 'declined'),
          )
          .toList();
    });

final pendingPersonalTasksProvider = Provider.autoDispose<int>((ref) {
  final personal = (ref.watch(personalNotebookProvider).asData?.value ?? [])
      .where((e) => e.kind == 'task' && !e.completed)
      .length;
  final reviews = (ref.watch(clinicalRitualReviewProvider).asData?.value ?? [])
      .where((ritual) => ritual.status != 'approved')
      .length;
  return personal + reviews;
});

String entryDate(BuildContext context, DateTime date) =>
    '${MaterialLocalizations.of(context).formatMediumDate(date)} · ${TimeOfDay.fromDateTime(date).format(context)}';

/// Foreground-only reminder. The saved due time survives logout and app closure.
class NotebookReminderBanner extends ConsumerStatefulWidget {
  const NotebookReminderBanner({super.key});
  @override
  ConsumerState<NotebookReminderBanner> createState() =>
      _NotebookReminderBannerState();
}

class _NotebookReminderBannerState
    extends ConsumerState<NotebookReminderBanner> {
  Timer? _clock;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) setState(() {});
      if (mounted && timer.tick.isEven) {
        ref.invalidate(personalNotebookProvider);
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _respond(PersonalEntry entry, String action) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(wardBoardServiceProvider)
          .communicationRequest(
            'PUT',
            '/notebook/${entry.id}',
            payload: {
              ...entry.payload,
              'completed': action == 'done',
              'reminder_at': action == 'snooze'
                  ? DateTime.now()
                        .add(const Duration(minutes: 15))
                        .toUtc()
                        .toIso8601String()
                  : null,
            },
          );
      ref.invalidate(personalNotebookProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save reminder. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(personalNotebookProvider).asData?.value ?? [];
    final due =
        entries
            .where(
              (entry) =>
                  !entry.completed &&
                  entry.reminderAt != null &&
                  !entry.reminderAt!.isAfter(DateTime.now()),
            )
            .toList()
          ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
    if (due.isEmpty) return const SizedBox.shrink();
    final entry = due.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        color: ClinicalTheme.urgentAmber.withValues(alpha: 0.09),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ClinicalTheme.radiusMedium),
          side: BorderSide(
            color: ClinicalTheme.urgentAmber.withValues(alpha: 0.6),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    color: ClinicalTheme.urgentAmber,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A gentle reminder',
                      style: TextStyle(
                        color: ClinicalTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                entry.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 6),
              Text(
                'Planned for ${entryDate(context, entry.reminderAt!)}',
                style: const TextStyle(
                  color: ClinicalTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => _respond(
                            entry,
                            entry.kind == 'task' ? 'done' : 'dismiss',
                          ),
                    icon: Icon(
                      entry.kind == 'task'
                          ? Icons.check
                          : Icons.notifications_off_outlined,
                    ),
                    label: Text(
                      entry.kind == 'task' ? 'Mark done' : 'Dismiss reminder',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _respond(entry, 'snooze'),
                    icon: const Icon(Icons.snooze),
                    label: const Text('Snooze 15 min'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PersonalNotebookScreen extends ConsumerStatefulWidget {
  const PersonalNotebookScreen({super.key});
  @override
  ConsumerState<PersonalNotebookScreen> createState() =>
      _PersonalNotebookScreenState();
}

class _PersonalNotebookScreenState
    extends ConsumerState<PersonalNotebookScreen> {
  int _filter = 0;
  final Set<String> _saving = {};

  Future<void> _save(PersonalEntry entry, Map<String, dynamic> payload) async {
    if (_saving.contains(entry.id)) return;
    setState(() => _saving.add(entry.id));
    try {
      await ref
          .read(wardBoardServiceProvider)
          .communicationRequest(
            'PUT',
            '/notebook/${entry.id}',
            payload: payload,
          );
      ref.invalidate(personalNotebookProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save changes. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(entry.id));
    }
  }

  Future<void> _delete(PersonalEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'It will be removed from your notebook and history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(wardBoardServiceProvider)
          .communicationRequest('DELETE', '/notebook/${entry.id}');
      ref.invalidate(personalNotebookProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete entry.')),
        );
      }
    }
  }

  Future<void> _edit([PersonalEntry? entry]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _EntryEditor(entry: entry),
    );
  }

  Future<void> _openRitual(ClinicalRitual ritual) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClinicalRitualReviewScreen(ritualId: ritual.ritualId),
      ),
    );
    ref.invalidate(clinicalRitualReviewProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authenticatedStaffProvider)?.isClinical != true) {
      return const Scaffold(
        body: Center(child: Text('Clinician sign-in required.')),
      );
    }
    final notebook = ref.watch(personalNotebookProvider);
    final entries = notebook.asData?.value ?? const <PersonalEntry>[];
    final pendingCount = entries
        .where((entry) => entry.kind == 'task' && !entry.completed)
        .length;
    final noteCount = entries.where((entry) => entry.kind == 'note').length;
    final completedCount = entries
        .where((entry) => entry.kind == 'task' && entry.completed)
        .length;
    final rituals = ref.watch(clinicalRitualReviewProvider);
    final patientInitialsById = {
      for (final patient in ref.watch(wardPatientsProvider))
        patient.patientId: patient.patientInitials,
    };
    final ritualEntries = rituals.asData?.value ?? const <ClinicalRitual>[];
    final reviewCount = ritualEntries
        .where((ritual) => ritual.status != 'approved')
        .length;
    final filterCounts = [pendingCount, noteCount, completedCount, reviewCount];

    return Scaffold(
      appBar: AppBar(
        title: Text(_filter == 3 ? 'Review summaries' : 'Tasks'),
        actions: [
          IconButton(
            tooltip: 'Refresh notebook',
            onPressed: () => ref.invalidate(personalNotebookProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: _filter == 3
                  ? _ClinicalReviewIntro(reviewCount: reviewCount)
                  : const _NotebookIntro(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < 4; i++)
                    ChoiceChip(
                      selectedColor: i == 3
                          ? ClinicalTheme.urgentAmber.withValues(alpha: 0.22)
                          : null,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i == 3) ...[
                            const Icon(Icons.fact_check_outlined, size: 16),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            [
                              'Pending',
                              'Notes',
                              'Completed',
                              'Review summaries',
                            ][i],
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _filter == i
                                  ? ClinicalTheme.clinicalBlue.withValues(
                                      alpha: 0.18,
                                    )
                                  : ClinicalTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('${filterCounts[i]}'),
                          ),
                        ],
                      ),
                      selected: _filter == i,
                      onSelected: (_) => setState(() => _filter = i),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_filter != 3) const NotebookReminderBanner(),
            Expanded(
              child: _filter == 3
                  ? _buildClinicalReviewList(
                      rituals,
                      patientInitialsById: patientInitialsById,
                    )
                  : notebook.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_off_outlined,
                                color: ClinicalTheme.textSecondary,
                                size: 36,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Cannot load your notebook. Check your connection.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              FilledButton.tonal(
                                onPressed: () =>
                                    ref.invalidate(personalNotebookProvider),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      data: (entries) {
                        final visible = entries
                            .where(
                              (entry) => _filter == 1
                                  ? entry.kind == 'note'
                                  : entry.kind == 'task' &&
                                        entry.completed == (_filter == 2),
                            )
                            .toList();
                        if (visible.isEmpty) {
                          return _NotebookEmptyState(
                            icon: [
                              Icons.task_alt,
                              Icons.sticky_note_2_outlined,
                              Icons.history,
                            ][_filter],
                            title: [
                              'No pending tasks.',
                              'No notes yet.',
                              'No completed tasks yet.',
                            ][_filter],
                            message: [
                              'Add a task for anything you need to follow up during this shift.',
                              'Capture a private note you want to remember later.',
                              'Completed tasks will remain here as your personal history.',
                            ][_filter],
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final entry = visible[index];
                            final isTask = entry.kind == 'task';
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color:
                                                (entry.completed
                                                        ? ClinicalTheme
                                                              .successGreen
                                                        : isTask
                                                        ? ClinicalTheme
                                                              .clinicalBlue
                                                        : ClinicalTheme
                                                              .inChargePurple)
                                                    .withValues(alpha: 0.14),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Icon(
                                            entry.completed
                                                ? Icons.check
                                                : isTask
                                                ? Icons.checklist
                                                : Icons.sticky_note_2_outlined,
                                            color: entry.completed
                                                ? ClinicalTheme.successGreen
                                                : isTask
                                                ? ClinicalTheme.clinicalBlue
                                                : ClinicalTheme.inChargePurple,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entry.body,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      height: 1.35,
                                                      decoration:
                                                          entry.completed
                                                          ? TextDecoration
                                                                .lineThrough
                                                          : null,
                                                    ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Added ${entryDate(context, entry.createdAt)}',
                                                style: const TextStyle(
                                                  color: ClinicalTheme
                                                      .textSecondary,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (entry.completedAt != null ||
                                        entry.reminderAt != null) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (entry.completedAt != null)
                                            _EntryMetaChip(
                                              icon: Icons.task_alt,
                                              label:
                                                  'Completed ${entryDate(context, entry.completedAt!)}',
                                              color: ClinicalTheme.successGreen,
                                            ),
                                          if (entry.reminderAt != null)
                                            _EntryMetaChip(
                                              icon: Icons.notifications_none,
                                              label:
                                                  'Reminder ${entryDate(context, entry.reminderAt!)}',
                                              color: ClinicalTheme.urgentAmber,
                                            ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: [
                                        if (isTask)
                                          FilledButton.tonalIcon(
                                            onPressed:
                                                _saving.contains(entry.id)
                                                ? null
                                                : () => _save(entry, {
                                                    ...entry.payload,
                                                    'completed':
                                                        !entry.completed,
                                                    'reminder_at': null,
                                                  }),
                                            icon: Icon(
                                              entry.completed
                                                  ? Icons.undo
                                                  : Icons.check,
                                            ),
                                            label: Text(
                                              entry.completed
                                                  ? 'Reopen'
                                                  : 'Mark done',
                                            ),
                                          ),
                                        TextButton.icon(
                                          onPressed: _saving.contains(entry.id)
                                              ? null
                                              : () => _edit(entry),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: const Text('Edit'),
                                        ),
                                        TextButton.icon(
                                          onPressed: _saving.contains(entry.id)
                                              ? null
                                              : () => _delete(entry),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          label: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClinicalReviewList(
    AsyncValue<List<ClinicalRitual>> rituals, {
    required Map<String, String> patientInitialsById,
  }) => rituals.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (_, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: ClinicalTheme.textSecondary,
              size: 36,
            ),
            const SizedBox(height: 12),
            const Text(
              'Clinical reviews could not be loaded. Check your connection.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => ref.invalidate(clinicalRitualReviewProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
    data: (items) {
      if (items.isEmpty) {
        return const _NotebookEmptyState(
          icon: Icons.fact_check_outlined,
          title: 'No clinical reviews yet.',
          message:
              'Recorded briefs and debriefs will appear here when they need review or have been approved.',
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final ritual = items[index];
          final needsReview = ritual.status != 'approved';
          final status = _ritualStatusLabel(ritual);
          final patientInitials = ritual.patientId == null
              ? null
              : patientInitialsById[ritual.patientId!];
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openRitual(ritual),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color:
                            (needsReview
                                    ? ClinicalTheme.urgentAmber
                                    : ClinicalTheme.successGreen)
                                .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        needsReview
                            ? Icons.fact_check_outlined
                            : Icons.verified_outlined,
                        color: needsReview
                            ? ClinicalTheme.urgentAmber
                            : ClinicalTheme.successGreen,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ritual.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${ritual.ritualType.toUpperCase()} · $status',
                            style: const TextStyle(
                              color: ClinicalTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          if (ritual.patientId?.isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              patientInitials?.isNotEmpty == true
                                  ? 'Patient $patientInitials'
                                  : 'Patient initials unavailable',
                              style: const TextStyle(
                                color: ClinicalTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            needsReview
                                ? 'Open to review, edit, and approve.'
                                : 'Approved and saved to the patient record.',
                            style: const TextStyle(
                              color: ClinicalTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  String _ritualStatusLabel(ClinicalRitual ritual) {
    if (ritual.status == 'draft_ready') return 'Draft ready for review';
    if (ritual.status == 'approved') return 'Approved';
    switch (ritual.recordingStatus) {
      case 'processing':
        return 'Processing transcript';
      case 'transcribed':
        return 'Transcript ready';
      case 'failed':
        return 'Processing failed';
      default:
        return ritual.status.replaceAll('_', ' ');
    }
  }
}

class _NotebookIntro extends StatelessWidget {
  const _NotebookIntro();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ClinicalTheme.surfaceAccent,
      borderRadius: BorderRadius.circular(ClinicalTheme.radiusMedium),
      border: Border.all(
        color: ClinicalTheme.clinicalBlue.withValues(alpha: 0.35),
      ),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline, color: ClinicalTheme.clinicalBlue),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your private clinical workspace',
                style: TextStyle(
                  color: ClinicalTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Keep personal tasks and notes together. Reminders are optional and stay with your account.',
                style: TextStyle(
                  color: ClinicalTheme.textSecondary,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ClinicalReviewIntro extends StatelessWidget {
  const _ClinicalReviewIntro({required this.reviewCount});

  final int reviewCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ClinicalTheme.surfaceAccent,
      borderRadius: BorderRadius.circular(ClinicalTheme.radiusMedium),
      border: Border.all(
        color: ClinicalTheme.urgentAmber.withValues(alpha: 0.45),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.fact_check_outlined, color: ClinicalTheme.urgentAmber),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Patient-linked summaries',
                style: TextStyle(
                  color: ClinicalTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                reviewCount == 0
                    ? 'Generated briefs and debriefs will appear here for review.'
                    : '$reviewCount ${reviewCount == 1 ? 'summary needs' : 'summaries need'} your attention or are still processing.',
                style: const TextStyle(
                  color: ClinicalTheme.textSecondary,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _NotebookEmptyState extends StatelessWidget {
  const _NotebookEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: ClinicalTheme.textMuted),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ClinicalTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );
}

class _EntryMetaChip extends StatelessWidget {
  const _EntryMetaChip({
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
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

class _EntryEditor extends ConsumerStatefulWidget {
  final PersonalEntry? entry;
  const _EntryEditor({this.entry});
  @override
  ConsumerState<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends ConsumerState<_EntryEditor> {
  late final TextEditingController _body;
  late final String _id;
  late String _kind;
  DateTime? _reminder;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _body = TextEditingController(text: widget.entry?.body ?? '');
    _id = widget.entry?.id ?? const Uuid().v4();
    _kind = widget.entry?.kind ?? 'task';
    _reminder = widget.entry?.reminderAt;
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final initial = _reminder != null && _reminder!.isAfter(now)
        ? _reminder!
        : now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (!value.isAfter(DateTime.now())) {
        _error = 'Choose a future reminder time.';
      } else {
        _reminder = value;
        _error = null;
      }
    });
  }

  Future<void> _submit() async {
    if (_body.text.trim().isEmpty) {
      setState(() => _error = 'Write a note or task first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(wardBoardServiceProvider)
          .communicationRequest(
            'PUT',
            '/notebook/$_id',
            payload: {
              'body': _body.text.trim(),
              'kind': _kind,
              'completed':
                  _kind == 'task' && (widget.entry?.completed ?? false),
              'reminder_at': _reminder?.toUtc().toIso8601String(),
            },
          );
      ref.invalidate(personalNotebookProvider);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save. Check your connection and try again. Your text is still here.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.entry == null ? 'Add to my notebook' : 'Edit entry'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final kind in ['task', 'note'])
                    ChoiceChip(
                      label: Text(kind == 'task' ? 'Task' : 'Note'),
                      selected: _kind == kind,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _kind = kind),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                enabled: !_saving,
                minLines: 3,
                maxLines: 8,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _kind == 'task' ? 'Task details' : 'Note',
                  hintText: _kind == 'task'
                      ? 'What needs to be followed up?'
                      : 'What would you like to remember?',
                  alignLabelWithHint: true,
                ),
              ),
              if (widget.entry?.completed != true) ...[
                TextButton.icon(
                  onPressed: _saving ? null : _pickReminder,
                  icon: const Icon(Icons.notifications_none),
                  label: Text(
                    _reminder == null
                        ? 'Add reminder (optional)'
                        : entryDate(context, _reminder!),
                  ),
                ),
                if (_reminder != null)
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _reminder = null),
                    child: const Text('Remove reminder'),
                  ),
                const Text(
                  'Reminders appear in Oravi while you use your dashboard or notebook. Due reminders remain here when you return.',
                ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );
}

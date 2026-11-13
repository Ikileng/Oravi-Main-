import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../providers/auth_providers.dart';
import '../providers/whiteboard_providers.dart';

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

final pendingPersonalTasksProvider = Provider.autoDispose<int>(
  (ref) => (ref.watch(personalNotebookProvider).asData?.value ?? [])
      .where((e) => e.kind == 'task' && !e.completed)
      .length,
);

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
              (e) =>
                  !e.completed &&
                  e.reminderAt != null &&
                  !e.reminderAt!.isAfter(DateTime.now()),
            )
            .toList()
          ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
    if (due.isEmpty) return const SizedBox.shrink();
    final entry = due.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A gentle reminder',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(entry.body, maxLines: 3, overflow: TextOverflow.ellipsis),
            Text('Planned for ${entryDate(context, entry.reminderAt!)}'),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _respond(
                          entry,
                          entry.kind == 'task' ? 'done' : 'dismiss',
                        ),
                  child: Text(
                    entry.kind == 'task' ? 'Mark done' : 'Dismiss reminder',
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _respond(entry, 'snooze'),
                  child: const Text('Snooze 15 min'),
                ),
              ],
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authenticatedStaffProvider)?.isClinical != true) {
      return const Scaffold(
        body: Center(child: Text('Clinician sign-in required.')),
      );
    }
    final notebook = ref.watch(personalNotebookProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My notebook'),
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
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Your personal notes and tasks. Reminders are optional.',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < 3; i++)
                ChoiceChip(
                  label: Text(['Pending', 'Notes', 'Completed'][i]),
                  selected: _filter == i,
                  onSelected: (_) => setState(() => _filter = i),
                ),
            ],
          ),
          const NotebookReminderBanner(),
          Expanded(
            child: notebook.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Cannot load your notebook. Check your connection.',
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(personalNotebookProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (entries) {
                final visible = entries
                    .where(
                      (e) => _filter == 1
                          ? e.kind == 'note'
                          : e.kind == 'task' && e.completed == (_filter == 2),
                    )
                    .toList();
                if (visible.isEmpty) {
                  return Center(
                    child: Text(
                      [
                        'No pending tasks.',
                        'No notes yet.',
                        'No completed tasks yet.',
                      ][_filter],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final e = visible[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.body,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text('Added ${entryDate(context, e.createdAt)}'),
                            if (e.completedAt != null)
                              Text(
                                'Completed ${entryDate(context, e.completedAt!)}',
                              ),
                            if (e.reminderAt != null)
                              Text(
                                'Reminder ${entryDate(context, e.reminderAt!)}',
                              ),
                            Wrap(
                              children: [
                                if (e.kind == 'task')
                                  TextButton.icon(
                                    onPressed: _saving.contains(e.id)
                                        ? null
                                        : () => _save(e, {
                                            ...e.payload,
                                            'completed': !e.completed,
                                            'reminder_at': null,
                                          }),
                                    icon: Icon(
                                      e.completed ? Icons.undo : Icons.check,
                                    ),
                                    label: Text(
                                      e.completed ? 'Reopen' : 'Mark done',
                                    ),
                                  ),
                                TextButton(
                                  onPressed: _saving.contains(e.id)
                                      ? null
                                      : () => _edit(e),
                                  child: const Text('Edit'),
                                ),
                                TextButton(
                                  onPressed: _saving.contains(e.id)
                                      ? null
                                      : () => _delete(e),
                                  child: const Text('Delete'),
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
    );
  }
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
              TextField(
                controller: _body,
                enabled: !_saving,
                minLines: 3,
                maxLines: 8,
                maxLength: 4000,
                decoration: const InputDecoration(
                  hintText: 'What would you like to remember?',
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

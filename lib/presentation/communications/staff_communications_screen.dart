import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/clinical_ritual_service.dart';
import '../../domain/models/clinical_ritual.dart';
import '../../domain/models/call_session.dart';
import '../../domain/models/staff_profile.dart';
import '../clinical_ritual_review_screen.dart';
import '../clinical_ritual_room_screen.dart';
import '../call_screen.dart';
import '../providers/auth_providers.dart';
import '../providers/whiteboard_providers.dart';
import 'personal_inbox.dart';

final staffInboxProvider = FutureProvider<List<List<dynamic>>>((ref) async {
  final staff = ref.watch(authenticatedStaffProvider);
  ref.watch(authAccessTokenProvider);
  if (staff == null || (!staff.isClinical && !staff.isSupport)) return [[], []];
  final api = ref.read(wardBoardServiceProvider);
  return Future.wait([
    api.communicationRequest('GET', '/direct/threads').then((v) => v as List),
    api.communicationRequest('GET', '/direct/calls').then((v) => v as List),
  ]);
});

final clinicalRitualHistoryProvider =
    FutureProvider.autoDispose<List<ClinicalRitual>>((ref) async {
      final staff = ref.watch(authenticatedStaffProvider);
      final token = ref.watch(authAccessTokenProvider);
      if (staff?.isClinical != true || token == null) return const [];
      return ClinicalRitualService(ref.read(wardBoardServiceProvider)).list();
    });

final recentActivitySearchProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      query,
    ) async {
      final staff = ref.watch(authenticatedStaffProvider);
      final token = ref.watch(authAccessTokenProvider);
      if (staff == null || token == null) return const [];
      final uri = Uri(queryParameters: {'q': query, 'limit': '100'});
      final response = await ref
          .read(wardBoardServiceProvider)
          .communicationRequest('GET', '/inbox/activities?${uri.query}');
      final result = Map<String, dynamic>.from(response as Map);
      return (result['items'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    });

Future<void> startStaffCall(
  BuildContext context,
  WidgetRef ref,
  String staffId,
) async {
  try {
    final api = ref.read(wardBoardServiceProvider);
    final result = await api.communicationRequest(
      'POST',
      '/direct/calls',
      payload: {'recipient_id': staffId},
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          session: CallSession.fromMap(
            Map<String, dynamic>.from(result as Map),
          ),
          api: api,
        ),
      ),
    );
    ref.invalidate(staffInboxProvider);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().contains('reachable Oravi device') ||
                    error.toString().contains('could not be notified')
                ? 'This clinician is offline or has no reachable Oravi device right now.'
                : 'Could not start the call. Check your connection and try again.',
          ),
        ),
      );
    }
  }
}

class StaffCommunicationsScreen extends ConsumerStatefulWidget {
  const StaffCommunicationsScreen({super.key});
  @override
  ConsumerState<StaffCommunicationsScreen> createState() =>
      _StaffCommunicationsScreenState();
}

class _StaffCommunicationsScreenState
    extends ConsumerState<StaffCommunicationsScreen> {
  Timer? _refresh;
  Timer? _searchDebounce;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(
      const Duration(seconds: 5),
      (_) => ref.invalidate(staffInboxProvider),
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _answer(String callId) async {
    try {
      final api = ref.read(wardBoardServiceProvider);
      final session = await api.acceptCall(callId);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(session: session, api: api),
        ),
      );
      ref.invalidate(staffInboxProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not answer: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(authenticatedStaffProvider);
    if (staff == null || (!staff.isClinical && !staff.isSupport)) {
      return const Scaffold(
        body: Center(child: Text('Staff sign-in required.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages & calls'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(staffInboxProvider);
              ref.invalidate(personalInboxProvider);
              ref.invalidate(clinicalRitualHistoryProvider);
              if (_searchQuery.isNotEmpty) {
                ref.invalidate(recentActivitySearchProvider(_searchQuery));
              }
            },
          ),
          if (staff.isSupport)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () {
                ref.read(authControllerProvider.notifier).logout();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) setState(() => _searchQuery = value.trim());
                });
              },
              decoration: InputDecoration(
                hintText: 'Search messages, calls, and briefs',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchDebounce?.cancel();
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _searchQuery.isNotEmpty
                ? _buildSearchResults()
                : ref
                      .watch(staffInboxProvider)
                      .when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) => Center(
                          child: Text('Could not load communications: $error'),
                        ),
                        data: (inbox) => ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Text(
                              '${staff.name} · ${staff.formattedRole}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 20),
                            const ReceivedInbox(),
                            Text(
                              'Direct conversations',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (inbox[0].isEmpty)
                              const ListTile(title: Text('No messages yet')),
                            for (final thread in inbox[0])
                              ListTile(
                                leading: const Icon(Icons.chat_bubble_outline),
                                title: Text(
                                  thread['contact']['name'] as String,
                                ),
                                subtitle: Text(
                                  thread['last_message'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing:
                                    (thread['unread_count'] as int? ?? 0) > 0
                                    ? Badge(
                                        label: Text(
                                          '${thread['unread_count']}',
                                        ),
                                        child: const Icon(
                                          Icons.mark_chat_unread_outlined,
                                        ),
                                      )
                                    : null,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => StaffChatScreen(
                                      staffId:
                                          thread['contact']['staff_id']
                                              as String,
                                      name: thread['contact']['name'] as String,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 20),
                            Text(
                              'Calls',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (inbox[1].isEmpty)
                              const ListTile(title: Text('No calls yet')),
                            for (final call in inbox[1])
                              ListTile(
                                leading: Icon(
                                  call['recipient_id'] == staff.staffId
                                      ? Icons.call_received
                                      : Icons.call_made,
                                ),
                                title: Text(call['name'] as String),
                                subtitle: Text(call['status'] as String),
                                trailing:
                                    call['status'] == 'ringing' &&
                                        call['recipient_id'] == staff.staffId
                                    ? Wrap(
                                        children: [
                                          IconButton(
                                            tooltip: 'Answer',
                                            icon: const Icon(Icons.call),
                                            onPressed: () => _answer(
                                              call['call_id'] as String,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Decline',
                                            icon: const Icon(Icons.call_end),
                                            onPressed: () async {
                                              try {
                                                await ref
                                                    .read(
                                                      wardBoardServiceProvider,
                                                    )
                                                    .declineCall(
                                                      call['call_id'] as String,
                                                    );
                                                ref.invalidate(
                                                  staffInboxProvider,
                                                );
                                              } catch (error) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text('$error'),
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            _buildBriefsSection(context, staff),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildBriefsSection(BuildContext context, StaffProfile staff) {
    if (!staff.isClinical) return const SizedBox.shrink();
    return Consumer(
      builder: (context, ref, _) => ref
          .watch(clinicalRitualHistoryProvider)
          .when(
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
            error: (_, _) => const ListTile(
              title: Text('Brief history could not be loaded.'),
            ),
            data: (rituals) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text('Briefs', style: Theme.of(context).textTheme.titleLarge),
                if (rituals.isEmpty)
                  const ListTile(title: Text('No brief activity yet')),
                for (final ritual in rituals)
                  ListTile(
                    leading: const Icon(Icons.groups_2_outlined),
                    title: Text(ritual.title),
                    subtitle: Text(
                      '${ritual.ritualType.toUpperCase()} · ${ritual.status}',
                    ),
                    onTap: () => _openRitual(context, ref, ritual.ritualId),
                  ),
                const Divider(),
              ],
            ),
          ),
    );
  }

  Widget _buildSearchResults() => ref
      .watch(recentActivitySearchProvider(_searchQuery))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Activity search is unavailable. Please retry.'),
        ),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No matching activity found.'))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    leading: Icon(switch (item['kind']) {
                      'message' => Icons.chat_bubble_outline,
                      'call' => Icons.call,
                      _ => Icons.groups_2_outlined,
                    }),
                    title: Text(
                      item['title'] as String? ?? 'Activity',
                      style: TextStyle(
                        fontWeight: item['unread'] == true
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      '${item['kind']} · ${item['body'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: item['unread'] == true
                        ? const Icon(Icons.circle, size: 9, color: Colors.blue)
                        : null,
                    onTap: () => _openActivity(context, item),
                  );
                },
              ),
      );

  Future<void> _openActivity(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    if (item['kind'] == 'message') {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => StaffChatScreen(
            staffId: item['staff_id'] as String,
            name: item['title'] as String,
          ),
        ),
      );
      return;
    }
    if (item['kind'] == 'brief') {
      await _openRitual(context, ref, item['ritual_id'] as String);
      return;
    }
    if (item['kind'] == 'call' &&
        item['status'] == 'ringing' &&
        item['direction'] == 'received') {
      await _answer(item['call_id'] as String);
      return;
    }
    if (item['unread'] == true && item['id'] is String) {
      await markInboxRead(ref, [item['id'] as String]);
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item['title'] as String? ?? 'Call activity'),
        content: Text('${item['body'] ?? ''}\n${item['created_at'] ?? ''}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openRitual(
    BuildContext context,
    WidgetRef ref,
    String ritualId,
  ) async {
    try {
      final ritual = await ClinicalRitualService(
        ref.read(wardBoardServiceProvider),
      ).get(ritualId);
      if (!context.mounted) return;
      if (ritual.status == 'draft_ready' || ritual.status == 'approved') {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ClinicalRitualReviewScreen(ritualId: ritualId),
          ),
        );
      } else if (ritual.status == 'requested' ||
          ritual.status == 'in_progress') {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ClinicalRitualRoomScreen(
              ritualId: ritualId,
              invitation: ritual.participantStatus == 'invited',
            ),
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(ritual.title),
            content: Text('This ritual has ${ritual.status}.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open brief activity: $error')),
        );
      }
    }
  }
}

class StaffChatScreen extends ConsumerStatefulWidget {
  final String staffId;
  final String name;
  const StaffChatScreen({super.key, required this.staffId, required this.name});
  @override
  ConsumerState<StaffChatScreen> createState() => _StaffChatScreenState();
}

class _StaffChatScreenState extends ConsumerState<StaffChatScreen> {
  final _text = TextEditingController();
  List<dynamic> _messages = [];
  Timer? _refresh;
  String? _error;
  String? _pendingId;
  String? _pendingBody;
  bool _sending = false;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _text.dispose();
    super.dispose();
  }

  String get _path => '/direct/threads/${Uri.encodeComponent(widget.staffId)}';
  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final result = await ref
          .read(wardBoardServiceProvider)
          .communicationRequest('GET', _path);
      if (mounted) {
        setState(() {
          _messages = result as List;
          _error = null;
        });
        final incoming = _messages
            .where(
              (m) =>
                  m['recipient_id'] ==
                  ref.read(authenticatedStaffProvider)?.staffId,
            )
            .map((m) => 'message:${m['id']}')
            .toList();
        await markInboxRead(ref, incoming);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _loading = false;
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    if (_pendingBody != body) {
      _pendingId = const Uuid().v4();
      _pendingBody = body;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(wardBoardServiceProvider)
          .communicationRequest(
            'POST',
            _path,
            payload: {'body': body, 'client_id': _pendingId},
          );
      if (!mounted) return;
      _text.clear();
      _pendingId = null;
      _pendingBody = null;
      ref.invalidate(staffInboxProvider);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = 'Message not sent. Retry: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(authenticatedStaffProvider);
    if (staff == null || (!staff.isClinical && !staff.isSupport)) {
      return const Scaffold(
        body: Center(child: Text('Staff sign-in required.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            tooltip: 'Call',
            icon: const Icon(Icons.call),
            onPressed: () => startStaffCall(context, ref, widget.staffId),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[_messages.length - 1 - index];
                  final mine = message['sender_id'] == staff.staffId;
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(message['body'] as String),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: !_sending,
                      maxLength: 4000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

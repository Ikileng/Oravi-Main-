import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/call_session.dart';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start call: $error')));
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
      body: ref
          .watch(staffInboxProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('Could not load communications: $error')),
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
                    title: Text(thread['contact']['name'] as String),
                    subtitle: Text(
                      thread['last_message'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => StaffChatScreen(
                          staffId: thread['contact']['staff_id'] as String,
                          name: thread['contact']['name'] as String,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Text('Calls', style: Theme.of(context).textTheme.titleLarge),
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
                                onPressed: () =>
                                    _answer(call['call_id'] as String),
                              ),
                              IconButton(
                                tooltip: 'Decline',
                                icon: const Icon(Icons.call_end),
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(wardBoardServiceProvider)
                                        .declineCall(call['call_id'] as String);
                                    ref.invalidate(staffInboxProvider);
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text('$error')),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          )
                        : null,
                  ),
              ],
            ),
          ),
    );
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

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
import '../theme/clinical_theme.dart';
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
            error.toString().contains('server notification credentials')
                ? 'Oravi server notification setup needs attention. Contact the administrator.'
                : error.toString().contains('turned availability off')
                ? 'This clinician has turned availability off. You can leave a message in their inbox.'
                : error.toString().contains('reachable Oravi device') ||
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
      backgroundColor: ClinicalTheme.canvas,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Messages & calls'),
            SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 11,
                  color: ClinicalTheme.textSecondary,
                ),
                SizedBox(width: 4),
                Text(
                  'Secure communication',
                  style: TextStyle(
                    color: ClinicalTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh communications',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshCommunications,
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
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () {
                      if (mounted) setState(() => _searchQuery = value.trim());
                    },
                  );
                },
                decoration: InputDecoration(
                  hintText: 'Search people, patients, messages',
                  prefixIcon: const Icon(Icons.search_rounded),
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
                ),
              ),
            ),
            Expanded(
              child: _searchQuery.isNotEmpty
                  ? _buildSearchResults()
                  : RefreshIndicator(
                      onRefresh: () async {
                        _refreshCommunications();
                        await ref.read(staffInboxProvider.future);
                      },
                      child: ref
                          .watch(staffInboxProvider)
                          .when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (_, _) => ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                _CommunicationStateCard(
                                  icon: Icons.cloud_off_outlined,
                                  title: 'Communications are unavailable',
                                  message:
                                      'Check your connection and try again.',
                                  onRetry: _refreshCommunications,
                                ),
                              ],
                            ),
                            data: (inbox) => ListView(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                              children: [
                                _SignedInContext(staff: staff),
                                const SizedBox(height: 18),
                                const ReceivedInbox(),
                                const SizedBox(height: 22),
                                _CommunicationSectionHeader(
                                  title: 'Direct conversations',
                                  count: inbox[0].length,
                                ),
                                const SizedBox(height: 10),
                                if (inbox[0].isEmpty)
                                  const _CommunicationStateCard(
                                    icon: Icons.forum_outlined,
                                    title: 'No messages yet',
                                    message:
                                        'Your direct conversations will appear here.',
                                  )
                                else
                                  _CommunicationGroup(
                                    children: [
                                      for (final thread in inbox[0])
                                        _DirectConversationTile(
                                          thread: Map<String, dynamic>.from(
                                            thread as Map,
                                          ),
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute<void>(
                                              builder: (_) => StaffChatScreen(
                                                staffId:
                                                    thread['contact']['staff_id']
                                                        as String,
                                                name:
                                                    thread['contact']['name']
                                                        as String,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                const SizedBox(height: 22),
                                _CommunicationSectionHeader(
                                  title: 'Calls',
                                  count: inbox[1].length,
                                ),
                                const SizedBox(height: 10),
                                if (inbox[1].isEmpty)
                                  const _CommunicationStateCard(
                                    icon: Icons.phone_in_talk_outlined,
                                    title: 'No calls yet',
                                    message:
                                        'Recent Oravi calls will appear here.',
                                  )
                                else
                                  _CommunicationGroup(
                                    children: [
                                      for (final call in inbox[1])
                                        _CallActivityTile(
                                          call: Map<String, dynamic>.from(
                                            call as Map,
                                          ),
                                          currentStaffId: staff.staffId,
                                          onAnswer: () => _answer(
                                            call['call_id'] as String,
                                          ),
                                          onDecline: () async {
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
                                            } catch (_) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Could not decline the call. Try again.',
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                _buildBriefsSection(context, staff),
                              ],
                            ),
                          ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _refreshCommunications() {
    ref.invalidate(staffInboxProvider);
    ref.invalidate(personalInboxProvider);
    ref.invalidate(clinicalRitualHistoryProvider);
    if (_searchQuery.isNotEmpty) {
      ref.invalidate(recentActivitySearchProvider(_searchQuery));
    }
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

class _SignedInContext extends StatelessWidget {
  const _SignedInContext({required this.staff});
  final StaffProfile staff;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ClinicalTheme.surfaceAccent,
      borderRadius: BorderRadius.circular(ClinicalTheme.radiusMedium),
      border: Border.all(
        color: ClinicalTheme.clinicalBlue.withValues(alpha: 0.25),
      ),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: ClinicalTheme.clinicalBlue.withValues(alpha: 0.15),
          child: Text(
            staff.initials,
            style: const TextStyle(
              color: ClinicalTheme.clinicalBlue,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                staff.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                staff.formattedRole,
                style: const TextStyle(
                  color: ClinicalTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const Row(
          children: [
            Icon(Icons.circle, size: 8, color: ClinicalTheme.successGreen),
            SizedBox(width: 5),
            Text(
              'Available',
              style: TextStyle(
                color: ClinicalTheme.successGreen,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _CommunicationSectionHeader extends StatelessWidget {
  const _CommunicationSectionHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      Text(
        '$count',
        style: const TextStyle(
          color: ClinicalTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _CommunicationGroup extends StatelessWidget {
  const _CommunicationGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: ClinicalTheme.surface,
      borderRadius: BorderRadius.circular(ClinicalTheme.radiusLarge),
      border: Border.all(color: ClinicalTheme.border),
    ),
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1)
            const Divider(height: 1, indent: 68),
        ],
      ],
    ),
  );
}

class _DirectConversationTile extends StatelessWidget {
  const _DirectConversationTile({required this.thread, required this.onTap});
  final Map<String, dynamic> thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final contact = Map<String, dynamic>.from(thread['contact'] as Map);
    final name = contact['name'] as String? ?? 'Clinician';
    final unread = thread['unread_count'] as int? ?? 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _ClinicianAvatar(name: name, role: contact['role'] as String?),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: unread > 0
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  if (contact['role'] != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${contact['role']}',
                      style: const TextStyle(
                        color: ClinicalTheme.clinicalBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    thread['last_message'] as String? ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ClinicalTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (unread > 0)
              Container(
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: ClinicalTheme.clinicalBlue,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              const Icon(Icons.chevron_right, color: ClinicalTheme.textMuted),
          ],
        ),
      ),
    );
  }
}

class _CallActivityTile extends StatelessWidget {
  const _CallActivityTile({
    required this.call,
    required this.currentStaffId,
    required this.onAnswer,
    required this.onDecline,
  });
  final Map<String, dynamic> call;
  final String currentStaffId;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final incoming = call['recipient_id'] == currentStaffId;
    final ringing = call['status'] == 'ringing' && incoming;
    final missed = call['status'] == 'missed';
    final color = missed
        ? ClinicalTheme.criticalRed
        : ClinicalTheme.successGreen;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              incoming ? Icons.call_received_rounded : Icons.call_made_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  call['name'] as String? ?? 'Oravi call',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${call['status'] ?? 'completed'}',
                  style: TextStyle(
                    color: missed ? color : ClinicalTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (ringing) ...[
            IconButton(
              tooltip: 'Decline',
              onPressed: onDecline,
              icon: const Icon(
                Icons.call_end,
                color: ClinicalTheme.criticalRed,
              ),
            ),
            IconButton(
              tooltip: 'Answer',
              onPressed: onAnswer,
              icon: const Icon(Icons.call, color: ClinicalTheme.successGreen),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClinicianAvatar extends StatelessWidget {
  const _ClinicianAvatar({required this.name, this.role});
  final String name;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase();
    final color = ClinicalTheme.cadreColor('${role ?? ''} $name');
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(
        initials.isEmpty ? 'CL' : initials,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CommunicationStateCard extends StatelessWidget {
  const _CommunicationStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: ClinicalTheme.surfaceSoft,
      borderRadius: BorderRadius.circular(ClinicalTheme.radiusLarge),
      border: Border.all(color: ClinicalTheme.border),
    ),
    child: Column(
      children: [
        Icon(icon, color: ClinicalTheme.textSecondary, size: 26),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ClinicalTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ],
    ),
  );
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
      backgroundColor: ClinicalTheme.canvas,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            _ClinicianAvatar(name: widget.name),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Secure direct message',
                    style: TextStyle(
                      color: ClinicalTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Call',
            icon: const Icon(Icons.call_outlined),
            onPressed: () => startStaffCall(context, ref, widget.staffId),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              color: ClinicalTheme.surfaceAccent,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 13,
                    color: ClinicalTheme.clinicalBlue,
                  ),
                  SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Keep patient identifiers within approved clinical threads',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ClinicalTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                color: ClinicalTheme.criticalRed.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 17,
                      color: ClinicalTheme.criticalRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: ClinicalTheme.criticalRed,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Retry',
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 18),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _messages.isEmpty && !_loading
                  ? const Center(
                      child: _CommunicationStateCard(
                        icon: Icons.chat_bubble_outline,
                        title: 'Start the conversation',
                        message:
                            'Messages sent here are for clinical coordination.',
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = Map<String, dynamic>.from(
                          _messages[_messages.length - 1 - index] as Map,
                        );
                        final mine = message['sender_id'] == staff.staffId;
                        return _ClinicalMessageBubble(
                          message: message,
                          mine: mine,
                        );
                      },
                    ),
            ),
            if (_sending) const LinearProgressIndicator(minHeight: 2),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
              decoration: const BoxDecoration(
                color: ClinicalTheme.surface,
                border: Border(top: BorderSide(color: ClinicalTheme.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: !_sending,
                      maxLength: 4000,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Secure message',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded, size: 19),
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

class _ClinicalMessageBubble extends StatelessWidget {
  const _ClinicalMessageBubble({required this.message, required this.mine});
  final Map<String, dynamic> message;
  final bool mine;

  @override
  Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 310),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 7),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFF176B87) : ClinicalTheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
        border: mine ? null : Border.all(color: ClinicalTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              message['body'] as String? ?? '',
              style: const TextStyle(
                color: ClinicalTheme.textPrimary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _communicationTime(message['created_at']),
            style: TextStyle(
              color: mine ? Colors.white70 : ClinicalTheme.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    ),
  );
}

String _communicationTime(Object? raw) {
  final value = raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
  if (value == null) return '';
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${value.hour < 12 ? 'AM' : 'PM'}';
}

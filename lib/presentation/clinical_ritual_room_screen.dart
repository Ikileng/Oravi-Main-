import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../data/clinical_ritual_service.dart';
import '../data/ward_board_service.dart';
import 'providers/auth_providers.dart';
import 'theme/clinical_theme.dart';

class ClinicalRitualRoomScreen extends ConsumerStatefulWidget {
  final String ritualId;
  final bool invitation;

  const ClinicalRitualRoomScreen({
    super.key,
    required this.ritualId,
    this.invitation = false,
  });

  @override
  ConsumerState<ClinicalRitualRoomScreen> createState() =>
      _ClinicalRitualRoomScreenState();
}

class _ClinicalRitualRoomScreenState
    extends ConsumerState<ClinicalRitualRoomScreen> {
  late final Room _room;
  ClinicalRitualService? _service;
  bool _connecting = true;
  bool _muted = false;
  bool _leaving = false;
  bool _recording = false;
  String? _error;
  Timer? _participantTimer;
  int _participantCount = 1;
  bool _initiator = false;
  bool _consented = false;
  String? _recordingMessage;
  String _patientId = '';
  String _ritualTitle = 'Clinical ritual';
  String _ritualType = 'ritual';
  final Set<String> _participantIds = {};

  @override
  void initState() {
    super.initState();
    _room = Room(
      roomOptions: const RoomOptions(adaptiveStream: false, dynacast: false),
    );
    unawaited(_connect());
  }

  ClinicalRitualService _getService() {
    return _service ??= ClinicalRitualService(
      WardBoardService(getAccessToken: () => ref.read(authAccessTokenProvider)),
    );
  }

  Future<void> _connect() async {
    try {
      final service = _getService();
      final ritual = await service.get(widget.ritualId);
      _recording = ritual.recordingStatus == 'recording';
      if (ritual.recordingStatus == 'declined') {
        _recordingMessage = 'The initiator chose not to record this meeting';
      }
      _patientId = ritual.patientId ?? '';
      _ritualTitle = ritual.title;
      _ritualType = ritual.ritualType;
      _participantIds.addAll(
        ritual.participants.map((p) => p['staff_id'] as String),
      );
      final staff = ref.read(authenticatedStaffProvider);
      _initiator = ritual.creatorId == staff?.staffId;
      if (widget.invitation && !_initiator) {
        final accept = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Join clinical ritual?'),
            content: Text(
              'You are invited to “${ritual.title}”. Accepting grants access to this meeting only; it does not sign you into any other Oravi session.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Accept and join'),
              ),
            ],
          ),
        );
        if (accept != true) {
          if (mounted) Navigator.pop(context);
          return;
        }
        await service.acceptInvitation(widget.ritualId);
      }
      if (_initiator) {
        final consent = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.record_voice_over, size: 42),
            title: const Text('Allow transcription?'),
            content: const Text(
              'Oravi will record this meeting on its server, transcribe it, and prepare a summary for your review. No meeting file is uploaded from your device. Choose No to meet without recording or transcription.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No, do not record'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes, start transcription'),
              ),
            ],
          ),
        );
        _consented = consent == true;
      }
      final session = await _getService().getRoomSession(widget.ritualId);
      await _room.connect(session.liveKitUrl, session.token);
      var recordingActive = _recording;
      if (_initiator) {
        try {
          final recording = await service.startRecording(
            widget.ritualId,
            consent: _consented,
          );
          recordingActive = recording.recordingStatus == 'recording';
          if (!recordingActive) {
            _recordingMessage = 'Meeting is not being recorded';
          }
        } catch (_) {
          _recordingMessage =
              'Recording could not start. The meeting can continue without transcription.';
        }
      }
      await _room.localParticipant!.setMicrophoneEnabled(true);
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _recording = recordingActive;
      });
      _participantTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!mounted) return;
        setState(() => _participantCount = _room.remoteParticipants.length + 1);
      });
    } catch (error) {
      await _room.disconnect();
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = 'Could not join the ritual room (${error.runtimeType}).';
      });
    }
  }

  Future<void> _toggleMute() async {
    final nextMuted = !_muted;
    await _room.localParticipant?.setMicrophoneEnabled(!nextMuted);
    if (mounted) setState(() => _muted = nextMuted);
  }

  Future<void> _leave() async {
    if (_leaving) return;
    if (mounted) {
      setState(() => _leaving = true);
    } else {
      _leaving = true;
    }
    _participantTimer?.cancel();
    try {
      await _room.disconnect();
      if (_initiator) await _getService().end(widget.ritualId);
    } catch (_) {
      // The room is already disconnected; the webhook remains authoritative.
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _inviteClinician() async {
    final query = TextEditingController();
    var search = _getService().searchStaff(_patientId, '');
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          title: const Text('Add a clinician'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: query,
                  decoration: const InputDecoration(
                    labelText: 'Search registered clinicians',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setDialogState(() {
                    search = _getService().searchStaff(_patientId, value);
                  }),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 280,
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: search,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final people = snapshot.data!
                          .where(
                            (person) =>
                                person['staff_id'] !=
                                    ref
                                        .read(authenticatedStaffProvider)
                                        ?.staffId &&
                                !_participantIds.contains(person['staff_id']),
                          )
                          .toList();
                      if (people.isEmpty) {
                        return const Center(
                          child: Text('No clinicians found.'),
                        );
                      }
                      return ListView(
                        children: [
                          for (final person in people)
                            ListTile(
                              title: Text(person['name'] as String),
                              subtitle: Text(person['role'] as String),
                              trailing: person['care_team'] == true
                                  ? const Chip(label: Text('Care team'))
                                  : const Icon(Icons.person_add_alt_1),
                              onTap: () async {
                                try {
                                  await _getService().addParticipant(
                                    widget.ritualId,
                                    person['staff_id'] as String,
                                  );
                                  _participantIds.add(
                                    person['staff_id'] as String,
                                  );
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(
                                      this.context,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text('Invitation sent.'),
                                      ),
                                    );
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Could not invite this clinician.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    query.dispose();
  }

  @override
  void dispose() {
    _participantTimer?.cancel();
    unawaited(_room.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roomReady = !_connecting && _error == null;
    final recordingColor = _recording
        ? ClinicalTheme.criticalRed
        : ClinicalTheme.textSecondary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: ClinicalTheme.background,
        appBar: AppBar(title: const Text('Clinical ritual')),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
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
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: ClinicalTheme.clinicalBlue.withValues(
                                  alpha: 0.14,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.groups_outlined,
                                color: ClinicalTheme.clinicalBlue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _ritualTitle,
                                    style: const TextStyle(
                                      color: ClinicalTheme.textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _ritualType
                                        .replaceAll('_', ' ')
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      color: ClinicalTheme.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 28),
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 54,
                            backgroundColor: ClinicalTheme.routineTeal
                                .withValues(alpha: 0.16),
                            child: const Icon(
                              Icons.groups,
                              size: 52,
                              color: ClinicalTheme.routineTeal,
                            ),
                          ),
                          if (roomReady)
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: ClinicalTheme.successGreen,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: ClinicalTheme.background,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.black,
                                size: 17,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _error ??
                            (_connecting
                                ? 'Joining secure room…'
                                : '$_participantCount clinician${_participantCount == 1 ? '' : 's'} connected'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _error == null
                              ? ClinicalTheme.textPrimary
                              : ClinicalTheme.criticalRed,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _connecting
                            ? 'Verifying access and preparing encrypted audio.'
                            : _error != null
                            ? 'Leave the room and try joining again when your connection is stable.'
                            : 'Only invited clinicians can enter this room.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: ClinicalTheme.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      if (roomReady) ...[
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: recordingColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(
                              ClinicalTheme.radiusMedium,
                            ),
                            border: Border.all(
                              color: recordingColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _recording
                                    ? Icons.fiber_manual_record
                                    : Icons.voicemail_outlined,
                                size: 20,
                                color: recordingColor,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _recording
                                          ? 'Recording and transcription active'
                                          : 'Not being recorded',
                                      style: TextStyle(
                                        color: recordingColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _recording
                                          ? 'A draft summary will be prepared for clinician review after the ritual.'
                                          : (_recordingMessage ??
                                                (_initiator
                                                    ? 'You chose to continue without recording.'
                                                    : 'Recording preference is controlled by the initiator.')),
                                      style: const TextStyle(
                                        color: ClinicalTheme.textSecondary,
                                        fontSize: 12,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      const SizedBox(height: 28),
                      if (roomReady)
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 20,
                          runSpacing: 16,
                          children: [
                            _RitualControl(
                              icon: _muted ? Icons.mic_off : Icons.mic,
                              label: _muted ? 'Unmute' : 'Mute',
                              active: _muted,
                              onPressed: _toggleMute,
                            ),
                            if (_initiator)
                              _RitualControl(
                                icon: Icons.person_add_alt_1,
                                label: 'Add clinician',
                                onPressed: _inviteClinician,
                              ),
                          ],
                        )
                      else
                        const SizedBox(height: 84),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _leaving ? null : _leave,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            backgroundColor: ClinicalTheme.criticalRed,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.call_end),
                          label: Text(
                            _leaving
                                ? 'Leaving…'
                                : _initiator
                                ? 'End ritual for everyone'
                                : 'Leave ritual',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RitualControl extends StatelessWidget {
  const _RitualControl({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      IconButton.filled(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(64, 64),
          backgroundColor: active
              ? ClinicalTheme.criticalRed
              : ClinicalTheme.surfaceElevated,
          foregroundColor: Colors.white,
        ),
        icon: Icon(icon, size: 27),
        tooltip: label,
      ),
      const SizedBox(height: 7),
      Text(
        label,
        style: const TextStyle(
          color: ClinicalTheme.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

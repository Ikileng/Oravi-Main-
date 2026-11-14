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

  const ClinicalRitualRoomScreen({super.key, required this.ritualId});

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
      final session = await _getService().getRoomSession(widget.ritualId);
      await _room.connect(session.liveKitUrl, session.token);
      await _room.localParticipant!.setMicrophoneEnabled(true);
      final ritual = await _getService().startRecording(widget.ritualId);
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _recording = ritual.recordingStatus == 'recording';
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
    _leaving = true;
    _participantTimer?.cancel();
    try {
      await _room.disconnect();
      await _getService().stopRecording(widget.ritualId);
    } catch (_) {
      // The room is already disconnected; the webhook remains authoritative.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _participantTimer?.cancel();
    unawaited(_room.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: ClinicalTheme.background,
        appBar: AppBar(title: const Text('Clinical Ritual')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 42,
                  backgroundColor: ClinicalTheme.routineTeal,
                  child: Icon(Icons.groups, size: 42, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(
                  _error ??
                      (_connecting
                          ? 'Joining the secure ritual room…'
                          : '$_participantCount clinician${_participantCount == 1 ? '' : 's'} connected'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _error == null
                        ? ClinicalTheme.textSecondary
                        : ClinicalTheme.criticalRed,
                  ),
                ),
                if (!_connecting && _error == null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _recording ? 'Server recording active' : 'Recording unavailable',
                    style: TextStyle(
                      color: _recording
                          ? ClinicalTheme.urgentAmber
                          : ClinicalTheme.criticalRed,
                    ),
                  ),
                  const SizedBox(height: 28),
                  IconButton.filled(
                    onPressed: _toggleMute,
                    icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                    tooltip: _muted ? 'Unmute' : 'Mute',
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _leaving ? null : _leave,
                  style: FilledButton.styleFrom(
                    backgroundColor: ClinicalTheme.criticalRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                  ),
                  icon: const Icon(Icons.call_end),
                  label: const Text('Leave ritual'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

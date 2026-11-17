import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../domain/models/call_session.dart';
import '../data/ward_board_service.dart';
import 'theme/clinical_theme.dart';

class CallScreen extends StatefulWidget {
  final CallSession session;
  final WardBoardService api;

  const CallScreen({super.key, required this.session, required this.api});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final Room _room;
  Timer? _durationTimer;
  Timer? _statusTimer;
  bool _checkingStatus = false;
  bool _ending = false;
  DateTime? _connectedAt;
  String? _error;
  bool _connecting = true;
  bool _muted = false;
  int _durationSeconds = 0;
  late String _callStatus;

  @override
  void initState() {
    super.initState();
    _callStatus = widget.session.status;
    _room = Room(
      roomOptions: const RoomOptions(adaptiveStream: false, dynacast: false),
    );
    unawaited(_connect());
    _statusTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkStatus(),
    );
  }

  Future<void> _checkStatus() async {
    if (_checkingStatus || _ending) return;
    _checkingStatus = true;
    try {
      final call = await widget.api.getCall(widget.session.callId);
      final status = call['status'] as String? ?? _callStatus;
      if (mounted && status != _callStatus) {
        setState(() => _callStatus = status);
        if (status == 'answered') _startDurationClock();
      }
      if (mounted &&
          const {
            'ended',
            'declined',
            'cancelled',
            'missed',
          }.contains(call['status'])) {
        await _end();
      }
    } catch (_) {
      // Keep connected audio usable through transient API outages.
    } finally {
      _checkingStatus = false;
    }
  }

  Future<void> _connect() async {
    try {
      await _room.connect(widget.session.liveKitUrl, widget.session.token);
      await _room.localParticipant!.setMicrophoneEnabled(true);
      if (!mounted) return;
      setState(() {
        _connecting = false;
      });
      if (_callStatus == 'answered') _startDurationClock();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = 'Could not connect the call (${error.runtimeType}).';
      });
    }
  }

  void _startDurationClock() {
    if (_connectedAt != null) return;
    _connectedAt = DateTime.now();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedAt == null) return;
      setState(() => _durationSeconds = DateTime.now().difference(_connectedAt!).inSeconds);
    });
  }

  Future<void> _end() async {
    if (_ending) return;
    _ending = true;
    _statusTimer?.cancel();
    _durationTimer?.cancel();
    await _room.disconnect();
    try {
      await widget.api.endCall(widget.session.callId);
    } catch (_) {
      // The local call is already ended. The event/outcome remains recoverable.
    }
    if (mounted) Navigator.of(context).pop(_callStatus == 'answered' ? _durationSeconds : null);
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _durationTimer?.cancel();
    unawaited(_room.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otherParty = widget.session.isIncoming
        ? widget.session.callerName
        : widget.session.recipientName;
    return Scaffold(
      backgroundColor: ClinicalTheme.background,
      appBar: AppBar(title: const Text('Oravi call')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius: 42,
                backgroundColor: ClinicalTheme.routineTeal,
                child: Icon(Icons.person, size: 42, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                otherParty,
                style: const TextStyle(
                  color: ClinicalTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error ??
                    (_connecting
                        ? 'Connecting securely…'
                        : _callStatus == 'ringing'
                        ? 'Calling • waiting for the clinician to answer. If they are offline or do not answer, this call will be marked missed.'
                        : 'Connected • ${_durationSeconds}s'),
                style: TextStyle(
                  color: _error == null
                      ? ClinicalTheme.textSecondary
                      : ClinicalTheme.criticalRed,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_error == null && !_connecting)
                IconButton.filled(
                  onPressed: () async {
                    final nextMuted = !_muted;
                    await _room.localParticipant!.setMicrophoneEnabled(
                      !nextMuted,
                    );
                    if (mounted) setState(() => _muted = nextMuted);
                  },
                  icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                  tooltip: _muted ? 'Unmute' : 'Mute',
                ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _end,
                style: FilledButton.styleFrom(
                  backgroundColor: ClinicalTheme.criticalRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.call_end),
                label: const Text('End call'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
